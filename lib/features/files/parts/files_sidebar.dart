part of '../files_page.dart';

// ---------------------------------------------------------------------------
// 左侧导航（W2 · dside 204）
// ---------------------------------------------------------------------------
class _Sidebar extends ConsumerWidget {
  const _Sidebar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final storages = ref.watch(storagesProvider).valueOrNull ?? const <StorageMount>[];

    return Container(
      width: 204,
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(right: BorderSide(color: p.line2)),
      ),
      // v1.0.17：工作区导航抽成公共组件（四个页面同一份，顺序固定不跳动）。
      child: ListView(
        padding: const EdgeInsets.fromLTRB(9, 4, 9, 12),
        children: [
          const WorkspaceNav(active: 'files'),
          const OlSectionLabel('挂载点'),
          if (storages.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              child: Text('暂无挂载点', style: TextStyle(fontSize: 10.5, color: p.ink4)),
            ),
          for (final mount in storages) _MountRow(mount: mount),
        ],
      ),
    );
  }
}

class _MountRow extends StatelessWidget {
  final StorageMount mount;
  const _MountRow({required this.mount});

  static const _dotColors = [
    Color(0xFF38BDF8),
    Color(0xFF7C5CFC),
    Color(0xFF22C55E),
    Color(0xFFF59E0B),
    Color(0xFF94A3B8),
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    final up = mount.isUp;
    final dot = _dotColors[mount.id.abs() % _dotColors.length];
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => context.go('/files?path=${Uri.encodeComponent(mount.mountPath)}'),
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 30,
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 9),
          child: Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: up ? dot : const Color(0xFFCBD5E1), borderRadius: BorderRadius.circular(2.5)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  mount.mountPath == '/' ? '根目录' : mount.mountPath,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: p.ink2),
                ),
              ),
              Text(
                // v2.1：挂载项不再展示容量，只标状态。
                up ? '正常' : '离线',
                style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: p.ink4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
