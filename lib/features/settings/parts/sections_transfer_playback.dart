part of '../settings_page.dart';

// 传输 / 播放分区（并发、限速、续播、倍速）
// ---------------------------------------------------------------------------
// 传输 / 播放 / 通知
// ---------------------------------------------------------------------------
class _TransferSection extends ConsumerWidget {
  const _TransferSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final notifier = ref.watch(appSettingsProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHead(title: '传输', subtitle: '并发与限速'),
        _GroupLabel('限速'),
        _Card(
          child: Column(
            children: [
              _Row(
                icon: 'download',
                title: '下载限速',
                subtitle: '0 表示不限速，单位 Mbps',
                trailing: _ValuePill(formatLimitSpeed(settings.downLimitKbps)),
                onTap: () => _editLimit(
                  context,
                  title: '下载限速',
                  currentKbps: settings.downLimitKbps,
                  onDone: notifier.setDownLimit,
                ),
              ),
              _Row(
                icon: 'upload',
                title: '上传限速',
                subtitle: '0 表示不限速，单位 Mbps',
                trailing: _ValuePill(formatLimitSpeed(settings.upLimitKbps)),
                onTap: () => _editLimit(
                  context,
                  title: '上传限速',
                  currentKbps: settings.upLimitKbps,
                  onDone: notifier.setUpLimit,
                ),
              ),
              _Row(
                icon: 'zap',
                title: '并发任务数',
                subtitle: '同时进行的传输数量（1–${AppSettingsNotifier.kMaxConcurrency}）',
                trailing: _ValuePill('${settings.concurrency}'),
                onTap: () => _editNumber(
                  context,
                  title: '并发任务数',
                  current: settings.concurrency,
                  onDone: notifier.setConcurrency,
                  max: AppSettingsNotifier.kMaxConcurrency,
                ),
              ),
              _Row(
                icon: 'download',
                title: '单文件分段数',
                subtitle: '一个文件拆成几路并行下载（1 = 不分段，默认 4）',
                trailing: _ValuePill('${settings.downloadSegments}'),
                onTap: () => _editNumber(
                  context,
                  title: '单文件分段数',
                  current: settings.downloadSegments,
                  onDone: notifier.setDownloadSegments,
                  min: 1,
                  max: AppSettingsNotifier.kMaxDownloadSegments,
                ),
              ),
            ],
          ),
        ),
        _GroupLabel('行为'),
        _Card(
          child: Column(
            children: [
              _Row(
                icon: 'cloud',
                title: '后台保持传输',
                subtitle: '关闭窗口后继续下载',
                trailing: OlSwitch(value: settings.backgroundTransfer, small: true, onChanged: notifier.setBackgroundTransfer),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 限速编辑：输入单位是 **Mbps（带宽口径）**，内部仍以 KB/s 存储。
  ///
  /// 1 Mbps = 1000 Kbps = 125 KB/s。显示与输入都用 Mbps，用户不必心算字节率。
  Future<void> _editLimit(
    BuildContext context, {
    required String title,
    required int currentKbps,
    required ValueChanged<int> onDone,
  }) async {
    final mbps = limitMbps(currentKbps);
    final controller = TextEditingController(
      text: currentKbps <= 0 ? '0' : (mbps == mbps.roundToDouble() ? '${mbps.round()}' : mbps.toStringAsFixed(1)),
    );
    final value = await showOlDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(hintText: '0 表示不限', suffixText: 'Mbps'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('取消')),
          TextButton(
            onPressed: () {
              final raw = double.tryParse(controller.text.trim()) ?? 0;
              final mbpsValue = raw < 0 ? 0.0 : raw;
              Navigator.of(dialogContext).pop(limitKbpsFromMbps(mbpsValue));
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null) onDone(value);
  }

  Future<void> _editNumber(
    BuildContext context, {
    required String title,
    required int current,
    required ValueChanged<int> onDone,
    int min = 1,
    int max = 1024 * 1024,
  }) async {
    final controller = TextEditingController(text: '$current');
    final value = await showOlDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(hintText: '$min – $max'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop((int.tryParse(controller.text.trim()) ?? min).clamp(min, max).toInt()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null) onDone(value);
  }
}

class _ValuePill extends StatelessWidget {
  final String text;
  const _ValuePill(this.text);

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(6), border: Border.all(color: p.line2)),
      child: Text(text, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: p.ink2)),
    );
  }
}

class _PlaybackSection extends ConsumerWidget {
  const _PlaybackSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final notifier = ref.watch(appSettingsProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHead(title: '播放与预览', subtitle: '断点续播、自动播放与默认倍速'),
        _Card(
          child: Column(
            children: [
              _Row(
                icon: 'clock',
                title: '断点续播',
                subtitle: '记住上次播放位置',
                trailing: OlSwitch(value: settings.resumePlayback, small: true, onChanged: notifier.setResumePlayback),
              ),
              _Row(
                icon: 'play',
                title: '自动播放下一集',
                subtitle: '同目录视频按顺序连播',
                trailing: OlSwitch(value: settings.autoPlayNext, small: true, onChanged: notifier.setAutoPlayNext),
              ),
              _Row(
                icon: 'zap',
                title: '默认倍速',
                subtitle: '播放器首次打开时使用',
                trailing: _ValuePill('${settings.playbackSpeed.toStringAsFixed(1)}×'),
                onTap: () => _pickSpeed(context, notifier, settings.playbackSpeed),
              ),
              _Row(
                icon: 'film',
                title: '优先直连播放',
                subtitle: '边下边播，不落地缓存',
                trailing: Text('固定', style: TextStyle(fontSize: 9.5, color: context.ol.ink4)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _pickSpeed(BuildContext context, AppSettingsNotifier notifier, double current) async {
    final value = await showModalBottomSheet<double>(
      sheetAnimationStyle: AnimationStyle.noAnimation,
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final speed in const [0.75, 1.0, 1.25, 1.5, 2.0])
              ListTile(
                dense: true,
                title: Text('${speed.toStringAsFixed(2)}×', style: const TextStyle(fontSize: 12.5)),
                trailing: speed == current ? const OlIcon('check', size: 14, color: OlTokens.sky600) : null,
                onTap: () => Navigator.of(sheetContext).pop(speed),
              ),
          ],
        ),
      ),
    );
    if (value != null) notifier.setPlaybackSpeed(value);
  }
}
