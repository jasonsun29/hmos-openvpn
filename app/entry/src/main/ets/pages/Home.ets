/*
 * hmos-openvpn M1: 首页
 * VPN 开关 + 模式切换 + 实时流量图 + 当前代理（对齐 Clash Verge home.tsx 卡片）
 * T5.1 VPN 开关：startVpnExtensionAbility/stopVpnExtensionAbility（M0b-3 验证链路）
 * TODO(T5.2/T5.3/T5.4): 模式切换/流量图/当前代理（依赖 SocketProxyService）
 */
import { common, Want } from '@kit.AbilityKit';
import { vpnExtension } from '@kit.NetworkKit';
import { ThemeColors } from '../model/Theme';

@Component
export struct HomePage {
  @Consume colors: ThemeColors;
  @State vpnOn: boolean = false;
  @State vpnState: string = '';

  aboutToAppear(): void {
    this.vpnState = 'vpn_disconnected';
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
      } else {
        await vpnExtension.stopVpnExtensionAbility(vpnWant);
        this.vpnState = 'vpn_disconnected';
      }
    } catch (e) {
      const msg: string = (e instanceof Error) ? e.message : String(e);
      this.vpnState = msg;
      this.vpnOn = !isOn; // 回滚开关状态
      console.error('M1', 'toggleVpn failed: ' + msg);
    }
  }

  build() {
    Column({ space: 16 }) {
      Text('首页')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .padding({ left: 24, top: 16 })

      // VPN 开关卡
      Row() {
        Column() {
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

      // 模式切换卡
      Row() {
        Text($r('app.string.proxy_mode'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.colors.textPrimary)
          .layoutWeight(1)
        Text('TODO(T5.2): ' + $r('app.string.mode_rule'))
          .fontSize(12)
          .fontColor(this.colors.textSecondary)
      }
      .width('92%')
      .padding(16)
      .borderRadius(12)
      .backgroundColor(this.colors.card)

      // 流量卡（占位）
      Row() {
        Text($r('app.string.traffic'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.colors.textPrimary)
          .layoutWeight(1)
        Text('TODO(T5.3)')
          .fontSize(12)
          .fontColor(this.colors.textSecondary)
      }
      .width('92%')
      .height(120)
      .padding(16)
      .borderRadius(12)
      .backgroundColor(this.colors.card)

      // 当前代理卡
      Row() {
        Text($r('app.string.current_proxy'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.colors.textPrimary)
          .layoutWeight(1)
        Text('TODO(T5.4)')
          .fontSize(12)
          .fontColor(this.colors.textSecondary)
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
}
