part of '../servers_page.dart';

// 移动端服务器卡
class _MobileServerCard extends StatelessWidget {
  final ServerProfile profile;
  final VoidCallback onSwitch;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _MobileServerCard({required this.profile, required this.onSwitch, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    final (label, color) = switch (profile.health) {
      ServerHealth.ok => ('${profile.latencyMs ?? 0} ms', OlTokens.okDeep),
      ServerHealth.timeout => ('超时', OlTokens.warnDeep),
      ServerHealth.unauthorized => ('需登录', OlTokens.dangerDeep),
      ServerHealth.unknown => ('未连接', p.ink4),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.line2)),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(9)),
                child: Center(child: OlIcon('server', size: 15, color: p.ink3)),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(profile.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.ink)),
                    Text(profile.displayHost, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 9.5, color: p.ink4)),
                  ],
                ),
              ),
              Text(label, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: color)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _TinyButton(label: profile.health == ServerHealth.timeout ? '重连' : '打开', primary: true, onTap: onSwitch),
              const SizedBox(width: 5),
              _TinyButton(label: '编辑', onTap: onEdit),
              const Spacer(),
              GestureDetector(
                onTapDown: (details) async {
                  await showOlMenu(context, position: details.globalPosition, items: [
                    OlMenuItem('编辑', 'edit', onEdit),
                    OlMenuItem('删除', 'trash', onDelete, danger: true),
                  ]);
                },
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: OlIcon('more', size: 14, color: p.ink3),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 返回上一页：从设置页 push 进来时回设置，从标题栏直接进来时回文件页。
void _backToPrevious(BuildContext context) {
  if (GoRouter.of(context).canPop()) {
    context.pop();
  } else {
    context.go('/files');
  }
}
