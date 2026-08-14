/*
 * hmos-openvpn T1.2: 主题系统（亮/暗/跟随系统三档 + M3 主题色自定义）
 * 对齐 Clash Verge 原版色值：
 *   亮色: 主色 #007AFF, 背景 #F5F5F5, 卡片 #FFFFFF, 文字 #1A1A1A
 *   暗色: 主色 #0A84FF, 背景 #2E303D, 卡片 #3A3C4A, 文字 #E8E8E8
 * M3-2 主题色自定义：
 *   - customPrimary 为空时用各模式默认主色
 *   - 预设色板（Clash Verge 风格）+ 恢复默认
 * 修复：getColors 原来无调用方，@Provide colors 恒为浅色静态值；
 *       现在由 MainPage.applyTheme() 按 模式×自定义色 解析并响应更新。
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

  // M3-2 预设主题色（Clash Verge 风格色板；'' = 跟随模式默认）
  static readonly PRESET_COLORS: Array<string> = [
    '',
    '#007AFF',
    '#0A84FF',
    '#07C160',
    '#FF9500',
    '#FF3B30',
    '#AF52DE',
    '#5AC8FA',
    '#FF2D55',
    '#8E8E93'
  ];

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

  // 按 亮/暗 × 自定义主色 解析最终配色（M3-2）
  static getColors(isDark: boolean, customPrimary: string = ''): ThemeColors {
    const base = isDark ? ThemeManager.darkColors : ThemeManager.lightColors;
    if (customPrimary === '' || customPrimary === base.primary) {
      return base;
    }
    return new ThemeColors(customPrimary, base.background, base.card,
      base.textPrimary, base.textSecondary, base.divider);
  }
}
