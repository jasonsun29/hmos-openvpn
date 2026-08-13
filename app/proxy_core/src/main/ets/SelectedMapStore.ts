/*
 * P3 全局模式语义 + 节点选择持久化（跨进程共享文件）
 *
 * UI 进程写、VPN 进程读（两进程共享应用 filesDir，M1 已验证）。
 * 文件结构：
 *   { "mode": "GLOBAL" | "RULE" | ""(未设置), "profiles": { [profileId]: { [groupName]: proxyName } } }
 *
 * 用途：
 *   1. 节点选择跨重启保留（上次选什么，下次还是什么）
 *   2. 全局模式跨重启保留（VPN 进程 onCreate 时按文件恢复 mode）
 *   3. 首次切全局时把当前规则模式选中节点继承给 GLOBAL 组（避免落 DIRECT）
 */
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { Context } from '@kit.AbilityKit';

const FILE_NAME = 'selected_map.json';

interface SelectedMapFile {
  mode: string;
  profiles: Record<string, Record<string, string>>;
}

export class SelectedMapStore {
  static async loadFile(context: Context): Promise<SelectedMapFile> {
    try {
      const path = context.filesDir + '/' + FILE_NAME;
      if (!fileIo.accessSync(path)) {
        return { mode: '', profiles: {} };
      }
      const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
      const stat = fileIo.statSync(path);
      const buf = new ArrayBuffer(stat.size > 0 ? stat.size : 1);
      fileIo.readSync(file.fd, buf, { offset: 0, length: buf.byteLength });
      fileIo.closeSync(file);
      const text = new util.TextDecoder().decodeToString(new Uint8Array(buf));
      const obj = JSON.parse(text) as SelectedMapFile;
      if (!obj.profiles) {
        obj.profiles = {};
      }
      if (typeof obj.mode !== 'string') {
        obj.mode = '';
      }
      return obj;
    } catch (e) {
      return { mode: '', profiles: {} };
    }
  }

  static async saveFile(context: Context, data: SelectedMapFile): Promise<void> {
    const path = context.filesDir + '/' + FILE_NAME;
    const text = JSON.stringify(data);
    const encoder = new util.TextEncoder();
    const file = fileIo.openSync(path,
      fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
    const enc = encoder.encodeInto(text);
    fileIo.writeSync(file.fd, enc.buffer, { offset: 0, length: enc.byteLength });
    fileIo.closeSync(file);
  }

  // 读某个 profile 的 selected-map
  static async load(context: Context, profileId: string): Promise<Record<string, string>> {
    const data = await SelectedMapStore.loadFile(context);
    return data.profiles[profileId] ?? {};
  }

  // 记录一次选择（组 → 节点）
  static async record(context: Context, profileId: string, group: string, proxy: string): Promise<void> {
    const data = await SelectedMapStore.loadFile(context);
    const map = data.profiles[profileId] ?? {};
    map[group] = proxy;
    data.profiles[profileId] = map;
    await SelectedMapStore.saveFile(context, data);
  }

  // 读持久化模式（未设置返回 ''）
  static async loadMode(context: Context): Promise<string> {
    const data = await SelectedMapStore.loadFile(context);
    return data.mode ?? '';
  }

  // 持久化模式
  static async saveMode(context: Context, mode: string): Promise<void> {
    const data = await SelectedMapStore.loadFile(context);
    data.mode = mode;
    await SelectedMapStore.saveFile(context, data);
  }
}
