import 'dart:async';
import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import '../../data/db/app_database.dart';
import '../sidecar/sidecar_paths.dart';

/// 本地偏好存储（单一 SQLite）。
///
/// 历史实现是 `userdata/prefs.json` 便携文件 + 原子写；现在全部并入
/// `userdata/opennest.db`，按数据形状拆表：
///
/// | 数据 | 表 |
/// |---|---|
/// | 标量偏好、`ol_prefs` 的每个字段 | `settings(key, value, kind)` |
/// | 每个源的浏览位置/排序 | `ui_state` |
/// | 每个源的下载目录 | `download_dirs` |
/// | 播放续播位置 | `resume_positions` |
/// | 离线目录快照 | `listing_cache` |
///
/// 对外 API 保持不变（同步读、异步写、250ms 合并落库），调用方无需改动。
class Prefs {
  Prefs._(this._db, this._path);

  static const _keyPrefs = 'ol_prefs';
  static const _cacheMaxEntries = 24;

  final Database _db;
  final String _path;

  final Map<String, _Setting> _settings = {};
  final Map<String, Map<String, String>> _browse = {};
  final Map<String, String> _downloads = {};
  final Map<String, Map<String, int>> _resume = {};
  final Map<String, Map<String, dynamic>> _cache = {};

  final Set<String> _dirtySettings = {};
  final Set<String> _dirtyBrowse = {};
  final Set<String> _dirtyDownloads = {};
  final Set<String> _dirtyResume = {};
  final Set<String> _dirtyCache = {};
  final Set<String> _deletedCache = {};

  Timer? _timer;
  bool _flushing = false;
  bool _pending = false;

  /// 单一数据库固定落在程序目录，恒为便携模式。
  bool get isPortable => true;

  String get storagePath => _path;

  static Future<Prefs> load() async {
    final db = await AppDatabase.instance();
    final prefs = Prefs._(db, await AppDatabase.filePath());
    await prefs._hydrate();
    return prefs;
  }

  Future<void> _hydrate() async {
    final settings = await _db.query('settings');
    for (final row in settings) {
      _settings['${row['key']}'] = _Setting('${row['value']}', '${row['kind']}');
    }
    final browse = await _db.query('ui_state');
    for (final row in browse) {
      _browse['${row['source_id']}'] = {
        'path': '${row['path']}',
        'order_by': '${row['order_by']}',
        'order_direction': '${row['order_direction']}',
        'saved_at': '${row['saved_at']}',
      };
    }
    final downloads = await _db.query('download_dirs');
    for (final row in downloads) {
      _downloads['${row['source_id']}'] = '${row['dir']}';
    }
    final resume = await _db.query('resume_positions');
    for (final row in resume) {
      _resume.putIfAbsent('${row['source_id']}', () => {})['${row['path']}'] =
          (row['seconds'] as num?)?.toInt() ?? 0;
    }
    final cache = await _db.query('listing_cache', orderBy: 'updated_at DESC', limit: _cacheMaxEntries);
    for (final row in cache) {
      try {
        final decoded = jsonDecode('${row['payload']}');
        if (decoded is Map) {
          _cache['${row['key']}'] = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
    }
  }

  // ------------------------------------------------------------- 标量读写

  String? getString(String key) {
    final downloadId = _downloadIdOf(key);
    if (downloadId != null) return _downloads[downloadId];
    return _settings[key]?.value;
  }

  bool getBool(String key, {bool fallback = false}) {
    final value = _settings[key]?.value;
    if (value == null) return fallback;
    return value == 'true' || value == '1';
  }

  int getInt(String key, {int fallback = 0}) {
    final value = _settings[key]?.value;
    if (value == null) return fallback;
    return int.tryParse(value) ?? fallback;
  }

  double getDouble(String key, {double fallback = 0}) {
    final value = _settings[key]?.value;
    if (value == null) return fallback;
    return double.tryParse(value) ?? fallback;
  }

  Future<void> setString(String key, String value) async {
    final downloadId = _downloadIdOf(key);
    if (downloadId != null) {
      _downloads[downloadId] = value;
      _dirtyDownloads.add(downloadId);
      _schedule();
      return;
    }
    _putSetting(key, value, 'string');
  }

  Future<void> setBool(String key, bool value) async => _putSetting(key, value ? 'true' : 'false', 'bool');

  Future<void> setInt(String key, int value) async => _putSetting(key, '$value', 'int');

  Future<void> setDouble(String key, double value) async => _putSetting(key, '$value', 'double');

  void _putSetting(String key, String value, String kind) {
    _settings[key] = _Setting(value, kind);
    _dirtySettings.add(key);
    _schedule();
  }

  Future<void> remove(String key) async {
    final downloadId = _downloadIdOf(key);
    if (downloadId != null) {
      _downloads.remove(downloadId);
      _dirtyDownloads.add(downloadId);
      _schedule();
      return;
    }
    final browseId = _sourceIdOf(key, '_browse');
    if (browseId != null) {
      _browse.remove(browseId);
      _dirtyBrowse.add(browseId);
      _schedule();
      return;
    }
    final resumeId = _sourceIdOf(key, '_resume');
    if (resumeId != null) {
      _resume.remove(resumeId);
      _dirtyResume.add(resumeId);
      _schedule();
      return;
    }
    if (_isCacheKey(key)) {
      _cache.remove(key);
      _deletedCache.add(key);
      _schedule();
      return;
    }
    if (key == 'ol_cache_index') {
      await clearListingCache();
      return;
    }
    if (_settings.remove(key) != null) {
      _dirtySettings.add(key);
      _schedule();
    }
  }

  // ------------------------------------------------------- 结构化偏好读写

  List<dynamic> getJsonList(String key) {
    // 目录缓存的 LRU 索引已由 `listing_cache` 表的时间序替代。
    return const [];
  }

  Future<void> setJsonList(String key, List<dynamic> value) async {
    // 收藏与传输记录已迁移到独立表（FavoriteDao / TransferDao），这里不再落盘。
  }

  Map<String, dynamic> getJsonMap(String key) {
    if (key == _keyPrefs) {
      final map = <String, dynamic>{};
      for (final entry in _settings.entries) {
        if (!entry.key.startsWith('app.')) continue;
        map[entry.key.substring(4)] = _decode(entry.value);
      }
      return map;
    }
    final browseId = _sourceIdOf(key, '_browse');
    if (browseId != null) return Map<String, dynamic>.from(_browse[browseId] ?? const {});
    final resumeId = _sourceIdOf(key, '_resume');
    if (resumeId != null) {
      final positions = _resume[resumeId];
      if (positions == null) return <String, dynamic>{};
      return positions.map((k, v) => MapEntry<String, dynamic>(k, v));
    }
    if (_isCacheKey(key)) return Map<String, dynamic>.from(_cache[key] ?? const {});
    return const {};
  }

  Future<void> setJsonMap(String key, Map<String, dynamic> value) async {
    if (key == _keyPrefs) {
      // 逐字段拆成标量，保留真实类型。
      final keep = <String>{};
      for (final entry in value.entries) {
        final name = 'app.${entry.key}';
        keep.add(name);
        final raw = entry.value;
        if (raw is bool) {
          _settings[name] = _Setting(raw ? 'true' : 'false', 'bool');
        } else if (raw is int) {
          _settings[name] = _Setting('$raw', 'int');
        } else if (raw is double) {
          _settings[name] = _Setting('$raw', 'double');
        } else if (raw != null) {
          _settings[name] = _Setting('$raw', 'string');
        }
        _dirtySettings.add(name);
      }
      final stale = _settings.keys.where((k) => k.startsWith('app.') && !keep.contains(k)).toList();
      for (final name in stale) {
        _settings.remove(name);
        _dirtySettings.add(name);
      }
      _schedule();
      return;
    }

    final browseId = _sourceIdOf(key, '_browse');
    if (browseId != null) {
      _browse[browseId] = {
        'path': '${value['path'] ?? '/'}',
        'order_by': '${value['order_by'] ?? 'name'}',
        'order_direction': '${value['order_direction'] ?? 'asc'}',
        'saved_at': '${value['saved_at'] ?? DateTime.now().toIso8601String()}',
      };
      _dirtyBrowse.add(browseId);
      _schedule();
      return;
    }

    final resumeId = _sourceIdOf(key, '_resume');
    if (resumeId != null) {
      final map = <String, int>{};
      value.forEach((k, v) {
        if (v is num) map[k] = v.toInt();
      });
      _resume[resumeId] = map;
      _dirtyResume.add(resumeId);
      _schedule();
      return;
    }

    if (_isCacheKey(key)) {
      _cache[key] = Map<String, dynamic>.from(value);
      _dirtyCache.add(key);
      _schedule();
    }
  }

  /// 清空离线目录缓存（设置页与切换源时调用）。
  Future<void> clearListingCache() async {
    _cache.clear();
    _dirtyCache.clear();
    _deletedCache.add('*');
    await flush();
  }

  // ------------------------------------------------------------- 落库

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 250), () => flush());
  }

  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    if (_flushing) {
      _pending = true;
      return;
    }
    _flushing = true;
    try {
      await _db.transaction((txn) async {
        for (final key in _dirtySettings) {
          final setting = _settings[key];
          if (setting == null) {
            await txn.delete('settings', where: 'key = ?', whereArgs: [key]);
          } else {
            await txn.insert(
              'settings',
              {'key': key, 'value': setting.value, 'kind': setting.kind},
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }
        for (final id in _dirtyBrowse) {
          final row = _browse[id];
          if (row == null) {
            await txn.delete('ui_state', where: 'source_id = ?', whereArgs: [id]);
          } else {
            await txn.insert(
              'ui_state',
              {
                'source_id': id,
                'path': row['path'],
                'order_by': row['order_by'],
                'order_direction': row['order_direction'],
                'saved_at': row['saved_at'],
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }
        for (final id in _dirtyDownloads) {
          final dir = _downloads[id];
          if (dir == null) {
            await txn.delete('download_dirs', where: 'source_id = ?', whereArgs: [id]);
          } else {
            await txn.insert(
              'download_dirs',
              {'source_id': id, 'dir': dir},
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }
        for (final id in _dirtyResume) {
          await txn.delete('resume_positions', where: 'source_id = ?', whereArgs: [id]);
          final positions = _resume[id];
          if (positions != null) {
            for (final entry in positions.entries) {
              await txn.insert(
                'resume_positions',
                {'source_id': id, 'path': entry.key, 'seconds': entry.value},
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
            }
          }
        }
        if (_deletedCache.remove('*')) {
          await txn.delete('listing_cache');
        }
        for (final key in _deletedCache) {
          await txn.delete('listing_cache', where: 'key = ?', whereArgs: [key]);
        }
        for (final key in _dirtyCache) {
          final payload = _cache[key];
          if (payload == null) continue;
          final text = jsonEncode(payload);
          await txn.insert(
            'listing_cache',
            {
              'key': key,
              'payload': text,
              'bytes': text.length,
              'updated_at': DateTime.now().millisecondsSinceEpoch,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      });
      _dirtySettings.clear();
      _dirtyBrowse.clear();
      _dirtyDownloads.clear();
      _dirtyResume.clear();
      _dirtyCache.clear();
      _deletedCache.clear();
      await _pruneCache();
    } catch (_) {
      // 落库失败保留脏标记，下次写入或退出时再试。
    } finally {
      _flushing = false;
      if (_pending) {
        _pending = false;
        unawaited(flush());
      }
    }
  }

  /// 只保留最近 [_cacheMaxEntries] 个目录快照。
  Future<void> _pruneCache() async {
    if (_cache.length <= _cacheMaxEntries) return;
    final rows = await _db.query('listing_cache', orderBy: 'updated_at ASC');
    final extra = rows.length - _cacheMaxEntries;
    for (var i = 0; i < extra; i++) {
      final key = '${rows[i]['key']}';
      await _db.delete('listing_cache', where: 'key = ?', whereArgs: [key]);
      _cache.remove(key);
    }
  }

  // ------------------------------------------------------------- 键解析

  String? _sourceIdOf(String key, String suffix) {
    if (!key.startsWith('ol_srv_') || !key.endsWith(suffix)) return null;
    final id = key.substring('ol_srv_'.length, key.length - suffix.length);
    return id.isEmpty ? null : id;
  }

  String? _downloadIdOf(String key) => _sourceIdOf(key, '_download');

  bool _isCacheKey(String key) => key.startsWith('ol_srv_') && key.contains('_cache|');

  Object? _decode(_Setting setting) {
    switch (setting.kind) {
      case 'bool':
        return setting.value == 'true';
      case 'int':
        return int.tryParse(setting.value);
      case 'double':
        return double.tryParse(setting.value);
      default:
        return setting.value;
    }
  }
}

class _Setting {
  final String value;
  final String kind;

  const _Setting(this.value, this.kind);
}
