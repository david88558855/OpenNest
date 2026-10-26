import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/api/api_exception.dart';
import '../../core/models/driver_schema.dart';
import '../../core/models/storage_source.dart';
import '../../data/db/app_database.dart';

/// 生成一个不冲突的挂载路径（`/s_<8位十六进制>`）。
///
/// 添加向导与配置导入共用同一套生成规则，避免两处各写一份。
String generateMountPath() {
  final random = Random.secure();
  final suffix = List.generate(8, (_) => random.nextInt(16).toRadixString(16)).join();
  return '/s_$suffix';
}

/// 引擎侧存储源列表（真值来源）。
final sourcesProvider = FutureProvider<List<StorageSource>>((ref) async {
  final api = ref.watch(sessionProvider).api;
  if (api == null) return const [];
  try {
    return await api.adminStorages();
  } on ApiException catch (_) {
    return const [];
  }
});

/// 每个存储源的最后访问时间（设置页「最近使用」列）。
final sourceUsageProvider = FutureProvider<Map<String, int>>((ref) async {
  return SourceUsageDao.instance.loadAll();
});

/// 驱动字典：一次拉全，添加向导按分组展示。
final driverCatalogProvider = FutureProvider<Map<String, DriverInfo>>((ref) async {
  final api = ref.watch(sessionProvider).api;
  if (api == null) return const {};
  try {
    return await api.driverList();
  } on ApiException catch (_) {
    return const {};
  }
});

class SourceActions {
  SourceActions(this._ref);

  final Ref _ref;

  /// 新建存储源；先落库再列一次根目录做连通性验证，失败即回滚。
  /// 返回 null 表示成功，否则返回可展示的错误文案。
  Future<String?> create(StorageSource source) async {
    final api = _ref.read(sessionProvider).api;
    if (api == null) return '引擎未就绪';
    int id = 0;
    try {
      id = await api.createStorage(source);
    } on ApiException catch (error) {
      return error.friendly;
    } catch (error) {
      return '保存失败：$error';
    }
    if (id <= 0) return '引擎未返回存储编号';

    try {
      await api.list(path: source.mountPath);
    } on ApiException catch (error) {
      // 连不通就别留下半成品，否则侧边栏会出现一个永远打不开的源。
      try {
        await api.deleteStorage(id);
      } catch (_) {}
      return '连接失败：${error.friendly}';
    } catch (error) {
      try {
        await api.deleteStorage(id);
      } catch (_) {}
      return '连接失败：$error';
    }

    _ref.invalidate(sourcesProvider);
    return null;
  }

  Future<String?> update(StorageSource source) async {
    final api = _ref.read(sessionProvider).api;
    if (api == null) return '引擎未就绪';
    try {
      await api.updateStorage(source);
      _ref.invalidate(sourcesProvider);
      return null;
    } on ApiException catch (error) {
      return error.friendly;
    }
  }

  Future<String?> remove(StorageSource source) async {
    final api = _ref.read(sessionProvider).api;
    if (api == null) return '引擎未就绪';
    try {
      await api.deleteStorage(source.id);
      _ref.invalidate(sourcesProvider);
      return null;
    } on ApiException catch (error) {
      return error.friendly;
    }
  }

  /// 测试连接：列一次该源的根目录。返回 null 表示通。
  Future<String?> test(StorageSource source) async {
    final api = _ref.read(sessionProvider).api;
    if (api == null) return '引擎未就绪';
    try {
      await api.list(path: source.mountPath);
      return null;
    } on ApiException catch (error) {
      return error.friendly;
    } catch (error) {
      return '连接失败：$error';
    }
  }

  Future<String?> toggle(StorageSource source) async {
    final api = _ref.read(sessionProvider).api;
    if (api == null) return '引擎未就绪';
    try {
      await api.setStorageEnabled(source.id, source.disabled);
      _ref.invalidate(sourcesProvider);
      return null;
    } on ApiException catch (error) {
      return error.friendly;
    }
  }
}

final sourceActionsProvider = Provider<SourceActions>((ref) => SourceActions(ref));
