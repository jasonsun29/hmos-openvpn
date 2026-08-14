import { socket, vpnExtension } from '@kit.NetworkKit';
import {  RpcResult } from './RpcRequest';
import { JSON, util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { ClashRpcType, IClashManager, VpnRawOptions } from './IClashManager';
import { ConnectionInfo, IpInfo, LogInfo, Provider, ProxyGroup, ProxyMode,
  Traffic } from '../models/Common';
import { fileIo, fileUri } from "@kit.CoreFileKit";
import { PromptAction } from '@kit.ArkUI';
import { UpdateConfigParams } from '../models/ClashConfig';
import { checkIp, queryCurrentIpInfo } from '../Request';
import { Fd, ParseProxyGroup, VpnOptions } from './FlClashVpnService';
// P1-1 移除 libflclash.so import：UI 进程走 IPC，不走 NAPI
// import { getVpnOptions, setFdMap } from 'libflclash.so';
import { Address, isIpv4, isIpv6, VpnConfig } from './CommonVpnService';

/*
 * hmos-openvpn P0-2 toast 限频：同一消息 1s 内合并计数
 * 场景：100+ 节点测速全部 RPC 失败时，原代码会 showToast 100+ 次造成 UI 假死
 * 策略：1s 内的同消息合并，只显示第一条；不同消息独立计数
 */
class ToastThrottler {
  private static lastMsg: string = ''
  private static lastAt: number = 0
  private static count: number = 0
  private static lastDiffMsg: string = ''
  private static lastDiffAt: number = 0

  static show(prompt: PromptAction | undefined, msg: string): void {
    if (!prompt) return
    const now = Date.now()
    if (msg === ToastThrottler.lastMsg) {
      if (now - ToastThrottler.lastAt < 1000) {
        ToastThrottler.count++
        return
      }
      // 超 1s：如果之前合并了计数，补一条尾提示
      if (ToastThrottler.count > 1) {
        prompt.showToast({ message: `${msg}（合并 ${ToastThrottler.count} 条）` })
        ToastThrottler.count = 0
        ToastThrottler.lastAt = now
        return
      }
    } else {
      // 不同消息：也要限频（1s 内最多 1 次）
      if (msg === ToastThrottler.lastDiffMsg && now - ToastThrottler.lastDiffAt < 1000) {
        return
      }
      ToastThrottler.lastDiffMsg = msg
      ToastThrottler.lastDiffAt = now
    }
    ToastThrottler.lastMsg = msg
    ToastThrottler.lastAt = now
    ToastThrottler.count = 1
    prompt.showToast({ message: msg })
  }
}

interface DelayInfo{
  name: string
  value: number
}
interface Snapshot{
  connections: ConnectionInfo[]
}
interface TrafficInfo{
  up: number
  down: number
}



export class SocketProxyService implements IClashManager {
  context?: common.Context
  active: boolean = false
  offlineTime: number[] = []
  static promptAction: PromptAction
  init(context: common.Context, promptAction: PromptAction) {
    this.context = context
    SocketProxyService.promptAction = promptAction
  }
  async setLogObserver(observer: (message: LogInfo) => void): Promise<()=>void> {
    return this.callbackRequest(ClashRpcType.setLogObserver, [], (message)=>{
        if(message != ""){
          observer(JSON.parse(message) as LogInfo)
        }
    })
  }
  async registerMessage(observer: (message: string) => void): Promise<()=>void> {
    return this.callbackRequest(ClashRpcType.registerOnMessage, [], observer)
  }
  async loadConfig(config: UpdateConfigParams): Promise<string> {
    // P1-5 去掉 "+ '/config'" 拼接 hack：Go 端 getProfilePath(id) 读 profiles/<id>.yaml，
    // 该文件由 ActivationStore.syncGoConfigYaml 从 <id>/config.yaml 同步生成（ArkTS 不改路径）
    // ClashVpnAbility.loadActiveConfig 也传 raw id，两端一致
    let result =  await this.sendMessageRequest(ClashRpcType.load, [JSON.stringify(config)])
    return result as string
  }
  async vailConfig(filepath: string){
    let result = await this.sendMessageRequest(ClashRpcType.validConfig, [filepath])
    return result as string;
  }
  async queryTrafficTotal(onlyProxy: boolean): Promise<Traffic> {
    let result = await this.sendMessageRequest(ClashRpcType.queryTrafficTotal, [onlyProxy])
    const json = JSON.parse(result as string) as TrafficInfo
    return new Traffic(json.up, json.down);
  } 
  async queryTrafficNow(onlyProxy: boolean): Promise<Traffic> {
    let result = await this.sendMessageRequest(ClashRpcType.queryTrafficNow,  [onlyProxy])
    const json = JSON.parse(result as string) as TrafficInfo
    return new Traffic(json.up, json.down);
  }

  async checkIpInfo(): Promise<IpInfo> {
    // let result = await checkIp()
    // let country = await queryIpInfo(result)
    // console.log(`IPtest SocketProxyService#checkIpInfo country: ${country}`)
    // if (country == "")
    //   country = await this.sendMessageRequest(ClashRpcType.getCountryCode, [result]) as string

    const ipInfo = await queryCurrentIpInfo()
    
    if (ipInfo) {
      console.log(`IPtest SocketProxyService#checkIpInfo IP: ${ipInfo.ip}, Country: ${ipInfo.country}`)
      return {
        ip: ipInfo.ip,
        country: ipInfo.country
      } as IpInfo
    }
    
    // 如果所有 API 都失败，尝试使用本地方法获取
    console.warn(`IPtest SocketProxyService#checkIpInfo 所有 API 请求失败，尝试本地方法`)
    const result = await checkIp()
    const country = await this.sendMessageRequest(ClashRpcType.getCountryCode, [result]) as string

    return {
      ip: result,
      country: country
    } as IpInfo
  }
  async queryConnections(): Promise<ConnectionInfo[]> {
    let result = await this.sendMessageRequest(ClashRpcType.queryConnections)
    const json = JSON.parse(result as string) as Snapshot
    return json.connections ?? [];
  }
  async getRequestList(): Promise<ConnectionInfo[]>{
    let result = await this.sendMessageRequest(ClashRpcType.getRequestList)
    return JSON.parse(result as string) as ConnectionInfo[]
  }
  async  clearRequestList(): Promise<boolean>{
    await this.sendMessageRequest(ClashRpcType.clearRequestList)
    return true
  }
  async closeConnection(id: string): Promise<string> {
    let result = await this.sendMessageRequest(ClashRpcType.closeConnection, [id])
    return result as string;
  }
  async clearConnections(): Promise<ConnectionInfo[]> {
    let result = await this.sendMessageRequest(ClashRpcType.clearConnections)
    const json = JSON.parse(result as string) as ConnectionInfo[]
    return json;
  }

  async queryProxyGroups(model: ProxyMode): Promise<ProxyGroup[]> {
    let result = await this.sendMessageRequest(ClashRpcType.queryProxyGroup,[model])
    return ParseProxyGroup(model, result as string)
  }
  async queryProviders(): Promise<Provider[]> {
    let result = await this.sendMessageRequest(ClashRpcType.queryProviders)
    return JSON.parse(result as string) as Provider[]
  }
  async getVpnOptions(): Promise<VpnOptions> {
    let result = await this.sendMessageRequest(ClashRpcType.vpnOptions)
    return JSON.parse(result as string) as VpnOptions
  }
  async setOptionStates(options: VpnRawOptions): Promise<string> {
    let result = await this.sendMessageRequest(ClashRpcType.setOptionState, [JSON.stringify(options)])
    return result as string
  }
  async updateProvider(provider: Provider): Promise<string> {
    return  (await this.sendMessageRequest(ClashRpcType.updateProvider,[provider.name])) as string
  }
  async upLoadProvider(provider: Provider, uri: string): Promise<string> {
    const temp = this.context?.filesDir + "/temp_provider";
    // P2-13 fileIo.copy 替代 fs.copy（API 签名一致，去掉 fileUri.getUriFromPath）
    fileIo.copy(uri, temp);
    return (await this.sendMessageRequest(ClashRpcType.uploadProvider, [provider.name, temp])) as string;
  }
  // P3-8 修正参数顺序：Go IPC 端约定 Params[0]=geoType(MMDB/ASN/GeoIp/GeoSite)、
  // Params[1]=geoName(文件名，经 Path.Resolve 拼到核心工作目录)。
  // 原签名 (geoName, geoType) 名字反了且发送顺序反了，会导致 Go 侧 switch 无匹配、RPC 挂到超时。
  // P3 真机验证：下载单个库最多 90s（Go 侧 context），UI socket 超时给 120s，
  // 否则大文件（mmdb ~13MB）还没下完 UI 就先超时报错。
  async updateGeoData(geoType: string, geoName: string): Promise<string>{
    return await (this.sendMessageRequest(ClashRpcType.updateGeoData,[geoType, geoName], 120000)) as string
  }
  async changeProxy(group: string, name: string): Promise<string> {
    let result = await this.sendMessageRequest(ClashRpcType.changeProxy,[group, name])
    return result as string
  }
  async healthCheck(proxyName: string): Promise<number> {
    // P0-1 独立短超时：3s socket 超时（不走默认 10s）
    let result = await this.sendMessageRequest(ClashRpcType.healthCheck, [proxyName, 3000], 3000)
    let info = JSON.parse(result as string) as DelayInfo
    return info.value
  }

  async healthCheckWithTimeout(proxyName: string, timeoutMs: number): Promise<number> {
    // P0-1 独立短超时：socket 超时 = timeoutMs（给 1s 余量），不走默认 10s
    let result = await this.sendMessageRequest(ClashRpcType.healthCheck, [proxyName, timeoutMs], timeoutMs + 1000)
    let info = JSON.parse(result as string) as DelayInfo
    return info.value
  }

  async startClash():Promise<boolean>{
    let json = await this.sendMessageRequest(ClashRpcType.startClash, [])
    return json as boolean
  }
  // TODO 返回运行时间,卡片和ui统一使用 需要测试,
  async getRuntime(): Promise<number> {
    let result = await this.sendMessageRequest(ClashRpcType.GetVpnRunTime)
    return result as number
  }
  // TODO startClash前需要调用判断, clash配置是否加载完成,
  // 没有加载,做友好提示,或则先加载clash配置,在启动
  async vpnConfigIsLoad(): Promise<boolean> {
    let result = await this.sendMessageRequest(ClashRpcType.VpnConfigInited)
    return result  == "true"
  }
  vpnConnection : vpnExtension.VpnConnection | undefined
  async getTunFd(config: VpnConfig): Promise<number> {
    let tunFd = -1
    try {
      this.vpnConnection = vpnExtension.createVpnConnection(this.context as common.VpnExtensionContext);
      tunFd = await this.vpnConnection.create(config)
      console.log("ClashVPN", `获取tunFd: ${tunFd}`)
      return tunFd;
    } catch (error) {
      console.log("ClashVPN", `Clash启动失败 ${error.message} => ${error.stack}` )
      this.vpnConnection?.destroy()
      return -1
    }
  }
  async stopClash():Promise<boolean>{
    let json = await this.sendMessageRequest(ClashRpcType.stopClash, [])
    return json as boolean
  }
  async reset():Promise<boolean>{
    let json = await this.sendMessageRequest(ClashRpcType.reset, [])
    return json as boolean
  }
  async ParseMessage(messageBuffer: string, resolve: (s: string| number | boolean | undefined)=>void, reject:  (err: string)=>void){
    try {
      // P1-3 调用方已按 EOF 分隔符裁剪，此处不再 replace("EOF","")
      let json = JSON.parse(messageBuffer) as RpcResult
      if (!json.error || json.error == "")
        resolve(json.result)
      else{
        // P0-2 toast 限频
        ToastThrottler.show(SocketProxyService.promptAction, JSON.stringify(json.error))
        resolve(json.error)
      }
    } catch (e) {
      console.error("ParseMessage", e, messageBuffer)
      reject("JSON解码失败: " + JSON.stringify(e))
    }
  }
  async sendMessageRequest(
    method: number,
    params: (string| number | boolean) [] = [],
    timeoutMs?: number
  ): Promise<string| number | boolean | undefined>{
    // P0-1 默认 10s，healthCheck 等场景传更短的超时
    const socketTimeout = timeoutMs ?? 10000
    console.log("sendMessageRequest " + method + " (socket timeout=" + socketTimeout + "ms)")
    // P1-3 NDJSON-with-EOF 分隔：Go 侧响应格式 = json + "EOF"
    // 之前用 200ms debounce 等齐，导致每次 RPC 至少 +200ms 延迟，且 closure 内 fullMessage='' 清空无效
    // 改为：增量接收 buffer，扫描到 "EOF" 立即裁帧解析，不再 debounce
    const FRAME_DELIM = 'EOF'
    return new Promise(async (resolve, reject)=>{
      let client: socket.LocalSocket = socket.constructLocalSocketInstance();
      let text = new util.TextDecoder()
      let buffer = ''
      let done = false
      const onFrame = (frame: string) => {
        if (done) return
        done = true
        this.ParseMessage(frame, (v) => { client.close(); resolve(v) }, (e) => { client.close(); reject(e) })
      }
      const tryExtractFrame = (): boolean => {
        const idx = buffer.indexOf(FRAME_DELIM)
        if (idx < 0) return false
        onFrame(buffer.substring(0, idx))
        buffer = buffer.substring(idx + FRAME_DELIM.length)
        return true
      }
      client.on('message', async (value: socket.LocalSocketMessageInfo) => {
        if (done) return
        const chunk = text.decodeToString(new Uint8Array(value.message), { stream: true })
        buffer += chunk
        tryExtractFrame()
      })
      setTimeout(()=>{
        if (!done) {
          reject("请求超时(" + socketTimeout + "ms)")
          client.close();
        }
      }, socketTimeout)
      client.on("error", ()=>{
        if (!done) reject("rpc client error")
      })
      // {"proxy-name":"♻️自动选择","timeout":3000}
      let socketPath = this.context?.filesDir + '/clash_go.sock'
      // || method == ClashRpcType.getRuntime 在clash_go里已实现,
      if (method == ClashRpcType.startClash || method == ClashRpcType.stopClash){
        socketPath = this.context?.filesDir + '/ClashBox.sock'
      }
      if (!await fileIo.access(socketPath))
      {
        // P0-2 toast 限频：只对用户主动启停（startClash/stopClash）提示；
        // 被动查询（连接/规则/流量轮询等）在 VPN 未启动时静默失败，
        // 避免页面轮询把"启动失败"toast 反复弹出（模拟器/未启动场景）
        if (method == ClashRpcType.startClash || method == ClashRpcType.stopClash) {
          ToastThrottler.show(SocketProxyService.promptAction, "VPN服务启动失败")
        }
        reject(new Error("VPN服务未启动"))
        return;
      }

      client.connect({address: { address: socketPath }, timeout:1000}).then(async ()=>{
        this.active = true
        client.send({ data: JSON.stringify({method, params}) });
      }).catch((e:Error)=>{
        this.active = false
        console.error("vpn服务启动失败", e.message, e.stack)
        if (e.message == "Connection refused"){
          // P0-2 toast 限频
          ToastThrottler.show(SocketProxyService.promptAction, "VPN服务被系统干掉了")
        } else {
          // P0-2 toast 限频
          ToastThrottler.show(SocketProxyService.promptAction, "vpn服务失败: " + e.message)
        }
        reject(e)
      });
    })
  }
  async callbackRequest(
    method: number,
    params: (string | number | boolean) [] = [],
    callBack: (message: string) => void
  ): Promise<() => void> {
    // P1-3 同样改为 NDJSON-with-EOF 增量解析：每次新 chunk 累加到 buffer，
    // 反复扫描 "EOF" 边界，裁出一帧后立即 JSON.parse 并回调（多用于日志/消息推送）
    const FRAME_DELIM = 'EOF'
    return new Promise(async (resolve, reject)=>{
      let tcp: socket.LocalSocket = socket.constructLocalSocketInstance();
      let buffer = ''
      const text = new util.TextDecoder()
      tcp.on('message', (value: socket.LocalSocketMessageInfo) => {
        const chunk = text.decodeToString(new Uint8Array(value.message), { stream: true })
        buffer += chunk
        let idx = buffer.indexOf(FRAME_DELIM)
        while (idx >= 0) {
          const frame = buffer.substring(0, idx)
          buffer = buffer.substring(idx + FRAME_DELIM.length)
          if (frame !== '') {
            try {
              const json = JSON.parse(frame) as RpcResult
              callBack(json.result as string)
            } catch (e) {
              const msg: string = (e instanceof Error) ? e.message : String(e)
              console.error("log error", msg, frame)
            }
          }
          idx = buffer.indexOf(FRAME_DELIM)
        }
      })
      tcp.on('error', (e: Error) => {
        reject("失败")
      });
      const socketPath = this.context?.filesDir + '/clash_go.sock'
      tcp.connect({address: { address: socketPath }, timeout:3000}).then(()=>{
        tcp.send({ data: JSON.stringify({method, params}) });
        resolve(()=>{
          tcp.close()
        })
      }).catch((e: Error)=>{
        console.log("socketProxy error", e.message)
        reject(e)
      });
    })
  }
}

export default new SocketProxyService()