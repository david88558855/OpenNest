part of '../transfers_page.dart';

// 左侧栏：返回入口 + 下载目录
// ---------------------------------------------------------------------------
// 左侧栏
// ---------------------------------------------------------------------------
class _QueueSidebar extends ConsumerWidget {
  const _QueueSidebar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;

    return Container(
      width: 200,
      decoration: BoxDecoration(
        // 0.5.0：与文件页一致 —— 侧栏改白底，主区改浅蓝灰。
        color: p.card,
        border: Border(right: BorderSide(color: p.line)),
      ),
      // 0.5.0：外层 padding 与设置页一致（18/12），返回行的图标位置
      // 与下方按钮的横向起点都与设置页对齐。
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 0.5.0：返回入口放在侧栏顶部靠左，规格与设置页的返回行完全一致
          // （padding 9/10、圆角 9、chev-l 15px + 文字 12.5/600）。
          _SideBackRow(onTap: () => goBackOrFiles(context)),
          // 0.5.0：移除侧栏的存储源列表 —— 存储源切换属于文件页的职责，
          // 传输页只关心队列本身。
          // 0.5.2：同时去掉「设置」入口 —— 传输页不需要它（左侧导航栏/设置页
          // 本身都能进设置，这里再放一个是重复入口，还占掉了队列的纵向空间）。
          const SizedBox(height: 10),
          _MiniButton(
            icon: 'download',
            label: '下载目录',
            onTap: () => showDownloadDirDialog(context, ref),
          ),
          // 剩余空间留白，按钮不再贴着窗口底边。
          const Spacer(),
        ],
      ),
    );
  }
}

/// 侧栏顶部的返回行。
///
/// 规格与设置页 `SettingsSidebar` 的返回项一致：chev-l 图标 15px + 文字
/// 12.5/600，padding 9/10、圆角 9。两页的返回入口位置与样式统一。
class _SideBackRow extends StatelessWidget {
  final VoidCallback onTap;

  const _SideBackRow({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          margin: const EdgeInsets.only(bottom: 1),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            children: [
              OlIcon('chev-l', size: 15, color: p.ink3),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '返回',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.ink2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
