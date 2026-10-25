part of '../files_page.dart';

// ---------------------------------------------------------------------------
// A2 · 移动端零件（头部 / 挂载点横滑 / 筛选 / 面包屑 / 行 / 批量条 / FAB）
// ---------------------------------------------------------------------------

class _MobileHead extends ConsumerWidget {
  const _MobileHead();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final profile = ref.watch(sessionProvider).profile;
    return Padding(
      padding: const EdgeInsets.fromLTRB(OlGap.pageMobile, 10, OlGap.pageMobile, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const OlDot(color: OlTokens.ok, size: 6),
              const SizedBox(width: 6),
              Expanded(
                child: GestureDetector(
                  onTap: () => context.push('/settings/servers'),
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          profile?.displayHost ?? '本机引擎',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: p.ink2),
                        ),
                      ),
                      const SizedBox(width: 3),
                      OlIcon('chev-r', size: 10, color: p.ink4),
                    ],
                  ),
                ),
              ),
              _CircleBtn(icon: 'search', onTap: () => context.go('/search')),
            ],
          ),
          const SizedBox(height: 10),
          Text('所有文件', style: TextStyle(fontSize: 23, letterSpacing: -0.8, fontWeight: FontWeight.w800, color: p.ink)),
        ],
      ),
    );
  }
}

class _CircleBtn extends StatelessWidget {
  final String icon;
  final VoidCallback onTap;
  const _CircleBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        // v2.3：触控目标由 30 提到 40（与 OlMobile.iconButton 一致）。
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: p.surface, shape: BoxShape.circle, border: Border.all(color: p.line2)),
        child: Center(child: OlIcon(icon, size: 18, color: p.ink2)),
      ),
    );
  }
}

class _MobileMounts extends ConsumerWidget {
  const _MobileMounts();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final storages = ref.watch(storagesProvider).valueOrNull ?? const <StorageMount>[];
    if (storages.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      // v2.4：外层 ListView 的 8+8 padding 会吃掉卡片高度，之前 80 实际只剩 64，
      // 卡片里的「正常」被压到底边。这里给到 96，卡片内容 70 才放得下。
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(OlGap.pageMobile, 8, OlGap.pageMobile, 8),
        itemCount: storages.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final mount = storages[index];
          return GestureDetector(
            onTap: () => context.go('/files?path=${Uri.encodeComponent(mount.mountPath)}'),
            child: Container(
              width: 166,
              padding: const EdgeInsets.fromLTRB(11, 12, 11, 12),
              decoration: BoxDecoration(
                color: p.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: p.line2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      OlIcon('hard-drive', size: 14, color: mount.isUp ? OlTokens.sky700 : p.ink4),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          mount.mountPath == '/' ? '根目录' : mount.mountPath,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: p.ink),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  // v2.1：挂载卡片不再显示容量，只保留驱动与状态。
                  Text(
                    mount.driver.isEmpty ? (mount.isUp ? '已挂载' : '离线') : mount.driver,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: p.ink3),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      OlDot(color: mount.isUp ? OlTokens.ok : const Color(0xFFCBD5E1), size: 5),
                      const SizedBox(width: 4),
                      Text(
                        mount.isUp ? '正常' : '离线',
                        style: TextStyle(fontSize: 9.5, color: p.ink4),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _KindFilter extends StatelessWidget {
  final FileKind? value;
  final ValueChanged<FileKind?> onChanged;
  final bool batch;
  final ValueChanged<bool> onBatch;
  const _KindFilter({
    required this.value,
    required this.onChanged,
    required this.batch,
    required this.onBatch,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Padding(
      padding: const EdgeInsets.fromLTRB(OlGap.pageMobile, 4, OlGap.pageMobile, 4),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  OlChip(label: '全部', selected: value == null, onTap: () => onChanged(null)),
                  const SizedBox(width: 6),
                  OlChip(label: '视频', selected: value == FileKind.video, onTap: () => onChanged(FileKind.video)),
                  const SizedBox(width: 6),
                  OlChip(label: '图片', selected: value == FileKind.image, onTap: () => onChanged(FileKind.image)),
                  const SizedBox(width: 6),
                  OlChip(label: '文档', selected: value == FileKind.text, onTap: () => onChanged(FileKind.text)),
                  // 末尾留一点滚动余量，最后一片不会被视口边缘切掉边框。
                  const SizedBox(width: 2),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // v2.1：类型筛选右侧的批量入口（长按列表项也会进入）。
          GestureDetector(
            onTap: () => onBatch(!batch),
            child: Container(
              // v2.3：与 chip 同高（34），点得中。
              height: OlMobile.chipHeight,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: batch ? OlTokens.sky600 : p.chipBg,
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: batch ? OlTokens.sky600 : p.chipBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OlIcon(batch ? 'check' : 'layers', size: 14, color: batch ? Colors.white : p.ink2),
                  const SizedBox(width: 5),
                  Text(
                    batch ? '完成' : '批量',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: batch ? Colors.white : p.ink2),
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

class _MobileCrumb extends ConsumerWidget {
  final FilesState state;
  const _MobileCrumb({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final segs = state.path.split('/').where((e) => e.isNotEmpty).toList();
    final notifier = ref.read(filesProvider.notifier);
    return Padding(
      padding: const EdgeInsets.fromLTRB(OlGap.pageMobile, 2, OlGap.pageMobile, 6),
      child: Row(
        children: [
          Expanded(
            // v2.1：路径栏按层级分段，点第 N 段回到第 N 层，不再一律回根目录。
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _CrumbTap(
                    label: '全部文件',
                    current: segs.isEmpty,
                    onTap: () => notifier.open('/'),
                  ),
                  for (var i = 0; i < segs.length; i++) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Text('/', style: TextStyle(fontSize: 12, color: p.ink4)),
                    ),
                    _CrumbTap(
                      label: segs[i],
                      current: i == segs.length - 1,
                      onTap: () => notifier.open('/${segs.take(i + 1).join('/')}'),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text('${state.items.length} 个项目', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: p.ink4)),
        ],
      ),
    );
  }
}

class _CrumbTap extends StatelessWidget {
  final String label;
  final bool current;
  final VoidCallback onTap;
  const _CrumbTap({required this.label, required this.current, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: current ? FontWeight.w800 : FontWeight.w600,
            color: current ? p.ink : p.ink3,
          ),
        ),
      ),
    );
  }
}

class _MobileRow extends StatelessWidget {
  final FileItem item;
  final bool selected;
  final bool batch;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  /// 右侧三点：打开竖向操作菜单（收藏 / 分享 / 下载 / 移动 / 复制 / 删除）。
  final ValueChanged<Offset> onMenu;

  const _MobileRow({
    required this.item,
    required this.selected,
    required this.batch,
    required this.onTap,
    required this.onLongPress,
    required this.onMenu,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: Container(
        // v2.3：字号放大后行高由 58 提到 66（OlMobile.rowHeight）。
        height: OlMobile.rowHeight,
        decoration: BoxDecoration(
          color: selected && batch ? p.rowSel : null,
          border: Border(bottom: BorderSide(color: p.divider)),
        ),
        child: Row(
          children: [
            if (batch) ...[
              OlCheckbox(value: selected, onChanged: (_) => onTap()),
              const SizedBox(width: 10),
            ],
            FileGlyph(item: item, size: 38, radius: 10, iconSize: 19),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: p.ink),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.isDir ? '文件夹' : '${formatBytes(item.size)} · ${formatDate(item.modified)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10.5, color: p.ink4),
                  ),
                ],
              ),
            ),
            // v2.6：右侧箭头改为三点，点开即竖向操作菜单（不再依赖长按 / 点行）。
            Builder(
              builder: (btnContext) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  final box = btnContext.findRenderObject() as RenderBox?;
                  final pos = box == null
                      ? Offset.zero
                      : box.localToGlobal(Offset(box.size.width, box.size.height));
                  onMenu(pos);
                },
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Center(child: OlIcon('more-v', size: 16, color: p.ink4)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 批量操作条（A2）：勾选后出现的底部操作。
class _BatchBar extends StatelessWidget {
  final int count;
  final VoidCallback onSelectAll;
  final VoidCallback onDownload;
  final VoidCallback onMove;
  final VoidCallback onCopy;
  final VoidCallback onDelete;
  final VoidCallback onExit;

  const _BatchBar({
    required this.count,
    required this.onSelectAll,
    required this.onDownload,
    required this.onMove,
    required this.onCopy,
    required this.onDelete,
    required this.onExit,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    // v2.3：字号放大后一行放不下「全选 + 计数 + 5 个动作」，
    // 拆成两行：上排状态与全选，下排五个等宽动作，避免互相挤压。
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.line),
        boxShadow: const [BoxShadow(color: Color(0x260D1B2A), blurRadius: 24, offset: Offset(0, 10))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: onSelectAll,
                behavior: HitTestBehavior.opaque,
                child: Row(
                  children: [
                    OlIcon('check', size: 17, color: p.ink2),
                    const SizedBox(width: 6),
                    Text('全选', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.ink2)),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                '已选 $count 项',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.ink3),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: _BatchAction(icon: 'download', label: '下载', enabled: count > 0, onTap: onDownload)),
              Expanded(child: _BatchAction(icon: 'move', label: '移动', enabled: count > 0, onTap: onMove)),
              Expanded(child: _BatchAction(icon: 'copy', label: '复制', enabled: count > 0, onTap: onCopy)),
              Expanded(child: _BatchAction(icon: 'trash', label: '删除', enabled: count > 0, danger: true, onTap: onDelete)),
              Expanded(child: _BatchAction(icon: 'x', label: '退出', enabled: true, onTap: onExit)),
            ],
          ),
        ],
      ),
    );
  }
}

class _BatchAction extends StatelessWidget {
  final String icon;
  final String label;
  final bool enabled;
  final bool danger;
  final VoidCallback onTap;
  const _BatchAction({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    final color = !enabled ? p.ink4 : (danger ? OlTokens.dangerDeep : p.ink2);
    return GestureDetector(
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            OlIcon(icon, size: 19, color: color),
            const SizedBox(height: 4),
            Text(label, maxLines: 1, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
          ],
        ),
      ),
    );
  }
}

class _Fab extends StatefulWidget {
  final VoidCallback onUpload;
  final VoidCallback onNewFolder;
  final VoidCallback onOffline;
  const _Fab({required this.onUpload, required this.onNewFolder, required this.onOffline});

  @override
  State<_Fab> createState() => _FabState();
}

class _FabState extends State<_Fab> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_open) ...[
          _FabAction(icon: 'folder-plus', label: '新建文件夹', onTap: widget.onNewFolder),
          const SizedBox(height: 8),
          _FabAction(icon: 'cloud-dl', label: '离线下载', onTap: widget.onOffline),
          const SizedBox(height: 8),
          _FabAction(icon: 'upload', label: '上传文件', onTap: widget.onUpload),
          const SizedBox(height: 10),
        ],
        GestureDetector(
          onTap: () => setState(() => _open = !_open),
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: OlTokens.gradientBrand,
              borderRadius: BorderRadius.circular(19),
              boxShadow: const [BoxShadow(color: Color(0x6638BDF8), blurRadius: 22, offset: Offset(0, 12))],
            ),
            // v1.0.42：去掉 180ms 旋转动画，图标保持静止（仍是「+」作为展开入口）
            child: const Center(
              child: OlIcon('plus', size: 22, color: Colors.white, strokeWidth: 2.2),
            ),
          ),
        ),
      ],
    );
  }
}

class _FabAction extends StatelessWidget {
  final String icon;
  final String label;
  final VoidCallback onTap;
  const _FabAction({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: p.line2),
          boxShadow: const [BoxShadow(color: Color(0x140D1B2A), blurRadius: 14, offset: Offset(0, 6))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OlIcon(icon, size: 13, color: OlTokens.sky700),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: p.ink2)),
          ],
        ),
      ),
    );
  }
}
