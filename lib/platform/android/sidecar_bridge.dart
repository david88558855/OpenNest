import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/openlist_api.dart';
import '../../core/sidecar/sidecar_config.dart';
import '../../core/sidecar/sidecar_manager.dart';
import '../../core/sidecar/sidecar_paths.dart';
import '../../core/sidecar/sidecar_state.dart';
import '../../core/storage/secure_store.dart';

/// 移动端引擎：二进制以原生库形式随包分发，由系统解压到可执行目录，
/// Dart 侧通过方法通道请求原生启动（Android 10+ 禁止在应用可写目录执行文件）。
class AndroidSidecarManager implements SidecarManager {
  AndroidSidecarManager(this._secure);

  static const MethodChannel _channel = MethodChannel('com.opennest.app/sidecar');

  final SecureStore _secure;
  int? _port;

  @override
  bool get isRunning => _port != null;

  @override
  Future<SidecarLaunch> start({void Function(String step)? onStep}) async {
    final root = await SidecarPaths.root();
    final logFile = await SidecarPaths.log();
    final password = await _ensurePassword();

    onStep?.call('检查运行实例');
    final adopted = await _adopt(password, logFile.path);
    if (adopted != null) return adopted;

    final configFile = await SidecarPaths.config();
    final jwt = SidecarConfig.randomSecret(32);

    int? previous;
    for (var attempt = 1; attempt <= 8; attempt++) {
      final port = await PortAllocator.pick(exclude: {
        kSidecarReservedPort,
        if (previous != null) previous,
      });
      await configFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(
          SidecarConfig.build(port: port, root: root, jwtSecret: jwt),
        ),
        flush: true,
      );

      onStep?.call('启动引擎（第 $attempt 次尝试，端口 $port）');
      try {
        await _channel.invokeMethod<int>('start', {
          'dataDir': root.path,
          'port': port,
          'password': password,
          'logPath': logFile.path,
        });
      } catch (error) {
        previous = port;
        if (attempt == 8) {
          throw SidecarException('引擎启动失败：$error', logPath: logFile.path);
        }
        continue;
      }

      if (!await _waitHealthy(port)) {
        await _channel.invokeMethod<bool>('stop');
        previous = port;
        continue;
      }

      onStep?.call('登录引擎');
      final api = OpenListApi(baseUrl: 'http://127.0.0.1:$port');
      String token;
      try {
        token = await api.login(username: 'admin', password: password);
      } catch (_) {
        await _channel.invokeMethod<bool>('stop');
        previous = port;
        continue;
      }
      await _secure.write(kSidecarTokenKey, token);
      await (await SidecarPaths.port()).writeAsString('$port');
      _port = port;

      String? version;
      try {
        version = (await api.publicSettings()).version;
      } on ApiException catch (_) {}

      return SidecarLaunch(
        port: port,
        token: token,
        version: version,
        logPath: logFile.path,
        binaryPath: 'nativeLibraryDir/libopenlist.so',
      );
    }
    throw SidecarException('引擎启动失败：多次尝试后仍未就绪。', logPath: logFile.path);
  }

  @override
  Future<void> stop() async {
    try {
      await _channel.invokeMethod<bool>('stop');
    } catch (_) {}
    for (final file in [await SidecarPaths.pid(), await SidecarPaths.port()]) {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
    _port = null;
  }

  @override
  Future<SidecarLaunch> relogin() async {
    final port = _port;
    if (port == null) throw SidecarException('引擎尚未启动，无法重新登录。');
    final password = await _secure.read(kSidecarAdminKey);
    if (password == null || password.isEmpty) {
      throw SidecarException('本机缺少引擎凭据，请重启应用以重新初始化。');
    }
    final api = OpenListApi(baseUrl: 'http://127.0.0.1:$port');
    final token = await api.login(username: 'admin', password: password);
    await _secure.write(kSidecarTokenKey, token);
    return SidecarLaunch(
      port: port,
      token: token,
      logPath: (await SidecarPaths.log()).path,
      binaryPath: 'nativeLibraryDir/libopenlist.so',
    );
  }

  Future<String> _ensurePassword() async {
    final existing = await _secure.read(kSidecarAdminKey);
    if (existing != null && existing.length >= 16) return existing;
    final password = SidecarConfig.randomSecret(32);
    await _secure.write(kSidecarAdminKey, password);
    return password;
  }

  Future<SidecarLaunch?> _adopt(String password, String logPath) async {
    final portFile = await SidecarPaths.port();
    if (!await portFile.exists()) return null;
    final port = int.tryParse((await portFile.readAsString()).trim());
    if (port == null || port <= 0) return null;
    if (!await _ping(port)) return null;

    final stored = await _secure.read(kSidecarTokenKey);
    final api = OpenListApi(baseUrl: 'http://127.0.0.1:$port', token: stored);
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
    _port = port;
    return SidecarLaunch(
      port: port,
      token: token,
      logPath: logPath,
      binaryPath: 'nativeLibraryDir/libopenlist.so',
    );
  }

  Future<bool> _waitHealthy(int port) async {
    final deadline = DateTime.now().add(const Duration(seconds: 40));
    while (DateTime.now().isBefore(deadline)) {
      if (await _ping(port)) return true;
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    return false;
  }

  static Future<bool> _ping(int port) async {
    final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 800);
    try {
      final request = await client.getUrl(Uri.parse('http://127.0.0.1:$port/ping'));
      final response = await request.close().timeout(const Duration(milliseconds: 1200));
      final body = await response.transform(utf8.decoder).join().timeout(
            const Duration(milliseconds: 1200),
          );
      return response.statusCode == 200 && body.toLowerCase().contains('pong');
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }
}
