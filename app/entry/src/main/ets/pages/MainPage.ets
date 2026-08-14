/*
 * hmos-openvpn M1: 主框架页（左侧导航栏 + 内容区）
 * 对齐 Clash Verge _layout.tsx：左侧导航栏 + 内容区
 * 导航项用 Button 组件（onClick 绑定可靠，Row 在真机有事件失效问题）
 * P3-15（t44）Navigation/NavDestination 迁移：
 *   - 页面保留在路由栈中（切页不销毁：轮询/滚动/搜索状态保留）
 *   - 侧栏点击：栈中已有该页 → popToIndex 回到栈顶；没有 → pushPathByName
 *   - onShown/onHidden 经 AppStorage 广播，页面 @Watch 做刷新/暂停
 *     （兼容 NavDestination 下 onPageShow/onPageHide 的生命周期语义变化）
 */
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { HomePage } from './Home';
import { ProxiesPage } from './Proxies';
import { ProfilesPage } from './Profiles';
import { SettingsPage } from './Settings';
import { ConnectionsPage } from './Connections';
import { RulesPage } from './Rules';
import { LogsPage } from './Logs';
import { UnlockPage } from './Unlock';
import { ThemeColors, ThemeManager } from '../model/Theme';
import { CoreState } from '../model/CoreState';
import { AppService } from '../service/AppService';
import { SettingsRepository } from '../repository/SettingsRepository';

@Entry
@Component
struct MainPage {
  @State currentIndex: number = 0;
  // M2 折叠态降级：窄屏（折叠）时侧栏降级为图标栏（宽 64、隐藏文字）
  @State compact: boolean = false;
  @Provide colors: ThemeColors = ThemeManager.lightColors;
  @Provide coreState: CoreState = new CoreState();
  @Provide('pathStack') pathStack: NavPathStack = new NavPathStack();
  // M3-2 主题变更广播（Settings 切主题/系统深浅色变化时触发重新解析配色）
  @StorageLink('themeChanged') @Watch('onThemeChanged') themeChanged: number = 0;
  private appService: AppService = AppService.getInstance();

  onThemeChanged(): void {
    this.applyTheme();
  }

  // M3-2 按 模式×自定义主色 解析并应用配色（修复原 getColors 无调用方、colors 恒浅色的问题）
  applyTheme(): void {
    const context = getContext(this) as common.UIAbilityContext;
    const isDark = context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    SettingsRepository.getInstance().getThemeColor().then((custom: string) => {
      this.colors = ThemeManager.getColors(isDark, custom);
    });
  }
  private navItems: Array<NavItem> = [
    { titleKey: 'nav_home', icon: '\uE6AE', pageName: 'Home' },
    { titleKey: 'nav_proxies', icon: '\uE6A8', pageName: 'Proxies' },
    { titleKey: 'nav_profiles', icon: '\uE726', pageName: 'Profiles' },
    { titleKey: 'nav_settings', icon: '\uE6F0', pageName: 'Settings' },
    { titleKey: 'nav_connections', icon: '\uE6B4', pageName: 'Connections' },
    { titleKey: 'nav_rules', icon: '\uE6D9', pageName: 'Rules' },
    { titleKey: 'nav_logs', icon: '\uE6DD', pageName: 'Logs' },
    { titleKey: 'nav_unlock', icon: '🎬', pageName: 'Unlock' }
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
    this.applyTheme();
    // t44 初始页推入（栈空时）
    if (this.pathStack.getIndexByName('Home').length === 0) {
      this.pathStack.pushPathByName('Home', null);
    }
  }

  // t44 侧栏导航：栈中已有该页 → 回到栈顶（保留状态）；没有 → 推入（首次加载刷新数据）
  onNavClick(index: number): void {
    console.log('NAV', 'click index=' + index + ' key=' + this.navItems[index].titleKey);
    this.currentIndex = index;
    const name = this.navItems[index].pageName;
    const indices = this.pathStack.getIndexByName(name);
    if (indices.length > 0) {
      this.pathStack.popToIndex(indices[indices.length - 1]);
    } else {
      this.pathStack.pushPathByName(name, null);
    }
  }

  // t44 页面显示/隐藏广播（AppStorage），页面侧 @Watch 处理刷新/暂停
  private onPageShown(name: string): void {
    AppStorage.setOrCreate('navPageShown', name + '_' + Date.now());
  }

  private onPageHidden(name: string): void {
    AppStorage.setOrCreate('navPageHidden', name + '_' + Date.now());
  }

  @Builder
  pageMap(name: string) {
    if (name === 'Home') {
      NavDestination() {
        HomePage()
      }
      .onShown(() => this.onPageShown('Home'))
      .onHidden(() => this.onPageHidden('Home'))
    } else if (name === 'Proxies') {
      NavDestination() {
        ProxiesPage()
      }
      .onShown(() => this.onPageShown('Proxies'))
      .onHidden(() => this.onPageHidden('Proxies'))
    } else if (name === 'Profiles') {
      NavDestination() {
        ProfilesPage()
      }
      .onShown(() => this.onPageShown('Profiles'))
      .onHidden(() => this.onPageHidden('Profiles'))
    } else if (name === 'Settings') {
      NavDestination() {
        SettingsPage()
      }
      .onShown(() => this.onPageShown('Settings'))
      .onHidden(() => this.onPageHidden('Settings'))
    } else if (name === 'Connections') {
      NavDestination() {
        ConnectionsPage()
      }
      .onShown(() => this.onPageShown('Connections'))
      .onHidden(() => this.onPageHidden('Connections'))
    } else if (name === 'Rules') {
      NavDestination() {
        RulesPage()
      }
      .onShown(() => this.onPageShown('Rules'))
      .onHidden(() => this.onPageHidden('Rules'))
    } else if (name === 'Logs') {
      NavDestination() {
        LogsPage()
      }
      .onShown(() => this.onPageShown('Logs'))
      .onHidden(() => this.onPageHidden('Logs'))
    } else if (name === 'Unlock') {
      NavDestination() {
        UnlockPage()
      }
      .onShown(() => this.onPageShown('Unlock'))
      .onHidden(() => this.onPageHidden('Unlock'))
    }
  }

  build() {
    Navigation(this.pathStack) {
      // 左侧导航栏（M2 折叠态：窄屏降级为图标栏）
      Column() {
        Text(this.compact ? '✈' : 'hmos-openvpn')
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
              if (!this.compact) {
                Text($r('app.string.' + item.titleKey))
                  .fontSize(14)
                  .fontColor(this.currentIndex === index ? '#007AFF' : '#666666')
              }
            }
            .width('100%')
            .justifyContent(this.compact ? FlexAlign.Center : FlexAlign.Start)
            .padding({ left: this.compact ? 0 : 20 })
          }
          .width('100%')
          .height(44)
          .type(ButtonType.Normal)
          .backgroundColor(this.currentIndex === index ? '#E8F2FF' : Color.Transparent)
          .borderRadius(8)
          .onClick(() => this.onNavClick(index))
        }, (item: NavItem) => item.titleKey)
      }
      .width(this.compact ? 64 : 180)
      .height('100%')
      .backgroundColor(this.colors.background)
      .alignItems(this.compact ? HorizontalAlign.Center : HorizontalAlign.Start)
    }
    .mode(NavigationMode.Split)
    // 注意：不能用 hideNavBar(true)——会把 Split 模式的菜单栏（我们的侧栏）整个隐藏
    .navBarWidth(this.compact ? 64 : 180)
    .navDestination(this.pageMap)
    .width('100%')
    .height('100%')
    .onAreaChange((_old: Area, newArea: Area) => {
      // 折叠态阈值：宽度 < 640vp 视为折叠窄屏
      const w = Number(newArea.width);
      // 阈值 480vp：Pura 展开态(~530vp)保持完整侧栏；折叠/窄屏(~360vp)走图标栏
      const isCompact = w < 480;
      if (isCompact !== this.compact) {
        this.compact = isCompact;
      }
    })
  }
}

interface NavItem {
  titleKey: string;
  icon: string;
  pageName: string;
}
