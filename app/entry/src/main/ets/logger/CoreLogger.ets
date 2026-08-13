/*
 * hmos-openvpn P2-4: 核心日志落盘
 *
 * 背景：Go 端 core.log 落盘需要重编译，不在本次范围内。
 * 替代方案：ArkTS 侧通过 setLogObserver 订阅核心推送的 LogInfo，
 *          把每条日志追加写到 filesDir/core.log（用户可导出）。
 *
 * 实现：
 * - install(svc, filesDir): 注册 setLogObserver 回调，把日志 append 到 core.log
 * - uninstall(): 返回 setLogObserver 的 unsubscribe 句柄并关闭文件 fd
 * - rotate(maxBytes): 文件超过 maxBytes（默认 1MB）后改名 core.log.1，重开新文件
 *
 * 落盘格式：每行 = [ISO 时间][LEVEL] payload
 * 例：2026-08-12T10:23:45.123Z [info] Start a new TCP connection
 */
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { LogInfo, LogLevel, SocketProxyService } from 'proxy_core';

const LOG_FILE_NAME = 'core.log';
const DEFAULT_MAX_BYTES = 1 * 1024 * 1024; // 1MB

export class CoreLogger {
  private static instance: CoreLogger | undefined;
  private static unsubscribe: (() => void) | null = null;
  private static fd: number = -1;
  private static currentPath: string = '';
  private static maxBytes: number = DEFAULT_MAX_BYTES;
  private static textEncoder: util.TextEncoder = new util.TextEncoder();

  static getInstance(): CoreLogger {
    if (!CoreLogger.instance) {
      CoreLogger.instance = new CoreLogger();
    }
    return CoreLogger.instance;
  }

  // 注册日志订阅器：每次启动 VPN 后调用，把核心日志流落到 filesDir/core.log
  async install(svc: SocketProxyService, filesDir: string, maxBytes: number = DEFAULT_MAX_BYTES): Promise<void> {
    // 已安装则先卸载
    if (CoreLogger.unsubscribe !== null) {
      this.uninstall();
    }
    CoreLogger.maxBytes = maxBytes;
    CoreLogger.currentPath = filesDir + '/' + LOG_FILE_NAME;
    // 打开文件（追加写），不存在则创建
    try {
      // fileIo.openSync 返回 File 对象（API 12+），取 .fd 存数字句柄
      CoreLogger.fd = fileIo.openSync(
        CoreLogger.currentPath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.APPEND
      ).fd;
    } catch (e) {
      const msg: string = (e instanceof Error) ? e.message : String(e);
      console.error('CoreLogger', 'openSync 失败: ' + msg);
      return;
    }
    // 注册 setLogObserver 订阅，拿到 unsubscribe 句柄
    try {
      CoreLogger.unsubscribe = await svc.setLogObserver((info: LogInfo) => {
        this.appendLine(info);
      });
    } catch (e) {
      const msg: string = (e instanceof Error) ? e.message : String(e);
      console.error('CoreLogger', 'setLogObserver 失败: ' + msg);
      this.closeFd();
    }
  }

  // 卸载：调 unsubscribe 句柄，关闭 fd
  uninstall(): void {
    if (CoreLogger.unsubscribe !== null) {
      try {
        CoreLogger.unsubscribe();
      } catch (e) {
        // ignore
      }
      CoreLogger.unsubscribe = null;
    }
    this.closeFd();
  }

  // 把单条 LogInfo 序列化为一行并追加到文件，超过 maxBytes 则 rotate
  private appendLine(info: LogInfo): void {
    if (CoreLogger.fd < 0) return;
    const ts: string = new Date(info.time ?? Date.now()).toISOString();
    const level: string = CoreLogger.levelToString(info.logLevel);
    const payload: string = (info.payload ?? '').replace(/\n/g, '\\n');
    const line: string = '[' + ts + '][' + level + '] ' + payload + '\n';
    const bytes: Uint8Array = CoreLogger.textEncoder.encodeInto(line);
    try {
      fileIo.writeSync(CoreLogger.fd, bytes.buffer, { offset: -1, length: bytes.byteLength });
    } catch (e) {
      // 写失败一次不打扰，下一条继续
      return;
    }
    // rotate 检查
    try {
      const stat = fileIo.statSync(CoreLogger.currentPath);
      if (stat.size > CoreLogger.maxBytes) {
        this.rotate();
      }
    } catch (e) {
      // ignore
    }
  }

  // rotate：core.log → core.log.1（覆盖旧 .1），重开新 fd
  private rotate(): void {
    this.closeFd();
    try {
      // 删旧 backup
      fileIo.unlinkSync(CoreLogger.currentPath + '.1');
    } catch (e) {
      // ignore: 旧 .1 不存在
    }
    try {
      fileIo.renameSync(CoreLogger.currentPath, CoreLogger.currentPath + '.1');
    } catch (e) {
      const msg: string = (e instanceof Error) ? e.message : String(e);
      console.error('CoreLogger', 'rotate 失败: ' + msg);
      return;
    }
    try {
      CoreLogger.fd = fileIo.openSync(
        CoreLogger.currentPath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.APPEND
      ).fd;
    } catch (e) {
      const msg: string = (e instanceof Error) ? e.message : String(e);
      console.error('CoreLogger', 'rotate 后 reopen 失败: ' + msg);
    }
  }

  private closeFd(): void {
    if (CoreLogger.fd >= 0) {
      try {
        fileIo.closeSync(CoreLogger.fd);
      } catch (e) {
        // ignore
      }
      CoreLogger.fd = -1;
    }
  }

  // 返回当前日志文件的绝对路径（暴露给 DiagnosticCollector 导出用）
  static getCurrentLogPath(filesDir: string): string {
    return filesDir + '/' + LOG_FILE_NAME;
  }

  private static levelToString(level: LogLevel): string {
    switch (level) {
      case LogLevel.Debug: return 'debug';
      case LogLevel.Info: return 'info';
      case LogLevel.Warning: return 'warn';
      case LogLevel.Error: return 'error';
      default: return 'unknown';
    }
  }
}
