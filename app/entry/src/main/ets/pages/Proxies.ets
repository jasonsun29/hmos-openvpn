/*
 * hmos-openvpn M1: 代理页
 * 代理组树 + 节点测速 + 切换（对齐 Clash Verge proxies.tsx）
 * T4.1/T4.2/T4.3: 依赖 SocketProxyService（queryProxyGroups/changeProxy/healthCheck）
 */
import { ThemeColors } from '../model/Theme';

@Component
export struct ProxiesPage {
  @Consume colors: ThemeColors;

  build() {
    Column() {
      Text($r('app.string.nav_proxies'))
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.colors.textPrimary)
        .width('100%')
        .padding({ left: 24, top: 16 })

      List({ space: 8 }) {
        ListItem() {
          Row() {
            Text('TODO(T4.1): ' + $r('app.string.nav_proxies'))
              .fontSize(14)
              .fontColor(this.colors.textSecondary)
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
}
