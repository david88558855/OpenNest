import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../api/api_exception.dart';
import '../api/openlist_api.dart';
import '../models/api_types.dart';
import '../storage/secure_store.dart';
import 'sidecar_config.dart';
import 'sidecar_paths.dart';
import 'sidecar_state.dart';

class SidecarException implements Exception {
  final String message;
  final String? logPath;

  SidecarException(this.message, {this.logPath});

  @override
  String toString() => message;
}

class SidecarLaunch {
  final int port;

  /// 访问令牌。为 null 表示「引擎起来了、但登录还没成功」。
  ///
  /// 这种情况不是故障：引擎的 `StoragesLoaded` 中间件会挂住除 `/` 以外的
  /// 全部接口（含 `/api/auth/login`），而该信号只在**所有存储源加载完**
  /// 之后才发出。换过网络、原地址已不可达的存储源会让这一步卡很久，
  /// 此时进程完全健康，不应该被判成「引擎启动失败」。
  final String? token;

  final String? version;
  final int? pid;
  final String logPath;
  final String binaryPath;

  const SidecarLaunch({
    required this.port,
    required this.token,
    required this.logPath,
    required this.binaryPath,
    this.version,
    this.pid,
  });

  /// 登录尚未完成（存储源仍在加载）。
  bool get pendingAuth => token == null || token!.isEmpty;
}

/// 引擎进程的统一接口：桌面用子进程实现，移动端用原生桥实现。
abstract class SidecarManager {
  Future<SidecarLaunch> start({void Function(String step)? onStep});
  Future<void> stop();
  Future<SidecarLaunch> relogin();
  bool get isRunning;

  /// 等 pid 对应的进程真正消失（最多 [timeout]）。
  ///
  /// 改引擎的 data.db 之前必须确认进程已退出：进程还在收尾时会与
  /// 引擎争写同一份 SQLite，最坏情况是库损坏。
  static Future<void> waitProcessGone(int pid, {Duration timeout = const Duration(seconds: 3)}) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final name = await SidecarManager.processNameOf(pid);
      if (name == null) return;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
  }

  /// 查询 pid 对应的进程名；进程不存在时返回 null。
  ///
  /// 只用于「按 pid 杀进程」之前的身份确认 —— PID 会被系统回收复用，
  /// 仅凭 pid 文件就发信号可能终止用户的无关程序。
  static Future<String?> processNameOf(int pid) async {
    try {
      if (Platform.isWindows) {
        final result = await Process.run(
          'tasklist',
          ['/FI', 'PID eq $pid', '/NH', '/FO', 'CSV'],
          runInShell: false,
        );
        final output = '${result.stdout}';
        // CSV 形如："openlist.exe","1234","Console","1","12,000 K"
        if (!output.contains('"$pid"')) return null;
        final match = RegExp(r'"([^"]+)"').firstMatch(output);
        return match?.group(1);
      }
      final result = await Process.run('ps', ['-p', '$pid', '-o', 'comm=']);
      final name = '${result.stdout}'.trim();
      return name.isEmpty ? null : name;
    } catch (_) {
      // 查不到就当「无法确认」，调用方据此放弃动作。
      return null;
    }
  }
}

/// 桌面实现：守护 `openlist server` 子进程。
class DesktopSidecarManager implements SidecarManager {
  DesktopSidecarManager(this._secure, {this.onExit});

  final SecureStore _secure;
  final void Function()? onExit;

  Process? _process;
  int? _port;
  String _binary = '';
  String _logPath = '';
  IOSink? _logSink;

  /// 引擎 stdout / stderr 的订阅。
  ///
  /// 0.5.9：以前这两个订阅没有保存，关闭日志 sink 之后若进程还有残留
  /// 输出，`sink.write` 会抛 `StreamSink is closed`，而这个订阅没人接 ——
  /// 表现为偶发的未捕获异步异常。现在随 sink 一起取消。
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;

  /// 启动尝试上限 3 次。
  ///
  /// 每次尝试最坏要等满健康检查窗口（30 秒）。以前是 10 次 —— 一个持续
  /// 崩溃的引擎能把启动页卡住五分钟，期间用户既进不了界面、也看不到可
  /// 操作的提示。「端口被占用」这类瞬时冲突 3 次足够覆盖。
  static const int _kMaxAttempts = 3;

  /// 登录等待上限。
  ///
  /// 引擎启动后还有一道关卡：`StoragesLoaded` 中间件在**所有存储源加载完**
  /// 之前会挂住除 `/` 以外的全部接口（含 `/api/auth/login`）。换过网络、
  /// 原地址不可达的存储源会让这一步卡几分钟。这里只等 12 秒，等到就登录，
  /// 等不到就以「未登录」状态返回 —— 引擎是健康的，杀进程才是错的。
  static const Duration _kLoginTimeout = Duration(seconds: 12);

  @override
  bool get isRunning => _process != null;

  @override
  Future<SidecarLaunch> start({void Function(String step)? onStep}) async {
    final root = await SidecarPaths.root();
    final binary = await SidecarPaths.binary();
    if (binary == null) {
      throw SidecarException(
        '未找到内嵌引擎（openlist.exe）。请确认它与主程序位于同一目录后重试。',
        logPath: _logPath,
      );
    }
    _binary = binary;
    final logFile = await SidecarPaths.log();
    _logPath = logFile.path;

    onStep?.call('读取引擎凭据');
    final password = await _ensurePassword();

    // 已在运行的实例直接复用，避免双进程写坏同一个数据库。
    onStep?.call('检查运行实例');
    final adopted = await _adopt(password);
    if (adopted != null) return adopted;

    onStep?.call('生成引擎配置');
    final configFile = await SidecarPaths.config();
    final jwt = await _ensureJwt(configFile);

    int? previous;
    for (var attempt = 1; attempt <= _kMaxAttempts; attempt++) {
      final port = await PortAllocator.pick(exclude: {
        kSidecarReservedPort,
        if (previous != null) previous,
      });
      final payload = SidecarConfig.build(port: port, root: root, jwtSecret: jwt);
      await configFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(payload),
        flush: true,
      );

      onStep?.call('启动引擎（第 $attempt 次尝试，端口 $port）');
      final process = await _spawn(binary, root, configFile, password, logFile);
      final healthy = await _waitHealthy(port, process);
      if (!healthy) {
        // 先取退出码：null 表示进程还活着（只是没在窗口内就绪），
        // 非 null 表示它自己退了 —— 那换个端口重试毫无意义，直接把
        // 原因抛给界面，别让用户对着启动页干等三分钟。
        final code = await _exitCode(process);
        await _kill(process);
        previous = port;
        if (code != null) {
          throw SidecarException(
            '引擎启动后立即退出（退出码 $code）。'
            '常见原因是某个存储源驱动在加载时崩溃 —— '
            '可在启动页点「安全模式启动」停用全部存储源后再逐个启用。',
            logPath: _logPath,
          );
        }
        continue;
      }

      onStep?.call('登录引擎');
      final api = OpenListApi(baseUrl: 'http://127.0.0.1:$port');
      String? token;
      SiteInfo? site;
      try {
        token = await api.login(username: 'admin', password: password).timeout(_kLoginTimeout);
      } on TimeoutException {
        // 引擎进程健康、HTTP 也就绪，但登录被 StoragesLoaded 中间件挂住了：
        // 说明还有存储源在加载。不杀进程、不换端口重试，以「未登录」返回，
        // 由会话层在界面里重试。
        onStep?.call('引擎已启动，正在等待存储源加载');
        token = null;
      } catch (_) {
        await _kill(process);
        previous = port;
        continue;
      }
      if (token != null) {
        try {
          site = await api.publicSettings().timeout(const Duration(seconds: 3));
        } on ApiException catch (_) {} on TimeoutException catch (_) {}
      }

      if (token != null) {
        await _secure.write(kSidecarTokenKey, token);
      }
      await (await SidecarPaths.port()).writeAsString('$port');
      await (await SidecarPaths.pid()).writeAsString('${process.pid}');

      _process = process;
      _port = port;
      _watchExit(process);

      return SidecarLaunch(
        port: port,
        token: token,
        version: site?.version ?? site?.apiVersion,
        pid: process.pid,
        logPath: _logPath,
        binaryPath: binary,
      );
    }

    throw SidecarException(
      '引擎启动失败：连续尝试 $_kMaxAttempts 个端口仍未就绪。请查看日志排查。',
      logPath: _logPath,
    );
  }

  @override
  Future<void> stop() async {
    final process = _process;
    _process = null;
    if (process != null) {
      await _kill(process);
      // 0.5.9：等进程真的消失再返回。安全模式紧接着就要改引擎的
      // data.db，进程还在退出的话会与它争写同一份 SQLite。
      await SidecarManager.waitProcessGone(process.pid);
    } else {
      final pidFile = await SidecarPaths.pid();
      if (await pidFile.exists()) {
        final pid = int.tryParse((await pidFile.readAsString()).trim());
        if (pid != null) {
          // 0.5.9：不能凭 pid 文件就盲杀。pid 文件可能是上次崩溃留下的
          // 残留，而 PID 会被系统回收给别的进程 —— Windows 上尤其常见。
          // 盲杀会终止用户毫不相关的程序。这里先确认这个 pid 确实是
          // 引擎进程再动手；确认不了就不杀（下次启动会接管这个实例，
          // 比误杀别的进程安全得多）。
          final name = await SidecarManager.processNameOf(pid);
          if (name != null && name.toLowerCase().contains('openlist')) {
            try {
              Process.killPid(pid);
            } catch (_) {}
            await SidecarManager.waitProcessGone(pid);
          }
        }
      }
    }
    for (final file in [await SidecarPaths.pid(), await SidecarPaths.port()]) {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
    await _closeLog();
  }

  @override
  Future<SidecarLaunch> relogin() async {
    final port = _port;
    if (port == null) {
      throw SidecarException('引擎尚未启动，无法重新登录。', logPath: _logPath);
    }
    final password = await _secure.read(kSidecarAdminKey);
    if (password == null || password.isEmpty) {
      throw SidecarException('本机缺少引擎凭据，请重启应用以重新初始化。', logPath: _logPath);
    }
    final api = OpenListApi(baseUrl: 'http://127.0.0.1:$port');
    final token = await api.login(username: 'admin', password: password);
    await _secure.write(kSidecarTokenKey, token);
    return SidecarLaunch(
      port: port,
      token: token,
      logPath: _logPath,
      binaryPath: _binary,
      pid: _process?.pid,
    );
  }

  // ---------------------------------------------------------------- 内部实现

  /// 管理员口令：固定为 [kDefaultAdminPassword]（`admin`）。
  ///
  /// 0.5.4 起不再随机生成，也不做任何跨版本口令迁移 / 校验 —— 启动即用
  /// 该口令登录引擎，全程没有口令输入或校验环节。这里顺手把钥匙串写成
  /// 同一个值，保证「设置 → 通用 → 内核密码」显示的就是真实生效的口令。
  Future<String> _ensurePassword() async {
    // 0.5.9：写不进去时记一条日志。引擎本身是用环境变量拿口令启动的，
    // 所以本次启动不受影响；受影响的是「下次重新登录」—— 钥匙串里
    // 没有凭据就登不进去。
    final ok = await _secure.write(kSidecarAdminKey, kDefaultAdminPassword);
    if (!ok) {
      stderr.writeln('sidecar: 引擎口令未能写入系统钥匙串，下次重新登录会失败');
    }
    return kDefaultAdminPassword;
  }

  Future<String> _ensureJwt(File configFile) async {
    try {
      if (await configFile.exists()) {
        final raw = jsonDecode(await configFile.readAsString());
        if (raw is Map && raw['jwt_secret'] is String) {
          final secret = raw['jwt_secret'] as String;
          if (secret.length >= 16) return secret;
        }
      }
    } catch (_) {}
    return SidecarConfig.randomSecret(32);
  }

  /// 接管一个已在运行的引擎实例。
  ///
  /// 同样不能假设「登录一定很快」：已有实例可能正在加载存储源，此时所有
  /// 接口（含登录）都被中间件挂住。那种情况下照旧接管 —— 进程是我们的、
  /// 端口是对的 —— 只是先不带令牌返回，由会话层稍后重试登录。
  Future<SidecarLaunch?> _adopt(String password) async {
    final portFile = await SidecarPaths.port();
    if (!await portFile.exists()) return null;
    final port = int.tryParse((await portFile.readAsString()).trim());
    if (port == null || port <= 0) return null;
    if (!await _ping(port)) return null;

    final stored = await _secure.read(kSidecarTokenKey);
    final api = OpenListApi(baseUrl: 'http://127.0.0.1:$port', token: stored);
    SiteInfo? site;
    String? token = stored;
    try {
      if (token == null || token.isEmpty) {
        token = await api.login(username: 'admin', password: password).timeout(_kLoginTimeout);
        await _secure.write(kSidecarTokenKey, token);
      } else {
        api.token = token;
        var valid = true;
        try {
          await api.me().timeout(const Duration(seconds: 5));
        } catch (_) {
          valid = false;
        }
        if (valid) {
          token = stored;
        } else {
          token = await api.login(username: 'admin', password: password).timeout(_kLoginTimeout);
          await _secure.write(kSidecarTokenKey, token);
        }
      }
    } on TimeoutException {
      token = null;
    } catch (_) {
      // 不是我们的引擎（或已不可用）：放弃接管，让调用方重新启动一个。
      return null;
    }
    try {
      site = await api.publicSettings().timeout(const Duration(seconds: 3));
    } on ApiException catch (_) {} on TimeoutException catch (_) {}

    _port = port;
    return SidecarLaunch(
      port: port,
      token: token,
      version: site?.version ?? site?.apiVersion,
      logPath: _logPath,
      binaryPath: _binary,
    );
  }

  Future<Process> _spawn(
    String binary,
    Directory root,
    File config,
    String password,
    File logFile,
  ) async {
    final process = await Process.start(
      binary,
      ['--data', root.path, '--config', config.path, 'server'],
      workingDirectory: root.path,
      environment: {'OPENLIST_ADMIN_PASSWORD': password},
      includeParentEnvironment: true,
    );
    await _closeLog();
    final sink = logFile.openWrite(mode: FileMode.append);
    _logSink = sink;
    sink.writeln('\n=== ${DateTime.now().toIso8601String()} 启动引擎 pid=${process.pid} ===');
    // 订阅必须保存：否则关闭 sink 之后进程的残留输出会写进已关闭的 sink。
    _stdoutSub = process.stdout.transform(utf8.decoder).listen(sink.write);
    _stderrSub = process.stderr.transform(utf8.decoder).listen(sink.write);
    return process;
  }

  Future<bool> _waitHealthy(int port, Process process) async {
    var exited = false;
    unawaited(process.exitCode.then((_) => exited = true));
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      if (exited) return false;
      if (await _ping(port)) return true;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    return false;
  }

  /// 进程已退出则返回退出码；仍在运行（健康检查只是超时）返回 null。
  Future<int?> _exitCode(Process process) async {
    try {
      return await process.exitCode.timeout(const Duration(milliseconds: 300));
    } catch (_) {
      return null;
    }
  }

  Future<void> _kill(Process process) async {
    try {
      process.kill();
    } catch (_) {}
    try {
      await process.exitCode.timeout(const Duration(seconds: 5));
    } catch (_) {
      try {
        process.kill(ProcessSignal.sigkill);
      } catch (_) {}
    }
  }

  void _watchExit(Process process) {
    unawaited(process.exitCode.then((_) async {
      if (_process?.pid != process.pid) return;
      _process = null;
      await _closeLog();
      onExit?.call();
    }));
  }

  Future<void> _closeLog() async {
    // 先断开订阅，再关 sink —— 顺序反了会出现「写向已关闭 sink」的异常。
    final outs = _stdoutSub;
    final errs = _stderrSub;
    _stdoutSub = null;
    _stderrSub = null;
    for (final sub in [outs, errs]) {
      if (sub == null) continue;
      try {
        await sub.cancel();
      } catch (_) {}
    }
    final sink = _logSink;
    _logSink = null;
    if (sink == null) return;
    try {
      await sink.flush();
      await sink.close();
    } catch (_) {}
  }

  /// 引擎是否已经「活着」。
  ///
  /// 先打 `/ping`（正常情况下的最快路径）。但要注意：引擎的 `StoragesLoaded`
  /// 中间件在**存储源加载完之前**会挂住除 `/` 以外的所有路径 —— 包括 `/ping`
  /// 本身（见上游 `server/middlewares/check.go`）。因此 `/ping` 不通时再探
  /// 一次 `/`：只要根路径能应答，就说明 HTTP 服务已起来、进程是健康的，
  /// 剩下只是存储源在慢慢加载。**不能**把「存储源加载慢」判成「引擎启动失败」。
  static Future<bool> _ping(int port) async {
    if (await _probe(port, '/ping', expectPong: true)) return true;
    return _probe(port, '/', expectPong: false);
  }

  static Future<bool> _probe(int port, String path, {required bool expectPong}) async {
    final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 700);
    try {
      final request = await client.getUrl(Uri.parse('http://127.0.0.1:$port$path'));
      final response = await request.close().timeout(const Duration(milliseconds: 900));
      if (response.statusCode >= 500) return false;
      final body = await response.transform(utf8.decoder).join().timeout(
            const Duration(milliseconds: 900),
          );
      if (!expectPong) return true;
      return response.statusCode == 200 && body.toLowerCase().contains('pong');
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }
}
