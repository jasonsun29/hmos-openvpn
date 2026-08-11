/*
 * hmos-openvpn M1: 设置页
 * 主题/语言/端口/DNS/TUN 栈（对齐 Clash Verge settings.tsx）
 * T6.1: 主题三档切换 + 语言（接入 ThemeManager + $r）
 * T6.2: 端口（默认 7980，冲突检测）
 * T6.3/T6.4: DNS/TUN 栈（L3 变更）
 */
import { ThemeColors, ThemeManager, ThemeMode } from '../model/Theme';
import { common } from '@kit.AbilityKit';
import { ConfigurationConstant } from '@kit.AbilityKit';

@Component
export struct SettingsPage {
  @Consume colors: ThemeColors;
  @State themeIndex: number = 2; // 默认跟随系统
  @State languageIndex: number = 1; // 默认英文（与 base 资源一致）

  setTheme(index: number): void {
    this.themeIndex = index;
    const mode: ThemeMode = index === 0 ? ThemeMode.Light : (index === 1 ? ThemeMode.Dark : ThemeMode.System);
    try {
      const context = getContext(this) as common.UIAbilityContext;
      context.getApplicationContext().setColorMode(ThemeManager.modeToColorMode(mode));
    } catch (e) {
      const msg: string = (e instanceof Error) ? e.message : String(e);
      console.error('M1', 'setColorMode failed: ' + msg);
    }
  }

  build() {
    Column() {
      Text($r('app.string.nav_settings'))
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.colors.textPrimary)
        .width('100%')
        .padding({ left: 24, top: 16 })

      List({ space: 8 }) {
        // 主题
        ListItem() {
          Column({ space: 8 }) {
            Row() {
              Text($r('app.string.theme'))
                .fontSize(15)
                .fontColor(this.colors.textPrimary)
                .layoutWeight(1)
            }
            .width('100%')
            Row({ space: 8 }) {
              this.themeOption(0, 'theme_light')
              this.themeOption(1, 'theme_dark')
              this.themeOption(2, 'theme_system')
            }
            .width('100%')
          }
          .width('100%')
          .padding(16)
          .borderRadius(12)
          .backgroundColor(this.colors.card)
        }
        // 语言
        ListItem() {
          Row() {
            Text($r('app.string.language'))
              .fontSize(15)
              .fontColor(this.colors.textPrimary)
              .layoutWeight(1)
            Text($r('app.string.language_zh') + ' / ' + $r('app.string.language_en'))
              .fontSize(13)
              .fontColor(this.colors.textSecondary)
          }
          .width('100%')
          .padding(16)
          .borderRadius(12)
          .backgroundColor(this.colors.card)
        }
        // 端口
        ListItem() {
          Row() {
            Text($r('app.string.port'))
              .fontSize(15)
              .fontColor(this.colors.textPrimary)
              .layoutWeight(1)
            Text('7980')
              .fontSize(13)
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

  @Builder
  themeOption(index: number, labelKey: string) {
    Row({ space: 4 }) {
      Radio({ value: 'theme' + index, group: 'themeGroup' })
        .checked(this.themeIndex === index)
        .onChange((checked: boolean) => {
          if (checked) {
            this.setTheme(index);
          }
        })
      Text($r('app.string.' + labelKey))
        .fontSize(13)
        .fontColor(this.colors.textPrimary)
    }
  }
}
