import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

/// 全局 UI 字体。
///
/// 桌面端统一 Arial；**Android 不设字体**（保持系统默认），这是刻意取舍：
/// 安卓系统不带 Arial，写死字体名只会静默回落到 Roboto。
String? get _uiFont =>
    defaultTargetPlatform == TargetPlatform.android ? null : 'Arial';

/// 中文回退链：Arial 不含 CJK 字形，取与 Arial 最接近的无衬线黑体
/// （Windows 微软雅黑 / macOS 苹方 / Linux 思源黑体）。
const List<String> _fontFallback = [
  'Microsoft YaHei',
  'PingFang SC',
  'Helvetica Neue',
  'Segoe UI',
  'Noto Sans CJK SC',
  'sans-serif',
];

/// 全局唯一主题：浅色。项目不支持深色模式与主题切换（0.4.0 起）。
ThemeData olTheme() {
  const p = OlPalette.light;
  // 字体只能通过构造器设置：ThemeData.copyWith 没有 fontFamily /
  // fontFamilyFallback 这两个命名参数（写在那里会直接编译失败）。
  final base = ThemeData(
    brightness: Brightness.light,
    useMaterial3: true,
    fontFamily: _uiFont,
    fontFamilyFallback: _fontFallback,
  );
  final scheme = ColorScheme.fromSeed(
    seedColor: OlTokens.sky600,
    brightness: Brightness.light,
  ).copyWith(
    surface: p.card,
    primary: OlTokens.sky600,
    error: OlTokens.danger,
  );
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: p.card,
    canvasColor: p.card,
    // v1.0.52：点击涟漪也属于动画（约 200ms 扩散）。
    // 全项目不要任何动画，这里换成 NoSplash 并把高亮色设为透明，
    // 点击即刻响应、没有任何过渡。
    splashFactory: NoSplash.splashFactory,
    // 涟漪扩散是动画，去掉；但保留**瞬时**的按下高亮色，
    // 否则点击完全没有视觉反馈（不是动画，是一帧变色）。
    splashColor: Colors.transparent,
    highlightColor: const Color(0x0F0D1B2A),
    dividerColor: p.line2,
    // v1.0.15：切换版块 / 导航栏一律硬切换，不要任何转场动作。
    // 之前桌面是 FadeUpwards（淡入 + 上滑 1/12 屏高），Android 是 Material 3 的 Zoom
    //（整页放大再缩小），在页面之间来回点时观感很差。这里全平台映射到「直接换页」。
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.windows: _NoTransitionBuilder(),
        TargetPlatform.linux: _NoTransitionBuilder(),
        TargetPlatform.macOS: _NoTransitionBuilder(),
        TargetPlatform.android: _NoTransitionBuilder(),
        TargetPlatform.iOS: _NoTransitionBuilder(),
        TargetPlatform.fuchsia: _NoTransitionBuilder(),
      },
    ),
    textTheme: base.textTheme
        .apply(
          bodyColor: p.ink,
          displayColor: p.ink,
          fontFamily: _uiFont,
          fontFamilyFallback: _fontFallback,
        )
        .copyWith(
          // 这几个覆盖样式的 fontFamily 必须显式再写一遍：新建的 TextStyle
          // 不会继承上面 apply 的结果，而 Text 又会以 bodyMedium 作为
          // DefaultTextStyle —— 漏写就会让整页退回系统默认字体。
          bodyMedium: TextStyle(
            fontSize: 13,
            height: 1.25,
            color: p.ink,
            fontWeight: FontWeight.w500,
            fontFamily: _uiFont,
            fontFamilyFallback: _fontFallback,
          ),
          bodySmall: TextStyle(
            fontSize: 11.5,
            height: 1.4,
            color: p.ink2,
            fontFamily: _uiFont,
            fontFamilyFallback: _fontFallback,
          ),
          labelLarge: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: p.ink,
            fontFamily: _uiFont,
            fontFamilyFallback: _fontFallback,
          ),
        ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      border: InputBorder.none,
      hintStyle: TextStyle(fontSize: 11.5, color: p.ink4, fontWeight: FontWeight.w500),
    ),
  );
}

/// 无转场：直接返回子组件，不淡入、不上滑、不缩放。
///
/// 应用的主导航（文件 / 传输 / 收藏 / 分享 / 设置）都是平级页面，
/// 任何"过渡动作"都会被感知成页面在跳。这里统一关掉，交给系统让新页面立即出现。
class _NoTransitionBuilder extends PageTransitionsBuilder {
  const _NoTransitionBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      child;
}

/// 系统栏样式：状态栏与导航栏都透明，让页面/导航条自身的底色一直铺到屏幕边缘。
///
/// 单一浅色主题 ⇒ 系统栏图标恒为深色（只有播放页的深色舞台需要反白，
/// 由播放页自己用 `AnnotatedRegion` 覆盖）。
/// 安卓 15 起强制 edge-to-edge，statusBarColor / systemNavigationBarColor 会被忽略，
/// 但旧版本系统与桌面平台仍依赖这里的取值，所以三端共用同一套定义。
const SystemUiOverlayStyle olSystemBars = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarBrightness: Brightness.light,
  statusBarIconBrightness: Brightness.dark,
  systemStatusBarContrastEnforced: false,
  systemNavigationBarColor: Colors.transparent,
  systemNavigationBarDividerColor: Colors.transparent,
  systemNavigationBarIconBrightness: Brightness.dark,
  systemNavigationBarContrastEnforced: false,
);
