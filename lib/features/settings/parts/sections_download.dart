part of '../settings_page.dart';

// 下载目录分区（按实例选择路径 / 公共目录授权）
// ---------------------------------------------------------------------------
// 存储挂载（只读）
// ---------------------------------------------------------------------------
// ---------------------------------------------------------------------------
// 下载目录（v2.2：独立分区，替代原「存储挂载」入口）
// ---------------------------------------------------------------------------
class _DownloadSection extends ConsumerStatefulWidget {
  const _DownloadSection();

  @override
  ConsumerState<_DownloadSection> createState() => _DownloadSectionState();
}

class _DownloadSectionState extends ConsumerState<_DownloadSection> {
  String? _dir;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final profile = ref.read(sessionProvider).profile;
    if (profile == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final dir = await resolveDownloadDir(ref, profile);
    if (!mounted) return;
    setState(() {
      _dir = dir;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    final profile = ref.watch(sessionProvider).profile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHead(title: '下载目录', subtitle: '下载与断点续传的落盘位置，按实例隔离'),
        _GroupLabel('当前目录'),
        _Card(
          padding: const EdgeInsets.all(11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(9)),
                    child: Center(child: OlIcon('download', size: 15, color: p.ink3)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      profile == null
                          ? '未连接服务器'
                          : (_loading ? '读取中…' : (_dir ?? '默认目录（按实例隔离）')),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10.5, height: 1.5, fontWeight: FontWeight.w600, color: p.ink2),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OlSoftButton(
                      label: '更改目录',
                      icon: 'folder',
                      onTap: profile == null
                          ? null
                          : () async {
                              await showDownloadDirDialog(context, ref);
                              await _load();
                            },
                    ),
                  ),
                  // v2.3：Android 去掉「授权说明」按钮（授权在选目录时按提示完成），
                  // 桌面保留「打开目录」——这是唯一能从设置跳到磁盘的入口。
                  if (!Platform.isAndroid) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: OlGhostButton(
                        label: '打开目录',
                        icon: 'external',
                        onTap: () {
                          final dir = _dir;
                          if (dir == null) return;
                          Process.run('explorer', [dir]);
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        _GroupLabel('其他'),
        _Card(
          child: Column(
            children: [
              _Row(
                icon: 'refresh',
                title: '恢复默认目录',
                subtitle: '清除本实例的自定义目录',
                trailing: Text('重置', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: p.ink3)),
                onTap: profile == null
                    ? null
                    : () async {
                        await ref.read(serverStoreProvider).clearDownloadDir(profile.id);
                        await _load();
                        if (context.mounted) olToast(context, '已恢复默认目录');
                      },
              ),
              _Row(
                icon: 'hard-drive',
                title: '按实例隔离',
                subtitle: '多服务器各自独立目录，避免同名覆盖',
                trailing: Text(profile?.isolatedDownload == true ? '已开启' : '已关闭', style: TextStyle(fontSize: 9.5, color: p.ink4)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
