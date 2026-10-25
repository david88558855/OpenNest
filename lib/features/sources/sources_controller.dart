import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/api/api_exception.dart';
import '../../core/models/driver_schema.dart';
import '../../core/models/storage_source.dart';

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
