part of '../settings_page.dart';

// A6 · Android「我的」列表与分区页

// ---------------------------------------------------------------------------
// A6 · Android 我的
// ---------------------------------------------------------------------------

/// A6 分区页：带返回的分区详情（v2.2）。
class _MobileSectionPage extends ConsumerWidget {
  final String tab;
  const _MobileSectionPage({required this.tab});

  static const _titles = {
    'transfer': '传输',
    'download': '下载目录',
    'playback': '播放与预览',
    'appearance': '外观',
    'about': '关于与更新',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    return AppFrame(
      navIndex: 3,
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
    final session = ref.watch(sessionProvider);
    final profile = session.profile;
    return ColoredBox(
      color: p.card,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(OlGap.pageMobile, 10, OlGap.pageMobile, 0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0B2233), Color(0xFF0D3B46)],
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(gradient: OlTokens.gradientBrand, borderRadius: BorderRadius.circular(14)),
                  child: const Center(child: OlIcon('user', size: 22, color: Colors.white)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile?.username ?? '未登录',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        profile == null
                            ? '未连接服务器'
                            : AppInfo.hostWithVersion(
                                profile.displayHost,
                                profile.version ?? session.site?.version,
                              ),
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: Color(0xFF9DB4C8)),
                      ),
                    ],
                  ),
                ),
                OlBadge(
                  label: session.offline ? '离线' : (session.signedIn ? '已连接' : '未登录'),
                  fg: session.offline ? const Color(0xFF5E4A22) : const Color(0xFF0B5C4C),
                  bg: session.offline ? const Color(0xFFFCD9A0) : const Color(0xFF7DD3FC),
                ),
              ],
            ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: OlGap.pageMobile),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _MobileGroup(
                  title: '引擎',
                  children: [
                    _MobileTile(
                      icon: 'server',
                      label: '引擎状态',
                      value: '端口 / 版本 / 日志',
                      onTap: () => context.go('/settings/servers'),
                    ),
                    _MobileTile(
                      icon: 'folder',
                      label: '存储源',
                      value: '添加 / 停用 / 删除',
                      onTap: () => context.push('/sources'),
                    ),
                  ],
                ),
                _MobileGroup(
                  title: '传输与播放',
                  children: [
                    // v2.3：下载目录提到传输设置之上（真机上更常改目录）。
                    _MobileTile(icon: 'download', label: '下载目录', value: '查看 / 更改', onTap: () => context.go('/settings/download')),
                    _MobileTile(icon: 'arrow-down', label: '传输设置', value: '并发 / 限速', onTap: () => context.go('/settings/transfer')),
                    _MobileTile(icon: 'play', label: '播放与预览', value: '续播 / 自动播放 / 倍速', onTap: () => context.go('/settings/playback')),
                  ],
                ),
                _MobileGroup(
                  title: '应用',
                  children: [
                    _MobileTile(icon: 'sun', label: '外观', value: '跟随系统', onTap: () => context.go('/settings/appearance')),
                    _MobileTile(icon: 'info', label: '关于 OpenNest', value: AppInfo.version, onTap: () => context.go('/settings/about')),
                    _MobileTile(
                      icon: 'refresh',
                      label: '重启引擎',
                      value: '',
                      onTap: () async {
                        await ref.read(sidecarProvider.notifier).restart();
                        if (!context.mounted) return;
                        await ref.read(sessionProvider.notifier).retry();
                        if (!context.mounted) return;
                        try {
                          await ref.read(filesProvider.notifier).attach();
                        } catch (_) {}
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${AppInfo.shortLabel} · 安卓 · 接口版本 v4',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 8.5, color: p.ink4),
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
  final bool danger;
  final VoidCallback onTap;
  const _MobileTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    this.danger = false,
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
            OlIcon(icon, size: 18, color: danger ? OlTokens.dangerDeep : p.ink3),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: danger ? OlTokens.dangerDeep : p.ink),
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
