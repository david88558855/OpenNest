import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/server_profile.dart';
import 'server_store.dart';

/// 下载落盘路径的唯一来源（v2.5）。
///
/// 规则：
///   - Android：公共「下载」目录 `/storage/emulated/0/Download/OpenNest`。
///   - Windows / macOS / Linux：系统下载目录下的 `OpenNest` 子目录。
///   - 用户在设置里显式选过目录时，显式目录优先。
/// 把任意名字压成**安全的单段路径**（v1.0.22）。
///
/// 之前只替换 9 个非法字符，`..`、结尾的点/空格、Windows 保留设备名、
/// 超长名字都会原样带进路径：
///   - 服务器显示名取 `..` 时 `root + sep + '..'` 会跳出 OpenNest 根目录；
///   - 结尾是 `.` 或空格时 Windows `mkdir` 直接失败；
///   - `CON/PRN/NUL/COM1` 这类保留名在 Windows 上创建会失败或行为异常；
///   - 名字过长会撞 260 字符路径上限。
String safePathSegment(String value) {
  var sanitized = value
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_')
      // 先把「纯点」序列整体干掉，避免 `..` / `.` 变成路径穿越或当前目录
      .replaceAll(RegExp(r'\.{2,}'), '_')
      .trim();
  // 结尾的点和空格在 Windows 上无法作为文件名
  sanitized = sanitized.replaceAll(RegExp(r'[. ]+$'), '').trim();
  if (sanitized.isEmpty) return 'item';
  // Windows 保留设备名（不区分大小写，允许带扩展名）
  final stem = sanitized.split('.').first.toUpperCase();
  const reserved = {
    'CON', 'PRN', 'AUX', 'NUL',
    'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
    'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9',
  };
  if (reserved.contains(stem)) sanitized = '_$sanitized';
  // 预留长度给「文件名 + 目录层级」，超过 64 字符截断
  if (sanitized.length > 64) sanitized = sanitized.substring(0, 64).trim();
  return sanitized.isEmpty ? 'item' : sanitized;
}

/// Android 的公共下载根目录（不含 OpenList 子目录）。
///
/// 不用 `getDownloadsDirectory()`：在 Android 上它返回的是
/// `/storage/emulated/0/Android/data/<pkg>/files/Download`（应用私有），
/// 文件管理器看不到。这里从 `getExternalStorageDirectory()` 的路径里截出存储根，
/// 兼容多用户 / 可移动存储（`/storage/emulated/<userId>`、`/storage/XXXX-XXXX`）。
Future<String> androidPublicDownloadRoot() async {
  String? external;
  try {
    external = (await getExternalStorageDirectory())?.path;
  } catch (_) {
    external = null;
  }
  final path = external ?? '';
  final cut = path.indexOf('/Android/');
  final storageRoot = cut > 0 ? path.substring(0, cut) : '/storage/emulated/0';
  return storageRoot + '/Download';
}

/// 系统默认下载根目录：Android 为公共 Download，桌面为系统下载文件夹。
Future<String> defaultDownloadBase() async {
  if (Platform.isAndroid) return androidPublicDownloadRoot();
  try {
    final downloads = await getDownloadsDirectory();
    if (downloads != null && downloads.path.isNotEmpty) return downloads.path;
  } catch (_) {
    // 某些 Linux 桌面没有 XDG 下载目录，退回文档目录
  }
  final fallback = await getApplicationDocumentsDirectory();
  return fallback.path;
}

/// 当前生效的下载目录（显式选择 > 默认 + OpenList [+ 服务器名]）。
Future<String> resolveDownloadDirFor(ServerStore store, ServerProfile profile) async {
  final saved = store.readDownloadDir(profile.id);
  if (saved != null && saved.isNotEmpty) return saved;
  final base = await defaultDownloadBase();
  // 0.5.0：不再按实例再分一层目录。本应用只连本机引擎
  // （profile.id 恒为 'local'、profile.name 恒为 '本机存储'），
  // 那层目录永远叫同一个名字，起不到区分作用。
  return base + Platform.pathSeparator + 'OpenNest';
}

/// 解析并确保目录存在；Android 未授予「所有文件访问权限」时退回应用私有目录，
/// 避免整个下载任务因为一个 mkdir 失败而直接报错。
Future<String> ensureDownloadDirFor(ServerStore store, ServerProfile profile) async {
  final dir = await resolveDownloadDirFor(store, profile);
  try {
    await Directory(dir).create(recursive: true);
    return dir;
  } catch (error) {
    debugPrint('download: 无法创建 $dir（$error），退回应用私有目录');
    // 回退到应用私有目录。仍与设置页显示的目标目录区分开，
    // 避免用户以为文件在显式目录里。
    final fallback = await getApplicationDocumentsDirectory();
    final root = fallback.path + Platform.pathSeparator + 'OpenNest';
    try {
      await Directory(root).create(recursive: true);
      return root;
    } catch (second) {
      debugPrint('download: 私有目录也不可写（$second），退回下载根目录');
      final base = await defaultDownloadBase();
      final alt = base + Platform.pathSeparator + 'OpenNest';
      await Directory(alt).create(recursive: true);
      return alt;
    }
  }
}
