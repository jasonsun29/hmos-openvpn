import { socket } from '@kit.NetworkKit';
import { common } from '@kit.AbilityKit';
import { CommonVpnService } from './CommonVpnService';
import { FlClashVpnService } from './FlClashVpnService';
import { startIpc } from 'libflclash.so';


export class SocketStubService {
  server: socket.LocalSocketServer = socket.constructLocalSocketServerInstance();
  clientPool: Map<number, socket.LocalSocketConnection>
  vpnService: CommonVpnService
  constructor( context: common.Context) {
    this.clientPool = new Map()
    this.vpnService = new FlClashVpnService(context)
    this.vpnService.init()
  }

  async startService(){
    try {
      const socketPath = this.vpnService.context.filesDir + '/ClashBox.sock'
      const goPath = this.vpnService.context.filesDir + '/clash_go.sock'
      startIpc(goPath)

      await this.server.listen({ address: socketPath})
      this.server.on('connect', (client: socket.LocalSocketConnection) => {
          this.clientPool.set(client.clientId, client);
          client.on("message", (value: socket.LocalSocketMessageInfo) => {
            this.vpnService.onRemoteMessageRequest(client, value)
          })
          client.on('close', () => {
            client.off("message")
            client.off("close")
            this.clientPool.delete(client.clientId);
          });
      })
    } catch (e) {
      // P2-8 失败清理 clientPool：listen() 失败或 startIpc() 抛错时，已有 client 也要清掉
      // 原代码漏清理，导致下次 startService 时残留旧 client，IPC 路由错乱
      this.cleanup();
      console.error("socket failure", e.message)
    }
  }

  // P2-8 释放所有 client + 关闭 server，startService 失败/进程退出时调用
  private cleanup(): void {
    // ArkTS 禁止解构声明（arkts-no-destruct-decls），用 Map.values() 遍历
    for (const client of this.clientPool.values()) {
      try {
        client.off("message");
        client.off("close");
        client.close();
      } catch (e) {
        // ignore: 单个 client 关闭失败不影响其他
      }
    }
    this.clientPool.clear();
    try {
      this.server.close();
    } catch (e) {
      // ignore: server 可能未启动
    }
  }
  startVpn(){
    this.vpnService.startVpn()
  }
  stopVpn(){
    this.vpnService.stopVpn()
  }
}
function sleepTime(timeout = 100): Promise<void>{
  return new Promise((resolve)=>{
    setTimeout(resolve, timeout)
  })
}