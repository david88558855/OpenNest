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
import '../../data/db/app_database.dart';
import '../sources/storage_health.dart';

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

  /// 各状态的任务数。
  ///
  /// 0.5.9：UI 原来用 `state.done.length` 取计数，而 `done` 每次访问都会
  /// 新建一个 List —— 一帧里要访问十几次，批量上千条任务时就是几万次
  /// 元素分配。这些计数走 `where().length`：照样遍历，但不物化 List。
  int get doneCount => tasks.where((e) => e.status == TransferStatus.done).length;
  int get failedCount => tasks.where((e) => e.status == TransferStatus.failed).length;
  int get runningCount => tasks.where((e) => e.status == TransferStatus.running).length;
  int get pausedCount => tasks.where((e) => e.status == TransferStatus.paused).length;

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

  /// 每个任务当前正在运行的协程。
  ///
  /// 0.5.9 修复：以前「暂停后立刻继续」会起第二个 `_run` 操作同一个任务
  /// —— 两个协程同时写同一个文件；更糟的是旧协程的 `finally` 会把**新**
  /// 协程的取消令牌从表里删掉，导致该任务此后再也停不下来。
  ///
  /// 现在 `_pump` 看到「这个任务还有协程在跑」就跳过，等旧协程自己收尾
  /// 后由它的 `finally` 再拉起一轮，天然保证同一任务同时只有一个协程。
  final Map<String, Future<void>> _running = {};

  /// 每个任务的运行代次。
  ///
  /// 协程的 `catch` / `finally` 必须先确认自己仍是「当前这一代」，
  /// 否则它会把新协程的状态改回 failed、并删掉新协程的令牌。
  final Map<String, int> _runSeq = {};

  /// 因「全部暂停」而暂停的任务 id；「全部继续」只恢复这些（v1.0.23）。
  final Set<String> _pausedByGlobal = {};
  Timer? _ticker;
  DateTime _lastEmit = DateTime.fromMillisecondsSinceEpoch(0);
  bool _pumping = false;
  ProviderSubscription<AppSettings>? _settingsSub;

  TransfersNotifier(this.ref) : super(const TransfersState()) {
    final settings = ref.read(appSettingsProvider);
    _downRateBytes = settings.downLimitKbps * 1024;
    _upRateBytes = settings.upLimitKbps * 1024;
    _downSegments = settings.downloadSegments;
    state = state.copyWith(concurrency: settings.concurrency);
    // v2.6：设置页改并发数后立即生效。之前只在构造时读一次，必须重启应用才生效。
    // 0.5.3：顺带把限速值同步进缓存（传输循环每批只读缓存，不再读 provider）。
    _settingsSub = ref.listen<AppSettings>(appSettingsProvider, (previous, next) {
      _downRateBytes = next.downLimitKbps * 1024;
      _upRateBytes = next.upLimitKbps * 1024;
      _downSegments = next.downloadSegments;
      if (previous?.concurrency == next.concurrency) return;
      if (state.concurrency != next.concurrency) {
        state = state.copyWith(concurrency: next.concurrency);
      }
      unawaited(_pump());
    });
    _restore();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  /// 限速的字节值缓存。
  ///
  /// 0.5.3（方案 A）：以前每收一个 64KB 块就 `ref.read(appSettingsProvider)`
  /// 一次 —— 1GB 下载就是 1.6 万次 provider 读取。改成由设置监听写入缓存，
  /// 传输循环里只读一个 int 字段；语义仍是「改完设置立即生效」。
  int _downRateBytes = 0;
  int _upRateBytes = 0;

  /// 单文件下载分段数（1 = 单流，与旧版等价）。
  ///
  /// 分段在下载启动时一次性规划，运行中改设置只影响后续任务 —— 中途
  /// 改变段边界没有意义（已发出的 Range 无法撤回）。
  int _downSegments = 4;

  /// 下载限速（字节/秒）。读缓存，不读 provider。
  int _downRate() => _downRateBytes;

  /// 上传限速（字节/秒）。同上。
  int _upRate() => _upRateBytes;

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

  Future<void> _restore() async {
    List<Map<String, dynamic>> raw;
    try {
      raw = await TransferDao.instance.loadAll();
    } catch (_) {
      raw = const [];
    }
    if (!mounted) return;
    final restored = <TransferTask>[];
    for (final e in raw) {
      // 0.5.11：逐条容错。以前一条 JSON 字段类型不对（比如 total 存成字符串）
      // 就会在 fromJson 里抛，整轮恢复中断，队列里其余任务全部丢失。
      try {
        final task = TransferTask.fromJson(e);
        if (task.status == TransferStatus.running || task.status == TransferStatus.queued) {
          task.status = TransferStatus.paused;
        }
        if (task.status != TransferStatus.done) restored.add(task);
      } catch (_) {
        // 坏记录直接跳过，不影响其它任务。
      }
    }
    if (restored.isNotEmpty && mounted) {
      state = state.copyWith(tasks: restored);
      unawaited(_pump());
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
    // 事务写入：一次替换全部任务，避免半截状态。
    unawaited(TransferDao.instance.replaceAll(list).catchError((_) {}));
  }

  void _emit() {
    // 0.5.9：dispose 之后不能再改 state。应用退出时正在下载的任务，
    // 它的进度回调会一路走到这里 —— StateNotifier 在 dispose 后
    // setState 会抛 StateError，而这条回调是 unawaited 的，异常没人接。
    if (!mounted) return;
    // 兜底清理：任务被移除后它的速度基准还留在表里，长期批量下载会让
    // 这张表无限增长。长度一致时不做任何遍历。
    if (_previousDone.length > state.tasks.length) {
      final ids = state.tasks.map((e) => e.id).toSet();
      _previousDone.removeWhere((id, _) => !ids.contains(id));
    }
    state = state.copyWith(tasks: List<TransferTask>.of(state.tasks));
  }

  void _emitThrottled() {
    final now = DateTime.now();
    // 0.5.3（方案 A）：下载侧的上报已经是「512KB 或 200ms 一次」，这里
    // 对齐到 200ms，避免同一帧内重复整表拷贝（每次都要 List.of 全量任务）。
    if (now.difference(_lastEmit).inMilliseconds < 200) return;
    _lastEmit = now;
    _emit();
  }

  void _tick() {
    if (!mounted) return;
    // 没有任务时不要每秒重建一次状态（空列表也要触发全局重建，纯浪费）。
    if (state.tasks.isEmpty) return;
    var down = 0.0;
    var up = 0.0;
    var anyRunning = false;
    for (final task in state.tasks) {
      final previous = _previousDone[task.id] ?? task.done;
      final delta = task.done - previous;
      _previousDone[task.id] = task.done;
      if (task.status == TransferStatus.running) {
        anyRunning = true;
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
    // 0.5.9：没有任务在跑、速度也已经归零时不必再重建状态。
    // 之前每秒都会 `List.of(全表)` + 触发一次全局 rebuild，
    // 批量上千条任务时这是纯粹的主线程浪费。
    if (!anyRunning && down == 0 && up == 0 && state.downSpeed == 0 && state.upSpeed == 0) {
      return;
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
    final String root;
    try {
      root = await _downloadDir(profile);
    } catch (error) {
      // 三级兜底目录都建不出来时（磁盘只读 / 权限异常），这里会抛。
      // 必须在 try 里接住，否则点「下载」会变成未捕获异常、按钮毫无反馈。
      return '无法准备下载目录：$error';
    }
    final dir = localSubdir.isEmpty ? root : '$root${Platform.pathSeparator}$localSubdir';
    try {
      await Directory(dir).create(recursive: true);
    } catch (error) {
      return '无法创建目录 $dir：$error';
    }
    // 同名文件不能互相覆盖：已在队列里的同一远程文件复用原路径（续传），
    // 否则在磁盘上顺延出「name (2).ext」。
    //
    // 0.5.11：但「复用」只对**已停下**（暂停 / 失败）的旧任务成立。旧任务还在
    // 跑或排队时再入队同一个文件，两个协程会同时写同一个文件（一个截断、
    // 一个追加），双双标成 done 而内容已坏。这种情况直接拒绝。
    for (final t in state.tasks) {
      if (t.kind == TransferKind.download &&
          t.remotePath == remotePath &&
          (t.status == TransferStatus.running || t.status == TransferStatus.queued)) {
        return '该文件已在下载队列中';
      }
    }
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

  /// 把「复制 / 移动到…」入队。
  ///
  /// 与下载/上传共用同一条队列与同一个并发上限：一次操作里选中的每个条目
  /// 生成一条任务（`name` 是条目名，`remotePath` 是源目录，`localPath` 是
  /// 目标目录），由 `_run` 逐个调引擎的 `/api/fs/copy` `/api/fs/move`。
  ///
  /// 服务端搬运没有字节级进度，所以 [TransferTask.total] 只用于展示大小，
  /// 不参与进度计算。
  Future<String?> enqueueCopyMove({
    required List<FileItem> items,
    required String srcDir,
    required String dstDir,
    required bool move,
  }) async {
    if (items.isEmpty) return null;
    final session = ref.read(sessionProvider);
    final profile = session.profile;
    if (profile == null || session.api == null) return '尚未连接服务器';
    final kind = move ? TransferKind.move : TransferKind.copy;
    final prefix = move ? 'mv' : 'cp';
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final created = <TransferTask>[];
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      created.add(TransferTask(
        id: '$prefix-$stamp-$i-${item.name.hashCode}',
        serverId: profile.id,
        serverLabel: profile.name,
        kind: kind,
        name: item.name,
        remotePath: srcDir,
        localPath: dstDir,
        total: item.size > 0 ? item.size : 0,
      ));
    }
    state = state.copyWith(
      tasks: [...created, ...state.tasks],
      clearError: true,
      pausedGlobally: false,
    );
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
    // 已完成的任务没有「继续」语义：再跑一遍会从本地已有长度发起 Range，
    // 服务端回 416，任务反而变成失败（用户看到「已完成」变「失败」）。
    if (task.status == TransferStatus.done) return;
    _pausedByGlobal.remove(id);
    task.status = TransferStatus.queued;
    task.error = null;
    // 0.5.11：单个任务「继续」必须解除全局暂停。以前只改任务状态，
    // 而 _pump 开头 `if (!state.pausedGlobally)` 会跳过整轮调度 ——
    // 点过「全部暂停」后点某一条的「继续」，那条永远停在排队中。
    state = state.copyWith(pausedGlobally: false);
    _emit();
    await _pump();
  }

  Future<void> retry(String id) async {
    final task = _find(id);
    if (task == null) return;
    _pausedByGlobal.remove(id);
    task.error = null;
    task.status = TransferStatus.queued;
    // 同上：重试也要解除全局暂停，否则任务只排队不启动。
    state = state.copyWith(pausedGlobally: false);
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
        // total 未知时（恢复的旧任务、服务端没给 size）无从判断完整性 ——
        // 这时宁可留下半成品，也不要把已经下完的文件误删。
        final sizeKnown = task.total > 0;
        final complete = sizeKnown && file.existsSync() && file.lengthSync() >= task.total;
        if (task.kind == TransferKind.download && file.existsSync() && sizeKnown && !complete) {
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
      // 0.5.9：必须先 cancel —— 以前只从表里摘掉令牌，正在跑的任务会
      // 继续下载并写盘，而界面上它已经消失了，用户再也停不掉它。
      _tokens[id]?.cancel();
      _tokens.remove(id);
      _previousDone.remove(id);
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
    final clamped = value.clamp(1, AppSettingsNotifier.kMaxConcurrency).toInt();
    if (state.concurrency != clamped) {
      state = state.copyWith(concurrency: clamped);
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
    var changed = false;
    try {
      if (!state.pausedGlobally) {
        var running = state.tasks.where((e) => e.status == TransferStatus.running).length;
        // 并发数为 0（异常值）会让下面直接 break，任务永远不启动
        final limit = state.concurrency > 0 ? state.concurrency : 1;
        for (final task in state.tasks.toList()) {
          if (running >= limit) break;
          if (task.status == TransferStatus.queued) {
            // 0.5.9：这个任务还有上一轮的协程在收尾（暂停后立刻继续的
            // 典型场景）。此时**不能**再起一个 —— 两个协程会同时写同一个
            // 文件。等旧协程的 finally 调 _pump() 时自然会拉起新一轮。
            if (_running.containsKey(task.id)) continue;
            // 0.5.11：会话换了服务器时 _run 会立刻把任务改回 paused 并返回，
            // 以前这里已经 running++ 占了并发槽 —— 槽被空占，本轮其余排队
            // 任务全被 break 掉。现在先判连接，没有 api 就不占槽。
            if (_apiFor(task.serverId) == null) {
              task.status = TransferStatus.paused;
              task.error = '切换了服务器，恢复后继续';
              changed = true;
              continue;
            }
            running++;
            _launch(task);
          }
        }
      }
    } finally {
      _pumping = false;
      if (changed) _emit();
    }
  }

  /// 启动一个任务的执行协程，并登记到 [_running]。
  ///
  /// 登记的意义：`_pump` 靠它判断「这个任务是不是已经在跑了」，
  /// 从而保证同一任务同时只有一个协程。
  void _launch(TransferTask task) {
    final future = _run(task);
    _running[task.id] = future;
    // catchError 兜底：whenComplete 会把原 future 的错误转发到返回的
    // future 上，这里没人 await，不接住就会变成未处理的异步异常。
    unawaited(future.whenComplete(() {
      if (identical(_running[task.id], future)) _running.remove(task.id);
    }).catchError((Object _) {}));
  }

  /// 某个任务当前是否仍由「这一代」协程持有。
  bool _isCurrent(String id, int gen) => _runSeq[id] == gen;

  Future<void> _run(TransferTask task) async {
    final api = _apiFor(task.serverId);
    if (api == null) {
      task.status = TransferStatus.paused;
      task.error = '切换了服务器，恢复后继续';
      _emit();
      return;
    }
    final token = CancelToken();
    // 运行代次：本次运行的身份。后续任何状态变更前都要确认代次没被
    // 后一轮覆盖（暂停后立刻继续会起新一轮）。
    final gen = (_runSeq[task.id] ?? 0) + 1;
    _runSeq[task.id] = gen;
    _tokens[task.id] = token;
    task.status = TransferStatus.running;
    task.error = null;
    _emit();
    try {
      if (task.isServerOp) {
        // 服务端复制 / 移动：一次请求处理一个条目，引擎递归处理目录。
        // 没有字节进度可拿，total/done 保持 0，完成即置 done。
        final names = [task.name];
        if (task.kind == TransferKind.copy) {
          await api.copy(task.remotePath, task.localPath, names);
        } else {
          await api.move(task.remotePath, task.localPath, names);
        }
        if (task.status != TransferStatus.paused) {
          task.status = TransferStatus.done;
        }
        // 复制/移动会改变目录内容（移动还会让源消失），刷一次当前列表。
        if (task.status == TransferStatus.done) {
          unawaited(ref.read(filesProvider.notifier).refresh());
        }
      } else if (task.kind == TransferKind.download) {
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
          // 1 = 单流（与旧版逐字节等价）；>1 且文件够大才真正分段。
          segments: _downSegments,
          knownTotal: task.total,
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
      // 只有「仍由本代协程持有」且「不是被取消的」才算失败。
      // 被取消（用户暂停 / 移除任务）时任务状态由调用方决定，这里不能改；
      // 代次过期时说明已经有新一轮在跑，更不能把它的状态改回 failed。
      if (_isCurrent(task.id, gen) && !token.isCancelled && task.status != TransferStatus.paused) {
        task.status = TransferStatus.failed;
        // v1.0.33：下载走的是 /d/<path>?sign=，401 多半是签名过期而不是会话失效。
        // 批量下载文件夹时会入队大量任务，之前任何一个 401 都会调 expire()
        // 把整机登出 —— 用户看到的就是「下载文件夹 → 跳回登录页」。
        task.error = e.needsReauth ? '下载链接已失效，请重试' : e.friendly;
      }
    } catch (e) {
      if (_isCurrent(task.id, gen) && !token.isCancelled && task.status != TransferStatus.paused) {
        task.status = TransferStatus.failed;
        task.error = '传输中断，可重试';
      }
    } finally {
      if (_isCurrent(task.id, gen)) {
        // 只摘属于本代的令牌与协程登记：新一轮可能已经把同名条目换掉了。
        _tokens.remove(task.id);
        _running.remove(task.id);
      }
      // notifier 已 dispose 时不能再碰 ref（Riverpod 会抛「used after
      // dispose」），也不能再改状态。
      if (mounted) {
        _persist();
        _emit();
        // 传输结束（成功或失败）都会回写存储源状态：一是列表里的引擎状态
        // 需要跟着刷新，二是一批任务失败往往就意味着那个源此刻已经失联 ——
        // 不该等用户去设置页手动点「测试连接」。内部有 3 秒合并窗口，
        // 批量传输不会每个任务都触发一轮探测。
        ref.read(storageHealthProvider.notifier).scheduleRefresh();
        await _pump();
      }
    }
  }

  String _resolveLocalPath(String dir, String name, String remotePath) {
    // 只复用「已停下」的旧任务的路径（续传场景）。运行中 / 排队中的同一文件
    // 在入队时已被拦掉（见 enqueueDownloadInto），这里再排除一次是为了防止
    // 竞态下两个任务拿到同一条路径。
    for (final task in state.tasks) {
      if (task.kind == TransferKind.download &&
          task.remotePath == remotePath &&
          (task.status == TransferStatus.paused || task.status == TransferStatus.failed)) {
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
