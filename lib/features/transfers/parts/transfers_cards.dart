part of '../transfers_page.dart';

// 顶部条 / 速度卡 / 指标卡 / 任务列表（sliver）/ 任务行 / 空态
// ---------------------------------------------------------------------------
// 顶部条 / 速度卡 / 指标
// ---------------------------------------------------------------------------
/// 全局控制条（设计稿 D5 `.gbar`）：全部暂停 + 并发 + 限速 + 汇总。
class _GlobalBar extends ConsumerWidget {
  const _GlobalBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final state = ref.watch(transfersProvider);
    final settings = ref.watch(appSettingsProvider);
    final notifier = ref.read(transfersProvider.notifier);

    // 汇总：已完成 + 进行中的总字节，以及按当前速度估算的剩余时间。
    var totalBytes = 0;
    var remaining = 0;
    for (final task in state.tasks) {
      totalBytes += task.total;
      if (task.status != TransferStatus.done) remaining += (task.total - task.done);
    }
    final speed = state.downSpeed + state.upSpeed;
    final eta = speed > 0 ? (remaining / speed).round() : 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
      decoration: BoxDecoration(
        color: p.card,
        border: Border(bottom: BorderSide(color: p.line)),
      ),
      child: Row(
        children: [
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
          const SizedBox(width: 10),
          const OlIcon('clock', size: 13, color: Color(0xFF6B7F94)),
          const SizedBox(width: 6),
          Text('并发 ${settings.concurrency}', style: TextStyle(fontSize: 11.5, color: p.ink3)),
          const SizedBox(width: 10),
          const OlIcon('sort', size: 13, color: Color(0xFF6B7F94)),
          const SizedBox(width: 6),
          Text(
            '限速：${_limitLabel(settings.downLimitKbps, settings.upLimitKbps)}',
            style: TextStyle(fontSize: 11.5, color: p.ink3),
          ),
          const Spacer(),
          Text(
            totalBytes <= 0 ? '暂无任务' : '总计 ${formatBytes(totalBytes)} · 剩余约 ${formatCountdown(eta)}',
            style: TextStyle(fontSize: 11.5, color: p.ink3),
          ),
        ],
      ),
    );
  }

  /// 限速文案：任一方向有上限就显示具体值，两边都无限速显示「不限」。
  String _limitLabel(int down, int up) {
    if (down <= 0 && up <= 0) return '不限';
    if (down > 0 && up > 0) return '下载 ${down}KB/s · 上传 ${up}KB/s';
    if (down > 0) return '下载 ${down}KB/s';
    return '上传 ${up}KB/s';
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
/// 任务列表（设计稿 D5）：按方向分组，每行 64 高紧凑卡。
class _TaskListSliver extends StatelessWidget {
  final List<TransferTask> tasks;
  final _Filter filter;
  final ValueChanged<_Filter> onFilter;

  const _TaskListSliver({required this.tasks, required this.filter, required this.onFilter});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;

    // 设计稿 D5：按方向分组（下载中 / 上传中）。离线任务并入下载组。
    final downloads = <TransferTask>[];
    final uploads = <TransferTask>[];
    for (final task in tasks) {
      if (task.kind == TransferKind.upload) {
        uploads.add(task);
      } else {
        downloads.add(task);
      }
    }

    if (tasks.isEmpty) {
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

    return SliverPadding(
      // 设计稿 D5 `.tasks`：padding 8/24/16。
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final groups = <String, List<TransferTask>>{
              '下载中': downloads,
              '上传中': uploads,
            };
            // 展平成「[标题, 行, 行, 标题, 行…]」的顺序列表。
            final flat = <Object>[];
            for (final entry in groups.entries) {
              if (entry.value.isEmpty) continue;
              flat.add(_GroupTitle(entry.key));
              flat.addAll(entry.value);
            }
            if (index >= flat.length) return const SizedBox.shrink();
            final item = flat[index];
            if (item is _GroupTitle) return item;
            final task = item as TransferTask;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _TaskRow(task: task),
            );
          },
          // 先算展开后的长度，避免闭包里每帧都重建 groups。
          childCount: _flatCount(downloads, uploads),
        ),
      ),
    );
  }

  int _flatCount(List<TransferTask> downloads, List<TransferTask> uploads) {
    var n = 0;
    if (downloads.isNotEmpty) n += downloads.length + 1;
    if (uploads.isNotEmpty) n += uploads.length + 1;
    return n;
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
    final upload = task.kind == TransferKind.upload;

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
              color: failed
                  ? const Color(0xFFFFF1F3)
                  : (upload ? OlTokens.tileTeal : OlTokens.tileSky),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: OlIcon(
                failed ? 'alert' : (upload ? 'upload' : 'download'),
                size: 18,
                color: failed
                    ? const Color(0xFFD92D4B)
                    : (upload ? const Color(0xFF0E9F6E) : const Color(0xFF0EA5E9)),
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
                    _TaskBadge(
                      label: failed
                          ? '失败'
                          : (upload ? '上传' : '下载'),
                      fg: failed
                          ? const Color(0xFF8A2438)
                          : (upload ? OlTokens.tagGreenFg : OlTokens.tagSkyFg),
                      bg: failed
                          ? const Color(0xFFFFF1F3)
                          : (upload ? OlTokens.tagGreenBg : OlTokens.tagSkyBg),
                    ),
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
            child: Column(
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
              child: _TaskBadge(
                label: _modeLabel(),
                fg: OlTokens.tagAmberFg,
                bg: OlTokens.tagAmberBg,
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

  /// 路径文案：源 → 目标。取远端路径与本地路径，缺失时退回来源标签。
  String _pathText() {
    final remote = task.remotePath.isEmpty ? task.serverLabel : task.remotePath;
    final local = task.localPath.isEmpty ? '' : task.localPath;
    if (local.isEmpty) return remote;
    return '$remote → $local';
  }

  /// 方式徽标：失败可续传、上传流式、下载分片。
  String _modeLabel() {
    if (task.status == TransferStatus.failed) return '可续传';
    if (task.kind == TransferKind.upload) return '流式上传';
    return '分片下载';
  }
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
