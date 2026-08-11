/*
 * hmos-openvpn M1: 首页（T5）
 * T5.1 VPN 开关（startVpnExtensionAbility/stop）— 已完成
 * T5.2 模式切换（loadConfig is-patch 下发 mode 字段）
 * T5.3 实时流量图（queryTrafficNow 1Hz 轮询 + 差分，Canvas 绘制）
 * T5.4 当前代理卡（queryProxyGroups 取 GLOBAL 组 now）
 * T5.5 IP 信息卡（api.ipify.org，超时 5s 显示 "--"）
 */
import { common, Want } from '@kit.AbilityKit';
import { vpnExtension } from '@kit.NetworkKit';
import { http } from '@kit.NetworkKit';
import { ThemeColors } from '../model/Theme';
import { AppService } from '../service/AppService';
import { BackgroundKeepAliveService } from '../service/BackgroundKeepAliveService';
import { SocketProxyService, UpdateConfigParams, ClashConfig, ProxyMode,
  ProxyGroup, Traffic } from 'proxy_core';
import { promptAction } from '@kit.ArkUI';

@Component
export struct HomePage {
  @Consume colors: ThemeColors;
  @State vpnOn: boolean = false;
  @State vpnState: string = '';
  @State mode: string = ProxyMode.Rule;
  @State currentProxy: string = '--';
  @State ipInfo: string = '';
  @State downRate: number = 0;
  @State upRate: number = 0;
  @State downTotal: string = '0 B';
  @State upTotal: string = '0 B';
  private appService: AppService = AppService.getInstance();
  private trafficTimer: number = -1;
  private prevDown: number = 0;
  private prevUp: number = 0;

  aboutToAppear(): void {
    this.vpnState = 'vpn_disconnected';
  }

  aboutToDisappear(): void {
    this.stopTrafficPoll();
  }

  async toggleVpn(isOn: boolean): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const vpnWant: Want = {
        deviceId: '',
        bundleName: context.abilityInfo.bundleName,
        abilityName: 'ClashVpnAbility',
        parameters: { requestId: Date.now() }
      };
      if (isOn) {
        this.vpnState = 'vpn_requesting';
        await vpnExtension.startVpnExtensionAbility(vpnWant);
        this.vpnState = 'vpn_connected';
        this.startTrafficPoll();
        this.refreshMode();
        this.refreshCurrentProxy();
        // T7.3a 后台保活（长时任务+常驻通知）
        BackgroundKeepAliveService.getInstance().start(context);
      } else {
        await vpnExtension.stopVpnExtensionAbility(vpnWant);
        this.vpnState = 'vpn_disconnected';
        this.stopTrafficPoll();
        BackgroundKeepAliveService.getInstance().stop(context);
      }
    } catch (e) {
      const msg: string = (e instanceof Error) ? e.message : String(e);
      this.vpnState = msg;
      this.vpnOn = !isOn; // 回滚
      console.error('M1', 'toggleVpn failed: ' + msg);
    }
  }

  // T5.2 模式切换（patch 下发）
  async setMode(mode: string): Promise<void> {
    const svc: SocketProxyService | undefined = this.appService.getProxyService();
    if (!svc) return;
    try {
      const activeId = await this.appService.getActiveProfileId();
      if (activeId === '') {
        promptAction.showToast({ message: '请先在订阅页激活一个订阅' });
        return;
      }
      const cfg = new ClashConfig();
      cfg.mode = mode as ProxyMode;
      const params: UpdateConfigParams = {
        'profile-id': activeId,
        config: cfg,
        params: {
          'is-patch': true,
          'is-compatible': false,
          'selected-map': {},
          'override-dns': false,
          'test-url': 'http://www.gstatic.com/generate_204'
        }
      };
      await svc.loadConfig(params);
      this.mode = mode;
    } catch (e) {
      const msg: string = (e instanceof Error) ? e.message : String(e);
      promptAction.showToast({ message: '模式切换失败: ' + msg });
    }
  }

  // T5.4 当前代理
  async refreshCurrentProxy(): Promise<void> {
    const svc: SocketProxyService | undefined = this.appService.getProxyService();
    if (!svc) return;
    try {
      const groups = await svc.queryProxyGroups(ProxyMode.Global);
      const g = groups.find((x: ProxyGroup) => x.name === 'GLOBAL');
      if (g) {
        this.currentProxy = g.now;
      }
    } catch (e) {
      const msg: string = (e instanceof Error) ? e.message : String(e);
      console.error('T5', 'refreshCurrentProxy: ' + msg);
    }
  }

  async refreshMode(): Promise<void> {
    // 从代理组推断当前模式（Rule 组存在=Rule 模式）
    const svc: SocketProxyService | undefined = this.appService.getProxyService();
    if (!svc) return;
    try {
      const groups = await svc.queryProxyGroups(ProxyMode.Rule);
      if (groups.length > 0) {
        this.mode = ProxyMode.Rule;
      }
    } catch (e) {
      console.error('T5', 'refreshMode: ' + String(e));
    }
  }

  // T5.3 流量轮询（1Hz 差分）
  startTrafficPoll(): void {
    this.prevDown = 0;
    this.prevUp = 0;
    this.trafficTimer = setInterval(() => {
      this.pollTraffic();
    }, 1000);
  }

  stopTrafficPoll(): void {
    if (this.trafficTimer !== -1) {
      clearInterval(this.trafficTimer);
      this.trafficTimer = -1;
    }
  }

  async pollTraffic(): Promise<void> {
    const svc: SocketProxyService | undefined = this.appService.getProxyService();
    if (!svc) return;
    try {
      const t: Traffic = await svc.queryTrafficNow(true);
      const down: number = t.downRaw ?? 0;
      const up: number = t.upRaw ?? 0;
      // 差分得每秒速率
      if (this.prevDown > 0) {
        this.downRate = Math.max(0, down - this.prevDown);
        this.upRate = Math.max(0, up - this.prevUp);
      }
      this.prevDown = down;
      this.prevUp = up;
      this.downTotal = this.formatBytes(down);
      this.upTotal = this.formatBytes(up);
    } catch (e) {
      console.error('T5', 'pollTraffic: ' + String(e));
    }
  }

  // T5.5 IP 信息（直连查询，本地出口）
  async refreshIpInfo(): Promise<void> {
    try {
      const httpRequest = http.createHttp();
      const resp = await httpRequest.request('https://api.ipify.org?format=json', {
        connectTimeout: 5000,
        readTimeout: 5000
      });
      const json = JSON.parse(resp.result as string) as Record<string, string>;
      this.ipInfo = json['ip'] ?? '--';
      httpRequest.destroy();
    } catch (e) {
      this.ipInfo = '--';
      console.error('T5', 'refreshIpInfo: ' + String(e));
    }
  }

  // T8.1 连通性测试：经代理请求 generate_204，测 E2E 耗时
  @State testResult: string = '';
  async testConnectivity(): Promise<void> {
    this.testResult = '测试中...';
    const t0 = Date.now();
    try {
      const httpRequest = http.createHttp();
      const resp = await httpRequest.request('https://www.gstatic.com/generate_204', {
        connectTimeout: 10000,
        readTimeout: 10000,
        usingCache: false
      });
      const elapsed = Date.now() - t0;
      const code = resp.responseCode;
      this.testResult = '204 测试: HTTP ' + code + '，耗时 ' + elapsed + 'ms ' +
        (code === 204 || code === 200 ? '✅' : '⚠️');
      httpRequest.destroy();
    } catch (e) {
      const elapsed = Date.now() - t0;
      const msg: string = (e instanceof Error) ? e.message : String(e);
      this.testResult = '204 测试失败 (' + elapsed + 'ms): ' + msg;
    }
  }

  formatBytes(bytes: number): string {
    if (bytes >= 1024 * 1024 * 1024) return (bytes / (1024 * 1024 * 1024)).toFixed(2) + ' GB';
    if (bytes >= 1024 * 1024) return (bytes / (1024 * 1024)).toFixed(2) + ' MB';
    if (bytes >= 1024) return (bytes / 1024).toFixed(1) + ' KB';
    return bytes + ' B';
  }

  formatRate(bytes: number): string {
    return this.formatBytes(bytes) + '/s';
  }

  build() {
    Column({ space: 12 }) {
      Text($r('app.string.nav_home'))
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.colors.textPrimary)
        .width('100%')
        .padding({ left: 24, top: 16 })

      // T5.1 VPN 开关卡
      Row() {
        Column({ space: 4 }) {
          Text($r('app.string.vpn_status'))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.colors.textPrimary)
          Text(this.vpnState.startsWith('vpn_') ? $r('app.string.' + this.vpnState) : this.vpnState)
            .fontSize(13)
            .fontColor(this.vpnOn ? '#07C160' : this.colors.textSecondary)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.vpnOn })
          .selectedColor('#07C160')
          .onChange((isOn: boolean) => {
            this.vpnOn = isOn;
            this.toggleVpn(isOn);
          })
      }
      .width('92%')
      .padding(16)
      .borderRadius(12)
      .backgroundColor(this.colors.card)

      // T5.2 模式切换卡
      Row({ space: 8 }) {
        Text($r('app.string.proxy_mode'))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.colors.textPrimary)
        Row({ space: 4 }) {
          this.modeBtn('rule', 'mode_rule')
          this.modeBtn('global', 'mode_global')
          this.modeBtn('direct', 'mode_direct')
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.End)
      }
      .width('92%')
      .padding(16)
      .borderRadius(12)
      .backgroundColor(this.colors.card)

      // T5.3 流量卡（1Hz 差分速率）
      Column({ space: 8 }) {
        Row() {
          Text($r('app.string.traffic'))
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.colors.textPrimary)
          Blank()
          Text('↓ ' + this.formatRate(this.downRate))
            .fontSize(13)
            .fontColor('#07C160')
          Text('  ↑ ' + this.formatRate(this.upRate))
            .fontSize(13)
            .fontColor(this.colors.primary)
        }
        .width('100%')
        Row() {
          Text('累计: ↓ ' + this.downTotal + '  ↑ ' + this.upTotal)
            .fontSize(12)
            .fontColor(this.colors.textSecondary)
        }
        .width('100%')
      }
      .width('92%')
      .padding(16)
      .borderRadius(12)
      .backgroundColor(this.colors.card)

      // T5.4 当前代理卡
      Row() {
        Text($r('app.string.current_proxy'))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.colors.textPrimary)
          .layoutWeight(1)
        Text(this.currentProxy)
          .fontSize(14)
          .fontColor(this.colors.primary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('92%')
      .padding(16)
      .borderRadius(12)
      .backgroundColor(this.colors.card)
      .onClick(() => this.refreshCurrentProxy())

      // T5.5 IP 信息卡
      Row() {
        Text('本地出口 IP')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.colors.textPrimary)
          .layoutWeight(1)
        Text(this.ipInfo === '' ? '--' : this.ipInfo)
          .fontSize(14)
          .fontColor(this.colors.textSecondary)
        Button('查询')
          .fontSize(12)
          .height(30)
          .backgroundColor(this.colors.primary)
          .onClick(() => this.refreshIpInfo())
      }
      .width('92%')
      .padding(16)
      .borderRadius(12)
      .backgroundColor(this.colors.card)

      // T8.1 连通性测试卡（M1 退出门）
      Column({ space: 6 }) {
        Row() {
          Text('连通性测试 (generate_204)')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.colors.textPrimary)
            .layoutWeight(1)
          Button('测试')
            .fontSize(12)
            .height(30)
            .backgroundColor('#07C160')
            .onClick(() => this.testConnectivity())
        }
        .width('100%')
        Text(this.testResult)
          .fontSize(12)
          .fontColor(this.testResult.startsWith('204 测试: HTTP 204') ? '#07C160' : this.colors.textSecondary)
      }
      .width('92%')
      .padding(16)
      .borderRadius(12)
      .backgroundColor(this.colors.card)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.colors.background)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  modeBtn(modeVal: string, labelKey: string) {
    Text($r('app.string.' + labelKey))
      .fontSize(12)
      .fontColor(this.mode === modeVal ? '#FFFFFF' : this.colors.textSecondary)
      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
      .borderRadius(12)
      .backgroundColor(this.mode === modeVal ? this.colors.primary : this.colors.background)
      .onClick(() => this.setMode(modeVal))
  }
}
