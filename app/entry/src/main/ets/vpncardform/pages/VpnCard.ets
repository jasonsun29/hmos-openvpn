/*
 * hmos-openvpn M3-3: 服务卡片 UI（2*2 默认尺寸）
 * 数据经 formBindingData 绑定到 @LocalStorageProp
 */
@Entry
@Component
struct VpnCard {
  @LocalStorageProp('vpnStatus') vpnStatus: string = 'VPN 未连接';
  @LocalStorageProp('modeText') modeText: string = '';

  build() {
    Column({ space: 4 }) {
      Text('HarmonyVPN')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#007AFF')
      Row({ space: 6 }) {
        Circle()
          .width(8)
          .height(8)
          .fill(this.vpnStatus.includes('已连接') ? '#34C759' : '#8E8E93')
        Text(this.vpnStatus)
          .fontSize(14)
          .fontColor(this.vpnStatus.includes('已连接') ? '#34C759' : '#8E8E93')
      }
      if (this.modeText !== '') {
        Text(this.modeText)
          .fontSize(12)
          .fontColor('#8E8E93')
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('rgba(255,255,255,0.85)')
    .borderRadius(20)
    .onClick(() => {
      // 点击卡片打开应用
      postCardAction(this, {
        action: 'router',
        abilityName: 'EntryAbility',
        params: { fromCard: true }
      });
    })
  }
}
