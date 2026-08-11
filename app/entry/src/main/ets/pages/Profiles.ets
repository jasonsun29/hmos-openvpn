/*
 * hmos-openvpn M1: 订阅页
 * 订阅列表 + 导入 + 用量展示（对齐 Clash Verge profiles.tsx）
 * TODO(T3): 接入 SocketProxyService（loadConfig/updateProvider/upLoadProvider）+ Profile 模型
 */
@Component
export struct ProfilesPage {
  build() {
    Column() {
      Text('订阅')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .padding({ left: 24, top: 16 })

      Row() {
        Text('TODO(T3.1): 订阅列表')
          .fontSize(14)
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
