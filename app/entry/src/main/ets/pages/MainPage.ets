/*
 * hmos-openvpn M1: 主框架页（左侧导航栏 + 内容区）
 * 对齐 Clash Verge _layout.tsx：左侧导航栏 + 内容区
 * 导航项用 Button 组件（onClick 绑定可靠，Row 在真机有事件失效问题）
 */
import { common } from '@kit.AbilityKit';
import { HomePage } from './Home';
import { ProxiesPage } from './Proxies';
import { ProfilesPage } from './Profiles';
import { SettingsPage } from './Settings';
import { ConnectionsPage } from './Connections';
import { RulesPage } from './Rules';
import { LogsPage } from './Logs';
import { ThemeColors, ThemeManager } from '../model/Theme';
import { CoreState } from '../model/CoreState';
import { AppService } from '../service/AppService';

@Entry
@Component
struct MainPage {
  @State currentIndex: number = 0;
  @Provide colors: ThemeColors = ThemeManager.lightColors;
  @Provide coreState: CoreState = new CoreState();
  private appService: AppService = AppService.getInstance();
  private navItems: Array<NavItem> = [
    { titleKey: 'nav_home', icon: '\uE6AE' },
    { titleKey: 'nav_proxies', icon: '\uE6A8' },
    { titleKey: 'nav_profiles', icon: '\uE726' },
    { titleKey: 'nav_settings', icon: '\uE6F0' },
    { titleKey: 'nav_connections', icon: '\uE6B4' },
    { titleKey: 'nav_rules', icon: '\uE6D9' },
    { titleKey: 'nav_logs', icon: '\uE6DD' }
  ];

  aboutToAppear(): void {
    const context = getContext(this) as common.UIAbilityContext;
    this.appService.init(context, this.getUIContext()).then(() => {
      console.log('T1', 'AppService initialized');
      // P3-10 状态恢复：AppStorage 里 vpnOn 仍为 true（VPN 进程可能还活着）时立即验活，
      // 心跳结果驱动 vpnAlive/vpnOn 复位（原逻辑散在 Home.onPageShow，抽到主框架更全面）
      if (AppStorage.get<boolean>('vpnOn') === true) {
        this.appService.pingCoreNow();
      }
    }).catch((e: Error) => {
      console.error('T1', 'AppService init failed: ' + e.message);
    });
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
          // 用 Button 承载导航项（onClick 可靠）
          Button() {
            Row({ space: 12 }) {
              Text(item.icon)
                .fontSize(18)
                .fontColor(this.currentIndex === index ? '#007AFF' : '#666666')
              Text($r('app.string.' + item.titleKey))
                .fontSize(14)
                .fontColor(this.currentIndex === index ? '#007AFF' : '#666666')
            }
            .width('100%')
            .justifyContent(FlexAlign.Start)
            .padding({ left: 20 })
          }
          .width('100%')
          .height(44)
          .type(ButtonType.Normal)
          .backgroundColor(this.currentIndex === index ? '#E8F2FF' : Color.Transparent)
          .borderRadius(8)
          .onClick(() => {
            console.log('NAV', 'click index=' + index + ' key=' + item.titleKey);
            this.currentIndex = index;
          })
        }, (item: NavItem) => item.titleKey)
      }
      .width(180)
      .height('100%')
      .backgroundColor(this.colors.background)
      .alignItems(HorizontalAlign.Start)

      // 内容区（build 内条件渲染）
      Column() {
        Row() {
          Text($r('app.string.' + this.navItems[this.currentIndex].titleKey))
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.colors.textPrimary)
            .layoutWeight(1)
          Text('idx=' + this.currentIndex)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FF3B30')
            .margin({ right: 24 })
        }
        .width('100%')
        .padding({ left: 24, top: 16, bottom: 16 })
        if (this.currentIndex === 0) {
          HomePage()
        } else if (this.currentIndex === 1) {
          ProxiesPage()
        } else if (this.currentIndex === 2) {
          ProfilesPage()
        } else if (this.currentIndex === 3) {
          SettingsPage()
        } else if (this.currentIndex === 4) {
          ConnectionsPage()
        } else if (this.currentIndex === 5) {
          RulesPage()
        } else if (this.currentIndex === 6) {
          LogsPage()
        } else {
          // M2 占位页
          Column() {
            Text($r('app.string.' + this.navItems[this.currentIndex].titleKey))
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
      .layoutWeight(1)
      .height('100%')
      .backgroundColor(this.colors.card)
    }
    .width('100%')
    .height('100%')
  }
}

interface NavItem {
  titleKey: string;
  icon: string;
}
