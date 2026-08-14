/*
 * UI 2.0 通用组件：玻璃卡片（毛玻璃 + 半透明底 + 大圆角）
 * 用法：
 *   GlassCard({ radius: 20, padding: 16 }) {
 *     // 卡片内容（父组件上下文构建）
 *   }
 */
import { ThemeColors, ThemeDimen } from '../model/Theme';

@Component
export struct GlassCard {
  @Consume colors: ThemeColors;
  @Prop radius: number = ThemeDimen.RadiusCard;
  @Prop cardPadding: number = ThemeDimen.CardPad;
  // 水平外边距（尾随闭包后不能链式调 .margin，故收进参数）
  @Prop marginH: number = 0;
  // 是否显示按压反馈（点击卡片）
  @Prop pressable: boolean = false;
  // 点击回调（尾随闭包后不能链式调 .onClick，故收进参数）
  action: () => void = () => {};
  @State pressed: boolean = false;
  @BuilderParam content: () => void = this.emptyContent;

  @Builder
  emptyContent() {
  }

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    .padding(this.cardPadding)
    .borderRadius(this.radius)
    .margin({ left: this.marginH, right: this.marginH })
    .onClick(() => {
      this.action();
    })
    .backgroundColor(this.pressed && this.pressable ? this.colors.card : this.colors.glassCard)
    .backgroundBlurStyle(BlurStyle.Thin)
    .scale(this.pressed && this.pressable ? { x: 0.98, y: 0.98 } : { x: 1, y: 1 })
    .animation({ duration: 120, curve: Curve.EaseOut })
    .onTouch((event: TouchEvent) => {
      if (!this.pressable) {
        return;
      }
      if (event.type === TouchType.Down) {
        this.pressed = true;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.pressed = false;
      }
    })
  }
}

/** 分组小标题：主题色圆点 + 标题 */
@Component
export struct SectionHeader {
  @Consume colors: ThemeColors;
  @Prop title: string = '';

  build() {
    Row({ space: 8 }) {
      Circle()
        .width(8)
        .height(8)
        .fill(this.colors.primary)
      Text(this.title)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.colors.textPrimary)
    }
    .width('100%')
    .margin({ top: ThemeDimen.GapM, bottom: ThemeDimen.GapS })
  }
}
