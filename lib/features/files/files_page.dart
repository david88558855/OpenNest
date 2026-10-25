import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/frame.dart';
import '../../app/providers.dart';
import '../../core/app_info.dart';
import '../../core/format.dart';
import '../../core/models/api_types.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/file_widgets.dart';
import '../../core/widgets/ol_controls.dart';
import '../../core/widgets/ol_scroll.dart';
import '../../core/widgets/ol_dialogs.dart';
import '../../core/widgets/ol_icon.dart';
import '../../core/widgets/workspace_nav.dart';
import 'file_actions.dart';
import 'files_controller.dart';

part 'parts/files_sidebar.dart';
part 'parts/files_desktop_chrome.dart';
part 'parts/files_list.dart';
part 'parts/files_mobile.dart';

/// W2（Windows 文件管理）/ W7（深色变体）/ A2（Android 文件列表）。
///
/// 布局：挂载点导航 204 → 列表（面包屑 50 / 工具条 48 / 表头 28 / 行 44 /
/// 拖拽提示 / 状态栏 30）。详情面板已于 v1.0.14 移除，现在是两栏。
/// 四态齐全：空目录 / 加载骨架 / 连接失败 / 离线。
///
/// v1.0.24：文件按职责拆到 `parts/`，本文件只保留页面壳与状态机：
///   - `parts/files_sidebar.dart`         左栏（挂载点）
///   - `parts/files_desktop_chrome.dart`  顶部条 / 面包屑 / 工具条 / 状态栏
///   - `parts/files_list.dart`            列表 / 网格 / 四态 / 拖拽浮层
///   - `parts/files_mobile.dart`          移动端零件与批量条
/// 用 `part` 共享私有作用域，拆分只搬代码、不改逻辑。
class FilesPage extends ConsumerStatefulWidget {
  final String? initialPath;
  const FilesPage({super.key, this.initialPath});

  @override
  ConsumerState<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends ConsumerState<FilesPage> {
  final _scroll = ScrollController();
  bool _dragging = false;
  FileKind? _kind;

  /// 批量模式：点击行只做勾选；长按任意行也会进入批量模式并勾选该行。
  bool _batch = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _openInitial();
  }

  @override
  void didUpdateWidget(covariant FilesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 侧栏挂载点走 /files?path=…，同一路由重建时 State 不会重建。
    if (widget.initialPath != oldWidget.initialPath) _openInitial();
  }

  void _openInitial() {
    final path = widget.initialPath;
    // null 表示没有显式路径（保留当前目录）；显式 "/" 要能回到根目录。
    if (path == null || path.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(filesProvider.notifier).open(path);
    });
  }

  void _onScroll() {
    final state = ref.read(filesProvider);
    if (!state.hasMore || state.loadingMore || state.loading) return;
    if (_scroll.position.extentAfter < 600) ref.read(filesProvider.notifier).loadMore();
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  List<FileItem> _filtered(List<FileItem> items) {
    final kind = _kind;
    if (kind == null) return items;
    return items.where((e) => kindOf(e.name, e.isDir) == kind).toList();
  }

  /// 打开文件操作菜单（v2.4）。异常一律转成可见提示，避免静默失败。
  Future<void> _showMenu(Offset position, FileItem item) async {
    try {
      await showItemMenu(context, ref, item, position, selection: ref.read(filesProvider).selectedItems);
    } catch (error) {
      if (mounted) olToast(context, '操作菜单打开失败：$error', error: true);
    }
  }

  void _openItem(FileItem item) {
    if (item.isDir) {
      ref.read(filesProvider.notifier).open(joinPath(ref.read(filesProvider).path, item.name));
    } else {
      openItem(context, ref, item);
    }
  }

  @override
  Widget build(BuildContext context) {
    // v1.0.38：目录切换后把列表拉回顶部。之前沿用上一个目录的滚动位置，
    // 新列表更短时会被 clamp 到末尾，看起来像「闪/跳」一下。
    ref.listen<String>(filesProvider.select((s) => s.path), (previous, next) {
      if (previous != next && _scroll.hasClients) _scroll.jumpTo(0);
    });
    if (context.isNarrow) return _buildMobile(context);
    return _buildDesktop(context);
  }

  // ------------------------------------------------------------------ W2 桌面
  Widget _buildDesktop(BuildContext context) {
    final state = ref.watch(filesProvider);
    return AppFrame(
      navIndex: 0,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyK, control: true): () => context.go('/search'),
          const SingleActivator(LogicalKeyboardKey.f5): () => ref.read(filesProvider.notifier).refresh(),
          const SingleActivator(LogicalKeyboardKey.keyA, control: true): () => ref.read(filesProvider.notifier).selectAll(),
          const SingleActivator(LogicalKeyboardKey.escape): () => ref.read(filesProvider.notifier).clearSelection(),
          const SingleActivator(LogicalKeyboardKey.delete): () {
            final selected = ref.read(filesProvider).selectedItems;
            if (selected.isNotEmpty) deleteItems(context, ref, selected);
          },
        },
        child: Focus(
          autofocus: true,
          child: Row(
            children: [
              const _Sidebar(),
              Expanded(
                child: DropTarget(
                  onDragEntered: (_) => setState(() => _dragging = true),
                  onDragExited: (_) => setState(() => _dragging = false),
                  onDragDone: (detail) async {
                    setState(() => _dragging = false);
                    if (detail.files.isEmpty) return;
                    await uploadPaths(context, ref, detail.files.map((e) => e.path).toList());
                  },
                  child: Stack(
                    children: [
                      Column(
                        children: [
                          const _TopBar(),
                          _Toolbar(
                            kind: _kind,
                            onKind: (k) => setState(() => _kind = k),
                            visible: _filtered(state.items).map((e) => e.name).toList(),
                            batch: _batch,
                            onBatch: (v) => setState(() {
                              _batch = v;
                              if (!v) ref.read(filesProvider.notifier).clearSelection();
                            }),
                          ),
                          Expanded(child: _buildBody(state)),
                          const _DropHint(),
                          const _StatusBar(),
                        ],
                      ),
                      if (_dragging) const _DropOverlay(),
                      // v1.0.26：桌面批量模式之前只有复选框、没有任何操作条，
                      // 等于「能选不能动」。这里补上与移动端同一套 _BatchBar。
                      // bottom 42 是为了让开 30 高的状态栏。
                      if (_batch)
                        Positioned(
                          left: 12,
                          right: 12,
                          bottom: 42,
                          child: _batchBar(state, _filtered(state.items)),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 批量操作条：桌面与移动端共用，动作集合完全一致。
  Widget _batchBar(FilesState state, List<FileItem> items) {
    return _BatchBar(
      count: state.selected.length,
      onSelectAll: () {
        final notifier = ref.read(filesProvider.notifier);
        final allSelected = items.isNotEmpty && items.every((e) => state.selected.contains(e.name));
        if (allSelected) {
          notifier.clearSelection();
        } else {
          notifier.selectOnly(items.map((e) => e.name));
        }
      },
      onDownload: () => downloadItems(context, ref, state.selectedItems),
      onMove: () => moveOrCopyItems(context, ref, state.selectedItems, move: true),
      onCopy: () => moveOrCopyItems(context, ref, state.selectedItems, move: false),
      onDelete: () => deleteItems(context, ref, state.selectedItems),
      onExit: () => setState(() {
        _batch = false;
        ref.read(filesProvider.notifier).clearSelection();
      }),
    );
  }

  Widget _buildBody(FilesState state) {
    final items = _filtered(state.items);
    // v1.0.38：骨架屏只在「超过 400ms 仍未返回」时出现（showSkeleton 由 controller 置位），
    // 快速切换目录时不再闪一下骨架；未到延迟前用等高占位保持布局稳定。
    if (items.isEmpty && state.showSkeleton) return const _SkeletonBody();
    if (items.isEmpty && state.loading) return const SizedBox.expand();
    if (items.isEmpty && state.error != null && !state.offline) {
      return _ErrorBody(
        message: state.error!,
        onRetry: () => ref.read(filesProvider.notifier).refresh(),
      );
    }
    if (items.isEmpty) return _EmptyBody(filtered: _kind != null);
    final list = state.grid
        ? _GridView(
            items: items,
            scroll: _scroll,
            onOpen: _openItem,
            batch: _batch,
            onMenu: (item, position) => showItemMenu(context, ref, item, position, selection: state.selectedItems),
          )
        : _ListView(
            items: items,
            scroll: _scroll,
            onOpen: _openItem,
            batch: _batch,
            onMenu: (item, position) => showItemMenu(context, ref, item, position, selection: state.selectedItems),
          );

    // v1.0.42：切目录时保留了旧列表（避免闪烁），但若新目录加载失败，
    // `items` 非空就不会走上面的 _ErrorBody —— 用户看到上一个目录的内容却没有提示。
    if (state.error != null && !state.offline) {
      return Column(
        children: [
          _InlineErrorBar(
            message: state.error!,
            onRetry: () => ref.read(filesProvider.notifier).refresh(),
          ),
          Expanded(
            child: OlPullToRefresh(
              onRefresh: () => ref.read(filesProvider.notifier).refresh(),
              child: list,
            ),
          ),
        ],
      );
    }
    return OlPullToRefresh(
      onRefresh: () => ref.read(filesProvider.notifier).refresh(),
      child: list,
    );
  }

  // ---------------------------------------------------------------- A2 移动端
  Widget _buildMobile(BuildContext context) {
    final state = ref.watch(filesProvider);
    final items = _filtered(state.items);
    return AppFrame(
      navIndex: 0,
      // v2.2：返回键在子目录里先回上一级；v2.5：到根目录后交给框架做「双击退出」。
      handleBack: true,
      onBack: () async {
        if (_batch) {
          setState(() => _batch = false);
          ref.read(filesProvider.notifier).clearSelection();
          return true;
        }
        if (state.path != '/') {
          await ref.read(filesProvider.notifier).goUp();
          return true;
        }
        return false;
      },
      child: Stack(
        children: [
          OlPullToRefresh(
            onRefresh: () => ref.read(filesProvider.notifier).refresh(),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                const SliverToBoxAdapter(child: _MobileHead()),
                const SliverToBoxAdapter(child: _MobileMounts()),
                SliverToBoxAdapter(
                  child: _KindFilter(
                    value: _kind,
                    onChanged: (k) => setState(() => _kind = k),
                    batch: _batch,
                    onBatch: (v) => setState(() {
                      _batch = v;
                      if (!v) ref.read(filesProvider.notifier).clearSelection();
                    }),
                  ),
                ),
                SliverToBoxAdapter(child: _MobileCrumb(state: state)),
                // 错误条独立于下面的 if/else 链：有旧列表时要和列表同时出现
                if (items.isNotEmpty && state.error != null && !state.offline)
                  SliverToBoxAdapter(
                    child: _InlineErrorBar(
                      message: state.error!,
                      onRetry: () => ref.read(filesProvider.notifier).refresh(),
                    ),
                  ),
                if (items.isEmpty && state.showSkeleton)
                  const SliverToBoxAdapter(child: SizedBox(height: 420, child: _SkeletonBody()))
                else if (items.isEmpty && state.loading)
                  const SliverToBoxAdapter(child: SizedBox(height: 420))
                else if (items.isEmpty && state.error != null && !state.offline)
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 300,
                      child: _ErrorBody(
                        message: state.error!,
                        onRetry: () => ref.read(filesProvider.notifier).refresh(),
                      ),
                    ),
                  )
                else if (items.isEmpty)
                  SliverToBoxAdapter(
                    child: SizedBox(height: 300, child: _EmptyBody(filtered: _kind != null)),
                  )
                else
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (rowContext, index) {
                        final item = items[index];
                        final selected = state.selected.contains(item.name);
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: OlGap.pageMobile),
                          child: _MobileRow(
                            item: item,
                            selected: selected,
                            batch: _batch,
                            onMenu: (pos) => _showMenu(pos, item),
                            onTap: () {
                              if (_batch) {
                                ref.read(filesProvider.notifier).toggleSelect(item.name);
                                return;
                              }
                              if (item.isDir) {
                                _openItem(item);
                                return;
                              }
                              // v2.1：点击文件先给操作列表，不直接打开/预览。
                              // v2.4：用页面级 context（不是 sliver 项 context），
                              // 避免列表重建后 context 失效导致弹层打不开；
                              // 异常要显式提示，不能再"点了没反应"。
                              final box = rowContext.findRenderObject() as RenderBox?;
                              final pos = box == null
                                  ? Offset.zero
                                  : box.localToGlobal(Offset(box.size.width / 2, box.size.height));
                              unawaited(_showMenu(pos, item));
                            },
                            onLongPress: () {
                              setState(() => _batch = true);
                              if (!selected) ref.read(filesProvider.notifier).toggleSelect(item.name);
                            },
                          ),
                        );
                      },
                      childCount: items.length,
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 112)),
              ],
            ),
          ),
          if (!_batch)
            Positioned(
              // v2.4：FAB 下移到右下角，坐在「设置」Tab 的正上方（原来 86 太靠上）。
              right: 18,
              bottom: 18,
              child: _Fab(
                onUpload: () => pickAndUpload(context, ref),
                onNewFolder: () => createFolder(context, ref),
                onOffline: () => offlineDownload(context, ref),
              ),
            ),
          if (_batch)
            Positioned(left: 12, right: 12, bottom: 12, child: _batchBar(state, items)),
          if (state.offline)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: Container(
                color: const Color(0xFFFFF6E5),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
                child: const Row(
                  children: [
                    OlIcon('alert', size: 12, color: Color(0xFFB47405)),
                    SizedBox(width: 6),
                    Text('离线模式 · 显示本地缓存', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: Color(0xFF5E4A22))),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

