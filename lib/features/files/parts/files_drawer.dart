part of '../files_page.dart';

// M2 · 移动端切源抽屉（效果图：宽 290 = 内容宽 78.4%，全屏 scrim，零动画）。
//
// 为什么自绘而不用 Scaffold.drawer：框架的 DrawerController 把时长写死成
// 246ms，AnimationStyle / DrawerTheme 都拿不到，与全站「零动画」冲突。
// 这里用条件渲染，一帧出现在位、一帧消失。

class _SourceDrawer extends ConsumerWidget {
  final VoidCallback onClose;

  const _SourceDrawer({required this.onClose});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final state = ref.watch(filesProvider);
    final sources = ref.watch(sourcesProvider).valueOrNull ?? const <StorageSource>[];
    return Container(
      decoration: BoxDecoration(
        color: p.card,
        boxShadow: const [
          BoxShadow(color: Color(0x380E3A46), blurRadius: 44, offset: Offset(14, 0)),
        ],
      ),
      child: Column(
        children: [
          // 0.5.0：去掉顶部「OpenNest / 免账户 · 直连存储」品牌块 ——
          // 抽屉的职责是切存储源，品牌信息在关于页已有，占掉 70px 反而把源列表推低。
          const SizedBox(height: 10),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
              children: [
                const _DrawerSection('存储源'),
                for (final source in sources)
                  _DrawerSourceRow(
                    source: source,
                    active: state.path == source.mountPath || state.path.startsWith('${source.mountPath}/'),
                    onTap: () {
                      onClose();
                      context.go('/files?path=${Uri.encodeComponent(source.mountPath)}');
                    },
                  ),
                if (sources.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                    child: Text('还没有存储源', style: TextStyle(fontSize: 11.5, color: p.ink4)),
                  ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(10, 12, 10, 16 + MediaQuery.viewPaddingOf(context).bottom),
            child: _DrawerAddButton(
              onTap: () {
                onClose();
                context.push('/sources/add');
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DrawerSection extends StatelessWidget {
  final String text;

  const _DrawerSection(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
      child: Text(
        text,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1, color: Color(0xFF9DB2C4)),
      ),
    );
  }
}

class _DrawerSourceRow extends StatelessWidget {
  final StorageSource source;
  final bool active;
  final VoidCallback onTap;

  const _DrawerSourceRow({required this.source, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    const green = {'SFTP', 'FTP', 'SMB'};
    const sky = {'本地', 'WebDAV'};
    final tag = driverShortTag(source.driver);
    final Color tagFg;
    final Color tagBg;
    if (sky.contains(tag)) {
      tagFg = const Color(0xFF08799F);
      tagBg = const Color(0xFFEAF8FE);
    } else if (green.contains(tag)) {
      tagFg = const Color(0xFF0B6B4A);
      tagBg = const Color(0xFFD3F2E6);
    } else {
      tagFg = const Color(0xFFB7791F);
      tagBg = const Color(0xFFFEF3C7);
    }
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        margin: const EdgeInsets.only(bottom: 2),
        decoration: BoxDecoration(
          color: active ? p.rowSel : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                source.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                  color: active ? p.ink : p.ink2,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: tagBg, borderRadius: BorderRadius.circular(99)),
              child: Text(tag, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: tagFg)),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerAddButton extends StatelessWidget {
  final VoidCallback onTap;

  const _DrawerAddButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: OlDashedBox(
        radius: 12,
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const OlIcon('plus', size: 14, color: OlTokens.sky600, strokeWidth: 2.4),
            const SizedBox(width: 7),
            const Text(
              '添加存储源',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF08799F)),
            ),
          ],
        ),
      ),
    );
  }
}
