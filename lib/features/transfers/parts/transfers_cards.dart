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

  /// 当前状态分组（进行中 / 已完成 / 失败）。
  ///
  /// 0.5.13：已完成 / 失败分组在这里给一个「清除全部」，放在「全部暂停」左侧。
  /// 之前桌面端只能一条条点行内 ×，清几十条历史纯靠手速。
  final _Filter filter;

  const _QueueBar({required this.kind, required this.onKind, required this.filter});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final state = ref.watch(transfersProvider);
    final notifier = ref.read(transfersProvider.notifier);

    int countOf(TransferKind kind) => state.tasks.where((e) => e.kind == kind).length;

    /// 当前分组 + 当前类型筛选下的任务 id（与列表里看得见的那批一致）。
    List<String> idsOf(TransferStatus status) => state.tasks
        .where((e) => e.status == status && (kind == null || e.kind == kind))
        .map((e) => e.id)
        .toList();

    final clearIds = switch (filter) {
      _Filter.done => idsOf(TransferStatus.done),
      _Filter.failed => idsOf(TransferStatus.failed),
      _ => const <String>[],
    };

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
          // 「清除全部」：只在已完成 / 失败分组出现，位置紧挨「全部暂停」左侧。
          // 列表被类型胶囊过滤过，清除也只看当前筛选，与眼睛看到的一致。
          if (filter == _Filter.done || filter == _Filter.failed) ...[
            OlGhostButton(
              label: filter == _Filter.done ? '清除已完成' : '清除失败',
              icon: 'trash',
              height: 32,
              fontSize: 12,
              horizontalPadding: 14,
              fgColor: p.ink,
              onTap: clearIds.isEmpty ? null : () => notifier.clearTasks(clearIds),
            ),
            const SizedBox(width: 8),
          ],
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

  const _TaskListSliver({required this.tasks, required this.filter});

  static const Map<TransferKind, String> _kindLabels = {
    TransferKind.download: '下载',
    TransferKind.upload: '上传',
    TransferKind.copy: '复制',
    TransferKind.move: '移动',
  };

  /// 分组标题跟随状态分组。
  ///
  /// 0.5.13：以前恒为「下载中 / 上传中」，切到「已完成」还写着「下载中」，
  /// 与分段选中态和 100% 的进度条互相矛盾。
  String _groupTitle(TransferKind kind) {
    final label = _kindLabels[kind]!;
    return switch (filter) {
      _Filter.done => '已完成 · $label',
      _Filter.failed => '失败 · $label',
      _ => '$label中',
    };
  }

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) {
      // 空态只说明「这里此刻没有任务」。0.5.11 去掉了「查看已完成（N）」按钮：
      // 顶部本来就有「已完成 / 失败」分段，计数也在上面，空态再放一个跳转按钮
      // 属于重复引导，用户反馈「完成之后不需要这个提示和按钮」。
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
      flat.add(_GroupTitle(_groupTitle(kind)));
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
///
/// `dense = true`（Android）时改走 [_MobileTaskRow]：手机宽度放不下桌面那套
/// 固定列宽（合计 ~540dp），硬排的结果是名称列被压成 0 宽、右侧徽标与
/// 「暂停 / 取消」整块被裁到屏幕外 —— 用户既看不到状态也点不到取消。
class _TaskRow extends ConsumerWidget {
  final TransferTask task;
  final bool dense;
  const _TaskRow({required this.task, this.dense = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (dense) return _MobileTaskRow(task: task);
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
      // 桌面固定 64 高（设计稿 D5 `.task`）；移动端走 _MobileTaskRow，不到这里。
      height: 64,
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
                            // 0.5.11：失败行此前写「已暂停」，与旁边的「失败」
                            // 徽标自相矛盾。
                            failed
                                ? '已中断'
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
                // 已完成的任务没有「暂停 / 继续」语义：以前这里判定走 else
                // 分支调 resume()，会把它重新排队再下一次 —— 本地文件已完整，
                // 服务端对 Range 请求回 416，任务反而从「已完成」变「失败」。
                if (!done) ...[
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
                ],
                _ActionButton(
                  icon: 'x',
                  tooltip: done ? '清除记录' : '取消',
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

/// Android 任务行：单列紧凑卡。
///
/// 结构：`[类型图标] [名称 / 进度 / 百分比·状态] [主操作] [取消]`。
/// 不再有固定宽度的「方式徽标」「操作列」——那些是桌面网格的产物，
/// 手机上会被挤出屏幕。宽度自适应：名称与进度条吃掉全部剩余空间。
class _MobileTaskRow extends ConsumerWidget {
  final TransferTask task;
  const _MobileTaskRow({required this.task});

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

    final (kindIcon, kindColor, kindTile) = switch (task.kind) {
      TransferKind.download => ('download', const Color(0xFF0EA5E9), OlTokens.tileSky),
      TransferKind.upload => ('upload', const Color(0xFF0E9F6E), OlTokens.tileTeal),
      TransferKind.copy => ('copy', OlTokens.tagVioletFg, OlTokens.tileViolet),
      TransferKind.move => ('move', const Color(0xFFD97706), OlTokens.tileAmber),
    };

    // 右侧状态：失败 / 已完成 / 速度，一句话说清当前在干什么。
    final statusText = failed
        ? '可重试'
        : (done ? '已完成' : (paused ? '已暂停' : (running ? '进行中' : '排队中')));
    final statusColor = failed
        ? const Color(0xFF8A2438)
        : (done ? const Color(0xFF0B6B4A) : p.ink3);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: failed ? OlTokens.failRowBg : p.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: failed ? const Color(0xFFF8C9D2) : p.line),
      ),
      child: Row(
        children: [
          // 类型图标：36×36 r10，紧贴卡片内边距，不再留出多余的空白。
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: failed ? const Color(0xFFFFF1F3) : kindTile,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: OlIcon(
                failed ? 'alert' : kindIcon,
                size: 17,
                color: failed ? const Color(0xFFD92D4B) : kindColor,
                strokeWidth: 1.9,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  task.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: p.ink),
                ),
                const SizedBox(height: 5),
                if (serverOp)
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          failed ? (task.error ?? '操作失败，可重试') : '服务端直传',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 10.5, color: p.ink3),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        statusText,
                        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: statusColor),
                      ),
                    ],
                  )
                else ...[
                  _ProgressBar(ratio: ratio, failed: failed, paused: paused),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${(ratio * 100).round()}% · ${formatBytes(task.done)} / ${formatBytes(task.total)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 10.5, color: p.ink3),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        done ? '已完成' : (failed ? statusText : formatSpeed(task.speed)),
                        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: statusColor),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          // 主操作：失败 → 重试；运行中 → 暂停；排队 → 继续。
          // 已完成的任务不给主操作（再跑一遍会 416 变失败），只留右侧「清除记录」。
          if (!done) ...[
            _ActionButton(
              icon: failed ? 'refresh' : (running ? 'pause' : 'play'),
              tooltip: failed ? '重试' : (running ? '暂停' : '继续'),
              size: 32,
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
          ],
          // 取消 / 移除：已完成的任务也能从这里清掉（以前这个按钮被挤出屏幕）。
          _ActionButton(
            icon: 'x',
            tooltip: done ? '清除记录' : '取消',
            danger: true,
            size: 32,
            onTap: () => notifier.remove(task.id),
          ),
        ],
      ),
    );
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

/// 行内操作按钮（设计稿 `.ia`）：默认 30×30、圆角 8、描边。
///
/// Android 传 [size] = 32（触控目标略大一点）；桌面保持 30。
class _ActionButton extends StatelessWidget {
  final String icon;
  final String tooltip;
  final bool danger;
  final VoidCallback onTap;
  final double size;

  const _ActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.danger = false,
    this.size = 30,
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
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: p.card,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: p.line),
            ),
            child: Center(
              child: OlIcon(
                icon,
                size: size == 30 ? 13 : 14,
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

  const _EmptyTransfers({
    this.title,
    this.subtitle,
    this.icon = 'arrow-down',
    this.iconColor,
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
        ],
      ),
    );
  }
}
