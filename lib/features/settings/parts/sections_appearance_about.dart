part of '../settings_page.dart';

// 外观 / 关于分区（主题、版本、项目主页）
// ---------------------------------------------------------------------------
// 外观
// ---------------------------------------------------------------------------
class _AppearanceSection extends ConsumerWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 0.4.0：主题切换已彻底移除，全局只有一套浅色主题，这里不再提供任何入口。
        // 0.5.0：并入「通用」分区后不再自带标题，改为区块标题 + 子分组。
        const _GroupHead(
          title: '外观',
          subtitle: '统一浅色主题 · 不支持切换',
        ),
        _GroupLabel('列表'),
        _Card(
          child: Column(
            children: [
              _Row(
                icon: 'panel',
                title: '紧凑列表',
                subtitle: '行高 36px，单屏显示更多',
                trailing: Text('固定 44px', style: TextStyle(fontSize: 9.5, color: p.ink4)),
              ),
              _Row(
                icon: 'image',
                title: '显示缩略图',
                subtitle: '图片与视频封面预览',
                trailing: Text('自动', style: TextStyle(fontSize: 9.5, color: p.ink4)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

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
              // v1.0.28：关于页只保留「项目主页」，其余（客户端版本 / 服务端 /
              // 数据目录 / 检查更新 / 退出登录）已移除。
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
