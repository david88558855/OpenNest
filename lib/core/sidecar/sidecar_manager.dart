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
  final String token;
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
}

/// 引擎进程的统一接口：桌面用子进程实现，移动端用原生桥实现。
abstract class SidecarManager {
  Future<SidecarLaunch> start({void Function(String step)? onStep});
  Future<void> stop();
  Future<SidecarLaunch> relogin();
  bool get isRunning;
}

SidecarManager createSidecarManager(SecureStore secure, {void Function()? onExit}) {
  if (Platform.isAndroid) return AndroidSidecarManager();
  return DesktopSidecarManager(secure, onExit: onExit);
}

/// 移动端实现由原生桥提供（下一阶段接入）；在此之前保持可编译并给出明确提示。
class AndroidSidecarManager implements SidecarManager {
  @override
  bool get isRunning => false;

  @override
  Future<SidecarLaunch> start({void Function(String step)? onStep}) async {
    throw SidecarException('移动端引擎尚未接入，请使用 Windows 版。');
  }

  @override
  Future<void> stop() async {}

  @override
  Future<SidecarLaunch> relogin() async {
    throw SidecarException('移动端引擎尚未接入，请使用 Windows 版。');
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
    for (var attempt = 1; attempt <= 10; attempt++) {
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
        await _kill(process);
        previous = port;
        continue;
      }

      onStep?.call('登录引擎');
      final api = OpenListApi(baseUrl: 'http://127.0.0.1:$port');
      String token;
      SiteInfo? site;
      try {
        token = await api.login(username: 'admin', password: password);
        try {
          site = await api.publicSettings();
        } on ApiException catch (_) {}
      } catch (_) {
        await _kill(process);
        previous = port;
        continue;
      }

      await _secure.write(kSidecarTokenKey, token);
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
      '引擎启动失败：连续尝试 10 个端口仍未就绪。请查看日志排查。',
      logPath: _logPath,
    );
  }

  @override
  Future<void> stop() async {
    final process = _process;
    _process = null;
    if (process != null) {
      await _kill(process);
    } else {
      final pidFile = await SidecarPaths.pid();
      if (await pidFile.exists()) {
        final pid = int.tryParse((await pidFile.readAsString()).trim());
        if (pid != null) {
          try {
            Process.killPid(pid);
          } catch (_) {}
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

  Future<String> _ensurePassword() async {
    final existing = await _secure.read(kSidecarAdminKey);
    if (existing != null && existing.length >= 16) return existing;
    final password = SidecarConfig.randomSecret(32);
    await _secure.write(kSidecarAdminKey, password);
    return password;
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

  Future<SidecarLaunch?> _adopt(String password) async {
    final portFile = await SidecarPaths.port();
    if (!await portFile.exists()) return null;
    final port = int.tryParse((await portFile.readAsString()).trim());
    if (port == null || port <= 0) return null;
    if (!await _ping(port)) return null;

    final stored = await _secure.read(kSidecarTokenKey);
    final api = OpenListApi(baseUrl: 'http://127.0.0.1:$port', token: stored);
    SiteInfo? site;
    String token;
    if (stored == null || stored.isEmpty) {
      token = await api.login(username: 'admin', password: password);
      await _secure.write(kSidecarTokenKey, token);
    } else {
      api.token = stored;
      var valid = true;
      try {
        await api.me();
      } catch (_) {
        valid = false;
      }
      if (valid) {
        token = stored;
      } else {
        token = await api.login(username: 'admin', password: password);
        await _secure.write(kSidecarTokenKey, token);
      }
    }
    try {
      site = await api.publicSettings();
    } on ApiException catch (_) {}

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
    process.stdout.transform(utf8.decoder).listen(sink.write);
    process.stderr.transform(utf8.decoder).listen(sink.write);
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
    final sink = _logSink;
    _logSink = null;
    if (sink == null) return;
    try {
      await sink.flush();
      await sink.close();
    } catch (_) {}
  }

  static Future<bool> _ping(int port) async {
    final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 700);
    try {
      final request = await client.getUrl(Uri.parse('http://127.0.0.1:$port/ping'));
      final response = await request.close().timeout(const Duration(milliseconds: 900));
      final body = await response.transform(utf8.decoder).join().timeout(
            const Duration(milliseconds: 900),
          );
      return response.statusCode == 200 && body.toLowerCase().contains('pong');
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }
}
