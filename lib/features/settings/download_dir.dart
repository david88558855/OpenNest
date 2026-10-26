import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/models/server_profile.dart';
import '../../core/storage/download_paths.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/ol_controls.dart';
import '../../core/widgets/ol_dialogs.dart';
import '../../core/widgets/ol_icon.dart';

/// Android 11+ 写入公共目录需要「所有文件访问权限」（MANAGE_EXTERNAL_STORAGE）。
/// 通过原生通道查询状态并跳转授权页，避免引入额外权限插件。
class StorageAccess {
  const StorageAccess._();

  static const MethodChannel _channel = MethodChannel('com.opennest.app/storage');

  static Future<bool> hasAllFiles() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('hasAllFilesAccess') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<void> requestAllFiles() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('requestAllFilesAccess');
    } on PlatformException {
      // 用户直接返回，忽略
    } on MissingPluginException {
      // 宿主未实现通道（旧安装包），忽略
    }
  }
}

/// 当前生效的下载目录：用户显式选择的优先，否则用默认规则推导。
///
/// v2.5：路径规则统一收敛到 `core/storage/download_paths.dart`——
/// Android 默认落在公共目录 `/storage/emulated/0/Download/OpenNest`。
/// 这里只保留 WidgetRef 版本方便 UI 调用。
Future<String> resolveDownloadDir(WidgetRef ref, ServerProfile profile) =>
    resolveDownloadDirFor(ref.read(serverStoreProvider), profile);

/// 下载目录弹窗：显示当前目录 / 恢复默认 / 选择目录。
///
/// v2.3：改为**居中对话框**。之前用底部面板（olSheet），在 Android 上会贴在
/// 屏幕最下方、被手势条压住，且与「设置里点一行」的语义不匹配——设置项一律
/// 用居中弹窗，只有文件长按才用底部面板（A7）。
Future<void> showDownloadDirDialog(BuildContext context, WidgetRef ref) async {
  final profile = ref.read(sessionProvider).profile;
  if (profile == null) {
    olToast(context, '请先登录服务器');
    return;
  }
  final path = await resolveDownloadDir(ref, profile);
  final authorized = await StorageAccess.hasAllFiles();
  if (!context.mounted) return;

  final action = await showOlDialog<String>(
    context: context,
    barrierColor: const Color(0x59091424),
    builder: (dialogContext) {
      final p = dialogContext.ol;
      return Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 26, vertical: 24),
        child: Container(
          width: 360,
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: p.line),
            boxShadow: const [BoxShadow(color: Color(0x330B1622), blurRadius: 40, offset: Offset(0, 18))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF8FE),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(child: OlIcon('download', size: 16, color: OlTokens.sky700)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '下载目录',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: p.ink),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${profile.name} · 独立子目录',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: p.ink4),
                        ),
                      ],
                    ),
                  ),
                  OlIconButton(
                    icon: 'x',
                    onTap: () => Navigator.of(dialogContext).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
                decoration: BoxDecoration(
                  color: p.surfaceAlt,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: p.line2),
                ),
                child: Row(
                  children: [
                    OlIcon('folder', size: 15, color: p.ink3),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        path,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, height: 1.5, color: p.ink2),
                      ),
                    ),
                  ],
                ),
              ),
              // 未授权时只给一行提示，不再放「授权说明」按钮（v2.3）。
              if (Platform.isAndroid && !authorized) ...[
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const OlIcon('shield', size: 13, color: Color(0xFFC98106)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '选择公共目录需要「所有文件访问权限」，点「选择目录」时按提示授权即可。',
                        style: TextStyle(fontSize: 10.5, height: 1.6, color: const Color(0xFF8A5B05)),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OlGhostButton(
                      label: '恢复默认',
                      height: 40,
                      onTap: () => Navigator.of(dialogContext).pop('reset'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OlPrimaryButton(
                      label: '选择目录',
                      icon: 'folder',
                      height: 40,
                      onTap: () => Navigator.of(dialogContext).pop('pick'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );

  if (!context.mounted) return;
  switch (action) {
    case 'reset':
      await ref.read(serverStoreProvider).clearDownloadDir(profile.id);
      if (context.mounted) olToast(context, '已恢复默认下载目录');
      break;
    case 'pick':
      await _pick(context, ref, profile);
      break;
  }
}

Future<void> _pick(BuildContext context, WidgetRef ref, ServerProfile profile, {bool afterGrant = false}) async {
  if (Platform.isAndroid && !await StorageAccess.hasAllFiles()) {
    // v1.0.23：授权返回后复查一次并继续选目录，不再让用户重复点两遍
    if (afterGrant) {
      if (context.mounted) {
        olToast(context, '仍未获得「所有文件访问权限」，可稍后在系统设置里授予', error: true);
      }
      return;
    }
    if (!context.mounted) return;
    final go = await olConfirm(
      context,
      title: '需要文件访问权限',
      message: 'Android 11 起，写入公共目录需要「所有文件访问权限」。可以先去授权后重试，或改用应用私有目录（无需授权）。',
      confirm: '去授权',
      icon: 'shield',
    );
    if (!go) return;
    await StorageAccess.requestAllFiles();
    // 系统授权页返回后权限落盘有延迟，等一小会儿再复查
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!context.mounted) return;
    if (await StorageAccess.hasAllFiles()) {
      await _pick(context, ref, profile, afterGrant: true);
    } else {
      olToast(context, '未获得权限，可稍后在系统设置里授予', error: true);
    }
    return;
  }
  // v1.0.22：选择器可能抛 PlatformException / MissingPluginException，
  // 以前会直接冒到未处理异步区，界面上什么都不发生。
  String? picked;
  try {
    picked = await FilePicker.platform.getDirectoryPath(dialogTitle: '选择下载目录');
  } catch (error) {
    if (context.mounted) olToast(context, '打开目录选择器失败：$error', error: true);
    return;
  }
  if (picked == null || picked.isEmpty) return;
  // 选完立刻验证可写，避免把不可写路径存下来（之后每次下载都静默回退）
  try {
    await Directory(picked).create(recursive: true);
    final probe = File('$picked${Platform.pathSeparator}.ol_write_test');
    await probe.writeAsString('ok', flush: true);
    await probe.delete();
  } catch (error) {
    if (context.mounted) olToast(context, '该目录不可写，请换一个：$error', error: true);
    return;
  }
  await ref.read(serverStoreProvider).saveDownloadDir(profile.id, picked);
  if (context.mounted) olToast(context, '下载目录已更新');
}

/// 设置页（移动）里的一行：下载目录 + 状态。
class DownloadDirTile extends ConsumerStatefulWidget {
  const DownloadDirTile({super.key});

  @override
  ConsumerState<DownloadDirTile> createState() => _DownloadDirTileState();
}

class _DownloadDirTileState extends ConsumerState<DownloadDirTile> {
  String? _path;
  bool _authorized = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profile = ref.read(sessionProvider).profile;
    if (profile == null) return;
    final path = await resolveDownloadDir(ref, profile);
    final ok = await StorageAccess.hasAllFiles();
    if (!mounted) return;
    setState(() {
      _path = path;
      _authorized = ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    final needsAuth = Platform.isAndroid && !_authorized;
    return InkWell(
      onTap: () async {
        await showDownloadDirDialog(context, ref);
        await _load();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 2),
        child: Row(
          children: [
            OlIcon('download', size: 16, color: needsAuth ? const Color(0xFFB47405) : p.ink3),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('下载目录', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.ink)),
                const SizedBox(height: 2),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 208),
                  child: Text(
                    _path ?? '读取中…',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 9, color: p.ink4),
                  ),
                ),
              ],
            ),
            const Spacer(),
            if (needsAuth)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFFFFF6E5), borderRadius: BorderRadius.circular(4)),
                child: const Text('需授权', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: Color(0xFFB47405))),
              )
            else if (_path != null)
              Text('可用', style: TextStyle(fontSize: 9, color: p.ink4)),
            const SizedBox(width: 4),
            OlIcon('chev-r', size: 13, color: p.ink4),
          ],
        ),
      ),
    );
  }
}

/// 设置页（桌面）里的「下载目录」行。
class DownloadDirLine extends ConsumerStatefulWidget {
  const DownloadDirLine({super.key});

  @override
  ConsumerState<DownloadDirLine> createState() => _DownloadDirLineState();
}

class _DownloadDirLineState extends ConsumerState<DownloadDirLine> {
  String? _path;
  bool _authorized = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profile = ref.read(sessionProvider).profile;
    if (profile == null) return;
    final path = await resolveDownloadDir(ref, profile);
    final ok = await StorageAccess.hasAllFiles();
    if (!mounted) return;
    setState(() {
      _path = path;
      _authorized = ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    final needsAuth = Platform.isAndroid && !_authorized;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('下载目录', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.ink2)),
                    if (needsAuth) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(color: const Color(0xFFFFF6E5), borderRadius: BorderRadius.circular(4)),
                        child: const Text('需授权', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: Color(0xFFB47405))),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _path ?? '读取中…',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 9, color: p.ink4)
                ),
              ],
            ),
          ),
          OlGhostButton(
            label: '更改',
            icon: 'folder',
            onTap: () async {
              await showDownloadDirDialog(context, ref);
              await _load();
            },
          ),
        ],
      ),
    );
  }
}
