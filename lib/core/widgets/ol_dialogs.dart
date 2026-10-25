import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'ol_controls.dart';
import 'ol_icon.dart';

class OlMenuItem {
  final String label;
  final String icon;
  final VoidCallback? onTap;
  final bool danger;
  final bool divider;

  const OlMenuItem(this.label, this.icon, this.onTap, {this.danger = false, this.divider = false});
}

/// A7 · Android 长按操作面板。
///
/// 结构按设计稿：顶部拖拽条 → 「已选择 N 个项目 / 取消」→ 文件行 →
/// 四个高频动作（播放 / 下载 / 分享 / 收藏）→ 次级动作列表（含删除）。
/// 桌面端继续用 [showOlMenu] 的右键浮层，两端动作集合一致。
Future<void> showOlActionSheet(
  BuildContext context, {
  required int count,
  required String title,
  required String subtitle,
  required Widget leading,
  required List<OlMenuItem> quick,
  required List<OlMenuItem> items,
}) async {
  final p = context.ol;
  await showModalBottomSheet<void>(
    context: context,
    sheetAnimationStyle: AnimationStyle.noAnimation,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x5707111D),
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) {
      void run(OlMenuItem item) {
        Navigator.of(sheetContext).pop();
        item.onTap?.call();
      }

      final maxHeight = MediaQuery.sizeOf(sheetContext).height * 0.86;
      return Container(
        // v2.4：内容超过一屏（动作多 + 字体放大）时必须可滚动，
        // 否则溢出会裁掉下半部分，看起来像"点了没反应"。
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        ),
        padding: EdgeInsets.fromLTRB(14, 8, 14, 18 + MediaQuery.paddingOf(sheetContext).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(color: p.line, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                children: [
                  Text(
                    count > 1 ? '已选择 $count 个项目' : '已选择 1 个项目',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: p.ink),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.of(sheetContext).pop(),
                    child: Text('取消', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: OlTokens.sky700)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(2, 4, 2, 12),
                      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.line2))),
                      child: Row(
                        children: [
                          leading,
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: p.ink),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: p.ink4),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        children: [
                          for (final item in quick)
                            Expanded(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => run(item),
                                child: Column(
                                  children: [
                                    Container(
                                      width: 42,
                                      height: 42,
                                      decoration: BoxDecoration(
                                        color: item.danger ? OlTokens.dangerSurface : const Color(0xFFF1F8FC),
                                        borderRadius: BorderRadius.circular(13),
                                      ),
                                      child: Center(
                                        child: OlIcon(
                                          item.icon,
                                          size: 17,
                                          color: item.danger ? OlTokens.dangerDeep : const Color(0xFF3D7E9E),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      item.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: p.ink2),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    for (final item in items)
                      InkWell(
                        onTap: () => run(item),
                        child: Container(
                          height: 46,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(border: Border(top: BorderSide(color: p.line2))),
                          child: Row(
                            children: [
                              OlIcon(item.icon, size: 16, color: item.danger ? const Color(0xFFE06B82) : p.ink3),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  item.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: item.danger ? OlTokens.dangerDeep : p.ink2,
                                  ),
                                ),
                              ),
                              OlIcon('chev-r', size: 14, color: p.ink4),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// 右键 / 「⋮」浮层菜单（v1.0.51 重写）。
///
/// 原来直接用 Material 的 `showMenu`：它的 `transitionDuration` 固定 300ms
/// （打开是 fade + scale，关闭同样 300ms），点上「⋮」要等近三分之一秒才看到菜单，
/// 关掉时又要等一次 —— 这就是「有动画而且显示很慢」的原因。
///
/// 现在用 `showGeneralDialog` 自绘：transitionDuration 为 0（关闭沿用同一时长），
/// 菜单立即出现、立即消失；位置自己算，超出屏幕右下时自动翻转/夹紧。
Future<void> showOlMenu(BuildContext context, {required Offset position, required List<OlMenuItem> items}) async {
  if (items.isEmpty) return;
  final p = context.ol;
  final screen = MediaQuery.sizeOf(context);
  const width = 160.0;
  const itemHeight = 34.0;
  final height = items.length * itemHeight + 8;

  var left = position.dx;
  var top = position.dy;
  // 优先向右下展开；右侧/下方放不下就翻转，最后夹紧在屏幕内
  if (left + width > screen.width - 8) left = position.dx - width;
  if (top + height > screen.height - 8) top = position.dy - height;
  left = left.clamp(8.0, (screen.width - width - 8).clamp(8.0, double.infinity)).toDouble();
  top = top.clamp(8.0, (screen.height - height - 8).clamp(8.0, double.infinity)).toDouble();

  final selected = await showGeneralDialog<int>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'menu',
    // 透明遮罩：靠 hit-test 关闭，不压暗背景
    barrierColor: Colors.transparent,
    transitionDuration: Duration.zero,
    pageBuilder: (dialogContext, _, __) => Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              width: width,
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: p.card,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: p.line),
                boxShadow: const [BoxShadow(color: Color(0x1F0D1B2A), blurRadius: 18, offset: Offset(0, 6))],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < items.length; i++)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.of(dialogContext).pop(i),
                      child: Container(
                        height: itemHeight,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Row(
                          children: [
                            OlIcon(items[i].icon, size: 13, color: items[i].danger ? OlTokens.dangerDeep : p.ink3),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                items[i].label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: items[i].danger ? OlTokens.dangerDeep : p.ink2,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
  if (selected != null) items[selected].onTap?.call();
}

/// 零时长对话框（v1.0.52）。
///
/// `showDialog` 走 `DialogRoute`，固定 150ms 淡入淡出，关闭还要再等一次。
/// 全项目不使用任何过渡动画，所有对话框统一走这里：`transitionDuration` 为 0，
/// 立即出现、立即消失。视觉（遮罩色、内容组件）由调用方决定。
Future<T?> showOlDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color barrierColor = const Color(0x59091424),
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: 'dialog',
    barrierColor: barrierColor,
    transitionDuration: Duration.zero,
    // showDialog 默认 useSafeArea，showGeneralDialog 不会 —— 这里补上，
    // 避免小屏 / 刘海屏上对话框顶到状态栏。
    pageBuilder: (dialogContext, _, __) => SafeArea(child: builder(dialogContext)),
  );
}

OverlayEntry? _toastEntry;
Timer? _toastTimer;

/// 轻提示（v1.0.52 重写）。
///
/// 原来用 `SnackBar`：进入 250ms 上滑 + 退出 250ms 淡出，操作后要等动画才看到结果。
/// 现在直接往 Overlay 里塞一条静态提示，出现与消失都是瞬时的，计时到点即移除。
/// 轻提示（v1.0.54 重新设计）。
///
/// - **位置**：移到页面顶部（安全区往下约 52，落在文件页「服务器地址」与
///   「所有文件」标题之间），不再压在底部导航上；
/// - **视觉**：白底 + 细描边 + 轻阴影，替代原来的深色块，和页面卡片风格统一；
/// - **文字**：显式 `decoration: none`，去掉部分机型上出现的下划线（黄线）；
/// - 出现与消失都是瞬时的（不带动画）。
void olToast(BuildContext context, String message, {bool error = false}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  final p = context.ol;
  final safeTop = MediaQuery.maybeOf(context)?.viewPadding.top ?? 0;

  // 连续调用时只保留最新一条
  _toastTimer?.cancel();
  final previous = _toastEntry;
  if (previous != null) {
    try {
      previous.remove();
    } catch (_) {}
    _toastEntry = null;
  }

  final entry = OverlayEntry(
    builder: (_) => Positioned(
      left: 16,
      right: 16,
      top: safeTop + 52,
      child: IgnorePointer(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 520),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: p.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: error ? OlTokens.dangerBorder : p.line2),
              boxShadow: const [BoxShadow(color: Color(0x140D1B2A), blurRadius: 14, offset: Offset(0, 4))],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OlIcon(
                  error ? 'alert' : 'check',
                  size: 14,
                  color: error ? OlTokens.dangerDeep : OlTokens.okDeep,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    // decoration 显式置 none：部分 Android 机型会把默认样式渲染出下划线
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.3,
                      color: error ? OlTokens.dangerInk : p.ink,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  _toastEntry = entry;
  _toastTimer = Timer(Duration(seconds: error ? 4 : 2), () {
    if (!identical(_toastEntry, entry)) return;
    try {
      entry.remove();
    } catch (_) {}
    _toastEntry = null;
  });
}

class _OlDialogShell extends StatelessWidget {
  final Widget child;
  const _OlDialogShell({required this.child});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: 380,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: p.line),
          boxShadow: const [BoxShadow(color: Color(0x330B1622), blurRadius: 40, offset: Offset(0, 18))],
        ),
        child: child,
      ),
    );
  }
}

class _DialogHeader extends StatelessWidget {
  final String title;
  final String? message;
  final String icon;

  const _DialogHeader({required this.title, required this.icon, this.message});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(color: p.isDark ? const Color(0xFF12202F) : const Color(0xFFEAF8FE), borderRadius: BorderRadius.circular(9)),
              child: Center(child: OlIcon(icon, size: 14, color: OlTokens.sky700)),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: p.ink)),
            ),
          ],
        ),
        if (message != null) ...[
          const SizedBox(height: 10),
          Text(message!, style: TextStyle(fontSize: 11.5, height: 1.65, color: p.ink3)),
        ],
      ],
    );
  }
}

/// Single-line (or multiline) prompt. Returns the entered string or null.
Future<String?> olPrompt(
  BuildContext context, {
  required String title,
  String? message,
  String hint = '',
  String initial = '',
  String confirm = '确定',
  String icon = 'edit',
  bool obscure = false,
  int maxLines = 1,
}) async {
  final controller = TextEditingController(text: initial);
  final result = await showOlDialog<String>(
    context: context,
    barrierColor: const Color(0x59091424),
    builder: (dialogContext) {
      final p = dialogContext.ol;
      return _OlDialogShell(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DialogHeader(title: title, icon: icon, message: message),
            const SizedBox(height: 14),
            OlField(
              controller: controller,
              icon: icon,
              hint: hint,
              obscure: obscure,
              autofocus: true,
              maxLines: maxLines,
              onSubmitted: (v) => Navigator.of(dialogContext).pop(v),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                GestureDetector(
                  onTap: () => Navigator.of(dialogContext).pop(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Text('取消', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: p.ink3)),
                  ),
                ),
                const SizedBox(width: 6),
                OlPrimaryButton(label: confirm, onTap: () => Navigator.of(dialogContext).pop(controller.text)),
              ],
            ),
          ],
        ),
      );
    },
  );
  controller.dispose();
  return result;
}

Future<bool> olConfirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirm = '确定',
  bool danger = false,
  String icon = 'alert',
}) async {
  final result = await showOlDialog<bool>(
    context: context,
    barrierColor: const Color(0x59091424),
    builder: (dialogContext) {
      final p = dialogContext.ol;
      return _OlDialogShell(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DialogHeader(title: title, icon: icon, message: message),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                GestureDetector(
                  onTap: () => Navigator.of(dialogContext).pop(false),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Text('取消', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: p.ink3)),
                  ),
                ),
                const SizedBox(width: 6),
                if (danger)
                  OlDangerButton(label: confirm, icon: 'trash', onTap: () => Navigator.of(dialogContext).pop(true))
                else
                  OlPrimaryButton(label: confirm, onTap: () => Navigator.of(dialogContext).pop(true)),
              ],
            ),
          ],
        ),
      );
    },
  );
  return result ?? false;
}

/// Rounded 26px top sheet used by the Android action panel (A7).
Future<T?> olSheet<T>(
  BuildContext context, {
  required Widget child,
  bool isScrollControlled = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    sheetAnimationStyle: AnimationStyle.noAnimation,
    isScrollControlled: isScrollControlled,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x57071117),
    builder: (sheetContext) {
      final p = sheetContext.ol;
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
        child: Container(
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
            boxShadow: const [BoxShadow(color: Color(0x33071117), blurRadius: 48, offset: Offset(0, -18))],
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(color: p.isDark ? const Color(0xFF243A52) : const Color(0xFFE3EBF3), borderRadius: BorderRadius.circular(99)),
                ),
                Flexible(child: child),
              ],
            ),
          ),
        ),
      );
    },
  );
}
