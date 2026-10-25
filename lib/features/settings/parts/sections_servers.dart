part of '../settings_page.dart';

// 服务器分区（只读容量/健康）与其信息条

// ---------------------------------------------------------------------------
// 服务器
// ---------------------------------------------------------------------------
class _ServersSection extends ConsumerWidget {
  const _ServersSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final session = ref.watch(sessionProvider);
    final profile = session.profile;
    final servers = ref.watch(serverListProvider).servers;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHead(
          title: '服务器管理',
          subtitle: '当前连接的 OpenList 实例与登录身份',
          // v1.0.40：push 而非 go —— go 会重建成整条栈，返回时设置页要重新构建（卡顿）
          action: OlGhostButton(label: '添加服务器', icon: 'plus', height: 28, fontSize: 10.5, onTap: () => context.push('/servers')),
        ),
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFF7FCFE), Color(0xFFF2FBF9)],
            ),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: p.line2),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(gradient: OlTokens.gradientBrand, borderRadius: BorderRadius.circular(11)),
                child: const Center(child: OlIcon('server', size: 18, color: Colors.white)),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            profile?.displayHost ?? '未连接',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: p.ink),
                          ),
                        ),
                        const SizedBox(width: 7),
                        OlBadge(
                          label: session.signedIn ? '已连接' : '未连接',
                          fg: session.signedIn ? OlTokens.okDeep : const Color(0xFFB47405),
                          bg: session.signedIn ? const Color(0xFFE7FBF5) : const Color(0xFFFFF6E5),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        profile?.username ?? '—',
                        session.user?.role == 3 ? '管理员' : '普通用户',
                        if (AppInfo.hasMeaningfulVersion(profile?.version ?? session.site?.version))
                          AppInfo.shortVersion(profile?.version ?? session.site?.version),
                        if (session.latencyMs != null) '${session.latencyMs} ms',
                        '${servers.length} 个服务器',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 9.5, color: p.ink4),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              OlGhostButton(label: '管理', height: 26, fontSize: 10, onTap: () => context.push('/servers')),
            ],
          ),
        ),
        _GroupLabel('已保存的服务器'),
        _Card(
          child: Column(
            children: [
              if (servers.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text('还没有服务器，点右上角「添加服务器」', style: TextStyle(fontSize: 10.5, color: p.ink4)),
                ),
              for (var i = 0; i < servers.length; i++)
                _Row(
                  icon: 'server',
                  title: servers[i].name,
                  subtitle: servers[i].baseUrl,
                  trailing: Text(
                    servers[i].id == profile?.id ? '当前' : '切换',
                    style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: servers[i].id == profile?.id ? OlTokens.sky700 : p.ink4),
                  ),
                  onTap: () => context.go('/servers/edit/${servers[i].id}'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        _InfoStrip(text: '管理后台（只读）：客户端只调用 /api/admin/storage/list；创建、用户与索引在浏览器完成。'),
      ],
    );
  }
}

class _InfoStrip extends StatelessWidget {
  final String text;
  const _InfoStrip({required this.text});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: p.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.line2),
      ),
      child: Row(
        children: [
          const OlIcon('info', size: 14, color: OlTokens.sky600),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 9.5, height: 1.6, color: p.ink3))),
        ],
      ),
    );
  }
}
