part of '../servers_page.dart';

// 左栏：返回 / 当前实例摘要 / 配置备份

/// 服务器管理自己的左栏：只有「返回」与当前实例摘要。
/// 它是独立一级页面，不再带任何设置导航（v1.0.14：设置已挪到工作区）。
class _ServersRail extends StatelessWidget {
  final ServerProfile? current;
  final int count;
  final VoidCallback onBack;

  /// v1.0.41：配置备份从「服务器列表末尾」上移到「当前实例」卡片正下方，
  /// 位置更符合「当前实例的附属操作」语义，也不用滚到列表底部才找得到。
  final VoidCallback onExport;
  final VoidCallback onImport;

  const _ServersRail({
    required this.current,
    required this.count,
    required this.onBack,
    required this.onExport,
    required this.onImport,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    Widget item(String icon, String label, VoidCallback onTap) => MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: Container(
              height: 31,
              margin: const EdgeInsets.only(bottom: 1),
              padding: const EdgeInsets.symmetric(horizontal: 9),
              child: Row(
                children: [
                  OlIcon(icon, size: 15, color: p.navIcon),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.nav),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

    return Container(
      width: 204,
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(right: BorderSide(color: p.line2)),
      ),
      padding: const EdgeInsets.fromLTRB(9, 4, 9, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const OlSectionLabel('导航'),
          item('chev-l', '返回', onBack),
          const OlSectionLabel('当前实例'),
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.fromLTRB(9, 8, 9, 9),
            decoration: BoxDecoration(
              color: p.surfaceAlt,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: p.line2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  current?.name ?? '未连接',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: p.ink),
                ),
                const SizedBox(height: 2),
                Text(
                  current?.displayHost ?? '—',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 9, fontFamily: 'monospace', color: p.ink4),
                ),
                const SizedBox(height: 4),
                Text('共 $count 个服务器', style: TextStyle(fontSize: 9, color: p.ink4)),
              ],
            ),
          ),
          const OlSectionLabel('配置备份'),
          _ConfigCard(
            child: Row(
              children: [
                Expanded(child: OlChip(label: '导出', icon: 'external', height: 22, onTap: onExport)),
                const SizedBox(width: 5),
                Expanded(child: OlChip(label: '导入', icon: 'download', height: 22, onTap: onImport)),
              ],
            ),
            footer: '不含密码，仅地址与偏好',
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            child: Text(
              '凭据写入系统安全存储\n删除只移除本地配置',
              style: TextStyle(fontSize: 8.5, height: 1.7, color: p.ink4),
            ),
          ),
        ],
      ),
    );
  }
}
