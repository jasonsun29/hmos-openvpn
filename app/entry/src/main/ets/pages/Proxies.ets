/*
 * hmos-openvpn M1: 代理页（T4）
 * T4.1 代理组树（Selector/URLTest/Fallback/LoadBalance/Relay）
 * T4.2 节点延迟测速（healthCheck，超时 5000ms 显示 "--"）
 * T4.3 切换节点（changeProxy + selected-map 持久化）
 * 数据层：SocketProxyService（queryProxyGroups/changeProxy/healthCheck）
 */
import { ThemeColors } from '../model/Theme';
import { AppService } from '../service/AppService';
import { ProxyGroup, ProxyMode, Proxy, SocketProxyService } from 'proxy_core';
import { promptAction } from '@kit.ArkUI';

@Component
export struct ProxiesPage {
  @Consume colors: ThemeColors;
  @State groups: Array<ProxyGroup> = [];
  @State expanded: Record<string, boolean> = {};
  @State testing: boolean = false;
  private appService: AppService = AppService.getInstance();

  aboutToAppear(): void {
    this.loadGroups();
  }

  async loadGroups(): Promise<void> {
    const svc: SocketProxyService | undefined = this.appService.getProxyService();
    if (!svc) return;
    try {
      // M1 用 Rule 模式展示代理组
      const list = await svc.queryProxyGroups(ProxyMode.Rule);
      this.groups = list;
      // T4 诊断：打印每组 now
      for (let g of list) {
        console.log('T4', 'group now: ' + g.name + ' = ' + g.now);
      }
    } catch (e) {
      const msg: string = (e instanceof Error) ? e.message : String(e);
      console.error('T4', 'loadGroups failed: ' + msg);
      // VPN 未启动时提示
      if (this.groups.length === 0) {
        promptAction.showToast({ message: '请先开启 VPN 再查看代理' });
      }
    }
  }

  // T4.3 切换节点
  async changeNode(group: ProxyGroup, proxyName: string): Promise<void> {
    console.log('T4', 'changeNode click: ' + group.name + ' -> ' + proxyName);
    const svc: SocketProxyService | undefined = this.appService.getProxyService();
    if (!svc) return;
    try {
      await svc.changeProxy(group.name, proxyName);
      console.log('T4', 'changeProxy OK: ' + group.name + ' -> ' + proxyName);
      promptAction.showToast({ message: '已切换到: ' + proxyName });
      // 强制重建列表（清空再加载，触发 ForEach 全量重建，避免 key 变更不渲染的坑）
      this.groups = [];
      this.loadGroups();
    } catch (e) {
      const msg: string = (e instanceof Error) ? e.message : String(e);
      console.error('T4', 'changeProxy failed: ' + msg);
      promptAction.showToast({ message: '切换失败: ' + msg });
    }
  }

  // T4.2 测速（组级并发，healthCheck 单节点）
  async testGroup(group: ProxyGroup): Promise<void> {
    const svc: SocketProxyService | undefined = this.appService.getProxyService();
    if (!svc) return;
    this.testing = true;
    try {
      const names = group.proxies.map((p: Proxy) => p.name);
      for (let i = 0; i < names.length; i++) {
        const name = names[i];
        try {
          const delay = await svc.healthCheck(name);
          const p = group.proxies.find((x: Proxy) => x.name === name);
          if (p) {
            p.latency = delay;
          }
        } catch (e) {
          const p = group.proxies.find((x: Proxy) => x.name === name);
          if (p) {
            p.latency = 0; // 未测/失败
          }
        }
        if (i % 5 === 0) {
          this.groups = [...this.groups]; // 渐进刷新
        }
      }
      this.groups = [...this.groups];
    } finally {
      this.testing = false;
    }
  }

  build() {
    Column() {
      Text($r('app.string.nav_proxies'))
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.colors.textPrimary)
        .width('100%')
        .padding({ left: 24, top: 16, bottom: 8 })

      // 顶部工具行
      Row() {
        Button(this.testing ? '测速中...' : '全部测速')
          .fontSize(13)
          .height(36)
          .backgroundColor(this.colors.primary)
          .enabled(!this.testing)
          .onClick(() => this.testAll())
        Button('刷新')
          .fontSize(13)
          .height(36)
          .backgroundColor(this.colors.textSecondary)
          .onClick(() => this.loadGroups())
      }
      .width('92%')
      .margin({ bottom: 8 })

      // 代理组树
      List({ space: 8 }) {
        ForEach(this.groups, (group: ProxyGroup) => {
          ListItem() {
            Column({ space: 4 }) {
              // 组头（可点击展开）
              Row() {
                Text(this.groupIcon(group.type))
                  .fontSize(16)
                  .margin({ right: 8 })
                Text(group.name)
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.colors.textPrimary)
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(this.formatDelay(this.nowDelay(group)))
                  .fontSize(13)
                  .fontColor(this.colors.textSecondary)
                  .margin({ right: 8 })
                Text(this.expanded[group.name] ? '▾' : '▸')
                  .fontSize(14)
                  .fontColor(this.colors.textSecondary)
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
                        .fontColor(p.latency !== undefined && p.latency > 0 ? '#07C160' : this.colors.textSecondary)
                        .margin({ right: 8 })
                      if (p.name === group.now) {
                        Text('✓')
                          .fontSize(14)
                          .fontColor(this.colors.primary)
                      }
                    }
                    .width('100%')
                  }
                  .width('100%')
                  .height(44)
                  .padding({ left: 24, right: 16 })
                  .backgroundColor(p.name === group.now ? '#E8F2FF' : Color.Transparent)
                  .borderRadius(6)
                  .type(ButtonType.Normal)
                  .onClick(() => this.changeNode(group, p.name))
                }, (p: Proxy) => p.name + p.latency + (p.name === group.now ? '_sel' : ''))
              }
            }
            .width('100%')
            .padding(12)
            .borderRadius(12)
            .backgroundColor(this.colors.card)
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

  // 全部组测速
  async testAll(): Promise<void> {
    for (let g of this.groups) {
      await this.testGroup(g);
    }
  }

  groupIcon(type: string): string {
    switch (type) {
      case 'Selector': return '🔀';
      case 'URLTest': return '⚡';
      case 'Fallback': return '🛡';
      case 'LoadBalance': return '⚖';
      case 'Relay': return '🔗';
      default: return '📦';
    }
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
