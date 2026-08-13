/*
 * hmos-openvpn M2: 连接页（对齐 Clash Verge connections.tsx）
 * T9.1 连接列表（实时刷新 1s）
 * T9.2 断开单个连接 / 全部断开
 * 数据层：SocketProxyService.queryConnections/closeConnection/clearConnections
 */
import { ThemeColors } from '../model/Theme';
import { AppService } from '../service/AppService';
import { SocketProxyService, ConnectionInfo } from 'proxy_core';
import { promptAction } from '@kit.ArkUI';

@Component
export struct ConnectionsPage {
  @Consume colors: ThemeColors;
  @State connections: Array<ConnectionInfo> = [];
  @State totalUp: number = 0;
  @State totalDown: number = 0;
  // P3-6 搜索/过滤
  @State searchText: string = '';
  private appService: AppService = AppService.getInstance();
  private refreshTimer: number = -1;

  aboutToAppear(): void {
    this.refresh();
    this.refreshTimer = setInterval(() => {
      this.refresh();
    }, 1000);
  }

  aboutToDisappear(): void {
    if (this.refreshTimer !== -1) {
      clearInterval(this.refreshTimer);
      this.refreshTimer = -1;
    }
  }

  async refresh(): Promise<void> {
    const svc: SocketProxyService | undefined = this.appService.getProxyService();
    if (!svc) return;
    try {
      this.connections = await svc.queryConnections();
      let up = 0;
      let down = 0;
      for (let c of this.connections) {
        up += c.upload;
        down += c.download;
      }
      this.totalUp = up;
      this.totalDown = down;
    } catch (e) {
      // VPN 未开时静默
    }
  }

  async closeOne(id: string): Promise<void> {
    const svc: SocketProxyService | undefined = this.appService.getProxyService();
    if (!svc) return;
    try {
      svc.closeConnection(id);
      this.refresh();
    } catch (e) {
      promptAction.showToast({ message: '断开失败' });
    }
  }

  async closeAll(): Promise<void> {
    const svc: SocketProxyService | undefined = this.appService.getProxyService();
    if (!svc) return;
    try {
      svc.clearConnections();
      this.refresh();
    } catch (e) {
      promptAction.showToast({ message: '清空失败' });
    }
  }

  formatDuration(start: number): string {
    const sec = Math.floor((Date.now() - start) / 1000);
    if (sec < 60) return sec + 's';
    if (sec < 3600) return Math.floor(sec / 60) + 'm' + (sec % 60) + 's';
    return Math.floor(sec / 3600) + 'h' + Math.floor((sec % 3600) / 60) + 'm';
  }

  // P3-6 按 host / 规则过滤
  private filtered(): Array<ConnectionInfo> {
    if (this.searchText === '') {
      return this.connections;
    }
    const kw = this.searchText.toLowerCase();
    return this.connections.filter((c: ConnectionInfo) =>
      this.hostOf(c).toLowerCase().includes(kw) ||
      (c.rule ?? '').toLowerCase().includes(kw));
  }

  build() {
    Column() {
      // 顶部汇总
      Row() {
        Text('连接 (' + this.connections.length + ')')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.colors.textPrimary)
          .layoutWeight(1)
        Text('↑ ' + AppService.formatBytes(this.totalUp) + '  ↓ ' + AppService.formatBytes(this.totalDown))
          .fontSize(13)
          .fontColor(this.colors.textSecondary)
        Button('全部断开')
          .fontSize(12)
          .height(32)
          .backgroundColor('#FF3B30')
          .margin({ left: 8 })
          .onClick(() => this.closeAll())
      }
      .width('100%')
      .padding({ left: 24, top: 16, right: 24, bottom: 8 })

      // P3-6 搜索框（按 host / 规则过滤）
      Row() {
        TextInput({ placeholder: '搜索 host / 规则', text: this.searchText })
          .width('92%')
          .height(36)
          .onChange((v: string) => { this.searchText = v; })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .margin({ bottom: 8 })

      // 连接列表
      List({ space: 6 }) {
        ForEach(this.filtered(), (c: ConnectionInfo) => {
          ListItem() {
            Row() {
              Column({ space: 2 }) {
                // 目标地址
                Text(this.hostOf(c))
                  .fontSize(14)
                  .fontColor(this.colors.textPrimary)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Row({ space: 8 }) {
                  Text(c.rule ?? '--')
                    .fontSize(11)
                    .fontColor(this.colors.primary)
                  Text(this.formatDuration(c.start))
                    .fontSize(11)
                    .fontColor(this.colors.textSecondary)
                  Text('↑ ' + AppService.formatBytes(c.upload) + ' ↓ ' + AppService.formatBytes(c.download))
                    .fontSize(11)
                    .fontColor(this.colors.textSecondary)
                }
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Button('断开')
                .fontSize(11)
                .height(28)
                .backgroundColor('#FF3B30')
                .onClick(() => this.closeOne(c.id))
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 10, bottom: 10 })
            .borderRadius(10)
            .backgroundColor(this.colors.card)
          }
        }, (c: ConnectionInfo) => c.id)
      }
      .layoutWeight(1)
      .width('100%')
      .padding({ left: 16, right: 16 })

      // 空状态（区分"无连接"与"无匹配结果"）
      if (this.connections.length === 0) {
        Column() {
          Text('暂无连接')
            .fontSize(14)
            .fontColor(this.colors.textSecondary)
            .margin({ top: 40 })
          Text('开启 VPN 后这里会显示实时连接')
            .fontSize(12)
            .fontColor(this.colors.textSecondary)
            .margin({ top: 8 })
        }
        .width('100%')
      } else if (this.filtered().length === 0) {
        Column() {
          Text('无匹配结果')
            .fontSize(14)
            .fontColor(this.colors.textSecondary)
            .margin({ top: 40 })
          Text('换个关键词试试')
            .fontSize(12)
            .fontColor(this.colors.textSecondary)
            .margin({ top: 8 })
        }
        .width('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.colors.background)
  }

  // 目标主机（去端口）
  hostOf(c: ConnectionInfo): string {
    const host = c.metadata?.host ?? '';
    if (host !== '') return host;
    const dst = c.metadata?.destinationIP ?? '';
    const port = c.metadata?.destinationPort ?? '';
    return dst + ':' + port;
  }
}
