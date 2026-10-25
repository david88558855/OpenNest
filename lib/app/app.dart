import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/theme.dart';
import '../core/theme/tokens.dart';
import '../platform/windows/tray.dart';
import 'providers.dart';
import 'router.dart';

class OpenNestApp extends ConsumerWidget {
  const OpenNestApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final settings = ref.watch(appSettingsProvider);
    ref.listen<String?>(trayNavigateProvider, (previous, next) {
      if (next == null) return;
      router.go(next);
      ref.read(trayNavigateProvider.notifier).state = null;
    });
    return MaterialApp.router(
      title: 'OpenNest',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: olTheme(Brightness.light),
      darkTheme: olTheme(Brightness.dark),
      themeMode: settings.themeMode,
      scrollBehavior: const _OlScrollBehavior(),
      builder: (context, child) {
        // 系统栏透明 + 图标亮度跟随主题；页面自己画到屏幕边缘，不再出现
        // 状态栏/导航栏的系统底色带（浅色主题下的“白条”就是它）。
        final dark = Theme.of(context).brightness == Brightness.dark;
        final media = MediaQuery.of(context);
        // 字号统一放大：Android 1.30（v2.3 真机反馈），桌面 1.12（v1.0.16：
        // 按设计稿的 8.5–13px 原样渲染在大屏上偏小）。都用 clamp，
        // 系统无障碍字号更大时不会被压回去。
        final scaled = media.copyWith(
          textScaler: media.textScaler.clamp(
            minScaleFactor: media.size.width < 900 ? OlMobile.textScale : OlDesktop.textScale,
          ),
        );
        return MediaQuery(
          data: scaled,
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            value: olSystemBars(dark: dark),
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}

class _OlScrollBehavior extends MaterialScrollBehavior {
  const _OlScrollBehavior();

  @override
  Widget buildScrollbar(
      BuildContext context, Widget child, ScrollableDetails details) {
    return Scrollbar(
      controller: details.controller,
      thickness: 6,
      radius: const Radius.circular(99),
      child: child,
    );
  }
}

/// Full-bleed dark surface used by the player and mobile login.
class OlDarkScaffold extends StatelessWidget {
  final Widget child;
  const OlDarkScaffold({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF07101B),
      body: child,
    );
  }
}
