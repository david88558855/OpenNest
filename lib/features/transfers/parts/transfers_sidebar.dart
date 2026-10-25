part of '../transfers_page.dart';

// 左侧队列导航（进行中 / 下载 / 上传 / 离线 / 已完成 / 失败）
// ---------------------------------------------------------------------------
// 左侧队列
// ---------------------------------------------------------------------------
class _QueueSidebar extends ConsumerWidget {
  final _Filter filter;
  final ValueChanged<_Filter> onFilter;
  const _QueueSidebar({required this.filter, required this.onFilter});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final state = ref.watch(transfersProvider);
    final down = state.active.where((e) => e.kind == TransferKind.download).length;
    final up = state.active.where((e) => e.kind == TransferKind.upload).length;
    final doneBytes = state.done.fold<int>(0, (sum, e) => sum + e.total);

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
                // v1.0.17：工作区导航共用同一份组件（条目/顺序/badge 与其它页一致），
                // 下面是传输页独有的队列筛选。
                const WorkspaceNav(active: 'transfers'),
                const OlSectionLabel('队列'),
                _NavRow(
                  icon: 'layers',
                  label: '进行中',
                  badge: state.pendingCount,
                  active: filter == _Filter.active,
                  onTap: () => onFilter(_Filter.active),
                ),
                _NavRow(
                  icon: 'download',
                  label: '正在下载',
                  badge: down,
                  active: filter == _Filter.download,
                  onTap: () => onFilter(_Filter.download),
                ),
                _NavRow(
                  icon: 'upload',
                  label: '正在上传',
                  badge: up,
                  active: filter == _Filter.upload,
                  onTap: () => onFilter(_Filter.upload),
                ),
                _NavRow(
                  icon: 'cloud-dl',
                  label: '离线下载',
                  badge: state.serverTasks.length,
                  active: filter == _Filter.offline,
                  onTap: () => onFilter(_Filter.offline),
                ),
                _NavRow(
                  icon: 'check',
                  label: '已完成',
                  badge: state.done.length,
                  active: filter == _Filter.done,
                  onTap: () => onFilter(_Filter.done),
                ),
                _NavRow(
                  icon: 'alert',
                  label: '失败',
                  badge: state.failed.length,
                  danger: true,
                  active: filter == _Filter.failed,
                  onTap: () => onFilter(_Filter.failed),
                ),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.fromLTRB(9, 8, 9, 12),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
            decoration: BoxDecoration(gradient: OlTokens.deepPanel, borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('今日流量', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF9DB4C8))),
                    const Spacer(),
                    const Text('不限速', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFF5EEAD4))),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  formatBytes(doneBytes),
                  style: const TextStyle(fontSize: 20, height: 1.1, letterSpacing: -0.5, fontWeight: FontWeight.w800, color: Colors.white),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text('下载 ${formatSpeed(state.downSpeed)}', style: const TextStyle(fontSize: 9, color: Color(0xFF8FA8BD))),
                    const Spacer(),
                    Text('上传 ${formatSpeed(state.upSpeed)}', style: const TextStyle(fontSize: 9, color: Color(0xFF8FA8BD))),
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

class _NavRow extends StatelessWidget {
  final String icon;
  final String label;
  final int badge;
  final bool active;
  final bool danger;
  final VoidCallback? onTap;

  const _NavRow({
    required this.icon,
    required this.label,
    this.badge = 0,
    this.active = false,
    this.danger = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    final fg = danger ? const Color(0xFFC2415A) : (active ? p.navOn : p.nav);
    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            height: 31,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            decoration: BoxDecoration(
              color: active ? p.navOnBg : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                OlIcon(icon, size: 15, color: danger ? const Color(0xFFE06B82) : (active ? OlTokens.sky600 : p.navIcon)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg),
                  ),
                ),
                if (badge > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: active ? p.card : p.navBadgeBg,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text('$badge', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: p.ink4)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
