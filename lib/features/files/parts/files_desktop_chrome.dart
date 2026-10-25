part of '../files_page.dart';

// ---------------------------------------------------------------------------
// 面包屑 / 工具条 / 状态栏
// ---------------------------------------------------------------------------
class _TopBar extends ConsumerWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final state = ref.watch(filesProvider);
    final segs = state.path.split('/').where((e) => e.isNotEmpty).toList();
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.hairline))),
      child: Row(
        children: [
          _RoundBtn(
            icon: 'chev-l',
            tooltip: '返回上级',
            onTap: state.path == '/' ? null : () => ref.read(filesProvider.notifier).goUp(),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              children: [
                _Crumb(text: '全部文件', current: segs.isEmpty, onTap: () => ref.read(filesProvider.notifier).open('/')),
                for (var i = 0; i < segs.length; i++) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 2),
                    child: OlIcon('chev-r', size: 12, color: Color(0xFFC2CFDB)),
                  ),
                  Flexible(
                    child: _Crumb(
                      text: segs[i],
                      current: i == segs.length - 1,
                      onTap: () => ref.read(filesProvider.notifier).open('/${segs.take(i + 1).join('/')}'),
                    ),
                  ),
                ],
              ],
            ),
          ),
          _SearchMini(onTap: () => context.go('/search')),
          const SizedBox(width: 8),
          OlPrimaryButton(label: '上传', icon: 'upload', height: 30, onTap: () => pickAndUpload(context, ref)),
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

class _RoundBtn extends StatelessWidget {
  final String icon;
  final String tooltip;
  final VoidCallback? onTap;
  const _RoundBtn({required this.icon, required this.tooltip, this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(color: p.fieldBg, borderRadius: BorderRadius.circular(6)),
            child: Center(child: OlIcon(icon, size: 13, color: onTap == null ? p.ink4 : p.ink3)),
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
              const OlKbd('Ctrl K'),
            ],
          ),
        ),
      ),
    );
  }
}

class _Toolbar extends ConsumerWidget {
  final FileKind? kind;
  final ValueChanged<FileKind?> onKind;
  final List<String> visible;
  final bool batch;
  final ValueChanged<bool> onBatch;
  const _Toolbar({
    required this.kind,
    required this.onKind,
    required this.visible,
    required this.batch,
    required this.onBatch,
  });

  Future<void> _sortMenu(BuildContext context, WidgetRef ref, Offset pos) async {
    final state = ref.read(filesProvider);
    final notifier = ref.read(filesProvider.notifier);
    await showOlMenu(
      context,
      position: pos,
      items: [
        OlMenuItem('按名称', 'sort', () => notifier.setSort('name')),
        OlMenuItem('按大小', 'sort', () => notifier.setSort('size')),
        OlMenuItem('按修改时间', 'clock', () => notifier.setSort('modified')),
        OlMenuItem(state.desc ? '改为升序' : '改为降序', 'arrow-up', () {
          notifier.setSort(state.orderBy, desc: !state.desc);
        }),
      ],
    );
  }

  Future<void> _filterMenu(BuildContext context, Offset pos) async {
    await showOlMenu(
      context,
      position: pos,
      items: [
        OlMenuItem('全部类型', 'filter', () => onKind(null)),
        OlMenuItem('仅文件夹', 'folder', () => onKind(FileKind.folder)),
        OlMenuItem('仅视频', 'film', () => onKind(FileKind.video)),
        OlMenuItem('仅图片', 'image', () => onKind(FileKind.image)),
        OlMenuItem('仅文档', 'file-text', () => onKind(FileKind.text)),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final state = ref.watch(filesProvider);
    final selected = state.selected.length;
    final allSelected = visible.isNotEmpty && visible.every(state.selected.contains);
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.divider))),
      child: Row(
        children: [
          OlCheckbox(
            value: allSelected,
            onChanged: (_) {
              final notifier = ref.read(filesProvider.notifier);
              if (allSelected) {
                notifier.clearSelection();
              } else {
                notifier.selectOnly(visible);
              }
            },
          ),
          const SizedBox(width: 9),
          Text(
            selected == 0 ? '${state.items.length} 个项目' : '${state.items.length} 个项目 · 已选 $selected 项',
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: p.ink4),
          ),
          const SizedBox(width: 10),
          // v1.0.57：桌面端新增「返回上层目录」入口（工具条左侧、紧跟项目计数）。
          // 根目录（state.path == '/'）时禁用置灰，没有可返回的上级。
          //
          // 只在桌面端存在：_Toolbar 仅被 _buildDesktop 使用，安卓端的
          // _KindFilter 不包含此控件 —— 安卓「返回上一层」由系统返回键承担
          // （AppFrame.onBack → filesProvider.goUp()），因此移动端既不渲染
          // 这个按钮，也不绑定任何点击事件。
          OlGhostButton(
            label: '返回上层目录',
            icon: 'arrow-up',
            height: 28,
            fontSize: 10.5,
            onTap: state.path == '/' ? null : () => ref.read(filesProvider.notifier).goUp(),
          ),
          const Spacer(),
          OlSeg<bool>(
            items: const [
              OlSegItem(false, '列表', icon: 'list'),
              OlSegItem(true, '网格', icon: 'grid'),
            ],
            value: state.grid,
            onChanged: (v) {
              if (v != state.grid) ref.read(filesProvider.notifier).toggleGrid();
            },
          ),
          const SizedBox(width: 8),
          Builder(
            builder: (btnContext) => OlIconButton(
              icon: 'sort',
              tooltip: '排序',
              onTap: () {
                final box = btnContext.findRenderObject() as RenderBox?;
                final pos = box == null ? Offset.zero : box.localToGlobal(const Offset(0, 28));
                _sortMenu(context, ref, pos);
              },
            ),
          ),
          Builder(
            builder: (btnContext) => OlIconButton(
              icon: 'filter',
              tooltip: kind == null ? '筛选类型' : '已筛选类型',
              color: kind == null ? null : OlTokens.sky700,
              onTap: () {
                final box = btnContext.findRenderObject() as RenderBox?;
                final pos = box == null ? Offset.zero : box.localToGlobal(const Offset(0, 28));
                _filterMenu(context, pos);
              },
            ),
          ),
          OlIconButton(icon: 'folder-plus', tooltip: '新建文件夹', onTap: () => createFolder(context, ref)),
          const SizedBox(width: 6),
          OlGhostButton(
            label: batch ? '完成' : '批量',
            icon: batch ? 'check' : 'layers',
            height: 28,
            fontSize: 10.5,
            onTap: () => onBatch(!batch),
          ),
        ],
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
    final latency = session.latencyMs;
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: p.surfaceAlt,
        border: Border(top: BorderSide(color: p.line2)),
      ),
      child: Row(
        children: [
          OlDot(color: session.signedIn ? OlTokens.ok : OlTokens.warn, size: 5),
          const SizedBox(width: 6),
          Text(
            session.signedIn ? '已连接${latency == null ? '' : ' · 延迟 $latency ms'}' : '未连接',
            style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w500, color: p.ink3),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              files.provider ?? session.profile?.displayHost ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w500, color: p.ink3),
            ),
          ),
          const Spacer(),
          if (files.offline)
            Text('离线 · 缓存目录', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: OlTokens.warn)),
          const SizedBox(width: 12),
          // v2.3：状态栏同样只显示短版本，长串会把整行挤出屏幕。
          // v2.6：dev / unknown 这类占位版本不显示。
          Text(
            AppInfo.hasMeaningfulVersion(session.profile?.version ?? session.site?.version)
                ? AppInfo.shortVersion(session.profile?.version ?? session.site?.version)
                : '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w500, color: p.ink3),
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
