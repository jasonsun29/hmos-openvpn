/*
 * hmos-openvpn P2-1: SettingsRepository
 * 集中管理 Preferences 持久化（主题/语言/端口/激活订阅/Prefs key）
 * 与 AppService 解耦，可独立注入测试
 */
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { ThemeMode } from '../model/Theme';

export class SettingsRepository {
  private pref: preferences.Preferences | undefined;
  private static instance: SettingsRepository | undefined;

  static getInstance(): SettingsRepository {
    if (!SettingsRepository.instance) {
      SettingsRepository.instance = new SettingsRepository();
    }
    return SettingsRepository.instance;
  }

  async init(context: common.Context): Promise<void> {
    this.pref = await preferences.getPreferences(context, 'app_settings');
  }

  async getString(key: string, def: string): Promise<string> {
    if (!this.pref) return def;
    const v = await this.pref.get(key, def);
    return v as string;
  }

  async setString(key: string, value: string): Promise<void> {
    if (!this.pref) return;
    await this.pref.put(key, value);
    await this.pref.flush();
  }

  // ---- 主题 ----
  async getThemeMode(): Promise<ThemeMode> {
    return (await this.getString('theme_mode', ThemeMode.System)) as ThemeMode;
  }

  async setThemeMode(mode: ThemeMode): Promise<void> {
    await this.setString('theme_mode', mode);
  }
}