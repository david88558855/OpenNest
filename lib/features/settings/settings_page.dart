import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/frame.dart';
import '../../app/providers.dart';
import '../../core/app_info.dart';
import '../../core/i18n/zh.dart';
import '../../core/models/driver_schema.dart';
import '../../core/models/storage_source.dart';
import '../../core/sidecar/engine_password_dialog.dart';
import '../../core/sidecar/sidecar_controller.dart';
import '../../core/sidecar/sidecar_state.dart';
import '../../core/sidecar/source_config_io.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/ol_controls.dart';
import '../../core/widgets/ol_dialogs.dart';
import '../../core/widgets/ol_icon.dart';
import '../sources/sources_controller.dart';
import 'download_dir.dart';
import 'settings_sidebar.dart';

part 'parts/settings_common.dart';
part 'parts/sections_servers.dart';
part 'parts/sections_download.dart';
part 'parts/sections_transfer_playback.dart';
part 'parts/sections_appearance_about.dart';
part 'parts/sections_general.dart';
part 'parts/sections_sources.dart';
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

  /// 旧分区名 → 新分区名。
  static const _aliases = {
    'servers': 'general',
    'download': 'general',
    'appearance': 'general',
    'profile': 'general',
  };

  /// 旧深链（/settings/servers 等）归一化到新分区，避免 404。
  ///
  /// 0.5.0 按设计稿 D8 重划分区后，旧分区名全部并入「通用」。
  static String normalizeTab(String tab) {
    if (tab == 'root') return 'general';
    return _aliases[tab] ?? tab;
  }

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late String _tab = widget.tab;

  // 0.5.0：按设计稿 D8 侧栏重划为 通用 / 存储源 / 传输 / 播放 / 关于。
  // 旧分区名（servers / download / appearance）保留在 _aliases 里做深链兼容，
  // 会被归一化到新分区，不至于 404。
  static const _known = {'general', 'sources', 'transfer', 'playback', 'about'};

  /// 桌面内容区实际渲染的分区：`root` 归一化为「通用」。
  String get _section => SettingsPage.normalizeTab(_tab);

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
      // 0.5.0：'servers' 不再算根列表 —— 移动端点「引擎状态」要能真正进入
      // 引擎分区（此前被拦回列表，是个进不去的死入口）。
      final showList = _tab == 'root' || !_known.contains(_section);
      if (showList) return const AppFrame(navIndex: 3, handleBack: true, child: _MobileSettings());
      return _MobileSectionPage(tab: _section);
    }
    return AppFrame(
      showNav: false,
      handleBack: true,
      child: Row(
        // 0.5.0：Row 默认 crossAxisAlignment 是 center —— 主区 ColoredBox
        // 会被压缩到内容高度并垂直居中，导致「关于」这类短页顶部留出大片空白，
        // 而「传输」这类长页几乎占满，页面之间表现不一致。
        // stretch 让主区撑满可用高度，背景铺满、内容从顶部 padding 起算。
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsSidebar(active: _section, onSelect: _select),
          Expanded(
            // 设计稿 D8 `.body` 背景是 #F8FBFE（浅蓝灰），卡片才是白底。
            child: ColoredBox(
              color: context.ol.surface,
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
