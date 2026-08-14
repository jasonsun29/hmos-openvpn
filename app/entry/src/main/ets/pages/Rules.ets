/*
 * hmos-openvpn M2: 规则页（对齐 Clash Verge rules.tsx）
 * T10.1 规则列表（从激活的订阅配置解析 rules 段）
 * T10.2 规则统计（静态）
 * P2-3 实时统计：调 getRequestList RPC 拿 ConnectionInfo.rule 字段，
 *      按命中次数 top-N 展示规则命中情况
 */
import { ThemeColors, ThemeDimen } from '../model/Theme';
import { AppService } from '../service/AppService';
import { getHome, SocketProxyService, ConnectionInfo, fileExists, readText } from 'proxy_core';
import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';

interface RuleItem {
  text: string;
  type: string;
  policy: string;
}

// P2-3 规则命中统计（实时）
interface RuleHitStat {
  rule: string;
  count: number;
}

@Builder function EmptyText(content: string) {}

@Component
export struct RulesPage {
  @Consume colors: ThemeColors;
  @State rules: Array<RuleItem> = [];
  // $r() 返回 Resource，与纯字符串拼接结果并存 → 联合类型
  @State stats: string | Resource = '';
  // P2-3 实时命中统计
  @State hitStats: Array<RuleHitStat> = [];
  // 模拟器验证修复：Navigation 栈下 aboutToDisappear 不触发 → 页面切走时 2s 轮询不停
  @StorageLink('vpnOn') vpnOn: boolean = false;
  @StorageLink('navPageShown') @Watch('onNavPageShownEvt') navPageShown: string = '';
  @StorageLink('navPageHidden') @Watch('onNavPageHiddenEvt') navPageHidden: string = '';
  private appService: AppService = AppService.getInstance();
  private hitRefreshTimer: number = -1;

  onNavPageShownEvt(): void {
    if (this.navPageShown.startsWith('Rules')) {
      this.startHitPoll();
    }
  }

  onNavPageHiddenEvt(): void {
    if (this.navPageHidden.startsWith('Rules')) {
      this.stopHitPoll();
    }
  }

  startHitPoll(): void {
    if (this.hitRefreshTimer !== -1) {
      return;
    }
    this.loadHitStats();
    this.hitRefreshTimer = setInterval(() => {
      this.loadHitStats();
    }, 2000);
  }

  stopHitPoll(): void {
    if (this.hitRefreshTimer !== -1) {
      clearInterval(this.hitRefreshTimer);
      this.hitRefreshTimer = -1;
    }
  }

  aboutToAppear(): void {
    this.loadRules();
    this.loadHitStats();
    this.startHitPoll();
  }

  aboutToDisappear(): void {
    this.stopHitPoll();
  }

  async loadRules(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const activeId = await this.appService.getActiveProfileId();
      if (activeId === '') {
        this.stats = $r('app.string.rules_no_active');
        return;
      }
      const home = await getHome(context);
      // 读取 ArkTS 格式配置（<id>/config.yaml）
      const cfgPath = home + '/profiles/' + activeId + '/config.yaml';
      if (!(await fileExists(cfgPath))) {
        this.stats = $r('app.string.rules_config_missing');
        return;
      }
      const data = await readText(cfgPath);
      const items: Array<RuleItem> = [];
      const lines = data.split('\n');
      let inRules = false;
      for (let line of lines) {
        const trimmed = line.trim();
        if (trimmed === 'rules:') {
          inRules = true;
          continue;
        }
        if (inRules) {
          // rules 段以缩进结束（下一个顶格 key）
          if (trimmed !== '' && !line.startsWith(' ') && !line.startsWith('-')) {
            break;
          }
          if (trimmed.startsWith('- ')) {
            const ruleText = trimmed.substring(2).trim();
            const parts = ruleText.split(',');
            if (parts.length >= 2) {
              items.push({
                text: ruleText,
                type: parts[0].trim(),
                policy: parts[parts.length - 1].trim()
              });
            }
          }
        }
      }
      this.rules = items;
      // 统计
      const policyCount: Record<string, number> = {};
      for (let r of items) {
        policyCount[r.policy] = (policyCount[r.policy] ?? 0) + 1;
      }
      const parts: string[] = [];
      for (let key of Object.keys(policyCount)) {
        parts.push(key + '×' + policyCount[key]);
      }
      this.stats = '共 ' + items.length + ' 条规则 | ' + parts.join(' ');
    } catch (e) {
      // P2-6 i18n：参数化消息通过 $r('app.string.xxx', arg) 传递
      this.stats = $r('app.string.rules_parse_failed', String(e));
    }
  }

  // P2-3 实时规则命中统计：调 getRequestList 拿所有 ConnectionInfo，按 rule 字段分组计数
  async loadHitStats(): Promise<void> {
    // VPN 未启动时无命中数据，静默停止轮询
    if (!this.vpnOn) {
      this.stopHitPoll();
      this.hitStats = [];
      return;
    }
    const svc: SocketProxyService | undefined = this.appService.getProxyService();
    if (!svc) {
      this.hitStats = [];
      return;
    }
    try {
      const list: Array<ConnectionInfo> = await svc.getRequestList();
      const counter: Record<string, number> = {};
      for (const c of list) {
        const ruleName = (c.rule ?? '').trim();
        if (ruleName === '') continue;
        counter[ruleName] = (counter[ruleName] ?? 0) + 1;
      }
      // 排序后取 top-10
      const arr: Array<RuleHitStat> = [];
      const keys = Object.keys(counter);
      for (const k of keys) {
        arr.push({ rule: k, count: counter[k] });
      }
      arr.sort((a: RuleHitStat, b: RuleHitStat) => b.count - a.count);
      this.hitStats = arr.slice(0, 10);
    } catch (e) {
      // 静默失败：VPN 未启动时 RPC 会 reject，不打扰用户
      this.hitStats = [];
    }
  }

  build() {
    Column() {
      // 标题 + 统计
      Row() {
        Column({ space: 2 }) {
          Text($r('app.string.rules_title'))
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.colors.textPrimary)
          Text(this.stats)
            .fontSize(11)
            .fontColor(this.colors.textSecondary)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Button($r('app.string.rules_refresh'))
          .fontSize(12)
          .height(32)
          .backgroundColor(this.colors.primary)
          .onClick(() => this.loadRules())
      }
      .width('100%')
      .padding({ left: 24, top: 16, right: 24, bottom: 8 })

      // P2-3 实时命中统计（top-10）
      if (this.hitStats.length > 0) {
        Column({ space: 4 }) {
          Row() {
            Text($r('app.string.rules_hit_stats_title'))
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.colors.textPrimary)
              .layoutWeight(1)
            Text($r('app.string.rules_hit_stats_refresh'))
              .fontSize(10)
              .fontColor(this.colors.textSecondary)
          }
          .width('100%')
          ForEach(this.hitStats, (h: RuleHitStat) => {
            Row() {
              Text(h.rule)
                .fontSize(12)
                .fontColor(this.colors.textPrimary)
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text('×' + h.count)
                .fontSize(12)
                .fontColor(this.colors.primary)
                .margin({ left: 8 })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 4, bottom: 4 })
            .borderRadius(6)
            .backgroundColor(this.colors.card)
          }, (h: RuleHitStat) => h.rule)
        }
        .width('92%')
        .margin({ bottom: 8 })
      }

      // 规则列表
      List({ space: 2 }) {
        ForEach(this.rules, (r: RuleItem, index: number) => {
          ListItem() {
            Row() {
              Text('' + (index + 1))
                .fontSize(11)
                .fontColor(this.colors.textSecondary)
                .width(30)
              Column({ space: 2 }) {
                Text(r.text)
                  .fontSize(12)
                  .fontColor(this.colors.textPrimary)
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Text(r.policy)
                .fontSize(11)
                .fontColor(this.colors.primary)
                .margin({ left: 8 })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
            .borderRadius(8)
            .backgroundColor(this.colors.card)
          }
        }, (r: RuleItem, index: number) => r.type + '_' + index)
      }
      .layoutWeight(1)
      .width('100%')
      .padding({ left: 16, right: 16 })

      if (this.rules.length === 0) {
        Text(this.stats)
          .fontSize(13)
          .fontColor(this.colors.textSecondary)
          .margin({ top: 40 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.colors.background)
  }
}
