import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/frame.dart';
import '../../app/providers.dart';
import '../../core/app_info.dart';
import '../../core/sidecar/sidecar_controller.dart';
import '../../core/sidecar/sidecar_state.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/ol_controls.dart';
import '../../core/widgets/ol_icon.dart';
import '../sources/sources_controller.dart';

/// 设置侧栏（设计稿 D8 `.nav`）。
///
/// 设计稿的导航是 5 项：**通用 / 存储源 / 传输 / 播放 / 关于**，
/// 存储源带一个数量徽标，底部是版本与许可说明。
///
/// 0.5.0 之前这里是「下载目录 / 传输 / 播放与预览 / 外观 / 关于与更新」
/// 加两个外链（引擎状态、存储源），与稿面结构不符，现按稿重划：
/// - 通用：下载目录 + 外观 + 引擎状态合并到这一个分区
/// - 存储源：从独立页并入设置，成为一个分区
class SettingsSidebar extends ConsumerWidget {
  final String active;
  final ValueChanged<String>? onSelect;
  const SettingsSidebar({super.key, required this.active, this.onSelect});

  /// 分区定义：[键, 标题, 图标, 路由]。
  ///
  /// 图标取自设计稿：通用是齿轮、存储源是数据库、传输是下载、播放是播放框、
  /// 关于是信息圈。齿轮在现有图标库里没有，用 `settings` 代替。
  static const items = <List<String>>[
    ['general', '通用', 'settings', '/settings/general'],
    ['sources', '存储源', 'server', '/settings/sources'],
    ['transfer', '传输', 'arrow-down', '/settings/transfer'],
    ['playback', '播放', 'play', '/settings/playback'],
    ['about', '关于', 'info', '/settings/about'],
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final session = ref.watch(sessionProvider);
    final sidecar = ref.watch(sidecarProvider);
    // 存储源数量徽标（设计稿 `.nav-i .n`）。
    final sourceCount = ref.watch(sourcesProvider).valueOrNull?.length ?? 0;

    void openSection(String key, String route) {
      onSelect?.call(key);
      context.go(route);
    }

    return Container(
      // 设计稿 D8：侧栏 216、padding 18/12。
      width: 216,
      decoration: BoxDecoration(
        color: p.card,
        border: Border(right: BorderSide(color: p.line)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 12),
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
              badge: item[0] == 'sources' && sourceCount > 0 ? sourceCount : 0,
              active: active == item[0],
              onTap: () => openSection(item[0], item[3]),
            ),
          const Spacer(),
          // 设计稿 `.nav-b`：版本 + 内核版本 + 许可，三行。
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Text(
              '${AppInfo.shortLabel} ${AppInfo.version}\n'
              '内嵌 OpenList ${AppInfo.shortVersion(sidecar.engineVersion ?? session.site?.version)}\n'
              'AGPL-3.0 · 源码公开',
              style: TextStyle(fontSize: 10, height: 1.6, color: p.ink4),
            ),
          ),
        ],
      ),
    );
  }
}

class _SideRow extends StatelessWidget {
  final String icon;
  final String label;
  final bool active;
  final int badge;
  final VoidCallback onTap;

  const _SideRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          // 设计稿 D8 `.nav-i`：padding 9/10、圆角 9、12.5/600。
          margin: const EdgeInsets.only(bottom: 1),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: active ? const Color(0xFFEAF8FE) : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            children: [
              OlIcon(icon, size: 15, color: active ? const Color(0xFF08799F) : p.ink3),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                    color: active ? const Color(0xFF08799F) : p.ink2,
                  ),
                ),
              ),
              // 徽标：设计稿 `.n` 10/800，底 #EDF2F8；选中时白底蓝字。
              if (badge > 0)
                Container(
                  constraints: const BoxConstraints(minWidth: 18),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: active ? p.card : const Color(0xFFEDF2F8),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    badge > 999 ? '999+' : '$badge',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: active ? const Color(0xFF08799F) : p.ink3,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
