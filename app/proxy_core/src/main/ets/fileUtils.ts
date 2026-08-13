/**
 * P2-13 文件工具统一入口（@kit.CoreFileKit.fileIo）：
 * - readFileUri / readFile / readText / writeFile（原有）
 * - fileExists（新增，统一入口去重）
 *
 * 之前 AppService / ClashVpnAbility / ActivationStore 重复实现 4 份，统一到此处。
 * P2-13 进一步从 @ohos.file.fs 迁移到 @kit.CoreFileKit.fileIo（新 kit API），
 *       API 签名一致，调用方代码无需改。
 */
import { fileIo, fileUri } from '@kit.CoreFileKit';

export async function readFileUri(uri: string, tempPath: string): Promise<Uint8Array | null> {
  fileIo.copy(uri, fileUri.getUriFromPath(tempPath));
  return await readFile(tempPath);
}

export async function readFile(filePath: string): Promise<Uint8Array | null> {
  if (!fileIo.accessSync(filePath)) {
    return null;
  }
  const file = fileIo.openSync(filePath, fileIo.OpenMode.READ_ONLY);
  const stats = fileIo.statSync(filePath);
  let bufSize = stats.size;
  let buf = new ArrayBuffer(bufSize);
  fileIo.readSync(file.fd, buf, { offset: 0, length: bufSize });
  fileIo.closeSync(file);
  return new Uint8Array(buf);
}

export async function readText(filePath: string): Promise<string> {
  if (!fileIo.accessSync(filePath)) {
    return '';
  }
  return await fileIo.readText(filePath);
}

export function writeFile(filePath: string, data: Uint8Array | null): void {
  if (data != null && data.byteLength > 0) {
    // P3 修复：TextEncoder.encodeInto 返回的是内部池化 ArrayBuffer 上的视图，
    // 直接写 data.buffer 会把尾部陈旧字节一起写盘（曾导致 yaml 尾部 53 行平移副本、
    // 拼出 MATCH,桔子云.in-addr.arpa 坏规则）。必须按视图 byteLength 截断写入 + TRUNC。
    const file = fileIo.openSync(filePath,
      fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
    fileIo.writeSync(file.fd, data.buffer, { offset: 0, length: data.byteLength });
    fileIo.fsyncSync(file.fd);
    fileIo.closeSync(file);
  }
}

export async function fileExists(filePath: string): Promise<boolean> {
  try {
    return await fileIo.access(filePath);
  } catch (e) {
    return false;
  }
}