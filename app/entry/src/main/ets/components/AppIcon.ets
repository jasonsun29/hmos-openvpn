/*
 * UI 2.0 图标体系：SymbolGlyph 统一封装（全面替代 emoji/字符图形）
 * 资源名已对照官方 SDK 符号表（toolchains/id_defined.json，4032 个系统符号）逐一核实。
 * $r() 仅接受字面量资源路径 → 用 switch 显式映射，不拼接字符串。
 */

/** 图标名常量（与 AppIcon.res 的映射一一对应） */
export class AppIconName {
  static readonly Home: string = 'house';
  static readonly HomeFill: string = 'house_fill';
  static readonly Proxies: string = 'square_grid_2x2';
  static readonly Profiles: string = 'square_stack_3d';
  static readonly Settings: string = 'gearshape';
  static readonly Connections: string = 'arrow_left_arrow_right';
  static readonly Rules: string = 'list_number';
  static readonly Logs: string = 'doc';
  static readonly Unlock: string = 'film';
  static readonly Logo: string = 'paperplane';
  static readonly Selector: string = 'shuffle';
  static readonly UrlTest: string = 'bolt';
  static readonly Fallback: string = 'arrow_down_to_line';
  static readonly LoadBalance: string = 'split';
  static readonly Relay: string = 'link';
  static readonly DefaultGroup: string = 'archivebox';
  static readonly Check: string = 'checkmark';
  static readonly Success: string = 'checkmark_circle_fill';
  static readonly Fail: string = 'xmark_circle_fill';
  static readonly Warn: string = 'warning';
  static readonly ChevronRight: string = 'chevron_right';
  static readonly ChevronDown: string = 'chevron_down';
  static readonly Qrcode: string = 'qrcode';
  static readonly Edit: string = 'square_and_pencil';
  static readonly Upload: string = 'upload';
  static readonly Trash: string = 'trash';
  static readonly Search: string = 'magnifyingglass';
  static readonly Clock: string = 'worldclock';
}

@Component
export struct AppIcon {
  @Prop name: string = AppIconName.Home;
  @Prop iconSize: number = 22;
  @Prop color: string = '#FFFFFF';
  @Prop weight: number = FontWeight.Medium;

  private res(): Resource {
    switch (this.name) {
      case 'house': return $r('sys.symbol.house');
      case 'house_fill': return $r('sys.symbol.house_fill');
      case 'square_grid_2x2': return $r('sys.symbol.square_grid_2x2');
      case 'square_stack_3d': return $r('sys.symbol.square_stack_3d');
      case 'gearshape': return $r('sys.symbol.gearshape');
      case 'arrow_left_arrow_right': return $r('sys.symbol.arrow_left_arrow_right');
      case 'list_number': return $r('sys.symbol.list_number');
      case 'doc': return $r('sys.symbol.doc');
      case 'film': return $r('sys.symbol.film');
      case 'paperplane': return $r('sys.symbol.paperplane');
      case 'shuffle': return $r('sys.symbol.shuffle');
      case 'bolt': return $r('sys.symbol.bolt');
      case 'arrow_down_to_line': return $r('sys.symbol.arrow_down_to_line');
      case 'split': return $r('sys.symbol.split');
      case 'link': return $r('sys.symbol.link');
      case 'archivebox': return $r('sys.symbol.archivebox');
      case 'checkmark': return $r('sys.symbol.checkmark');
      case 'checkmark_circle_fill': return $r('sys.symbol.checkmark_circle_fill');
      case 'xmark_circle_fill': return $r('sys.symbol.xmark_circle_fill');
      case 'warning': return $r('sys.symbol.warning');
      case 'chevron_right': return $r('sys.symbol.chevron_right');
      case 'chevron_down': return $r('sys.symbol.chevron_down');
      case 'qrcode': return $r('sys.symbol.qrcode');
      case 'square_and_pencil': return $r('sys.symbol.square_and_pencil');
      case 'upload': return $r('sys.symbol.upload');
      case 'trash': return $r('sys.symbol.trash');
      case 'magnifyingglass': return $r('sys.symbol.magnifyingglass');
      case 'worldclock': return $r('sys.symbol.worldclock');
      default: return $r('sys.symbol.house');
    }
  }

  build() {
    SymbolGlyph(this.res())
      .fontSize(this.iconSize)
      .fontWeight(this.weight)
      .fontColor([this.color])
  }
}
