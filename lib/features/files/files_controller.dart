import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/openlist_api.dart';
import '../../core/format.dart';
import '../../core/models/api_types.dart';

class FilesState {
  final String path;
  final String serverId;
  final List<FileItem> items;
  final int total;
  final int page;
  final bool loading;
  final bool loadingMore;
  final bool showSkeleton;
  final String? error;
  final bool offline;
  final Set<String> selected;
  final String orderBy;
  final bool desc;
  final bool grid;
  final bool canWrite;
  final String? provider;

  const FilesState({
    this.path = '/',
    this.serverId = '',
    this.items = const [],
    this.total = 0,
    this.page = 1,
    this.loading = false,
    this.loadingMore = false,
    this.showSkeleton = false,
    this.error,
    this.offline = false,
    this.selected = const {},
    this.orderBy = 'name',
    this.desc = false,
    this.grid = false,
    this.canWrite = true,
    this.provider,
  });

  bool get hasMore => items.length < total;
  int get folderCount => items.where((e) => e.isDir).length;
  int get fileCount => items.where((e) => !e.isDir).length;
  List<FileItem> get selectedItems => items.where((e) => selected.contains(e.name)).toList();

  FilesState copyWith({
    String? path,
    String? serverId,
    List<FileItem>? items,
    int? total,
    int? page,
    bool? loading,
    bool? loadingMore,
    bool? showSkeleton,
    String? error,
    bool clearError = false,
    bool? offline,
    Set<String>? selected,
    String? orderBy,
    bool? desc,
    bool? grid,
    bool? canWrite,
    String? provider,
  }) =>
      FilesState(
        path: path ?? this.path,
        serverId: serverId ?? this.serverId,
        items: items ?? this.items,
        total: total ?? this.total,
        page: page ?? this.page,
        loading: loading ?? this.loading,
        loadingMore: loadingMore ?? this.loadingMore,
        showSkeleton: showSkeleton ?? this.showSkeleton,
        error: clearError ? null : (error ?? this.error),
        offline: offline ?? this.offline,
        selected: selected ?? this.selected,
        orderBy: orderBy ?? this.orderBy,
        desc: desc ?? this.desc,
        grid: grid ?? this.grid,
        canWrite: canWrite ?? this.canWrite,
        provider: provider ?? this.provider,
      );
}

class FilesNotifier extends StateNotifier<FilesState> {
  final Ref ref;
  Timer? _skeletonTimer;
  int _seq = 0;

  FilesNotifier(this.ref) : super(const FilesState());

  static const perPage = 100;

  OpenListApi? get _api => ref.read(sessionProvider).api;

  /// Binds the controller to the active instance. Restores the per-server
  /// browse position when the profile asks for it.
  Future<void> attach() async {
    final session = ref.read(sessionProvider);
    final profile = session.profile;
    if (profile == null) {
      state = const FilesState();
      return;
    }
    if (state.serverId == profile.id && state.items.isNotEmpty) return;
    final browse = ref.read(serverStoreProvider).readBrowse(profile.id);
    final start = profile.rememberBrowse ? (browse['path'] as String? ?? '/') : '/';
    final orderBy = (browse['order_by'] as String?) ?? 'name';
    final desc = (browse['order_direction'] as String?) == 'desc';
    state = FilesState(serverId: profile.id, path: start, orderBy: orderBy, desc: desc, grid: state.grid);
    await open(start);
  }

  Future<void> open(String path, {bool refresh = false}) async {
    final api = _api;
    final profile = ref.read(sessionProvider).profile;
    if (api == null || profile == null) return;
    final normalized = path.isEmpty ? '/' : path;
    _seq++;
    final seq = _seq;
    _skeletonTimer?.cancel();
    state = state.copyWith(
      path: normalized,
      loading: true,
      showSkeleton: false,
      // v1.0.38：不再清空 items。清空会让列表区立刻塌成骨架屏，
      // 每次进/出子目录都闪一下；保留旧列表直到新数据到达更平稳
      //（面包屑已经变成新路径，列表在几百毫秒内替换）。
      // 骨架屏只用于「超过 400ms 仍未返回」（showSkeleton 由 _skeletonTimer 置位）。
      total: 0,
      page: 1,
      selected: const {},
      clearError: true,
      offline: false,
    );
    _skeletonTimer = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      if (seq == _seq && state.loading) {
        state = state.copyWith(showSkeleton: true);
      }
    });
    try {
      final result = await api.list(
        path: normalized,
        page: 1,
        perPage: perPage,
        refresh: refresh,
        orderBy: state.orderBy,
        orderDirection: state.desc ? 'desc' : 'asc',
      );
      if (seq != _seq || !mounted) return;
      final store = ref.read(serverStoreProvider);
      state = state.copyWith(
        items: result.items,
        total: result.total,
        loading: false,
        showSkeleton: false,
        canWrite: result.write,
        provider: result.provider,
        offline: false,
        clearError: true,
      );
      await store.saveBrowse(profile.id, normalized, state.orderBy, state.desc);
      await store.cacheListing(profile.id, normalized, result.items.map((e) => e.toJson()).toList());
    } on ApiException catch (e) {
      if (seq != _seq || !mounted) return;
      if (e.needsReauth) {
        await ref.read(sessionProvider.notifier).expire();
      }
      final store = ref.read(serverStoreProvider);
      final cached = store.readCachedListing(profile.id, normalized);
      final rawItems = cached['items'];
      final cachedItems = <FileItem>[];
      if (rawItems is List) {
        for (final raw in rawItems) {
          if (raw is Map) cachedItems.add(FileItem.fromJson(Map<String, dynamic>.from(raw)));
        }
      }
      state = state.copyWith(
        loading: false,
        showSkeleton: false,
        error: e.friendly,
        items: cachedItems.isEmpty ? state.items : cachedItems,
        total: cachedItems.isEmpty ? state.total : cachedItems.length,
        offline: cachedItems.isNotEmpty && e.network,
      );
    }
  }

  Future<void> refresh() => open(state.path, refresh: true);

  Future<void> loadMore() async {
    final api = _api;
    if (api == null || state.loading || state.loadingMore || !state.hasMore) return;
    final seq = _seq;
    state = state.copyWith(loadingMore: true);
    try {
      final nextPage = state.page + 1;
      final result = await api.list(
        path: state.path,
        page: nextPage,
        perPage: perPage,
        orderBy: state.orderBy,
        orderDirection: state.desc ? 'desc' : 'asc',
      );
      if (!mounted || seq != _seq) return;
      // v1.0.23：服务端分页在增删文件后可能返回重复条目，按 name 去重，
      // 否则列表里会出现两条相同文件（选择、批量操作都会跟着错）。
      final merged = <String, FileItem>{for (final item in state.items) item.name: item};
      for (final item in result.items) {
        merged.putIfAbsent(item.name, () => item);
      }
      state = state.copyWith(
        items: merged.values.toList(),
        total: result.total,
        page: nextPage,
        loadingMore: false,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      state = state.copyWith(loadingMore: false, error: e.friendly);
    }
  }

  Future<void> goUp() => open(parentOf(state.path));

  Future<void> setSort(String orderBy, {bool? desc}) async {
    final nextDesc = desc ?? (state.orderBy == orderBy ? !state.desc : false);
    state = state.copyWith(orderBy: orderBy, desc: nextDesc);
    await open(state.path, refresh: true);
  }

  void toggleGrid() => state = state.copyWith(grid: !state.grid);

  void toggleSelect(String name) {
    final next = {...state.selected};
    if (!next.remove(name)) next.add(name);
    state = state.copyWith(selected: next);
  }

  void selectAll() {
    state = state.copyWith(selected: state.items.map((e) => e.name).toSet());
  }

  /// 只勾选给定名字（批量「全选」用：仅作用于当前筛选结果）。
  void selectOnly(Iterable<String> names) {
    state = state.copyWith(selected: names.toSet());
  }

  void clearSelection() => state = state.copyWith(selected: const {});

  Future<String?> mutate(Future<void> Function(OpenListApi api) action, {bool refreshAfter = true}) async {
    final api = _api;
    if (api == null) return '尚未连接服务器';
    try {
      await action(api);
      if (refreshAfter) await refresh();
      return null;
    } on ApiException catch (e) {
      if (e.needsReauth) await ref.read(sessionProvider.notifier).expire();
      return e.friendly;
    }
  }

}
