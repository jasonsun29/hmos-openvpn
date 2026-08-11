/*
 * hmos-openvpn M2: 规则页（对齐 Clash Verge rules.tsx）
 * T10.1 规则列表（从激活的订阅配置解析 rules 段）
 * T10.2 规则统计（总数/按策略分组）
 * 注：mihomo 核心 NAPI 未暴露 /rules API，从配置解析展示（静态）
 */
import { ThemeColors } from '../model/Theme';
import { AppService } from '../service/AppService';
import fs from '@ohos.file.fs';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { getHome } from 'proxy_core';

interface RuleItem {
  text: string;
  type: string;
  policy: string;
}

@Component
export struct RulesPage {
  @Consume colors: ThemeColors;
  @State rules: Array<RuleItem> = [];
  @State stats: string = '';
  private appService: AppService = AppService.getInstance();

  aboutToAppear(): void {
    this.loadRules();
  }

  async loadRules(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const activeId = await this.appService.getActiveProfileId();
      if (activeId === '') {
        this.stats = '未激活订阅';
        return;
      }
      const home = await getHome(context);
      // 读取 ArkTS 格式配置（<id>/config.yaml）
      const cfgPath = home + '/profiles/' + activeId + '/config.yaml';
      if (!(await RulesPage.fileExists(cfgPath))) {
        this.stats = '配置文件不存在';
        return;
      }
      const data = await RulesPage.readText(cfgPath);
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
      this.stats = '解析失败: ' + String(e);
    }
  }

  static async fileExists(path: string): Promise<boolean> {
    try {
      return await fs.access(path);
    } catch (e) {
      return false;
    }
  }

  static async readText(filePath: string): Promise<string> {
    try {
      const file = await fs.open(filePath);
      const stats = await fs.stat(filePath);
      const buf = new ArrayBuffer(stats.size);
      await fs.read(file.fd, buf);
      fs.closeSync(file);
      const decoder = new util.TextDecoder();
      return decoder.decodeWithStream(new Uint8Array(buf));
    } catch (e) {
      return '';
    }
  }

  build() {
    Column() {
      // 标题 + 统计
      Row() {
        Column({ space: 2 }) {
          Text('规则')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.colors.textPrimary)
          Text(this.stats)
            .fontSize(11)
            .fontColor(this.colors.textSecondary)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Button('刷新')
          .fontSize(12)
          .height(32)
          .backgroundColor(this.colors.primary)
          .onClick(() => this.loadRules())
      }
      .width('100%')
      .padding({ left: 24, top: 16, right: 24, bottom: 8 })

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
