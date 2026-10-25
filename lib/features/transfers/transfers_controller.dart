import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/openlist_api.dart';
import '../../core/models/api_types.dart';
import '../../core/models/server_profile.dart';
import '../../core/models/transfer_task.dart';
import '../../core/storage/download_paths.dart';
import '../../core/storage/prefs.dart';

class TransfersState {
  final List<TransferTask> tasks;
  final List<ServerTask> serverTasks;
  final double downSpeed;
  final double upSpeed;
  final int concurrency;
  final bool pausedGlobally;
  final String? error;

  const TransfersState({
    this.tasks = const [],
    this.serverTasks = const [],
    this.downSpeed = 0,
    this.upSpeed = 0,
    this.concurrency = 2,
    this.pausedGlobally = false,
    this.error,
  });

  List<TransferTask> get active => tasks.where((e) => e.status == TransferStatus.running).toList();
  List<TransferTask> get queued => tasks.where((e) => e.status == TransferStatus.queued).toList();
  List<TransferTask> get paused => tasks.where((e) => e.status == TransferStatus.paused).toList();
  List<TransferTask> get done => tasks.where((e) => e.status == TransferStatus.done).toList();
  List<TransferTask> get failed => tasks.where((e) => e.status == TransferStatus.failed).toList();
  int get pendingCount => tasks.where((e) => e.status == TransferStatus.running || e.status == TransferStatus.queued).length;

  TransfersState copyWith({
    List<TransferTask>? tasks,
    List<ServerTask>? serverTasks,
    double? downSpeed,
    double? upSpeed,
    int? concurrency,
    bool? pausedGlobally,
    String? error,
    bool clearError = false,
  }) =>
      TransfersState(
        tasks: tasks ?? this.tasks,
        serverTasks: serverTasks ?? this.serverTasks,
        downSpeed: downSpeed ?? this.downSpeed,
        upSpeed: upSpeed ?? this.upSpeed,
        concurrency: concurrency ?? this.concurrency,
        pausedGlobally: pausedGlobally ?? this.pausedGlobally,
        error: clearError ? null : (error ?? this.error),
      );
}

class TransfersNotifier extends StateNotifier<TransfersState> {
  final Ref ref;
  final Map<String, CancelToken> _tokens = {};
  final Map<String, int> _previousDone = {};

  /// 因「全部暂停」而暂停的任务 id；「全部继续」只恢复这些（v1.0.23）。
  final Set<String> _pausedByGlobal = {};
  Timer? _ticker;
  DateTime _lastEmit = DateTime.fromMillisecondsSinceEpoch(0);
  bool _pumping = false;
  ProviderSubscription<AppSettings>? _settingsSub;

  /// 缓存 prefs：dispose 时 ref 已失效，但合并窗口里的状态还得落盘。
  final Prefs _prefs;

  TransfersNotifier(this.ref)
      : _prefs = ref.read(prefsProvider),
        super(const TransfersState()) {
    state = state.copyWith(concurrency: ref.read(appSettingsProvider).concurrency);
    // v2.6：设置页改并发数后立即生效。之前只在构造时读一次，必须重启应用才生效。
    _settingsSub = ref.listen<AppSettings>(appSettingsProvider, (previous, next) {
      if (previous?.concurrency == next.concurrency) return;
      if (state.concurrency != next.concurrency) {
        state = state.copyWith(concurrency: next.concurrency);
      }
      unawaited(_pump());
    });
    _restore();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  static const _persistKey = 'ol_transfers';

  /// 下载限速（字节/秒），每个数据块都重新读取，运行中改设置即时生效。
  int _downRate() => ref.read(appSettingsProvider).downLimitKbps * 1024;

  /// 上传限速（字节/秒），同上。
  int _upRate() => ref.read(appSettingsProvider).upLimitKbps * 1024;

  @override
  void dispose() {
    // 合并窗口内的改动必须立即落盘，否则退出应用会丢任务列表
    _persistNow();
    _settingsSub?.close();
    _ticker?.cancel();
    for (final token in _tokens.values) {
      token.cancel();
    }
    super.dispose();
  }

  void _restore() {
    final raw = ref.read(prefsProvider).getJsonList(_persistKey);
    final restored = <TransferTask>[];
    for (final e in raw) {
      if (e is Map) {
        final task = TransferTask.fromJson(Map<String, dynamic>.from(e));
        if (task.status == TransferStatus.running || task.status == TransferStatus.queued) {
          task.status = TransferStatus.paused;
        }
        if (task.status != TransferStatus.done) restored.add(task);
      }
    }
    if (restored.isNotEmpty) {
      state = state.copyWith(tasks: restored);
    }
  }

  Timer? _persistTimer;

  /// v1.0.44：落盘改为 400ms 合并。
  ///
  /// `_persist` 会把**全部任务**序列化成 JSON，而 `_run` 的 finally 每个任务都调一次：
  /// 1000 个任务的批量下载 = 1000 次全量序列化，持续占用主线程。
  /// 合并后一批任务结束只写一次（prefs 内部还有 250ms 落盘合并，双保险）。
  void _persist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 400), _persistNow);
  }

  void _persistNow() {
    _persistTimer?.cancel();
    _persistTimer = null;
    final list = state.tasks
        .where((e) => e.status == TransferStatus.paused || e.status == TransferStatus.queued || e.status == TransferStatus.running || e.status == TransferStatus.failed)
        .map((e) => e.toJson())
        .toList();
    _prefs.setJsonList(_persistKey, list);
  }

  void _emit() => state = state.copyWith(tasks: List<TransferTask>.of(state.tasks));

  void _emitThrottled() {
    final now = DateTime.now();
    if (now.difference(_lastEmit).inMilliseconds < 150) return;
    _lastEmit = now;
    _emit();
  }

  void _tick() {
    if (!mounted) return;
    // 没有任务时不要每秒重建一次状态（空列表也要触发全局重建，纯浪费）。
    if (state.tasks.isEmpty) return;
    var down = 0.0;
    var up = 0.0;
    for (final task in state.tasks) {
      final previous = _previousDone[task.id] ?? task.done;
      final delta = task.done - previous;
      _previousDone[task.id] = task.done;
      if (task.status == TransferStatus.running) {
        task.speed = delta < 0 ? 0 : delta.toDouble();
        if (task.kind == TransferKind.download) {
          down += task.speed;
        } else {
          up += task.speed;
        }
      } else {
        task.speed = 0;
      }
    }
    state = state.copyWith(tasks: List<TransferTask>.of(state.tasks), downSpeed: down, upSpeed: up);
  }

  // ------------------------------------------------------------- enqueue

  Future<String?> enqueueDownload(FileItem item, String currentDir, {bool schedule = true}) async {
    if (item.isDir) return '暂不支持整目录下载';
    // v1.0.37：`item.parent` 可能是空串（不是 null），`??` 不会回退，
    // 会拼出空的远端路径；统一按「空则用当前目录 + 文件名」处理。
    final parent = item.parent?.trim();
    final remotePath = (parent == null || parent.isEmpty)
        ? (currentDir == '/' ? '/${item.name}' : '$currentDir/${item.name}')
        : parent;
    return enqueueDownloadInto(item: item, remotePath: remotePath, localSubdir: '', schedule: schedule);
  }

  /// 批量入队后统一调度一次（配合 `schedule: false` 使用）。
  ///
  /// v1.0.34：_persist 会把**全部任务**序列化成 JSON。批量入队 1000 个文件时，
  /// 每个任务都 persist 一次 = 1000 次全量序列化，直接卡主线程。
  /// 因此批量路径统一走「入队时不 persist、kick 时补一次」。
  Future<void> kick() async {
    _persist();
    _emit();
    await _pump();
  }

  /// 入队一个下载任务，可指定本地相对子目录（v1.0.31）。
  ///
  /// 文件夹递归下载时，每个文件带着自己的相对子目录进来，落盘后与远端结构一致。
  /// [localSubdir] 用 `/` 分隔，调用方需保证每级已过 `safePathSegment`。
  Future<String?> enqueueDownloadInto({
    required FileItem item,
    required String remotePath,
    required String localSubdir,
    bool schedule = true,
  }) async {
    final session = ref.read(sessionProvider);
    final profile = session.profile;
    if (profile == null || session.api == null) return '尚未连接服务器';
    if (item.isDir) return '暂不支持整目录下载';
    final root = await _downloadDir(profile);
    final dir = localSubdir.isEmpty ? root : '$root${Platform.pathSeparator}$localSubdir';
    try {
      await Directory(dir).create(recursive: true);
    } catch (error) {
      return '无法创建目录 $dir：$error';
    }
    // 同名文件不能互相覆盖：已在队列里的同一远程文件复用原路径（续传），
    // 否则在磁盘上顺延出「name (2).ext」。
    final localPath = _resolveLocalPath(dir, item.name, remotePath);
    final task = TransferTask(
      id: 'dl-${DateTime.now().microsecondsSinceEpoch}-${item.name.hashCode}',
      serverId: profile.id,
      serverLabel: profile.name,
      kind: TransferKind.download,
      name: item.name,
      remotePath: remotePath,
      localPath: localPath,
      localSubdir: localSubdir,
      total: item.size,
      sign: item.sign,
    );
    // v1.0.35：如果之前点过「全部暂停」，新任务会静默卡在 queued（列表里有、进度不动）。
    // 用户主动点下载就说明想让任务跑，这里直接解除全局暂停。
    state = state.copyWith(tasks: [task, ...state.tasks], clearError: true, pausedGlobally: false);
    if (schedule) {
      _persist();
      await _pump();
    }
    return null;
  }

  Future<String?> enqueueUpload({required String localPath, required String remoteDir, required String name}) async {
    final session = ref.read(sessionProvider);
    final profile = session.profile;
    if (profile == null || session.api == null) return '尚未连接服务器';
    final remotePath = remoteDir == '/' ? '/$name' : '$remoteDir/$name';
    int size = 0;
    try {
      size = await File(localPath).length();
    } catch (_) {
      size = 0;
    }
    final task = TransferTask(
      id: 'ul-${DateTime.now().microsecondsSinceEpoch}-${name.hashCode}',
      serverId: profile.id,
      serverLabel: profile.name,
      kind: TransferKind.upload,
      name: name,
      remotePath: remotePath,
      localPath: localPath,
      total: size,
    );
    state = state.copyWith(tasks: [task, ...state.tasks], clearError: true);
    _persist();
    await _pump();
    return null;
  }

  // --------------------------------------------------------------- control

  void pause(String id) {
    final task = _find(id);
    if (task == null) return;
    task.status = TransferStatus.paused;
    _tokens[id]?.cancel();
    _persist();
    _emit();
  }

  Future<void> resume(String id) async {
    final task = _find(id);
    if (task == null) return;
    _pausedByGlobal.remove(id);
    task.status = TransferStatus.queued;
    task.error = null;
    _emit();
    await _pump();
  }

  Future<void> retry(String id) async {
    final task = _find(id);
    if (task == null) return;
    _pausedByGlobal.remove(id);
    task.error = null;
    task.status = TransferStatus.queued;
    _emit();
    await _pump();
  }

  void remove(String id) {
    _tokens[id]?.cancel();
    _tokens.remove(id);
    _previousDone.remove(id);
    _pausedByGlobal.remove(id);
    final task = _find(id);
    if (task != null && task.status != TransferStatus.done) {
      try {
        final file = File(task.localPath);
        // 只清理未完成的半成品：完整文件（同名已下载完）不能因为移除任务被删掉。
        final complete = task.total > 0 && file.existsSync() && file.lengthSync() >= task.total;
        if (task.kind == TransferKind.download && file.existsSync() && !complete) {
          file.deleteSync();
        }
      } catch (_) {
        // ignore
      }
    }
    state = state.copyWith(tasks: state.tasks.where((e) => e.id != id).toList());
    _persist();
  }

  /// 批量移除（「清除失败 / 清除已完成」用）：一次状态更新 + 一次落盘。
  void clearTasks(List<String> ids) {
    if (ids.isEmpty) return;
    final set = ids.toSet();
    for (final id in set) {
      _tokens.remove(id);
      _pausedByGlobal.remove(id);
    }
    state = state.copyWith(tasks: state.tasks.where((e) => !set.contains(e.id)).toList());
    _persist();
  }

  void clearFinished() {
    state = state.copyWith(
      tasks: state.tasks.where((e) => e.status != TransferStatus.done && e.status != TransferStatus.failed).toList(),
    );
    _persist();
  }

  /// 全局暂停：只记录「被全局暂停」的任务，`resumeAll` 只恢复这些。
  /// 用户自己点暂停的任务不在集合里，不会被「全部继续」误拉起（v1.0.23）。
  Future<void> pauseAll() async {
    state = state.copyWith(pausedGlobally: true);
    for (final task in state.tasks) {
      if (task.status == TransferStatus.running || task.status == TransferStatus.queued) {
        task.status = TransferStatus.paused;
        _pausedByGlobal.add(task.id);
        _tokens[task.id]?.cancel();
      }
    }
    _persist();
    _emit();
  }

  Future<void> resumeAll() async {
    state = state.copyWith(pausedGlobally: false);
    final pending = {..._pausedByGlobal};
    _pausedByGlobal.clear();
    for (final task in state.tasks) {
      if (task.status == TransferStatus.paused && pending.contains(task.id)) {
        task.status = TransferStatus.queued;
      }
    }
    _emit();
    await _pump();
  }

  /// 并发数统一由设置持有；这里只做转发，避免出现「两个真相」。
  Future<void> setConcurrency(int value) async {
    ref.read(appSettingsProvider.notifier).setConcurrency(value);
    if (state.concurrency != value.clamp(1, 8).toInt()) {
      state = state.copyWith(concurrency: value.clamp(1, 8).toInt());
    }
    await _pump();
  }

  void clearError() => state = state.copyWith(clearError: true);

  // ---------------------------------------------------------------- worker

  TransferTask? _find(String id) {
    for (final t in state.tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  OpenListApi? _apiFor(String serverId) {
    final session = ref.read(sessionProvider);
    if (session.profile?.id == serverId) return session.api;
    return null;
  }

  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    try {
      if (!state.pausedGlobally) {
        var running = state.tasks.where((e) => e.status == TransferStatus.running).length;
        // 并发数为 0（异常值）会让下面直接 break，任务永远不启动
        final limit = state.concurrency > 0 ? state.concurrency : 1;
        for (final task in state.tasks.toList()) {
          if (running >= limit) break;
          if (task.status == TransferStatus.queued) {
            running++;
            unawaited(_run(task));
          }
        }
      }
    } finally {
      _pumping = false;
    }
  }

  Future<void> _run(TransferTask task) async {
    final api = _apiFor(task.serverId);
    if (api == null) {
      task.status = TransferStatus.paused;
      task.error = '切换了服务器，恢复后继续';
      _emit();
      return;
    }
    final token = CancelToken();
    _tokens[task.id] = token;
    task.status = TransferStatus.running;
    task.error = null;
    _emit();
    try {
      if (task.kind == TransferKind.download) {
        var sign = task.sign;
        if (sign == null || sign.isEmpty) {
          final info = await api.get(task.remotePath);
          sign = info.sign ?? '';
          task.sign = sign;
        }
        final target = File(task.localPath);
        await target.parent.create(recursive: true);
        final received = await api.downloadToFile(
          path: task.remotePath,
          sign: sign,
          target: target,
          cancelToken: token,
          throttleRate: _downRate,
          onProgress: (done, total) {
            task.done = done;
            if (total > 0) task.total = total;
            _emitThrottled();
          },
        );
        task.done = received;
        if (task.total <= 0) task.total = received;
        if (task.status != TransferStatus.paused) task.status = TransferStatus.done;
      } else {
        await api.uploadFile(
          remotePath: task.remotePath,
          source: File(task.localPath),
          cancelToken: token,
          // v2.6：上传限速同样每块重读，设置改动即时生效。
          throttleRate: _upRate,
          onProgress: (sent, total) {
            task.done = sent;
            if (total > 0) task.total = total;
            _emitThrottled();
          },
        );
        if (task.status != TransferStatus.paused) {
          task.done = task.total;
          task.status = TransferStatus.done;
        }
      }
    } on ApiException catch (e) {
      if (task.status != TransferStatus.paused) {
        task.status = TransferStatus.failed;
        // v1.0.33：下载走的是 /d/<path>?sign=，401 多半是签名过期而不是会话失效。
        // 批量下载文件夹时会入队大量任务，之前任何一个 401 都会调 expire()
        // 把整机登出 —— 用户看到的就是「下载文件夹 → 跳回登录页」。
        task.error = e.needsReauth ? '下载链接已失效，请重试' : e.friendly;
      }
    } catch (e) {
      if (task.status != TransferStatus.paused) {
        task.status = TransferStatus.failed;
        task.error = '传输中断，可重试';
      }
    } finally {
      _tokens.remove(task.id);
      _persist();
      _emit();
      await _pump();
    }
  }

  String _resolveLocalPath(String dir, String name, String remotePath) {
    for (final task in state.tasks) {
      if (task.kind == TransferKind.download &&
          task.remotePath == remotePath &&
          task.status != TransferStatus.done) {
        return task.localPath;
      }
    }
    final safe = _safeName(name);
    final candidate = File('$dir${Platform.pathSeparator}$safe');
    if (!candidate.existsSync()) return candidate.path;
    final dot = safe.lastIndexOf('.');
    final base = dot > 0 ? safe.substring(0, dot) : safe;
    final ext = dot > 0 ? safe.substring(dot) : '';
    for (var i = 2; i < 1000; i++) {
      final next = File('$dir${Platform.pathSeparator}$base ($i)$ext');
      if (!next.existsSync()) return next.path;
    }
    return candidate.path;
  }

  Future<String> _downloadDir(ServerProfile profile) async {
    // v2.5：与设置页共用同一套路径规则（Android 落在公共 Download/OpenList），
    // 并处理目录创建失败（未授权公共目录时退回应用私有目录）。
    return ensureDownloadDirFor(ref.read(serverStoreProvider), profile);
  }

  /// v1.0.22：文件名清洗统一走 `safePathSegment`（含 `..`、结尾点/空格、
  /// Windows 保留设备名与超长截断），不再维护第二套规则。
  String _safeName(String value) => safePathSegment(value);

  Future<void> loadServerTasks() async {
    final api = ref.read(sessionProvider).api;
    if (api == null) return;
    try {
      final tasks = await api.tasks();
      state = state.copyWith(serverTasks: tasks);
    } on ApiException catch (e) {
      state = state.copyWith(error: e.friendly);
    }
  }
}
