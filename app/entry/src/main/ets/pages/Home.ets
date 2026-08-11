/*
 * hmos-openvpn M1: 首页
 * VPN 开关 + 模式切换 + 实时流量图 + 当前代理（对齐 Clash Verge home.tsx 卡片）
 * TODO(T5): 接入 SocketProxyService（queryTrafficNow/queryProxyGroups/vpnConfigIsLoad）
 */
@Component
export struct HomePage {
  @State vpnOn: boolean = false;
  @State mode: string = 'rule';

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
          Text(this.vpnOn ? '已连接' : '未连接')
            .fontSize(13)
            .fontColor(this.vpnOn ? '#07C160' : '#999999')
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.vpnOn })
          .selectedColor('#07C160')
          .onChange((isOn: boolean) => {
            this.vpnOn = isOn;
            // TODO(T5.1): startVpnExtensionAbility / stopVpnExtensionAbility
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
