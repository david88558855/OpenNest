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
                subtitle: '0 表示不限速',
                trailing: _ValuePill('${settings.downLimitKbps} KB/s'),
                onTap: () => _editNumber(
                  context,
                  title: '下载限速',
                  current: settings.downLimitKbps,
                  onDone: notifier.setDownLimit,
                ),
              ),
              _Row(
                icon: 'upload',
                title: '上传限速',
                subtitle: '0 表示不限速',
                trailing: _ValuePill('${settings.upLimitKbps} KB/s'),
                onTap: () => _editNumber(
                  context,
                  title: '上传限速',
                  current: settings.upLimitKbps,
                  onDone: notifier.setUpLimit,
                ),
              ),
              _Row(
                icon: 'zap',
                title: '并发任务数',
                subtitle: '同时进行的传输数量',
                trailing: _ValuePill('${settings.concurrency}'),
                onTap: () => _editNumber(
                  context,
                  title: '并发任务数',
                  current: settings.concurrency,
                  onDone: notifier.setConcurrency,
                  max: 8,
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
                icon: 'wifi',
                title: '仅在 Wi-Fi 下传输',
                subtitle: '移动网络下排队等待',
                trailing: OlSwitch(value: settings.wifiOnly, small: true, onChanged: notifier.setWifiOnly),
              ),
              _Row(
                icon: 'cloud',
                title: '后台保持传输',
                subtitle: '关闭窗口后继续下载',
                trailing: OlSwitch(value: settings.backgroundTransfer, small: true, onChanged: notifier.setBackgroundTransfer),
              ),
              _Row(
                icon: 'anchor',
                title: '切换服务器时暂停旧任务',
                subtitle: '避免多实例抢占带宽',
                trailing: OlSwitch(value: settings.pauseOnSwitch, small: true, onChanged: notifier.setPauseOnSwitch),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _editNumber(
    BuildContext context, {
    required String title,
    required int current,
    required ValueChanged<int> onDone,
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
          decoration: const InputDecoration(hintText: '0 表示不限'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop((int.tryParse(controller.text.trim()) ?? 0).clamp(0, max).toInt()),
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
                subtitle: 'Range 直读，不落地缓存',
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
