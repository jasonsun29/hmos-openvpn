/*
 * hmos-openvpn M1: 设置页（T6）
 * T6.1 主题三档切换 + 语言（已完成）
 * T6.2 端口（默认 7980，冲突检测提示）
 * T6.3 DNS 配置（L3 变更：重建 TUN）
 * T6.4 TUN 栈（L3 变更：重建 TUN）
 * 下发通道：loadConfig is-patch（T2.3 配置合成管线）
 */
import { ThemeColors, ThemeManager, ThemeMode } from '../model/Theme';
import { common } from '@kit.AbilityKit';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { AppService } from '../service/AppService';
import { SocketProxyService, UpdateConfigParams, ClashConfig, DnsEnhancedMode, TunStack,
  ProxyMode, Dns, Tun } from 'proxy_core';
import { promptAction } from '@kit.ArkUI';

@Component
export struct SettingsPage {
  @Consume colors: ThemeColors;
  @State themeIndex: number = 2; // 默认跟随系统
  @State port: string = '7980';
  @State dnsModeIndex: number = 0; // fake-ip
  @State tunStackIndex: number = 0; // system
  private appService: AppService = AppService.getInstance();

  aboutToAppear(): void {
    // 恢复主题偏好
    this.appService.getThemeMode().then((mode: ThemeMode) => {
      this.themeIndex = mode === ThemeMode.Light ? 0 : (mode === ThemeMode.Dark ? 1 : 2);
    });
  }

  setTheme(index: number): void {
    this.themeIndex = index;
    const mode: ThemeMode = index === 0 ? ThemeMode.Light : (index === 1 ? ThemeMode.Dark : ThemeMode.System);
    try {
      const context = getContext(this) as common.UIAbilityContext;
      context.getApplicationContext().setColorMode(ThemeManager.modeToColorMode(mode));
      this.appService.setThemeMode(mode);
    } catch (e) {
      const msg: string = (e instanceof Error) ? e.message : String(e);
      console.error('M1', 'setColorMode failed: ' + msg);
    }
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

  // T6.3 DNS 模式（L3 变更）
  async applyDnsMode(): Promise<void> {
    await this.patchConfig((cfg: ClashConfig) => {
      const dns = new Dns();
      dns.enable = true;
      dns['enhanced-mode'] = this.dnsModeIndex === 0 ? DnsEnhancedMode.FakeIp : DnsEnhancedMode.Mapping;
      cfg.dns = dns;
    }, 'DNS 模式已更新（TUN 重建中...）');
  }

  // T6.4 TUN 栈（L3 变更）
  async applyTunStack(): Promise<void> {
    await this.patchConfig((cfg: ClashConfig) => {
      const tun: Tun = cfg.tun ? cfg.tun : new Tun();
      tun.stack = this.tunStackIndex === 0 ? TunStack.System : (this.tunStackIndex === 1 ? TunStack.Gvisor : TunStack.Mixed);
      tun.enable = true;
      cfg.tun = tun;
    }, 'TUN 栈已更新（TUN 重建中...）');
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
          .borderRadius(12)
          .backgroundColor(this.colors.card)
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
          .borderRadius(12)
          .backgroundColor(this.colors.card)
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
          .borderRadius(12)
          .backgroundColor(this.colors.card)
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
          .borderRadius(12)
          .backgroundColor(this.colors.card)
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
          .borderRadius(12)
          .backgroundColor(this.colors.card)
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
