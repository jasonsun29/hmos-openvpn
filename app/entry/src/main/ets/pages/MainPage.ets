/*
 * hmos-openvpn M1: 主框架页（Navigation + 左侧栏）
 * 对齐 Clash Verge _layout.tsx：左侧导航栏 + 内容区
 * T1.1: M1 渲染 4 页签（home/proxies/profiles/settings），connections/rules/logs M2 占位
 * T1.2: 主题注入（@Provide colors）
 * T1.3: i18n（$r 引用）
 */
import { router } from '@kit.ArkUI';
import { HomePage } from './Home';
import { ProxiesPage } from './Proxies';
import { ProfilesPage } from './Profiles';
import { SettingsPage } from './Settings';
import { ThemeColors, ThemeManager, ThemeMode } from '../model/Theme';
import { CoreState, CoreStateType } from '../model/CoreState';

@Entry
@Component
struct MainPage {
  @State currentIndex: number = 0;
  @State isDark: boolean = false;
  @Provide colors: ThemeColors = ThemeManager.lightColors;
  @Provide coreState: CoreState = new CoreState();
  private navItems: Array<NavItem> = [
    { titleKey: 'nav_home', icon: '\uE6AE', page: 'pages/Home' },
    { titleKey: 'nav_proxies', icon: '\uE6A8', page: 'pages/Proxies' },
    { titleKey: 'nav_profiles', icon: '\uE726', page: 'pages/Profiles' },
    { titleKey: 'nav_settings', icon: '\uE6F0', page: 'pages/Settings' },
    { titleKey: 'nav_connections', icon: '\uE6B4', page: '' },
    { titleKey: 'nav_rules', icon: '\uE6D9', page: '' },
    { titleKey: 'nav_logs', icon: '\uE6DD', page: '' }
  ];

  aboutToAppear(): void {
    // 跟随系统深浅色（后续 T6.1 支持三档切换）
    const dc = this.getUIContext().getHostContext();
  }

  build() {
    Row() {
      // 左侧导航栏
      Column() {
        Text('hmos-openvpn')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.colors.primary)
          .margin({ top: 24, bottom: 24 })

        ForEach(this.navItems, (item: NavItem, index: number) => {
          Row() {
            Text(item.icon)
              .fontSize(20)
              .fontColor(this.currentIndex === index ? this.colors.primary : this.colors.textSecondary)
              .margin({ right: 12 })
            Text($r('app.string.' + item.titleKey))
              .fontSize(14)
              .fontColor(this.currentIndex === index ? this.colors.primary : this.colors.textSecondary)
          }
          .width('100%')
          .height(44)
          .padding({ left: 20 })
          .borderRadius(8)
          .backgroundColor(this.currentIndex === index ? '#E8F2FF' : Color.Transparent)
          .onClick(() => {
            this.currentIndex = index;
            if (item.page !== '') {
              router.pushUrl({ url: item.page });
            }
          })
        }, (item: NavItem) => item.titleKey)
      }
      .width(180)
      .height('100%')
      .backgroundColor(this.colors.background)
      .alignItems(HorizontalAlign.Start)

      // 内容区
      Column() {
        Text($r('app.string.' + this.navItems[this.currentIndex].titleKey))
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.colors.textPrimary)
          .width('100%')
          .padding({ left: 24, top: 16, bottom: 16 })
        // 内容占位
        this.pageContent(this.currentIndex)
      }
      .layoutWeight(1)
      .height('100%')
      .backgroundColor(this.colors.card)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  pageContent(index: number) {
    if (index === 0) {
      HomePage()
    } else if (index === 1) {
      ProxiesPage()
    } else if (index === 2) {
      ProfilesPage()
    } else if (index === 3) {
      SettingsPage()
    } else {
      // M2 占位页
      Column() {
        Text($r('app.string.' + this.navItems[index].titleKey))
          .fontSize(16)
          .fontColor(this.colors.textSecondary)
          .margin({ top: 60 })
        Text('M2')
          .fontSize(13)
          .fontColor(this.colors.textSecondary)
          .margin({ top: 8 })
      }
      .width('100%')
      .height('100%')
    }
  }
}

interface NavItem {
  titleKey: string;
  icon: string;
  page: string;
}
