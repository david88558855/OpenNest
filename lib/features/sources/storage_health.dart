import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/openlist_api.dart';
import '../../core/models/storage_source.dart';
import 'sources_controller.dart';

/// 单个存储源的健康快照。
///
/// 「健康」不等于「引擎怎么说」：引擎的 `storage.status` 只在它真的访问过
/// 该驱动时才会更新（初始化成功后就一直是 work），换网络、远端关机、令牌
/// 过期这些都可能让它继续显示「正常」。所以这里维护的是一份**我们主动探测
/// 出来**的结论，按源独立更新。
class StorageHealth {
  final int id;

  /// 上一次探测的结论：能否真的列出该源的根目录。
  final bool online;

  /// 正在探测（还没有新结论时界面显示「检测中」）。
  final bool probing;

  /// 失联原因，可直接展示给用户。
  final String? message;

  /// 本次结论的产生时间。
  final DateTime checkedAt;

  /// 探测耗时（毫秒），用来区分「慢但通」和「不通」。
  final int latencyMs;

  const StorageHealth({
    required this.id,
    required this.online,
    required this.checkedAt,
    this.probing = false,
    this.message,
    this.latencyMs = 0,
  });

  StorageHealth copyWith({
    bool? online,
    bool? probing,
    String? message,
    bool clearMessage = false,
    DateTime? checkedAt,
    int? latencyMs,
  }) =>
      StorageHealth(
        id: id,
        online: online ?? this.online,
        probing: probing ?? this.probing,
        message: clearMessage ? null : (message ?? this.message),
        checkedAt: checkedAt ?? this.checkedAt,
        latencyMs: latencyMs ?? this.latencyMs,
      );
}

/// 路径属于哪个存储源：按挂载路径前缀匹配，取最长前缀（支持嵌套挂载）。
StorageSource? sourceForPath(List<StorageSource> sources, String path) {
  StorageSource? best;
  for (final source in sources) {
    final mount = source.mountPath;
    if (mount.isEmpty) continue;
    if (path == mount || path.startsWith('$mount/')) {
      if (best == null || mount.length > best.mountPath.length) best = source;
    }
  }
  return best;
}

final storageHealthProvider =
    StateNotifierProvider<StorageHealthNotifier, Map<int, StorageHealth>>((ref) {
  final notifier = StorageHealthNotifier(ref);
  ref.onDispose(notifier.dispose);
  return notifier;
});

/// 存储源状态的自动刷新器。
///
/// 三层节奏，都不依赖用户手动操作：
/// 1. **快速轮询（25s）**：只拉一次引擎的存储列表，让引擎自己报的
///    `status` 跟着刷新（开销一次 GET）。
/// 2. **深度探测（90s）**：逐个源真打一次 `fs/list`（`refresh: true`，
///    绕过引擎的目录缓存），确认「此刻」是否可达。换网络、远端关机这类
///    情况只有真访问才能发现。
/// 3. **事件触发**：传输结束、进入设置页、应用回到前台时立刻补一次探测。
///
/// 每个源的结论各自独立写入（[StorageHealth]），所以 A 源失联不会影响
/// B 源继续显示正常，也不会出现「整表一起变红」的假象。
class StorageHealthNotifier extends StateNotifier<Map<int, StorageHealth>> {
  StorageHealthNotifier(this._ref) : super(const {});

  final Ref _ref;

  /// 引擎存储列表轮询间隔。
  static const Duration pollInterval = Duration(seconds: 25);

  /// 深度探测间隔。10 分钟无人操作也至少能探测 6 轮。
  static const Duration probeInterval = Duration(seconds: 90);

  /// 单源探测上限。超过就判失联 —— 界面不能等引擎驱动的超时。
  static const Duration probeTimeout = Duration(seconds: 12);

  /// 并发探测数：每个探测都是一次真实的远端访问，别把引擎和网络打满。
  static const int probeConcurrency = 3;

  Timer? _pollTimer;
  Timer? _probeTimer;
  Timer? _debounce;
  bool _probing = false;

  /// 探测进行中时又来了一次请求 —— 当前轮结束后补跑。
  ///
  /// 0.5.9：以前探测期间触发的刷新被直接丢弃。多源 × 12 秒超时意味着
  /// 一轮探测可能持续几十秒，这段时间里「传输失败后立刻标红」的请求
  /// 正好会丢，界面要干等下一个 90 秒周期。
  bool _probePending = false;
  final Set<int> _inflight = {};
  DateTime? _lastProbe;

  /// 最近一次完整探测的完成时间（设置页显示「最后检测」用）。
  DateTime? get lastProbeAt => _lastProbe;

  /// 挂在应用根节点上：开始周期刷新，并立刻探一轮。
  void attach() {
    _pollTimer ??= Timer.periodic(pollInterval, (_) => _pollEngineList());
    _probeTimer ??= Timer.periodic(probeInterval, (_) => unawaited(probeAll()));
    unawaited(probeAll());
  }

  void detach() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _probeTimer?.cancel();
    _probeTimer = null;
    _debounce?.cancel();
    _debounce = null;
  }

  @override
  void dispose() {
    detach();
    super.dispose();
  }

  /// 传输结束（成功/失败/取消）后调用。
  ///
  /// 用 3 秒合并窗口：批量下载 1000 个文件时不会每个任务都触发一轮探测。
  void scheduleRefresh() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 3), () {
      _ref.invalidate(sourcesProvider);
      unawaited(probeAll());
    });
  }

  /// 立刻刷新：拉一次列表 + 探一轮（进入设置页、回到前台时用）。
  Future<void> refreshNow() async {
    if (_api() == null) return;
    _ref.invalidate(sourcesProvider);
    await probeAll();
  }

  /// 数据够新就不重复探测，避免每次重建设置页都打一轮。
  Future<void> probeIfStale({Duration maxAge = const Duration(seconds: 20)}) async {
    final last = _lastProbe;
    if (last != null && DateTime.now().difference(last) < maxAge) return;
    await refreshNow();
  }

  /// 逐个源探测（每批 [probeConcurrency] 个并发，批次之间串行）。
  Future<void> probeAll() async {
    if (_probing) {
      // 记一笔，等当前轮跑完再补一轮，别把这次刷新吞掉。
      _probePending = true;
      return;
    }
    final api = _api();
    if (api == null) return;
    _probing = true;
    try {
      List<StorageSource> sources;
      try {
        sources = await _ref.read(sourcesProvider.future).timeout(const Duration(seconds: 10));
      } catch (_) {
        // 列表都读不到（引擎忙/未登录）：保留上一次结论，别把状态清空。
        return;
      }
      final targets = sources.where((s) => !s.disabled && s.mountPath.isNotEmpty).toList();
      // 已删除 / 已停用的源不再保留旧结论。
      final keep = targets.map((s) => s.id).toSet();
      if (state.keys.any((id) => !keep.contains(id))) {
        state = {
          for (final entry in state.entries)
            if (keep.contains(entry.key)) entry.key: entry.value,
        };
      }
      for (var i = 0; i < targets.length; i += probeConcurrency) {
        final batch = targets.skip(i).take(probeConcurrency).toList();
        await Future.wait(batch.map((s) => _probeOne(api, s)));
      }
      _lastProbe = DateTime.now();
    } finally {
      _probing = false;
      if (_probePending) {
        _probePending = false;
        unawaited(probeAll());
      }
    }
  }

  /// 文件页成功列出某目录 → 该源此刻肯定可达，立刻置为在线（不必等探测周期）。
  void observeReachable(String path) {
    final source = _sourceOf(path);
    if (source == null) return;
    _put(StorageHealth(
      id: source.id,
      online: true,
      checkedAt: DateTime.now(),
      latencyMs: state[source.id]?.latencyMs ?? 0,
    ));
  }

  /// 文件页列出某目录失败 → 该源此刻不可达，立刻反映出来。
  ///
  /// 这是「打开目录就发现失联」的最快路径：不用等 90 秒的探测周期。
  /// 只有「网络 / 授权 / 服务端」类错误才算这个源失联；404 这类是
  /// **路径**问题（子目录被删了），不该把整个源标红。
  void observeUnreachable(String path, ApiException error) {
    final fatal = error.network || error.needsReauth || (error.httpStatus ?? error.code) >= 500;
    if (!fatal) return;
    final source = _sourceOf(path);
    if (source == null) return;
    final message = _reasonOf(error);
    final previous = state[source.id];
    // 同一个原因不重复写状态，避免文件页重试时抖动。
    if (previous != null && !previous.online && previous.message == message) return;
    _put(StorageHealth(
      id: source.id,
      online: false,
      checkedAt: DateTime.now(),
      message: message,
      latencyMs: previous?.latencyMs ?? 0,
    ));
  }

  // ------------------------------------------------------------------ 内部

  OpenListApi? _api() {
    final session = _ref.read(sessionProvider);
    if (!session.signedIn) return null;
    return session.api;
  }

  StorageSource? _sourceOf(String path) {
    if (path.isEmpty) return null;
    final sources = _ref.read(sourcesProvider).valueOrNull ?? const <StorageSource>[];
    final source = sourceForPath(sources, path);
    if (source == null || source.disabled) return null;
    return source;
  }

  void _pollEngineList() {
    if (_api() == null) return;
    // 只刷新引擎侧列表（status 字段）；探测结论由 _probeOne 单独维护，
    // 不会被这次刷新覆盖。
    _ref.invalidate(sourcesProvider);
    // 引擎刚就绪（还没有任何结论）或上一轮结论已经过期：顺带补一轮探测。
    // 否则冷启动后要干等一个完整探测周期，界面会长时间停在「待加载」。
    final last = _lastProbe;
    if (last == null || DateTime.now().difference(last) > probeInterval) {
      unawaited(probeAll());
    }
  }

  Future<void> _probeOne(OpenListApi api, StorageSource source) async {
    if (_inflight.contains(source.id)) return;
    _inflight.add(source.id);
    final previous = state[source.id];
    _put(StorageHealth(
      id: source.id,
      online: previous?.online ?? false,
      probing: true,
      message: previous?.message,
      checkedAt: previous?.checkedAt ?? DateTime.now(),
      latencyMs: previous?.latencyMs ?? 0,
    ));

    final cancelToken = CancelToken();
    final watch = Stopwatch()..start();
    try {
      // refresh: true 绕过引擎的目录缓存 —— 用缓存命中的结果判「在线」，
      // 正好会把已经失联的源继续显示成正常。
      await api
          .list(path: source.mountPath, perPage: 1, refresh: true, cancelToken: cancelToken)
          .timeout(probeTimeout);
      _put(StorageHealth(
        id: source.id,
        online: true,
        checkedAt: DateTime.now(),
        latencyMs: watch.elapsedMilliseconds,
      ));
    } on TimeoutException {
      // 客户端超时必须把请求也取消掉，否则引擎那边会一直挂着一个
      // driver 调用（源多了会累积）。
      cancelToken.cancel('探测超时');
      _put(StorageHealth(
        id: source.id,
        online: false,
        checkedAt: DateTime.now(),
        message: '${probeTimeout.inSeconds} 秒内无响应（远端可能已不可达）',
        latencyMs: watch.elapsedMilliseconds,
      ));
    } on ApiException catch (error) {
      _put(StorageHealth(
        id: source.id,
        online: false,
        checkedAt: DateTime.now(),
        message: _reasonOf(error),
        latencyMs: watch.elapsedMilliseconds,
      ));
    } catch (error) {
      _put(StorageHealth(
        id: source.id,
        online: false,
        checkedAt: DateTime.now(),
        message: _clip('$error'),
        latencyMs: watch.elapsedMilliseconds,
      ));
    } finally {
      _inflight.remove(source.id);
    }
  }

  void _put(StorageHealth health) {
    if (!mounted) return;
    state = {...state, health.id: health};
  }

  String _reasonOf(ApiException error) {
    if (error.needsReauth) return '授权已失效，需要重新登录该源';
    if (error.rateLimited) return '请求过于频繁，稍后自动重试';
    if (error.network) return '连接超时或远端不可达';
    final message = error.message.trim();
    if (message.isEmpty) return '连接失败（${error.code}）';
    return _clip(message);
  }

  String _clip(String value) {
    final text = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return text.length > 60 ? '${text.substring(0, 59)}…' : text;
  }
}
