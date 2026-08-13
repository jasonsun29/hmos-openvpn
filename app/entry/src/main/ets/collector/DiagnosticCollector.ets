/*
 * hmos-openvpn P2-1: DiagnosticCollector
 * 一键日志导出：收集关键状态到日志文件，便于用户反馈时附在 issue
 */
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { getHome, writeFile } from 'proxy_core';
import { CoreState } from '../model/CoreState';
import { GeoDataInstaller } from '../installer/GeoDataInstaller';

export class DiagnosticCollector {
  static async exportLogs(
    context: common.Context,
    coreState: CoreState,
    extra: Record<string, string> = {}
  ): Promise<string> {
    try {
      const home = await getHome(context);
      const logPath = home + '/diagnostics.txt';
      const lines: Array<string> = [];
      lines.push('=== hmos-openvpn 诊断信息 ===');
      lines.push('时间: ' + new Date().toISOString());
      lines.push('核心状态: ' + coreState.state + ' (subCode=' + coreState.subCode + ')');
      lines.push('工作目录: ' + home);
      for (const k of Object.keys(extra)) {
        lines.push(k + ': ' + extra[k]);
      }
      // 文件系统状态
      const geoFiles = await GeoDataInstaller.verify(home);
      for (const f of geoFiles) {
        lines.push(f.name + ': ' + (f.ok ? '存在' : '缺失'));
      }
      const content = lines.join('\n') + '\n';
      const encoder = new util.TextEncoder();
      await writeFile(logPath, encoder.encodeInto(content));
      return logPath;
    } catch (e) {
      const msg: string = (e instanceof Error) ? e.message : String(e);
      return '导出失败: ' + msg;
    }
  }
}