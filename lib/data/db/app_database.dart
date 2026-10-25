import 'dart:convert';
import 'dart:io';

import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/sidecar/sidecar_paths.dart';

/// 本地数据库：传输记录与收藏走 SQLite（事务），路径跟随主程序目录。
///
/// 只保存 JSON 载荷 + 少量索引列：模型演进时不需要写迁移，也不会因为
/// 新增字段而丢数据。
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
        version: 1,
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE transfer_tasks (id TEXT PRIMARY KEY, sort_key INTEGER NOT NULL, payload TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE favorites (key TEXT PRIMARY KEY, payload TEXT NOT NULL)',
          );
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

class FavoriteDao {
  FavoriteDao._();

  static final FavoriteDao instance = FavoriteDao._();

  Future<List<Map<String, dynamic>>> loadAll() async {
    final db = await AppDatabase.instance();
    final rows = await db.query('favorites', orderBy: 'rowid DESC');
    final result = <Map<String, dynamic>>[];
    for (final row in rows) {
      try {
        final decoded = jsonDecode('${row['payload']}');
        if (decoded is Map) result.add(Map<String, dynamic>.from(decoded));
      } catch (_) {}
    }
    return result;
  }

  Future<void> put(String serverId, Map<String, dynamic> payload) async {
    final db = await AppDatabase.instance();
    await db.insert(
      'favorites',
      {'key': '$serverId|${payload['path']}', 'payload': jsonEncode(payload)},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> remove(String serverId, String path) async {
    final db = await AppDatabase.instance();
    await db.delete('favorites', where: 'key = ?', whereArgs: ['$serverId|$path']);
  }

  Future<void> clearAll() async {
    final db = await AppDatabase.instance();
    await db.delete('favorites');
  }
}
