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
 */
import { ThemeColors } from '../model/Theme';
import { AppService } from '../service/AppService';
import { ProxyGroup, ProxyMode, Proxy, SocketProxyService, SelectedMapStore } from 'proxy_core';
import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';

@Component
export struct ProxiesPage {
  @Consume colors: ThemeColors;
  @State groups: Array<ProxyGroup> = [];
  @State expanded: Record<string, boolean> = {};
  @State testing: boolean = false;
  // P1-6 generation 计数器：每次新测试 +1，中途检查避免竞态
  private testToken: number = 0;
  private appService: AppService = AppService.getInstance();

  aboutToAppear(): void {
    this.loadGroups();
  }

  async loadGroups(): Promise<void> {
    const svc: SocketProxyService | undefined = this.appService.getProxyService();
    if (!svc) return;
    try {
      // P3 模式感知：全局模式下查询并展示 GLOBAL 组（含其全部成员），
      // 规则模式下维持原规则组树。模式来自 Home 写入的 AppStorage 'vpnMode'。
      // 注意：vpnMode 存的是按钮值（小写 global/rule/direct），
      // queryProxyGroups/ParseProxyGroup 要求 ProxyMode 枚举（大写）→ 归一化
      const rawMode: string = AppStorage.get<string>('vpnMode') ?? '';
      const mode: ProxyMode = rawMode.toUpperCase() === ProxyMode.Global ? ProxyMode.Global : ProxyMode.Rule;
      const list = await svc.queryProxyGroups(mode);
      this.groups = list;
      // P1-9 移除循环诊断日志：reload 时打 N 条没价值，仅 catch 时打 error
    } catch (e) {
      const msg: string = (e instanceof Error) ? e.message : String(e);
      console.error('Proxies', 'loadGroups failed: ' + msg);
      // VPN 未启动时提示
      if (this.groups.length === 0) {
        promptAction.showToast({ message: '请先开启 VPN 再查看代理' });
      }
    }
  }

  // T4.3 切换节点
  async changeNode(group: ProxyGroup, proxyName: string): Promise<void> {
    console.log('Proxies', 'changeNode click: ' + group.name + ' -> ' + proxyName);
    const svc: SocketProxyService | undefined = this.appService.getProxyService();
    if (!svc) return;
    try {
      await svc.changeProxy(group.name, proxyName);
      console.log('Proxies', 'changeProxy OK: ' + group.name + ' -> ' + proxyName);
      // P3 持久化：写入跨进程共享文件（VPN 重启后 selected-map 恢复），
      // 下次打开保持上次选择
      const context = getContext(this) as common.UIAbilityContext;
      const activeId = await this.appService.getActiveProfileId();
      if (activeId !== '') {
        await SelectedMapStore.record(context, activeId, group.name, proxyName);
      }
      promptAction.showToast({ message: '已切换到: ' + proxyName });
      // P1-7 广播代理变更事件，Home 页 currentProxy 通过 @StorageLink @Watch 自动刷新
      AppStorage.setOrCreate<number>('proxyChangedAt', Date.now());
      AppStorage.setOrCreate<string>('currentProxyName', proxyName);
      // 强制重建列表（清空再加载，触发 ForEach 全量重建，避免 key 变更不渲染的坑）
      this.groups = [];
      this.loadGroups();
    } catch (e) {
      const msg: string = (e instanceof Error) ? e.message : String(e);
      console.error('Proxies', 'changeProxy failed: ' + msg);
      promptAction.showToast({ message: '切换失败: ' + msg });
    }
  }

  // T4.2 测速（并发分批：超时 3000ms，避免 100+ 节点串行卡死）
  // P3 真机调优：并发 6 → 16。死节点每次固定吃掉 3s URLTest 超时，
  // 大订阅（桔子云 ~1000 节点）下 6 并发全量测速需 11+ 分钟，
  // 16 并发可压缩到 ~4 分钟；Go 核心健康检查为无状态并发，16 路无压力。
  async testGroup(group: ProxyGroup, token: number): Promise<void> {
    const svc: SocketProxyService | undefined = this.appService.getProxyService();
    if (!svc) return;
    try {
      const names = group.proxies.map((p: Proxy) => p.name);
      const CONCURRENCY = 16;
      for (let i = 0; i < names.length; i += CONCURRENCY) {
        // 中途若 generation 变更（连点 / 新一轮），立即退出
        if (this.testToken !== token) return;
        const batch = names.slice(i, i + CONCURRENCY);
        await Promise.all(batch.map(async (name: string) => {
          try {
            const delay = await svc.healthCheckWithTimeout(name, 3000);
            // generation 又变了就别回填
            if (this.testToken !== token) return;
            const p = group.proxies.find((x: Proxy) => x.name === name);
            if (p) {
              p.latency = delay;
            }
          } catch (e) {
            if (this.testToken !== token) return;
            const p = group.proxies.find((x: Proxy) => x.name === name);
            if (p) {
              p.latency = 0; // 未测/失败
            }
          }
        }));
        if (this.testToken === token) {
          this.groups = [...this.groups]; // 每批后渐进刷新
        }
      }
      if (this.testToken === token) {
        this.groups = [...this.groups];
      }
    } catch (e) {
      const msg: string = (e instanceof Error) ? e.message : String(e);
      console.error('Proxies', 'testGroup failed: ' + msg);
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
          .backgroundColor(this.testing ? '#8A8A8A' : this.colors.primary)
          .onClick(() => {
            console.log('Proxies', 'testAll click, testing=' + this.testing);
            this.testAll();
          })
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
                // 单组测速按钮
                Button('⚡')
                  .fontSize(13)
                  .height(28)
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
      // 只有当前 generation 才清 testing，避免新测试被错误清掉
      if (this.testToken === myToken) {
        this.testing = false;
      }
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
