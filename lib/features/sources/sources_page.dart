import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/frame.dart';
import '../../app/providers.dart';
import '../../core/i18n/zh.dart';
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
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 0.5.0：该页只被 push 进来（设置 / 引擎状态），此前两端都没有返回入口。
                      Padding(
                        padding: const EdgeInsets.only(top: 2, right: 12),
                        child: OlBackButton(onTap: () => goBackOrFiles(context)),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 设计稿 D8：标题 19/800 + 副标题 11.5。
                            Text('存储源管理', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: p.ink)),
                            const SizedBox(height: 4),
                            Text(
                              '所有连接配置本地保存 · 密码与令牌仅存系统钥匙串 · 导出内容不含任何凭据',
                              style: TextStyle(fontSize: 11.5, color: p.ink3),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  // 设计稿 D8 `.toolbar`：主按钮 + 右侧两个幽灵按钮。
                  Row(
                    children: [
                      OlPrimaryButton(
                        label: '添加存储源',
                        icon: 'plus',
                        height: 32,
                        fontSize: 12,
                        horizontalPadding: 14,
                        onTap: () => context.push('/sources/add'),
                      ),
                      const Spacer(),
                    ],
                  ),
                  const SizedBox(height: 14),
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
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
                    children: [
                      _SourceTable(sources: items),
                      const SizedBox(height: 16),
                      // 设计稿 D8 `.dd`：数据目录 + 凭据说明双卡。
                      const _DataAndCredentialsRow(),
                    ],
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

/// 存储源表格（设计稿 D8 `.card` + `.thead` + `.trow`）。
///
/// 列：图标 / 名称+副标题 / 状态点+文案 / 挂载路径 / 操作。
/// 稿面的第 4 列是「最近使用」，本项目没有这个数据源，改为挂载路径。
class _SourceTable extends ConsumerWidget {
  final List<StorageSource> sources;

  const _SourceTable({required this.sources});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    return Container(
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // 表头（设计稿 `.thead`）：底 #F8FBFE、10.5/800 #9DB2C4。
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: p.surface,
              border: Border(bottom: BorderSide(color: p.line)),
            ),
            child: Row(
              children: [
                const SizedBox(width: 44),
                Expanded(
                  child: Text('名称 / 协议', style: _headStyle),
                ),
                SizedBox(
                  width: 130,
                  child: Text('状态', style: _headStyle),
                ),
                SizedBox(
                  width: 120,
                  child: Text('挂载路径', style: _headStyle),
                ),
                SizedBox(
                  width: 150,
                  child: Text('操作', style: _headStyle, textAlign: TextAlign.right),
                ),
              ],
            ),
          ),
          for (final source in sources) _SourceTableRow(source: source),
        ],
      ),
    );
  }

  static const _headStyle = TextStyle(
    fontSize: 10.5,
    fontWeight: FontWeight.w800,
    color: Color(0xFF9DB2C4),
    letterSpacing: 0.6,
  );
}

/// 表格行（设计稿 `.trow`）：57 高、最后一行无边线。
class _SourceTableRow extends ConsumerWidget {
  final StorageSource source;

  const _SourceTableRow({required this.source});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final actions = ref.read(sourceActionsProvider);
    final tag = driverShortTag(source.driver);
    final healthy = !source.disabled && source.isHealthy;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.line2)),
      ),
      child: Row(
        children: [
          // 图标块 32×32 r9（设计稿 `.s-ic`）
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: source.disabled ? p.chipBg : OlTokens.tileSky,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Center(
              child: OlIcon(
                source.driver == 'Local' ? 'hard-drive' : 'cloud',
                size: 16,
                color: source.disabled ? p.ink4 : OlTokens.sky600,
                strokeWidth: 1.9,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // 名称 + 副标题
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  source.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: p.ink),
                ),
                const SizedBox(height: 2),
                Text(
                  tag,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5, color: p.ink4),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // 状态点 + 文案
          SizedBox(
            width: 130,
            child: Row(
              children: [
                OlDot(
                  color: source.disabled
                      ? const Color(0xFFD92D4B)
                      : (healthy ? const Color(0xFF0E9F6E) : const Color(0xFFF9C25B)),
                  size: 7,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    source.disabled
                        ? '已停用'
                        : (healthy ? '已连接' : storageStatusLabel(source.status)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: p.ink2),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 120,
            child: Text(
              source.mountPath,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: p.ink3),
            ),
          ),
          const SizedBox(width: 12),
          // 操作列
          SizedBox(
            width: 150,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _TableAction(
                  icon: source.disabled ? 'play' : 'pause',
                  tooltip: source.disabled ? '启用' : '停用',
                  onTap: () async {
                    final error = await actions.toggle(source);
                    if (!context.mounted) return;
                    if (error != null) olToast(context, error, error: true);
                  },
                ),
                const SizedBox(width: 6),
                _TableAction(
                  icon: 'trash',
                  tooltip: '删除',
                  danger: true,
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
          ),
        ],
      ),
    );
  }
}

/// 表格内的操作按钮（设计稿 `.ia`）：28×28、圆角 8、描边。
class _TableAction extends StatelessWidget {
  final String icon;
  final String tooltip;
  final bool danger;
  final VoidCallback onTap;

  const _TableAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: p.card,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: p.line),
            ),
            child: Center(
              child: OlIcon(
                icon,
                size: 13,
                color: danger ? const Color(0xFFD92D4B) : p.ink2,
                strokeWidth: 2,
              ),
            ),
          ),
        ),
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


/// 数据目录与凭据说明（设计稿 D8 `.dd` 两张 `.dcard`）。
///
/// 0.5.0：按需求**不实现**「清除所有凭据」——引擎的 admin 口令是首次初始化
/// 就写死的，清掉之后本机将无法再登录自己的引擎，且无法从 UI 恢复。
/// 这里只保留说明与目录定位。
class _DataAndCredentialsRow extends ConsumerWidget {
  const _DataAndCredentialsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final dir = ref.watch(prefsProvider).storagePath;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _DataCard(
            icon: 'download',
            iconColor: const Color(0xFF0EA5E9),
            title: '数据目录',
            description: '内嵌服务端数据库、传输临时文件与日志均存放于此；迁移时整体拷贝即可。',
            path: dir,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _DataCard(
            icon: 'lock',
            iconColor: const Color(0xFF0E9F6E),
            title: '凭据管理',
            description: '所有密码与令牌保存在系统钥匙串，只在本机使用，永不上传。',
          ),
        ),
      ],
    );
  }
}

/// 单张数据卡（设计稿 `.dcard`）：r14、padding 16。
class _DataCard extends StatelessWidget {
  final String icon;
  final Color iconColor;
  final String title;
  final String description;
  final String? path;

  const _DataCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
    this.path,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              OlIcon(icon, size: 15, color: iconColor, strokeWidth: 1.9),
              const SizedBox(width: 8),
              Text(title, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: p.ink)),
            ],
          ),
          const SizedBox(height: 6),
          Text(description, style: TextStyle(fontSize: 11, height: 1.6, color: p.ink3)),
          if (path != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: p.surface,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: p.line),
              ),
              child: Text(
                path!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10.5, color: p.ink2),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
