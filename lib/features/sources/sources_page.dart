import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/frame.dart';
import '../../core/models/storage_source.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/ol_controls.dart';
import '../../core/widgets/ol_dialogs.dart';
import '../../core/widgets/ol_icon.dart';
import 'sources_controller.dart';

/// 存储源管理：引擎侧挂载的全部源、状态与运维动作。
class SourcesPage extends ConsumerWidget {
  const SourcesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final sources = ref.watch(sourcesProvider);

    return AppFrame(
      showNav: false,
      handleBack: true,
      child: ColoredBox(
        color: p.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('存储源', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: p.ink)),
                        const SizedBox(height: 4),
                        Text(
                          '添加本地目录、网络存储或网盘，全部在本机引擎上直连',
                          style: TextStyle(fontSize: 11.5, color: p.ink3),
                        ),
                      ],
                    ),
                  ),
                  OlPrimaryButton(
                    label: '添加存储源',
                    icon: 'plus',
                    height: 34,
                    onTap: () => context.push('/sources/add'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: sources.when(
                loading: () => const Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: OlTokens.sky600),
                  ),
                ),
                error: (error, _) => _Message(text: '读取失败：$error'),
                data: (items) {
                  if (items.isEmpty) {
                    return _Empty(onAdd: () => context.push('/sources/add'));
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
                    itemCount: items.length,
                    separatorBuilder: (context, index) => Divider(height: 1, color: p.line2),
                    itemBuilder: (context, index) => _SourceRow(source: items[index]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceRow extends ConsumerWidget {
  final StorageSource source;

  const _SourceRow({required this.source});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final actions = ref.read(sourceActionsProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: source.disabled ? p.chipBg : const Color(0xFFEAF8FE),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: OlIcon(
                source.driver == 'Local' ? 'hard-drive' : 'cloud',
                size: 16,
                color: source.disabled ? p.ink4 : OlTokens.sky600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        source.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.ink),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OlBadge(
                      label: source.driver,
                      fg: const Color(0xFF075E7E),
                      bg: const Color(0xFFEAF8FE),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${source.mountPath}  ·  ${source.disabled ? '已停用' : (source.isHealthy ? '已连接' : (source.status.isEmpty ? '待加载' : source.status))}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5, color: p.ink3),
                ),
              ],
            ),
          ),
          OlGhostButton(
            label: source.disabled ? '启用' : '停用',
            height: 30,
            fontSize: 10.5,
            onTap: () async {
              final error = await actions.toggle(source);
              if (!context.mounted) return;
              if (error != null) olToast(context, error, error: true);
            },
          ),
          const SizedBox(width: 8),
          OlGhostButton(
            label: '删除',
            height: 30,
            fontSize: 10.5,
            onTap: () async {
              final ok = await olConfirm(
                context,
                title: '删除存储源',
                message: '将从引擎移除「${source.displayName}」，不影响远端文件。',
                confirm: '删除',
                danger: true,
              );
              if (!ok) return;
              final error = await actions.remove(source);
              if (!context.mounted) return;
              if (error != null) olToast(context, error, error: true);
            },
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final VoidCallback onAdd;

  const _Empty({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: OlEmptyState(
        icon: 'folder-plus',
        title: '还没有存储源',
        subtitle: '添加一个本地目录或网络存储，就能开始管理文件',
        action: OlPrimaryButton(label: '添加存储源', icon: 'plus', height: 36, onTap: onAdd),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final String text;

  const _Message({required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(text, style: TextStyle(fontSize: 11.5, color: context.ol.ink3)),
    );
  }
}
