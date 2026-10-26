part of '../files_page.dart';

// ---------------------------------------------------------------------------
// 左侧栏：存储源 + 底部动作（对齐效果图 D3）
// ---------------------------------------------------------------------------
class _Sidebar extends ConsumerWidget {
  const _Sidebar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final sources = ref.watch(sourcesProvider).valueOrNull ?? const <StorageSource>[];
    final transfers = ref.watch(transfersProvider);
    final currentPath = ref.watch(filesProvider).path;

    return Container(
      width: 236,
      decoration: BoxDecoration(
        // 0.5.0：侧栏与主区背景互换 —— 侧栏改白底，主区改浅蓝灰。
        // 与设置页 D8 的结构保持一致（导航白、内容区 #F8FBFE）。
        color: p.card,
        border: Border(right: BorderSide(color: p.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(10, 14, 10, 8),
              children: [
                _SideLabel(text: '存储源'),
                if (sources.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
                    child: Text('还没有存储源', style: TextStyle(fontSize: 10.5, color: p.ink4)),
                  ),
                for (final source in sources)
                  _SourceRow(
                    source: source,
                    active: currentPath == source.mountPath || currentPath.startsWith('${source.mountPath}/'),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => context.push('/sources/add'),
                    borderRadius: BorderRadius.circular(9),
                    child: Container(
                      height: 34,
                      decoration: BoxDecoration(
                        color: p.card,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: const Color(0xFFBDE7FA), style: BorderStyle.solid),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          OlIcon('plus', size: 12, color: OlTokens.sky600),
                          SizedBox(width: 6),
                          Text(
                            '添加存储源',
                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF08799F)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _SideAction(
                        icon: 'download',
                        label: '传输',
                        badge: transfers.pendingCount,
                        onTap: () => context.go('/transfers'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _SideAction(
                        icon: 'settings',
                        label: '设置',
                        onTap: () => context.go('/settings'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SideLabel extends StatelessWidget {
  final String text;
  const _SideLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          color: context.ol.ink4,
        ),
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  final StorageSource source;
  final bool active;

  const _SourceRow({required this.source, required this.active});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: () => context.go('/files?path=${Uri.encodeComponent(source.mountPath)}'),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
            decoration: BoxDecoration(
              color: active ? p.card : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              // 常驻 1px 描边：选中/悬停时不会因为多出边框而跳动
              border: Border.all(color: active ? const Color(0xFFBDE7FA) : Colors.transparent),
            ),
            child: Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: source.disabled ? p.chipBg : const Color(0xFFEAF8FE),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Center(
                    child: OlIcon(
                      source.driver == 'Local' ? 'hard-drive' : 'cloud',
                      size: 13,
                      color: source.disabled ? p.ink4 : OlTokens.sky600,
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    source.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      color: active ? p.ink : p.ink2,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: source.disabled ? p.chipBg : const Color(0xFFEAF8FE),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    driverShortTag(source.driver),
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: source.disabled ? p.ink4 : const Color(0xFF08799F),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SideAction extends StatelessWidget {
  final String icon;
  final String label;
  final int badge;
  final VoidCallback onTap;

  const _SideAction({required this.icon, required this.label, required this.onTap, this.badge = 0});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          height: 34,
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: p.line),
          ),
          child: Stack(
            children: [
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OlIcon(icon, size: 13, color: p.ink2),
                    const SizedBox(width: 5),
                    Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: p.ink2)),
                  ],
                ),
              ),
              if (badge > 0)
                Positioned(
                  right: 4,
                  top: -1,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: OlTokens.sky600,
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: p.surface, width: 1.5),
                    ),
                    child: Text(
                      '$badge',
                      style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
