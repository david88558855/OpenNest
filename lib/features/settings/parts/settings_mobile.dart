part of '../settings_page.dart';

// A6 · Android「我的」列表与分区页

// ---------------------------------------------------------------------------
// A6 · Android 我的
// ---------------------------------------------------------------------------

/// A6 分区页：带返回的分区详情（v2.2）。
class _MobileSectionPage extends ConsumerWidget {
  final String tab;
  const _MobileSectionPage({required this.tab});

  // 0.5.0：分区按设计稿 D8 重划为 通用 / 存储源 / 传输 / 播放 / 关于。
  static const _titles = {
    'general': '通用',
    'sources': '存储源',
    'transfer': '传输',
    'playback': '播放',
    'about': '关于',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    return AppFrame(
      navIndex: 2,
      showNav: false,
      // v2.5：系统返回先回「我的」，再按才退出应用。
      handleBack: true,
      onBack: () async {
        context.go('/settings');
        return true;
      },
      child: ColoredBox(
        color: p.card,
        child: Column(
          children: [
            SizedBox(
              height: 54,
              child: Row(
                children: [
                  OlIconButton(icon: 'chev-l', size: 34, iconSize: 18, onTap: () => context.go('/settings')),
                  const SizedBox(width: 2),
                  Text(
                    _titles[tab] ?? '设置',
                    style: TextStyle(fontSize: 17, letterSpacing: -0.4, fontWeight: FontWeight.w800, color: p.ink),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                child: _SectionBody(section: tab),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileSettings extends ConsumerWidget {
  const _MobileSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    return ColoredBox(
      color: p.card,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: OlGap.pageMobile),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 0.5.0：分区按设计稿 D8 重划为 通用 / 存储源 / 传输 / 播放 / 关于。
                _MobileGroup(
                  title: '设置',
                  children: [
                    _MobileTile(
                      icon: 'settings',
                      label: '通用',
                      value: '下载目录 / 引擎状态',
                      onTap: () => context.go('/settings/general'),
                    ),
                    _MobileTile(
                      icon: 'database',
                      label: '存储源',
                      value: '添加 / 测试 / 删除',
                      onTap: () => context.go('/settings/sources'),
                    ),
                    _MobileTile(icon: 'arrow-down', label: '传输', value: '并发 / 限速', onTap: () => context.go('/settings/transfer')),
                    _MobileTile(icon: 'play', label: '播放', value: '续播 / 自动播放 / 倍速', onTap: () => context.go('/settings/playback')),
                    _MobileTile(icon: 'info', label: '关于', value: AppInfo.version, onTap: () => context.go('/settings/about')),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileGroup extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _MobileGroup({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 10, 2, 6),
          child: Text(
            title,
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1, color: p.ink4),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: p.line2),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _MobileTile extends StatelessWidget {
  final String icon;
  final String label;
  final String value;
  final VoidCallback onTap;
  const _MobileTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return InkWell(
      onTap: onTap,
      child: Container(
        // v2.3：行高 50 → 58，图标与字号同步放大，避免文字被裁。
        height: 58,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.line2))),
        child: Row(
          children: [
            OlIcon(icon, size: 18, color: p.ink3),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
            if (value.isNotEmpty)
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 11, color: p.ink4),
                ),
              ),
            const SizedBox(width: 6),
            OlIcon('chev-r', size: 15, color: p.ink4),
          ],
        ),
      ),
    );
  }
}
