/*
 * hmos-openvpn T2: AppService 单例服务门面
 * UI 侧统一数据入口（对齐 ClashBox ClashViewModel 的职责，但轻量化）
 * 依赖：proxy_core 的 SocketProxyService（RPC 客户端，连 VPN 进程 socket）
 * 职责：
 *   - 核心生命周期（initClash/start/stop）
 *   - 数据查询（proxyGroups/traffic/providers）
 *   - 配置下发（loadConfig/validateConfig）
 *   - 状态归属（Preferences: 主题/语言/端口/激活订阅）
 * 修复：
 *   P0-4 VPN 断连心跳检测（5s 一次 ping，3 次连续失败 AppStorage 通知 UI）
 */
import { common, Want } from '@kit.AbilityKit';
import { vpnExtension } from '@kit.NetworkKit';
import { preferences } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
// P2-13 文件 API 统一：所有文件操作走 fileIo（@kit.CoreFileKit），删除 fs import
import { SocketProxyService, getHome, ProfileRepo, UpdateConfigParams, ClashConfig, ActivationStore, SelectedMapStore } from 'proxy_core';
import { CoreState, CoreStateType, ClashErrorCode } from '../model/CoreState';
import { ThemeMode } from '../model/Theme';
import { SettingsRepository } from '../repository/SettingsRepository';
import { GeoDataInstaller } from '../installer/GeoDataInstaller';
import { DiagnosticCollector } from '../collector/DiagnosticCollector';
import { SubscriptionUpdater } from './SubscriptionUpdater';

export class AppService {
  private static instance: AppService | undefined;
  private context: common.UIAbilityContext | undefined;
  private uiContext: UIContext | undefined;
  private pref: preferences.Preferences | undefined;
  private proxyService: SocketProxyService | undefined;
  private profileRepo: ProfileRepo | undefined;
  coreState: CoreState = new CoreState();
  // P0-4 心跳检测
  private heartbeatTimer: number = -1;
  private heartbeatFailCount: number = 0;
  private static readonly HEARTBEAT_INTERVAL_MS = 5000;
  private static readonly HEARTBEAT_FAIL_THRESHOLD = 3;

  static getInstance(): AppService {
    if (!AppService.instance) {
      AppService.instance = new AppService();
    }
    return AppService.instance;
  }

  async init(context: common.UIAbilityContext, uiContext: UIContext): Promise<void> {
    this.context = context;
    this.uiContext = uiContext;
    // P2-1 SettingsRepository 单例初始化（取代原来 AppService 内嵌的 Prefs 逻辑）
    await SettingsRepository.getInstance().init(context);
    this.pref = await preferences.getPreferences(context, 'app_settings');
    // P1-2 ActivationStore 单例初始化（Prefs + 跨进程文件 + Go yaml 同步 集中）
    await ActivationStore.getInstance().init(context);
    // 核心工作目录
    const home = await getHome(context);
    console.log('AppService', 'home=' + home);
    // ProfileRepo 初始化（订阅元数据 → RDB，T2.4）
    this.profileRepo = new ProfileRepo();
    await this.profileRepo.init(context);
    // P2-1 GeoX 数据内置委派给 GeoDataInstaller
    await GeoDataInstaller.install(context);
    // P2-5 订阅自动更新 worker 安装（profileRepo 必须先初始化）
    if (this.profileRepo) {
      SubscriptionUpdater.getInstance().install(context, this.profileRepo);
    }
    // SocketProxyService 初始化（需要 context + promptAction）
    this.proxyService = new SocketProxyService();
    if (this.uiContext) {
      this.proxyService.init(context, this.uiContext.getPromptAction());
    }
  }

  getProxyService(): SocketProxyService | undefined {
    return this.proxyService;
  }

  // P0-4 启动心跳检测（VPN 开后调用）
  startHeartbeat(): void {
    if (this.heartbeatTimer !== -1) {
      return; // 已在运行
    }
    this.heartbeatFailCount = 0;
    // 初始为 alive
    AppStorage.setOrCreate('vpnAlive', true);
    this.heartbeatTimer = setInterval(() => {
      this.pingCore();
    }, AppService.HEARTBEAT_INTERVAL_MS);
    console.log('Heartbeat', 'startHeartbeat, interval=' + AppService.HEARTBEAT_INTERVAL_MS + 'ms');
  }

  // P0-4 停止心跳（VPN 关后调用）
  stopHeartbeat(): void {
    if (this.heartbeatTimer !== -1) {
      clearInterval(this.heartbeatTimer);
      this.heartbeatTimer = -1;
    }
    this.heartbeatFailCount = 0;
    AppStorage.setOrCreate('vpnAlive', false);
  }

  // P0-4 心跳探测：调轻量 RPC，连续 3 次失败 → 标记 alive=false
  private async pingCore(): Promise<void> {
    const svc: SocketProxyService | undefined = this.proxyService;
    if (!svc) {
      this.markAlive(false);
      return;
    }
    try {
      // 调 vpnConfigIsLoad，最轻量的 RPC（不拉代理组 / 不拉流量）
      const ready: boolean = await svc.vpnConfigIsLoad();
      if (ready) {
        this.markAlive(true);
      } else {
        this.markAlive(false);
      }
    } catch (e) {
      this.markAlive(false);
      const msg: string = (e instanceof Error) ? e.message : String(e);
      console.warn('Heartbeat', 'ping failed: ' + msg);
    }
  }

  private markAlive(alive: boolean): void {
    if (alive) {
      this.heartbeatFailCount = 0;
      if (AppStorage.get<boolean>('vpnAlive') !== true) {
        AppStorage.setOrCreate('vpnAlive', true);
        console.log('Heartbeat', 'vpnAlive → true');
      }
    } else {
      this.heartbeatFailCount++;
      if (this.heartbeatFailCount >= AppService.HEARTBEAT_FAIL_THRESHOLD
          && AppStorage.get<boolean>('vpnAlive') !== false) {
        AppStorage.setOrCreate('vpnAlive', false);
        console.warn('Heartbeat', 'vpnAlive → false (连续 ' + this.heartbeatFailCount + ' 次失败)');
      }
    }
  }

  // 加载激活的订阅配置到核心（开 VPN 前必须执行，否则核心 currentConfig=nil 崩溃）
  async loadActiveProfile(): Promise<boolean> {
    const svc = this.proxyService;
    if (!svc) return false;
    const activeId = await this.getActiveProfileId();
    if (activeId === '') return false;
    try {
      const params: UpdateConfigParams = {
        'profile-id': activeId,
        config: new ClashConfig(),
        params: {
          'is-patch': false,
          'is-compatible': false,
          // P3 持久化：恢复上次选择的组节点（跨进程共享文件）
          'selected-map': this.context
            ? await SelectedMapStore.load(this.context, activeId) : {},
          'override-dns': false,
          'test-url': 'https://www.gstatic.com/generate_204'
        }
      };
      await svc.loadConfig(params);
      console.log('AppService', 'loadActiveProfile OK id=' + activeId);
      return true;
    } catch (e) {
      const msg: string = (e instanceof Error) ? e.message : String(e);
      console.error('AppService', 'loadActiveProfile failed: ' + msg);
      return false;
    }
  }

  getProfileRepo(): ProfileRepo | undefined {
    return this.profileRepo;
  }

  // ---- Preferences 状态归属（P2-1 委派到 SettingsRepository）----
  async getPrefString(key: string, def: string): Promise<string> {
    return await SettingsRepository.getInstance().getString(key, def);
  }

  async setPrefString(key: string, value: string): Promise<void> {
    await SettingsRepository.getInstance().setString(key, value);
  }

  async getThemeMode(): Promise<ThemeMode> {
    return await SettingsRepository.getInstance().getThemeMode();
  }

  async setThemeMode(mode: ThemeMode): Promise<void> {
    await SettingsRepository.getInstance().setThemeMode(mode);
  }

  // P1-2 代理到 ActivationStore（集中处理 Prefs + 跨进程文件 + yaml 同步）
  async getActiveProfileId(): Promise<string> {
    return await ActivationStore.getInstance().getActiveProfileId();
  }

  async setActiveProfileId(id: string): Promise<void> {
    await ActivationStore.getInstance().setActiveProfileId(id);
  }

  // P1-11 手动触发一次心跳（应用回前台、页面 onPageShow 时调用）
  // 原本 pingCore 是 private（只被 setInterval 调用），公开一个立即触发入口
  async pingCoreNow(): Promise<void> {
    await this.pingCore();
  }

  // P1-4 TUN 重建：L3 变更（DNS/TUN 栈）需要 stopVpn → load → startVpn
  // 1. 先将 patch 写入 Prefs pendingL3Patch，供 VPN 进程 onCreate 读取
  // 2. 然后 stopVpn → sleep 800ms → startVpn（VPN 进程重启时会读 pending patch）
  async rebuildTun(l3Patch: Record<string, Object>): Promise<boolean> {
    const context = this.context;
    if (!context) return false;
    // 1. 写 pendingL3Patch 到 Prefs（VPN 进程读取后清除）
    try {
      await this.setPrefString('pending_l3_patch', JSON.stringify(l3Patch));
    } catch (e) {
      const msg: string = (e instanceof Error) ? e.message : String(e);
      console.error('TUN', '写 pendingL3Patch 失败: ' + msg);
      return false;
    }
    // 2. 重建 TUN：stopVpn → sleep → startVpn
    const vpnWant: Want = {
      deviceId: '',
      bundleName: context.abilityInfo.bundleName,
      abilityName: 'ClashVpnAbility',
      parameters: { requestId: Date.now() }
    };
    try {
      await vpnExtension.stopVpnExtensionAbility(vpnWant);
      // 等待 VPN 进程释放 TUN fd / socket 资源
      await new Promise<void>((r) => setTimeout(r, 800));
      await vpnExtension.startVpnExtensionAbility(vpnWant);
      console.log('TUN', 'TUN 重建完成');
      return true;
    } catch (e) {
      const msg: string = (e instanceof Error) ? e.message : String(e);
      console.error('TUN', 'TUN 重建失败: ' + msg);
      return false;
    }
  }

  // ---- 核心生命周期（T2.1）----
  setCoreState(state: CoreStateType, subCode: ClashErrorCode = ClashErrorCode.NONE,
    message: string = ''): void {
    this.coreState = new CoreState(state, subCode, message);
  }

  // P2-1 GeoX 数据内置已抽到 installer/GeoDataInstaller.install
  // P2-1 静态 readFile/writeFile 已抽到 proxy_core/fileUtils

  // P3-3 公共化：formatBytes 多处重复，统一在 AppService 静态方法供其他模块引用
  static formatBytes(bytes: number): string {
    if (bytes >= 1024 * 1024 * 1024) return (bytes / (1024 * 1024 * 1024)).toFixed(2) + ' GB';
    if (bytes >= 1024 * 1024) return (bytes / (1024 * 1024)).toFixed(2) + ' MB';
    if (bytes >= 1024) return (bytes / 1024).toFixed(1) + ' KB';
    return bytes + ' B';
  }

  // P2-1 一键日志导出委派给 DiagnosticCollector.exportLogs（保留 facade 兼容现有调用方）
  async exportLogs(): Promise<string> {
    if (!this.context) return 'no context';
    return await DiagnosticCollector.exportLogs(this.context, this.coreState, {
      '激活订阅': await this.getActiveProfileId(),
      '主题': await SettingsRepository.getInstance().getThemeMode()
    });
  }

  // P2-2 fileExists 已统一到 proxy_core/fileUtils（外部通过 import { fileExists } from 'proxy_core' 使用）
}
