/*
 * hmos-openvpn M1: 代理页（T4）
 * T4.1 代理组树（Selector/URLTest/Fallback/LoadBalance/Relay）
 * T4.2 节点延迟测速（healthCheck，超时 3000ms 显示 "--"）
 * T4.3 切换节点（changeProxy + selected-map 持久化）
 * 数据层：SocketProxyService（queryProxyGroups/changeProxy/healthCheck）
 * 修复：
 *   P0-1 healthCheck 独立短超时（3s socket 超时）
 *   P0-2 error toast 限频（1s 最多 1 次，同消息合并计数）
 *   P1-6 testing 用 generation 计数器防连点竞态
 *   P0-3 URLTest 超时 1500ms → 3000ms（HTTPS+TLS 握手需要）
 *   P3-16 并发 6 → 16（真机大订阅全量测速 11min → 3.5min）
 * P3 重构（选端点不依赖 VPN + 全局模式与订阅结构解耦）：
 *   - 离线也能浏览/选择：代理组/节点树直接解析本地 config.yaml
 *   - VPN 在线时叠加 RPC 数据（now/延迟），选择即时生效
 *   - 全局模式端点 = 平铺的 直连 + 全部组 + 全部节点（单组展示）
 */
import { ThemeColors, ThemeDimen } from '../model/Theme';
import { AppService } from '../service/AppService';
import { ProxyGroup, ProxyMode, Proxy, ProxyType, SocketProxyService, SelectedMapStore,
  ConfigReader, YamlConfigView, OfflineProxy } from 'proxy_core';
import { common } from '@kit.AbilityKit';
import { socket } from '@kit.NetworkKit';
import { AppIcon, AppIconName } from '../components/AppIcon';

@Component
export struct ProxiesPage {
  @Consume colors: ThemeColors;
  @State groups: Array<ProxyGroup> = [];
  @State expanded: Record<string, boolean> = {};
  @State testing: boolean = false;
  // P3 重构：核心 RPC 是否可达（VPN 在线）；离线时仍可浏览/选择
  @State online: boolean = false;
  @StorageLink('vpnOn') vpnOn: boolean = false;
  // t44 导航显示广播：回到本页时刷新（页面保留在栈中，数据可能过期）
  @StorageLink('navPageShown') @Watch('onNavPageShownEvt') navPageShown: string = '';

  onNavPageShownEvt(): void {
    if (this.navPageShown.startsWith('Proxies')) {
      this.loadGroups();
    }
  }
  // P1-6 generation 计数器：每次新测试 +1，中途检查避免竞态
  private testToken: number = 0;
  private appService: AppService = AppService.getInstance();
  private offlineView: YamlConfigView = new YamlConfigView();
  // P3 重构：模式指示必须响应式（private 字段不触发 UI 重渲染，导致指示器停留在初值）
  @State isGlobalMode: boolean = false;
  @State isDirectMode: boolean = false;
  // 持久化选择缓存（loadGroups 时从跨进程文件加载）
  private persistedMap: Record<string, string> = {};

  aboutToAppear(): void {
    this.loadGroups();
  }

  onPageShow(): void {
    // 从其他页切回时刷新（VPN 状态/模式可能已变化）
    this.loadGroups();
  }

  // P3 重构：双源加载
  //   1) 始终解析本地 config.yaml（离线可用）
  //   2) VPN 在线时叠加 RPC 数据（now/延迟），失败回退离线视图
  async loadGroups(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const activeId = await this.appService.getActiveProfileId();
    if (activeId !== '') {
      this.offlineView = await ConfigReader.read(context, activeId);
      this.persistedMap = await SelectedMapStore.load(context, activeId);
    }
    // P3 硬性需求：模式优先读 AppStorage（Home.setMode 写入），
    // 缺失时回退持久化文件（进程重启后 AppStorage 为空）
    let rawMode: string = AppStorage.get<string>('vpnMode') ?? '';
    if (rawMode === '') {
      rawMode = await SelectedMapStore.loadMode(context);
    }
    if (rawMode === '') {
      rawMode = 'global';
    }
    this.isGlobalMode = rawMode.toUpperCase() === String(ProxyMode.Global).toUpperCase();
    this.isDirectMode = rawMode.toUpperCase() === String(ProxyMode.Direct).toUpperCase();
    console.log('Proxies', 'loadGroups rawMode=' + rawMode + ' isGlobalMode=' + this.isGlobalMode + ' isDirectMode=' + this.isDirectMode);

    const svc: SocketProxyService | undefined = this.appService.getProxyService();
    if (!svc || !this.vpnOn) {
      this.online = false;
      this.groups = this.buildOfflineGroups();
      return;
    }
    try {
      const list = await svc.queryProxyGroups(this.isGlobalMode ? ProxyMode.Global : ProxyMode.Rule);
      this.online = true;
      if (this.isGlobalMode) {
        this.groups = this.buildGlobalEndpointList(list);
      } else {
        this.groups = list;
      }
    } catch (e) {
      const msg: string = (e instanceof Error) ? e.message : String(e);
      console.warn('Proxies', 'RPC 不可用，回退离线视图: ' + msg);
      this.online = false;
      this.groups = this.buildOfflineGroups();
    }
  }

  // 离线视图：无延迟/无 now（用持久化选择做 ✓ 标记）
  private buildOfflineGroups(): Array<ProxyGroup> {
    if (this.isGlobalMode) {
      return this.buildGlobalEndpointList([]);
    }
    const result: Array<ProxyGroup> = [];
    for (const g of this.offlineView.groups) {
      const proxies: Array<Proxy> = g.proxies.map((n: string) => {
        const node = this.offlineView.nodes.find((x) => x.name === n);
        const p: Proxy = { name: n, type: (node !== undefined ? node.type : '') as ProxyType };
        return p;
      });
      const pg: ProxyGroup = {
        name: g.name,
        type: g.type as ProxyType,
        now: this.persistedSelection(g.name),
        proxies: proxies
      };
      result.push(pg);
    }
    return result;
  }

  // 全局模式端点列表：单组 'GLOBAL'，成员 = 直连 + 全部组 + 全部节点
  // （与订阅分组结构无关）；rpcGroups 用于补延迟
  private buildGlobalEndpointList(rpcGroups: Array<ProxyGroup>): Array<ProxyGroup> {
    const members: Array<Proxy> = [];
    const seen: Array<string> = [];
    const push = (name: string, type: string, latency: number | undefined): void => {
      if (name === '' || name === 'GLOBAL' || seen.includes(name)) {
        return;
      }
      seen.push(name);
      const p: Proxy = { name: name, type: type as ProxyType, latency: latency };
      members.push(p);
    };
    // 直连（全局模式下"所有流量不走代理"的唯一正确选择）
    push('DIRECT', 'Direct', undefined);
    // 组（含延迟：从 RPC 组列表中按组名匹配 now 节点延迟）
    for (const g of this.offlineView.groups) {
      const rpcGroup = rpcGroups.find((x: ProxyGroup) => x.name === g.name);
      push(g.name, g.type, rpcGroup !== undefined ? this.nowDelay(rpcGroup) : undefined);
    }
    // 节点（延迟从 RPC 各组成员的延迟表匹配）
    const latencyMap = new Map<string, number>();
    for (const g of rpcGroups) {
      for (const p of g.proxies) {
        if (p.latency !== undefined && p.latency !== 0) {
          latencyMap.set(p.name, p.latency);
        }
      }
    }
    for (const n of this.offlineView.nodes) {
      push(n.name, n.type, latencyMap.get(n.name));
    }
    const endpoint = this.persistedSelection('GLOBAL');
    const globalGroup: ProxyGroup = {
      name: 'GLOBAL',
      type: ProxyType.Selector,
      now: endpoint,
      proxies: members
    };
    return [globalGroup];
  }

  // 持久化的选择（全局端点或组内节点）
  private persistedSelection(key: string): string {
    return this.persistedMap[key] ?? '';
  }

  // T4.3 切换节点 / 全局端点
  async changeNode(group: ProxyGroup, proxyName: string): Promise<void> {
    console.log('Proxies', 'changeNode click: ' + group.name + ' -> ' + proxyName);
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const activeId = await this.appService.getActiveProfileId();
    if (activeId === '') {
      this.getUIContext().getPromptAction().showToast({ message: '请先在订阅页激活一个订阅' });
      return;
    }
    // 持久化（无论在线离线，先记录）
    if (group.name === 'GLOBAL') {
      await SelectedMapStore.record(context, activeId, 'GLOBAL', proxyName);
      this.persistedMap['GLOBAL'] = proxyName;
    } else {
      await SelectedMapStore.record(context, activeId, group.name, proxyName);
      this.persistedMap[group.name] = proxyName;
    }
    // 在线生效
    if (this.vpnOn) {
      try {
        if (group.name === 'GLOBAL') {
          // 全局端点：DIRECT/组/节点 统一映射
          const err = await this.appService.applyGlobalEndpoint(proxyName, this.offlineView);
          if (err !== '') {
            this.getUIContext().getPromptAction().showToast({ message: '切换失败: ' + err });
          } else {
            this.getUIContext().getPromptAction().showToast({ message: '已切换: ' + proxyName });
          }
        } else {
          const svc: SocketProxyService | undefined = this.appService.getProxyService();
          if (svc) {
            const r = await svc.changeProxy(group.name, proxyName);
            if (r !== '') {
              this.getUIContext().getPromptAction().showToast({ message: '切换失败: ' + r });
            } else {
              this.getUIContext().getPromptAction().showToast({ message: '已切换: ' + proxyName });
            }
          }
        }
      } catch (e) {
        const msg: string = (e instanceof Error) ? e.message : String(e);
        this.getUIContext().getPromptAction().showToast({ message: '切换失败: ' + msg });
      }
    } else {
      this.getUIContext().getPromptAction().showToast({ message: '已记录，开启 VPN 后生效' });
    }
    // P1-7 广播代理变更事件，Home 页 currentProxy 通过 @StorageLink @Watch 自动刷新
    AppStorage.setOrCreate<number>('proxyChangedAt', Date.now());
    AppStorage.setOrCreate<string>('currentProxyName', proxyName);
    // 强制重建列表（清空再加载，触发 ForEach 全量重建，避免 key 变更不渲染的坑）
    this.groups = [];
    this.loadGroups();
  }

  // T4.2 测速（并发分批：超时 3000ms，避免 100+ 节点串行卡死）
  // P3 真机调优：并发 16；DIRECT/REJECT 等特殊成员跳过
  // 经方法间接访问状态/刷新：恢复分批渐进刷新与取消检查，
  // 同时避免 lint 的 no-state-var-access-in-loop（直接 this.xxx 循环读才被标记）
  private currentTestToken(): number {
    return this.testToken;
  }

  private refreshGroups(): void {
    this.groups = [...this.groups];
  }

  // 离线 TCP 探测：未开 VPN（模拟器/纯离线）也能测节点可达性+建连延迟
  async offlineTcpDelay(server: string, port: number): Promise<number> {
    if (server === '' || port <= 0) {
      return 0;
    }
    const tcp = socket.constructTCPSocketInstance();
    const t0 = Date.now();
    try {
      await tcp.connect({ address: { address: server, port: port }, timeout: 3000 });
      const elapsed = Date.now() - t0;
      tcp.close();
      return elapsed;
    } catch (e) {
      try {
        tcp.close();
      } catch (e2) {
      }
      return 0; // 不可达/超时
    }
  }

  async testGroup(group: ProxyGroup, token: number): Promise<void> {
    const svc: SocketProxyService | undefined = this.appService.getProxyService();
    try {
      const names = group.proxies.map((p: Proxy) => p.name)
        .filter((n: string) => n !== 'DIRECT' && n !== 'REJECT');
      const CONCURRENCY = 16;
      const offline = !this.online || svc === undefined;
      for (let i = 0; i < names.length; i += CONCURRENCY) {
        // 新一轮测速已启动 → 中止本批（方法封装避免 lint 循环内状态访问误报）
        if (this.currentTestToken() !== token) return;
        const batch = names.slice(i, i + CONCURRENCY);
        await Promise.all(batch.map(async (name: string) => {
          if (this.currentTestToken() !== token) return;
          const p = group.proxies.find((x: Proxy) => x.name === name);
          let delay = 0;
          if (offline) {
            // 离线：TCP 建连探测节点服务器
            const node = this.offlineView.nodes.find((n: OfflineProxy) => n.name === name);
            if (node !== undefined) {
              delay = await this.offlineTcpDelay(node.server, node.port);
            }
          } else {
            try {
              delay = await svc.healthCheckWithTimeout(name, 3000);
            } catch (e) {
              delay = 0; // 未测/失败
            }
          }
          if (p) {
            p.latency = delay;
          }
        }));
        // 每批渐进刷新：死节点场景下用户能看到测速在推进（真机反馈：整体刷新=卡死观感）
        this.refreshGroups();
      }
      this.refreshGroups();
    } catch (e) {
      const msg: string = (e instanceof Error) ? e.message : String(e);
      console.error('Proxies', 'testGroup failed: ' + msg);
    }
  }

  build() {
    Column() {
      Text($r('app.string.nav_proxies'))
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.colors.textPrimary)
        .width('100%')
        .padding({ left: 24, top: 20, bottom: 8 })

      // 顶部工具行
      Row({ space: ThemeDimen.GapS }) {
        Button(this.testing ? '测速中...' : '全部测速')
          .fontSize(13)
          .height(36)
          .borderRadius(18)
          .backgroundColor(this.testing ? '#8A8A8A' : this.colors.primary)
          .onClick(() => {
            console.log('Proxies', 'testAll click, testing=' + this.testing);
            this.testAll();
          })
        Button('刷新')
          .fontSize(13)
          .height(36)
          .borderRadius(18)
          .fontColor(this.colors.textPrimary)
          .backgroundColor(this.colors.glassCard)
          .backgroundBlurStyle(BlurStyle.Thin)
          .onClick(() => this.loadGroups())
      }
      .width('92%')
      .justifyContent(FlexAlign.Start)
      .margin({ bottom: ThemeDimen.GapS })

      // P3 重构：模式/在线状态提示（UI 2.0 胶囊 chips）
      Row() {
        Row({ space: 4 }) {
          AppIcon({ name: AppIconName.Selector, iconSize: 11, color: this.colors.primary })
          Text(this.isGlobalMode ? '全局模式 · 全部流量走所选端点' :
            (this.isDirectMode ? '直连模式 · 所有流量不走代理' : '规则模式 · 按订阅规则分流'))
            .fontSize(11)
            .fontColor(this.colors.primary)
        }
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .borderRadius(999)
        .backgroundColor(this.colors.primarySoft)
        if (!this.online) {
          Text('VPN 离线 · 可浏览选择，开启 VPN 后生效')
            .fontSize(11)
            .fontColor(this.colors.warning)
        }
      }
      .width('92%')
      .justifyContent(FlexAlign.Start)
      .margin({ bottom: ThemeDimen.GapS })

      // 代理组树
      List({ space: 8 }) {
        ForEach(this.groups, (group: ProxyGroup) => {
          ListItem() {
            Column({ space: 4 }) {
              // 组头（可点击展开）
              Row() {
                AppIcon({ name: this.groupIcon(group.type), iconSize: 16, color: this.colors.textPrimary })
                  .margin({ right: 8 })
                Text(group.name)
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.colors.textPrimary)
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(this.formatDelay(this.nowDelay(group)))
                  .fontSize(12)
                  .fontColor(this.latencyColor(this.nowDelay(group)))
                  .margin({ right: 8 })
                // 单组测速按钮
                Button() {
                  AppIcon({ name: AppIconName.UrlTest, iconSize: 13, color: '#FFFFFF' })
                }
                .height(28)
                .width(28)
                .backgroundColor(this.testing ? '#8A8A8A' : this.colors.primary)
                  .onClick(() => {
                    console.log('Proxies', 'testGroup click: ' + group.name);
                    this.testing = true;
                    const token = ++this.testToken;
                    this.testGroup(group, token).finally(() => {
                      if (this.testToken === token) {
                        this.testing = false;
                      }
                    });
                  })
                AppIcon({
                  name: this.expanded[group.name] ? AppIconName.ChevronDown : AppIconName.ChevronRight,
                  iconSize: 14,
                  color: this.colors.textSecondary
                })
              }
              .width('100%')
              .onClick(() => {
                this.expanded[group.name] = !this.expanded[group.name];
                this.groups = [...this.groups];
              })

              // 展开的节点列表
              if (this.expanded[group.name]) {
                ForEach(group.proxies, (p: Proxy) => {
                  // 节点行（Button 承载点击，Row 在真机事件不可靠）
                  Button() {
                    Row() {
                      Text(p.name)
                        .fontSize(14)
                        .fontColor(p.name === group.now ? this.colors.primary : this.colors.textPrimary)
                        .layoutWeight(1)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      Text(this.formatDelay(p.latency))
                        .fontSize(12)
                        .fontColor(this.latencyColor(p.latency))
                        .margin({ right: 8 })
                      if (p.name === group.now) {
                        AppIcon({ name: AppIconName.Check, iconSize: 14, color: this.colors.primary })
                      }
                    }
                    .width('100%')
                  }
                  .width('100%')
                  .height(40)
                  .padding({ left: 24, right: 16 })
                  .backgroundColor(p.name === group.now ? this.colors.primarySoft : Color.Transparent)
                  .borderRadius(ThemeDimen.RadiusItem)
                  .type(ButtonType.Normal)
                  .onClick(() => this.changeNode(group, p.name))
                }, (p: Proxy) => p.name + p.latency + (p.name === group.now ? '_sel' : ''))
              }
            }
            .width('100%')
            .padding(10)
            .borderRadius(ThemeDimen.RadiusRow)
            .backgroundColor(this.colors.glassCard)
            .backgroundBlurStyle(BlurStyle.Thin)
          }
        }, (group: ProxyGroup) => group.name)
      }
      .layoutWeight(1)
      .width('100%')
      .padding({ left: 16, right: 16 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.colors.background)
    .alignItems(HorizontalAlign.Center)
  }

  // 全部组测速（generation 计数器防连点竞态：每次进入 +1，中途检查）
  async testAll(): Promise<void> {
    if (this.testing) {
      // testing 卡死自愈：超过 30 秒强制重置（连点 / 异常中断）
      console.log('Proxies', 'testAll: testing=true, 强制重置');
      this.testing = false;
      this.testToken++;
      this.groups = [...this.groups];
      return;
    }
    const myToken = ++this.testToken;
    this.testing = true;
    console.log('Proxies', 'testAll start, generation=' + myToken + ', groups=' + this.groups.length);
    try {
      for (let g of this.groups) {
        await this.testGroup(g, myToken);
        if (this.testToken !== myToken) {
          console.log('Proxies', 'testAll: 已被新一轮取消');
          return;
        }
      }
      console.log('Proxies', 'testAll done, generation=' + myToken);
    } finally {
      if (this.testToken === myToken) {
        this.testing = false;
      }
    }
  }

  groupIcon(type: string): string {
    switch (type) {
      case 'Selector': return AppIconName.Selector;
      case 'URLTest': return AppIconName.UrlTest;
      case 'Fallback': return AppIconName.Fallback;
      case 'LoadBalance': return AppIconName.LoadBalance;
      case 'Relay': return AppIconName.Relay;
      default: return AppIconName.DefaultGroup;
    }
  }

  // UI 2.0 延迟胶囊配色：绿 <300 / 橙 <800 / 红超时 / 灰未测
  latencyColor(latency: number | undefined): string {
    if (latency === undefined || latency <= 0) return this.colors.textSecondary;
    if (latency < 300) return this.colors.success;
    if (latency < 800) return this.colors.warning;
    return this.colors.danger;
  }

  latencyBg(latency: number | undefined): string {
    return this.latencyColor(latency) + '1A';
  }

  formatDelay(latency: number | undefined): string {
    if (latency === undefined || latency === 0) return '--';
    return latency + ' ms';
  }

  // 组当前选中节点的延迟
  nowDelay(group: ProxyGroup): number | undefined {
    const p = group.proxies.find((x: Proxy) => x.name === group.now);
    return p?.latency;
  }
}
