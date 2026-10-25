part of '../files_page.dart';

// ---------------------------------------------------------------------------
class _ListView extends ConsumerWidget {
  final List<FileItem> items;
  final ScrollController scroll;
  final ValueChanged<FileItem> onOpen;
  final bool batch;
  final void Function(FileItem item, Offset position) onMenu;

  const _ListView({
    required this.items,
    required this.scroll,
    required this.onOpen,
    required this.batch,
    required this.onMenu,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final state = ref.watch(filesProvider);
    return Column(
      children: [
        Container(
          height: 28,
          color: p.tableHeadBg,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              const SizedBox(width: 30),
              Expanded(
                flex: 5,
                child: Text('名称', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: p.th)),
              ),
              SizedBox(
                width: 74,
                child: Text('大小', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: p.th)),
              ),
              SizedBox(
                width: 108,
                child: Text('修改时间', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: p.th)),
              ),
              const SizedBox(width: 34),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: scroll,
            // 内容不满一屏时也能下拉刷新
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return _FileRow(
                item: item,
                selected: state.selected.contains(item.name),
                batch: batch,
                onTap: () {
                  if (batch) {
                    ref.read(filesProvider.notifier).toggleSelect(item.name);
                    return;
                  }
                  // v2.1：单击文件夹进入；单击文件先给操作列表。
                  if (item.isDir) {
                    onOpen(item);
                  } else {
                    final box = context.findRenderObject() as RenderBox?;
                    final pos = box == null ? Offset.zero : box.localToGlobal(const Offset(40, 44));
                    onMenu(item, pos);
                  }
                },
                onDoubleTap: item.isDir ? () => onOpen(item) : null,
                onMenu: (pos) => onMenu(item, pos),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _FileRow extends StatefulWidget {
  final FileItem item;
  final bool selected;
  final bool batch;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;
  final ValueChanged<Offset> onMenu;

  const _FileRow({
    required this.item,
    required this.selected,
    required this.batch,
    required this.onTap,
    required this.onDoubleTap,
    required this.onMenu,
  });

  @override
  State<_FileRow> createState() => _FileRowState();
}

class _FileRowState extends State<_FileRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    final item = widget.item;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onDoubleTap: widget.onDoubleTap,
        onSecondaryTapDown: (d) => widget.onMenu(d.globalPosition),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: widget.selected ? p.rowSel : (_hover ? p.rowHover : null),
            border: Border(bottom: BorderSide(color: p.divider)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 30,
                // v2.6：非批量模式且未悬停时不画空选择框——之前每行都挂一个
                // 空心小方块，看起来像"图标前面多了个坏掉的控件"。
                child: (widget.batch || _hover || widget.selected)
                    ? Center(
                        child: OlCheckbox(
                          value: widget.selected,
                          onChanged: (_) => widget.onTap(),
                        ),
                      )
                    : null,
              ),
              Expanded(
                flex: 5,
                child: Row(
                  children: [
                    FileGlyph(item: item, size: 29, radius: 8, iconSize: 15),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: p.ink),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 74,
                child: Text(item.isDir ? '—' : formatBytes(item.size), style: TextStyle(fontSize: 11.5, color: p.ink3)),
              ),
              SizedBox(
                width: 108,
                child: Text(formatDate(item.modified), style: TextStyle(fontSize: 11.5, color: p.ink3)),
              ),
              SizedBox(
                width: 34,
                child: (_hover || widget.selected)
                    ? OlIconButton(
                        icon: 'more',
                        size: 24,
                        iconSize: 13,
                        onTap: () {
                          final box = context.findRenderObject() as RenderBox?;
                          final pos = box == null ? Offset.zero : box.localToGlobal(const Offset(20, 30));
                          widget.onMenu(pos);
                        },
                      )
                    : OlIcon('more', size: 13, color: p.ink4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GridView extends ConsumerWidget {
  final List<FileItem> items;
  final ScrollController scroll;
  final ValueChanged<FileItem> onOpen;
  final bool batch;
  final void Function(FileItem item, Offset position) onMenu;

  const _GridView({
    required this.items,
    required this.scroll,
    required this.onOpen,
    required this.batch,
    required this.onMenu,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final state = ref.watch(filesProvider);
    return GridView.builder(
      controller: scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        // v2.6：网格收紧（150→116，比例 0.92→1.06），文件名不再被大片留白推到底部。
        maxCrossAxisExtent: 116,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1.06,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final selected = state.selected.contains(item.name);
        return GestureDetector(
          onTap: () {
            if (batch) {
              ref.read(filesProvider.notifier).toggleSelect(item.name);
              return;
            }
            if (item.isDir) {
              onOpen(item);
            } else {
              final box = context.findRenderObject() as RenderBox?;
              onMenu(item, box == null ? Offset.zero : box.localToGlobal(const Offset(40, 44)));
            }
          },
          onDoubleTap: item.isDir ? () => onOpen(item) : null,
          onSecondaryTapDown: (d) => onMenu(item, d.globalPosition),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: selected ? p.rowSel : p.card,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: selected ? OlTokens.sky.withAlpha(90) : p.line2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FileGlyph(item: item, size: 30, radius: 8, iconSize: 15),
                const SizedBox(height: 6),
                Expanded(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10.5, height: 1.3, fontWeight: FontWeight.w700, color: p.ink),
                    ),
                  ),
                ),
                Text(item.isDir ? '文件夹' : formatBytes(item.size), style: TextStyle(fontSize: 9, color: p.ink4)),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// 四态
// ---------------------------------------------------------------------------
class _SkeletonBody extends StatelessWidget {
  const _SkeletonBody();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      itemCount: 10,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: const [
            OlSkeleton(width: 29, height: 29, radius: 8),
            SizedBox(width: 10),
            Expanded(child: OlSkeleton(height: 11)),
            SizedBox(width: 40),
            OlSkeleton(width: 70, height: 10),
            SizedBox(width: 14),
            OlSkeleton(width: 80, height: 10),
          ],
        ),
      ),
    );
  }
}

class _EmptyBody extends StatelessWidget {
  final bool filtered;
  const _EmptyBody({this.filtered = false});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: OlEmptyState(
        icon: filtered ? 'filter' : 'folder',
        title: filtered ? '没有匹配的文件' : '这个目录还是空的',
        // v2.4：手机上没有右上角上传按钮，提示改为右下角「+」。
        subtitle: filtered
            ? '切换筛选条件，或搜索全部挂载点'
            : (context.isNarrow ? '点右下角「+」上传文件或新建文件夹' : '把文件拖进来，或点右上角「上传」'),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorBody({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: OlEmptyState(
        icon: 'alert',
        title: '无法读取这个目录',
        subtitle: message,
        action: OlGhostButton(label: '重试', icon: 'refresh', onTap: onRetry),
      ),
    );
  }
}

class _DropOverlay extends StatelessWidget {
  const _DropOverlay();

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Positioned.fill(
      child: Container(
        color: OlTokens.sky.withAlpha(18),
        alignment: Alignment.center,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: OlTokens.sky.withAlpha(120)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const OlIcon('upload', size: 18, color: OlTokens.sky600),
              const SizedBox(width: 10),
              Text('松手即可上传到当前目录', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.ink)),
            ],
          ),
        ),
      ),
    );
  }
}
