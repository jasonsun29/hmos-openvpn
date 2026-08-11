/*
 * hmos-openvpn T1.2: 主题系统（亮/暗/跟随系统三档）
 * 对齐 Clash Verge 原版色值：
 *   亮色: 主色 #007AFF, 背景 #F5F5F5, 卡片 #FFFFFF, 文字 #1A1A1A
 *   暗色: 主色 #0A84FF, 背景 #2E303D, 卡片 #3A3C4A, 文字 #E8E8E8
 */
import { ConfigurationConstant } from '@kit.AbilityKit';

export enum ThemeMode {
  Light = 'light',
  Dark = 'dark',
  System = 'system'
}

export class ThemeColors {
  primary: string;       // 主色
  background: string;    // 页面背景
  card: string;          // 卡片背景
  textPrimary: string;   // 主文字
  textSecondary: string; // 次要文字
  divider: string;       // 分隔线

  constructor(primary: string, background: string, card: string, textPrimary: string,
    textSecondary: string, divider: string) {
    this.primary = primary;
    this.background = background;
    this.card = card;
    this.textPrimary = textPrimary;
    this.textSecondary = textSecondary;
    this.divider = divider;
  }
}

export class ThemeManager {
  static lightColors: ThemeColors = new ThemeColors('#007AFF', '#F5F5F5', '#FFFFFF', '#1A1A1A', '#8A8A8E', '#E5E5EA');
  static darkColors: ThemeColors = new ThemeColors('#0A84FF', '#2E303D', '#3A3C4A', '#E8E8E8', '#9898A5', '#454752');

  static modeToColorMode(mode: ThemeMode): ConfigurationConstant.ColorMode {
    switch (mode) {
      case ThemeMode.Light:
        return ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
      case ThemeMode.Dark:
        return ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
      default:
        return ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
    }
  }

  static getColors(isDark: boolean): ThemeColors {
    return isDark ? ThemeManager.darkColors : ThemeManager.lightColors;
  }
}
