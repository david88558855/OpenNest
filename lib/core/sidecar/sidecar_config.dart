import 'dart:io';
import 'dart:math';

import 'sidecar_state.dart';

/// 生成引擎配置文件，并负责端口探测。
class SidecarConfig {
  const SidecarConfig._();

  /// 最小可用配置。
  ///
  /// 三处关键点：
  /// 1. `address` 固定回环——默认的 0.0.0.0 会把管理接口暴露到局域网；
  /// 2. `https_port` 必须为 -1，否则引擎会尝试监听 TLS；
  /// 3. 关闭对象存储 / 文件传输 / 远程登录等附加监听，只保留本机接口。
  static Map<String, dynamic> build({
    required int port,
    required Directory root,
    required String jwtSecret,
  }) {
    final sep = Platform.pathSeparator;
    return <String, dynamic>{
      'force': true,
      'scheme': <String, dynamic>{
        'address': '127.0.0.1',
        'http_port': port,
        'https_port': -1,
      },
      'database': <String, dynamic>{
        'type': 'sqlite3',
        'db_file': '${root.path}${sep}data.db',
        'table_prefix': 'x_',
      },
      'jwt_secret': jwtSecret,
      'token_expires_in': 48,
      'temp_dir': '${root.path}${sep}temp',
      'log': <String, dynamic>{
        'enable': true,
        'max_size': 10,
        'max_backups': 3,
        'max_age': 7,
      },
      's3': <String, dynamic>{'enable': false},
      'ftp': <String, dynamic>{'enable': false},
      'sftp': <String, dynamic>{'enable': false},
    };
  }

  static String randomSecret(int length) {
    const alphabet = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random.secure();
    return List<String>.generate(length, (_) => alphabet[random.nextInt(alphabet.length)]).join();
  }
}

/// 端口探测。
///
/// 引擎配置里的端口写 0 时，日志只会打印 `:0`，真实端口无处可查，
/// 所以必须先自己绑一个空闲端口，再把确定的值写进配置。
class PortAllocator {
  const PortAllocator._();

  static Future<int> pick({Set<int> exclude = const {kSidecarReservedPort}}) async {
    for (var attempt = 0; attempt < 24; attempt++) {
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = socket.port;
      await socket.close();
      if (port > 1024 && !exclude.contains(port)) return port;
    }
    throw StateError('本机没有可用端口');
  }
}
