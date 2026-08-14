/*
 * hmos-openvpn M3: unlock 流媒体解锁检测页（对齐 Clash Verge unlock.tsx）
 *
 * 检测机制（v1，无 Go 重编译）：
 *   UI 进程 http 请求经 VPN TUN 出去（与 Home 的出口 IP 查询同机制）：
 *   - 全局模式 → 走当前全局端点，检测该端点的解锁情况
 *   - 规则模式 → 走规则路由的出口
 *   - VPN 关闭 → 直连检测（本地网络）
 * 判定：按各服务的 HTTP 状态码分类（2xx/3xx=解锁，403/451 等=封锁，超时/网络错=失败）。
 * 与核心侧逐节点检测的差异：核心 healthCheck 仅支持单一 test-url（constant.DefaultTestURL），
 * 逐节点×逐服务需要换 test-url 重发配置，留作后续 spike（见 docs/AGENT_CONTEXT）。
 */
import { ThemeColors, ThemeDimen } from '../model/Theme';
import { http } from '@kit.NetworkKit';
import { promptAction } from '@kit.ArkUI';
import { AppIcon, AppIconName } from '../components/AppIcon';

interface UnlockService {
  key: string;
  url: string;
  okStatuses: Array<number>;
}

class UnlockResult {
  key: string = '';
  status: string = 'idle'; // idle | testing | unlocked | blocked | failed
  detail: string = '';

  constructor(key: string, status: string, detail: string) {
    this.key = key;
    this.status = status;
    this.detail = detail;
  }
}

@Component
export struct UnlockPage {
  @Consume colors: ThemeColors;
  @State results: Array<UnlockResult> = [];
  @State allTesting: boolean = false;
  private services: Array<UnlockService> = [
    { key: 'Netflix', url: 'https://www.netflix.com/title/81280792', okStatuses: [200] },
    { key: 'YouTube', url: 'https://www.youtube.com/premium', okStatuses: [200, 302] },
    { key: 'Disney+', url: 'https://www.disneyplus.com/', okStatuses: [200, 302] },
    { key: 'ChatGPT', url: 'https://chatgpt.com/', okStatuses: [200] },
    { key: 'OpenAI API', url: 'https://api.openai.com/v1/models', okStatuses: [200, 401] },
    { key: 'Google', url: 'https://www.google.com/generate_204', okStatuses: [204] },
    { key: 'Telegram', url: 'https://telegram.org/', okStatuses: [200, 302] },
    { key: 'DMM', url: 'https://www.dmm.co.jp/', okStatuses: [200, 302] },
    { key: 'AbemaTV', url: 'https://abema.tv/', okStatuses: [200, 302] },
    { key: 'TikTok', url: 'https://www.tiktok.com/', okStatuses: [200, 302] }
  ];

  private setResult(key: string, status: string, detail: string): void {
    const idx = this.results.findIndex((r: UnlockResult) => r.key === key);
    if (idx >= 0) {
      this.results[idx] = new UnlockResult(key, status, detail);
    } else {
      this.results.push(new UnlockResult(key, status, detail));
    }
    this.results = [...this.results]; // 触发 @State 渲染（ArkTS 禁止对象 spread）
  }

  private resultOf(key: string): UnlockResult {
    const found = this.results.find((r: UnlockResult) => r.key === key);
    return found ?? new UnlockResult(key, 'idle', '');
  }

  async detectService(key: string): Promise<void> {
    const svc = this.services.find((s: UnlockService) => s.key === key);
    if (!svc) return;
    this.setResult(key, 'testing', '');
    try {
      const httpRequest = http.createHttp();
      const resp = await httpRequest.request(svc.url, {
        connectTimeout: 8000,
        readTimeout: 8000,
        expectDataType: http.HttpDataType.STRING
      });
      httpRequest.destroy();
      const code = resp.responseCode;
      if (svc.okStatuses.includes(code)) {
        this.setResult(key, 'unlocked', 'HTTP ' + code);
      } else {
        this.setResult(key, 'blocked', 'HTTP ' + code);
      }
    } catch (e) {
      // BusinessError 不是 Error 实例：需从对象字段提取 message（否则显示 [object Object]）
      let msg = '';
      if (e instanceof Error) {
        msg = e.message;
      } else if (typeof e === 'object' && e !== null) {
        const be = e as Record<string, Object>;
        const m = be['message'];
        if (typeof m === 'string') {
          msg = m;
        }
      }
      if (msg === '') {
        msg = JSON.stringify(e);
      }
      if (msg.length > 28) {
        msg = msg.substring(0, 28) + '…';
      }
      this.setResult(key, 'failed', msg);
    }
  }

  async detectAll(): Promise<void> {
    if (this.allTesting) {
      return;
    }
    this.allTesting = true;
    // 顺序检测（避免并发全触发限流）；单服务 8s 超时
    for (const s of this.services) {
      await this.detectService(s.key);
    }
    this.allTesting = false;
  }

  statusText(r: UnlockResult): string {
    switch (r.status) {
      case 'testing': return '检测中...';
      case 'unlocked': return '解锁';
      case 'blocked': return '不可用';
      case 'failed': return '失败';
      default: return '未检测';
    }
  }

  // 状态图标名（SymbolGlyph）
  statusIcon(r: UnlockResult): string {
    switch (r.status) {
      case 'unlocked': return AppIconName.Success;
      case 'blocked': return AppIconName.Fail;
      case 'failed': return AppIconName.Warn;
      default: return AppIconName.Clock;
    }
  }

  statusColor(r: UnlockResult): string {
    switch (r.status) {
      case 'unlocked': return '#07C160';
      case 'blocked': return '#FF3B30';
      case 'failed': return '#FF9500';
      case 'testing': return this.colors.primary;
      default: return this.colors.textSecondary;
    }
  }

  build() {
    Column() {
      Text($r('app.string.nav_unlock'))
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.colors.textPrimary)
        .width('100%')
        .padding({ left: 24, top: 20, bottom: 8 })

      Row() {
        Text('流媒体解锁检测（当前出口）')
          .fontSize(12)
          .fontColor(this.colors.textSecondary)
          .layoutWeight(1)
        Button(this.allTesting ? '检测中...' : '全部检测')
          .fontSize(13)
          .height(36)
          .backgroundColor(this.allTesting ? '#8A8A8A' : this.colors.primary)
          .onClick(() => this.detectAll())
      }
      .width('92%')
      .margin({ bottom: 8 })

      List({ space: 8 }) {
        ForEach(this.services, (s: UnlockService) => {
          ListItem() {
            Row() {
              Column({ space: 2 }) {
                Text(s.key)
                  .fontSize(15)
                  .fontColor(this.colors.textPrimary)
                Text(this.resultOf(s.key).detail)
                  .fontSize(10)
                  .fontColor(this.colors.textSecondary)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Row({ space: 4 }) {
                AppIcon({
                  name: this.statusIcon(this.resultOf(s.key)),
                  iconSize: 14,
                  color: this.statusColor(this.resultOf(s.key))
                })
                Text(this.statusText(this.resultOf(s.key)))
                  .fontSize(13)
                  .fontColor(this.statusColor(this.resultOf(s.key)))
              }
              .margin({ right: 8 })

              Button('检测')
                .fontSize(12)
                .height(30)
                .backgroundColor(this.colors.primary)
                .onClick(() => this.detectService(s.key))
            }
            .width('100%')
            .padding(14)
            .borderRadius(ThemeDimen.RadiusRow)
            .backgroundColor(this.colors.glassCard)
            .backgroundBlurStyle(BlurStyle.Thin)
          }
        }, (s: UnlockService) => s.key)
      }
      .layoutWeight(1)
      .width('100%')
      .padding({ left: 16, right: 16 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.colors.background)
  }
}
