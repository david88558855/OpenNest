import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// 统一下拉刷新容器（v1.0.56）。
///
/// 桌面端默认的 `ScrollBehavior.dragDevices` 不含鼠标/触控板，滚轮也产生不了
/// overscroll —— 于是 `RefreshIndicator` 在电脑上永远触发不了。这里放开
/// mouse / trackpad 拖动，安卓与桌面共用同一套下拉逻辑与视觉。
///
/// 使用前提：被包裹的滚动组件需要 `physics: AlwaysScrollableScrollPhysics()`，
/// 否则内容不满一屏时无法下拉。
class OlPullToRefresh extends StatelessWidget {
  final Future<void> Function() onRefresh;
  final Widget child;

  const OlPullToRefresh({super.key, required this.onRefresh, required this.child});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        dragDevices: const {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
          PointerDeviceKind.stylus,
        },
        scrollbars: false,
      ),
      child: RefreshIndicator(
        onRefresh: onRefresh,
        color: OlTokens.sky600,
        backgroundColor: p.card,
        strokeWidth: 2,
        displacement: 24,
        child: child,
      ),
    );
  }
}
