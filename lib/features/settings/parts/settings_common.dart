part of '../settings_page.dart';

// 分区路由与通用卡片 / 行 / 分组标签

// ---------------------------------------------------------------------------
// 分区路由
// ---------------------------------------------------------------------------
class _SectionBody extends ConsumerWidget {
  final String section;
  const _SectionBody({required this.section});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (section) {
      case 'transfer':
        return const _TransferSection();
      case 'download':
        return const _DownloadSection();
      case 'playback':
        return const _PlaybackSection();
      case 'about':
        return const _AboutSection();
      case 'appearance':
        return const _AppearanceSection();
      case 'servers':
      default:
        return const _ServersSection();
    }
  }
}

// ---------------------------------------------------------------------------
// 通用块
// ---------------------------------------------------------------------------
class _SectionHead extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? action;
  const _SectionHead({required this.title, required this.subtitle, this.action});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 14.5, letterSpacing: -0.3, fontWeight: FontWeight.w800, color: p.ink)),
                const SizedBox(height: 3),
                Text(subtitle, style: TextStyle(fontSize: 10.5, color: p.ink4)),
              ],
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const _Card({required this.child, this.padding = EdgeInsets.zero});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: padding,
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: p.line2),
      ),
      child: child,
    );
  }
}

class _Row extends StatelessWidget {
  final String icon;
  final String title;
  final String subtitle;
  final Widget trailing;
  final VoidCallback? onTap;

  const _Row({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return MouseRegion(
      cursor: onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.line2))),
          child: Row(
            children: [
              Container(
                width: 23,
                height: 23,
                decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(6)),
                child: Center(child: OlIcon(icon, size: 12, color: p.ink3)),
              ),
              const SizedBox(width: 9),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: p.ink2),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10, color: p.ink4),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // v2.3：trailing 必须限宽并右对齐。之前服务端版本串没有约束，
              // 会把标题列挤到只剩 1 个字宽，整行变成竖排中文。
              Flexible(
                flex: 2,
                child: Align(alignment: Alignment.centerRight, child: trailing),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  final String text;
  const _GroupLabel(this.text);

  @override
  Widget build(BuildContext context) => OlSectionLabel(text);
}
