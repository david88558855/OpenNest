part of '../files_page.dart';

// ---------------------------------------------------------------------------
// 左侧栏：存储源 + 底部动作（对齐效果图 D3）
// ---------------------------------------------------------------------------
class _Sidebar extends ConsumerWidget {
  const _Sidebar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final sources = ref.watch(sourcesProvider).valueOrNull ?? const <StorageSource>[];
    final transfers = ref.watch(transfersProvider);
    final currentPath = ref.watch(filesProvider).path;

    return Container(
      width: 236,
      decoration: BoxDecoration(
        // 0.5.0：侧栏与主区背景互换 —— 侧栏改白底，主区改浅蓝灰。
        // 与设置页 D8 的结构保持一致（导航白、内容区 #F8FBFE）。
        color: p.card,
        border: Border(right: BorderSide(color: p.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(10, 14, 10, 8),
              children: [
                _SideLabel(text: '存储源'),
                if (sources.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
                    child: Text('还没有存储源', style: TextStyle(fontSize: 10.5, color: p.ink4)),
                  ),
                for (final source in sources)
                  _SourceRow(
                    source: source,
                    active: currentPath == source.mountPath || currentPath.startsWith('${source.mountPath}/'),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => context.push('/sources/add'),
                    borderRadius: BorderRadius.circular(9),
                    child: Container(
                      height: 34,
                      decoration: BoxDecoration(
                        color: p.card,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: const Color(0xFFBDE7FA), style: BorderStyle.solid),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          OlIcon('plus', size: 12, color: OlTokens.sky600),
                          SizedBox(width: 6),
                          Text(
                            '添加存储源',
                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF08799F)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _SideAction(
                        icon: 'download',
                        label: '传输',
                        badge: transfers.pendingCount,
                        onTap: () => context.go('/transfers'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _SideAction(
                        icon: 'settings',
                        label: '设置',
                        onTap: () => context.go('/settings'),
                      ),
                    ),
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

class _SideLabel extends StatelessWidget {
  final String text;
  const _SideLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          color: context.ol.ink4,
        ),
      ),
    );
  }
}

class _SourceRow extends ConsumerWidget {
  final StorageSource source;
  final bool active;

  const _SourceRow({required this.source, required this.active});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    // 只订阅「本源」的状态：别的源变化不会重建这一行。
    final health = ref.watch(storageHealthProvider.select((all) => all[source.id]));
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: () => context.go('/files?path=${Uri.encodeComponent(source.mountPath)}'),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
            decoration: BoxDecoration(
              color: active ? p.card : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              // 常驻 1px 描边：选中/悬停时不会因为多出边框而跳动
              border: Border.all(color: active ? const Color(0xFFBDE7FA) : Colors.transparent),
            ),
            child: Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: source.disabled ? p.chipBg : const Color(0xFFEAF8FE),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Center(
                    child: OlIcon(
                      source.driver == 'Local' ? 'hard-drive' : 'cloud',
                      size: 13,
                      color: source.disabled ? p.ink4 : OlTokens.sky600,
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    source.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      color: active ? p.ink : p.ink2,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // 连接状态（正常 / 断开 / 停用），替换原来的驱动短标签。
                _SourceStatusTag(source: source, health: health),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 存储源的实时连接状态：正常（绿）/ 断开（红）/ 停用（灰）。
///
/// 数据来自 [storageHealthProvider]：25 秒轮询 + 90 秒逐源真探测 + 列目录
/// 成功/失败的即时回写，所以这里反映的是「此刻连不连得上」，不是驱动名。
///
/// 布局稳定：固定 [width] 宽、右对齐，三种文案都在同一格里换字，
/// 不会让行内其它元素跳动；也没加任何动画，切换是瞬时换字换色。
class _SourceStatusTag extends StatelessWidget {
  final StorageSource source;
  final StorageHealth? health;

  const _SourceStatusTag({required this.source, required this.health});

  static const double width = 26;

  @override
  Widget build(BuildContext context) {
    final state = _ConnectionState.of(context, source, health);
    return Tooltip(
      message: state.detail,
      waitDuration: const Duration(milliseconds: 500),
      child: SizedBox(
        width: width,
        child: Text(
          state.label,
          textAlign: TextAlign.right,
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: TextStyle(
            fontSize: 9.5,
            height: 1.1,
            fontWeight: FontWeight.w800,
            color: state.fg,
          ),
        ),
      ),
    );
  }
}

/// 胶囊版连接状态：移动端抽屉与标题栏用（沿用它们原来的胶囊样式）。
class _ConnectionStatusPill extends StatelessWidget {
  final StorageSource source;
  final StorageHealth? health;

  const _ConnectionStatusPill({required this.source, required this.health});

  @override
  Widget build(BuildContext context) {
    final state = _ConnectionState.of(context, source, health);
    return Tooltip(
      message: state.detail,
      waitDuration: const Duration(milliseconds: 500),
      child: Container(
        // 固定最小宽度：「—」与「正常/断开/停用」宽度一致，切换不跳。
        constraints: const BoxConstraints(minWidth: 34),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: state.bg,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(
          state.label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: state.pillFg),
        ),
      ),
    );
  }
}

/// 连接状态的统一取值：文案 / 颜色 / 悬停说明。
///
/// 桌面侧栏（纯文字）与移动端抽屉、标题栏（胶囊）共用这一份判定 ——
/// 三处各判一遍很容易出现「同一状态文案或颜色不一致」。
class _ConnectionState {
  final String label;

  /// 纯文字场景的前景色。
  final Color fg;

  /// 胶囊场景的前景色（浅色底上要更深才够对比）。
  final Color pillFg;

  /// 胶囊底色。
  final Color bg;

  final String detail;

  const _ConnectionState({
    required this.label,
    required this.fg,
    required this.pillFg,
    required this.bg,
    required this.detail,
  });

  factory _ConnectionState.of(
    BuildContext context,
    StorageSource source,
    StorageHealth? health,
  ) {
    final p = context.ol;
    if (source.disabled) {
      return _ConnectionState(
        label: '停用',
        fg: p.ink4,
        pillFg: p.ink4,
        bg: p.chipBg,
        detail: '该存储源已在设置里停用',
      );
    }
    if (health == null) {
      // 还没探测到结论（引擎刚起来的一两秒）：占位符，宽度不变，不会闪。
      return _ConnectionState(
        label: '—',
        fg: p.ink4,
        pillFg: p.ink4,
        bg: p.chipBg,
        detail: '正在检测连接状态…',
      );
    }
    if (health.online) {
      return _ConnectionState(
        label: '正常',
        fg: OlTokens.ok,
        pillFg: const Color(0xFF0B6B4A),
        bg: const Color(0xFFD3F2E6),
        detail: '已连接'
            '${health.latencyMs > 0 ? ' · 响应 ${health.latencyMs}ms' : ''}'
            ' · ${_ago(health.checkedAt)}检测',
      );
    }
    final reason = health.message;
    return _ConnectionState(
      label: '断开',
      fg: OlTokens.dangerDeep,
      pillFg: OlTokens.dangerDeep,
      bg: const Color(0xFFFDE8EC),
      detail: '无法连接该存储源'
          '${reason == null || reason.isEmpty ? '' : '：$reason'}',
    );
  }

  static String _ago(DateTime at) {
    final diff = DateTime.now().difference(at);
    if (diff.inSeconds < 15) return '刚刚';
    if (diff.inMinutes < 1) return '${diff.inSeconds} 秒前';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    return '${diff.inHours} 小时前';
  }
}

class _SideAction extends StatelessWidget {
  final String icon;
  final String label;
  final int badge;
  final VoidCallback onTap;

  const _SideAction({required this.icon, required this.label, required this.onTap, this.badge = 0});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          height: 34,
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: p.line),
          ),
          child: Stack(
            children: [
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OlIcon(icon, size: 13, color: p.ink2),
                    const SizedBox(width: 5),
                    Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: p.ink2)),
                  ],
                ),
              ),
              if (badge > 0)
                Positioned(
                  right: 4,
                  top: -1,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: OlTokens.sky600,
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: p.surface, width: 1.5),
                    ),
                    child: Text(
                      '$badge',
                      style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
