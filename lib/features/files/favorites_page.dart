import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/frame.dart';
import '../../app/providers.dart';
import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/file_widgets.dart';
import '../../core/widgets/ol_controls.dart';
import '../../core/widgets/ol_dialogs.dart';
import '../../core/widgets/workspace_nav.dart';
import '../../core/widgets/ol_scroll.dart';

/// 收藏。
///
/// v1.0.18：移除「最近使用」；v1.0.26：分享功能整体移除，这里只剩收藏列表。
/// 左侧工作区导航 204 + 列表（Windows 行高 56 / Android 58）。
class FavoritesPage extends ConsumerWidget {
  const FavoritesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppFrame(
      navIndex: 2,
      handleBack: true,
      child: context.isNarrow
          ? const _MobileBody()
          : const Row(
              children: [
                _Sidebar(),
                Expanded(child: _DesktopBody()),
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// 左侧工作区导航
// ---------------------------------------------------------------------------
class _Sidebar extends ConsumerWidget {
  const _Sidebar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final profile = ref.watch(sessionProvider).profile;

    return Container(
      width: 204,
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(right: BorderSide(color: p.line2)),
      ),
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(9, 4, 9, 0),
              children: [
                // v1.0.17：与文件 / 分享 / 传输页共用同一份工作区导航，
                // 条目顺序与 badge 完全一致，切页不会重排。
                const WorkspaceNav(active: 'favorites'),
                const OlSectionLabel('存储'),
                if (profile != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                    child: Row(
                      children: [
                        const OlDot(color: OlTokens.ok, size: 6),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            profile.displayHost,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: p.ink2),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Text('收藏只存在本机，不写入服务端。', style: TextStyle(fontSize: 8.5, height: 1.6, color: p.ink4)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 主区（Windows / Android）
// ---------------------------------------------------------------------------
class _DesktopBody extends ConsumerWidget {
  const _DesktopBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    return ColoredBox(
      color: p.card,
      child: Column(
        children: [
          Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.hairline))),
            child: Row(
              children: [
                OlIconButton(icon: 'chev-l', size: 30, iconSize: 17, tooltip: '返回', onTap: () => goBackOrFiles(context)),
                const SizedBox(width: 8),
                Text('收藏', style: TextStyle(fontSize: 18, letterSpacing: -0.5, fontWeight: FontWeight.w800, color: p.ink)),
                const Spacer(),
              ],
            ),
          ),
          const Expanded(child: _FavoriteList()),
        ],
      ),
    );
  }
}

class _MobileBody extends StatelessWidget {
  const _MobileBody();

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return ColoredBox(
      color: p.card,
      child: Column(
        children: [
          SizedBox(
            height: 54,
            child: Row(
              children: [
                OlIconButton(icon: 'chev-l', size: 34, iconSize: 18, onTap: () => goBackOrFiles(context)),
                const SizedBox(width: 2),
                Text(
                  '收藏',
                  style: TextStyle(fontSize: 17, letterSpacing: -0.4, fontWeight: FontWeight.w800, color: p.ink),
                ),
              ],
            ),
          ),
          const Expanded(child: _FavoriteList()),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 收藏
// ---------------------------------------------------------------------------
class _FavoriteList extends ConsumerWidget {
  const _FavoriteList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(sessionProvider).profile;
    final entries = ref.watch(favoritesProvider).where((e) => e.serverId == profile?.id).toList();
    // v1.0.56：统一下拉刷新（收藏是本地数据，刷新即重建列表）
    Future<void> refresh() async {
      ref.invalidate(favoritesProvider);
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }

    if (entries.isEmpty) {
      // 空态也要能下拉：包一层可滚动容器
      return OlPullToRefresh(
        onRefresh: refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(
              height: 320,
              child: OlEmptyState(
                icon: 'star',
                title: '还没有收藏',
                subtitle: '在文件上右键或长按，选「收藏」即可固定到这里',
              ),
            ),
          ],
        ),
      );
    }
    return OlPullToRefresh(
      onRefresh: refresh,
      child: ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
      itemCount: entries.length,
      separatorBuilder: (context, index) => Divider(height: 1, color: context.ol.divider),
      itemBuilder: (context, index) {
        final entry = entries[index];
        return _EntryRow(
          leading: FileGlyph(name: entry.name, isDir: entry.isDir, size: 32, radius: 9, iconSize: 16),
          name: entry.name,
          subtitle: entry.path,
          trailing: entry.isDir ? '文件夹' : formatBytes(entry.size),
          onOpen: () async {
            if (entry.isDir) {
              await ref.read(filesProvider.notifier).open(entry.path);
              if (context.mounted) context.go('/files?path=${Uri.encodeComponent(entry.path)}');
            } else {
              context.go('/files?path=${Uri.encodeComponent(parentOf(entry.path))}');
            }
          },
          onRemove: () async {
            await ref.read(favoritesProvider.notifier).removeEntry(entry);
            if (context.mounted) olToast(context, '已取消收藏');
          },
        );
      },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 我的分享（只读 + 浏览器打开）
// ---------------------------------------------------------------------------

/// 分享行使用图标底（非文件图标）。

// ---------------------------------------------------------------------------
// 通用行
// ---------------------------------------------------------------------------
class _EntryRow extends StatefulWidget {
  final Widget leading;
  final String name;
  final String subtitle;
  final String trailing;
  final VoidCallback onOpen;
  final Future<void> Function()? onRemove;

  const _EntryRow({
    required this.leading,
    required this.name,
    required this.subtitle,
    required this.trailing,
    required this.onOpen,
    this.onRemove,
  });

  @override
  State<_EntryRow> createState() => _EntryRowState();
}

class _EntryRowState extends State<_EntryRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onOpen,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          color: _hover ? p.rowHover : null,
          child: Row(
            children: [
              widget.leading,
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.ink),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 9.5, color: p.ink4),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(widget.trailing, style: TextStyle(fontSize: 9.5, color: p.ink4)),
              if (widget.onRemove != null) ...[
                const SizedBox(width: 8),
                OlIconButton(
                  icon: 'trash',
                  size: 26,
                  iconSize: 13,
                  tooltip: '移除收藏',
                  onTap: () => widget.onRemove!(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
