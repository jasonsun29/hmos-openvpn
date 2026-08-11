/*
 * hmos-openvpn M1: 订阅页
 * 订阅列表 + 导入 + 用量展示（对齐 Clash Verge profiles.tsx）
 * T3.1-T3.4: 依赖 SocketProxyService（loadConfig/updateProvider/upLoadProvider）+ Profile 模型
 */
import { ThemeColors } from '../model/Theme';

@Component
export struct ProfilesPage {
  @Consume colors: ThemeColors;

  build() {
    Column() {
      Text($r('app.string.nav_profiles'))
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.colors.textPrimary)
        .width('100%')
        .padding({ left: 24, top: 16 })

      Row() {
        Text('TODO(T3.1): ' + $r('app.string.nav_profiles'))
          .fontSize(14)
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
