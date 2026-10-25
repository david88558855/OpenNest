import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../theme/tokens.dart';
import 'ol_controls.dart';
import 'ol_icon.dart';

/// 桌面左栏「工作区」导航（v1.0.17）。
///
/// 文件 / 收藏 / 分享 / 传输四个页面**共用这一份**，条目、顺序、badge、
/// 行高、间距完全固定：
///
///   所有文件 → 收藏 → 传输任务 →（分隔线）→ 设置
///
/// 之前每个页面各自硬编码列表：文件页是「最近使用 → 收藏」、收藏页是
/// 「收藏 → 最近使用」，badge 也不一致（文件页给最近使用和分享计数、
/// 传输页没有）。切页时整列会重排并上下跳一下，观感就是「导航栏错乱」。
///
/// v1.0.18：按需求移除「最近使用」入口。
/// v1.0.26：分享功能整体移除，「我的分享」入口一并删除。
///
/// 页面独有的内容（挂载点 / 队列 / 存储）由调用方接在本组件后面。
class WorkspaceNav extends ConsumerWidget {
  /// 当前高亮的条目：files / favorites / transfers / settings。
  final String active;

  const WorkspaceNav({super.key, required this.active});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(sessionProvider).profile;
    final serverId = profile?.id;
    final favorites = ref.watch(favoritesProvider).where((e) => e.serverId == serverId).length;
    final transfers = ref.watch(transfersProvider).pendingCount;

    return Column(
      // 在 ListView 里必须收紧，否则无界高度会报错
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const OlSectionLabel('工作区'),
        _NavRow(icon: 'folder', label: '所有文件', active: active == 'files', onTap: () => context.go('/files')),
        _NavRow(
          icon: 'star',
          label: '收藏',
          badge: favorites,
          active: active == 'favorites',
          onTap: () => context.go('/favorites'),
        ),
        _NavRow(
          icon: 'arrow-down',
          label: '传输任务',
          badge: transfers,
          active: active == 'transfers',
          onTap: () => context.go('/transfers'),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          child: Divider(height: 1),
        ),
        _NavRow(icon: 'settings', label: '设置', active: active == 'settings', onTap: () => context.go('/settings')),
      ],
    );
  }
}

class _NavRow extends StatelessWidget {
  final String icon;
  final String label;
  final int badge;
  final bool active;
  final VoidCallback onTap;

  const _NavRow({required this.icon, required this.label, required this.onTap, this.badge = 0, this.active = false});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            // 固定行高：badge 有无、数字位数变化都不会改变这一行的高度，
            // 整列位置才不会跟着动。
            height: 31,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            decoration: BoxDecoration(
              color: active ? p.navOnBg : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                OlIcon(icon, size: 15, color: active ? OlTokens.sky600 : p.navIcon),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: active ? p.navOn : p.nav),
                  ),
                ),
                // badge 用固定宽度占位，避免「3」→「12」时把文字挤动
                if (badge > 0) _Badge(label: badge > 999 ? '999+' : '$badge', active: active),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final bool active;
  const _Badge({required this.label, required this.active});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Container(
      constraints: const BoxConstraints(minWidth: 18),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: active ? p.card : p.navBadgeBg,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: active ? const Color(0xFF0B7A9E) : p.ink4),
      ),
    );
  }
}
