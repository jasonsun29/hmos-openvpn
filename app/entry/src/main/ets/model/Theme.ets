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
 * UI 2.0（HarmonyOS 原生质感）：
 *   - 背景改为系统灰（#F2F3F5 / #1C1C1E），卡片白色分层
 *   - 新增玻璃 token（glassCard/glassNav，半透明底 + backgroundBlurStyle）
 *   - 新增语义色（success/warning/danger）+ 主色软底（primarySoft 选中态）
 */
import { ConfigurationConstant } from '@kit.AbilityKit';

export enum ThemeMode {
  Light = 'light',
  Dark = 'dark',
  System = 'system'
}

export class ThemeColors {
  primary: string;       // 主色（可自定义）
  background: string;    // 页面背景（系统灰）
  card: string;          // 实色卡片
  glassCard: string;     // 玻璃卡片底（半透明，配 backgroundBlurStyle）
  glassNav: string;      // 侧栏玻璃底
  textPrimary: string;   // 主文字
  textSecondary: string; // 次要文字
  divider: string;       // 分隔线
  success: string;       // 语义色：成功
  warning: string;       // 语义色：警告
  danger: string;        // 语义色：危险
  primarySoft: string;   // 主色 12% 透明底（选中态高亮）

  constructor(primary: string, background: string, card: string, glassCard: string,
    glassNav: string, textPrimary: string, textSecondary: string, divider: string,
    success: string, warning: string, danger: string, primarySoft: string) {
    this.primary = primary;
    this.background = background;
    this.card = card;
    this.glassCard = glassCard;
    this.glassNav = glassNav;
    this.textPrimary = textPrimary;
    this.textSecondary = textSecondary;
    this.divider = divider;
    this.success = success;
    this.warning = warning;
    this.danger = danger;
    this.primarySoft = primarySoft;
  }
}

/** UI 2.0 尺寸 token：圆角/留白/间距三级 */
export class ThemeDimen {
  static readonly RadiusCard = 20;   // 大卡片圆角
  static readonly RadiusRow = 16;    // 行卡片圆角
  static readonly RadiusItem = 12;   // 内部元素
  static readonly PagePad = 16;      // 页面边距
  static readonly CardPad = 16;      // 卡片内 padding
  static readonly GapS = 8;          // 间距：小
  static readonly GapM = 12;         // 间距：中
  static readonly GapL = 16;         // 间距：大
}

export class ThemeManager {
  // UI 2.0 系统灰底 + 玻璃分层
  static lightColors: ThemeColors = new ThemeColors(
    '#007AFF', '#F2F3F5', '#FFFFFF', 'rgba(255,255,255,0.75)', 'rgba(250,250,252,0.85)',
    '#1A1A1A', '#8A8A8E', '#E5E5EA', '#34C759', '#FF9F0A', '#FF453A', '#007AFF1F');
  static darkColors: ThemeColors = new ThemeColors(
    '#0A84FF', '#1C1C1E', '#2C2C2E', 'rgba(44,44,46,0.72)', 'rgba(28,28,30,0.85)',
    '#E8E8E8', '#9898A5', '#3A3A3C', '#30D158', '#FFD60A', '#FF453A', '#0A84FF1F');

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
    // primarySoft 跟随自定义主色（12% 透明）
    return new ThemeColors(customPrimary, base.background, base.card, base.glassCard,
      base.glassNav, base.textPrimary, base.textSecondary, base.divider,
      base.success, base.warning, base.danger, customPrimary + '1F');
  }
}
