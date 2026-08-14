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
    Column() {
      Text('HarmonyVPN')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#007AFF')
        .margin({ bottom: 8 })
      Text(this.vpnStatus)
        .fontSize(14)
        .fontColor(this.vpnStatus.includes('已连接') ? '#07C160' : '#8E8E93')
        .margin({ bottom: 4 })
      Text(this.modeText)
        .fontSize(12)
        .fontColor('#8E8E93')
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#FFFFFF')
    .borderRadius(16)
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
