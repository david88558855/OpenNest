part of '../settings_page.dart';

// 外观 / 关于分区（主题、版本、项目主页）
// ---------------------------------------------------------------------------
// 外观
// ---------------------------------------------------------------------------
class _AppearanceSection extends ConsumerWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final notifier = ref.watch(appSettingsProvider.notifier);
    final p = context.ol;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHead(title: '外观', subtitle: '默认跟随系统；播放器始终深色'),
        _GroupLabel('主题'),
        _Card(
          padding: const EdgeInsets.all(11),
          child: Row(
            children: [
              _ThemeCard(
                label: '浅色',
                selected: settings.themeMode == ThemeMode.light,
                gradient: const LinearGradient(colors: [Color(0xFFF4F8FC), Color(0xFFE9F1F8)]),
                onTap: () => notifier.setTheme(ThemeMode.light),
              ),
              const SizedBox(width: 9),
              _ThemeCard(
                label: '深色',
                selected: settings.themeMode == ThemeMode.dark,
                gradient: const LinearGradient(colors: [Color(0xFF0D1A29), Color(0xFF13293B)]),
                onTap: () => notifier.setTheme(ThemeMode.dark),
              ),
              const SizedBox(width: 9),
              _ThemeCard(
                label: '跟随系统',
                selected: settings.themeMode == ThemeMode.system,
                gradient: const LinearGradient(colors: [Color(0xFFF4F8FC), Color(0xFF0D1A29)]),
                onTap: () => notifier.setTheme(ThemeMode.system),
              ),
            ],
          ),
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

class _ThemeCard extends StatelessWidget {
  final String label;
  final bool selected;
  final LinearGradient gradient;
  final VoidCallback onTap;
  const _ThemeCard({required this.label, required this.selected, required this.gradient, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Container(
              height: 54,
              decoration: BoxDecoration(
                gradient: gradient,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: selected ? OlTokens.sky600 : p.line2, width: selected ? 2 : 1),
              ),
              child: selected
                  ? const Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: EdgeInsets.all(5),
                        child: OlIcon('check', size: 12, color: OlTokens.sky600),
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected ? p.ink : p.ink3,
              ),
            ),
          ],
        ),
      ),
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
