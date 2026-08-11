/*
 * hmos-openvpn T2: AppService 单例服务门面
 * UI 侧统一数据入口（对齐 ClashBox ClashViewModel 的职责，但轻量化）
 * 依赖：proxy_core 的 SocketProxyService（RPC 客户端，连 VPN 进程 socket）
 * 职责：
 *   - 核心生命周期（initClash/start/stop）
 *   - 数据查询（proxyGroups/traffic/providers）
 *   - 配置下发（loadConfig/validateConfig）
 *   - 状态归属（Preferences: 主题/语言/端口/激活订阅）
 */
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { SocketProxyService, getHome } from 'proxy_core';
import { CoreState, CoreStateType, ClashErrorCode } from '../model/CoreState';
import { ThemeMode } from '../model/Theme';

export class AppService {
  private static instance: AppService | undefined;
  private context: common.UIAbilityContext | undefined;
  private uiContext: UIContext | undefined;
  private pref: preferences.Preferences | undefined;
  private proxyService: SocketProxyService | undefined;
  coreState: CoreState = new CoreState();

  static getInstance(): AppService {
    if (!AppService.instance) {
      AppService.instance = new AppService();
    }
    return AppService.instance;
  }

  async init(context: common.UIAbilityContext, uiContext: UIContext): Promise<void> {
    this.context = context;
    this.uiContext = uiContext;
    // Preferences 初始化
    this.pref = await preferences.getPreferences(context, 'app_settings');
    // 核心工作目录
    const home = await getHome(context);
    console.log('T2', 'home=' + home);
    // SocketProxyService 初始化（需要 context + promptAction）
    this.proxyService = new SocketProxyService();
    if (this.uiContext) {
      this.proxyService.init(context, this.uiContext.getPromptAction());
    }
  }

  getProxyService(): SocketProxyService | undefined {
    return this.proxyService;
  }

  // ---- Preferences 状态归属（T2.4）----
  async getPrefString(key: string, def: string): Promise<string> {
    if (!this.pref) return def;
    const v = await this.pref.get(key, def);
    return v as string;
  }

  async setPrefString(key: string, value: string): Promise<void> {
    if (!this.pref) return;
    await this.pref.put(key, value);
    await this.pref.flush();
  }

  async getThemeMode(): Promise<ThemeMode> {
    const v = await this.getPrefString('theme_mode', ThemeMode.System);
    return v as ThemeMode;
  }

  async setThemeMode(mode: ThemeMode): Promise<void> {
    await this.setPrefString('theme_mode', mode);
  }

  async getActiveProfileId(): Promise<string> {
    return await this.getPrefString('active_profile_id', '');
  }

  async setActiveProfileId(id: string): Promise<void> {
    await this.setPrefString('active_profile_id', id);
  }

  // ---- 核心生命周期（T2.1）----
  setCoreState(state: CoreStateType, subCode: ClashErrorCode = ClashErrorCode.NONE,
    message: string = ''): void {
    this.coreState = new CoreState(state, subCode, message);
  }
}
