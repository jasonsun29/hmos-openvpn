/*
 * hmos-openvpn M2: 日志页（对齐 Clash Verge logs.tsx）
 * T11.1 实时日志流（setLogObserver）
 * T11.2 日志级别过滤（info/debug/error）
 * T11.3 清空/暂停
 * 数据层：SocketProxyService.setLogObserver（核心日志回调）
 */
import { ThemeColors, ThemeDimen } from '../model/Theme';
import { AppService } from '../service/AppService';
import { SocketProxyService, LogInfo, LogLevel } from 'proxy_core';

@Component
export struct LogsPage {
  @Consume colors: ThemeColors;
  @State logs: Array<LogInfo> = [];
  @State levelFilter: string = 'info';
  @State paused: boolean = false;
  private appService: AppService = AppService.getInstance();
  private unregister: (() => void) | undefined = undefined;
  private maxLogs: number = 300;

  aboutToAppear(): void {
    this.startLog();
  }

  aboutToDisappear(): void {
    this.stopLog();
  }

  async startLog(): Promise<void> {
    const svc: SocketProxyService | undefined = this.appService.getProxyService();
    if (!svc) return;
    try {
      this.unregister = await svc.setLogObserver((log: LogInfo) => {
        if (this.paused) return;
        if (this.levelFilter === 'error' && log.logLevel !== LogLevel.Error) return;
        if (this.levelFilter === 'warning' && log.logLevel !== LogLevel.Error && log.logLevel !== LogLevel.Warning) return;
        this.logs.push(log);
        if (this.logs.length > this.maxLogs) {
          this.logs.shift();
        }
      });
    } catch (e) {
      console.error('T11', 'startLog failed: ' + String(e));
    }
  }

  stopLog(): void {
    if (this.unregister) {
      try {
        this.unregister();
      } catch (e) {
        // 忽略
      }
      this.unregister = undefined;
    }
  }

  clearLogs(): void {
    this.logs = [];
  }

  levelColor(level: LogLevel): string {
    if (level === LogLevel.Error) return '#FF3B30';
    if (level === LogLevel.Warning) return '#FF9500';
    if (level === LogLevel.Info) return '#07C160';
    if (level === LogLevel.Debug) return '#007AFF';
    return '#999999';
  }

  formatTime(time: number): string {
    const d = new Date(time);
    const pad = (n: number): string => n < 10 ? '0' + n : '' + n;
    return pad(d.getHours()) + ':' + pad(d.getMinutes()) + ':' + pad(d.getSeconds());
  }

  build() {
    Column() {
      // 顶部工具栏
      Row({ space: 8 }) {
        Text('日志')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.colors.textPrimary)
          .layoutWeight(1)
        // 级别过滤
        this.levelBtn('info', 'info')
        this.levelBtn('warning', 'warn')
        this.levelBtn('error', 'error')
        // 暂停/继续
        Button(this.paused ? '继续' : '暂停')
          .fontSize(12)
          .height(32)
          .backgroundColor(this.colors.primary)
          .onClick(() => { this.paused = !this.paused; })
        // 清空
        Button('清空')
          .fontSize(12)
          .height(32)
          .backgroundColor('#FF3B30')
          .onClick(() => this.clearLogs())
      }
      .width('100%')
      .padding({ left: 24, top: 16, right: 24, bottom: 8 })

      // 日志列表
      List({ space: 2 }) {
        ForEach(this.logs, (log: LogInfo, index: number) => {
          ListItem() {
            Row() {
              Text(this.formatTime(log.time))
                .fontSize(11)
                .fontColor(this.colors.textSecondary)
              Text(log.logLevel.toUpperCase())
                .fontSize(11)
                .fontColor(this.levelColor(log.logLevel))
                .width(48)
                .margin({ left: 6 })
              Text(log.payload)
                .fontSize(12)
                .fontColor(this.colors.textPrimary)
                .layoutWeight(1)
                .maxLines(3)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
            .padding({ left: 16, right: 16, top: 4, bottom: 4 })
          }
        }, (log: LogInfo, index: number) => log.time + '_' + index)
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)

      // 空状态
      if (this.logs.length === 0) {
        Text('暂无日志（开启 VPN 后显示核心日志）')
          .fontSize(13)
          .fontColor(this.colors.textSecondary)
          .margin({ top: 40 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.colors.background)
  }

  @Builder
  levelBtn(val: string, label: string) {
    Button(label)
      .fontSize(11)
      .height(30)
      .backgroundColor(this.levelFilter === val ? this.colors.primary : this.colors.background)
      .fontColor(this.levelFilter === val ? '#FFFFFF' : this.colors.textSecondary)
      .onClick(() => {
        this.levelFilter = val;
        this.clearLogs();
      })
  }
}
