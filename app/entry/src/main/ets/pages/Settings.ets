/*
 * hmos-openvpn M1: 设置页（T6）
 * T6.1 主题三档切换 + 语言（已完成）
 * T6.2 端口（默认 7980，冲突检测提示）
 * T6.3 DNS 配置（L3 变更：重建 TUN）
 * T6.4 TUN 栈（L3 变更：重建 TUN）
 * 下发通道：loadConfig is-patch（T2.3 配置合成管线）
 */
import { ThemeColors, ThemeManager, ThemeMode, ThemeDimen } from '../model/Theme';
import { common } from '@kit.AbilityKit';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { AppService } from '../service/AppService';
import { SocketProxyService, UpdateConfigParams, ClashConfig, DnsEnhancedMode, TunStack,
  ProxyMode, Dns, Tun, getHome } from 'proxy_core';
import { promptAction } from '@kit.ArkUI';
// P3-8 GeoX 更新时间读取（statSync）
import { fileIo } from '@kit.CoreFileKit';

@Component
export struct SettingsPage {
  @Consume colors: ThemeColors;
  @State themeIndex: number = 2; // 默认跟随系统
  @State port: string = '7980';
  @State dnsModeIndex: number = 0; // fake-ip
  @State tunStackIndex: number = 0; // system
  // P3-8 GeoX 数据
  @State geoLastUpdate: string = '--';
  @State geoUpdating: boolean = false;
  // M3-2 当前主题色（'' = 默认）
  @State themeColor: string = '';
  @StorageLink('vpnOn') vpnOn: boolean = false;
  private appService: AppService = AppService.getInstance();

  aboutToAppear(): void {
    // 恢复主题偏好
    this.appService.getThemeMode().then((mode: ThemeMode) => {
      this.themeIndex = mode === ThemeMode.Light ? 0 : (mode === ThemeMode.Dark ? 1 : 2);
    });
    this.refreshGeoTime();
    this.currentThemeColor().then((c: string) => {
      this.themeColor = c;
    });
  }

  setTheme(index: number): void {
    this.themeIndex = index;
    const mode: ThemeMode = index === 0 ? ThemeMode.Light : (index === 1 ? ThemeMode.Dark : ThemeMode.System);
    try {
      const context = getContext(this) as common.UIAbilityContext;
      context.getApplicationContext().setColorMode(ThemeManager.modeToColorMode(mode));
      this.appService.setThemeMode(mode);
      // M3-2 广播：MainPage 重新解析配色（修复 colors 不随模式切换的问题）
      AppStorage.setOrCreate('themeChanged', Date.now());
    } catch (e) {
      const msg: string = (e instanceof Error) ? e.message : String(e);
      console.error('Settings', 'setColorMode failed: ' + msg);
    }
  }

  // M3-2 主题色切换（预设色板；'' = 跟随模式默认）
  async setThemeColor(color: string): Promise<void> {
    const repo = this.appService; // 用 AppService 的 Pref 通道
    await repo.setPrefString('theme_color', color);
    AppStorage.setOrCreate('themeChanged', Date.now());
  }

  // M3-2 当前主题色（用于色板选中态）
  async currentThemeColor(): Promise<string> {
    return await this.appService.getPrefString('theme_color', '');
  }

  // T6.2 端口下发（L2 变更）
  async applyPort(): Promise<void> {
    const p: number = parseInt(this.port);
    if (isNaN(p) || p < 1 || p > 65535) {
      promptAction.showToast({ message: '端口无效（1-65535）' });
      return;
    }
    await this.patchConfig((cfg: ClashConfig) => {
      cfg['mixed-port'] = p;
    }, '端口已更新: ' + p);
  }

  // T6.3 DNS 模式（P1-4 L3 变更 → TUN 重建）
  async applyDnsMode(): Promise<void> {
    const enhancedMode = this.dnsModeIndex === 0 ? 'fake-ip' : 'redir-host';
    promptAction.showToast({ message: 'TUN 重建中（DNS → ' + enhancedMode + '）...' });
    const ok: boolean = await this.appService.rebuildTun({ 'dnsEnhancedMode': enhancedMode });
    if (ok) {
      promptAction.showToast({ message: 'DNS 模式已更新' });
    } else {
      promptAction.showToast({ message: 'TUN 重建失败' });
    }
  }

  // T6.4 TUN 栈（P1-4 L3 变更 → TUN 重建）
  async applyTunStack(): Promise<void> {
    const stack = this.tunStackIndex === 0 ? 'system' : (this.tunStackIndex === 1 ? 'gvisor' : 'mixed');
    promptAction.showToast({ message: 'TUN 重建中（stack → ' + stack + '）...' });
    const ok: boolean = await this.appService.rebuildTun({ 'tunStack': stack });
    if (ok) {
      promptAction.showToast({ message: 'TUN 栈已更新' });
    } else {
      promptAction.showToast({ message: 'TUN 重建失败' });
    }
  }

  // T2.3 配置合成管线（patch 下发）
  async patchConfig(mutate: (cfg: ClashConfig) => void, successMsg: string): Promise<void> {
    const svc: SocketProxyService | undefined = this.appService.getProxyService();
    if (!svc) return;
    try {
      const activeId = await this.appService.getActiveProfileId();
      if (activeId === '') {
        promptAction.showToast({ message: '请先在订阅页激活一个订阅' });
        return;
      }
      const cfg = new ClashConfig();
      mutate(cfg);
      const params: UpdateConfigParams = {
        'profile-id': activeId,
        config: cfg,
        params: {
          'is-patch': true,
          'is-compatible': true,
          'selected-map': {},
          'override-dns': false,
          'test-url': 'http://www.gstatic.com/generate_204'
        }
      };
      await svc.loadConfig(params);
      promptAction.showToast({ message: successMsg });
    } catch (e) {
      const msg: string = (e instanceof Error) ? e.message : String(e);
      promptAction.showToast({ message: '配置更新失败: ' + msg });
    }
  }

  build() {
    Column() {
      Text($r('app.string.nav_settings'))
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.colors.textPrimary)
        .width('100%')
        .padding({ left: 24, top: 16 })

      List({ space: 8 }) {
        // T6.1 主题
        ListItem() {
          Column({ space: 8 }) {
            Row() {
              Text($r('app.string.theme'))
                .fontSize(15)
                .fontColor(this.colors.textPrimary)
                .layoutWeight(1)
            }
            .width('100%')
            Row({ space: 8 }) {
              this.themeOption(0, 'theme_light')
              this.themeOption(1, 'theme_dark')
              this.themeOption(2, 'theme_system')
            }
            .width('100%')
          }
          .width('100%')
          .padding(16)
          .borderRadius(ThemeDimen.RadiusRow)
          .backgroundColor(this.colors.glassCard)
          .backgroundBlurStyle(BlurStyle.Thin)
        }

        // M3-2 主题色自定义（预设色板）
        ListItem() {
          Column({ space: 8 }) {
            Row() {
              Text('主题色')
                .fontSize(15)
                .fontColor(this.colors.textPrimary)
                .layoutWeight(1)
            }
            .width('100%')
            Row({ space: 8 }) {
              ForEach(ThemeManager.PRESET_COLORS, (c: string) => {
                Button()
                  .width(30)
                  .height(30)
                  .borderRadius(15)
                  .backgroundColor(c === '' ? '#CCCCCC' : c)
                  .border({ width: this.themeColor === c ? 2 : 0, color: this.colors.textPrimary })
                  .onClick(() => {
                    this.themeColor = c;
                    this.setThemeColor(c);
                  })
              }, (c: string) => 'tc_' + c)
            }
            .width('100%')
          }
          .width('100%')
          .padding(16)
          .borderRadius(ThemeDimen.RadiusRow)
          .backgroundColor(this.colors.glassCard)
          .backgroundBlurStyle(BlurStyle.Thin)
        }

        // T6.2 端口
        ListItem() {
          Row({ space: 8 }) {
            Text($r('app.string.port'))
              .fontSize(15)
              .fontColor(this.colors.textPrimary)
              .layoutWeight(1)
            TextInput({ text: this.port })
              .width(120)
              .height(36)
              .fontSize(14)
              .type(InputType.Number)
              .onChange((v: string) => { this.port = v; })
            Button('应用')
              .fontSize(12)
              .height(32)
              .backgroundColor(this.colors.primary)
              .onClick(() => this.applyPort())
          }
          .width('100%')
          .padding(16)
          .borderRadius(ThemeDimen.RadiusRow)
          .backgroundColor(this.colors.glassCard)
          .backgroundBlurStyle(BlurStyle.Thin)
        }

        // T6.3 DNS 模式（L3）
        ListItem() {
          Column({ space: 8 }) {
            Row() {
              Text('DNS 模式')
                .fontSize(15)
                .fontColor(this.colors.textPrimary)
                .layoutWeight(1)
            }
            .width('100%')
            Row({ space: 8 }) {
              this.dnsOption(0, 'fake-ip')
              this.dnsOption(1, 'redir-host')
            }
            .width('100%')
          }
          .width('100%')
          .padding(16)
          .borderRadius(ThemeDimen.RadiusRow)
          .backgroundColor(this.colors.glassCard)
          .backgroundBlurStyle(BlurStyle.Thin)
        }

        // T6.4 TUN 栈（L3）
        ListItem() {
          Column({ space: 8 }) {
            Row() {
              Text('TUN 栈')
                .fontSize(15)
                .fontColor(this.colors.textPrimary)
                .layoutWeight(1)
            }
            .width('100%')
            Row({ space: 8 }) {
              this.tunOption(0, 'system')
              this.tunOption(1, 'gvisor')
              this.tunOption(2, 'mixed')
            }
            .width('100%')
          }
          .width('100%')
          .padding(16)
          .borderRadius(ThemeDimen.RadiusRow)
          .backgroundColor(this.colors.glassCard)
          .backgroundBlurStyle(BlurStyle.Thin)
        }

        // P3-8 GeoX 数据（geoip/geosite/asn 规则库）
        ListItem() {
          Row({ space: 8 }) {
            Column({ space: 2 }) {
              Text('GeoX 数据')
                .fontSize(15)
                .fontColor(this.colors.textPrimary)
              Text('上次更新: ' + this.geoLastUpdate)
                .fontSize(11)
                .fontColor(this.colors.textSecondary)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Button(this.geoUpdating ? '更新中...' : '更新')
              .fontSize(12)
              .height(32)
              .backgroundColor(this.colors.primary)
              .onClick(() => this.updateGeoData())
          }
          .width('100%')
          .padding(16)
          .borderRadius(ThemeDimen.RadiusRow)
          .backgroundColor(this.colors.glassCard)
          .backgroundBlurStyle(BlurStyle.Thin)
        }

        // T8.3 日志导出
        ListItem() {
          Row() {
            Text('导出诊断日志')
              .fontSize(15)
              .fontColor(this.colors.textPrimary)
              .layoutWeight(1)
            Button('导出')
              .fontSize(12)
              .height(32)
              .backgroundColor(this.colors.primary)
              .onClick(() => this.exportLogs())
          }
          .width('100%')
          .padding(16)
          .borderRadius(ThemeDimen.RadiusRow)
          .backgroundColor(this.colors.glassCard)
          .backgroundBlurStyle(BlurStyle.Thin)
        }
      }
      .layoutWeight(1)
      .width('100%')
      .padding({ left: 16, right: 16 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.colors.background)
  }

  // T8.3 日志导出
  async exportLogs(): Promise<void> {
    const path = await this.appService.exportLogs();
    promptAction.showToast({ message: '日志已导出: ' + path });
  }

  // P3-8 读 GeoX 数据文件的 mtime，展示"上次更新"
  async refreshGeoTime(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const home = await getHome(context);
      const geoPath = home + '/geoip.metadb';
      if (!fileIo.accessSync(geoPath)) {
        this.geoLastUpdate = '未安装';
        return;
      }
      const stat = fileIo.statSync(geoPath);
      // fs.Stat.mtime 单位是秒（Unix 时间戳），Date.now() 是毫秒 → 先乘 1000
      const mtimeMs: number = stat.mtime * 1000;
      const days = Math.floor((Date.now() - mtimeMs) / 86400000);
      this.geoLastUpdate = days <= 0 ? '今天' : (days === 1 ? '1 天前' : days + ' 天前');
    } catch (e) {
      this.geoLastUpdate = '未知';
    }
  }

  // P3-8 GeoX 更新：走 Go IPC（clash_go.sock），VPN 必须已启动
  // Go 端约定 [geoType, geoName]：geoType ∈ MMDB/ASN/GeoIp/GeoSite，
  // geoName 为文件名（Path.Resolve 拼到核心工作目录）；下载地址来自配置的 geox-url。
  async updateGeoData(): Promise<void> {
    console.log('Settings', 'updateGeoData click, geoUpdating=' + this.geoUpdating + ', vpnOn=' + this.vpnOn);
    if (this.geoUpdating) {
      return; // 防重复（不用 enabled 禁用，与 M2 按钮防抖经验一致）
    }
    const svc: SocketProxyService | undefined = this.appService.getProxyService();
    if (!svc || !this.vpnOn) {
      console.warn('Settings', 'updateGeoData 跳过: svc=' + (svc !== undefined) + ', vpnOn=' + this.vpnOn);
      promptAction.showToast({ message: 'VPN 未启动，无法更新' });
      return;
    }
    this.geoUpdating = true;
    promptAction.showToast({ message: 'GeoX 更新中...' });
    try {
      const results: string[] = [];
      results.push(await svc.updateGeoData('MMDB', 'geoip.metadb'));
      results.push(await svc.updateGeoData('GeoIp', 'GeoIP.dat'));
      results.push(await svc.updateGeoData('GeoSite', 'GeoSite.dat'));
      results.push(await svc.updateGeoData('ASN', 'ASN.mmdb'));
      const errors: string[] = results.filter((r: string) => r !== '');
      if (errors.length > 0) {
        promptAction.showToast({ message: '部分更新失败: ' + errors.join('; ') });
      } else {
        promptAction.showToast({ message: 'GeoX 更新完成' });
      }
      await this.refreshGeoTime();
    } catch (e) {
      promptAction.showToast({ message: '更新失败: ' + String(e) });
    } finally {
      this.geoUpdating = false;
    }
  }

  @Builder
  themeOption(index: number, labelKey: string) {
    Row({ space: 4 }) {
      Radio({ value: 'theme' + index, group: 'themeGroup' })
        .checked(this.themeIndex === index)
        .onChange((checked: boolean) => {
          if (checked) {
            this.setTheme(index);
          }
        })
      Text($r('app.string.' + labelKey))
        .fontSize(13)
        .fontColor(this.colors.textPrimary)
    }
  }

  @Builder
  dnsOption(index: number, label: string) {
    Row({ space: 4 }) {
      Radio({ value: 'dns' + index, group: 'dnsGroup' })
        .checked(this.dnsModeIndex === index)
        .onChange((checked: boolean) => {
          if (checked) {
            this.dnsModeIndex = index;
            this.applyDnsMode();
          }
        })
      Text(label)
        .fontSize(13)
        .fontColor(this.colors.textPrimary)
    }
  }

  @Builder
  tunOption(index: number, label: string) {
    Row({ space: 4 }) {
      Radio({ value: 'tun' + index, group: 'tunGroup' })
        .checked(this.tunStackIndex === index)
        .onChange((checked: boolean) => {
          if (checked) {
            this.tunStackIndex = index;
            this.applyTunStack();
          }
        })
      Text(label)
        .fontSize(13)
        .fontColor(this.colors.textPrimary)
    }
  }
}
