/*
 * P3 重构：离线配置解析 + 全局模式端点映射（订阅结构无关）
 *
 * 原则：
 *   1. 选端点不依赖 VPN 在线——代理组/节点树直接解析本地 config.yaml（激活订阅文件在沙箱内）
 *   2. 全局模式端点 = 平铺的 "直连 + 全部组 + 全部节点"，与订阅怎么分组无关
 *   3. 映射到核心的真实机制（核心 Selector.Set 校验成员归属）：
 *      - 直连         → mode=Direct
 *      - 选组         → mode=Global + GLOBAL组→该组
 *      - 选节点       → mode=Global + GLOBAL组→包含该节点的真实组 + 该组→该节点
 *      - 未选         → mode=Global（核心默认）
 *      - 规则模式     → mode=Rule（组内选择照常生效）
 */
import { parse } from 'yaml';
import { Context } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { getHome } from './appPath';
import { readFile } from './fileUtils';
import { ProxyMode } from './models/Common';

export interface OfflineGroup {
  name: string;
  type: string;
  proxies: Array<string>;
}

export interface OfflineProxy {
  name: string;
  type: string;
  // 离线测速用：直连节点服务器测 TCP 建连延迟（未开 VPN/模拟器可用）
  server: string;
  port: number;
}

export class YamlConfigView {
  groups: Array<OfflineGroup> = [];
  nodes: Array<OfflineProxy> = [];

  isGroupName(name: string): boolean {
    return this.groups.some((g: OfflineGroup) => g.name === name);
  }

  findGroupContaining(proxyName: string): string {
    for (const g of this.groups) {
      if (g.proxies.includes(proxyName)) {
        return g.name;
      }
    }
    return '';
  }
}

export class ConfigReader {
  // 解析 yaml 文本 → 组/节点视图（失败返回空视图，调用方自行兜底）
  static parse(content: string): YamlConfigView {
    const view = new YamlConfigView();
    try {
      const doc = parse(content) as Record<string, Object>;
      const groups = doc['proxy-groups'] as Array<Record<string, Object>>;
      (groups ?? []).forEach((g: Record<string, Object>) => {
        const name = g['name'] as string;
        const type = g['type'] as string;
        if (name === undefined || name === '' || type === undefined) {
          return;
        }
        view.groups.push({ name: name, type: type, proxies: (g['proxies'] as Array<string>) ?? [] });
      });
      const proxies = doc['proxies'] as Array<Record<string, Object>>;
      (proxies ?? []).forEach((p: Record<string, Object>) => {
        const name = p['name'] as string;
        if (name === undefined || name === '') {
          return;
        }
        view.nodes.push({
          name: name,
          type: (p['type'] as string) ?? '',
          server: (p['server'] as string) ?? '',
          port: Number(p['port'] ?? 0)
        });
      });
    } catch (e) {
      console.error('ConfigReader', 'parse failed: ' + String(e));
    }
    return view;
  }

  // 读激活订阅的 config.yaml（ArkTS 格式副本）并解析
  static async read(context: Context, profileId: string): Promise<YamlConfigView> {
    try {
      const home = await getHome(context);
      const path = home + '/profiles/' + profileId + '/config.yaml';
      const data: Uint8Array | null = await readFile(path);
      if (!data) {
        return new YamlConfigView();
      }
      const text = new util.TextDecoder().decodeToString(data);
      return ConfigReader.parse(text);
    } catch (e) {
      console.error('ConfigReader', 'read failed: ' + String(e));
      return new YamlConfigView();
    }
  }
}

export interface ResolvedModeConfig {
  mode: string;
  selectedMap: Record<string, string>;
}

export class GlobalModeResolver {
  /**
   * 把应用侧状态（持久化模式 + 各选择）解析为核心启动参数。
   * persistedMap['GLOBAL'] 的语义 = 用户选的全局端点（DIRECT | 组名 | 节点名 | 空）。
   */
  static resolve(persistedMode: string, persistedMap: Record<string, string>,
    view: YamlConfigView): ResolvedModeConfig {
    const coreMap: Record<string, string> = {};
    // 组内选择对规则/全局模式都保留
    for (const k of Object.keys(persistedMap)) {
      if (k !== 'GLOBAL') {
        coreMap[k] = persistedMap[k];
      }
    }
    const endpoint = persistedMap['GLOBAL'] ?? '';
    const modeUpper = persistedMode.toUpperCase();
    if (modeUpper === ProxyMode.Rule) {
      return { mode: ProxyMode.Rule, selectedMap: coreMap };
    }
    if (endpoint === 'DIRECT') {
      return { mode: ProxyMode.Direct, selectedMap: coreMap };
    }
    if (endpoint === '') {
      // 默认全局；GLOBAL 保持核心默认选择
      return { mode: ProxyMode.Global, selectedMap: coreMap };
    }
    if (view.isGroupName(endpoint)) {
      coreMap['GLOBAL'] = endpoint;
      return { mode: ProxyMode.Global, selectedMap: coreMap };
    }
    const group = view.findGroupContaining(endpoint);
    if (group !== '') {
      coreMap['GLOBAL'] = group;
      coreMap[group] = endpoint;
      return { mode: ProxyMode.Global, selectedMap: coreMap };
    }
    // 端点对不上当前订阅（订阅更新后名字失效）：退回全局默认，避免选中失败回退 DIRECT
    console.warn('GlobalModeResolver', '端点已不存在: ' + endpoint);
    return { mode: ProxyMode.Global, selectedMap: coreMap };
  }
}
