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
import { Profile, ProfileType, ProfileRepo, SubscriptionInfo, getHome, fileExists, readText } from 'proxy_core';
import { common, abilityAccessCtrl } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { util } from '@kit.ArkTS';
// P2-13 文件 API 统一：saveEdit 写配置文件用 fileIo.sync，文本读取走 proxy_core/readText
// P3-7/P3-11 picker：本地文件导入 + 导出
import { fileIo, picker } from '@kit.CoreFileKit';
// P3-12 扫码导入（系统 ScanKit 默认扫码页）；M3 二维码分享（generateBarcode）
import { scanCore, scanBarcode, generateBarcode } from '@kit.ScanKit';
import { image } from '@kit.ImageKit';
import { AppIcon, AppIconName } from '../components/AppIcon';

// BusinessError 在 OHOS 上不是 Error 实例：统一提取 code/message（否则显示 [object Object]）
function errMsg(e: Object): string {
  if (e instanceof Error) {
    return e.message;
  }
  if (typeof e === 'object' && e !== null) {
    const be = e as Record<string, Object>;
    const m = be['message'];
    if (typeof m === 'string' && m !== '') {
      return m;
    }
    const c = be['code'];
    if (c !== undefined && c !== null) {
      return '错误码 ' + String(c);
    }
  }
  return JSON.stringify(e);
}

function errCode(e: Object): string {
  if (typeof e === 'object' && e !== null) {
    const be = e as Record<string, Object>;
    const c = be['code'];
    if (c !== undefined && c !== null) {
      return String(c);
    }
  }
  return '';
}

@Component
export struct ProfilesPage {
  @Consume colors: ThemeColors;
  @State profiles: Array<Profile> = [];
  @State activeId: string = '';
  @State urlInput: string = '';
  // 配置编辑状态
  @State showEditor: boolean = false;
  @State editContent: string = '';
  // M3 订阅二维码分享
  @State showQr: boolean = false;
  @State qrContent: string = '';
  @State qrPixelMap: image.PixelMap | undefined = undefined;
  private editingId: string = '';
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

  // T3.2 URL 导入（输入框入口）
  async importFromUrl(): Promise<void> {
    const url: string = this.urlInput.trim();
    if (url === '') {
      promptAction.showToast({ message: '请输入订阅 URL' });
      return;
    }
    await this.doImportUrl(url);
    this.urlInput = '';
  }

  // P3-12 公共导入入口：URL 导入与扫码导入共用（校验 + 拉取 + 入库）
  async doImportUrl(url: string): Promise<void> {
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
      await this.loadProfiles();
    } catch (e) {
      const msg: string = errMsg(e);
      console.error('T3', '导入失败 url=' + url + ' err=' + msg + ' stack=' + ((e instanceof Error) ? e.stack : ''));
      promptAction.showToast({ message: '导入失败: ' + msg });
    }
  }

  // P3-12 扫码导入：ScanKit 默认扫码页（QR_CODE）→ 解析 URL → 复用 doImportUrl
  async scanImport(): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    try {
      // 系统扫码页需要相机预览 → 先申请 CAMERA（拒绝则提示并退出）
      const atManager = abilityAccessCtrl.createAtManager();
      const grant = await atManager.requestPermissionsFromUser(context, ['ohos.permission.CAMERA']);
      if (grant.authResults.length === 0 || grant.authResults[0] !== 0) {
        promptAction.showToast({ message: '需要相机权限才能扫码（可在设置中开启）' });
        return;
      }
      const options: scanBarcode.ScanOptions = { scanTypes: [scanCore.ScanType.QR_CODE] };
      const result = await scanBarcode.startScanForResult(context, options);
      let url: string = (result.originalValue ?? '').trim();
      if (url === '') {
        promptAction.showToast({ message: '未识别到内容' });
        return;
      }
      // 兼容 clash://install?url=... 等 schema，解析出真实订阅 URL
      if (!url.startsWith('https://') && url.includes('url=')) {
        const m = url.match(/url=([^&\s]+)/);
        if (m && m[1] !== undefined) {
          url = decodeURIComponent(m[1]);
        }
      }
      await this.doImportUrl(url);
    } catch (e) {
      const msg: string = errMsg(e);
      // 1000500002 = 用户取消扫码，静默（BusinessError 不在 message 里带 code，需单独比对）
      const isCancel: boolean = msg.includes('1000500002') || errCode(e) === '1000500002';
      if (!isCancel) {
        console.error('T3', '扫码失败: ' + msg);
        promptAction.showToast({ message: '扫码失败: ' + msg });
      }
    }
  }

  // P3-7 本地文件订阅导入：DocumentViewPicker 选择 .yaml/.yml → saveByUri 拷入沙箱
  async importFromFile(): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    const docPicker = new picker.DocumentViewPicker(context);
    try {
      const uris = await docPicker.select({
        maxSelectNumber: 1,
        fileSuffixFilters: ['.yaml,.yml']
      });
      console.log('Profiles', 'importFromFile uris=' + JSON.stringify(uris));
      if (uris.length === 0) {
        return; // 用户取消
      }
      const profile = new Profile(ProfileType.File, '');
      profile.loadContext(context);
      await profile.saveByUri(uris[0]);
      // 从文件名推断订阅名（去掉扩展名），列表展示更友好
      const segs = uris[0].split('/');
      const rawName = segs[segs.length - 1] ?? '';
      profile.name = rawName.replace(/\.(yaml|yml)$/i, '');
      const repo: ProfileRepo | undefined = this.appService.getProfileRepo();
      if (repo) {
        await repo.addOrUpdate(profile);
        promptAction.showToast({ message: '文件导入成功' });
        await this.loadProfiles();
      }
    } catch (e) {
      promptAction.showToast({ message: '导入失败: ' + errMsg(e) });
    }
  }

  // P3-11 订阅导出：把 <id>/config.yaml 复制到用户选择的保存位置
  async exportProfile(p: Profile): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const home = await getHome(context);
      const cfgPath = home + '/profiles/' + p.id + '/config.yaml';
      if (!(await fileExists(cfgPath))) {
        promptAction.showToast({ message: '配置不存在' });
        return;
      }
      const docPicker = new picker.DocumentViewPicker(context);
      const saveUris = await docPicker.save({
        newFileNames: [(p.name ?? p.id) + '.yaml']
      });
      console.log('Profiles', 'exportProfile saveUris=' + JSON.stringify(saveUris));
      if (saveUris.length === 0) {
        console.log('Profiles', 'exportProfile 用户取消');
        return; // 用户取消
      }
      await fileIo.copyFile(cfgPath, saveUris[0]);
      console.log('Profiles', 'exportProfile 复制完成: ' + saveUris[0]);
      promptAction.showToast({ message: '已导出' });
    } catch (e) {
      console.error('Profiles', 'exportProfile 失败: ' + errMsg(e));
      promptAction.showToast({ message: '导出失败: ' + errMsg(e) });
    }
  }

  // M3 订阅二维码分享：URL 订阅 → clash://install?url= 二维码（与扫码导入闭环）
  async showProfileQr(p: Profile): Promise<void> {
    if (p.type !== ProfileType.Url || p.url === '') {
      promptAction.showToast({ message: '仅支持 URL 订阅生成二维码' });
      return;
    }
    this.qrContent = 'clash://install?url=' + p.url;
    try {
      const options: generateBarcode.CreateOptions = {
        scanType: scanCore.ScanType.QR_CODE,
        height: 280,
        width: 280
      };
      this.qrPixelMap = await generateBarcode.createBarcode(this.qrContent, options);
      this.showQr = true;
    } catch (e) {
      console.error('Profiles', '二维码生成失败: ' + errMsg(e) + ' code=' + errCode(e));
      promptAction.showToast({ message: '二维码生成失败: ' + errMsg(e) });
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
        // P3-7 本地文件导入
        Button('文件')
          .height(40)
          .fontSize(13)
          .backgroundColor('#5A6B8C')
          .onClick(() => this.importFromFile())
        // P3-12 扫码导入
        Button('扫码')
          .height(40)
          .fontSize(13)
          .backgroundColor('#5A6B8C')
          .onClick(() => this.scanImport())
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
                AppIcon({ name: AppIconName.Check, iconSize: 18, color: this.colors.primary })
                  .margin({ right: 8 })
              }
              // 删除按钮
              Button('删除')
                .fontSize(12)
                .height(30)
                .backgroundColor('#FF3B30')
                .onClick(() => this.deleteProfile(p))
              // 编辑按钮
              Button('编辑')
                .fontSize(12)
                .height(30)
                .backgroundColor(this.colors.primary)
                .margin({ left: 4 })
                .onClick(() => this.editProfile(p))
              // P3-11 导出按钮
              Button('导出')
                .fontSize(12)
                .height(30)
                .backgroundColor('#5A6B8C')
                .margin({ left: 4 })
                .onClick(() => this.exportProfile(p))
              // M3 二维码分享
              Button('二维码')
                .fontSize(12)
                .height(30)
                .backgroundColor('#5A6B8C')
                .margin({ left: 4 })
                .onClick(() => this.showProfileQr(p))
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
      // M3 二维码分享 Sheet：挂 List 节点（根节点已挂编辑器 Sheet；
      // 同节点重复 bindSheet 会后者覆盖前者，导致编辑器 Sheet 永不弹出）
      .bindSheet($$this.showQr, this.qrSheet(), {
        height: 460,
        showClose: true,
        dragBar: true
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.colors.background)
    .alignItems(HorizontalAlign.Center)
    // P3-4（t33）配置编辑对话框：手写覆盖层改为系统 bindSheet
    // （系统级动画、返回键/下滑关闭，$$ 双向绑定）
    .bindSheet($$this.showEditor, this.editorSheet(), {
      height: '70%',
      showClose: true,
      dragBar: true
    })
  }

  // M3 二维码分享 Sheet
  @Builder
  qrSheet() {
    Column({ space: 12 }) {
      Text('订阅二维码')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.colors.textPrimary)
        .width('100%')
      if (this.qrPixelMap !== undefined) {
        Image(this.qrPixelMap)
          .width(280)
          .height(280)
      }
      Text(this.qrContent)
        .fontSize(10)
        .fontColor(this.colors.textSecondary)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Text('用另一台设备的 HarmonyVPN「扫码」导入')
        .fontSize(11)
        .fontColor(this.colors.textSecondary)
        .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding(16)
    .backgroundColor(this.colors.card)
    .alignItems(HorizontalAlign.Center)
  }

  // P3-4（t33）编辑器 Sheet 内容
  @Builder
  editorSheet() {
    Column() {
      Row() {
        Text('编辑配置')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.colors.textPrimary)
          .layoutWeight(1)
        Button('关闭')
          .fontSize(12)
          .height(30)
          .backgroundColor('#999999')
          .onClick(() => { this.showEditor = false; })
      }
      .width('100%')

      TextArea({ text: this.editContent })
        .width('100%')
        .layoutWeight(1)
        .fontSize(12)
        .onChange((v: string) => { this.editContent = v; })

      Button('保存配置')
        .width('100%')
        .height(40)
        .fontSize(14)
        .backgroundColor(this.colors.primary)
        .margin({ top: 8 })
        .onClick(() => this.saveEdit())
    }
    .width('100%')
    .height('100%')
    .padding(16)
    .backgroundColor(this.colors.card)
  }

  // T12.1 配置编辑：读取配置文件 → 编辑对话框 → 保存
  async editProfile(p: Profile): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const home = await getHome(context);
      const cfgPath = home + '/profiles/' + p.id + '/config.yaml';
      let content: string = '';
      if (await fileExists(cfgPath)) {
        content = await readText(cfgPath);
      }
      this.editContent = content;
      this.editingId = p.id;
      this.showEditor = true;
    } catch (e) {
      promptAction.showToast({ message: '读取配置失败' });
    }
  }

  // 保存编辑后的配置
  async saveEdit(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const home = await getHome(context);
      const id = this.editingId;
      if (id === '') return;
      const cfgPath = home + '/profiles/' + id + '/config.yaml';
      const encoder = new util.TextEncoder();
      // P2-13 sync API：fileIo.openSync / writeSync / closeSync（替代 fs.open/fs.write/fs.closeSync）
      const file = fileIo.openSync(cfgPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      const enc1 = encoder.encodeInto(this.editContent);
      fileIo.writeSync(file.fd, enc1.buffer, { offset: 0, length: enc1.byteLength });
      fileIo.closeSync(file);
      // 同步 Go 格式（纯拷贝）
      const goPath = home + '/profiles/' + id + '.yaml';
      const goFile = fileIo.openSync(goPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      const enc2 = encoder.encodeInto(this.editContent);
      fileIo.writeSync(goFile.fd, enc2.buffer, { offset: 0, length: enc2.byteLength });
      fileIo.closeSync(goFile);
      this.showEditor = false;
      promptAction.showToast({ message: '配置已保存' });
    } catch (e) {
      promptAction.showToast({ message: '保存失败: ' + errMsg(e) });
    }
  }

  formatUsage(si: SubscriptionInfo): string {
    const used = si.upload + si.download;
    const parts: string[] = [];
    // P3-3 公共化：统一走 AppService.formatBytes
    parts.push('已用 ' + AppService.formatBytes(used));
    if (si.total > 0) {
      parts.push('共 ' + AppService.formatBytes(si.total));
    }
    if (si.expire > 0) {
      const d = new Date(si.expire * 1000);
      parts.push('到期 ' + d.getFullYear() + '-' + (d.getMonth() + 1) + '-' + d.getDate());
    }
    return parts.join(' / ');
  }
}
