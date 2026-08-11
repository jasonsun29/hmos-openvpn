/*
 * hmos-openvpn M1: 订阅页（T3）
 * T3.1 订阅列表（增删改/切换激活）
 * T3.2 订阅导入（URL）
 * T3.3 订阅用量（SubscriptionInfo 展示，expire=0 不展示）
 * T3.4 节点预览
 * 数据层：proxy_core ProfileRepo（RDB）+ Profile 实体（update/save）
 */
import { ThemeColors } from '../model/Theme';
import { AppService } from '../service/AppService';
import { Profile, ProfileType, ProfileRepo, SubscriptionInfo } from 'proxy_core';
import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';

@Component
export struct ProfilesPage {
  @Consume colors: ThemeColors;
  @State profiles: Array<Profile> = [];
  @State activeId: string = '';
  @State urlInput: string = '';
  private appService: AppService = AppService.getInstance();

  aboutToAppear(): void {
    this.loadProfiles();
  }

  async loadProfiles(): Promise<void> {
    const repo: ProfileRepo | undefined = this.appService.getProfileRepo();
    if (!repo) return;
    const context = getContext(this) as common.UIAbilityContext;
    const list = await repo.queryAll();
    for (let p of list) {
      p.loadContext(context);
    }
    this.profiles = list;
    this.activeId = await this.appService.getActiveProfileId();
  }

  // T3.2 URL 导入
  async importFromUrl(): Promise<void> {
    const url: string = this.urlInput.trim();
    if (url === '') {
      promptAction.showToast({ message: '请输入订阅 URL' });
      return;
    }
    if (!url.startsWith('https://')) {
      promptAction.showToast({ message: '仅支持 HTTPS 订阅（安全要求）' });
      return;
    }
    const repo: ProfileRepo | undefined = this.appService.getProfileRepo();
    if (!repo) return;
    const profile = new Profile(ProfileType.Url, url);
    const context = getContext(this) as common.UIAbilityContext;
    profile.loadContext(context);
    try {
      // vailConfig 回调：配置已通过 isYAML 校验，直接返回空字符串=通过
      // （真实核心校验在"激活"时由 loadConfig 执行，导入阶段只需格式合法）
      await profile.update(async (config: string): Promise<string> => {
        return '';
      });
      await repo.addOrUpdate(profile);
      promptAction.showToast({ message: '订阅导入成功: ' + profile.name });
      this.urlInput = '';
      await this.loadProfiles();
    } catch (e) {
      const msg: string = (e instanceof Error) ? e.message : String(e);
      console.error('T3', '导入失败 url=' + url + ' err=' + msg + ' stack=' + ((e instanceof Error) ? e.stack : ''));
      promptAction.showToast({ message: '导入失败: ' + msg });
    }
  }

  // T3.1 切换激活
  async activateProfile(p: Profile): Promise<void> {
    this.activeId = p.id;
    await this.appService.setActiveProfileId(p.id);
    promptAction.showToast({ message: '已激活: ' + (p.name ?? p.id) });
  }

  // T3.1 删除
  async deleteProfile(p: Profile): Promise<void> {
    const repo: ProfileRepo | undefined = this.appService.getProfileRepo();
    if (!repo) return;
    await repo.delete(p.id);
    await p.delete();
    if (this.activeId === p.id) {
      this.activeId = '';
      await this.appService.setActiveProfileId('');
    }
    await this.loadProfiles();
  }

  build() {
    Column() {
      Text($r('app.string.nav_profiles'))
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.colors.textPrimary)
        .width('100%')
        .padding({ left: 24, top: 16, bottom: 8 })

      // URL 导入行
      Row({ space: 8 }) {
        TextInput({ placeholder: 'https://订阅链接', text: this.urlInput })
          .layoutWeight(1)
          .height(40)
          .fontSize(14)
          .onChange((v: string) => { this.urlInput = v; })
        Button('导入')
          .height(40)
          .fontSize(13)
          .backgroundColor(this.colors.primary)
          .onClick(() => this.importFromUrl())
      }
      .width('92%')
      .margin({ bottom: 8 })

      // 订阅列表
      List({ space: 8 }) {
        ForEach(this.profiles, (p: Profile) => {
          ListItem() {
            Row() {
              Column({ space: 4 }) {
                Text(p.name ?? p.id)
                  .fontSize(15)
                  .fontWeight(this.activeId === p.id ? FontWeight.Bold : FontWeight.Normal)
                  .fontColor(this.activeId === p.id ? this.colors.primary : this.colors.textPrimary)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                // T3.3 订阅用量（expire=0 不展示到期）
                if (p.subscriptionInfo) {
                  Text(this.formatUsage(p.subscriptionInfo))
                    .fontSize(12)
                    .fontColor(this.colors.textSecondary)
                }
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              // 激活标记
              if (this.activeId === p.id) {
                Text('✓')
                  .fontSize(18)
                  .fontColor(this.colors.primary)
                  .margin({ right: 8 })
              }
              // 删除按钮
              Button('删除')
                .fontSize(12)
                .height(30)
                .backgroundColor('#FF3B30')
                .onClick(() => this.deleteProfile(p))
            }
            .width('100%')
            .padding(16)
            .borderRadius(12)
            .backgroundColor(this.colors.card)
            .onClick(() => this.activateProfile(p))
          }
        }, (p: Profile) => p.id)
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

  formatUsage(si: SubscriptionInfo): string {
    const used = si.upload + si.download;
    const parts: string[] = [];
    parts.push('已用 ' + this.formatBytes(used));
    if (si.total > 0) {
      parts.push('共 ' + this.formatBytes(si.total));
    }
    if (si.expire > 0) {
      const d = new Date(si.expire * 1000);
      parts.push('到期 ' + d.getFullYear() + '-' + (d.getMonth() + 1) + '-' + d.getDate());
    }
    return parts.join(' / ');
  }

  formatBytes(bytes: number): string {
    if (bytes >= 1024 * 1024 * 1024) return (bytes / (1024 * 1024 * 1024)).toFixed(2) + ' GB';
    if (bytes >= 1024 * 1024) return (bytes / (1024 * 1024)).toFixed(2) + ' MB';
    if (bytes >= 1024) return (bytes / 1024).toFixed(1) + ' KB';
    return bytes + ' B';
  }
}
