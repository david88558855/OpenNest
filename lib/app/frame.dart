import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:window_manager/window_manager.dart';

import '../core/theme/tokens.dart';
import '../core/widgets/ol_controls.dart';
import '../core/widgets/ol_dialogs.dart';
import '../core/widgets/ol_icon.dart';
import 'providers.dart';

/// Desktop window chrome (W1/W2…) + Android bottom navigation (A2/A3/A6).
///
/// v2.5：Android 系统返回键统一在这里接管——根 Tab 页（`handleBack: true`）
/// 第一次按只提示「再按一次返回桌面」，2 秒内再按一次才真正退出应用；
/// 页面可以用 [onBack] 抢先处理（例如文件页逐级回退、设置分区页回总览）。
/// 被 push 出来的页面（服务器管理 / 播放器）不接管，保持正常的出栈返回。
class AppFrame extends ConsumerStatefulWidget {
  final Widget child;
  final int navIndex;
  final bool showNav;
  final bool showTitleBar;

  /// true 表示页面自己绘制到系统栏下方，并自行处理安全区（登录页的渐变头部、
  /// 设置页的个人资料渐变）。此时框架不再叠加任何内边距，避免重复避让。
  final bool edgeToEdge;

  /// 是否接管系统返回键。根 Tab 页与「go」出来的分区页传 true。
  final bool handleBack;

  /// 页面自定义返回：返回 true 表示本次返回已被页面消费，不再走「双击退出」。
  final Future<bool> Function()? onBack;

  const AppFrame({
    super.key,
    required this.child,
    this.navIndex = 0,
    this.showNav = true,
    this.showTitleBar = true,
    this.edgeToEdge = false,
    this.handleBack = false,
    this.onBack,
  });

  @override
  ConsumerState<AppFrame> createState() => _AppFrameState();
}

class _AppFrameState extends ConsumerState<AppFrame> {
  /// 连续两次返回的判定窗口。
  static const _exitWindow = Duration(seconds: 2);
  DateTime? _lastBackAt;

  Future<void> _handleSystemBack() async {
    // 1) 页面自己的返回逻辑优先（抽屉 / 批量模式 / 上一级目录）。
    if (widget.onBack != null && await widget.onBack!.call()) return;
    // 2) 子页面：栈里有上一页就正常出栈。
    //    0.5.0 修复：之前只判断「双击退出」，导致 /sources、/sources/add、/preview
    //    这些 push 进来的页面按系统返回键第一次只提示、第二次直接退出应用。
    final router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop();
      return;
    }
    // 3) 根页：2 秒内再按一次才退出应用。
    final now = DateTime.now();
    final last = _lastBackAt;
    if (last != null && now.difference(last) <= _exitWindow) {
      _lastBackAt = null;
      await SystemNavigator.pop();
      return;
    }
    _lastBackAt = now;
    if (mounted) olToast(context, '再按一次返回桌面');
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final narrow = mq.size.width < 900;
    final p = context.ol;
    final navShown = narrow && widget.showNav;

    // 顶部：始终避开状态栏/刘海，否则内容会压到状态栏上。
    // 底部：有底部导航时由导航条自己撑满系统导航栏区域；没有导航时由框架补足，
    // 避免内容被系统手势条盖住。软键盘弹出时 viewInsets 已经压缩了可用高度，
    // 此时不再追加底部内边距，否则会多出一段空白。
    final insets = _frameInsets(mq, bleed: widget.edgeToEdge, navShown: navShown);

    // v1.0.44：内容区加独立图层。打开子页面（如设置 → 服务器管理）时，
    // 被覆盖的页面会保留自己的 layer，返回时直接合成、无需整页重绘 ——
    // 这是「从服务器管理返回设置页卡一下」的主要开销（设置页有大量卡片/阴影）。
    Widget content = RepaintBoundary(child: widget.child);
    if (insets != EdgeInsets.zero) {
      // 消费掉已经补过的内边距：子页面再次读取 MediaQuery.padding 时不会重复避让。
      content = MediaQuery.removePadding(
        context: context,
        removeTop: insets.top > 0,
        removeBottom: insets.bottom > 0,
        removeLeft: insets.left > 0,
        removeRight: insets.right > 0,
        child: Padding(padding: insets, child: content),
      );
    }

    Widget body = content;
    if (!narrow && widget.showTitleBar) {
      body = Column(
        children: [
          const OlTitleBar(),
          Expanded(child: body),
        ],
      );
    }
    if (navShown) {
      body = Column(
        children: [
          Expanded(child: body),
          _BottomNav(index: widget.navIndex, bottomInset: _systemBottomInset(mq)),
        ],
      );
    }
    if (widget.handleBack && Platform.isAndroid) {
      body = PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          _handleSystemBack();
        },
        child: body,
      );
    }
    return Scaffold(
      backgroundColor: p.card,
      body: body,
    );
  }

  EdgeInsets _frameInsets(MediaQueryData mq, {required bool bleed, required bool navShown}) {
    if (bleed) return EdgeInsets.zero;
    return EdgeInsets.only(
      top: mq.padding.top,
      bottom: navShown ? 0 : _systemBottomInset(mq),
      left: mq.padding.left,
      right: mq.padding.right,
    );
  }
}

/// 系统底部内边距（导航栏 / 手势条）。软键盘弹出时返回 0，交给 Scaffold 的
/// resizeToAvoidBottomInset 处理，避免与 viewInsets 叠加出多余空白。
double _systemBottomInset(MediaQueryData mq) {
  if (mq.viewInsets.bottom > 0) return 0;
  return mq.viewPadding.bottom;
}

/// 返回上一页：能从路由栈里退就退，否则回文件页。
///
/// 桌面主页面（传输 / 设置 / 存储源）都是平级 `go` 出来的，
/// 没有可 pop 的栈，所以统一兜底到 `/files`；从其它页面 push 进来时正常出栈。
void goBackOrFiles(BuildContext context) {
  if (GoRouter.of(context).canPop()) {
    context.pop();
  } else {
    context.go('/files');
  }
}

class OlTitleBar extends ConsumerWidget {
  const OlTitleBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final session = ref.watch(sessionProvider);
    final profile = session.profile;
    final canDrag = Platform.isWindows || Platform.isLinux || Platform.isMacOS;

    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: const Color(0xFFFBFDFF),
        border: Border(bottom: BorderSide(color: p.line2)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 13),
          const OlMark(size: 19, radius: 6),
          const SizedBox(width: 8),
          Text(
            'OpenNest',
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: const Color(0xFF3B4F64), letterSpacing: -0.1),
          ),
          const SizedBox(width: 9),
          Container(width: 1, height: 12, color: p.line),
          const SizedBox(width: 7),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            // v1.0.40：改用 push。全局已关闭页面转场（PageTransitionsTheme →
            // _NoTransitionBuilder），当初「push 会缩放转场」的顾虑不成立；
            // 而 go 会重建成整条路由栈，从设置/文件页进去后返回要重建目标页，
            // 表现为明显卡顿。
            // 0.5.0：引擎状态已并入设置页的「通用」分区。
            onTap: () => context.push('/settings/general'),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
              child: Row(
                children: [
                  OlDot(color: session.signedIn ? OlTokens.ok : OlTokens.warn, size: 5),
                  const SizedBox(width: 5),
                  Text(
                    profile?.displayHost ?? (session.connecting ? '引擎启动中' : '本机引擎'),
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: const Color(0xFF7C8FA3)),
                  ),
                  const SizedBox(width: 4),
                  OlIcon('chev-r', size: 9, color: p.ink4),
                ],
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (_) async {
                if (canDrag) await windowManager.startDragging();
              },
              onDoubleTap: () async {
                if (!canDrag) return;
                if (await windowManager.isMaximized()) {
                  await windowManager.unmaximize();
                } else {
                  await windowManager.maximize();
                }
              },
              child: const SizedBox.expand(),
            ),
          ),
          // 设计稿 D8 `.tb-right`：品牌胶囊在窗口控件左侧。
          if (canDrag) ...[
            const _BrandPill(),
            const SizedBox(width: 10),
          ],
          if (canDrag) const _WindowControls(),
        ],
      ),
    );
  }
}

/// 标题栏右侧的品牌胶囊（设计稿 D8 `.pill`）。
class _BrandPill extends StatelessWidget {
  const _BrandPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF8FE),
        borderRadius: BorderRadius.circular(99),
      ),
      child: const Text(
        '免账户 · 直连存储',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF08799F)),
      ),
    );
  }
}

class _WindowControls extends StatelessWidget {
  const _WindowControls();

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Row(
      children: [
        _CtrlButton(
          icon: 'minus',
          color: p.ink3,
          onTap: () => windowManager.minimize(),
        ),
        _CtrlButton(
          icon: 'square',
          color: p.ink3,
          onTap: () async {
            if (await windowManager.isMaximized()) {
              await windowManager.unmaximize();
            } else {
              await windowManager.maximize();
            }
          },
        ),
        _CtrlButton(
          icon: 'x',
          color: const Color(0xFF8B9AA9),
          onTap: () => windowManager.close(),
        ),
      ],
    );
  }
}

class _CtrlButton extends StatelessWidget {
  final String icon;
  final Color color;
  final VoidCallback onTap;

  const _CtrlButton({required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 38,
          color: Colors.transparent,
          child: Center(child: OlIcon(icon, size: 12, color: color, strokeWidth: 1.6)),
        ),
      ),
    );
  }
}

class _BottomNav extends ConsumerWidget {
  final int index;

  /// 系统导航栏 / 手势条高度：导航条底色要一直铺到屏幕最底部，
  /// 否则底部会露出 Scaffold 的底色（浅色主题下就是一条白边）。
  final double bottomInset;

  const _BottomNav({required this.index, required this.bottomInset});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final transfers = ref.watch(transfersProvider);
    final pending = transfers.pendingCount;
    final items = <_NavItem>[
      _NavItem('文件', 'folder', '/files'),
      _NavItem('传输', 'arrow-down', '/transfers', badge: pending),
      _NavItem('设置', 'settings', '/settings'),
    ];
    return Container(
      // v2.3：图标与文字放大后底栏由 70 抬到 78，避免文字贴边被裁。
      height: 78 + bottomInset,
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: BoxDecoration(
        color: const Color(0xFAFFFFFF),
        border: Border(top: BorderSide(color: p.line2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (var i = 0; i < items.length; i++)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => context.go(items[i].route),
              child: SizedBox(
                width: 62,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        OlIcon(
                          items[i].icon,
                          size: 23,
                          color: i == index ? const Color(0xFF0782AE) : const Color(0xFF9AABBC),
                          strokeWidth: i == index ? 2.1 : 1.9,
                        ),
                        if (items[i].badge > 0)
                          Positioned(
                            right: -7,
                            top: -4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(color: OlTokens.sky600, borderRadius: BorderRadius.circular(99)),
                              child: Text('${items[i].badge}', style: const TextStyle(fontSize: 7.5, fontWeight: FontWeight.w900, color: Colors.white)),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      items[i].label,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: i == index ? const Color(0xFF0782AE) : const Color(0xFF9AABBC),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      width: 3,
                      height: 3,
                      decoration: BoxDecoration(
                        color: i == index ? OlTokens.sky600 : Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NavItem {
  final String label;
  final String icon;
  final String route;
  final int badge;
  const _NavItem(this.label, this.icon, this.route, {this.badge = 0});
}
