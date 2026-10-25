import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/frame.dart';
import '../../app/providers.dart';
import '../../core/app_info.dart';
import '../../core/sidecar/sidecar_controller.dart';
import '../../core/sidecar/sidecar_state.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/ol_controls.dart';
import '../../core/widgets/ol_dialogs.dart';
import '../../core/widgets/ol_icon.dart';
import 'download_dir.dart';
import 'settings_sidebar.dart';

part 'parts/settings_common.dart';
part 'parts/sections_servers.dart';
part 'parts/sections_download.dart';
part 'parts/sections_transfer_playback.dart';
part 'parts/sections_appearance_about.dart';
part 'parts/settings_mobile.dart';

/// W6（Windows 设置）/ A6（Android 我的）。
///
/// 账户与存储分开：账户决定登录态，存储只读展示每个挂载点的健康与容量。
/// 管理后台写操作一律跳浏览器（产品基线 02）。
///
/// 分区切换同时做两件事：本地 setState（保证点击即有反馈）+ 同步路由
/// `/settings/<tab>`（保证深链与返回栈正确）。只改 query 时同一路由不会重建，
/// 是 v1.0.5「设置分区点不开」的根因。
class SettingsPage extends ConsumerStatefulWidget {
  final String tab;
  const SettingsPage({super.key, this.tab = 'root'});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late String _tab = widget.tab;

  static const _known = {'servers', 'transfer', 'download', 'playback', 'appearance', 'about'};

  /// 桌面内容区实际渲染的分区：`root` 归一化为外观。
  String get _section => _tab == 'root' ? 'appearance' : _tab;

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.tab != oldWidget.tab) _tab = widget.tab;
  }

  void _select(String tab) {
    if (!_known.contains(tab)) return;
    setState(() => _tab = tab);
    context.go('/settings/$tab');
  }

  @override
  Widget build(BuildContext context) {
    if (context.isNarrow) {
      // A6：/settings 是「我的」列表（tab == 'root'）；分区页带返回。
      // v1.0.14：判定从「tab 名是否等于 servers」改成显式哨兵 root，
      // 否则把默认 tab 换成 appearance 时根列表会被整段跳过（选项全部消失）。
      final showList = _tab == 'root' || _tab == 'servers' || _tab == 'profile' || !_known.contains(_tab);
      if (showList) return const AppFrame(navIndex: 3, handleBack: true, child: _MobileSettings());
      return _MobileSectionPage(tab: _tab);
    }
    return AppFrame(
      showNav: false,
      handleBack: true,
      child: Row(
        children: [
          SettingsSidebar(active: _section, onSelect: _select),
          Expanded(
            child: ColoredBox(
              color: context.ol.card,
              child: SingleChildScrollView(
                // 设计稿 D8 `.main`：padding 24/28，去掉 maxWidth 760 让内容铺满。
                padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
                child: _SectionBody(section: _section),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
