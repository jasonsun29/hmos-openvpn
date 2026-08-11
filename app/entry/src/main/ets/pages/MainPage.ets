/*
 * hmos-openvpn M1: 主框架页（Navigation + 左侧栏）
 * 对齐 Clash Verge _layout.tsx：左侧导航栏 + 内容区
 * M1 页面：home / proxies / profiles / settings（connections/rules/logs/unlock M2 占位）
 */
import { router } from '@kit.ArkUI';
import { HomePage } from './Home';
import { ProxiesPage } from './Proxies';
import { ProfilesPage } from './Profiles';
import { SettingsPage } from './Settings';

@Entry
@Component
struct MainPage {
  @State currentIndex: number = 0;
  private navItems: Array<NavItem> = [
    { title: '首页', icon: '\uE6AE', page: 'pages/Home' },
    { title: '代理', icon: '\uE6A8', page: 'pages/Proxies' },
    { title: '订阅', icon: '\uE726', page: 'pages/Profiles' },
    { title: '设置', icon: '\uE6F0', page: 'pages/Settings' },
    { title: '连接(M2)', icon: '\uE6B4', page: '' },
    { title: '规则(M2)', icon: '\uE6D9', page: '' },
    { title: '日志(M2)', icon: '\uE6DD', page: '' }
  ];

  build() {
    Row() {
      // 左侧导航栏
      Column() {
        Text('hmos-openvpn')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#007AFF')
          .margin({ top: 24, bottom: 24 })

        ForEach(this.navItems, (item: NavItem, index: number) => {
          Row() {
            Text(item.icon)
              .fontSize(20)
              .fontColor(this.currentIndex === index ? '#007AFF' : '#666666')
              .margin({ right: 12 })
            Text(item.title)
              .fontSize(14)
              .fontColor(this.currentIndex === index ? '#007AFF' : '#666666')
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
        }, (item: NavItem) => item.title)
      }
      .width(180)
      .height('100%')
      .backgroundColor('#F7F8FA')
      .alignItems(HorizontalAlign.Start)

      // 内容区
      Column() {
        Text(this.navItems[this.currentIndex].title)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .width('100%')
          .padding({ left: 24, top: 16, bottom: 16 })
        // 内容占位
        this.pageContent(this.currentIndex)
      }
      .layoutWeight(1)
      .height('100%')
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
    } else {
      SettingsPage()
    }
  }
}

interface NavItem {
  title: string;
  icon: string;
  page: string;
}
