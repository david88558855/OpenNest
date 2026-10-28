import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/openlist_api.dart';
import '../../core/format.dart';
import '../../core/models/api_types.dart';
import '../../core/models/storage_source.dart';
import '../../data/db/app_database.dart';
import '../sources/sources_controller.dart';
import '../sources/storage_health.dart';

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

  /// 最近一次**成功**打开的目录。
  ///
  /// 0.5.11：新目录加载失败且没有缓存时，列表会保留上一个目录的内容
  /// （避免闪成空白），但 `path` 已经是新路径 —— 两者不一致时，删除 / 重命名
  /// 会按「新目录 + 旧条目名」拼路径，命中同名文件。所以失败时把 path
  /// 回滚到这里，界面停在原目录 + 错误条。
  String _lastGoodPath = '/';

  FilesNotifier(this.ref) : super(const FilesState());

  static const perPage = 100;

  /// 0.5.9：骨架屏定时器必须在这里取消。
  /// 以前没有 dispose，ProviderScope 重建或退出应用后定时器仍会挂一次
  /// （回调有 mounted 守卫，不会崩，但属于资源泄漏）。
  @override
  void dispose() {
    _skeletonTimer?.cancel();
    _skeletonTimer = null;
    super.dispose();
  }

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
    if (api == null || profile == null) {
      // 引擎没起来（降级模式）时不要静默返回空列表 —— 那看起来就像
      // 「这个目录里什么都没有」。给一条明确的原因，用户才知道该去
      // 「设置 → 通用」启动引擎。
      _skeletonTimer?.cancel();
      state = state.copyWith(
        loading: false,
        showSkeleton: false,
        // 两种「还没就绪」要说清楚，别让用户以为目录是空的：
        // - 没有 api：引擎进程没起来（降级模式），去设置里启动/重启；
        // - 有 api 但没有 profile：引擎活着，但会话还没建立 —— 通常是
        //   StoragesLoaded 中间件还挂着（某个换过网络的存储源连不上）。
        error: api == null
            ? '内嵌引擎未就绪，无法列出目录。可在「设置 → 通用」启动或重启引擎。'
            : '引擎仍在加载存储源，暂时无法列出目录。换过网络、原地址已不可达的存储源会卡很久 —— '
                '可在「设置 → 存储源」停用该源，或在启动页用「安全模式启动」。',
      );
      return;
    }
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
      //
      // 0.5.11：loadingMore 必须归零。以前切目录时不清，而 loadMore 在
      // 「代次已过期」的分支直接 return（不复位）—— 一次「滚到底 + 立刻切
      // 目录」之后 loadingMore 永久为 true，「加载更多」再也发不出去。
      total: 0,
      page: 1,
      loadingMore: false,
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
      _lastGoodPath = normalized;
      final store = ref.read(serverStoreProvider);
      // 0.5.0：根目录下的每一项就是一个存储源的挂载点。引擎返回的名字
      // 就是挂载路径段 —— 新建的存储由用户命名（`本地存储6`），与 OpenList
      // Web 一致；旧存储是自动生成的 `s_aaaaaaaa`，这里统一还原成用户
      // 当初起的名字。只改展示名，路径拼接仍用原始 name。
      final known = ref.read(sourcesProvider).valueOrNull ?? const <StorageSource>[];
      final items = normalized == '/'
          ? _withSourceNames(result.items, known)
          : result.items;
      state = state.copyWith(
        items: items,
        total: result.total,
        loading: false,
        showSkeleton: false,
        canWrite: result.write,
        provider: result.provider,
        offline: false,
        clearError: true,
      );
      // 写浏览位置前再确认一次代次：用户快速连续导航时，早先那次请求的
      // await 可能晚一步回来，把「上次位置」写成中间那个目录。
      if (seq == _seq) {
        await store.saveBrowse(profile.id, normalized, state.orderBy, state.desc);
      }
      await store.cacheListing(profile.id, normalized, items.map((e) => e.toJson()).toList());
      // 目录真的列出来了 → 这个源此刻可达，立刻把状态刷成正常，
      // 不必等 90 秒的深度探测周期。
      ref.read(storageHealthProvider.notifier).observeReachable(normalized);
      // 0.5.0：记录本次访问的存储源，设置页「最近使用」列要用。
      // 路径形如 `/本地存储6/子目录`，取第一段作为源标识。
      // 挂载路径由用户命名，没有固定前缀，只能对照已知源列表判断。
      final sourceId = _sourceIdOfPath(normalized, known);
      if (sourceId.isNotEmpty) {
        await SourceUsageDao.instance.touch(sourceId);
        ref.invalidate(sourceUsageProvider);
      }
    } on ApiException catch (e) {
      if (seq != _seq || !mounted) return;
      if (e.needsReauth) {
        await ref.read(sessionProvider.notifier).expire();
      }
      // 这个目录打不开 → 若是网络/授权/服务端类错误，该源此刻不可达，
      // 立刻反映到存储列表里（404 之类属于路径问题，不标源失联）。
      ref.read(storageHealthProvider.notifier).observeUnreachable(normalized, e);
      final store = ref.read(serverStoreProvider);
      final cached = store.readCachedListing(profile.id, normalized);
      final rawItems = cached['items'];
      final cachedItems = <FileItem>[];
      if (rawItems is List) {
        for (final raw in rawItems) {
          if (raw is Map) cachedItems.add(FileItem.fromJson(Map<String, dynamic>.from(raw)));
        }
      }
      // 离线回读同样要把根目录的挂载点换成存储源名称，否则一断网
      // 根目录就退回显示 s_xxxxxxxx，与在线时表现不一致。
      final cachedKnown = ref.read(sourcesProvider).valueOrNull ?? const <StorageSource>[];
      final cachedItems2 = normalized == '/' ? _withSourceNames(cachedItems, cachedKnown) : cachedItems;
      // 没有该目录的离线快照时，列表保留的是上一个目录的内容：这时把 path
      // 一起回滚，否则「面包屑 = 新目录、条目 = 旧目录」，而删除 / 重命名
      // 是按 state.path + 条目名拼路径的，会误伤新目录里的同名文件。
      final keepingPrevious = cachedItems2.isEmpty;
      state = state.copyWith(
        path: keepingPrevious ? _lastGoodPath : normalized,
        loading: false,
        showSkeleton: false,
        error: e.friendly,
        items: cachedItems2.isEmpty ? state.items : cachedItems2,
        total: cachedItems2.isEmpty ? state.total : cachedItems2.length,
        offline: cachedItems2.isNotEmpty && e.network,
      );
    } catch (e) {
      // 非 ApiException（本地 JSON 解析异常、数据库写入失败等）：同样要把
      // loading / showSkeleton 复位，否则界面永远停在骨架屏且没有任何提示。
      if (seq != _seq || !mounted) return;
      state = state.copyWith(
        path: _lastGoodPath,
        loading: false,
        showSkeleton: false,
        error: '打开目录失败：$e',
      );
    }
  }

  Future<void> refresh() async {
    // 会话还没建立（引擎在加载存储源）时，先补一次会话再重开当前路径；
    // 否则「重试」只会反复刷同一条错误，用户没法从这个状态里恢复。
    if (ref.read(sessionProvider).profile == null) {
      try {
        await ref.read(sessionProvider.notifier).retry();
      } catch (_) {}
      if (!mounted) return;
      await attach();
      return;
    }
    await open(state.path, refresh: true);
  }

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
      if (!mounted) return;
      // 0.5.11：代次过期也要把 loadingMore 复位 —— 否则「滚到底的同时切目录」
      // 之后 state.loadingMore 永久为 true，loadMore 的入口守卫会把后续
      // 所有「加载更多」都拦掉。
      if (seq != _seq) {
        state = state.copyWith(loadingMore: false);
        return;
      }
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
      // 旧目录请求的失败不能盖到新目录上：只在代次仍有效时写 error。
      if (seq != _seq) {
        state = state.copyWith(loadingMore: false);
        return;
      }
      state = state.copyWith(loadingMore: false, error: e.friendly);
    } catch (_) {
      // 非 ApiException（解析 / 本地 IO）：至少把 loadingMore 复位，
      // 否则「加载更多」永久失效。
      if (!mounted) return;
      state = state.copyWith(loadingMore: false);
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

/// 从路径里取出存储源标识（挂载路径首段）。
///
/// 路径形如 `/本地存储6/子目录/文件`，源标识就是 `/本地存储6`。
/// 根路径（`/`）与不存在的标识返回空串。
///
/// 挂载路径由用户命名（与 OpenList Web 一致），没有固定前缀，
/// 所以只能对照已知的存储源列表来判断首段是不是某个源 ——
/// 不能只按字符串特征猜，否则会把普通目录名误当源。
String _sourceIdOfPath(String path, List<StorageSource> sources) {
  final normalized = path.isEmpty ? '/' : path;
  if (normalized == '/') return '';
  final segments = normalized.split('/').where((e) => e.isNotEmpty).toList();
  if (segments.isEmpty) return '';
  final first = segments.first;
  for (final source in sources) {
    final mount = source.mountPath;
    if (mount.isEmpty) continue;
    final seg = mount.startsWith('/') ? mount.substring(1) : mount;
    if (seg == first) return '/$first';
  }
  return '';
}

/// 把根目录下的挂载点项的展示名换成存储源名称。
///
/// 两种情况：
/// - 新建的存储：挂载路径由用户命名（`/本地存储6`），引擎在根目录返回的
///   目录名就是「本地存储6」，与 OpenList Web 的表现一致 —— 此时这里
///   是 no-op（显示名与目录名相同）。
/// - 0.5.0 之前建的存储：挂载路径是自动生成的 `/s_xxxxxxxx`，根目录会
///   显示一堆无意义的路径段。这里按挂载路径段匹配存储源，取其 remark
///   还原成用户当初起的名字。
///
/// 只改 [FileItem.displayName]，[FileItem.name] 保持不变 —— 后者参与
/// 路径拼接（`joinPath(path, item.name)`），改了会跳错目录。
List<FileItem> _withSourceNames(List<FileItem> items, List<StorageSource> sources) {
  if (items.isEmpty) return items;
  if (sources.isEmpty) return items;
  // 挂载路径段 → 存储源
  final byMount = <String, StorageSource>{};
  for (final source in sources) {
    final mount = source.mountPath;
    if (mount.isEmpty) continue;
    byMount[mount.startsWith('/') ? mount.substring(1) : mount] = source;
  }
  if (byMount.isEmpty) return items;
  return items.map((item) {
    final source = byMount[item.name];
    if (source == null) return item;
    final label = source.displayName;
    if (label.isEmpty || label == item.name) return item;
    return FileItem(
      name: item.name,
      size: item.size,
      isDir: item.isDir,
      modified: item.modified,
      sign: item.sign,
      thumb: item.thumb,
      type: item.type,
      hashInfo: item.hashInfo,
      parent: item.parent,
      provider: item.provider,
      displayName: label,
    );
  }).toList();
}
