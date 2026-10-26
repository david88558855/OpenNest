part of '../transfers_page.dart';

// 顶部条 / 速度卡 / 指标卡 / 任务列表（sliver）/ 任务行 / 空态
// ---------------------------------------------------------------------------
// 顶部条 / 速度卡 / 指标
// ---------------------------------------------------------------------------
/// 限速文案：任一方向有上限就显示具体值，两边都无限速显示「不限」。
String _limitLabel(int down, int up) {
  if (down <= 0 && up <= 0) return '不限';
  if (down > 0 && up > 0) {
    return '下载 ${formatLimitSpeed(down)} · 上传 ${formatLimitSpeed(up)}';
  }
  if (down > 0) return '下载 ${formatLimitSpeed(down)}';
  return '上传 ${formatLimitSpeed(up)}';
}

/// 工具栏（设计稿 D5b `.bar`）：左＝类型筛选，右＝汇总 + 全部暂停。
///
/// 0.5.0 把原来的「全局控制条」与「类型筛选行」合并成一行：
/// - 「并发 / 限速」搬到标题区副标题右侧（那是只读信息，不占这两行的位置）
/// - 左侧留给操作类型筛选（全部 / 下载 / 上传 / 复制 / 移动）
/// - 右侧只留「总计 + 全部暂停」，与左侧胶囊同高一行
class _QueueBar extends ConsumerWidget {
  /// 当前类型筛选，null = 全部。
  final TransferKind? kind;
  final ValueChanged<TransferKind?> onKind;

  const _QueueBar({required this.kind, required this.onKind});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final state = ref.watch(transfersProvider);
    final notifier = ref.read(transfersProvider.notifier);

    int countOf(TransferKind kind) => state.tasks.where((e) => e.kind == kind).length;

    // 汇总：全部任务的总字节，以及按当前速度估算的剩余时间。
    var totalBytes = 0;
    var remaining = 0;
    for (final task in state.tasks) {
      totalBytes += task.total;
      if (task.status != TransferStatus.done) remaining += (task.total - task.done);
    }
    final speed = state.downSpeed + state.upSpeed;
    final eta = speed > 0 ? (remaining / speed).round() : 0;

    final chips = <(TransferKind?, String, int)>[
      (null, '全部', state.tasks.length),
      (TransferKind.download, '下载', countOf(TransferKind.download)),
      (TransferKind.upload, '上传', countOf(TransferKind.upload)),
      (TransferKind.copy, '复制', countOf(TransferKind.copy)),
      (TransferKind.move, '移动', countOf(TransferKind.move)),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.transparent,
        border: Border(bottom: BorderSide(color: p.line)),
      ),
      child: Row(
        children: [
          for (final chip in chips) ...[
            _TypeChip(
              label: chip.$2,
              count: chip.$3,
              selected: kind == chip.$1,
              onTap: () => onKind(chip.$1),
            ),
            const SizedBox(width: 7),
          ],
          const Spacer(),
          Text(
            totalBytes <= 0 ? '暂无任务' : '总计 ${formatBytes(totalBytes)} · 剩余约 ${formatCountdown(eta)}',
            style: TextStyle(fontSize: 11.5, color: p.ink3),
          ),
          const SizedBox(width: 10),
          OlGhostButton(
            label: state.pausedGlobally ? '全部继续' : '全部暂停',
            icon: state.pausedGlobally ? 'play' : 'pause',
            height: 32,
            fontSize: 12,
            horizontalPadding: 14,
            fgColor: p.ink,
            onTap: () {
              if (state.pausedGlobally) {
                notifier.resumeAll();
              } else {
                notifier.pauseAll();
              }
            },
          ),
        ],
      ),
    );
  }
}

/// 类型筛选胶囊：26 高、圆角 99；选中浅蓝底 + 蓝字，计数徽标反白。
class _TypeChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _TypeChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFEAF8FE) : p.card,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: selected ? const Color(0xFFBDE7FA) : p.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: selected ? const Color(0xFF08799F) : p.ink2,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: selected ? p.card : const Color(0xFFEDF2F8),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: selected ? const Color(0xFF08799F) : const Color(0xFF6B7F94),
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

/// 任务分组标题（设计稿 D5 `.grp-t`）。
class _GroupTitle extends StatelessWidget {
  final String text;

  const _GroupTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: const Color(0xFF9DB2C4),
          letterSpacing: 1,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 任务列表（sliver 版：按需构建任务行，v1.0.30）
// ---------------------------------------------------------------------------
/// 任务列表（设计稿 D5b）：按**操作类型**分组（下载中 / 上传中 / 复制中 / 移动中），
/// 每行 64 高紧凑卡；空组自动不显示。
class _TaskListSliver extends StatelessWidget {
  final List<TransferTask> tasks;
  final _Filter filter;
  final ValueChanged<_Filter> onFilter;

  /// 历史任务数：仅用于「进行中为空但历史里有内容」时给出跳转引导。
  /// 服务端复制 / 移动是秒级完成的，不提示的话用户会以为没入队。
  final int doneCount;
  final int failedCount;

  const _TaskListSliver({
    required this.tasks,
    required this.filter,
    required this.onFilter,
    this.doneCount = 0,
    this.failedCount = 0,
  });

  static const Map<TransferKind, String> _groupTitles = {
    TransferKind.download: '下载中',
    TransferKind.upload: '上传中',
    TransferKind.copy: '复制中',
    TransferKind.move: '移动中',
  };

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) {
      // 「进行中」为空但历史里有任务：给一个跳转。复制 / 移动在服务端是秒级
      // 完成的，用户切到传输页时任务往往已经 done —— 不给引导会被当成「没入队」。
      final historyHint = filter == _Filter.active && (doneCount > 0 || failedCount > 0);
      return SliverToBoxAdapter(
        child: SizedBox(
          height: 260,
          child: _EmptyTransfers(
            icon: switch (filter) {
              _Filter.failed => 'alert',
              _Filter.done => 'check',
              _ => 'arrow-down',
            },
            iconColor: filter == _Filter.failed ? OlTokens.danger : null,
            title: switch (filter) {
              _Filter.failed => '没有失败的任务',
              _Filter.done => '还没有已完成的任务',
              _Filter.offline => '没有离线下载任务',
              _Filter.download => '没有下载任务',
              _Filter.upload => '没有上传任务',
              _ => '没有进行中的任务',
            },
            subtitle: historyHint
                ? '最近已完成 $doneCount 个${failedCount > 0 ? '，失败 $failedCount 个' : ''}'
                : null,
            action: historyHint
                ? OlGhostButton(
                    label: failedCount > 0 ? '查看失败任务' : '查看已完成',
                    icon: failedCount > 0 ? 'alert' : 'check',
                    height: 28,
                    fontSize: 11,
                    horizontalPadding: 12,
                    onTap: () => onFilter(failedCount > 0 ? _Filter.failed : _Filter.done),
                  )
                : null,
          ),
        ),
      );
    }

    // 按类型分组，并展平成「[标题, 行, 行, 标题, 行…]」。
    // 分组只在 build 里算一次，不再像原来那样在每个 item 的 builder 里重算。
    final groups = <TransferKind, List<TransferTask>>{};
    for (final task in tasks) {
      groups.putIfAbsent(task.kind, () => <TransferTask>[]).add(task);
    }
    final flat = <Object>[];
    for (final kind in TransferKind.values) {
      final list = groups[kind];
      if (list == null || list.isEmpty) continue;
      flat.add(_GroupTitle(_groupTitles[kind]!));
      flat.addAll(list);
    }

    return SliverPadding(
      // 设计稿 D5 `.tasks`：padding 8/24/16。
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            if (index >= flat.length) return const SizedBox.shrink();
            final item = flat[index];
            if (item is _GroupTitle) return item;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _TaskRow(task: item as TransferTask),
            );
          },
          childCount: flat.length,
        ),
      ),
    );
  }
}

/// 任务行（设计稿 D5 `.task`）：64 高、grid 40/1fr/190/150/96、圆角 14 描边。
class _TaskRow extends ConsumerWidget {
  final TransferTask task;
  final bool dense;
  const _TaskRow({required this.task, this.dense = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final notifier = ref.read(transfersProvider.notifier);
    final ratio = task.total <= 0 ? 0.0 : (task.done / task.total).clamp(0.0, 1.0);
    final failed = task.status == TransferStatus.failed;
    final running = task.status == TransferStatus.running;
    final paused = task.status == TransferStatus.paused;
    final done = task.status == TransferStatus.done;
    final serverOp = task.isServerOp;
    // 操作类型 → 图标 / 图标色 / 图标块底色（复制紫、移动橙，与设计稿 D5b 一致）
    final (kindIcon, kindColor, kindTile) = switch (task.kind) {
      TransferKind.download => ('download', const Color(0xFF0EA5E9), OlTokens.tileSky),
      TransferKind.upload => ('upload', const Color(0xFF0E9F6E), OlTokens.tileTeal),
      TransferKind.copy => ('copy', OlTokens.tagVioletFg, OlTokens.tileViolet),
      TransferKind.move => ('move', const Color(0xFFD97706), OlTokens.tileAmber),
    };
    // 名称前胶囊：类型 + 配色
    final (badgeLabel, badgeFg, badgeBg) = failed
        ? ('失败', const Color(0xFF8A2438), const Color(0xFFFFF1F3))
        : switch (task.kind) {
            TransferKind.download => ('下载', OlTokens.tagSkyFg, OlTokens.tagSkyBg),
            TransferKind.upload => ('上传', OlTokens.tagGreenFg, OlTokens.tagGreenBg),
            TransferKind.copy => ('复制', OlTokens.tagVioletFg, OlTokens.tagVioletBg),
            TransferKind.move => ('移动', OlTokens.tagAmberFg, OlTokens.tagAmberBg),
          };

    return Container(
      height: dense ? null : 64,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: failed ? OlTokens.failRowBg : p.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: failed ? const Color(0xFFF8C9D2) : p.line),
      ),
      child: Row(
        children: [
          // 图标块 38×38 r10（设计稿 `.ic`）
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: failed ? const Color(0xFFFFF1F3) : kindTile,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: OlIcon(
                failed ? 'alert' : kindIcon,
                size: 18,
                color: failed ? const Color(0xFFD92D4B) : kindColor,
                strokeWidth: 1.9,
              ),
            ),
          ),
          const SizedBox(width: 14),
          // 名称 + 路径（1fr）
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  task.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.ink),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    _TaskBadge(label: badgeLabel, fg: badgeFg, bg: badgeBg),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        _pathText(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10.5, color: p.ink4),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          // 进度 + meta（190）
          SizedBox(
            width: 190,
            child: serverOp
                // 复制 / 移动由服务端整条目搬运，拿不到字节进度：不画进度条，
                // 用两行状态文字，高度节奏与字节传输行保持一致。
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        failed
                            ? '失败'
                            : (done
                                ? '已完成'
                                : (paused
                                    ? '已暂停'
                                    : (running ? '处理中…' : '排队中'))),
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: failed
                              ? const Color(0xFF8A2438)
                              : (done ? const Color(0xFF0B6B4A) : p.ink2),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        failed ? (task.error ?? '操作失败，可重试') : '服务端直传',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10.5, color: p.ink3),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _ProgressBar(ratio: ratio, failed: failed, paused: paused),
                      const SizedBox(height: 5),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${(ratio * 100).round()}% · ${formatBytes(task.done)} / ${formatBytes(task.total)}',
                            style: TextStyle(fontSize: 10.5, color: p.ink3),
                          ),
                          Text(
                            failed
                                ? '已暂停'
                                : (done ? '已完成' : formatSpeed(task.speed)),
                            style: TextStyle(
                              fontSize: 10.5,
                              color: failed ? const Color(0xFF8A2438) : p.ink3,
                              fontWeight: failed ? FontWeight.w700 : FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
          const SizedBox(width: 14),
          // 方式徽标（150）
          SizedBox(
            width: 150,
            child: Align(
              alignment: Alignment.centerLeft,
              // 方式徽标统一中性灰：琥珀色留给「移动」的类型胶囊，
              // 否则一行里两个橙色徽标会互相干扰。
              child: _TaskBadge(
                label: _modeLabel(task, failed),
                fg: const Color(0xFF42566B),
                bg: const Color(0xFFEDF2F8),
              ),
            ),
          ),
          const SizedBox(width: 14),
          // 操作（96）
          SizedBox(
            width: 96,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _ActionButton(
                  icon: failed
                      ? 'refresh'
                      : (running ? 'pause' : (paused ? 'play' : 'pause')),
                  tooltip: failed
                      ? '重试'
                      : (running ? '暂停' : (paused ? '继续' : '暂停')),
                  danger: false,
                  onTap: () {
                    if (failed) {
                      notifier.retry(task.id);
                    } else if (running) {
                      notifier.pause(task.id);
                    } else {
                      notifier.resume(task.id);
                    }
                  },
                ),
                const SizedBox(width: 6),
                _ActionButton(
                  icon: 'x',
                  tooltip: '取消',
                  danger: true,
                  onTap: () => notifier.remove(task.id),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 路径文案：源 → 目标。
  ///
  /// 下载/上传取「远端完整路径 → 本地完整路径」；
  /// 复制/移动取「源目录 → 目标目录」（条目名在名称那行）。
  String _pathText() {
    final remote = task.remotePath.isEmpty ? task.serverLabel : task.remotePath;
    final local = task.localPath.isEmpty ? '' : task.localPath;
    if (local.isEmpty) return remote;
    return '$remote → $local';
  }

}

/// 方式徽标：字节传输写传输方式，复制/移动写服务端直传，失败统一「可续传」。
String _modeLabel(TransferTask task, bool failed) {
  if (failed) return '可续传';
  return switch (task.kind) {
    TransferKind.download => '分片 + 续传',
    TransferKind.upload => '流式上传',
    TransferKind.copy => '服务端直传',
    TransferKind.move => '服务端直传',
  };
}

/// 任务徽标（设计稿 `.badge`）：9.5/800、圆角 99、padding 2/7。
class _TaskBadge extends StatelessWidget {
  final String label;
  final Color fg;
  final Color bg;

  const _TaskBadge({required this.label, required this.fg, required this.bg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Text(label, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: fg)),
    );
  }
}

/// 进度条（设计稿 `.pg`）：7 高、槽 #EDF2F8、已完成渐变，暂停态变灰。
class _ProgressBar extends StatelessWidget {
  final double ratio;
  final bool failed;
  final bool paused;

  const _ProgressBar({required this.ratio, required this.failed, required this.paused});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 7,
      decoration: BoxDecoration(
        color: const Color(0xFFEDF2F8),
        borderRadius: BorderRadius.circular(99),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: ratio.clamp(0.0, 1.0),
        child: Container(
          decoration: BoxDecoration(
            color: failed
                ? const Color(0xFFF8C9D2)
                : (paused ? const Color(0xFFC4D5E4) : null),
            gradient: (failed || paused)
                ? null
                : const LinearGradient(colors: [Color(0xFF38BDF8), Color(0xFF2DD4BF)]),
            borderRadius: BorderRadius.circular(99),
          ),
        ),
      ),
    );
  }
}

/// 行内操作按钮（设计稿 `.ia`）：30×30、圆角 8、描边。
class _ActionButton extends StatelessWidget {
  final String icon;
  final String tooltip;
  final bool danger;
  final VoidCallback onTap;

  const _ActionButton({
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
            width: 30,
            height: 30,
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

class _EmptyTransfers extends StatelessWidget {
  final String? title;
  final String? subtitle;

  /// v1.0.30：图标跟随筛选。之前固定用向下箭头，切到「失败」时
  /// 也显示下载箭头，看起来像功能坏了（截图里「没有失败的任务」配了个 ↓）。
  final String icon;
  final Color? iconColor;

  /// 可选的引导按钮：目前用于「进行中为空，但历史里有已完成任务」的场景。
  final Widget? action;

  const _EmptyTransfers({
    this.title,
    this.subtitle,
    this.icon = 'arrow-down',
    this.iconColor,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          OlIcon(icon, size: 24, color: iconColor ?? p.ink4),
          const SizedBox(height: 8),
          Text(
            title ?? '没有传输任务',
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: p.ink3),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle ?? '下载或上传文件后，这里会显示实时进度',
            style: TextStyle(fontSize: 9.5, color: p.ink4),
          ),
          if (action != null) ...[
            const SizedBox(height: 10),
            action!,
          ],
        ],
      ),
    );
  }
}
