import 'dart:convert';

import '../models/server_profile.dart';
import 'prefs.dart';

/// Persists the server index, the active instance and every per-server key.
/// Nothing here is ever sent to a server: the whole file is local-only.
class ServerStore {
  static const keyIndex = 'ol_servers_index';
  static const keyActive = 'ol_active_server_id';
  static const keyPrefs = 'ol_prefs';

  /// 目录缓存的 LRU 索引（v2.3）。之前每个目录一份 JSON 无限堆积，
  /// 浏览几千个目录后 prefs 会膨胀到几十 MB，冷启动解析明显变慢。
  static const keyCacheIndex = 'ol_cache_index';
  static const cacheMaxEntries = 24;
  static const cacheMaxBytes = 2 * 1024 * 1024;

  final Prefs prefs;

  ServerStore(this.prefs);

  List<ServerProfile> loadServers() {
    final raw = prefs.getJsonList(keyIndex);
    final out = <ServerProfile>[];
    for (final e in raw) {
      if (e is Map) {
        final p = ServerProfile.fromJson(Map<String, dynamic>.from(e));
        if (p.id.isNotEmpty && p.baseUrl.isNotEmpty) out.add(p);
      }
    }
    out.sort((a, b) => (b.lastUsed ?? DateTime(1970)).compareTo(a.lastUsed ?? DateTime(1970)));
    return out;
  }

  Future<void> saveServers(List<ServerProfile> servers) async {
    await prefs.setJsonList(keyIndex, servers.map((e) => e.toJson()).toList());
  }

  String? loadActiveId() {
    final id = prefs.getString(keyActive);
    if (id == null || id.isEmpty) return null;
    return id;
  }

  Future<void> saveActiveId(String? id) async {
    if (id == null || id.isEmpty) {
      await prefs.remove(keyActive);
    } else {
      await prefs.setString(keyActive, id);
    }
  }

  // ------------------------------------------------------- per-server data

  Future<void> saveBrowse(String id, String path, String orderBy, bool desc) async {
    await prefs.setJsonMap('ol_srv_${id}_browse', {
      'path': path,
      'order_by': orderBy,
      'order_direction': desc ? 'desc' : 'asc',
      'saved_at': DateTime.now().toIso8601String(),
    });
  }

  Map<String, dynamic> readBrowse(String id) => prefs.getJsonMap('ol_srv_${id}_browse');

  Future<void> saveDownloadDir(String id, String dir) =>
      prefs.setString('ol_srv_${id}_download', dir);

  String? readDownloadDir(String id) => prefs.getString('ol_srv_${id}_download');

  Future<void> clearDownloadDir(String id) => prefs.remove('ol_srv_${id}_download');

  Future<void> saveFavorites(String id, List<Map<String, dynamic>> items) =>
      prefs.setJsonList('ol_srv_${id}_favorites', items);

  List<Map<String, dynamic>> readFavorites(String id) {
    final raw = prefs.getJsonList('ol_srv_${id}_favorites');
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<void> saveResume(String id, String path, int seconds) async {
    final all = prefs.getJsonMap('ol_srv_${id}_resume');
    all[path] = seconds;
    final keys = all.keys.toList();
    if (keys.length > 300) {
      for (final k in keys.take(keys.length - 300)) {
        all.remove(k);
      }
    }
    await prefs.setJsonMap('ol_srv_${id}_resume', all);
  }

  int readResume(String id, String path) {
    final all = prefs.getJsonMap('ol_srv_${id}_resume');
    final v = all[path];
    return v is num ? v.toInt() : 0;
  }

  /// Offline list cache: survives a dropped connection so the last directory
  /// stays readable (W2 四态 / 离线).
  ///
  /// v2.3：写入时维护 LRU 索引，最多保留 [cacheMaxEntries] 个目录且总量不超过
  /// [cacheMaxBytes]；超出时按最后访问时间淘汰最旧的条目。
  Future<void> cacheListing(String id, String path, List<Map<String, dynamic>> items) async {
    final key = 'ol_srv_${id}_cache|$path';
    final map = <String, dynamic>{'items': items, 'at': DateTime.now().toIso8601String()};
    await prefs.setJsonMap(key, map);
    await _touchCacheIndex(key, jsonEncode(map).length);
  }

  Map<String, dynamic> readCachedListing(String id, String path) =>
      prefs.getJsonMap('ol_srv_${id}_cache|$path');

  /// 维护 LRU 索引：把 [key] 提到队尾，再从队首淘汰超额条目。
  Future<void> _touchCacheIndex(String key, int bytes) async {
    final entries = <Map<String, dynamic>>[];
    for (final raw in prefs.getJsonList(keyCacheIndex)) {
      if (raw is! Map) continue;
      final k = raw['k'];
      if (k is! String || k.isEmpty || k == key) continue;
      final n = raw['n'];
      entries.add({'k': k, 'n': n is num ? n.toInt() : 0});
    }
    entries.add({'k': key, 'n': bytes});

    var total = entries.fold<int>(0, (sum, e) => sum + ((e['n'] as int?) ?? 0));
    while (entries.length > cacheMaxEntries || (total > cacheMaxBytes && entries.length > 1)) {
      final evicted = entries.removeAt(0);
      total -= (evicted['n'] as int?) ?? 0;
      final victim = evicted['k'];
      if (victim is String) await prefs.remove(victim);
    }
    await prefs.setJsonList(keyCacheIndex, entries);
  }

  /// 清空全部离线目录缓存（设置里的「清除缓存」/ 退出登录时调用）。
  Future<void> clearListingCache() async {
    for (final raw in prefs.getJsonList(keyCacheIndex)) {
      if (raw is Map && raw['k'] is String) await prefs.remove(raw['k'] as String);
    }
    await prefs.remove(keyCacheIndex);
  }
}
