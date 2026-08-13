/*
 * hmos-openvpn P1-2: ActivationStore 单例
 * 集中处理"激活订阅"的状态同步：
 *   1. Preferences:  active_profile_id（key=app_settings）
 *   2. 跨进程文件:   filesDir/active_profile.id（VPN 进程读取）
 *   3. Go 配置格式:  profiles/<id>.yaml（Go 内核 readFile 的路径）
 *   4. ArkTS 配置:   profiles/<id>/config.yaml（UI 写入）
 *
 * P1-5 待修：Go 端 getProfilePath 读 <id>.yaml，但 ArkTS 存 <id>/config.yaml，
 *           复制这步是 hack。彻底方案是统一路径（待 Go 端改动后移除）。
 */
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { fileIo } from '@kit.CoreFileKit';
import { getHome } from './appPath';
import { readFile, writeFile, fileExists } from './fileUtils';
import { patchGlobalGroupInYaml } from './YamlGlobalPatch';

const PREF_NAME = 'app_settings';
const PREF_KEY_ACTIVE_ID = 'active_profile_id';

export class ActivationStore {
  private static instance: ActivationStore | undefined;
  private pref: preferences.Preferences | undefined;
  private context: common.Context | undefined;
  // 当前激活订阅（内存缓存，避免频繁读 Prefs）
  private cachedActiveId: string = '';

  static getInstance(): ActivationStore {
    if (!ActivationStore.instance) {
      ActivationStore.instance = new ActivationStore();
    }
    return ActivationStore.instance;
  }

  async init(context: common.Context): Promise<void> {
    this.context = context;
    this.pref = await preferences.getPreferences(context, PREF_NAME);
  }

  // 读取当前激活订阅 ID（缓存 + Prefs）
  async getActiveProfileId(): Promise<string> {
    if (this.cachedActiveId !== '') {
      return this.cachedActiveId;
    }
    if (!this.pref) return '';
    const v: string = await this.pref.get(PREF_KEY_ACTIVE_ID, '') as string;
    this.cachedActiveId = v;
    return v;
  }

  // 设置激活订阅：Prefs + 文件 + yaml 复制 三处统一在一处
  async setActiveProfileId(id: string): Promise<void> {
    if (!this.pref || !this.context) {
      console.error('ActivationStore', 'setActiveProfileId: 未初始化');
      return;
    }
    // 1. 写 Prefs
    await this.pref.put(PREF_KEY_ACTIVE_ID, id);
    await this.pref.flush();
    this.cachedActiveId = id;

    // 2. 写跨进程共享文件（VPN 进程读取）
    try {
      const statePath = this.context.filesDir + '/active_profile.id';
      const file = fileIo.openSync(
        statePath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC
      );
      const encoder = new util.TextEncoder();
      const buf = encoder.encodeInto(id);
      fileIo.writeSync(file.fd, buf.buffer, { offset: 0, length: buf.byteLength });
      fileIo.closeSync(file);
    } catch (e) {
      console.error('ActivationStore', '写激活状态文件失败: ' + String(e));
    }

    // 3. yaml 路径同步（P1-5 待修：Go 端 getProfilePath 改为读 <id>/config.yaml 后移除）
    if (id !== '') {
      await this.syncGoConfigYaml(id);
    }
  }

  // 同步 Go 侧配置格式：<id>.yaml ← <id>/config.yaml
  private async syncGoConfigYaml(id: string): Promise<void> {
    if (!this.context) return;
    try {
      const home = await getHome(this.context);
      const srcPath = home + '/profiles/' + id + '/config.yaml';
      const dstPath = home + '/profiles/' + id + '.yaml';
      if (await fileExists(srcPath)) {
        const data: Uint8Array | null = await readFile(srcPath);
        if (data) {
          // P3 全局模式修复：Go 格式 yaml 同步时补全 GLOBAL 组成员
          const text = new util.TextDecoder().decodeToString(data);
          const patched = patchGlobalGroupInYaml(text);
          const encoder = new util.TextEncoder();
          // 直接传 encodeInto 视图（byteLength=内容长度），writeFile 按视图长度截断写入
          await writeFile(dstPath, encoder.encodeInto(patched));
          console.log('ActivationStore', '已同步Go配置格式: ' + id + '.yaml');
        }
      }
    } catch (e) {
      console.error('ActivationStore', 'syncGoConfigYaml failed: ' + String(e));
    }
  }

  // 清空激活订阅（用于卸载订阅时）
  async clearActiveProfileId(): Promise<void> {
    await this.setActiveProfileId('');
  }

  // ---- 跨进程读取：VPN 进程专用 ----
  // 读跨进程共享文件 /active_profile.id（UI 写，VPN 读）
  static async readActiveProfileIdFromFile(filesDir: string): Promise<string> {
    const statePath = filesDir + '/active_profile.id';
    try {
      // P2-13 统一到 fileIo（sync API），与 setActiveProfileId 的写入路径对齐
      if (!fileIo.accessSync(statePath)) return '';
      const file = fileIo.openSync(statePath, fileIo.OpenMode.READ_ONLY);
      const stat = fileIo.statSync(statePath);
      const buf = new ArrayBuffer(stat.size > 0 ? stat.size : 1);
      fileIo.readSync(file.fd, buf, { offset: 0, length: buf.byteLength });
      fileIo.closeSync(file);
      const text = new util.TextDecoder().decodeWithStream(new Uint8Array(buf));
      return text.replace(/\0/g, '').trim();
    } catch (e) {
      console.error('ActivationStore', 'readActiveProfileIdFromFile failed: ' + String(e));
      return '';
    }
  }

  // 跨进程同步 yaml 格式（VPN 进程调用，从 ArkTS 格式复制到 Go 读取格式）
  // P1-5 TODO：Go 端 getProfilePath 改为读 <id>/config.yaml 后可移除
  // 签名改为接收 Context（避免 object literal 伪造 Context，满足 arkts-no-untyped-obj-literals）
  static async ensureGoConfigYaml(context: common.Context, activeId: string): Promise<boolean> {
    if (activeId === '') return false;
    try {
      const home = await getHome(context);
      const srcPath = home + '/profiles/' + activeId + '/config.yaml';
      const dstPath = home + '/profiles/' + activeId + '.yaml';
      if (await fileExists(srcPath)) {
        // P3 全局模式修复：每次启动都重新同步（确保 GLOBAL 组补丁生效，
        // 修复旧版本遗留的未补丁 yaml）
        const data: Uint8Array | null = await readFile(srcPath);
        if (data) {
          const text = new util.TextDecoder().decodeToString(data);
          const patched = patchGlobalGroupInYaml(text);
          const encoder = new util.TextEncoder();
          await writeFile(dstPath, encoder.encodeInto(patched));
          console.log('ActivationStore', 'ensureGoConfigYaml OK: ' + activeId);
          return true;
        }
      }
      return false;
    } catch (e) {
      console.error('ActivationStore', 'ensureGoConfigYaml failed: ' + String(e));
      return false;
    }
  }
}