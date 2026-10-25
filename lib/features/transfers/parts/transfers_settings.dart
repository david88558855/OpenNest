part of '../transfers_page.dart';

// 右侧传输设置面板（限速 / 并发 / 时段 / 开关）
// ---------------------------------------------------------------------------
// 右侧设置面板（W3 · tright 250）
// ---------------------------------------------------------------------------
class _TransferSettings extends ConsumerWidget {
  const _TransferSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final settings = ref.watch(appSettingsProvider);
    final profile = ref.watch(sessionProvider).profile;
    final notifier = ref.watch(appSettingsProvider.notifier);

    return Container(
      decoration: BoxDecoration(
        color: p.surfaceAlt,
        border: Border(left: BorderSide(color: p.line2)),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        children: [
          Row(
            children: [
              Text('传输设置', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 1, color: p.ink4)),
              const Spacer(),
              OlIcon('settings', size: 13, color: p.ink4),
            ],
          ),
          const SizedBox(height: 8),
          _LimitRow(
            label: '下载限速',
            value: settings.downLimitKbps,
            unit: 'KB/s',
            onTap: () => _editLimit(
              context,
              title: '下载限速',
              current: settings.downLimitKbps,
              onDone: notifier.setDownLimit,
            ),
          ),
          _LimitRow(
            label: '上传限速',
            value: settings.upLimitKbps,
            unit: 'KB/s',
            onTap: () => _editLimit(
              context,
              title: '上传限速',
              current: settings.upLimitKbps,
              onDone: notifier.setUpLimit,
            ),
          ),
          _LimitRow(
            label: '并发任务数',
            value: settings.concurrency,
            unit: '个',
            onTap: () => _editLimit(
              context,
              title: '并发任务数',
              current: settings.concurrency,
              onDone: notifier.setConcurrency,
              max: 8,
            ),
          ),
          const SizedBox(height: 12),
          Text('完成后', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: p.ink4)),
          _SwitchRow(label: '任务完成通知', value: settings.trayNotify, onChanged: notifier.setTrayNotify),
          _SwitchRow(
            label: '后台保持传输',
            value: settings.backgroundTransfer,
            onChanged: notifier.setBackgroundTransfer,
          ),
          const SizedBox(height: 12),
          Text('下载位置', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: p.ink4)),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () => showDownloadDirDialog(context, ref),
            child: Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: p.card,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: p.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile == null
                        ? '未连接服务器'
                        : (ref.read(serverStoreProvider).readDownloadDir(profile.id) ?? '默认目录（按实例隔离）'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: p.ink2),
                  ),
                  const SizedBox(height: 4),
                  Text('点击更改', style: TextStyle(fontSize: 8.5, color: p.ink4)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OlGhostButton(
                  label: '暂停全部',
                  height: 28,
                  fontSize: 10,
                  onTap: () => ref.read(transfersProvider.notifier).pauseAll(),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OlSoftButton(
                  label: '打开目录',
                  height: 28,
                  onTap: () async {
                    if (profile == null || !Platform.isWindows) return;
                    final dir = await resolveDownloadDir(ref, profile);
                    try {
                      await Process.run('explorer', [dir]);
                    } catch (_) {
                      if (context.mounted) olToast(context, '无法打开目录：$dir', error: true);
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _editLimit(
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
          decoration: const InputDecoration(hintText: '0 表示不限速'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('取消')),
          TextButton(
            onPressed: () {
              final parsed = int.tryParse(controller.text.trim()) ?? 0;
              Navigator.of(dialogContext).pop(parsed.clamp(0, max).toInt());
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null) onDone(value);
  }
}

class _LimitRow extends StatelessWidget {
  final String label;
  final int value;
  final String unit;
  final VoidCallback onTap;
  const _LimitRow({required this.label, required this.value, required this.unit, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.line2))),
        child: Row(
          children: [
            Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: p.ink2)),
            const Spacer(),
            Container(
              height: 26,
              constraints: const BoxConstraints(minWidth: 58),
              padding: const EdgeInsets.symmetric(horizontal: 7),
              decoration: BoxDecoration(
                color: p.card,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: p.line),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$value', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: p.ink)),
                  const SizedBox(width: 3),
                  Text(unit, style: TextStyle(fontSize: 8.5, color: p.ink4)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchRow({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.line2))),
      child: Row(
        children: [
          Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: p.ink2)),
          const Spacer(),
          OlSwitch(value: value, small: true, onChanged: onChanged),
        ],
      ),
    );
  }
}
