/*
 * hmos-openvpn M1: 代理页
 * 代理组树 + 节点测速 + 切换（对齐 Clash Verge proxies.tsx）
 * TODO(T4): 接入 SocketProxyService（queryProxyGroups/changeProxy/healthCheck）
 */
@Component
export struct ProxiesPage {
  build() {
    Column() {
      Text('代理')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .padding({ left: 24, top: 16 })

      List({ space: 8 }) {
        ListItem() {
          Row() {
            Text('TODO(T4.1): 代理组树')
              .fontSize(14)
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
