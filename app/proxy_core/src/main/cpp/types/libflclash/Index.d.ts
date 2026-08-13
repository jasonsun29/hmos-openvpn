
export const initClash: (path: string, version: string) => void;
export const startTun: (fd: number, callback: (id: number, fd: number) => void) => number;
export const getVpnOptions: () => string;
export const setFdMap: (fd: number) => void;
export const stopTun: () => void;
export const forceGc: () => void;
export const validateConfig: (paramsString: string) => Promise<string>;
export const updateConfig: (paramsString: string) => Promise<string>;
export const getCountryCode: (ip: string) => Promise<string>
export const getProxies: () => string;
export const changeProxy: (params: string) => Promise<string>;
export const getTraffic: () => string;
export const getTotalTraffic: () => string;
export const resetTraffic: () => void;
export const asyncTestDelay: (paramsString: string) => Promise<string>;
export const getExternalProviders: () => string;
export const getExternalProvider: (name: string) => string;
export const updateExternalProvider: (name: string) => Promise<string>;
export const sideLoadExternalProvider: (name: string, data: Uint8Array) => Promise<string>;
export const updateGeoData: (type: string, name: string) => Promise<string>;
export const getConnections: () => Promise<string>;
export const closeConnections: () => string;
export const closeConnection: (connectionId: string) => string;
export const getRequestList: () => string;
export const clearRequestList: () => string;
export const registerMessage: (callback: (message: string, value: string) => void) => void;
export const startLog: (callback: (message: string, value: string) => void) => string;
export const startListener: () => void
export const stopListener: () => void
export const stopLog: () => void;
export const startIpc: (path) => void;

// P3-9（t38）：updateDns NAPI 已导出但**故意不接入**。
// 签名：updateDns(dnsList: string) —— 逗号分隔的 DNS 地址串（Go 侧 GetValueStringUtf8 读 args[0]，非数组）。
// 弃用理由（2026-08-14 决策）：
//   1. OHOS 侧 dns.UpdateSystemDNS 只替换核心自身 systemResolver（fake-ip 网关 172.19.0.2），
//      不触碰系统 DNS——收益边际；
//   2. TUN 重建/断连窗口内 172.19.0.2 不可达时，核心域名解析整体失效 → 全断网风险；
//   3. 现网验证（M2 + P3 真机）fake-ip DNS 接管已工作正常，无需此调用。
// 若未来确需 fake-ip 网关接管，接入点：ClashVpnAbility.loadActiveConfig 的 setTunOptions 之后
// 调 updateDns('172.19.0.2')，onDestroy 调 updateDns('') 恢复。
export const updateDns: (dnsList: string) => Promise<void>;
