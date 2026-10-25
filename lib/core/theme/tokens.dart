import 'package:flutter/material.dart';

/// Design tokens — a direct Dart mapping of the CSS custom properties in
/// OpenList-Client-Design.html v2.0 (:root block + 02 Design System + W7).
///
/// 读数规则：颜色、圆角、字号、间距全部来自设计稿，不要在这里发明新值。
class OlTokens {
  const OlTokens._();

  // ---- Brand（02 · 品牌色取自 OpenList Logo）----
  static const sky = Color(0xFF38BDF8);
  static const sky400 = Color(0xFF38BDF8);
  static const sky600 = Color(0xFF0EA5E9);
  static const sky700 = Color(0xFF0284C7);
  static const teal = Color(0xFF2DD4BF);
  static const teal600 = Color(0xFF14B8A6);
  static const deep = Color(0xFF0E3A46);
  static const violet = Color(0xFF7C5CFC);

  // ---- Semantic ----
  static const ok = Color(0xFF0E9F6E);
  static const okDeep = Color(0xFF0B7A63);
  static const warn = Color(0xFFF59E0B);
  static const warnDeep = Color(0xFFB47405);
  static const danger = Color(0xFFF43F5E);

  /// v1.0.47：错误提示的底色 / 描边 / 文字（原来散落在各页面的字面量）
  static const dangerSurface = Color(0xFFFFF1F3);
  static const dangerBorder = Color(0xFFF8C9D2);
  static const dangerInk = Color(0xFF8A2438);
  static const dangerDeep = Color(0xFFD92D4B);

  // ---- 文件类型色（02 · Video / Image / Doc）----
  static const typeVideo = Color(0xFF7C5CFC);
  static const typeImage = Color(0xFF2DD4BF);
  static const typeDoc = Color(0xFFF97316);
  static const typeAudio = Color(0xFFEC4899);
  static const typeFolder = Color(0xFF38BDF8);
  static const typeOther = Color(0xFF64748B);

  // ---- Radii（02 · 20 卡片 / 14 面板 / 9 按钮 / 99 胶囊）----
  static const r1 = 22.0; // 旧：卡片 / 弹层
  static const r2 = 16.0; // 旧：面板 / 缩略图
  static const r3 = 12.0;
  static const r4 = 9.0; // 按钮 / 字段
  static const rCard = 20.0;
  static const rPanel = 14.0;
  static const rField = 9.0;
  static const rPill = 99.0;

  static const gradientPrimary = LinearGradient(
    begin: Alignment(-0.9, -1),
    end: Alignment(0.9, 1),
    colors: [Color(0xFF38BDF8), Color(0xFF20C6C8)],
  );

  static const gradientBrand = LinearGradient(
    begin: Alignment(-0.8, -1),
    end: Alignment(0.9, 1),
    colors: [Color(0xFF38BDF8), Color(0xFF2DD4BF)],
  );

  static const gradientAccentText = LinearGradient(
    begin: Alignment(-1, -0.4),
    end: Alignment(1, 0.4),
    colors: [Color(0xFF7DD3FC), Color(0xFF5EEAD4)],
  );

  static const deepPanel = LinearGradient(
    begin: Alignment(-0.7, -1),
    end: Alignment(0.9, 1),
    colors: [Color(0xFF0E2233), Color(0xFF123042)],
  );

  /// 品牌深色渐变（160deg）：首启欢迎页左栏/移动端头图、抽屉头部。
  /// 对应效果图 `linear-gradient(160deg,#0E3A46 0%,#0B4F63 55%,#0EA5E9 130%)`。
  static const gradientDusk = LinearGradient(
    begin: Alignment(-0.7, -1),
    end: Alignment(0.9, 1.3),
    colors: [Color(0xFF0E3A46), Color(0xFF0B4F63), Color(0xFF0EA5E9)],
    stops: [0, 0.55, 1],
  );
}

/// 4pt 基准网格：4 / 8 / 12 / 16 / 24 / 32。
class OlGap {
  const OlGap._();
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;

  /// Windows 内边距 16–20px；Android 页面边距 18px。
  static const pageDesktop = 16.0;
  static const pageDesktopWide = 20.0;
  static const pageMobile = 18.0;

  /// Windows 列表行高 44px；Android 列表行高 58px；触控目标 ≥ 44。
  static const rowDesktop = 44.0;
  static const rowMobile = 66.0;
  static const touchMin = 44.0;
}

/// 移动端专用的尺寸修正（v2.2 起步，v2.3 按真机反馈整体上调）。
class OlMobile {
  const OlMobile._();

  /// Android 字号放大比例。
  ///
  /// v2.2 的 1.12 在 360dp 真机上仍然偏小（11.5px → 12.9px），v2.3 提到 1.30：
  /// 设计稿的 9.5 / 10.5 / 11.5 实际渲染约 12.4 / 13.7 / 15，正文达到移动端
  /// 可读下限。仍然用 clamp 实现，不覆盖系统更大的无障碍字号。
  static const textScale = 1.0;

  /// 移动端列表行高（设计稿 A2，v2.3 由 58 提到 66 以容纳放大后的两行文字）。
  static const rowHeight = 66.0;

  /// 移动端触控最小尺寸。
  static const touch = 44.0;

  /// 移动端按钮最小高度（v2.3：30px 的桌面按钮在手机上点不中）。
  static const buttonHeight = 42.0;

  /// 行内紧凑按钮（原本 22–26px）在移动端的高度下限。
  static const buttonCompact = 34.0;

  /// 移动端 chip（类型筛选等）高度。
  static const chipHeight = 34.0;

  /// 移动端图标按钮尺寸。
  static const iconButton = 40.0;
}

/// 桌面端尺寸修正（v1.0.16）。
///
/// 早期按设计稿的 8.5–13px 原样落地，在 1440×900 的窗口里整屏偏小；
/// 这里统一放大 12%，与 Android 一样用 clamp，不覆盖系统更大的无障碍字号。
class OlDesktop {
  const OlDesktop._();

  /// Windows / macOS / Linux 字号放大比例。
  static const textScale = 1.0;
}

/// 单一浅色调色板。所有界面元素都从这里取色，项目**不支持深色模式**
/// 与主题切换（0.4.0 起移除）。
class OlPalette {
  final Color bg;
  final Color card;
  final Color surface; // sidebars
  final Color surfaceAlt; // detail panels / status bars
  final Color line;
  final Color line2;
  final Color hairline;
  final Color ink;
  final Color ink2;
  final Color ink3;
  final Color ink4;
  final Color nav;
  final Color navIcon;
  final Color navOnBg;
  final Color navOn;
  final Color navBadgeBg;
  final Color tableHeadBg;
  final Color th;
  final Color rowHover;
  final Color rowSel;
  final Color fieldBg;
  final Color fieldBorder;
  final Color chipBg;
  final Color chipBorder;
  final Color divider;

  const OlPalette({
    required this.bg,
    required this.card,
    required this.surface,
    required this.surfaceAlt,
    required this.line,
    required this.line2,
    required this.hairline,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.ink4,
    required this.nav,
    required this.navIcon,
    required this.navOnBg,
    required this.navOn,
    required this.navBadgeBg,
    required this.tableHeadBg,
    required this.th,
    required this.rowHover,
    required this.rowSel,
    required this.fieldBg,
    required this.fieldBorder,
    required this.chipBg,
    required this.chipBorder,
    required this.divider,
  });

  static const light = OlPalette(
    bg: Color(0xFFEDF2F8),
    card: Color(0xFFFFFFFF),
    surface: Color(0xFFF8FBFE),
    surfaceAlt: Color(0xFFFFFFFF),
    line: Color(0xFFE3EBF3),
    line2: Color(0xFFF1F6FB),
    hairline: Color(0xFFF1F6FB),
    ink: Color(0xFF0D1B2A),
    ink2: Color(0xFF42566B),
    ink3: Color(0xFF6B7F94),
    ink4: Color(0xFF9DB2C4),
    nav: Color(0xFF42566B),
    navIcon: Color(0xFF6B7F94),
    navOnBg: Color(0xFFEAF8FE),
    navOn: Color(0xFF08799F),
    navBadgeBg: Color(0xFFEDF2F8),
    tableHeadBg: Color(0xFFFCFDFE),
    th: Color(0xFF9DB2C4),
    rowHover: Color(0xFFF8FBFE),
    rowSel: Color(0xFFEAF8FE),
    fieldBg: Color(0xFFFFFFFF),
    fieldBorder: Color(0xFFE3EBF3),
    chipBg: Color(0xFFEAF8FE),
    chipBorder: Color(0xFFBDE7FA),
    divider: Color(0xFFF1F6FB),
  );
}

/// 主题与断点快捷访问：`context.ol` 取调色板，`context.isNarrow` 判断窄屏。
///
/// 注意：extension 的**名字不会出现在使用处**（写的是 `context.ol`），
/// 静态扫描"符号引用次数"会把它误判成死代码——v1.0.21 第一次提交就踩了这个坑，
/// 已恢复并在此说明，后续清理请勿按名字统计判断 extension。
extension OlThemeContext on BuildContext {
  /// 只有一套浅色调色板（0.4.0 移除深色模式）。
  OlPalette get ol => OlPalette.light;
  bool get isNarrow => MediaQuery.sizeOf(this).width < 900;
}

/// Text styles — 02 · Type scale：DISPLAY 32 / TITLE 20 / BODY 13 / CAPTION 10 / MICRO 9。
class OlText {
  const OlText._();

  static const base = TextStyle(fontSize: 13, height: 1.25);

  /// DISPLAY / 32 —— 页面大标题（「所有文件」）。
  static const display = TextStyle(fontSize: 32, height: 1.1, letterSpacing: -1.2, fontWeight: FontWeight.w800);

  /// TITLE / 20 —— 卡片与详情标题。
  static const title = TextStyle(fontSize: 20, height: 1.2, letterSpacing: -0.5, fontWeight: FontWeight.w800);

  /// BODY / 13 —— 文件名等正文。
  static const body13 = TextStyle(fontSize: 13, height: 1.35, fontWeight: FontWeight.w500);

  /// CAPTION / 10 —— 大小、时间等次级信息。
  static const caption = TextStyle(fontSize: 10, height: 1.4, fontWeight: FontWeight.w600);

  /// MICRO / 9 —— 分区标签、徽标。
  static const micro = TextStyle(fontSize: 9, height: 1.4, fontWeight: FontWeight.w700);

  static const h1 = TextStyle(fontSize: 41, height: 1.06, letterSpacing: -1.8, fontWeight: FontWeight.w800);
  static const h2 = TextStyle(fontSize: 26, height: 1.15, letterSpacing: -0.8, fontWeight: FontWeight.w800);
  static const h3 = TextStyle(fontSize: 19, height: 1.2, letterSpacing: -0.5, fontWeight: FontWeight.w800);
  static const section = TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, letterSpacing: -0.15);
  static const label = TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 1.0);
  static const eyebrow = TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 2.0);
  static const body = TextStyle(fontSize: 12, height: 1.7);
  static const small = TextStyle(fontSize: 10.5, height: 1.6);
  static const tiny = TextStyle(fontSize: 9, height: 1.5);
  static const mono = TextStyle(fontSize: 10, letterSpacing: 0.2);
}
