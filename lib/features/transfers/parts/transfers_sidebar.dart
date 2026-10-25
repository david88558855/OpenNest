part of '../transfers_page.dart';

// 左侧栏：存储源列表（设计稿 D5）
// ---------------------------------------------------------------------------
// 左侧栏
// ---------------------------------------------------------------------------
class _QueueSidebar extends ConsumerWidget {
  const _QueueSidebar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final sources = ref.watch(sourcesProvider).valueOrNull ?? const <StorageSource>[];

    return Container(
      width: 200,
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(right: BorderSide(color: p.line)),
      ),
      child: Column(
        children: [
          Expanded(
            child: ListView(
              // 设计稿 D5：侧栏 padding 16/10。
              padding: const EdgeInsets.fromLTRB(10, 16, 10, 0),
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(10, 0, 10, 6),
                  child: Text(
                    '存储源',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF9DB2C4),
                      letterSpacing: 1,
                    ),
                  ),
                ),
                for (final source in sources)
                  _SourceRow(source: source),
                if (sources.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                    child: Text(
                      '还没有存储源',
                      style: TextStyle(fontSize: 11.5, color: p.ink4),
                    ),
                  ),
              ],
            ),
          ),
          // 底部两个 mini 按钮（设计稿 D5）
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _MiniButton(
                  icon: 'download',
                  label: '下载目录',
                  onTap: () => showDownloadDirDialog(context, ref),
                ),
                const SizedBox(height: 8),
                _MiniButton(
                  icon: 'settings',
                  label: '设置',
                  onTap: () => context.go('/settings'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 侧栏源行：名称 + 右侧类型胶囊（设计稿 D5 `.src` + `.pt`）。
class _SourceRow extends StatelessWidget {
  final StorageSource source;

  const _SourceRow({required this.source});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    final tag = driverShortTag(source.driver);
    final (fg, bg) = _tagColors(tag);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => context.go('/files?path=${Uri.encodeComponent(source.mountPath)}'),
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  source.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: p.ink2),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
                child: Text(
                  tag,
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: fg),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 类型胶囊配色：本地/WebDAV 蓝、网盘琥珀、SFTP/FTP/SMB 绿。
  (Color, Color) _tagColors(String tag) {
    const sky = {'本地', 'WebDAV'};
    const green = {'SFTP', 'FTP', 'SMB'};
    if (sky.contains(tag)) {
      return (const Color(0xFF08799F), const Color(0xFFEAF8FE));
    }
    if (green.contains(tag)) {
      return (const Color(0xFF0B6B4A), const Color(0xFFD3F2E6));
    }
    return (const Color(0xFFB7791F), const Color(0xFFFEF3C7));
  }
}

/// 侧栏底部 mini 按钮（设计稿 D5 `.mini`）：34 高、描边、白底。
class _MiniButton extends StatelessWidget {
  final String icon;
  final String label;
  final VoidCallback onTap;

  const _MiniButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 34,
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: p.line),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OlIcon(icon, size: 13, color: p.ink2),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: p.ink2)),
            ],
          ),
        ),
      ),
    );
  }
}
