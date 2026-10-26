import 'dart:convert';
import 'dart:io';

import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/sidecar/sidecar_paths.dart';

/// 唯一的本地存储：`userdata/opennest.db`。
///
/// 表结构（版本 4）：
/// - `settings`        标量偏好与 `ol_prefs` 的每个字段（key/value/kind 三列，保留类型）
/// - `ui_state`        每个存储源的浏览位置与排序、视图偏好
/// - `download_dirs`   每个存储源的下载目录
/// - `resume_positions` 播放续播位置（按源 + 路径）
/// - `listing_cache`   离线目录快照（引擎返回的任意结构，按快照整体存放）
/// - `transfer_tasks`  传输记录（载荷 + 排序键）
/// - `source_usage`    每个存储源的最后访问时间（设置页「最近使用」列）
///
/// 0.5.0：收藏功能整体取消，`favorites` 表随之删除（升级到 v3 时 DROP）。
class AppDatabase {
  AppDatabase._();

  static Database? _db;

  static Future<Database> instance() async {
    final cached = _db;
    if (cached != null) return cached;

    final path = (await SidecarPaths.appDb()).path;
    final factory = Platform.isAndroid ? sqflite.databaseFactory : _desktopFactory();
    final database = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 4,
        onCreate: (db, version) => _createSchema(db),
        onUpgrade: (db, oldVersion, newVersion) async {
          // 旧版本只有 transfer_tasks / favorites，补齐新增表即可。
          if (oldVersion < 2) await _createV2Tables(db);
          // 0.5.0：收藏功能取消，连带清掉遗留的收藏表。
          if (oldVersion < 3) await db.execute('DROP TABLE IF EXISTS favorites');
          // 0.5.0：设置页按设计稿 D8 增「最近使用」列，需要按源记访问时间。
          if (oldVersion < 4) await _createV4Tables(db);
        },
      ),
    );
    _db = database;
    return database;
  }

  static DatabaseFactory _desktopFactory() {
    sqfliteFfiInit();
    return databaseFactoryFfi;
  }

  static Future<void> _createSchema(Database db) async {
    await db.execute(
      'CREATE TABLE transfer_tasks (id TEXT PRIMARY KEY, sort_key INTEGER NOT NULL, payload TEXT NOT NULL)',
    );
    await _createV2Tables(db);
    await _createV4Tables(db);
  }

  static Future<void> _createV2Tables(Database db) async {
    await db.execute(
      'CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL, kind TEXT NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS ui_state (source_id TEXT PRIMARY KEY, path TEXT NOT NULL, '
      'order_by TEXT NOT NULL, order_direction TEXT NOT NULL, saved_at TEXT NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS download_dirs (source_id TEXT PRIMARY KEY, dir TEXT NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS resume_positions (source_id TEXT NOT NULL, path TEXT NOT NULL, '
      'seconds INTEGER NOT NULL, PRIMARY KEY (source_id, path))',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS listing_cache (key TEXT PRIMARY KEY, payload TEXT NOT NULL, '
      'bytes INTEGER NOT NULL, updated_at INTEGER NOT NULL)',
    );
  }

  static Future<void> _createV4Tables(Database db) async {
    await db.execute(
      'CREATE TABLE IF NOT EXISTS source_usage (source_id TEXT PRIMARY KEY, last_used INTEGER NOT NULL)',
    );
  }

  /// 供诊断使用：当前数据库文件路径。
  static Future<String> filePath() async => (await SidecarPaths.appDb()).path;
}

/// 存储源访问时间：设置页「最近使用」列的数据来源。
///
/// 按源（挂载路径）记最后一次打开时间。浏览位置存在 `ui_state` 里，但那是
/// 按「本机身份」分桶的（只有一个 local），无法区分具体是哪个源被打开过，
/// 所以这里单独记一张表。
class SourceUsageDao {
  SourceUsageDao._();

  static final SourceUsageDao instance = SourceUsageDao._();

  Future<Map<String, int>> loadAll() async {
    final db = await AppDatabase.instance();
    final rows = await db.query('source_usage');
    final result = <String, int>{};
    for (final row in rows) {
      final id = '${row['source_id']}';
      final at = (row['last_used'] as num?)?.toInt() ?? 0;
      if (id.isNotEmpty) result[id] = at;
    }
    return result;
  }

  Future<void> touch(String sourceId) async {
    if (sourceId.isEmpty) return;
    final db = await AppDatabase.instance();
    await db.insert(
      'source_usage',
      {'source_id': sourceId, 'last_used': DateTime.now().millisecondsSinceEpoch},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> remove(String sourceId) async {
    final db = await AppDatabase.instance();
    await db.delete('source_usage', where: 'source_id = ?', whereArgs: [sourceId]);
  }
}

class TransferDao {
  TransferDao._();

  static final TransferDao instance = TransferDao._();

  Future<List<Map<String, dynamic>>> loadAll() async {
    final db = await AppDatabase.instance();
    final rows = await db.query('transfer_tasks', orderBy: 'sort_key ASC');
    final result = <Map<String, dynamic>>[];
    for (final row in rows) {
      try {
        final decoded = jsonDecode('${row['payload']}');
        if (decoded is Map) result.add(Map<String, dynamic>.from(decoded));
      } catch (_) {}
    }
    return result;
  }

  Future<void> replaceAll(List<Map<String, dynamic>> tasks) async {
    final db = await AppDatabase.instance();
    await db.transaction((txn) async {
      await txn.delete('transfer_tasks');
      for (var i = 0; i < tasks.length; i++) {
        final payload = tasks[i];
        await txn.insert(
          'transfer_tasks',
          {
            'id': '${payload['id'] ?? i}',
            'sort_key': i,
            'payload': jsonEncode(payload),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }
}
