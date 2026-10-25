import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/theme.dart';
import '../core/theme/tokens.dart';
import '../platform/windows/tray.dart';
import 'router.dart';

class OpenNestApp extends ConsumerWidget {
  const OpenNestApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    ref.listen<String?>(trayNavigateProvider, (previous, next) {
      if (next == null) return;
      router.go(next);
      ref.read(trayNavigateProvider.notifier).state = null;
    });
    return MaterialApp.router(
      title: 'OpenNest',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      // 单一浅色主题：不再提供 darkTheme / themeMode，系统深色模式下也保持浅色。
      theme: olTheme(),
      scrollBehavior: const _OlScrollBehavior(),
      builder: (context, child) {
        // 系统栏透明 + 图标亮度固定为深色（浅色界面）；页面自己画到屏幕边缘，
        // 不再出现状态栏/导航栏的系统底色带（浅色主题下的"白条"就是它）。
        final media = MediaQuery.of(context);
        // 字号统一：桌面与移动都用 1.0，跟随设计稿原始字号。
        // 用 clamp 而不是直接赋值，系统无障碍字号更大时不会被压回去。
        final scaled = media.copyWith(
          textScaler: media.textScaler.clamp(
            minScaleFactor: media.size.width < 900 ? OlMobile.textScale : OlDesktop.textScale,
          ),
        );
        return MediaQuery(
          data: scaled,
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            value: olSystemBars,
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
