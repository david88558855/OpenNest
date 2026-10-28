import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'sidecar_paths.dart';

/// 引擎自身数据库（`userdata/data.db`）里「存储源」表的低层读写。
///
/// 为什么需要它：OpenList 启动时会把**全部已启用的存储源**逐个加载
/// （`bootstrap.LoadStorages` → 每个源一个 goroutine → `op.LoadStorage`）。
/// 只要有一条存储源的驱动在初始化时崩掉（驱动 panic 会直接带崩整个 Go
/// 进程），引擎就会在每次启动的同一处再崩一次：客户端看到的永远是
/// 「引擎启动失败」，界面也进不去。引擎没有提供「跳过某个存储源启动」的
/// 开关，唯一可行的自救通道就是——趁引擎没在跑的时候直接改它的库，把
/// `x_storages.disabled` 置 1，下次启动就不再加载它。
///
/// 使用约束（由调用方保证）：
/// - **只在引擎进程已退出时调用**，避免与引擎争写同一份 SQLite；
/// - 出任何问题直接抛异常，不做静默降级 —— 宁可提示「安全模式不可用」，
///   也不能写坏用户的引擎库。
class EngineStore {
  EngineStore._(this.path);

  final String path;

  /// 存储源表名。引擎配置里 `table_prefix` 固定为 `x_`
  /// （见 `SidecarConfig.build`），因此表名是 `x_storages`。
  static const String tableName = 'x_storages';

  /// 打开引擎库；库不存在时抛 [StateError]。
  static Future<EngineStore> open() async {
    final root = await SidecarPaths.root();
    final file = File('${root.path}${Platform.pathSeparator}data.db');
    if (!await file.exists()) {
      throw StateError('引擎数据库不存在：${file.path}');
    }
    return EngineStore._(file.path);
  }

  /// 停用全部存储源，返回被停用的条数。
  ///
  /// [backup] 为 true（默认）时先把 `data.db` 连同 `-wal` / `-shm` 复制一份
  /// `data.db.bak-<时间戳>`；备份失败直接抛异常、不改库。
  Future<int> disableAll({bool backup = true}) async {
    if (backup) await snapshot();
    final db = await _openDb();
    try {
      await _requireTable(db);
      return await db.rawUpdate('UPDATE $tableName SET disabled = 1 WHERE disabled = 0');
    } finally {
      await db.close();
    }
  }

  /// 停用 / 启用单个存储源（按 id）。返回是否真的改到了行。
  Future<bool> setDisabled(int id, bool disabled) async {
    final db = await _openDb();
    try {
      await _requireTable(db);
      final changed = await db.rawUpdate(
        'UPDATE $tableName SET disabled = ? WHERE id = ?',
        [disabled ? 1 : 0, id],
      );
      return changed > 0;
    } finally {
      await db.close();
    }
  }

  /// 把引擎库整份复制成 `data.db.bak-<时间戳>`（含 WAL 附属文件）。
  ///
  /// WAL 里可能还留着最近一次写事务，只备份主库文件会丢数据，所以
  /// `-wal` / `-shm` 存在时一并复制。
  Future<String> snapshot() async {
    final dbFile = File(path);
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(RegExp(r'[:.]'), '-');
    final target = '${dbFile.path}.bak-$stamp';
    await dbFile.copy(target);
    for (final suffix in const ['-wal', '-shm']) {
      final side = File('${dbFile.path}$suffix');
      if (await side.exists()) {
        await side.copy('$target$suffix');
      }
    }
    return target;
  }

  Future<Database> _openDb() async {
    // sqflite_common_ffi 在桌面与 Android 上都可用（后者靠 sqlite3_flutter_libs
    // 提供的 libsqlite3）。singleInstance 关掉：这是引擎的库，不是应用自己的库，
    // 不能被缓存复用。
    sqfliteFfiInit();
    return databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(readOnly: false, singleInstance: false),
    );
  }

  /// 表结构不对时立刻放弃：宁可报错，也不要在不认识的库上执行 UPDATE。
  Future<void> _requireTable(Database db) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      [tableName],
    );
    if (rows.isEmpty) {
      throw StateError('引擎库里没有 $tableName 表，已放弃改动');
    }
  }
}
