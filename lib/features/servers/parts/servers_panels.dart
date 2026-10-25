part of '../servers_page.dart';

// 桌面三块：列表头 / 筛选行 / 列表体 / 右侧详情面板（v1.0.49）

/// 标题 + 「添加服务器」。数量从 provider 读，避免调用方再传一遍。
class _ServerListHeader extends ConsumerWidget {
  final VoidCallback onAdd;
  const _ServerListHeader({required this.onAdd});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final count = ref.watch(serverListProvider).count;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('服务器管理', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: p.ink)),
              const SizedBox(height: 4),
              Text(
                '$count 个服务器 · 数量不限 · 配置与缓存按实例隔离',
                style: TextStyle(fontSize: 10.5, color: p.ink4),
              ),
            ],
          ),
        ),
        OlPrimaryButton(label: '添加服务器', icon: 'plus', onTap: onAdd),
      ],
    );
  }
}

/// 搜索框 + 全部/已连接/异常 三个筛选 + 当前实例标识。
class _ServerFilterBar extends ConsumerWidget {
  final TextEditingController controller;
  final String filter;
  final ValueChanged<String> onQuery;
  final ValueChanged<String> onFilter;

  const _ServerFilterBar({
    required this.controller,
    required this.filter,
    required this.onQuery,
    required this.onFilter,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(serverListProvider);
    final current = ref.watch(sessionProvider).profile;
    final okCount = state.servers.where((e) => e.health == ServerHealth.ok).length;
    return Row(
      children: [
        SizedBox(
          width: 196,
          child: OlField(
            controller: controller,
            icon: 'search',
            hint: '搜索名称或地址',
            dense: true,
            onChanged: onQuery,
          ),
        ),
        const SizedBox(width: 8),
        OlChip(label: '全部 ${state.count}', selected: filter == 'all', onTap: () => onFilter('all')),
        const SizedBox(width: 6),
        OlChip(label: '已连接 $okCount', selected: filter == 'ok', onTap: () => onFilter('ok')),
        const SizedBox(width: 6),
        OlChip(label: '异常 ${state.servers.length - okCount}', selected: filter == 'error', onTap: () => onFilter('error')),
        const Spacer(),
        if (current != null) OlChip(label: '当前：${current.name}', teal: true, icon: 'check'),
      ],
    );
  }
}

/// 服务器行列表（含底部说明）。删除 / 测试连接都在这里闭环，不再往页面壳回传。
class _ServerListBody extends ConsumerWidget {
  final List<ServerProfile> servers;
  final String? editingId;
  final ValueChanged<String> onSelect;
  final ValueChanged<ServerProfile> onSwitch;

  const _ServerListBody({
    required this.servers,
    required this.editingId,
    required this.onSelect,
    required this.onSwitch,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final activeId = ref.watch(serverListProvider).activeId;
    return ListView(
      children: [
        for (final server in servers)
          _ServerRow(
            server: server,
            current: server.id == activeId,
            selected: server.id == editingId,
            onSelect: () => onSelect(server.id),
            onSwitch: () => onSwitch(server),
            // v1.0.16：「编辑」打开独立编辑页（带返回）。
            onEdit: () => context.push('/servers/edit/${server.id}'),
            onDelete: () async {
              final confirmed = await olConfirm(
                context,
                title: '删除「${server.name}」',
                message: '只移除本地配置与凭据，不影响服务端数据。',
                confirm: '删除',
                danger: true,
              );
              if (!confirmed) return;
              final wasActive = activeId == server.id;
              await ref.read(serverListProvider.notifier).remove(server.id);
              if (wasActive) await ref.read(sessionProvider.notifier).retry();
              if (context.mounted) olToast(context, '已删除 ${server.name}');
            },
            onReconnect: () async {
              final result = await ref.read(sessionProvider.notifier).probe(server.baseUrl);
              if (!context.mounted) return;
              if (result.ok) {
                await ref.read(serverListProvider.notifier).touch(
                      server.id,
                      latencyMs: result.latencyMs,
                      health: ServerHealth.ok,
                      siteTitle: result.site?.title,
                      version: result.site?.version,
                    );
                if (context.mounted) olToast(context, '连接正常 · ${result.latencyMs} ms');
              } else {
                await ref.read(serverListProvider.notifier).touch(server.id, health: ServerHealth.timeout);
                if (context.mounted) olToast(context, result.error ?? '连接失败', error: true);
              }
            },
          ),
        const SizedBox(height: 6),
        Row(
          children: [
            const OlIcon('info', size: 10, color: Color(0xFFB2C1CF)),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                '列表保存在本地，凭据写入系统安全存储；删除服务器只移除本地配置，不影响服务端数据。',
                style: TextStyle(fontSize: 8.5, height: 1.6, color: p.ink4),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 右侧详情：新建表单 / 空态提示 / 编辑表单。
class _ServerDetailPanel extends StatelessWidget {
  final bool isNew;
  final ServerProfile? editing;
  final VoidCallback onClear;
  final VoidCallback onBackToNew;
  final VoidCallback onSaved;

  const _ServerDetailPanel({
    required this.isNew,
    required this.editing,
    required this.onClear,
    required this.onBackToNew,
    required this.onSaved,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Container(
      width: 316,
      decoration: BoxDecoration(
        color: p.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.line2),
      ),
      child: isNew
          ? ServerForm(profile: null, onClose: onClear, onSaved: onClear)
          : editing == null
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const OlIcon('server', size: 16, color: OlTokens.sky600),
                      const SizedBox(height: 8),
                      Text('选择左侧服务器进行编辑，或添加一个新的实例。', style: TextStyle(fontSize: 11, height: 1.7, color: p.ink3)),
                    ],
                  ),
                )
              : ServerForm(
                  profile: editing,
                  onClose: onBackToNew,
                  onSaved: onSaved,
                  onDeleted: onClear,
                ),
    );
  }
}
