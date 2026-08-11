/*
 * hmos-openvpn T1.4: CoreState 全局状态机（设计文档 §3.5.1）
 * Idle/Booting/Running/Reloading/Stopping/Error(subCode)
 * 状态转换矩阵：
 *   initClash       -> Booting
 *   vpnStarted      -> Running
 *   reloadConfig    -> Reloading -> Running
 *   vpnStopped      -> Idle
 *   异常            -> Error(subCode)
 */

// 错误子码（M1 覆盖 5 条失败路径，对应 subCode 文案映射 T1.5）
export enum ClashErrorCode {
  NONE = 0,
  ABI_MISMATCH = 1,          // nativeVersion() ABI 握手失败
  SUBSCRIPTION_FETCH_FAILED = 2, // 订阅拉取失败
  VPN_START_FAILED = 3,      // VPN 启动失败
  CONFIG_VALIDATE_FAILED = 4, // 配置校验失败
  CORE_INIT_FAILED = 5       // 核心初始化失败
}

export enum CoreStateType {
  Idle = 'Idle',
  Booting = 'Booting',
  Running = 'Running',
  Reloading = 'Reloading',
  Stopping = 'Stopping',
  Error = 'Error'
}

export class CoreState {
  state: CoreStateType = CoreStateType.Idle;
  subCode: ClashErrorCode = ClashErrorCode.NONE;
  message: string = '';
  timestamp: number = 0;

  constructor(state: CoreStateType = CoreStateType.Idle, subCode: ClashErrorCode = ClashErrorCode.NONE,
    message: string = '') {
    this.state = state;
    this.subCode = subCode;
    this.message = message;
    this.timestamp = Date.now();
  }

  isRunning(): boolean {
    return this.state === CoreStateType.Running;
  }

  isBusy(): boolean {
    return this.state === CoreStateType.Booting || this.state === CoreStateType.Reloading ||
      this.state === CoreStateType.Stopping;
  }

  isError(): boolean {
    return this.state === CoreStateType.Error;
  }
}
