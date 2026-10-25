import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/frame.dart';
import '../../app/providers.dart';
import '../../core/format.dart';
import '../../core/models/server_profile.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/ol_controls.dart';
import '../../core/widgets/ol_dialogs.dart';
import '../../core/widgets/ol_icon.dart';
import 'server_form.dart';

part 'parts/servers_rail.dart';
part 'parts/servers_row.dart';
part 'parts/servers_mobile.dart';
part 'parts/servers_panels.dart';

class ServersPage extends ConsumerStatefulWidget {
  const ServersPage({super.key});

  @override
  ConsumerState<ServersPage> createState() => _ServersPageState();
}

class _ServersPageState extends ConsumerState<ServersPage> {
  String? _selectedId;
  String _query = '';
  String _filter = 'all';
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 900;
    final body = narrow ? _buildMobile(context) : _buildDesktop(context);
    return AppFrame(showNav: false, child: body);
  }

  List<ServerProfile> _filtered(List<ServerProfile> servers) {
    var list = servers;
    if (_filter == 'ok') {
      list = list.where((e) => e.health == ServerHealth.ok).toList();
    } else if (_filter == 'error') {
      list = list.where((e) => e.health != ServerHealth.ok).toList();
    }
    if (_query.trim().isNotEmpty) {
      final q = _query.trim().toLowerCase();
      list = list.where((e) => e.name.toLowerCase().contains(q) || e.baseUrl.toLowerCase().contains(q)).toList();
    }
    return list;
  }

  /// 点击服务器 = 切换为当前实例，并直接进入它上次浏览的文件夹。
  Future<void> _switchTo(ServerProfile profile, {bool open = true}) async {
    final settings = ref.read(appSettingsProvider);
    if (settings.pauseOnSwitch) {
      await ref.read(transfersProvider.notifier).pauseAll();
    }
    // v2.6：switchTo 内部已负责 setActive + boot + files.attach，
    // 这里不再重复 attach（否则空目录会被连续请求两次）。
    await ref.read(sessionProvider.notifier).switchTo(profile.id);
    if (!context.mounted) return;
    if (!ref.read(sessionProvider).signedIn) {
      // 该实例还没有可用凭据：直接带地址去登录页，而不是留在原地提示一句。
      olToast(context, '「${profile.name}」需要重新登录');
      context.go('/login');
      return;
    }
    if (open) {
      _backToPrevious(context);
    } else {
      olToast(context, '已切换到 ${profile.name}');
    }
  }

  Widget _buildDesktop(BuildContext context) {
    final p = context.ol;
    final serversState = ref.watch(serverListProvider);
    final session = ref.watch(sessionProvider);
    final servers = _filtered(serversState.servers);
    final isNew = _selectedId == 'new';
    final selected = serversState.servers.where((e) => e.id == (_selectedId ?? serversState.activeId)).toList();
    final editing = isNew ? null : (selected.isEmpty ? null : selected.first);

    return Row(
      children: [
        // v2.6：服务器管理不再复用「设置」侧栏，自带返回入口。
        _ServersRail(
          current: session.profile,
          count: serversState.count,
          onBack: () => goBackOrFiles(context),
          onExport: _exportConfig,
          onImport: _importConfig,
        ),
        Expanded(
          child: Container(
            color: p.card,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
            // v1.0.49：页面壳只做组装，四块分别由 _ServerListHeader /
            // _ServerFilterBar / _ServerListBody / _ServerDetailPanel 承担。
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ServerListHeader(onAdd: () => setState(() => _selectedId = 'new')),
                const SizedBox(height: 12),
                _ServerFilterBar(
                  controller: _search,
                  filter: _filter,
                  onQuery: (v) => setState(() => _query = v),
                  onFilter: (v) => setState(() => _filter = v),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _ServerListBody(
                          servers: servers,
                          editingId: editing?.id,
                          onSelect: (id) => setState(() => _selectedId = id),
                          onSwitch: _switchTo,
                        ),
                      ),
                      const SizedBox(width: 11),
                      _ServerDetailPanel(
                        isNew: isNew,
                        editing: editing,
                        onClear: () => setState(() => _selectedId = null),
                        onBackToNew: () => setState(() => _selectedId = 'new'),
                        onSaved: () => setState(() {}),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMobile(BuildContext context) {
    final p = context.ol;
    final serversState = ref.watch(serverListProvider);
    final session = ref.watch(sessionProvider);
    final current = session.profile;
    final others = serversState.servers.where((e) => e.id != current?.id).toList();
    final settings = ref.watch(appSettingsProvider);

    return Container(
      color: p.card,
      child: Column(
        children: [
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                OlIconButton(icon: 'chev-l', size: 30, iconSize: 18, onTap: () => _backToPrevious(context)),
                const SizedBox(width: 6),
                Text('服务器', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: p.ink)),
                const Spacer(),
                Text('${serversState.count} 个 · 不限', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: p.ink4)),
                const SizedBox(width: 8),
                OlIconButton(icon: 'plus', size: 30, iconSize: 15, onTap: () => context.push('/servers/edit/new')),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                if (current != null) _CurrentServerCard(profile: current, signedIn: session.signedIn),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Text('全部服务器', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: p.ink4)),
                    const Spacer(),
                    Text('其他 ${others.length} 个', style: TextStyle(fontSize: 9, color: p.ink4)),
                  ],
                ),
                const SizedBox(height: 8),
                for (final server in others) ...[
                  GestureDetector(
                    // 整卡可点：切换并打开该服务器的文件夹
                    onTap: () => _switchTo(server),
                    child: _MobileServerCard(
                    profile: server,
                    onSwitch: () => _switchTo(server),
                    onEdit: () => context.push('/servers/edit/${server.id}'),
                    onDelete: () async {
                      final confirmed = await olConfirm(
                        context,
                        title: '删除「${server.name}」',
                        message: '只移除本地配置与凭据，不影响服务端数据。',
                        confirm: '删除',
                        danger: true,
                      );
                      if (!confirmed) return;
                      await ref.read(serverListProvider.notifier).remove(server.id);
                      if (context.mounted) olToast(context, '已删除 ${server.name}');
                    },
                  ),
                  ),
                  const SizedBox(height: 8),
                ],
                GestureDetector(
                  onTap: () => context.push('/servers/edit/new'),
                  child: Container(
                    height: 46,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: p.isDark ? const Color(0xFF243A52) : const Color(0xFFD8E4EF)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        OlIcon('plus', size: 14, color: OlTokens.sky600),
                        const SizedBox(width: 6),
                        Text('添加服务器', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: const Color(0xFF0A93C4))),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                  decoration: BoxDecoration(
                    color: p.surfaceAlt,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: p.line2),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('切换行为', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: p.ink3)),
                      for (final row in <List<String>>[
                        ['切换时暂停旧任务', 'pause'],
                        ['恢复上次浏览位置', 'browse'],
                      ])
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Row(
                            children: [
                              Text(row[0], style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: p.ink2)),
                              const Spacer(),
                              OlSwitch(
                                small: true,
                                value: row[1] == 'pause'
                                    ? settings.pauseOnSwitch
                                    : (current?.rememberBrowse ?? true),
                                onChanged: (v) async {
                                  if (row[1] == 'pause') {
                                    ref.read(appSettingsProvider.notifier).setPauseOnSwitch(v);
                                  } else if (current != null) {
                                    await ref.read(serverListProvider.notifier).upsert(current.copyWith(rememberBrowse: v));
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: OlGhostButton(label: '导出配置', icon: 'external', onTap: _exportConfig)),
                    const SizedBox(width: 8),
                    Expanded(child: OlGhostButton(label: '导入配置', icon: 'download', onTap: _importConfig)),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '删除服务器只移除本地配置，不影响服务端数据；凭据保存在系统 Keystore。',
                  style: TextStyle(fontSize: 8.5, height: 1.6, color: p.ink4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 导出配置（v1.0.43）。
  ///
  /// 改为弹系统保存对话框：由用户决定路径与文件名，取消则什么都不做；
  /// 之前是固定写到应用文档目录，用户既不知道位置也改不了名字。
  Future<void> _exportConfig() async {
    final servers = ref.read(serverListProvider).servers;
    if (servers.isEmpty) {
      olToast(context, '还没有可导出的服务器配置', error: true);
      return;
    }
    final payload = {
      'product': 'OpenNest',
      'version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'servers': servers.map((e) {
        final json = e.toJson();
        json.remove('lastUsed');
        return json;
      }).toList(),
    };
    final content = const JsonEncoder.withIndent('  ').convert(payload);

    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final defaultName = 'openlist-servers-${now.year}${two(now.month)}${two(now.day)}.json';

    String? path;
    try {
      path = await FilePicker.platform.saveFile(
        dialogTitle: '导出服务器配置',
        fileName: defaultName,
        type: FileType.custom,
        allowedExtensions: ['json'],
        // Android 走 SAF，插件拿不到可写路径，必须由它带着内容写入；
        // 桌面端会忽略该参数、只返回路径。
        bytes: utf8.encode(content),
      );
    } catch (e) {
      if (mounted) olToast(context, '无法打开保存对话框：$e', error: true);
      return;
    }
    // 用户取消：不写任何文件
    if (path == null || path.isEmpty) return;

    try {
      // 桌面端 saveFile 只负责选址，落盘要自己做
      if (!Platform.isAndroid) {
        final file = File(path);
        await file.parent.create(recursive: true);
        await file.writeAsString(content, flush: true);
      }
      if (!mounted) return;
      olToast(context, '已导出到 $path');
    } on FileSystemException catch (e) {
      if (!mounted) return;
      olToast(context, '写入失败：${e.osError?.message ?? e.message}', error: true);
    } catch (e) {
      if (!mounted) return;
      olToast(context, '导出失败：$e', error: true);
    }
  }

  Future<void> _importConfig() async {
    final result = await FilePicker.platform.pickFiles(withData: true, type: FileType.custom, allowedExtensions: ['json']);
    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.first.bytes;
    if (bytes == null) return;
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      final rawList = decoded is List ? decoded : (decoded is Map ? decoded['servers'] : null);
      if (rawList is! List) throw const FormatException('缺少 servers');
      var added = 0;
      for (final raw in rawList) {
        if (raw is! Map) continue;
        final profile = ServerProfile.fromJson({
          ...Map<String, dynamic>.from(raw),
          'id': newServerId(),
        });
        // 导入的地址同样要过安全校验，避免把公网 HTTP 实例带进配置。
        if (profile.baseUrl.isEmpty || validateBaseUrl(profile.baseUrl) != null) continue;
        await ref.read(serverListProvider.notifier).upsert(profile.copyWith(health: ServerHealth.unknown));
        added++;
      }
      if (!mounted) return;
      olToast(context, added == 0 ? '没有可导入的服务器' : '已导入 $added 个服务器（需重新登录）');
    } catch (_) {
      if (mounted) olToast(context, '配置文件格式不正确', error: true);
    }
  }
}
