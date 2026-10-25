import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 所有可写数据都落在主程序目录下，保证便携：解压即用、复制即走。
///
/// 桌面：`<主程序目录>/userdata/`；移动：应用私有目录下的 `opennest/`。
class SidecarPaths {
  const SidecarPaths._();

  static Directory desktopRoot() {
    final exeDir = File(Platform.resolvedExecutable).parent;
    return Directory('${exeDir.path}${Platform.pathSeparator}userdata');
  }

  static Future<Directory> root() async {
    final dir = Platform.isAndroid
        ? Directory(
            '${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}opennest',
          )
        : desktopRoot();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<File> _file(String name) async {
    final dir = await root();
    return File('${dir.path}${Platform.pathSeparator}$name');
  }

  static Future<File> config() => _file('config.json');
  static Future<File> pid() => _file('sidecar.pid');
  static Future<File> port() => _file('sidecar.port');
  static Future<File> log() => _file('sidecar.log');
  static Future<File> appDb() => _file('opennest.db');

  /// 引擎可执行文件位置。
  ///
  /// 桌面：优先主程序同目录（便携包布局），其次 `userdata/bin/`（开发调试）。
  /// 移动端由原生桥返回系统原生库目录，这里返回空。
  static Future<String?> binary() async {
    if (Platform.isAndroid) return null;
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final sep = Platform.pathSeparator;
    final candidates = <String>[
      '$exeDir${sep}openlist.exe',
      '$exeDir${sep}openlist',
      '$exeDir${sep}userdata${sep}bin${sep}openlist.exe',
      '$exeDir${sep}userdata${sep}bin${sep}openlist',
    ];
    for (final path in candidates) {
      if (await File(path).exists()) return path;
    }
    return null;
  }

  /// 读取日志尾部若干行，用于启动失败时展示。
  static Future<String> tailLog({int lines = 24}) async {
    try {
      final file = await log();
      if (!await file.exists()) return '';
      final text = await file.readAsString();
      final all = text.split('\n');
      final start = all.length > lines ? all.length - lines : 0;
      return all.sublist(start).join('\n').trim();
    } catch (_) {
      return '';
    }
  }
}
