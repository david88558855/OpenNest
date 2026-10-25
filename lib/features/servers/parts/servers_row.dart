part of '../servers_page.dart';

// 桌面服务器行与小组件（行 / 小按钮 / 配置卡 / 当前实例卡 / 深色 chip）
class _ServerRow extends StatelessWidget {
  final ServerProfile server;
  final bool current;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onSwitch;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onReconnect;

  const _ServerRow({
    required this.server,
    required this.current,
    required this.selected,
    required this.onSelect,
    required this.onSwitch,
    required this.onEdit,
    required this.onDelete,
    required this.onReconnect,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    final healthColor = server.health == ServerHealth.ok
        ? OlTokens.okDeep
        : server.health == ServerHealth.timeout
            ? OlTokens.warnDeep
            : p.ink4;
    return GestureDetector(
      onTap: onSelect,
      onDoubleTap: onSwitch,
      child: Container(
        margin: const EdgeInsets.only(bottom: 7),
        // v1.0.39：行整体略微加高，配合字号/按钮放大
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          gradient: current ? const LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight, colors: [Color(0xFFF5FCFE), Color(0xFFF7FEFC)]) : null,
          color: current ? null : p.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? OlTokens.sky : (current ? const Color(0xFFBFE9F7) : p.line2)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: current ? const Color(0xFFE9F8FF) : p.surfaceAlt, borderRadius: BorderRadius.circular(10)),
              child: Center(child: OlIcon('server', size: 17, color: current ? const Color(0xFF0A93C4) : p.ink3)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          server.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: p.ink),
                        ),
                      ),
                      if (current) ...[
                        const SizedBox(width: 6),
                        const OlBadge(label: '当前'),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${server.baseUrl} · ${server.username}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, fontFamily: 'monospace', color: p.ink4),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 84,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OlDot(size: 4, color: server.health == ServerHealth.ok ? OlTokens.ok : (server.health == ServerHealth.timeout ? OlTokens.warn : p.ink4)),
                      const SizedBox(width: 4),
                      Text(
                        server.latencyMs != null ? '${server.latencyMs} ms' : (server.health == ServerHealth.timeout ? '超时' : '未连接'),
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: healthColor),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(relativeTime(server.lastUsed), style: TextStyle(fontSize: 9.5, color: p.ink4)),
                ],
              ),
            ),
            const SizedBox(width: 6),
            if (!current) _TinyButton(label: '打开', primary: true, onTap: onSwitch),
            const SizedBox(width: 4),
            _TinyButton(label: '编辑', onTap: onEdit),
            GestureDetector(
              onTapDown: (details) async {
                await showOlMenu(context, position: details.globalPosition, items: [
                  OlMenuItem('编辑', 'edit', onEdit),
                  OlMenuItem('测试连接', 'zap', onReconnect),
                  OlMenuItem('删除', 'trash', onDelete, danger: true),
                ]);
              },
              child: Container(
                width: 27,
                height: 27,
                decoration: BoxDecoration(border: Border.all(color: p.line2), borderRadius: BorderRadius.circular(7), color: p.card),
                child: Center(child: OlIcon('more-v', size: 14, color: p.ink3)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TinyButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool primary;

  const _TinyButton({required this.label, required this.onTap, this.primary = false});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // v1.0.16：改用 onTapDown 立即响应。行本身带 onDoubleTap（双击切换服务器），
      // 内层 onTap 会被双击判定拖住约 300ms，用户感知就是「点了编辑没反应」。
      onTapDown: (_) => onTap(),
      child: Container(
        // v1.0.39：按钮略微加大（23×9 → 27×10.5），点击区域更舒服
        height: 27,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: primary ? const Color(0xFFEAF8FE) : p.card,
          border: Border.all(color: primary ? const Color(0xFFCDEEFA) : p.line),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: primary ? const Color(0xFF08799F) : p.ink2),
          ),
        ),
      ),
    );
  }
}

class _ConfigCard extends StatelessWidget {
  /// 传 null 时由外部的 OlSectionLabel 承担标题（左侧窄栏就是这种用法）。
  // ignore: unused_field
  final String? title;
  final Widget child;
  final String footer;

  const _ConfigCard({this.title, required this.child, required this.footer});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.line2)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null && title!.isNotEmpty) ...[
            Text(title!, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: p.ink3)),
            const SizedBox(height: 6),
          ],
          child,
          const SizedBox(height: 5),
          Text(footer, style: TextStyle(fontSize: 8, color: p.ink4)),
        ],
      ),
    );
  }
}

class _CurrentServerCard extends StatelessWidget {
  final ServerProfile profile;
  final bool signedIn;

  const _CurrentServerCard({required this.profile, required this.signedIn});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF0B2233), Color(0xFF0D3B46)]),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const OlMark(size: 26, radius: 8, iconSize: 12),
              const SizedBox(width: 8),
              const Text('CURRENT SERVER', style: TextStyle(fontSize: 8, letterSpacing: 1.6, fontWeight: FontWeight.w800, color: Color(0xFF9DB4C8))),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(color: const Color(0xFF7DD3FC), borderRadius: BorderRadius.circular(5)),
                child: Text(
                  signedIn ? '已连接' : '待登录',
                  style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: Color(0xFF0B5C4C)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(profile.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: Colors.white)),
          const SizedBox(height: 3),
          Text(profile.baseUrl, style: const TextStyle(fontSize: 9.5, fontFamily: 'monospace', color: Color(0xFF8FA8BD))),
          const SizedBox(height: 10),
          Row(
            children: [
              _DarkChip(label: '编辑', icon: 'edit', onTap: () => context.push('/servers/edit/${profile.id}')),
            ],
          ),
        ],
      ),
    );
  }
}

class _DarkChip extends StatelessWidget {
  final String label;
  final String icon;
  final VoidCallback onTap;
  const _DarkChip({required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(color: const Color(0x1FFFFFFF), borderRadius: BorderRadius.circular(7), border: Border.all(color: const Color(0x24FFFFFF))),
        child: Row(
          children: [
            OlIcon(icon, size: 11, color: const Color(0xFFBFE6F5)),
            const SizedBox(width: 5),
            Text(label, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: Color(0xFFCFE6F3))),
          ],
        ),
      ),
    );
  }
}
