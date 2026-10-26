import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/api/api_exception.dart';
import '../../core/models/driver_schema.dart';
import '../../core/models/storage_source.dart';
import '../../data/db/app_database.dart';

/// 由用户填的名称生成挂载路径。
///
/// 语义与 OpenList 的 Web 界面保持一致：创建存储时填的挂载路径，
/// 就是根文件夹里显示的目录名 —— 填「本地存储6」，根目录就显示
/// 「本地存储6」，点进去是它的内容。
///
/// 引擎对挂载路径有格式要求（不能含空格与特殊字符），所以这里做一次
/// 清洗：去掉首尾空白，把路径分隔符与非法字符替换成下划线。名称本身
/// （含中文）原样保留 —— 中文挂载路径是 OpenList 支持的。
String mountPathOf(String name) {
  final raw = name.trim();
  final cleaned = raw
      .replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  // 清洗后为空（例如只填了空格或斜杠）时退回一个可用的默认值。
  final fallback = cleaned.isEmpty ? 'storage' : cleaned;
  return '/$fallback';
}

/// 生成一个不冲突的挂载路径（`/s_<8位十六进制>`）。
///
/// 仅用于配置导入等「没有用户命名」的场景 —— 导入的条目必须落到
/// 独立路径上，不能覆盖既有存储。添加向导走 [mountPathOf]。
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
/// 引擎里不开放的驱动。
///
/// `AList V3`（远程 AList）：本应用内嵌的就是 OpenList 服务端，再挂一个
/// 远程 AList 没有意义 —— 用户要接远程 OpenList，用 `OpenList` 那个驱动即可。
const Set<String> kHiddenDrivers = {'AList V3'};

final driverCatalogProvider = FutureProvider<Map<String, DriverInfo>>((ref) async {
  final api = ref.watch(sessionProvider).api;
  if (api == null) return const {};
  try {
    final all = await api.driverList();
    return {
      for (final entry in all.entries)
        if (!kHiddenDrivers.contains(entry.key)) entry: entry.value,
    };
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
      return _friendlyCreateError(error);
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

/// 创建存储失败时的中文提示。
///
/// 引擎对「挂载路径已存在」返回的是 500 + 一句英文 SQL 约束错误
/// （`UNIQUE constraint failed: x_storages.mount_path`），
/// 直接透给用户没法看懂，这里翻译成「换个名称」。
String _friendlyCreateError(ApiException error) {
  final raw = error.message.toLowerCase();
  if (raw.contains('mount_path') && raw.contains('unique')) {
    return '该挂载路径已存在，请换一个名称';
  }
  if (raw.contains('already exists') || raw.contains('duplicate')) {
    return '该挂载路径已存在，请换一个名称';
  }
  return error.friendly;
}
