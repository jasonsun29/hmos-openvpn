/*
 * hmos-openvpn M1: 设置页
 * 主题/语言/端口/DNS/TUN 栈（对齐 Clash Verge settings.tsx）
 * TODO(T6): 主题三档 + 端口(mixed-port) + DNS + TUN 栈
 */
@Component
export struct SettingsPage {
  build() {
    Column() {
      Text('设置')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .padding({ left: 24, top: 16 })

      List({ space: 8 }) {
        ListItem() {
          Row() {
            Text('主题')
              .fontSize(15)
              .layoutWeight(1)
            Text('TODO(T6.1)')
              .fontSize(13)
              .fontColor('#999999')
          }
          .width('100%')
          .padding(16)
          .borderRadius(12)
          .backgroundColor('#FFFFFF')
        }
        ListItem() {
          Row() {
            Text('语言')
              .fontSize(15)
              .layoutWeight(1)
            Text('TODO(T6.1)')
              .fontSize(13)
              .fontColor('#999999')
          }
          .width('100%')
          .padding(16)
          .borderRadius(12)
          .backgroundColor('#FFFFFF')
        }
        ListItem() {
          Row() {
            Text('端口 (mixed-port)')
              .fontSize(15)
              .layoutWeight(1)
            Text('TODO(T6.2)')
              .fontSize(13)
              .fontColor('#999999')
          }
          .width('100%')
          .padding(16)
          .borderRadius(12)
          .backgroundColor('#FFFFFF')
        }
      }
      .layoutWeight(1)
      .width('100%')
      .padding({ left: 16, right: 16 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F7F8FA')
  }
}
