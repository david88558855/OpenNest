part of '../transfers_page.dart';

// 顶部条 / 速度卡 / 指标卡 / 任务列表（sliver）/ 任务行 / 空态
// ---------------------------------------------------------------------------
// 顶部条 / 速度卡 / 指标
// ---------------------------------------------------------------------------
class _TopBar extends ConsumerWidget {
  final VoidCallback onNew;
  const _TopBar({required this.onNew});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final state = ref.watch(transfersProvider);
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: p.surfaceAlt,
        border: Border(bottom: BorderSide(color: p.hairline)),
      ),
      child: Row(
        children: [
          // v1.0.14：传输是独立页面，顶部给显式返回。
          OlIconButton(icon: 'chev-l', size: 30, iconSize: 17, tooltip: '返回', onTap: () => goBackOrFiles(context)),
          const SizedBox(width: 6),
          Text('传输中心', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: p.ink)),
          const SizedBox(width: 4),
          OlIcon('chev-r', size: 12, color: p.ink4),
          const SizedBox(width: 4),
          Text('全部任务', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: p.ink3)),
          const Spacer(),
          OlIconButton(
            icon: state.pausedGlobally ? 'play' : 'pause',
            tooltip: state.pausedGlobally ? '全部继续' : '全部暂停',
            squared: true,
            onTap: () {
              final notifier = ref.read(transfersProvider.notifier);
              if (state.pausedGlobally) {
                notifier.resumeAll();
              } else {
                notifier.pauseAll();
              }
            },
          ),
          const SizedBox(width: 8),
          OlGhostButton(label: '新建任务', icon: 'plus', height: 30, onTap: onNew),
        ],
      ),
    );
  }
}

class _SpeedCard extends StatelessWidget {
  final TransfersState state;
  final bool compact;
  const _SpeedCard({required this.state, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final total = state.downSpeed + state.upSpeed;
    final mb = total / (1024 * 1024);
    return Container(
      height: compact ? 118 : 132,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0C1E2E), Color(0xFF0E2C40), Color(0xFF0F3A46)],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Stack(
        children: [
          Positioned(right: -30, top: -70, child: _glow(220, const Color(0x382DD4BF))),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'CURRENT THROUGHPUT',
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1.4, color: Color(0xFF8FB2C6)),
                        ),
                        const SizedBox(height: 7),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              mb >= 10 ? mb.toStringAsFixed(0) : mb.toStringAsFixed(1),
                              style: TextStyle(
                                fontSize: compact ? 28 : 31,
                                height: 1,
                                letterSpacing: -1,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.only(left: 4, bottom: 3),
                              child: Text('MB/s ↓', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF9EBBCE))),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            _SpeedMeta(label: '上传', value: formatSpeed(state.upSpeed)),
                            const SizedBox(width: 12),
                            _SpeedMeta(label: '活动任务', value: '${state.active.length}'),
                            const SizedBox(width: 12),
                            _SpeedMeta(label: '并发', value: '${state.concurrency}'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    height: 22,
                    padding: const EdgeInsets.symmetric(horizontal: 9),
                    decoration: BoxDecoration(
                      color: const Color(0x17FFFFFF),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: const Color(0x24FFFFFF)),
                    ),
                    child: const Center(
                      child: Text('全局不限速', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFFBFE6F5))),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              SizedBox(
                height: compact ? 36 : 44,
                child: CustomPaint(
                  painter: _SparkPainter(value: total <= 0 ? 0.12 : (mb / 8).clamp(0.15, 1.0)),
                  size: Size.infinite,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _glow(double size, Color color) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [color, color.withAlpha(0)])),
      );
}

class _SpeedMeta extends StatelessWidget {
  final String label;
  final String value;
  const _SpeedMeta({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('$label ', style: const TextStyle(fontSize: 9, color: Color(0xFF8FA8BD))),
        Text(value, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFFCFE6F3))),
      ],
    );
  }
}

class _SparkPainter extends CustomPainter {
  final double value;
  _SparkPainter({required this.value});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..moveTo(0, size.height * 0.8);
    const steps = 12;
    for (var i = 1; i <= steps; i++) {
      final x = size.width * i / steps;
      final wave = (i.isEven ? 0.35 : 0.65) * value;
      final y = size.height * (0.75 - wave * 0.6);
      final cx = size.width * (i - 0.5) / steps;
      path.quadraticBezierTo(cx, y, x, size.height * (0.72 - wave * 0.5));
    }
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x6138BDF8), Color(0x0038BDF8)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = const Color(0xFF7DD3FC),
    );
  }

  @override
  bool shouldRepaint(covariant _SparkPainter oldDelegate) => oldDelegate.value != value;
}

class _StatTiles extends StatelessWidget {
  final TransfersState state;
  final int visible;
  const _StatTiles({required this.state, required this.visible});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    final doneBytes = state.done.fold<int>(0, (sum, e) => sum + e.total);
    return Row(
      children: [
        Expanded(child: _Tile(icon: 'arrow-down', label: '下载速度', value: formatSpeed(state.downSpeed), palette: p)),
        const SizedBox(width: 8),
        Expanded(child: _Tile(icon: 'arrow-up', label: '上传速度', value: formatSpeed(state.upSpeed), palette: p)),
        const SizedBox(width: 8),
        Expanded(child: _Tile(icon: 'zap', label: '队列', value: '$visible 项', palette: p)),
        const SizedBox(width: 8),
        Expanded(child: _Tile(icon: 'clock', label: '今日完成', value: formatBytes(doneBytes), palette: p)),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  final String icon;
  final String label;
  final String value;
  final OlPalette palette;
  const _Tile({required this.icon, required this.label, required this.value, required this.palette});

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 9, 11, 9),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: p.line2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              OlIcon(icon, size: 11, color: p.ink4),
              const SizedBox(width: 5),
              Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: p.ink4)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 14, letterSpacing: -0.3, fontWeight: FontWeight.w800, color: p.ink),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 任务列表（sliver 版：按需构建任务行，v1.0.30）
// ---------------------------------------------------------------------------
class _TaskListSliver extends StatelessWidget {
  final List<TransferTask> tasks;
  final _Filter filter;
  final ValueChanged<_Filter> onFilter;

  const _TaskListSliver({required this.tasks, required this.filter, required this.onFilter});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return DecoratedSliver(
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.line2),
      ),
      sliver: SliverMainAxisGroup(
        slivers: [
          SliverToBoxAdapter(child: _TaskListHeader(tasks: tasks, filter: filter, onFilter: onFilter)),
          if (tasks.isEmpty)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 160,
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
                    _ => '没有进行中的任务',
                  },
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => _TaskRow(task: tasks[index]),
                childCount: tasks.length,
              ),
            ),
        ],
      ),
    );
  }
}

/// 卡片头：标题 + 全部/下载/上传 分段；已完成/失败分组额外给「清除」。
class _TaskListHeader extends ConsumerWidget {
  final List<TransferTask> tasks;
  final _Filter filter;
  final ValueChanged<_Filter> onFilter;

  const _TaskListHeader({required this.tasks, required this.filter, required this.onFilter});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final clearable = filter == _Filter.done || filter == _Filter.failed;
    // v2.6：标题跟随筛选走。之前固定写「进行中」，切到已完成/失败仍是这个标题。
    final title = switch (filter) {
      _Filter.done => '已完成',
      _Filter.failed => '失败',
      _Filter.offline => '离线下载',
      _Filter.download => '正在下载',
      _Filter.upload => '正在上传',
      _ => '进行中',
    };
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.line2))),
      child: Row(
        children: [
          Text(title, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: p.ink2)),
          const Spacer(),
          // v1.0.35：已完成 / 失败分组提供一键清除（之前只能逐条点，失败列表清不掉）
          if (clearable && tasks.isNotEmpty) ...[
            OlGhostButton(
              label: '清除',
              icon: 'trash',
              height: 21,
              fontSize: 9,
              onTap: () => ref.read(transfersProvider.notifier).clearTasks(tasks.map((e) => e.id).toList()),
            ),
            const SizedBox(width: 6),
          ],
          OlSeg<_Filter>(
            items: [
              OlSegItem(_Filter.all, '全部 ${tasks.length}'),
              OlSegItem(_Filter.download, '下载'),
              OlSegItem(_Filter.upload, '上传'),
            ],
            value: (filter == _Filter.upload || filter == _Filter.download) ? filter : _Filter.all,
            onChanged: onFilter,
            height: 21,
          ),
        ],
      ),
    );
  }
}

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
    final done = task.status == TransferStatus.done;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 0 : 12, vertical: 9),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.divider))),
      child: Row(
        children: [
          FileGlyph(name: task.name, size: 30, radius: 8, iconSize: 15),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: p.ink),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        failed ? '连接失败' : task.serverLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: failed ? FontWeight.w700 : FontWeight.w500,
                          color: failed ? OlTokens.dangerDeep : p.ink4,
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(formatSpeed(task.speed), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: p.ink2)),
                    const SizedBox(width: 7),
                    Text('${formatBytes(task.done)} / ${formatBytes(task.total)}', style: TextStyle(fontSize: 9, color: p.ink4)),
                  ],
                ),
                const SizedBox(height: 5),
                OlProgress(value: ratio, height: 3),
              ],
            ),
          ),
          SizedBox(
            width: 56,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  done ? '完成' : '${(ratio * 100).round()}%',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: failed ? OlTokens.dangerDeep : p.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  done || task.speed <= 0 ? '' : '剩余 ${formatCountdown(((task.total - task.done) / task.speed).round())}',
                  style: TextStyle(fontSize: 9, color: p.ink4),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          // 离线下载任务由服务端执行，本地暂停/重试无意义（v2.2 审计）。
          if (task.id.startsWith('srv-'))
            SizedBox(
              width: 24,
              height: 24,
              child: Center(child: OlIcon('cloud-dl', size: 12, color: p.ink4)),
            )
          else if (failed)
            // v1.0.35：失败任务之前只有「重试」，没有移除按钮，失败列表越积越多清不掉。
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OlGhostButton(label: '重试', height: 22, fontSize: 9, onTap: () => notifier.retry(task.id)),
                const SizedBox(width: 2),
                OlIconButton(icon: 'x', size: 24, iconSize: 12, tooltip: '移除', onTap: () => notifier.remove(task.id)),
              ],
            )
          else if (running)
            OlIconButton(icon: 'pause', size: 24, iconSize: 12, tooltip: '暂停', onTap: () => notifier.pause(task.id))
          else if (task.status == TransferStatus.paused)
            OlIconButton(icon: 'play', size: 24, iconSize: 12, tooltip: '继续', onTap: () => notifier.resume(task.id))
          else
            OlIconButton(icon: 'x', size: 24, iconSize: 12, tooltip: '移除', onTap: () => notifier.remove(task.id)),
        ],
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
