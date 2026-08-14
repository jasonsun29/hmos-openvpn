/*
 * hmos-openvpn M1: 首页（T5）
 * T5.1 VPN 开关（startVpnExtensionAbility/stop）— 已完成
 * T5.2 模式切换（loadConfig is-patch 下发 mode 字段）
 * T5.3 实时流量图（queryTrafficNow 1Hz 轮询 + 差分，Canvas 绘制）
 * T5.4 当前代理卡（queryProxyGroups 取 GLOBAL 组 now）
 * T5.5 IP 信息卡（api.ipify.org，超时 5s 显示 "--"）
 * 修复：
 *   P0-4 监听 AppStorage 'vpnAlive'，false 时自动复位 vpnOn（防假连接）
 *   P0-5 setMode() test-url 统一 HTTPS（与 ClashVpnAbility 一致）
 */
import { common, Want } from '@kit.AbilityKit';
import { vpnExtension } from '@kit.NetworkKit';
import { http } from '@kit.NetworkKit';
import { ThemeColors, ThemeDimen } from '../model/Theme';
import { GlassCard } from '../components/GlassCard';
import { AppIcon, AppIconName } from '../components/AppIcon';
import { AppService } from '../service/AppService';
import { BackgroundKeepAliveService } from '../service/BackgroundKeepAliveService';
import { SocketProxyService, ProxyMode, ProxyGroup, Traffic, SelectedMapStore, ConfigReader } from 'proxy_core';
import { promptAction } from '@kit.ArkUI';
// P3-5 统一异步错误处理
import { tryRunAsync } from '../utils/AsyncUtils';

@Component
export struct HomePage {
  @Consume colors: ThemeColors;
  // VPN 开关状态存 AppStorage（跨页面切换保留）
  @StorageLink('vpnOn') vpnOn: boolean = false;
  @StorageLink('vpnStateKey') vpnState: string = '';
  // P0-4 监听 VPN 存活心跳（false 时自动复位 vpnOn）
  @StorageLink('vpnAlive') @Watch('onVpnAliveChanged') vpnAlive: boolean = false;
  // P1-7 监听代理切换事件，实时刷新当前代理显示
  @StorageLink('currentProxyName') @Watch('onCurrentProxyChanged') currentProxyName: string = '';
  // t44 导航显示/隐藏广播：兼容 NavDestination 下 onPageShow/onPageHide 语义变化
  @StorageLink('navPageShown') @Watch('onNavPageShownEvt') navPageShown: string = '';
  @StorageLink('navPageHidden') @Watch('onNavPageHiddenEvt') navPageHidden: string = '';

  onNavPageShownEvt(): void {
    if (this.navPageShown.startsWith('Home')) {
      this.onPageShow();
    }
  }

  onNavPageHiddenEvt(): void {
    if (this.navPageHidden.startsWith('Home')) {
      this.onPageHide();
    }
  }

  onVpnAliveChanged(): void {
    // P0-4 心跳探测到核心挂了 → 复位 UI 状态，防“假连接”bug
    if (!this.vpnAlive && this.vpnOn) {
      console.warn('Home', 'vpnAlive → false, 复位 vpnOn');
      this.vpnOn = false;
      this.vpnState = 'vpn_disconnected';
      this.stopTrafficPoll();
      // 真机回归补充：同步落盘 vpnOn，避免服务卡片继续显示“已连接”
      const context = getContext(this) as common.UIAbilityContext;
      SelectedMapStore.saveVpnOn(context, false);
    }
  }

  // P1-7 Proxies 页切换节点后，实时刷新当前代理显示
  onCurrentProxyChanged(): void {
    if (this.currentProxyName !== '') {
      this.currentProxy = this.currentProxyName;
      console.log('Home', 'currentProxy updated via StorageLink: ' + this.currentProxyName);
    }
  }
  // P3 重构：默认全局模式（按钮值小写 global/rule/direct）
  @State mode: string = 'global';
  @State currentProxy: string = '--';
  @State ipInfo: string = '';
  @State downRate: number = 0;
  @State upRate: number = 0;
  @State downTotal: string = '0 B';
  @State upTotal: string = '0 B';
  // P3-1 波形图 Canvas 实际尺寸（onAreaChange 自适应容器宽度）
  @State canvasW: number = 340;
  @State canvasH: number = 90;
  private appService: AppService = AppService.getInstance();
  private trafficTimer: number = -1;
  private prevDown: number = 0;
  private prevUp: number = 0;
  private toggling: boolean = false;
  // 流量波形采样（最多 60 个点 = 60 秒）
  // P3-2 采样窗口上限常量（批量裁剪阈值 = 2 倍上限）
  private static readonly MAX_HISTORY_POINTS = 60;
  private downHistory: Array<number> = [];
  private upHistory: Array<number> = [];
  private canvasCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));

  aboutToAppear(): void {
    // 首次进入时初始化（AppStorage 已有值则不覆盖）
    if (this.vpnState === '') {
      this.vpnState = 'vpn_disconnected';
    }
    // P3 硬性需求：启动即恢复持久化模式（上次选什么，重启后还是什么）
    this.refreshMode();
    // 恢复轮询（如果 VPN 还开着）
    if (this.vpnOn) {
      this.startTrafficPoll();
      this.refreshCurrentProxy();
      // P1-11 应用回到前台时立即 pingCore 验活（setInterval 可能被系统挂起，需手动补一次）
      this.appService.pingCoreNow();
    }
  }

  onPageShow(): void {
    // P3 硬性需求：切回首页时同步持久化模式
    this.refreshMode();
    // P1-11 页面进入前台：与退后台时可能 socket 断开的场景，强制刷新
    if (this.vpnOn) {
      this.refreshCurrentProxy();
      this.appService.pingCoreNow();
    }
  }

  onPageHide(): void {
    // P1-11 页面退后台：停止流量轮询节省资源（避免 setInterval 反复打错误日志）
    this.stopTrafficPoll();
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
        // 配置加载由 VPN 进程 onCreate 完成（loadActiveConfig）；此处直接启动 VPN
        await vpnExtension.startVpnExtensionAbility(vpnWant);
        this.vpnState = 'vpn_connected';
        // 恢复轮询/RPC（核心已就绪）
        this.startTrafficPoll();
        this.refreshMode();
        this.refreshCurrentProxy();
        // P0-4 启动心跳检测（VPN 进程被杀时系统不通知，需自建心跳）
        this.appService.startHeartbeat();
        // M3-3 服务卡片状态
        SelectedMapStore.saveVpnOn(context, true);
        // T7.3a 后台保活（长时任务+常驻通知，防止 VPN 进程被系统回收）
        BackgroundKeepAliveService.getInstance().start(context);
      } else {
        await vpnExtension.stopVpnExtensionAbility(vpnWant);
        this.vpnState = 'vpn_disconnected';
        this.stopTrafficPoll();
        // P0-4 停止心跳
        this.appService.stopHeartbeat();
        BackgroundKeepAliveService.getInstance().stop(context);
        // M3-3 服务卡片状态
        SelectedMapStore.saveVpnOn(context, false);
      }
    } catch (e) {
      const msg: string = (e instanceof Error) ? e.message : String(e);
      this.vpnState = 'vpn_disconnected';
      this.vpnOn = !isOn; // 回滚
      // P1-10 识别授权失败场景，提示用户具体原因
      if (/cancel|denied|拒绝|取消/i.test(msg)) {
        promptAction.showToast({ message: 'VPN 授权已取消' });
      } else if (/policy|forbidden|不允许|90024|95100002/i.test(msg)) {
        promptAction.showToast({ message: '系统策略不允许启动 VPN（检查权限设置）' });
      } else {
        promptAction.showToast({ message: 'VPN 启动失败: ' + msg });
      }
      console.error('Home', 'toggleVpn failed: ' + msg);
    }
  }

  // T5.2 模式切换（patch 下发）
  // P3 重构：模式切换。模式是应用自己的状态（持久化），与订阅结构无关。
  // VPN 在线时立即下发生效；离线时保存，开启 VPN 后由启动路径应用。
  async setMode(mode: string): Promise<void> {
    console.log('Home', 'setMode click: ' + mode);
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const activeId = await this.appService.getActiveProfileId();
      if (activeId === '') {
        promptAction.showToast({ message: '请先在订阅页激活一个订阅' });
        return;
      }
      await SelectedMapStore.saveMode(context, mode);
      this.mode = mode;
      AppStorage.setOrCreate('vpnMode', mode);
      if (!this.vpnOn) {
        promptAction.showToast({ message: '已保存，开启 VPN 后生效' });
        return;
      }
      if (mode.toUpperCase() === ProxyMode.Global) {
        // 全局模式：应用持久化的全局端点（DIRECT/组/节点），未选则核心默认
        const view = await ConfigReader.read(context, activeId);
        const endpoint = (await SelectedMapStore.load(context, activeId))['GLOBAL'] ?? '';
        const err = await this.appService.applyGlobalEndpoint(endpoint, view);
        if (err !== '') {
          promptAction.showToast({ message: '切换失败: ' + err });
        } else {
          promptAction.showToast({ message: '已切换为全局模式' });
        }
      } else if (mode.toUpperCase() === ProxyMode.Direct) {
        await this.appService.patchMode(ProxyMode.Direct);
      } else {
        await this.appService.patchMode(ProxyMode.Rule);
      }
      this.refreshCurrentProxy();
    } catch (e) {
      const msg: string = (e instanceof Error) ? e.message : String(e);
      promptAction.showToast({ message: '模式切换失败: ' + msg });
    }
  }

  // T5.4 当前代理：全局模式下优先显示持久化端点（离线也能看），
  // 未选择时查询核心 GLOBAL 组当前值
  async refreshCurrentProxy(): Promise<void> {
    const svc: SocketProxyService | undefined = this.appService.getProxyService();
    if (!svc) return;
    await tryRunAsync('Home.refreshCurrentProxy', async (): Promise<void> => {
      const context = getContext(this) as common.UIAbilityContext;
      const activeId = await this.appService.getActiveProfileId();
      if (activeId !== '') {
        const endpoint = (await SelectedMapStore.load(context, activeId))['GLOBAL'] ?? '';
        if (endpoint !== '') {
          this.currentProxy = endpoint;
          return;
        }
      }
      const groups = await svc.queryProxyGroups(ProxyMode.Global);
      const g = groups.find((x: ProxyGroup) => x.name === 'GLOBAL');
      if (g) {
        this.currentProxy = g.now;
      }
    });
  }

  async refreshMode(): Promise<void> {
    await tryRunAsync('Home.refreshMode', async (): Promise<void> => {
      // P3 持久化模式优先（上次选什么模式，重启后还是什么模式）
      const context = getContext(this) as common.UIAbilityContext;
      const persisted = await SelectedMapStore.loadMode(context);
      if (persisted !== '') {
        // 统一大写比较（按钮值是小写 global/rule/direct）
        const p = persisted.toUpperCase();
        if (p === ProxyMode.Global || p === ProxyMode.Direct || p === ProxyMode.Rule) {
          this.mode = persisted;
          AppStorage.setOrCreate('vpnMode', persisted);
          console.log('Home', '恢复持久化模式: ' + persisted);
          return;
        }
      }
      // P3 重构：无持久化记录（首次）→ 默认全局模式
      this.mode = 'global';
      AppStorage.setOrCreate('vpnMode', 'global');
    });
  }

  // T5.3 流量轮询（1Hz 差分）
  startTrafficPoll(): void {
    if (this.trafficTimer !== -1) {
      return; // t44 防重复：NavDestination 下 onPageShow 可能多次触发
    }
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
    await tryRunAsync('Home.pollTraffic', async (): Promise<void> => {
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
      this.downTotal = AppService.formatBytes(down);
      this.upTotal = AppService.formatBytes(up);
      // 流量波形采样（1Hz 推入，最多 60 点）
      this.downHistory.push(this.downRate);
      this.upHistory.push(this.upRate);
      // P3-2 批量裁剪替代逐个 shift()：shift 每次 O(n) 搬移，
      // 攒到 2 倍上限再一次剪掉，摊还 O(1)
      if (this.downHistory.length > HomePage.MAX_HISTORY_POINTS * 2) {
        this.downHistory.splice(0, this.downHistory.length - HomePage.MAX_HISTORY_POINTS);
        this.upHistory.splice(0, this.upHistory.length - HomePage.MAX_HISTORY_POINTS);
      }
      this.drawTrafficGraph();
    });
  }

  // T5.3b 流量波形绘制（Canvas，对齐 Clash Verge enhanced-canvas-traffic-graph）
  drawTrafficGraph(): void {
    const ctx = this.canvasCtx;
    if (!ctx) return;
    // P3-1 用 onAreaChange 实测尺寸，随容器宽度自适应
    const w = this.canvasW;
    const h = this.canvasH;
    ctx.clearRect(0, 0, w, h);
    // 背景网格线（行数随高度动态）
    ctx.strokeStyle = '#303030';
    ctx.lineWidth = 0.5;
    const gridRows = Math.floor(h / 20);
    for (let i = 0; i < gridRows; i++) {
      const y = 15 + i * 20;
      ctx.beginPath();
      ctx.moveTo(0, y);
      ctx.lineTo(w, y);
      ctx.stroke();
    }
    // 计算最大速率（避免除零）
    // 循环前取局部引用：避免循环内反复读 this.downHistory（hp-arkui-no-state-var-access-in-loop）
    const down = this.downHistory;
    const up = this.upHistory;
    let maxRate = 1;
    for (let v of down) {
      if (v > maxRate) maxRate = v;
    }
    for (let v of up) {
      if (v > maxRate) maxRate = v;
    }
    if (maxRate <= 0) return;
    const n = down.length;
    if (n < 2) return;
    const step = w / 60;
    // 下载曲线（蓝色）
    ctx.strokeStyle = '#0A84FF';
    ctx.lineWidth = 2;
    ctx.beginPath();
    for (let i = 0; i < n; i++) {
      const x = w - (n - i) * step;
      const y = h - (down[i] / maxRate) * (h - 20) - 5;
      if (i === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    }
    ctx.stroke();
    // 上传曲线（绿色）
    ctx.strokeStyle = '#07C160';
    ctx.lineWidth = 1.5;
    ctx.beginPath();
    for (let i = 0; i < n; i++) {
      const x = w - (n - i) * step;
      const y = h - (up[i] / maxRate) * (h - 20) - 5;
      if (i === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    }
    ctx.stroke();
  }

  // T5.5 IP 信息（直连查询，本地出口）
  async refreshIpInfo(): Promise<void> {
    // 多服务 fallback：ipify（海外）→ ip.sb → ipip（国内可达）
    const services: Array<string> = [
      'https://api.ipify.org?format=json',
      'https://api.ip.sb/ip',
      'https://myip.ipip.net'
    ];
    // lint 规则 hp-arkui-no-state-var-access-in-loop：循环内不写 @State，
    // 先在局部变量累积，循环外一次性赋值
    let found: string = '';
    for (let i = 0; i < services.length; i++) {
      try {
        const httpRequest = http.createHttp();
        const resp = await httpRequest.request(services[i], {
          connectTimeout: 8000,
          readTimeout: 8000,
          usingCache: false
        });
        const body: string = resp.result as string;
        httpRequest.destroy();
        // 解析 IP（三种格式：json / 纯文本 / 中文文本）
        let ip: string = '';
        try {
          const json = JSON.parse(body) as Record<string, string>;
          ip = json['ip'] ?? '';
        } catch (e) {
          // 非 JSON，尝试提取 IPv4
          const m = body.match(/(\d{1,3}\.){3}\d{1,3}/);
          ip = m ? m[0] : body.trim();
        }
        if (ip !== '' && ip.length < 40) {
          found = ip;
          break;
        }
      } catch (e) {
        const msg: string = (e instanceof Error) ? e.message : JSON.stringify(e);
        console.error('Home', 'refreshIpInfo svc' + i + ' failed: ' + msg);
      }
    }
    this.ipInfo = found !== '' ? found : '查询失败（网络不可达）';
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
      this.testResult = '204 测试: HTTP ' + code + '，耗时 ' + elapsed + 'ms，' +
        (code === 204 || code === 200 ? '通过' : '异常');
      httpRequest.destroy();
    } catch (e) {
      const elapsed = Date.now() - t0;
      const msg: string = (e instanceof Error) ? e.message : String(e);
      this.testResult = '204 测试失败 (' + elapsed + 'ms): ' + msg;
    }
  }

  // P3-3 公共化：本页删除重复实现，统一走 AppService.formatBytes
  formatRate(bytes: number): string {
    return AppService.formatBytes(bytes) + '/s';
  }

  build() {
    Scroll() {
      Column({ space: ThemeDimen.GapM }) {
        Text($r('app.string.nav_home'))
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.colors.textPrimary)
          .width('100%')
          .padding({ left: 24, top: 20, bottom: 4 })

        // UI 2.0 Hero 状态卡（玻璃大卡：状态大字 + 大开关 + 当前代理）
        GlassCard({ radius: 24, marginH: ThemeDimen.PagePad }) {
          Column({ space: 12 }) {
            Row() {
              Text($r('app.string.vpn_status'))
                .fontSize(13)
                .fontColor(this.colors.textSecondary)
              Blank()
              Circle()
                .width(8)
                .height(8)
                .fill(this.vpnOn ? this.colors.success : this.colors.textSecondary)
            }
            .width('100%')
            Row() {
              Text(this.vpnState.startsWith('vpn_') ? $r('app.string.' + this.vpnState) : this.vpnState)
                .fontSize(28)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.vpnOn ? this.colors.success : this.colors.textPrimary)
              Blank()
              Toggle({ type: ToggleType.Switch, isOn: this.vpnOn })
                .selectedColor(this.colors.success)
                .scale({ x: 1.15, y: 1.15 })
                .onChange((isOn: boolean) => {
                  // 防抖：toggleVpn 执行期间忽略重复触发（Toggle 可能触发多次 onChange）
                  if (this.toggling) {
                    return;
                  }
                  if (isOn === this.vpnOn) {
                    return;
                  }
                  this.toggling = true;
                  this.vpnOn = isOn;
                  this.toggleVpn(isOn).finally(() => {
                    setTimeout(() => {
                      this.toggling = false;
                    }, 500);
                  });
                })
            }
            .width('100%')
            Row() {
              Text($r('app.string.current_proxy'))
                .fontSize(13)
                .fontColor(this.colors.textSecondary)
              Blank()
              Text(this.currentProxy)
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.colors.primary)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .width('100%')
          }
        }

        // UI 2.0 模式分段控件（胶囊组）
        Row({ space: 4 }) {
          this.modeBtn('rule', 'mode_rule')
          this.modeBtn('global', 'mode_global')
          this.modeBtn('direct', 'mode_direct')
        }
        .padding(4)
        .borderRadius(999)
        .backgroundColor(this.colors.glassCard)
        .backgroundBlurStyle(BlurStyle.Thin)

        // UI 2.0 流量玻璃卡（1Hz 差分速率 + 实时波形）
        GlassCard({ marginH: ThemeDimen.PagePad }) {
          Column({ space: 8 }) {
            Row() {
              Text($r('app.string.traffic'))
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.colors.textPrimary)
              Blank()
              Text('↓ ' + this.formatRate(this.downRate))
                .fontSize(13)
                .fontColor(this.colors.success)
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
            // T5.3b 实时流量波形（Canvas，P3-1 宽度自适应容器）
            Canvas(this.canvasCtx)
              .width('100%')
              .height(90)
              .margin({ top: 8 })
              .onAreaChange((_old: Area, newArea: Area) => {
                this.canvasW = Number(newArea.width);
                this.canvasH = Number(newArea.height);
                this.drawTrafficGraph();
              })
              .onReady(() => {
                if (this.canvasCtx) {
                  this.drawTrafficGraph();
                }
              })
          }
        }

        // UI 2.0 工具行 1：当前代理（点击刷新）
        GlassCard({ radius: ThemeDimen.RadiusRow, marginH: ThemeDimen.PagePad, pressable: true, action: () => this.refreshCurrentProxy() }) {
          Row({ space: 8 }) {
            AppIcon({ name: AppIconName.Selector, iconSize: 16, color: this.colors.primary })
            Text($r('app.string.current_proxy'))
              .fontSize(14)
              .fontColor(this.colors.textPrimary)
              .layoutWeight(1)
            Text(this.currentProxy)
              .fontSize(13)
              .fontColor(this.colors.primary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            AppIcon({ name: AppIconName.ChevronRight, iconSize: 13, color: this.colors.textSecondary })
          }
          .width('100%')
        }

        // UI 2.0 工具行 2：本地出口 IP
        GlassCard({ radius: ThemeDimen.RadiusRow, marginH: ThemeDimen.PagePad }) {
          Row({ space: 8 }) {
            AppIcon({ name: AppIconName.Logo, iconSize: 16, color: this.colors.primary })
            Text('本地出口 IP')
              .fontSize(14)
              .fontColor(this.colors.textPrimary)
              .layoutWeight(1)
            Text(this.ipInfo === '' ? '--' : this.ipInfo)
              .fontSize(13)
              .fontColor(this.colors.textSecondary)
            Button('查询')
              .fontSize(12)
              .height(30)
              .backgroundColor(this.colors.primary)
              .onClick(() => this.refreshIpInfo())
          }
          .width('100%')
        }

        // UI 2.0 工具行 3：连通性测试（M1 退出门）
        GlassCard({ radius: ThemeDimen.RadiusRow, marginH: ThemeDimen.PagePad }) {
          Column({ space: 6 }) {
            Row({ space: 8 }) {
              AppIcon({ name: AppIconName.UrlTest, iconSize: 16, color: this.colors.success })
              Text('连通性测试 (generate_204)')
                .fontSize(14)
                .fontColor(this.colors.textPrimary)
                .layoutWeight(1)
              Button('测试')
                .fontSize(12)
                .height(30)
                .backgroundColor(this.colors.success)
                .onClick(() => this.testConnectivity())
            }
            .width('100%')
            Text(this.testResult)
              .fontSize(12)
              .fontColor(this.testResult.startsWith('204 测试: HTTP 204') ? this.colors.success : this.colors.textSecondary)
          }
        }
      }
      .width('100%')
      .backgroundColor(this.colors.background)
      .alignItems(HorizontalAlign.Center)
      .padding({ bottom: 24 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.colors.background)
    .scrollBar(BarState.Off)
  }

  @Builder
  modeBtn(modeVal: string, labelKey: string) {
    Text($r('app.string.' + labelKey))
      .fontSize(13)
      .fontWeight(this.mode === modeVal ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.mode === modeVal ? '#FFFFFF' : this.colors.textSecondary)
      .padding({ left: 18, right: 18, top: 8, bottom: 8 })
      .borderRadius(999)
      .backgroundColor(this.mode === modeVal ? this.colors.primary : Color.Transparent)
      .onClick(() => this.setMode(modeVal))
  }
}
