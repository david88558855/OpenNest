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
    // 与桌面端一致：3 次尝试。原生侧对「启动后立即退出」已经会立刻抛错，
    // 再多试只会把启动页卡得更久（每次都要等满健康检查窗口）。
    for (var attempt = 1; attempt <= 3; attempt++) {
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
        // 原生侧 start 返回的是 Boolean（是否启动成功），
        // 这里必须按 bool 接收。此前误写成 invokeMethod<int>，方法通道
        // 拿到 bool 却按 int 解析，直接抛
        // "type 'bool' is not a subtype of type 'int?' in type cast"，
        // 表现为安卓版「引擎启动失败」。
        final started = await _channel.invokeMethod<bool>('start', {
          'dataDir': root.path,
          'port': port,
          'password': password,
          'logPath': logFile.path,
        });
        if (started != true) {
          throw SidecarException('原生侧未能启动引擎进程。');
        }
      } catch (error) {
        previous = port;
        if (attempt == 3) {
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
      String? token;
      try {
        // 引擎的 StoragesLoaded 中间件在存储源加载完之前会挂住登录接口
        // （换过网络、原地址不可达的源会卡很久）。只等 12 秒，等不到就
        // 以「未登录」返回 —— 进程是健康的，stop 掉才是错的。
        token = await api.login(username: 'admin', password: password)
            .timeout(const Duration(seconds: 12));
      } on TimeoutException {
        onStep?.call('引擎已启动，正在等待存储源加载');
        token = null;
      } catch (_) {
        await _channel.invokeMethod<bool>('stop');
        previous = port;
        continue;
      }
      if (token != null) {
        await _secure.write(kSidecarTokenKey, token);
      }
      await (await SidecarPaths.port()).writeAsString('$port');
      _port = port;

      String? version;
      if (token != null) {
        try {
          version = (await api.publicSettings().timeout(const Duration(seconds: 3))).version;
        } on ApiException catch (_) {} on TimeoutException catch (_) {}
      }

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
    String? token = stored;
    try {
      if (token == null || token.isEmpty) {
        token = await api.login(username: 'admin', password: password)
            .timeout(const Duration(seconds: 12));
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
          token = await api.login(username: 'admin', password: password)
              .timeout(const Duration(seconds: 12));
          await _secure.write(kSidecarTokenKey, token);
        }
      }
    } on TimeoutException {
      // 已有实例正在加载存储源（接口被中间件挂住）：照旧接管，
      // 只是先不带令牌，交给会话层重试。
      token = null;
    } catch (_) {
      // 不是我们的引擎（或已不可用）：放弃接管，重新启一个。
      return null;
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

  /// 引擎是否已经「活着」。
  ///
  /// `/ping` 也会被引擎的 `StoragesLoaded` 中间件挂住（存储源没加载完时
  /// 除 `/` 以外全部阻塞），所以 `/ping` 不通时再探根路径：能应答就说明
  /// HTTP 已起来、进程健康，只是存储源还在加载。
  static Future<bool> _ping(int port) async {
    if (await _probe(port, '/ping', expectPong: true)) return true;
    return _probe(port, '/', expectPong: false);
  }

  static Future<bool> _probe(int port, String path, {required bool expectPong}) async {
    final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 800);
    try {
      final request = await client.getUrl(Uri.parse('http://127.0.0.1:$port$path'));
      final response = await request.close().timeout(const Duration(milliseconds: 1200));
      if (response.statusCode >= 500) return false;
      final body = await response.transform(utf8.decoder).join().timeout(
            const Duration(milliseconds: 1200),
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
