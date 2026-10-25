import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/frame.dart';
import '../../app/providers.dart';
import '../../core/app_info.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/ol_controls.dart';
import '../../core/widgets/ol_icon.dart';

/// W6 设置侧栏（v1.0.14：设置与服务器管理都是独立的一级页面）。
///
/// 结构：返回 → 设置分区（下载目录 / 传输 / 播放与预览 / 外观 / 关于与更新）
/// → 服务器管理（跳到独立页面，不是设置分区）。
/// 两端都有自己的返回，互不嵌套：设置不再"挂在服务器管理下面"，
/// 服务器管理页也不再带设置导航。
class SettingsSidebar extends ConsumerWidget {
  final String active;
  final ValueChanged<String>? onSelect;
  const SettingsSidebar({super.key, required this.active, this.onSelect});

  static const items = <List<String>>[
    ['download', '下载目录', 'download', '/settings/download'],
    ['transfer', '传输', 'arrow-down', '/settings/transfer'],
    ['playback', '播放与预览', 'play', '/settings/playback'],
    ['appearance', '外观', 'sun', '/settings/appearance'],
    ['about', '关于与更新', 'info', '/settings/about'],
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final session = ref.watch(sessionProvider);

    void openSection(String key, String route) {
      onSelect?.call(key);
      context.go(route);
    }

    return Container(
      width: 204,
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(right: BorderSide(color: p.line2)),
      ),
      padding: const EdgeInsets.fromLTRB(9, 4, 9, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 独立页面必备的出口
          _SideRow(icon: 'chev-l', label: '返回', onTap: () => goBackOrFiles(context)),
          const OlSectionLabel('设置'),
          for (final item in items)
            _SideRow(
              icon: item[2],
              label: item[1],
              active: active == item[0],
              onTap: () => openSection(item[0], item[3]),
            ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            child: Divider(height: 1),
          ),
          // 引擎状态是设置分区（不再有独立的服务器管理页）
          _SideRow(icon: 'server', label: '引擎状态', active: active == 'servers', onTap: () => context.go('/settings/servers')),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
            child: Text(
              // v1.0.20：Windows 的配置写在 <主程序目录>/userdata/prefs.json，
              // 目录搬走配置跟着走；目录不可写时才是系统存储。
              '${AppInfo.shortLabel}\n'
              '${AppInfo.shortVersion(session.profile?.version ?? session.site?.version)} · ${_platformLabel()}\n'
              '${ref.watch(prefsProvider).isPortable ? '便携数据 · userdata/' : '系统存储（程序目录不可写）'}',
              style: TextStyle(fontSize: 8.5, height: 1.7, color: p.ink4),
            ),
          ),
        ],
      ),
    );
  }

  String _platformLabel() {
    if (Platform.isWindows) return 'Windows x64';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isLinux) return 'Linux';
    return Platform.operatingSystem;
  }
}

class _SideRow extends StatelessWidget {
  final String icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _SideRow({required this.icon, required this.label, required this.onTap, this.active = false});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 31,
          margin: const EdgeInsets.only(bottom: 1),
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            color: active ? p.navOnBg : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              OlIcon(icon, size: 15, color: active ? OlTokens.sky600 : p.navIcon),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: active ? p.navOn : p.nav),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
