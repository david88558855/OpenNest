import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

ThemeData olTheme(Brightness brightness) {
  final p = brightness == Brightness.dark ? OlPalette.dark : OlPalette.light;
  final base = ThemeData(brightness: brightness, useMaterial3: true);
  final scheme = ColorScheme.fromSeed(
    seedColor: OlTokens.sky600,
    brightness: brightness,
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
    textTheme: base.textTheme.apply(
      bodyColor: p.ink,
      displayColor: p.ink,
      fontFamilyFallback: const ['Segoe UI', 'PingFang SC', 'Microsoft YaHei', 'Noto Sans CJK SC'],
    ).copyWith(
      bodyMedium: TextStyle(fontSize: 13, height: 1.25, color: p.ink, fontWeight: FontWeight.w500),
      bodySmall: TextStyle(fontSize: 11.5, height: 1.4, color: p.ink2),
      labelLarge: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: p.ink),
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
/// 应用的主导航（文件 / 传输 / 收藏 / 分享 / 设置 / 服务器管理）都是平级页面，
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
/// 图标亮度跟随主题——深色界面用浅色图标，浅色界面用深色图标。
/// 安卓 15 起强制 edge-to-edge，statusBarColor / systemNavigationBarColor 会被忽略，
/// 但旧版本系统与桌面平台仍依赖这里的取值，所以三端共用同一套定义。
SystemUiOverlayStyle olSystemBars({required bool dark}) {
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarBrightness: dark ? Brightness.dark : Brightness.light,
    statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
    systemStatusBarContrastEnforced: false,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
    systemNavigationBarContrastEnforced: false,
  );
}

/// 恒定深色页面（登录、播放器）使用：系统栏图标始终为浅色。
const SystemUiOverlayStyle olDarkSystemBars = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarBrightness: Brightness.dark,
  statusBarIconBrightness: Brightness.light,
  systemStatusBarContrastEnforced: false,
  systemNavigationBarColor: Colors.transparent,
  systemNavigationBarDividerColor: Colors.transparent,
  systemNavigationBarIconBrightness: Brightness.light,
  systemNavigationBarContrastEnforced: false,
);
