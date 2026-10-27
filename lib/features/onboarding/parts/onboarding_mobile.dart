part of '../onboarding_page.dart';

// M1 · 移动端首启空状态：深色渐变头图 + 上浮圆角面板（5 张单列卡 + 分享块 + 页脚）。

class _MobileOnboarding extends StatelessWidget {
  final TextEditingController share;
  final void Function(String?) onDriver;
  final VoidCallback onImport;
  final VoidCallback onSkip;

  const _MobileOnboarding({
    required this.share,
    required this.onDriver,
    required this.onImport,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return ColoredBox(
      color: p.card,
      child: Column(
        children: [
          _MobileBrand(topInset: MediaQuery.paddingOf(context).top),
          Expanded(
            // 效果图用 margin-top:-16 做「面板上浮」；Flutter 的 Container 不支持负
            // margin，这里用位移实现，底部 16px 露出的是同色 Scaffold 底，看不出来。
            child: Transform.translate(
              offset: const Offset(0, -16),
              child: Container(
                decoration: BoxDecoration(
                  color: p.card,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
                  boxShadow: const [
                    BoxShadow(color: Color(0x140E3A46), blurRadius: 24, offset: Offset(0, -6)),
                  ],
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 22, 18, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '添加你的第一个存储',
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: p.ink),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '选择一种存储类型，或粘贴分享链接直接导入',
                            style: TextStyle(fontSize: 11.5, height: 1.5, color: p.ink3),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                        child: Column(
                          children: [
                            for (final proto in _mobileProtocols) ...[
                              _MobileProtocolRow(proto: proto, onTap: () => onDriver(proto.driver)),
                              const SizedBox(height: 9),
                            ],
                            const SizedBox(height: 5),
                            _MobileShare(share: share, onImport: onImport),
                          ],
                        ),
                      ),
                    ),
                    _MobileFoot(onSkip: onSkip),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileBrand extends StatelessWidget {
  final double topInset;

  const _MobileBrand({required this.topInset});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: OlTokens.gradientDusk),
      padding: EdgeInsets.fromLTRB(24, topInset + 12, 24, 30),
      child: ClipRect(
        child: Stack(
          children: [
            Positioned(
              right: -90,
              top: -90,
              child: Container(
                width: 260,
                height: 260,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [Color(0x5238BDF8), Color(0x0038BDF8)],
                    stops: [0, 0.65],
                  ),
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // 0.5.1：统一用品牌母版（白狐 + 紫蓝渐变）。
                    const OlMark(size: 40, radius: 12),
                    const SizedBox(width: 10),
                    const Text(
                      'OpenNest',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text.rich(
                  TextSpan(
                    style: const TextStyle(fontSize: 23, height: 1.32, fontWeight: FontWeight.w800, color: Colors.white),
                    children: [
                      const TextSpan(text: '无需注册登录\n'),
                      TextSpan(
                        text: '直连你的存储',
                        style: const TextStyle(color: Color(0xFF7FE7D4)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '没有账号，没有密码要记。\n连接第一个存储，30 秒开始。',
                  style: TextStyle(fontSize: 12.5, height: 1.6, color: Color(0xFFC9E4F2)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileProtocolRow extends StatelessWidget {
  final _Proto proto;
  final VoidCallback onTap;

  const _MobileProtocolRow({required this.proto, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 62,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: p.line),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: proto.bg, borderRadius: BorderRadius.circular(11)),
              child: Center(child: OlIcon(proto.icon, size: 19, color: proto.fg, strokeWidth: 1.9)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    proto.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: p.ink),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    proto.desc,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10.5, color: p.ink3),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const OlIcon('chev-r', size: 16, color: Color(0xFFC4D5E4), strokeWidth: 2.4),
          ],
        ),
      ),
    );
  }
}

class _MobileShare extends StatelessWidget {
  final TextEditingController share;
  final VoidCallback onImport;

  const _MobileShare({required this.share, required this.onImport});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return OlDashedBox(
      radius: 14,
      fill: p.surface,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const OlIcon('link', size: 13, color: OlTokens.sky600),
              const SizedBox(width: 6),
              const Text(
                '粘贴分享链接直接导入',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF08799F)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 11),
                  decoration: BoxDecoration(
                    color: p.card,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: p.line),
                  ),
                  child: Center(
                    child: TextField(
                      controller: share,
                      onSubmitted: (_) => onImport(),
                      style: TextStyle(fontSize: 12, color: p.ink),
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        hintText: 'https://… （含提取码）',
                        hintStyle: TextStyle(fontSize: 12, color: p.ink4),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OlPrimaryButton(label: '导入', height: 38, fontSize: 12, onTap: onImport),
            ],
          ),
        ],
      ),
    );
  }
}

class _MobileFoot extends StatelessWidget {
  final VoidCallback onSkip;

  const _MobileFoot({required this.onSkip});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 10, 18, 12 + MediaQuery.viewPaddingOf(context).bottom),
      child: Row(
        children: [
          const OlIcon('lock', size: 13, color: OlTokens.ok),
          const SizedBox(width: 6),
          Expanded(
            child: Text('凭据仅存本机钥匙串', style: TextStyle(fontSize: 10.5, color: p.ink3)),
          ),
          OlGhostButton(label: '稍后再说', height: 34, fontSize: 11.5, onTap: onSkip),
        ],
      ),
    );
  }
}
