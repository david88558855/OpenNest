import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/frame.dart';
import '../../app/providers.dart';
import '../../core/format.dart';
import '../../core/models/api_types.dart';
import '../../core/models/transfer_task.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/ol_controls.dart';
import '../../core/widgets/ol_icon.dart';
import '../files/file_actions.dart';
import '../settings/download_dir.dart';
import 'transfers_controller.dart';

part 'parts/transfers_sidebar.dart';
part 'parts/transfers_cards.dart';

/// W3（Windows 传输中心）/ A3（Android 传输 Tab）。
///
/// 布局：队列侧栏 204 → 主区（速度卡 / 四个指标 / 任务列表）→ 设置面板 250。
/// 上传、下载、离线任务共用一套语义；暂停 / 继续 / 重试 / 限速都在这里。
class TransfersPage extends ConsumerStatefulWidget {
  const TransfersPage({super.key});

  @override
  ConsumerState<TransfersPage> createState() => _TransfersPageState();
}

enum _Filter { active, all, download, upload, offline, done, failed }

class _TransfersPageState extends ConsumerState<TransfersPage> {
  _Filter _filter = _Filter.active;

  /// 类型筛选（第二个维度）：null = 全部。
  ///
  /// 与「进行中 / 已完成」是**两个独立维度**，可以叠加：
  /// 比如「已完成 + 复制」= 看历史里的复制任务。
  TransferKind? _kind;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(transfersProvider.notifier).loadServerTasks();
    });
  }

  List<TransferTask> _visible(TransfersState state) {
    final byState = _visibleByState(state);
    if (_kind == null) return byState;
    return byState.where((e) => e.kind == _kind).toList();
  }

  List<TransferTask> _visibleByState(TransfersState state) {
    switch (_filter) {
      case _Filter.active:
        // v2.6：「进行中」只放真正的在途任务。已完成 / 失败的一律归到各自分组，
        // 之前这里返回 state.tasks（全部），导致传输完成后仍赖在「进行中」列表里。
        return state.tasks
            .where((e) => e.status != TransferStatus.done && e.status != TransferStatus.failed)
            .toList();
      case _Filter.all:
        return state.tasks;
      case _Filter.download:
        return state.tasks.where((e) => e.kind == TransferKind.download).toList();
      case _Filter.upload:
        return state.tasks.where((e) => e.kind == TransferKind.upload).toList();
      case _Filter.offline:
        return state.serverTasks.map(_fromServer).toList();
      case _Filter.done:
        return state.done;
      case _Filter.failed:
        return state.failed;
    }
  }

  TransferTask _fromServer(ServerTask task) => TransferTask(
        id: 'srv-${task.id}',
        serverId: '',
        serverLabel: '离线下载',
        kind: TransferKind.download,
        name: task.name,
        remotePath: '',
        localPath: '',
        total: task.totalBytes,
        done: task.doneBytes,
        status: TransferStatus.running,
        error: task.error,
      );

  @override
  Widget build(BuildContext context) {
    if (context.isNarrow) return _buildMobile(context);
    return _buildDesktop(context);
  }

  // ------------------------------------------------------------------ W3 桌面
  Widget _buildDesktop(BuildContext context) {
    final p = context.ol;
    final state = ref.watch(transfersProvider);
    final tasks = _visible(state);
    return AppFrame(
      navIndex: 1,
      handleBack: true,
      child: Row(
        children: [
          const _QueueSidebar(),
          Expanded(
            // 0.5.0：与文件页一致 —— 主区底色改浅蓝灰。
            child: ColoredBox(
              color: p.surface,
              child: Column(
                children: [
                  _QueueHead(
                    filter: _filter,
                    onFilter: (f) => setState(() => _filter = f),
                    onNew: () => offlineDownload(context, ref),
                  ),
                  // 工具栏：左＝类型筛选，右＝汇总 + 清除已完成/失败 + 全部暂停
                  _QueueBar(
                    kind: _kind,
                    onKind: (k) => setState(() => _kind = k),
                    filter: _filter,
                  ),
                  Expanded(
                    // v1.0.30：整页改 sliver 体系。原来任务列表是
                    // SingleChildScrollView + Column + for 循环，会把所有任务行
                    // 一次性 build（2000 个任务 = 2000 个进度监听），大目录下载时卡死。
                    // 现在任务行走 SliverList，按需构建。
                    child: CustomScrollView(
                      slivers: [
                        _TaskListSliver(
                          tasks: tasks,
                          filter: _filter,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- A3 移动端
  Widget _buildMobile(BuildContext context) {
    final p = context.ol;
    final state = ref.watch(transfersProvider);
    final visible = _visible(state);
    // 顶部右侧按钮跟随分段：进行中 → 全局暂停；已完成 / 失败 → 清除。
    // 0.5.11：以前这里恒为「全部暂停」，已完成列表里既清不掉、也没法批量删，
    // 只能一个个点行内的 ×（而手机上行内按钮还被挤出了屏幕）。
    final Widget trailingAction;
    if (_filter == _Filter.done) {
      trailingAction = OlGhostButton(
        label: '清除已完成',
        icon: 'trash',
        height: 28,
        fontSize: 10,
        onTap: state.doneCount == 0
            ? null
            : () => ref
                .read(transfersProvider.notifier)
                .clearTasks(visible.where((e) => e.status == TransferStatus.done).map((e) => e.id).toList()),
      );
    } else if (_filter == _Filter.failed) {
      trailingAction = OlGhostButton(
        label: '清除失败',
        icon: 'trash',
        height: 28,
        fontSize: 10,
        onTap: state.failedCount == 0
            ? null
            : () => ref
                .read(transfersProvider.notifier)
                .clearTasks(visible.where((e) => e.status == TransferStatus.failed).map((e) => e.id).toList()),
      );
    } else {
      trailingAction = OlGhostButton(
        label: state.pausedGlobally ? '全部继续' : '全部暂停',
        icon: state.pausedGlobally ? 'play' : 'pause',
        height: 28,
        fontSize: 10,
        onTap: () {
          final notifier = ref.read(transfersProvider.notifier);
          if (state.pausedGlobally) {
            notifier.resumeAll();
          } else {
            notifier.pauseAll();
          }
        },
      );
    }
    return AppFrame(
      navIndex: 1,
      handleBack: true,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              // v1.0.14：Android 也给显式返回（之前只能靠底部 tab 或系统返回）。
              padding: const EdgeInsets.fromLTRB(10, 8, OlGap.pageMobile, 8),
              child: Row(
                children: [
                  OlIconButton(icon: 'chev-l', size: 34, iconSize: 18, onTap: () => goBackOrFiles(context)),
                  const SizedBox(width: 2),
                  Text('传输', style: TextStyle(fontSize: 18, letterSpacing: -0.4, fontWeight: FontWeight.w800, color: p.ink)),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: OlGap.pageMobile, vertical: 4),
              child: Text(
                '下载 ${formatSpeed(state.downSpeed)} · 上传 ${formatSpeed(state.upSpeed)}',
                style: TextStyle(fontSize: 11.5, color: context.ol.ink3),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(OlGap.pageMobile, 12, OlGap.pageMobile, 0),
              child: Row(
                children: [
                  Expanded(
                    // v1.0.32：等分模式。三档在放大字号下会超出可用宽度，
                    // 之前最后一段的选中块会被顶出灰底（用户截图里的溢出）。
                    child: OlSeg<_Filter>(
                      items: const [
                        OlSegItem(_Filter.active, '进行中'),
                        OlSegItem(_Filter.done, '已完成'),
                        OlSegItem(_Filter.failed, '失败'),
                      ],
                      value: (_filter == _Filter.done || _filter == _Filter.failed) ? _filter : _Filter.active,
                      onChanged: (f) => setState(() => _filter = f),
                      expand: true,
                    ),
                  ),
                  const SizedBox(width: 8),
                  trailingAction,
                ],
              ),
            ),
          ),
          if (visible.isEmpty)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 240,
                // 0.5.11：空态只说明当前分组为空。去掉了「查看已完成（N）」提示
                // 与按钮 —— 顶部分段里已经有计数，再引导一次属于重复。
                child: _EmptyTransfers(
                  icon: switch (_filter) {
                    _Filter.failed => 'alert',
                    _Filter.done => 'check',
                    _ => 'arrow-down',
                  },
                  iconColor: _filter == _Filter.failed ? OlTokens.danger : null,
                  title: switch (_filter) {
                    _Filter.active => '没有进行中的任务',
                    _Filter.done => '还没有已完成的任务',
                    _Filter.failed => '没有失败的任务',
                    _ => '没有传输任务',
                  },
                  subtitle: switch (_filter) {
                    _Filter.active => '完成或失败的任务会移到对应分组',
                    _Filter.done => '下载或上传成功后出现在这里',
                    _Filter.failed => '传输失败时会出现在这里，可重试',
                    _ => '下载或上传文件后，这里会显示实时进度',
                  },
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: OlGap.pageMobile),
                  child: _TaskRow(task: visible[index], dense: true),
                ),
                childCount: visible.length,
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 104)),
        ],
      ),
    );
  }
}


/// 队列标题区（设计稿 D5 `.head`）：标题 + 副标题 + 右侧分段。
class _QueueHead extends ConsumerWidget {
  final _Filter filter;
  final ValueChanged<_Filter> onFilter;
  final VoidCallback onNew;

  const _QueueHead({required this.filter, required this.onFilter, required this.onNew});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final state = ref.watch(transfersProvider);
    final settings = ref.watch(appSettingsProvider);
    final active = state.tasks.where((e) => e.status != TransferStatus.done && e.status != TransferStatus.failed).length;
    final done = state.doneCount;
    final failed = state.failedCount;

    return Container(
      // 设计稿 D5 `.head`：padding 20/24/0。
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      decoration: const BoxDecoration(
        // 0.5.0：标题区与下方全局条同属主区，底色必须一致。
        //
        // 此前这里写死 p.card（白），而主区底色已改为 p.surface（浅蓝灰），
        // 于是标题区变成一条突兀的白带，与紧邻的全局条割裂开。
        // 改为透明后透出主区的浅蓝灰，与下方完全连成一片。
        color: Colors.transparent,
        // 设计稿的 `.head` 没有分隔线（分隔线在 `.gbar` 底部）。
        // 这里也不重复画，避免标题区下方多出一道多余的横线。
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 0.5.0：返回入口移到左侧栏顶部（与设置页一致），标题区不再放返回按钮。
          Expanded(
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('传输队列', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: p.ink)),
              const SizedBox(height: 4),
              // 0.5.0：并发 / 限速从工具栏挪到副标题右侧 —— 这两项是「看」的
              // 信息，跟说明文字同一行更省纵向空间，工具栏那行留给筛选与操作。
              Row(
                children: [
                  Flexible(
                    child: Text(
                      '任务持久化保存 · 重启后自动恢复 · 断点续传',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: p.ink3),
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 10,
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    color: p.line,
                  ),
                  const OlIcon('clock', size: 12, color: Color(0xFF6B7F94)),
                  const SizedBox(width: 5),
                  Text('并发 ${settings.concurrency}', style: TextStyle(fontSize: 11.5, color: p.ink3)),
                  const SizedBox(width: 12),
                  const OlIcon('sort', size: 12, color: Color(0xFF6B7F94)),
                  const SizedBox(width: 5),
                  Text(
                    '限速：${_limitLabel(settings.downLimitKbps, settings.upLimitKbps)}',
                    style: TextStyle(fontSize: 11.5, color: p.ink3),
                  ),
                ],
              ),
            ],
            ),
          ),
          // 设计稿 `.tabs`：底 #F1F6FB、圆角 10、padding 3，段高 30。
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F6FB),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                _TabButton(
                  label: '进行中',
                  count: active,
                  selected: filter == _Filter.active,
                  onTap: () => onFilter(_Filter.active),
                ),
                const SizedBox(width: 6),
                _TabButton(
                  label: '已完成',
                  count: done,
                  selected: filter == _Filter.done,
                  onTap: () => onFilter(_Filter.done),
                ),
                // 0.5.2：桌面端此前漏了「失败」入口，失败任务只能靠空态里的
                // 引导按钮跳过去，等于查不到。按顺序放在「已完成」右边。
                const SizedBox(width: 6),
                _TabButton(
                  label: '失败',
                  count: failed,
                  danger: failed > 0,
                  selected: filter == _Filter.failed,
                  onTap: () => onFilter(_Filter.failed),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          OlGhostButton(
            label: '新建任务',
            icon: 'plus',
            height: 32,
            fontSize: 12,
            horizontalPadding: 14,
            fgColor: p.ink,
            onTap: onNew,
          ),
        ],
      ),
    );
  }
}

/// 分段按钮（设计稿 `.tab`）：30 高、圆角 8；选中白底 + 轻阴影 + 计数徽标。
class _TabButton extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  /// 红色计数徽标：失败数用它，扫一眼就知道有东西要处理。
  final bool danger;

  const _TabButton({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    this.danger = false,
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
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: selected ? p.card : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: selected
                ? const [BoxShadow(color: Color(0x1A0E3A46), blurRadius: 6, offset: Offset(0, 2))]
                : null,
          ),
          child: Row(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected ? p.ink : p.ink2,
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                  decoration: BoxDecoration(
                    color: danger ? const Color(0xFFFDE8EC) : const Color(0xFFEAF8FE),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: danger ? const Color(0xFFD92D4B) : const Color(0xFF08799F),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
