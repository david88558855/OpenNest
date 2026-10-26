part of '../settings_page.dart';

/// 存储源管理分区（设计稿 D8 主区 `.main`）。
///
/// 设计稿里存储源是**设置内的一个分区**，不是独立页面：左侧导航第 2 项
/// 「存储源」带数量徽标，右侧主区依次是标题、副标题、工具栏、源列表表格、
/// 数据与凭据双卡。
///
/// 与旧版独立页（`/sources`）的差异：
/// - 不再自带侧栏与返回按钮（设置框架已经提供了）
/// - 工具栏补齐「导入配置 / 导出配置」
/// - 表格第 4 列是「最近使用」（按源记录的最后打开时间）
/// - 操作列是「测试 / 编辑 / 删除」三键
class _SourcesSection extends ConsumerWidget {
  const _SourcesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final sources = ref.watch(sourcesProvider);

    // 0.5.0：设置主区是 SingleChildScrollView（无界高度），这里**不能**用
    // Expanded —— 会抛 unbounded height。改成整体 Column，列表区自己滚动。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 设计稿 D8 `.h1` + `.sub`
        const _SectionHead(
          title: '存储源管理',
          subtitle: '所有连接配置本地保存 · 密码与令牌仅存系统钥匙串 · 导出内容不含任何凭据',
        ),
        const SizedBox(height: 18),
        // 设计稿 D8 `.toolbar`：左侧主按钮 + 右侧两个幽灵按钮。
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
            OlGhostButton(
              label: '导入配置',
              icon: 'download',
              height: 32,
              fontSize: 12,
              horizontalPadding: 14,
              onTap: () => _importConfig(context, ref),
            ),
            const SizedBox(width: 8),
            OlGhostButton(
              label: '导出配置',
              icon: 'upload',
              height: 32,
              fontSize: 12,
              horizontalPadding: 14,
              onTap: () => _exportConfig(context, ref),
            ),
          ],
        ),
        const SizedBox(height: 14),
        sources.when(
            loading: () => const SizedBox(
              height: 200,
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: OlTokens.sky600),
                ),
              ),
            ),
            error: (error, _) => SizedBox(
              height: 200,
              child: Center(
                child: Text('读取失败：$error', style: TextStyle(fontSize: 11.5, color: p.ink3)),
              ),
            ),
            data: (items) {
              if (items.isEmpty) {
                // 滚动容器里的 Center 会塌成零高（内容贴顶），给一个明确高度
                // 让空态落在视觉舒适的位置。
                return SizedBox(
                  height: 260,
                  child: Center(
                    child: OlEmptyState(
                      icon: 'folder-plus',
                      title: '还没有存储源',
                      subtitle: '添加一个本地目录或网络存储，就能开始管理文件',
                      action: OlPrimaryButton(
                        label: '添加存储源',
                        icon: 'plus',
                        height: 36,
                        onTap: () => context.push('/sources/add'),
                      ),
                    ),
                  ),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SourceTable(sources: items),
                  const SizedBox(height: 16),
                  // 设计稿 D8 `.dd`：数据目录 + 凭据说明双卡。
                  const _DataAndCredentialsRow(),
                ],
              );
            },
          ),
      ],
    );
  }

  /// 导出：把当前全部存储源写成 JSON（不含任何密码 / 令牌）。
  Future<void> _exportConfig(BuildContext context, WidgetRef ref) async {
    final items = ref.read(sourcesProvider).valueOrNull ?? const <StorageSource>[];
    if (items.isEmpty) {
      olToast(context, '没有可导出的存储源');
      return;
    }
    final bundle = SourceConfigBundle(items);
    // 优先让用户选保存位置；取消则回落到数据目录（保证功能可用）。
    final path = await FilePicker.platform.saveFile(
      dialogTitle: '导出存储源配置',
      fileName: SourceConfigBundle.defaultFileName(),
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    String? written;
    if (path != null) {
      written = await bundle.exportTo(path);
    } else {
      written = await bundle.exportToDataDir();
    }
    if (!context.mounted) return;
    if (written == null) {
      olToast(context, '导出失败', error: true);
      return;
    }
    olToast(context, '已导出 ${items.length} 个存储源（不含密码）：$written');
  }

  /// 导入：读 JSON 并逐条创建。
  Future<void> _importConfig(BuildContext context, WidgetRef ref) async {
    final bundle = await SourceConfigBundle.pickAndParse();
    if (!context.mounted) return;
    if (bundle == null) return; // 用户取消或文件格式不对
    if (bundle.sources.isEmpty) {
      olToast(context, '配置文件里没有存储源', error: true);
      return;
    }

    final actions = ref.read(sourceActionsProvider);
    final created = <String>[];
    final failed = <String>[];
    for (final source in bundle.sources) {
      if (!context.mounted) return;
      // 挂载路径由客户端生成（与添加向导一致），导入时重新分配，避免与现有源冲突。
      final prepared = source.copyWith(mountPath: generateMountPath());
      final error = await actions.create(prepared);
      if (error == null) {
        created.add(prepared.displayName);
      } else {
        failed.add('${prepared.displayName}：$error');
      }
    }
    if (!context.mounted) return;
    ref.invalidate(sourcesProvider);

    // 导入结果逐条反馈：成功多少、失败多少、失败原因。
    final message = StringBuffer();
    if (created.isNotEmpty) message.write('成功导入 ${created.length} 个');
    if (failed.isNotEmpty) {
      if (message.isNotEmpty) message.write('；');
      message.write('${failed.length} 个失败（${failed.first}）');
    }
    olToast(context, message.toString(), error: failed.isNotEmpty);
  }
}

/// 源列表表格（设计稿 D8 `.card` + `.thead` + `.trow`）。
///
/// 列：图标 44 / 名称·协议 / 状态 130 / 最近使用 120 / 操作 150。
class _SourceTable extends ConsumerWidget {
  final List<StorageSource> sources;

  const _SourceTable({required this.sources});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    // 最近使用：按源记的最后打开时间。
    final usage = ref.watch(sourceUsageProvider).valueOrNull ?? const <String, int>{};
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
                Expanded(child: Text('名称 / 协议', style: _headStyle)),
                SizedBox(width: 130, child: Text('状态', style: _headStyle)),
                SizedBox(width: 120, child: Text('最近使用', style: _headStyle)),
                SizedBox(width: 150, child: Text('操作', style: _headStyle, textAlign: TextAlign.right)),
              ],
            ),
          ),
          for (final source in sources)
            _SourceTableRow(source: source, lastUsed: usage[source.mountPath]),
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

/// 表格行（设计稿 `.trow`）。
class _SourceTableRow extends ConsumerStatefulWidget {
  final StorageSource source;
  final int? lastUsed;

  const _SourceTableRow({required this.source, this.lastUsed});

  @override
  ConsumerState<_SourceTableRow> createState() => _SourceTableRowState();
}

class _SourceTableRowState extends ConsumerState<_SourceTableRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    final actions = ref.read(sourceActionsProvider);
    final source = widget.source;
    final tag = driverShortTag(source.driver);
    final status = _statusOf(source);

    return MouseRegion(
      // 设计稿 D8 `.trow:hover`：底色变 #FBFDFF。
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _hover ? const Color(0xFFFBFDFF) : Colors.transparent,
        border: Border(bottom: BorderSide(color: p.line2)),
      ),
      child: Row(
        children: [
          // 图标块 32×32 r9（设计稿 `.s-ic`）：按协议族取底色与图标色。
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: source.disabled ? p.chipBg : _tileBg(source.driver),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Center(
              child: OlIcon(
                source.driver == 'Local' ? 'hard-drive' : 'cloud',
                size: 16,
                color: source.disabled ? p.ink4 : _tileFg(source.driver),
                strokeWidth: 1.9,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // 名称 + 副标题（协议）
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
          // 状态点 + 文案（设计稿 `.st`）
          SizedBox(
            width: 130,
            child: Row(
              children: [
                OlDot(color: status.color, size: 7),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    status.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: p.ink2),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // 最近使用
          SizedBox(
            width: 120,
            child: Text(
              _lastUsedLabel(widget.lastUsed),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: p.ink3),
            ),
          ),
          const SizedBox(width: 12),
          // 操作列：测试 / 编辑 / 删除
          SizedBox(
            width: 150,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _TableAction(
                  icon: 'refresh',
                  tooltip: '测试连接',
                  onTap: () async {
                    final error = await actions.test(source);
                    if (!context.mounted) return;
                    olToast(context, error ?? '连接正常', error: error != null);
                  },
                ),
                const SizedBox(width: 6),
                _TableAction(
                  // 设计稿 D8 的编辑键是铅笔（`edit`），不是三点。
                  icon: 'edit',
                  tooltip: '编辑',
                  onTap: () => _editSource(context, ref, source),
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
                    if (error != null) {
                      olToast(context, error, error: true);
                      return;
                    }
                    olToast(context, '已删除「${source.displayName}」');
                  },
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  /// 状态映射：绿=已连接、黄=令牌将过期 / 待加载、红=离线或已停用。
  static _SourceStatus _statusOf(StorageSource source) {
    if (source.disabled) {
      return const _SourceStatus('已停用', Color(0xFFD92D4B));
    }
    if (source.isHealthy) {
      return const _SourceStatus('已连接', Color(0xFF0E9F6E));
    }
    final raw = source.status.toLowerCase();
    // 引擎报的令牌类错误映射成「令牌将过期」（设计稿的黄色预警态）。
    if (raw.contains('token') || raw.contains('expire') || raw.contains('unauthorized')) {
      return const _SourceStatus('令牌将过期', Color(0xFFF9C25B));
    }
    if (raw.isEmpty) {
      return const _SourceStatus('待加载', Color(0xFFF9C25B));
    }
    return const _SourceStatus('离线（只读缓存）', Color(0xFFD92D4B));
  }

  /// 「最近使用」的相对时间文案。
  static String _lastUsedLabel(int? lastUsed) {
    if (lastUsed == null || lastUsed <= 0) return '从未使用';
    final at = DateTime.fromMillisecondsSinceEpoch(lastUsed);
    final diff = DateTime.now().difference(at);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    if (diff.inDays < 30) return '${diff.inDays} 天前';
    return '${at.year}-${at.month.toString().padLeft(2, '0')}-${at.day.toString().padLeft(2, '0')}';
  }

  /// 协议族的图标底色（与设计稿一致：本地/文件蓝、对象紫、网盘橙、远程绿）。
  static Color _tileBg(String driver) {
    switch (driverGroupOf(driver)) {
      case DriverGroup.local:
        return const Color(0xFFEAF8FE);
      case DriverGroup.object:
        return const Color(0xFFF0EDFF);
      case DriverGroup.cloud:
        return const Color(0xFFFFF6E8);
      case DriverGroup.server:
        return const Color(0xFFE8FBF3);
      case DriverGroup.other:
      default:
        return const Color(0xFFF1F6FB);
    }
  }

  static Color _tileFg(String driver) {
    switch (driverGroupOf(driver)) {
      case DriverGroup.local:
        return const Color(0xFF0EA5E9);
      case DriverGroup.object:
        return const Color(0xFF7C5CFC);
      case DriverGroup.cloud:
        return const Color(0xFFF97316);
      case DriverGroup.server:
        return const Color(0xFF0E9F6E);
      case DriverGroup.other:
      default:
        return const Color(0xFF6B7F94);
    }
  }

  /// 编辑存储源：名称、备注、缓存时长与启停。
  ///
  /// 凭据字段不在这里改 —— 驱动表单有几十个字段且各驱动不同，
  /// 凭据改动走「删除后重新添加」更安全（也避免把密码写进日志）。
  Future<void> _editSource(BuildContext context, WidgetRef ref, StorageSource source) async {
    final result = await showOlDialog<_SourceEditResult>(
      context: context,
      builder: (dialogContext) => _SourceEditDialog(source: source),
    );
    if (result == null) return;
    final actions = ref.read(sourceActionsProvider);
    final updated = source.copyWith(
      remark: result.remark,
      cacheExpiration: result.cacheExpiration,
      disabled: result.disabled,
    );
    final error = await actions.update(updated);
    if (!context.mounted) return;
    if (error != null) {
      olToast(context, error, error: true);
      return;
    }
    olToast(context, '已保存「${updated.displayName}」');
  }
}

/// 状态元组。
class _SourceStatus {
  final String label;
  final Color color;
  const _SourceStatus(this.label, this.color);
}

/// 编辑对话框的返回值。
class _SourceEditResult {
  final String remark;
  final int cacheExpiration;
  final bool disabled;
  const _SourceEditResult(this.remark, this.cacheExpiration, this.disabled);
}

/// 存储源编辑对话框。
class _SourceEditDialog extends StatefulWidget {
  final StorageSource source;
  const _SourceEditDialog({required this.source});

  @override
  State<_SourceEditDialog> createState() => _SourceEditDialogState();
}

class _SourceEditDialogState extends State<_SourceEditDialog> {
  late final TextEditingController _remark =
      TextEditingController(text: widget.source.remark);
  late final TextEditingController _cache =
      TextEditingController(text: '${widget.source.cacheExpiration}');
  late bool _disabled = widget.source.disabled;

  @override
  void dispose() {
    _remark.dispose();
    _cache.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 400,
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: p.line),
            boxShadow: const [
              BoxShadow(color: Color(0x1F0E3A46), blurRadius: 40, offset: Offset(0, 14)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  OlIcon('server', size: 16, color: p.ink2),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      '编辑存储源',
                      style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: p.ink),
                    ),
                  ),
                  OlIconButton(icon: 'x', size: 28, iconSize: 13, onTap: () => context.pop()),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${driverShortTag(widget.source.driver)} · ${widget.source.mountPath}',
                style: TextStyle(fontSize: 10.5, color: p.ink4),
              ),
              const SizedBox(height: 14),
              Text('备注', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: p.ink2)),
              const SizedBox(height: 6),
              OlField(controller: _remark, icon: 'server', hint: '显示名称（留空则用挂载路径）'),
              const SizedBox(height: 12),
              Text('缓存时长（分钟）', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: p.ink2)),
              const SizedBox(height: 6),
              OlField(controller: _cache, icon: 'clock', hint: '30', keyboardType: TextInputType.number),
              const SizedBox(height: 14),
              Row(
                children: [
                  OlIcon('eye', size: 14, color: p.ink3),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '停用此存储源',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.ink),
                    ),
                  ),
                  OlSwitch(value: _disabled, small: true, onChanged: (v) => setState(() => _disabled = v)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '凭据与路径参数请通过「删除后重新添加」修改，避免密码被写入日志。',
                style: TextStyle(fontSize: 10, height: 1.6, color: p.ink4),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OlGhostButton(label: '取消', height: 32, fontSize: 12, onTap: () => context.pop()),
                  const SizedBox(width: 8),
                  OlPrimaryButton(
                    label: '保存',
                    height: 32,
                    fontSize: 12,
                    onTap: () {
                      final cache = int.tryParse(_cache.text.trim()) ?? 30;
                      context.pop(
                        _SourceEditResult(_remark.text.trim(), cache.clamp(0, 100000), _disabled),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 表格内的操作按钮（设计稿 `.ia`）：28×28、圆角 8、描边。
class _TableAction extends StatefulWidget {
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
  State<_TableAction> createState() => _TableActionState();
}

class _TableActionState extends State<_TableAction> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    // 设计稿 D8 `.ia:hover`：描边变 #38BDF8、图标变 #0EA5E9。
    // 删除键悬停时保持红色语义（危险操作不该在悬停时变蓝）。
    final borderColor = _hover ? const Color(0xFF38BDF8) : p.line;
    final iconColor = widget.danger
        ? const Color(0xFFD92D4B)
        : (_hover ? const Color(0xFF0EA5E9) : p.ink2);
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: p.card,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: borderColor),
            ),
            child: Center(
              child: OlIcon(
                widget.icon,
                size: 13,
                color: iconColor,
                strokeWidth: 2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 数据目录与凭据说明（设计稿 D8 `.dd` 两张 `.dcard`）。
///
/// 0.5.0：设计稿此处原为「清除所有凭据…」，改为「查看内核密码…」。
/// 引擎的 admin 口令是首次初始化就写死的，清掉之后本机将无法再登录自己的
/// 引擎且无法从 UI 恢复；查看则没有任何副作用，且用户确实偶尔需要它。
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
            // 0.5.0：设计稿此处原为「清除所有凭据…」。引擎 admin 口令首次
            // 初始化即写死，清掉后本机将无法再登录自己的引擎且无法从 UI 恢复，
            // 因此改为「查看内核密码…」——明文展示当前实例实际使用的口令。
            action: OlGhostButton(
              label: '查看内核密码…',
              icon: 'key',
              height: 30,
              fontSize: 11,
              onTap: () => showEnginePasswordDialog(context, ref),
            ),
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
  final Widget? action;

  const _DataCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
    this.path,
    this.action,
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
          if (action != null) ...[
            const SizedBox(height: 10),
            action!,
          ],
        ],
      ),
    );
  }
}
