/*
 * hmos-openvpn M1: 首页
 * VPN 开关 + 模式切换 + 实时流量图 + 当前代理（对齐 Clash Verge home.tsx 卡片）
 * T5.1 VPN 开关：startVpnExtensionAbility/stopVpnExtensionAbility（M0b-3 验证链路）
 * TODO(T5.2/T5.3/T5.4): 模式切换/流量图/当前代理（依赖 SocketProxyService）
 */
import { common, Want } from '@kit.AbilityKit';
import { vpnExtension } from '@kit.NetworkKit';

@Component
export struct HomePage {
  @State vpnOn: boolean = false;
  @State vpnState: string = '未连接';

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
        this.vpnState = '请求授权...';
        await vpnExtension.startVpnExtensionAbility(vpnWant);
        this.vpnState = '已连接';
      } else {
        await vpnExtension.stopVpnExtensionAbility(vpnWant);
        this.vpnState = '未连接';
      }
    } catch (e) {
      const msg: string = (e instanceof Error) ? e.message : String(e);
      this.vpnState = '错误: ' + msg;
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
          Text('VPN 状态')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
          Text(this.vpnState)
            .fontSize(13)
            .fontColor(this.vpnOn ? '#07C160' : '#999999')
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
      .backgroundColor('#FFFFFF')

      // 模式切换卡
      Row() {
        Text('代理模式')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
        Text('TODO(T5.2): 三态切换')
          .fontSize(12)
          .fontColor('#999999')
      }
      .width('92%')
      .padding(16)
      .borderRadius(12)
      .backgroundColor('#FFFFFF')

      // 流量卡（占位）
      Row() {
        Text('流量')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
        Text('TODO(T5.3): Canvas 流量图')
          .fontSize(12)
          .fontColor('#999999')
      }
      .width('92%')
      .height(120)
      .padding(16)
      .borderRadius(12)
      .backgroundColor('#FFFFFF')

      // 当前代理卡
      Row() {
        Text('当前代理')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
        Text('TODO(T5.4)')
          .fontSize(12)
          .fontColor('#999999')
      }
      .width('92%')
      .padding(16)
      .borderRadius(12)
      .backgroundColor('#FFFFFF')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F7F8FA')
    .alignItems(HorizontalAlign.Center)
  }
}
