part of '../onboarding_page.dart';

// D1 · 桌面首启空状态：430 品牌栏 + 748 主区（8 张协议卡 4 列 + 分享条 + 信任页脚）。

class _DesktopOnboarding extends StatelessWidget {
  final TextEditingController share;
  final void Function(String?) onDriver;
  final VoidCallback onImport;
  final VoidCallback onSkip;

  const _DesktopOnboarding({
    required this.share,
    required this.onDriver,
    required this.onImport,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return ColoredBox(
      color: p.bg,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 效果图窗口内容宽 1178；最小窗口 1024 时左右各留 18 的内边距。
          final width = (constraints.maxWidth - 36).clamp(320.0, 1178.0);
          final height = (constraints.maxHeight - 36).clamp(420.0, 720.0);
          return Center(
            child: Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(color: Color(0x240E3A46), blurRadius: 70, offset: Offset(0, 24)),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  decoration: BoxDecoration(
                    color: p.card,
                    border: Border.all(color: p.line),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(width: 430, child: _BrandPanel()),
                      Expanded(
                        child: _MainPanel(
                          share: share,
                          onDriver: onDriver,
                          onImport: onImport,
                          onSkip: onSkip,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: OlTokens.gradientDusk),
      child: ClipRect(
        child: Stack(
          children: [
            // 右下角光斑：radial-gradient(circle, rgba(56,189,248,.35), transparent 65%)
            Positioned(
              right: -120,
              bottom: -120,
              child: Container(
                width: 340,
                height: 340,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [Color(0x5938BDF8), Color(0x0038BDF8)],
                    stops: [0, 0.65],
                  ),
                ),
              ),
            ),
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(44, 52, 44, 52),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // 0.5.1：统一用品牌母版（白狐 + 紫蓝渐变），替换旧的
                      // 「渐变方块 + layers 线条图标」。
                      const OlMark(size: 46, radius: 13),
                      const SizedBox(width: 12),
                      const Text(
                        'OpenNest',
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 34),
                  Text.rich(
                    TextSpan(
                      style: const TextStyle(fontSize: 30, height: 1.35, fontWeight: FontWeight.w800, color: Colors.white),
                      children: [
                        const TextSpan(text: '无需注册登录\n'),
                        TextSpan(
                          text: '直连你的存储',
                          style: const TextStyle(color: Color(0xFF7FE7D4)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    '安装即用。没有账号、没有登录页，\n连接第一个存储，30 秒开始管理文件。',
                    style: TextStyle(fontSize: 13.5, height: 1.7, color: Color(0xFFC9E4F2)),
                  ),
                  const SizedBox(height: 36),
                  const _FeatRow(
                    icon: 'shield',
                    title: '免账户',
                    desc: '服务端凭据随机生成，仅存本机系统钥匙串',
                  ),
                  const SizedBox(height: 14),
                  const _FeatRow(
                    icon: 'hard-drive',
                    title: '本地 + 远程',
                    desc: '磁盘目录、NAS、对象存储、网盘、远程服务器',
                  ),
                  const SizedBox(height: 14),
                  const _FeatRow(
                    icon: 'layers',
                    title: '85+ 存储驱动',
                    desc: '内嵌 OpenList 引擎，一种界面管理所有存储',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatRow extends StatelessWidget {
  final String icon;
  final String title;
  final String desc;

  const _FeatRow({required this.icon, required this.title, required this.desc});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: const Color(0x1FFFFFFF),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0x38FFFFFF)),
          ),
          child: Center(child: OlIcon(icon, size: 17, color: const Color(0xFF7FE7D4))),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Colors.white),
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: const TextStyle(fontSize: 11.5, height: 1.5, color: Color(0xFFA9CFDF)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MainPanel extends StatelessWidget {
  final TextEditingController share;
  final void Function(String?) onDriver;
  final VoidCallback onImport;
  final VoidCallback onSkip;

  const _MainPanel({
    required this.share,
    required this.onDriver,
    required this.onImport,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(52, 46, 52, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '欢迎使用 OpenNest',
            style: TextStyle(fontSize: 24, height: 1.2, fontWeight: FontWeight.w800, color: p.ink),
          ),
          const SizedBox(height: 8),
          Text(
            '没有账号要注册，也没有密码要登录 —— 添加你的第一个存储即可开始。',
            style: TextStyle(fontSize: 13, height: 1.5, color: p.ink3),
          ),
          const SizedBox(height: 26),
          LayoutBuilder(
            builder: (context, constraints) {
              final cardWidth = ((constraints.maxWidth - 3 * 14) / 4).clamp(120.0, 200.0);
              return Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  for (final proto in _desktopProtocols)
                    SizedBox(
                      width: cardWidth,
                      height: 140,
                      child: _ProtocolCard(proto: proto, onTap: () => onDriver(proto.driver)),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 22),
          _ShareBar(share: share, onImport: onImport),
          const SizedBox(height: 26),
          Row(
            children: [
              const OlIcon('lock', size: 14, color: OlTokens.ok),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  '所有密码与令牌仅保存在本机系统钥匙串，永不上传',
                  style: TextStyle(fontSize: 11.5, color: p.ink3),
                ),
              ),
              const SizedBox(width: 12),
              OlGhostButton(label: '稍后再说', height: 38, onTap: onSkip),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProtocolCard extends StatelessWidget {
  final _Proto proto;
  final VoidCallback onTap;

  const _ProtocolCard({required this.proto, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: p.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: proto.bg, borderRadius: BorderRadius.circular(11)),
                child: Center(child: OlIcon(proto.icon, size: 19, color: proto.fg, strokeWidth: 1.9)),
              ),
              const SizedBox(height: 10),
              Text(
                proto.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13.5, height: 1.2, fontWeight: FontWeight.w800, color: p.ink),
              ),
              const SizedBox(height: 3),
              Text(
                proto.desc,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, height: 1.45, color: p.ink3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShareBar extends StatelessWidget {
  final TextEditingController share;
  final VoidCallback onImport;

  const _ShareBar({required this.share, required this.onImport});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return OlDashedBox(
      radius: 14,
      fill: p.surface,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          const OlIcon('link', size: 18, color: OlTokens.sky600),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: p.card,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: p.line),
              ),
              child: Center(
                child: TextField(
                  controller: share,
                  onSubmitted: (_) => onImport(),
                  style: TextStyle(fontSize: 12.5, color: p.ink),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    hintText: '或粘贴分享链接（含提取码），直接作为存储源导入…',
                    hintStyle: TextStyle(fontSize: 12.5, color: p.ink4),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          OlGhostButton(label: '导入', height: 38, fontSize: 12.5, onTap: onImport),
        ],
      ),
    );
  }
}
