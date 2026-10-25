import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/openlist_api.dart';
import '../../core/format.dart';
import '../../core/models/api_types.dart';
import '../../core/storage/download_paths.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/file_widgets.dart';
import '../../core/widgets/ol_controls.dart';
import '../../core/widgets/ol_dialogs.dart';
import '../../core/widgets/ol_icon.dart';
import '../settings/download_dir.dart';

String _basename(String path) {
  final parts = path.split(RegExp(r'[\\/]'));
  return parts.isEmpty ? path : parts.last;
}

Future<void> pickAndUpload(BuildContext context, WidgetRef ref) async {
  final result = await FilePicker.platform.pickFiles(allowMultiple: true);
  if (result == null) return;
  final paths = result.files.map((e) => e.path).whereType<String>().toList();
  if (paths.isEmpty) return;
  await uploadPaths(context, ref, paths);
}

Future<void> uploadPaths(BuildContext context, WidgetRef ref, List<String> paths) async {
  final dir = ref.read(filesProvider).path;
  if (!ref.read(filesProvider).canWrite) {
    olToast(context, '当前目录没有写入权限', error: true);
    return;
  }
  final transfers = ref.read(transfersProvider.notifier);
  var queued = 0;
  for (final path in paths) {
    final error = await transfers.enqueueUpload(localPath: path, remoteDir: dir, name: _basename(path));
    if (error == null) queued++;
  }
  if (queued > 0) {
    olToast(context, '已加入上传队列 · $queued 个文件');
  }
}

Future<void> createFolder(BuildContext context, WidgetRef ref) async {
  final dir = ref.read(filesProvider).path;
  final name = await olPrompt(
    context,
    title: '新建文件夹',
    message: '将在「${dir == '/' ? '根目录' : dir}」下创建',
    hint: '文件夹名称',
    icon: 'folder-plus',
    confirm: '创建',
  );
  if (name == null || name.trim().isEmpty) return;
  final target = joinPath(dir, name.trim());
  final error = await ref.read(filesProvider.notifier).mutate((api) => api.mkdir(target));
  if (error != null && context.mounted) {
    olToast(context, error, error: true);
  } else if (context.mounted) {
    olToast(context, '已创建 ${name.trim()}');
  }
}

Future<void> renameItem(BuildContext context, WidgetRef ref, FileItem item) async {
  final dir = ref.read(filesProvider).path;
  final name = await olPrompt(
    context,
    title: '重命名',
    hint: '新名称',
    initial: item.name,
    icon: 'edit',
    confirm: '重命名',
  );
  if (name == null || name.trim().isEmpty || name.trim() == item.name) return;
  final source = joinPath(dir, item.name);
  final error = await ref.read(filesProvider.notifier).mutate((api) => api.rename(source, name.trim()));
  if (error != null && context.mounted) {
    olToast(context, error, error: true);
  } else if (context.mounted) {
    olToast(context, '已重命名');
  }
}

Future<void> deleteItems(BuildContext context, WidgetRef ref, List<FileItem> items) async {
  if (items.isEmpty) return;
  final dir = ref.read(filesProvider).path;
  final confirmed = await olConfirm(
    context,
    title: items.length == 1 ? '删除「${items.first.name}」' : '删除 ${items.length} 个项目',
    message: '删除后无法从客户端恢复（服务端回收站策略取决于存储驱动）。',
    confirm: '删除',
    danger: true,
  );
  if (!confirmed) return;
  final error = await ref.read(filesProvider.notifier).mutate((api) => api.remove(dir, items.map((e) => e.name).toList()));
  if (!context.mounted) return;
  if (error != null) {
    olToast(context, error, error: true);
  } else {
    olToast(context, '已删除 ${items.length} 个项目');
    ref.read(filesProvider.notifier).clearSelection();
  }
}

Future<void> moveOrCopyItems(BuildContext context, WidgetRef ref, List<FileItem> items, {required bool move}) async {
  if (items.isEmpty) return;
  final dir = ref.read(filesProvider).path;
  final target = await showOlDialog<String>(
    context: context,
    barrierColor: const Color(0x59091424),
    builder: (_) => _DirPickerDialog(title: move ? '移动到…' : '复制到…', initialPath: dir),
  );
  if (target == null) return;
  if (target == dir) {
    if (context.mounted) olToast(context, '目标目录与当前目录相同', error: true);
    return;
  }
  // 目录不能移动到自身或自己的子目录（服务端会失败，或产生环）。
  for (final item in items) {
    if (!item.isDir) continue;
    final itemPath = joinPath(dir, item.name);
    if (target == itemPath || target.startsWith('$itemPath/')) {
      if (context.mounted) olToast(context, '不能把「${item.name}」移动到它自己的子目录', error: true);
      return;
    }
  }
  final names = items.map((e) => e.name).toList();
  final error = await ref.read(filesProvider.notifier).mutate(
        (api) => move ? api.move(dir, target, names) : api.copy(dir, target, names),
      );
  if (!context.mounted) return;
  if (error != null) {
    olToast(context, error, error: true);
  } else {
    olToast(context, move ? '已移动 ${names.length} 个项目' : '已复制 ${names.length} 个项目');
    ref.read(filesProvider.notifier).clearSelection();
  }
}

/// 本次进程内只提示一次「公共目录未授权」，避免每次下载都弹。
bool _storageHintShown = false;

Future<void> downloadItem(BuildContext context, WidgetRef ref, FileItem item) async {
  // v2.5：默认下载目录改到公共 Download 目录，未授权时会在 ensureDownloadDirFor
  // 里退回应用私有目录——这里显式说明一次，避免用户找不到文件。
  if (Platform.isAndroid && !_storageHintShown) {
    final granted = await StorageAccess.hasAllFiles();
    if (!granted) {
      _storageHintShown = true;
      if (context.mounted) {
        olToast(context, '未授予「所有文件访问权限」，本次保存到应用私有目录；可在 设置 → 下载目录 授权后改用公共 Download 目录');
      }
    }
  }
  final error = await ref.read(transfersProvider.notifier).enqueueDownload(item, ref.read(filesProvider).path);
  if (!context.mounted) return;
  if (error != null) {
    olToast(context, error, error: true);
  } else {
    olToast(context, '已开始下载 ${item.name}');
  }
}

/// 批量下载（v1.0.26 起，v1.0.31 支持文件夹递归）。
///
/// 桌面与移动端共用这一个入口：
///   - 全是文件 → 逐个入队，不弹窗、不逐个 toast（最后汇总一次）；
///   - 含文件夹 → 先扫描目录树（带进度、可取消），再按相对子目录逐个入队，
///     落盘结构与远端一致。
Future<void> downloadItems(BuildContext context, WidgetRef ref, List<FileItem> items) async {
  final notifier = ref.read(transfersProvider.notifier);
  final basePath = ref.read(filesProvider).path;
  final files = items.where((e) => !e.isDir).toList();
  final dirs = items.where((e) => e.isDir).toList();

  if (files.isNotEmpty) {
    for (final item in files) {
      // schedule: false —— 批量入队时不要每加一条就调度一次，
      // 否则 N 个文件会触发 N 次 _pump + N 次落盘。
      await notifier.enqueueDownload(item, basePath, schedule: false);
    }
    await notifier.kick();
    if (context.mounted) olToast(context, '已加入 ${files.length} 个文件');
  }
  if (dirs.isEmpty) return;

  final api = ref.read(sessionProvider).api;
  if (api == null) {
    if (context.mounted) olToast(context, '尚未连接服务器', error: true);
    return;
  }
  await _downloadFolders(context, ref, api, dirs, basePath);
}

/// 单次批量下载的上限，防止误选超大目录把队列撑爆、把服务端打满。
const _maxFolderFiles = 2000;
const _maxFolderDepth = 24;

/// 递归扫描的节流间隔：翻页 80ms、目录切换 40ms。
const _scanPageGap = Duration(milliseconds: 80);
const _scanDirGap = Duration(milliseconds: 40);

/// 扫描得到的一个待入队文件：远端完整路径在扫描时就已经确定。
class _FolderEntry {
  final FileItem item;
  final String remotePath;
  final String subdir;
  const _FolderEntry(this.item, this.remotePath, this.subdir);
}

class _ScanOutcome {
  /// v1.0.37：同时保存 item 与**完整远端路径**。
  /// 之前只存 item + 子目录，入队时用 `item.parent ?? joinPath(basePath, name)` 反推路径，
  /// 而 `item.parent` 在部分服务端为空串/null，回退用的 basePath 又是「浏览目录」而非
  /// 文件所在的子目录 —— 拼出来的 remotePath 少了层级，下载必然 404。
  final List<_FolderEntry> entries = [];
  int skippedDirs = 0;
  int failedDirs = 0;
  bool truncated = false;
  bool cancelled = false;

  int get fileCount => entries.length;
}

/// 扫描若干文件夹，返回所有文件及其相对子目录。
///
/// 用 BFS 逐层 `list`，串行 + 80ms 间隔，避免把服务端打满；
/// 单个目录失败只记数继续，最后汇总。
Future<_ScanOutcome> _scanFolders(
  OpenListApi api,
  List<FileItem> roots,
  String basePath, {
  void Function(int found, int dirs)? onProgress,
  bool Function()? isCancelled,
}) async {
  final outcome = _ScanOutcome();
  final queue = <MapEntry<String, String>>[]; // remotePath → 相对子目录
  for (final dir in roots) {
    // v1.0.37：parent 可能是空串（不是 null），`??` 不会回退，会拼出空的远端路径。
    final parent = dir.parent?.trim();
    final remote = (parent == null || parent.isEmpty) ? joinPath(basePath, dir.name) : parent;
    queue.add(MapEntry(remote, safePathSegment(dir.name)));
  }
  final visited = <String>{};
  var scannedDirs = 0;

  while (queue.isNotEmpty) {
    if (isCancelled?.call() == true) {
      outcome.cancelled = true;
      break;
    }
    if (outcome.fileCount >= _maxFolderFiles) {
      outcome.truncated = true;
      break;
    }
    final entry = queue.removeAt(0);
    if (!visited.add(entry.key)) continue;
    if (entry.value.split('/').length > _maxFolderDepth) {
      outcome.skippedDirs++;
      continue;
    }
    scannedDirs++;

    var page = 1;
    while (true) {
      if (isCancelled?.call() == true) {
        outcome.cancelled = true;
        break;
      }
      List<FileItem> pageItems;
      try {
        final result = await api.list(path: entry.key, page: page, perPage: 100);
        pageItems = result.items;
      } catch (_) {
        outcome.failedDirs++;
        break;
      }
      for (final item in pageItems) {
        if (item.isDir) {
          final childRemote = joinPath(entry.key, item.name);
          queue.add(MapEntry(childRemote, '${entry.value}/${safePathSegment(item.name)}'));
        } else {
          if (outcome.fileCount >= _maxFolderFiles) {
            outcome.truncated = true;
            break;
          }
          // 远端路径在扫描时就按「当前遍历到的目录 + 文件名」确定，不再事后反推
          outcome.entries.add(_FolderEntry(item, joinPath(entry.key, item.name), entry.value));
        }
      }
      onProgress?.call(outcome.fileCount, scannedDirs);
      if (pageItems.length < 100) break;
      page++;
      // 服务端限流的兜底间隔（翻页）
      await Future<void>.delayed(_scanPageGap);
    }
    if (outcome.cancelled || outcome.truncated) break;
    // v1.0.44：目录之间也留间隔。之前只在翻页时等待，深层目录会连续打 list，
    // 服务端一限流就变成「N 个目录读取失败」。
    await Future<void>.delayed(_scanDirGap);
  }
  return outcome;
}

/// 扫描 → 入队，带可取消的进度弹窗。
Future<void> _downloadFolders(
  BuildContext context,
  WidgetRef ref,
  OpenListApi api,
  List<FileItem> dirs,
  // 浏览目录：仅用于「文件夹自身 parent 为空」时拼根路径，透传给 _scanFolders。
  String basePath,
) async {
  var cancelled = false;
  var dialogReady = false;
  var dialogClosed = false;
  final progress = ValueNotifier<(int, int)>((0, 0));
  // 用 rootNavigator 的 Navigator 显式关闭弹窗：只 pop 一次，且带状态守卫。
  // v1.0.33：之前是「设一个 -1 哨兵，让弹窗自己在 build 里 pop」，
  // 每帧都会注册一次 postFrameCallback，pop 次数不受控 —— 会把文件页也弹掉，
  // 表现为「批量下载文件夹 → 界面崩掉 / 跳回登录」。
  final navigator = Navigator.of(context, rootNavigator: true);

  unawaited(showOlDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: const Color(0x59091424),
    builder: (_) => _FolderScanDialog(
      progress: progress,
      onCancel: () {
        cancelled = true;
        // 用户点取消时也负责关掉自己，任何情况下都不会被弹窗卡住
        dialogClosed = true;
        if (navigator.canPop()) navigator.pop();
      },
      onReady: () => dialogReady = true,
    ),
  ));

  _ScanOutcome outcome;
  try {
    outcome = await _scanFolders(
      api,
      dirs,
      basePath,
      isCancelled: () => cancelled,
      onProgress: (found, scannedDirs) => progress.value = (found, scannedDirs),
    );
  } finally {
    // 等弹窗真正挂载（正常一帧内就绪），最多重试 5 帧
    for (var i = 0; i < 5 && !dialogReady; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
    if (!dialogClosed) {
      dialogClosed = true;
      if (dialogReady && context.mounted) {
        await _popScanDialog(navigator);
      }
    }
    // 弹窗正在执行退出动画，此时 dispose 会让 ValueListenableBuilder 访问已释放对象
    unawaited(Future<void>.delayed(
      const Duration(milliseconds: 400),
      progress.dispose,
    ));
  }
  if (!context.mounted) return;

  final notifier = ref.read(transfersProvider.notifier);
  var queued = 0;
  var failed = 0;
  for (final entry in outcome.entries) {
    final error = await notifier.enqueueDownloadInto(
      item: entry.item,
      remotePath: entry.remotePath,
      localSubdir: entry.subdir,
      schedule: false,
    );
    if (error == null) {
      queued++;
    } else {
      failed++;
    }
  }
  await notifier.kick();
  if (!context.mounted) return;

  final parts = <String>['已加入 $queued 个文件'];
  if (outcome.skippedDirs > 0) parts.add('跳过 ${outcome.skippedDirs} 个目录（层级过深）');
  if (outcome.failedDirs > 0) parts.add('${outcome.failedDirs} 个目录读取失败');
  if (failed > 0) parts.add('$failed 个文件入队失败');
  if (outcome.truncated) parts.add('已达 $_maxFolderFiles 个上限，请分批下载');
  if (outcome.cancelled) parts.add('已取消（剩余未处理）');
  olToast(context, parts.join('，'), error: failed > 0 || outcome.failedDirs > 0);
}

/// 关闭扫描弹窗：只 pop 一次，异常吞掉（弹窗可能已被用户关掉）。
Future<void> _popScanDialog(NavigatorState navigator) async {
  try {
    if (navigator.canPop()) navigator.pop();
  } catch (_) {}
}

/// 「正在扫描目录」弹窗：显示已发现文件数与已扫描目录数，可取消。
class _FolderScanDialog extends StatefulWidget {
  final ValueNotifier<(int, int)> progress;
  final VoidCallback onCancel;
  final VoidCallback? onReady;
  const _FolderScanDialog({required this.progress, required this.onCancel, this.onReady});

  @override
  State<_FolderScanDialog> createState() => _FolderScanDialogState();
}

class _FolderScanDialogState extends State<_FolderScanDialog> {
  @override
  void initState() {
    super.initState();
    // 挂载完成后再回报，调用方据此判断「现在 pop 是安全的」
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onReady?.call());
  }

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Dialog(
      backgroundColor: Colors.transparent,
      child: ValueListenableBuilder<(int, int)>(
        valueListenable: widget.progress,
        builder: (context, value, _) => Container(
          width: 360,
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
          decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: p.line)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const OlIcon('folder', size: 14, color: OlTokens.sky600),
                  const SizedBox(width: 8),
                  Text('正在扫描文件夹', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: p.ink)),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '已发现 ${value.$1} 个文件 · 已扫描 ${value.$2} 个目录',
                style: TextStyle(fontSize: 11, color: p.ink3),
              ),
              const SizedBox(height: 6),
              Text(
                '上限 $_maxFolderFiles 个文件、$_maxFolderDepth 层目录',
                style: TextStyle(fontSize: 9.5, color: p.ink4),
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: OlGhostButton(label: '取消', onTap: widget.onCancel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> offlineDownload(BuildContext context, WidgetRef ref) async {
  final dir = ref.read(filesProvider).path;
  final urls = await olPrompt(
    context,
    title: '离线下载',
    message: '每行一个链接，保存到「${dir == '/' ? '根目录' : dir}」。需要服务端已配置 Aria2 / qBittorrent。',
    hint: 'https://example.com/file.iso',
    icon: 'cloud-dl',
    confirm: '添加任务',
    maxLines: 4,
  );
  if (urls == null) return;
  final list = urls.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  if (list.isEmpty) return;
  final error = await ref.read(filesProvider.notifier).mutate(
        (api) => api.addOfflineDownload(urls: list, path: dir),
        refreshAfter: false,
      );
  if (!context.mounted) return;
  if (error != null) {
    olToast(context, error, error: true);
  } else {
    olToast(context, '已提交 ${list.length} 个离线任务');
    ref.read(transfersProvider.notifier).loadServerTasks();
  }
}

Future<String?> signedUrl(WidgetRef ref, FileItem item) async {
  final api = ref.read(sessionProvider).api;
  if (api == null) return null;
  var sign = item.sign;
  final path = item.parent ?? joinPath(ref.read(filesProvider).path, item.name);
  if (sign == null || sign.isEmpty) {
    try {
      final info = await api.get(path);
      sign = info.sign;
    } on ApiException catch (_) {
      return null;
    }
  }
  return api.downloadUrl(path, sign: sign);
}

Future<void> openItem(BuildContext context, WidgetRef ref, FileItem item) async {
  final files = ref.read(filesProvider.notifier);
  final dir = ref.read(filesProvider).path;
  if (item.isDir) {
    await files.open(joinPath(dir, item.name));
    return;
  }
  final kind = kindOf(item.name, false);
  if (kind == FileKind.video || kind == FileKind.audio) {
    final path = item.parent ?? joinPath(dir, item.name);
    context.push('/player?path=${Uri.encodeComponent(path)}&name=${Uri.encodeComponent(item.name)}');
    return;
  }
  await previewItem(context, ref, item);
}

Future<void> previewItem(BuildContext context, WidgetRef ref, FileItem item) async {
  final kind = kindOf(item.name, false);
  final url = await signedUrl(ref, item);
  if (!context.mounted) return;
  if (url == null) {
    olToast(context, '无法获取预览直链', error: true);
    return;
  }
  await showOlDialog<void>(
    context: context,
    barrierColor: const Color(0x8C07111D),
    builder: (dialogContext) {
      final p = dialogContext.ol;
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(28),
        child: Container(
          width: 720,
          constraints: const BoxConstraints(maxHeight: 620),
          decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(18), border: Border.all(color: p.line)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.line2))),
                child: Row(
                  children: [
                    FileGlyph(item: item, size: 24, radius: 7, iconSize: 13),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: p.ink)),
                    ),
                    Text(formatBytes(item.size), style: TextStyle(fontSize: 10, color: p.ink4)),
                    const SizedBox(width: 10),
                    OlIconButton(icon: 'x', onTap: () => Navigator.of(dialogContext).pop()),
                  ],
                ),
              ),
              Flexible(
                child: _PreviewBody(kind: kind, url: url, item: item),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _PreviewBody extends StatefulWidget {
  final FileKind kind;
  final String url;
  final FileItem item;

  const _PreviewBody({required this.kind, required this.url, required this.item});

  @override
  State<_PreviewBody> createState() => _PreviewBodyState();
}

class _PreviewBodyState extends State<_PreviewBody> {
  String? _text;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.kind != FileKind.image && widget.kind != FileKind.video) {
      _loadText();
    }
  }

  Future<void> _loadText() async {
    try {
      final response = await Dio().get<List<int>>(
        widget.url,
        options: Options(responseType: ResponseType.bytes, validateStatus: (s) => s != null && s < 400),
      );
      final bytes = response.data ?? const <int>[];
      final slice = bytes.length > 200000 ? bytes.sublist(0, 200000) : bytes;
      setState(() {
        _text = utf8.decode(slice, allowMalformed: true);
      });
    } catch (_) {
      if (mounted) setState(() => _error = '无法读取文件内容，可能不是文本文件');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    if (widget.kind == FileKind.image) {
      return Container(
        color: const Color(0xFF0B1622),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(12),
        child: Image.network(
          widget.url,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Text('图片加载失败', style: TextStyle(fontSize: 12, color: p.ink3)),
        ),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(_error!, style: TextStyle(fontSize: 12, color: p.ink3)),
      );
    }
    if (_text == null) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: p.surfaceAlt,
      child: SingleChildScrollView(
        child: SelectableText(
          _text!.isEmpty ? '（空文件）' : _text!,
          style: TextStyle(fontSize: 11.5, height: 1.7, fontFamily: 'monospace', color: p.ink2),
        ),
      ),
    );
  }
}

/// Row “more” menu and the right-click menu use the same entries.
/// 媒体类文件的「打开」动作（v2.4）。
///
/// 之前只有视频 / 音频有入口，图片只能靠双击预览；现在点击即弹菜单，
/// 所以图片也要给一个显式的预览项，否则点开菜单没有任何"能看"的动作。
OlMenuItem? _openAction(BuildContext context, WidgetRef ref, FileItem item) {
  if (item.isDir) return null;
  switch (kindOf(item.name, false)) {
    case FileKind.video:
    case FileKind.audio:
      return OlMenuItem('播放', 'play', () => openItem(context, ref, item));
    case FileKind.image:
      return OlMenuItem('预览', 'image', () => openItem(context, ref, item));
    case FileKind.text:
    case FileKind.code:
      return OlMenuItem('预览', 'file-text', () => openItem(context, ref, item));
    default:
      return null;
  }
}

Future<void> showItemMenu(
  BuildContext context,
  WidgetRef ref,
  FileItem item,
  Offset position, {
  List<FileItem>? selection,
}) async {
  final files = ref.read(filesProvider);
  final profile = ref.read(sessionProvider).profile;
  final path = item.parent ?? joinPath(files.path, item.name);
  final isFavorite = profile != null && ref.read(favoritesProvider).any((e) => e.serverId == profile.id && e.path == path);
  final targets = (selection != null && selection.length > 1) ? selection : [item];

  OlMenuItem favoriteItem() => OlMenuItem(
        isFavorite ? '取消收藏' : '收藏',
        'star',
        () async {
          if (profile == null) return;
          await ref.read(favoritesProvider.notifier).toggle(profile.id, item, files.path);
          if (context.mounted) olToast(context, isFavorite ? '已取消收藏' : '已加入收藏');
        },
      );

  final openAction = _openAction(context, ref, item);
  // v1.0.26：分享功能整体移除，菜单固定为
  // 打开 / 收藏 / 下载 / 重命名 / 移动 / 复制 / 删除。
  final entries = <OlMenuItem>[
    if (openAction != null) openAction,
    favoriteItem(),
    // v1.0.33：文件夹也提供「下载」—— 走递归下载（含子目录全部文件）。
    OlMenuItem(
      '下载',
      'download',
      () => item.isDir ? downloadItems(context, ref, [item]) : downloadItem(context, ref, item),
    ),
    OlMenuItem('重命名', 'edit', () => renameItem(context, ref, item)),
    OlMenuItem('移动到…', 'move', () => moveOrCopyItems(context, ref, targets, move: true)),
    OlMenuItem('复制到…', 'copy', () => moveOrCopyItems(context, ref, targets, move: false)),
    OlMenuItem('删除', 'trash', () => deleteItems(context, ref, targets), danger: true),
  ];

  // A7：Android 用底部操作面板；Windows 用右键浮层。动作集合完全一致。
  if (Platform.isAndroid || context.isNarrow) {
    const quickLabels = {'播放', '预览', '收藏', '取消收藏', '下载'};
    final quick = entries.where((e) => quickLabels.contains(e.label)).toList();
    await showOlActionSheet(
      context,
      count: targets.length,
      title: item.name,
      subtitle: item.isDir ? '文件夹' : '${formatBytes(item.size)} · ${formatDate(item.modified)}',
      leading: FileGlyph(item: item, size: 38, radius: 10, iconSize: 18),
      quick: quick,
      items: entries.where((e) => !quick.contains(e)).toList(),
    );
    return;
  }

  await showOlMenu(context, position: position, items: entries);
}

/// Server-side directory picker used by move / copy (POST /api/fs/dirs).
class _DirPickerDialog extends ConsumerStatefulWidget {
  final String title;
  final String initialPath;

  const _DirPickerDialog({required this.title, required this.initialPath});

  @override
  ConsumerState<_DirPickerDialog> createState() => _DirPickerDialogState();
}

class _DirPickerDialogState extends ConsumerState<_DirPickerDialog> {
  late String _path = widget.initialPath;
  List<DirNode> _dirs = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = ref.read(sessionProvider).api;
    if (api == null) {
      setState(() {
        _loading = false;
        _error = '尚未连接服务器';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _dirs = const [];
    });
    try {
      final dirs = await api.dirs(path: _path);
      if (!mounted) return;
      setState(() {
        _dirs = dirs;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.friendly;
      });
    } catch (e) {
      // v1.0.33：非 ApiException（解析失败 / 类型不符）之前会让弹窗永远转圈。
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '读取目录失败：$e';
      });
    }
  }

  Future<void> _enter(String path) async {
    if (path == _path) return;
    setState(() => _path = path);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 460,
        height: 480,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(18), border: Border.all(color: p.line)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                OlIcon('move', size: 15, color: OlTokens.sky700),
                const SizedBox(width: 8),
                Text(widget.title, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: p.ink)),
                const Spacer(),
                OlIconButton(icon: 'x', onTap: () => Navigator.of(context).pop()),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
              decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(8), border: Border.all(color: p.line2)),
              child: Row(
                children: [
                  OlIcon('folder', size: 12, color: p.ink3),
                  const SizedBox(width: 6),
                  Expanded(child: Text(_path, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, fontFamily: 'monospace', color: p.ink2))),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : _error != null
                      ? Center(child: Text(_error!, style: TextStyle(fontSize: 11.5, color: OlTokens.dangerDeep)))
                      : ListView(
                          children: [
                            if (_path != '/')
                              InkWell(
                                onTap: () => _enter(parentOf(_path)),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
                                  child: Row(
                                    children: [
                                      OlIcon('chev-u', size: 13, color: p.ink3),
                                      const SizedBox(width: 8),
                                      Text('返回上级', style: TextStyle(fontSize: 11.5, color: p.ink3)),
                                    ],
                                  ),
                                ),
                              ),
                            for (final dir in _dirs)
                              InkWell(
                                onTap: () => _enter(dir.path),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
                                  child: Row(
                                    children: [
                                      const OlIcon('folder', size: 14, color: OlTokens.sky600),
                                      const SizedBox(width: 8),
                                      Expanded(child: Text(dir.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: p.ink))),
                                      OlIcon('chev-r', size: 12, color: p.ink4),
                                    ],
                                  ),
                                ),
                              ),
                            if (_dirs.isEmpty && _path != '/')
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text('该目录下没有子文件夹', style: TextStyle(fontSize: 11, color: p.ink4)),
                              ),
                          ],
                        ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text('目标：$_path', style: TextStyle(fontSize: 9.5, color: p.ink4)),
                const Spacer(),
                OlGhostButton(label: '取消', onTap: () => Navigator.of(context).pop()),
                const SizedBox(width: 8),
                OlPrimaryButton(label: '选择此目录', onTap: () => Navigator.of(context).pop(_path)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
