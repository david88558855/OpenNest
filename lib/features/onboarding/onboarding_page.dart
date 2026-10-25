import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/frame.dart';
import '../../app/providers.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/ol_controls.dart';
import '../../core/widgets/ol_dialogs.dart';
import '../../core/widgets/ol_icon.dart';
import '../boot/boot_entry.dart';
import '../sources/share_link.dart';

part 'parts/onboarding_desktop.dart';
part 'parts/onboarding_mobile.dart';

/// 首启空状态（效果图 D1 桌面 / M1 移动）。
///
/// 免账户产品没有登录页，首屏唯一动作是「连接第一个存储」：
/// 品牌栏 + 协议卡片 + 分享链接导入 + 信任声明 + 稍后再说。
/// 只在「无存储源且没点过稍后再说」时由启动页导航进来。
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final TextEditingController _share = TextEditingController();

  @override
  void dispose() {
    _share.dispose();
    super.dispose();
  }

  void _openDriver(String? driver) {
    if (driver == null || driver.isEmpty) {
      context.push('/sources/add');
      return;
    }
    // 驱动名里可能带空格（如 `Onedrive Sharelink`），统一交给 Uri 编码。
    context.push(Uri(path: '/sources/add', queryParameters: {'driver': driver}).toString());
  }

  void _importShare() {
    final text = _share.text.trim();
    if (text.isEmpty) {
      olToast(context, '先粘贴分享链接，再点导入', error: true);
      return;
    }
    final link = parseShareLink(text);
    if (link == null) {
      olToast(context, '认不出这条分享链接，请手动选择存储类型', error: true);
      context.push('/sources/add');
      return;
    }
    _share.clear();
    context.push(
      Uri(path: '/sources/add', queryParameters: {'driver': link.driver, ...link.values}).toString(),
    );
  }

  Future<void> _skip() async {
    // 记住「跳过」：下次启动直接进文件页，不再回到欢迎页。
    await ref.read(prefsProvider).setBool(kOnboardDoneKey, true);
    ref.read(bootEntryProvider.notifier).state = BootEntry.files;
    if (mounted) context.go('/files');
  }

  @override
  Widget build(BuildContext context) {
    if (context.isNarrow) {
      // 移动端口图是深色渐变，状态栏图标必须反白。
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: olDarkSystemBars,
        child: AppFrame(
          showNav: false,
          showTitleBar: false,
          edgeToEdge: true,
          child: _MobileOnboarding(
            share: _share,
            onDriver: _openDriver,
            onImport: _importShare,
            onSkip: _skip,
          ),
        ),
      );
    }
    return AppFrame(
      showNav: false,
      showTitleBar: true,
      child: _DesktopOnboarding(
        share: _share,
        onDriver: _openDriver,
        onImport: _importShare,
        onSkip: _skip,
      ),
    );
  }
}

/// 协议卡片的数据形状（桌面 8 张 / 移动 5 张共用）。
class _Proto {
  final String? driver;
  final String title;
  final String desc;
  final String icon;
  final Color bg;
  final Color fg;

  const _Proto(this.driver, this.title, this.desc, this.icon, this.bg, this.fg);
}

const _skyBg = Color(0xFFEAF8FE);
const _skyFg = Color(0xFF0EA5E9);

const List<_Proto> _desktopProtocols = [
  _Proto('Local', '本地存储', '此设备上的目录', 'hard-drive', _skyBg, _skyFg),
  _Proto('WebDav', 'WebDAV', 'Nextcloud · 群晖 · AList', 'cloud', _skyBg, _skyFg),
  _Proto('S3', 'S3 对象存储', 'MinIO · 阿里云 OSS · AWS', 'database', Color(0xFFF0EDFF), Color(0xFF7C5CFC)),
  _Proto('Sftp', 'SFTP', 'Linux 服务器', 'server', _skyBg, _skyFg),
  _Proto('FTP', 'FTP · FTPS', '传统服务器', 'arrow-up', _skyBg, _skyFg),
  _Proto('SMB', 'SMB', 'Windows · 局域网共享', 'wifi', _skyBg, _skyFg),
  _Proto('OpenList', '远程 OpenList', '级联已有 AList · OpenList', 'link', Color(0xFFE8FBF3), Color(0xFF0E9F6E)),
  _Proto(null, '更多类型', '云盘 · 70+ 驱动', 'folder', Color(0xFFFFF6E8), Color(0xFFF97316)),
];

const List<_Proto> _mobileProtocols = [
  _Proto('Local', '本地存储', '此设备上的目录', 'hard-drive', _skyBg, _skyFg),
  _Proto('WebDav', 'WebDAV', 'Nextcloud · 群晖 · AList', 'cloud', _skyBg, _skyFg),
  _Proto('S3', 'S3 对象存储', 'MinIO · 阿里云 OSS · AWS', 'database', Color(0xFFF0EDFF), Color(0xFF7C5CFC)),
  _Proto('Sftp', 'SFTP · FTP · SMB', 'Linux 服务器 / 局域网共享', 'server', Color(0xFFE8FBF3), Color(0xFF0E9F6E)),
  _Proto(null, '更多类型', '云盘 · 分享链接 · 远程 OpenList', 'folder', Color(0xFFFFF6E8), Color(0xFFF97316)),
];
