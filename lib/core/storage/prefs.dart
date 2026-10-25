import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Key/value store.
///
/// v1.0.20 起 Windows 走**真正的便携存储**，v1.0.29 起配置来源唯一化：
///   - 权威文件：`<主程序目录>/userdata/prefs.json`（相对 exe 解析，
///     整个目录拷走/搬走，配置跟着走）；
///   - **唯一判定依据**：仅当主程序目录下存在 prefs.json 才加载使用；
///     目录下没有该文件即视为无配置（**不从旧版 / 系统用户目录移植任何数据**）；
///   - 所有读写都在内存 Map 上完成，写操作合并后 250ms 落盘（tmp → rename 原子写），
///     进程退出前 `flush()` 保证最后一次写入不丢；
///   - 主程序目录不可写（例如装在 Program Files）时退到
///     `%LOCALAPPDATA%/OpenNest/userdata/prefs.json`。
///
/// 其它平台（Android）仍然用 SharedPreferences，行为不变。
///
/// 键名沿用固定约定：ol_servers_index / ol_active_server_id / ol_srv_<id>_* /
/// ol_prefs / ol_transfers。密钥（密码 / Token）永远不进这个文件，只在系统安全存储。
class Prefs {
  final Map<String, Object?> _data;
  final File? _file;
  final SharedPreferences? _sp;
  Timer? _flushTimer;
  bool _dirty = false;

  /// 落盘互斥：同一时刻只允许一路写 `.tmp`（见 `_flushNow`）。
  bool _flushing = false;
  bool _pending = false;

  Prefs._file(this._data, this._file) : _sp = null;
  Prefs._sp(this._sp)
      : _data = <String, Object?>{},
        _file = null;

  /// 便携存储是否生效（Windows 且拿到了可写路径）。
  bool get isPortable => _file != null;

  /// 数据文件位置，设置页展示用。
  String get storagePath => _file?.path ?? '系统存储（SharedPreferences）';

  static Future<Prefs> load() async {
    if (!Platform.isWindows) {
      final sp = await SharedPreferences.getInstance();
      return Prefs._sp(sp);
    }
    final file = _portablePath();
    if (file == null) {
      // 程序目录不可写（极端情况）：退回系统存储，至少不让数据只停留在内存里。
      debugPrint('prefs: no writable portable dir, falling back to shared_preferences');
      final sp = await SharedPreferences.getInstance();
      return Prefs._sp(sp);
    }
    final data = <String, Object?>{};

    // v1.0.29：配置的唯一判定依据是「主程序目录下是否存在 prefs.json」。
    // 只读这个文件；不再从旧版 / 系统用户目录（SharedPreferences）移植任何数据。
    // 目录下没有该文件就当作无配置，运行时把首次改动写回该文件。
    if (file.existsSync()) {
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) {
          decoded.forEach((k, v) => data[k.toString()] = v);
        }
      } catch (error) {
        // 文件损坏：备份现场并视为无配置（不静默清空，也绝不从别处移植）
        try {
          await file.rename('${file.path}.bak');
        } catch (_) {}
        debugPrint('prefs: portable file corrupt, backed up ($error)');
      }
    }

    return Prefs._file(data, file);
  }

  /// `<主程序目录>/userdata/prefs.json`，不可写时退到 LOCALAPPDATA。
  ///
  /// 用 `Platform.resolvedExecutable` 的父目录解析——不依赖当前工作目录，
  /// 从快捷方式、任务栏、命令行任意方式启动都指向同一个位置。
  static File? _portablePath() {
    final sep = Platform.pathSeparator;
    try {
      final exeDir = File(Platform.resolvedExecutable).parent;
      final dir = Directory('${exeDir.path}${sep}userdata');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      return File('${dir.path}${sep}prefs.json');
    } catch (error) {
      debugPrint('prefs: exe dir not writable, falling back ($error)');
    }
    final local = Platform.environment['LOCALAPPDATA'];
    if (local != null && local.isNotEmpty) {
      final dir = Directory('$local${sep}OpenNest${sep}userdata');
      try {
        if (!dir.existsSync()) dir.createSync(recursive: true);
        return File('${dir.path}${sep}prefs.json');
      } catch (error) {
        debugPrint('prefs: LOCALAPPDATA not writable ($error)');
      }
    }
    return null;
  }

  // ------------------------------------------------------------------ 读写

  Object? _read(String key) {
    final sp = _sp;
    if (sp != null) return sp.get(key);
    return _data[key];
  }

  /// 写入标量。
  ///
  /// v1.0.23：只有 `setString/setBool/setInt/setDouble` 会走到这里（JSON 结构
  /// 由 `setJsonList/setJsonMap` 先编码成 String）。之前保留了一个 List 分支，
  /// 在 SharedPreferences 侧会把元素强制字符串化，两端行为不一致——已删除，
  /// 遇到非标量直接忽略并留日志，不再静默写出"看起来成功"的脏数据。
  Future<void> _write(String key, Object? value) async {
    final sp = _sp;
    if (sp != null) {
      if (value is String) {
        await sp.setString(key, value);
      } else if (value is bool) {
        await sp.setBool(key, value);
      } else if (value is int) {
        await sp.setInt(key, value);
      } else if (value is double) {
        await sp.setDouble(key, value);
      } else {
        debugPrint('prefs: unsupported value type for $key (${value.runtimeType})');
      }
      return;
    }
    _data[key] = value;
    _schedule();
  }

  Future<void> _remove(String key) async {
    final sp = _sp;
    if (sp != null) {
      await sp.remove(key);
      return;
    }
    _data.remove(key);
    _schedule();
  }

  String? getString(String key) {
    final value = _read(key);
    return value is String ? value : null;
  }

  bool getBool(String key, {bool fallback = false}) {
    final value = _read(key);
    return value is bool ? value : fallback;
  }

  int getInt(String key, {int fallback = 0}) {
    final value = _read(key);
    if (value is int) return value;
    if (value is num) return value.toInt();
    return fallback;
  }

  double getDouble(String key, {double fallback = 0}) {
    final value = _read(key);
    if (value is num) return value.toDouble();
    return fallback;
  }

  Future<void> setString(String key, String value) => _write(key, value);
  Future<void> setBool(String key, bool value) => _write(key, value);
  Future<void> setInt(String key, int value) => _write(key, value);
  Future<void> setDouble(String key, double value) => _write(key, value);
  Future<void> remove(String key) => _remove(key);

  List<dynamic> getJsonList(String key) {
    final raw = getString(key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded;
    } catch (_) {
      return const [];
    }
    return const [];
  }

  Future<void> setJsonList(String key, List<dynamic> value) => setString(key, jsonEncode(value));

  Map<String, dynamic> getJsonMap(String key) {
    final raw = getString(key);
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return const {};
    }
    return const {};
  }

  Future<void> setJsonMap(String key, Map<String, dynamic> value) => setString(key, jsonEncode(value));

  // ------------------------------------------------------------------ 落盘

  void _schedule() {
    if (_file == null) return;
    _dirty = true;
    _flushTimer?.cancel();
    _flushTimer = Timer(const Duration(milliseconds: 250), () {
      _flushNow();
    });
  }

  /// 立即落盘（退出前调用，保证最后一次写入不丢）。
  Future<void> flush() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    await _flushNow(force: true);
  }

  /// 落盘。
  ///
  /// 两条硬约束（审查发现的问题，v1.0.21）：
  ///   1. **互斥**：定时器回调与 `flush()` 可能同时进来，两路写同一个 `.tmp`
  ///      会产出半截 JSON。这里用 `_flushing` + `_pending` 串行化，同一时刻只有一路在写。
  ///   2. **可回滚的原子替换**：旧文件先改名成 `.bak` 再让 `.tmp` 就位（不是先删后改名），
  ///      替换失败还能把 `.bak` 还原回去，避免"目标已删、新文件没就位"导致的配置全丢。
  Future<void> _flushNow({bool force = false}) async {
    final file = _file;
    if (file == null) return;
    if (!_dirty && !force) return;
    if (_flushing) {
      _pending = true;
      return;
    }
    _flushing = true;
    _dirty = false;
    final bak = File('${file.path}.bak');
    try {
      final map = <String, dynamic>{};
      _data.forEach((key, value) {
        if (value is String || value is num || value is bool || value is List || value is Map) {
          map[key] = value;
        }
      });
      await file.parent.create(recursive: true);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(jsonEncode(map), flush: true);

      if (file.existsSync()) {
        try {
          if (bak.existsSync()) bak.deleteSync();
          file.renameSync(bak.path);
        } catch (error) {
          debugPrint('prefs: rotate to .bak failed ($error)');
        }
      }
      try {
        await tmp.rename(file.path);
      } catch (error) {
        // 替换失败：把备份还原，宁可留着旧数据也不要丢
        try {
          if (!file.existsSync() && bak.existsSync()) bak.renameSync(file.path);
        } catch (_) {}
        rethrow;
      }
    } catch (error) {
      // 落盘失败保留脏标记，下次写入或退出时再试
      _dirty = true;
      debugPrint('prefs: flush failed ($error)');
    } finally {
      _flushing = false;
      if (_pending) {
        _pending = false;
        unawaited(_flushNow());
      }
    }
  }
}
