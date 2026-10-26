part of '../files_page.dart';

// ---------------------------------------------------------------------------
// 面包屑 / 工具条 / 状态栏
// ---------------------------------------------------------------------------
class _TopBar extends ConsumerWidget {
  final FileKind? kind;
  final ValueChanged<FileKind?> onKind;
  final bool batch;
  final VoidCallback onBatch;

  const _TopBar({required this.kind, required this.onKind, required this.batch, required this.onBatch});

  Future<void> _moreMenu(BuildContext context, WidgetRef ref, Offset position) async {
    final state = ref.read(filesProvider);
    final notifier = ref.read(filesProvider.notifier);
    await showOlMenu(context, position: position, items: [
      OlMenuItem('新建文件夹', 'folder-plus', () => createFolder(context, ref), divider: true),
      OlMenuItem('按名称排序', 'sort', () => notifier.setSort('name')),
      OlMenuItem('按大小排序', 'sort', () => notifier.setSort('size')),
      OlMenuItem('按修改时间排序', 'clock', () => notifier.setSort('modified')),
      OlMenuItem(state.desc ? '改为升序' : '改为降序', 'arrow-up', () {
        notifier.setSort(state.orderBy, desc: !state.desc);
      }, divider: true),
      OlMenuItem('筛选：全部类型', 'filter', () => onKind(null)),
      OlMenuItem('筛选：仅文件夹', 'folder', () => onKind(FileKind.folder)),
      OlMenuItem('筛选：仅视频', 'film', () => onKind(FileKind.video)),
      OlMenuItem('筛选：仅图片', 'image', () => onKind(FileKind.image)),
      OlMenuItem('筛选：仅文档', 'file-text', () => onKind(FileKind.text), divider: true),
      OlMenuItem(batch ? '退出批量选择' : '批量选择', 'check', onBatch),
    ]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final state = ref.watch(filesProvider);
    final notifier = ref.read(filesProvider.notifier);
    final segs = state.path.split('/').where((e) => e.isNotEmpty).toList();
    final sources = ref.watch(sourcesProvider).valueOrNull ?? const <StorageSource>[];
    StorageSource? current;
    for (final source in sources) {
      if (state.path == source.mountPath || state.path.startsWith('${source.mountPath}/')) {
        current = source;
        break;
      }
    }
    final rootLabel = current?.displayName ?? '全部文件';
    final atRoot = state.path == '/';

    return Container(
      height: OlDesktop.topBar,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        // 0.5.0：主区底色改为浅蓝灰后，顶栏透明化，透出同一层。
        color: Colors.transparent,
        border: Border(bottom: BorderSide(color: p.line)),
      ),
      child: Row(
        children: [
          // 设计稿是「后退 / 前进 / 上一级」三颗；本项目没有历史栈，
          // 这里落成「返回上一级」与「回到全部文件」两颗可用按钮。
          OlIconButton(
            icon: 'chev-l',
            size: OlDesktop.iconBtn,
            squared: true,
            iconSize: 15,
            tooltip: '返回上一级',
            onTap: atRoot ? null : () => notifier.goUp(),
          ),
          const SizedBox(width: 8),
          OlIconButton(
            icon: 'arrow-up',
            size: OlDesktop.iconBtn,
            squared: true,
            iconSize: 15,
            tooltip: '回到全部文件',
            onTap: atRoot ? null : () => notifier.open('/'),
          ),
          const SizedBox(width: 8),
          const OlIcon('cloud', size: 13, color: OlTokens.sky600, strokeWidth: 2),
          const SizedBox(width: 6),
          Flexible(
            child: _Crumb(
              text: rootLabel,
              current: atRoot,
              onTap: () => notifier.open('/'),
            ),
          ),
          for (var i = 0; i < segs.length; i++) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 2),
              child: Text('/', style: TextStyle(fontSize: 12.5, color: Color(0xFF9DB2C4))),
            ),
            Flexible(
              child: _Crumb(
                // 0.5.0：挂载点那一段显示存储源名称（如「本地存储6」），
                // 不显示引擎的挂载路径段（s_xxxxxxxx）。
                // 跳转路径仍用原始段 —— 那是引擎侧的真实路径。
                text: i == 0 && current != null ? current.displayName : segs[i],
                current: i == segs.length - 1,
                onTap: () => notifier.open('/${segs.take(i + 1).join('/')}'),
              ),
            ),
          ],
          const Spacer(),
          _SearchMini(onTap: () => context.go('/search')),
          const SizedBox(width: 8),
          OlGhostButton(
            label: '上传',
            icon: 'upload',
            height: OlDesktop.btn,
            fontSize: 12,
            horizontalPadding: 14,
            fgColor: p.ink,
            onTap: () => pickAndUpload(context, ref),
          ),
          const SizedBox(width: 8),
          OlGhostButton(
            label: '新建',
            icon: 'plus',
            height: OlDesktop.btn,
            fontSize: 12,
            horizontalPadding: 14,
            fgColor: p.ink,
            onTap: () => createFolder(context, ref),
          ),
          const SizedBox(width: 8),
          OlIconButton(
            icon: 'list',
            size: OlDesktop.iconBtn,
            squared: true,
            iconSize: 15,
            tooltip: '列表视图',
            color: state.grid ? p.ink2 : OlTokens.sky600,
            onTap: state.grid ? notifier.toggleGrid : null,
          ),
          const SizedBox(width: 8),
          OlIconButton(
            icon: 'grid',
            size: OlDesktop.iconBtn,
            squared: true,
            iconSize: 15,
            tooltip: '网格视图',
            color: state.grid ? OlTokens.sky600 : p.ink2,
            onTap: state.grid ? null : notifier.toggleGrid,
          ),
          const SizedBox(width: 8),
          // OlIconButton 没有 onTapDown，这里包一层拿按钮右下角作为菜单锚点。
          Builder(
            builder: (btnContext) => GestureDetector(
              onTapDown: (_) {
                final box = btnContext.findRenderObject() as RenderBox?;
                final position = box == null
                    ? Offset.zero
                    : box.localToGlobal(Offset(box.size.width, box.size.height + 4));
                _moreMenu(context, ref, position);
              },
              child: OlIconButton(
                icon: 'more-v',
                size: OlDesktop.iconBtn,
                squared: true,
                iconSize: 15,
                tooltip: '更多',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Crumb extends StatelessWidget {
  final String text;
  final bool current;
  final VoidCallback onTap;
  const _Crumb({required this.text, required this.current, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: current ? 14 : 13,
              fontWeight: current ? FontWeight.w800 : FontWeight.w600,
              color: current ? p.ink : p.ink3,
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchMini extends StatelessWidget {
  final VoidCallback onTap;
  const _SearchMini({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 186,
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            color: p.fieldBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: p.line2),
          ),
          child: Row(
            children: [
              OlIcon('search', size: 13, color: p.ink4),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '搜索当前目录',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: p.ink4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DropHint extends StatelessWidget {
  const _DropHint();

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return SizedBox(
      height: 28,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          OlIcon('upload', size: 13, color: p.ink4),
          const SizedBox(width: 6),
          Text('将文件拖到这里上传到当前目录', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: p.ink4)),
        ],
      ),
    );
  }
}

class _StatusBar extends ConsumerWidget {
  const _StatusBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final session = ref.watch(sessionProvider);
    final files = ref.watch(filesProvider);
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        // 0.5.0：与顶栏一致，透明化透出主区的浅蓝灰底。
        color: Colors.transparent,
        border: Border(top: BorderSide(color: p.line2)),
      ),
      child: Row(
        children: [
          OlDot(color: session.signedIn ? OlTokens.ok : OlTokens.warn, size: 6),
          const SizedBox(width: 7),
          Text(
            session.signedIn ? '已连接 · 内嵌引擎' : '未连接',
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: p.ink2),
          ),
          const SizedBox(width: 10),
          Text('·', style: TextStyle(fontSize: 10.5, color: p.ink4)),
          const SizedBox(width: 10),
          Text('${files.total} 个项目', style: TextStyle(fontSize: 10.5, color: p.ink3)),
          if (files.selected.isNotEmpty) ...[
            const SizedBox(width: 10),
            Text('·', style: TextStyle(fontSize: 10.5, color: p.ink4)),
            const SizedBox(width: 10),
            Text('已选 ${files.selected.length} 项', style: TextStyle(fontSize: 10.5, color: p.ink3)),
          ],
          const Spacer(),
          if (files.offline)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Text('离线 · 缓存目录', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: OlTokens.warn)),
            ),
          Text(
            '双击打开 · 空格预览',
            style: TextStyle(fontSize: 10, color: p.ink4),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 列表 / 网格

/// 内联错误条（v1.0.42）。
///
/// 切目录保留旧列表后，若新目录加载失败不会走整页 `_ErrorBody`（那会清掉列表），
/// 用这条紧凑横幅把原因显示在列表上方，并提供重试。
class _InlineErrorBar extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _InlineErrorBar({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 6, 8, 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: OlTokens.dangerSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: OlTokens.dangerBorder),
      ),
      child: Row(
        children: [
          const OlIcon('alert', size: 13, color: OlTokens.dangerDeep),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10.5, height: 1.4, color: OlTokens.dangerInk),
            ),
          ),
          const SizedBox(width: 8),
          OlGhostButton(label: '重试', icon: 'refresh', height: 22, fontSize: 9, onTap: onRetry),
        ],
      ),
    );
  }
}
