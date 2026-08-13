/*
 * P3 全局模式语义修复（无 Go 重编译约束下的 yaml 层方案）：
 *
 * 背景：
 *   1. 多数机场订阅的 yaml 没有 GLOBAL 组 → 核心自动创建 NewSelector("GLOBAL", [全部组])，
 *      成员只有组、连 DIRECT 都没有；若 yaml 自带 GLOBAL 且只列 DIRECT/REJECT 等特殊项，
 *      则全局模式下无法选择真实节点。
 *   2. 核心 Selector.Set 校验成员归属；ForceSet 不校验但 selectedProxy() 找不到名字时
 *      会回退到 proxies[0]（常为 DIRECT）→ 全局模式变成"全局直连"。
 *
 * 方案：在 Go 格式 yaml（<id>.yaml）同步时：
 *   - 无 GLOBAL 组 → 在 proxy-groups: 后插入 GLOBAL 组，
 *     成员 = DIRECT + REJECT + 全部组名 + 全部节点名；
 *   - 有 GLOBAL 组 → 用同样的全集扩展其 proxies 列表。
 * 只做文本级替换/插入，其余内容逐字节不动。
 *
 * 缩进风格：自适应原文件（"  - name:" 内联风格 与 "-\n  name:" 独立 dash 风格都兼容），
 * 列表项按首项缩进匹配，避免吞掉下一个组的 dash 行。
 */
import { parse } from 'yaml';

function quote(name: string): string {
  return "'" + name.replace(/'/g, "''") + "'";
}

export function collectYamlNames(content: string): Array<string> {
  const names: Array<string> = [];
  try {
    const doc = parse(content) as Record<string, Object>;
    const groups = doc['proxy-groups'] as Array<Record<string, Object>>;
    const proxies = doc['proxies'] as Array<Record<string, Object>>;
    const push = (n: string): void => {
      if (n !== undefined && n !== '' && n !== 'GLOBAL' && !names.includes(n)) {
        names.push(n);
      }
    };
    (groups ?? []).forEach((g: Record<string, Object>) => push(g['name'] as string));
    (proxies ?? []).forEach((p: Record<string, Object>) => push(p['name'] as string));
  } catch (e) {
    console.error('YamlGlobalPatch', 'collectYamlNames failed: ' + String(e));
  }
  return names;
}

function buildGlobalBlock(dashIndent: string, members: Array<string>): string {
  const keyIndent = dashIndent + '  ';
  const itemIndent = keyIndent + '  ';
  const lines = members.map((n: string) => itemIndent + '- ' + quote(n));
  return dashIndent + '-\n' +
    keyIndent + 'name: GLOBAL\n' +
    keyIndent + 'type: select\n' +
    keyIndent + 'proxies:\n' +
    lines.join('\n') + '\n';
}

export function patchGlobalGroupInYaml(content: string): string {
  try {
    const doc = parse(content) as Record<string, Object>;
    const groups = doc['proxy-groups'] as Array<Record<string, Object>>;
    const globalGroup = (groups ?? []).find((g: Record<string, Object>) => g['name'] === 'GLOBAL');
    const names = collectYamlNames(content);
    const members: Array<string> = ['DIRECT', 'REJECT'];
    for (const n of names) {
      if (!members.includes(n)) {
        members.push(n);
      }
    }

    // proxy-groups: 行定位 + 原文件缩进风格探测
    const keyRe = /^([ \t]*)proxy-groups:[ \t]*\r?\n/m;
    const km = keyRe.exec(content);
    if (!km) {
      return content;
    }
    const after = content.slice(km.index + km[1].length);
    const dashRe = /^([ \t]*)-[ \t]*(?:name:|$)/m;
    const dm = dashRe.exec(after);
    const dashIndent = dm && dm[1] !== undefined ? dm[1] : (km[1] ?? '') + '  ';

    if (!globalGroup) {
      // 无 GLOBAL 组：插入到 proxy-groups: 行之后
      const block = buildGlobalBlock(dashIndent, members);
      return content.slice(0, km.index + km[1].length) + block + content.slice(km.index + km[1].length);
    }

    // 已有 GLOBAL 组：定位其 proxies 列表并替换为全集
    // 内联风格：  - name: GLOBAL
    const reInline = /(^[ \t]*-[ \t]*name:\s*["']?GLOBAL["']?\s*\r?\n(?:[^\n]*\n)*?^[ \t]*proxies:[ \t]*\r?\n)((?:^[ \t]+-[^\n]*\r?\n)*)/m;
    // 独立 dash 风格：-\n  name: GLOBAL
    const reDash = /(^[ \t]*-[ \t]*\r?\n[ \t]*name:\s*["']?GLOBAL["']?\s*\r?\n(?:[^\n]*\n)*?^[ \t]*proxies:[ \t]*\r?\n)((?:^[ \t]+-[^\n]*\r?\n)*)/m;
    let m = reInline.exec(content);
    if (!m) {
      m = reDash.exec(content);
    }
    if (!m || m[2] === undefined) {
      return content;
    }
    const existing = (globalGroup['proxies'] as Array<string>) ?? [];
    const merged: Array<string> = [];
    for (const n of existing.concat(names)) {
      if (n !== undefined && n !== '' && n !== 'GLOBAL' && !merged.includes(n)) {
        merged.push(n);
      }
    }
    const indentMatch = /^([ \t]+)-/.exec(m[2] ?? '');
    const itemIndent = indentMatch && indentMatch[1] !== undefined ? indentMatch[1] : dashIndent + '    ';
    const lines = merged.map((n: string) => itemIndent + '- ' + quote(n));
    const replaced = m[1] + lines.join('\n') + '\n';
    return content.slice(0, m.index) + replaced + content.slice(m.index + m[0].length);
  } catch (e) {
    console.error('YamlGlobalPatch', 'patchGlobalGroupInYaml failed: ' + String(e));
    return content;
  }
}
