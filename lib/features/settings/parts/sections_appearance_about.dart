part of '../settings_page.dart';

// 关于分区（项目链接、版本与许可）
// ---------------------------------------------------------------------------
class _AboutSection extends ConsumerWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHead(title: '关于与更新', subtitle: '项目链接'),
        _Card(
          child: Column(
            children: [
              // 0.5.0：版本号从设置侧栏底部移到「关于」分区 ——
              // 版本信息归到一处，侧栏只留导航。
              _Row(
                icon: 'info',
                title: '版本',
                subtitle: '${AppInfo.shortLabel} ${AppInfo.version}',
              ),
              _Row(
                icon: 'external',
                title: '项目主页',
                subtitle: 'github.com/david88558855/OpenNest',
                trailing: const OlIcon('chev-r', size: 13, color: OlTokens.sky600),
                onTap: () => launchUrl(
                  Uri.parse('https://github.com/david88558855/OpenNest'),
                  mode: LaunchMode.externalApplication,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '第三方程式库版权归各自作者所有；OpenList 品牌素材归 OpenList Team。',
          style: TextStyle(fontSize: 9, height: 1.6, color: p.ink4),
        ),
      ],
    );
  }
}
