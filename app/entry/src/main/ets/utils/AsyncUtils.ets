/*
 * hmos-openvpn P3-5: tryRunAsync 统一异步错误处理
 * 把全工程重复的 `try { await x } catch (e) { console.error(tag, msg) }`
 * 收敛为一个工具函数：失败时打日志并返回 undefined，不抛出。
 * 适用场景：失败可忽略、仅需日志的异步调用；需要 UI 提示/状态回滚的
 * 调用点仍保留各自的 try/catch。
 */
export async function tryRunAsync<T>(tag: string, fn: () => Promise<T>): Promise<T | undefined> {
  try {
    return await fn();
  } catch (e) {
    const msg: string = (e instanceof Error) ? e.message : String(e);
    console.error(tag, msg);
    return undefined;
  }
}
