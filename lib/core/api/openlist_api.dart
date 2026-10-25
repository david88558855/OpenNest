import 'dart:io';

import 'package:dio/dio.dart';

import '../format.dart';
import '../models/api_types.dart';
import 'api_exception.dart';

/// Thin, typed wrapper over the OpenList HTTP API (v3 / v4).
///
/// Every request is issued against the Base URL the user typed, so sub-path
/// deployments such as `https://host/openlist` work without extra config.
class OpenListApi {
  final String baseUrl;
  final Dio _dio;
  String? token;

  OpenListApi({required this.baseUrl, this.token})
      : _dio = Dio(
          BaseOptions(
            baseUrl: baseUrl,
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 40),
            sendTimeout: const Duration(seconds: 40),
            validateStatus: (s) => s != null && s < 500,
            headers: const {'Accept': 'application/json'},
            responseType: ResponseType.json,
          ),
        );

  Dio get dio => _dio;

  Options _opts({Map<String, String>? headers, ResponseType? type, Duration? receiveTimeout}) {
    final h = <String, String>{};
    if (token != null && token!.isNotEmpty) h['Authorization'] = token!;
    if (headers != null) h.addAll(headers);
    return Options(
      headers: h,
      responseType: type,
      receiveTimeout: receiveTimeout,
    );
  }

  /// HTTP 层错误（401/403/404/429/5xx）必须显式转成 ApiException：
  /// validateStatus 放行了 <500，代理直接返回 401 HTML 时否则会被当成成功。
  dynamic _handle(Response<dynamic> res) {
    final status = res.statusCode ?? 0;
    if (status >= 400) {
      final body = res.data;
      // v1.0.23：非 JSON 响应（反代返回的 HTML 错误页）之前会得到空 message，
      // 界面上就是一条没有任何内容的错误条。这里退到状态文本并截断。
      var msg = body is Map ? (body['message'] ?? '').toString().trim() : '';
      if (msg.isEmpty && body is String) {
        final text = body.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
        if (text.isNotEmpty) msg = text.length > 120 ? '${text.substring(0, 120)}…' : text;
      }
      if (msg.isEmpty) msg = _statusText(status);
      throw ApiException(status, msg, httpStatus: status);
    }
    return _unwrap(res.data);
  }

  String _statusText(int status) {
    switch (status) {
      case 400:
        return '请求参数有误';
      case 401:
        return '登录已失效，请重新连接';
      case 403:
        return '没有权限访问该资源';
      case 404:
        return '路径不存在或已被移动';
      case 413:
        return '文件超过服务端限制';
      case 429:
        return '请求过于频繁，请稍后再试';
      default:
        return status >= 500 ? '服务端错误（$status）' : '请求失败（$status）';
    }
  }

  dynamic _unwrap(dynamic data) {
    if (data is Map) {
      final code = data['code'];
      if (code is num && code.toInt() != 200) {
        throw ApiException(code.toInt(), (data['message'] ?? '请求失败').toString());
      }
      return data['data'];
    }
    return data;
  }

  /// 429 只重试一次，退避 2s（服务端未给 Retry-After 时的兜底）。
  static const _rateLimitBackoff = Duration(seconds: 2);

  Future<dynamic> _get(String path, {Map<String, dynamic>? query}) async {
    for (var attempt = 0; ; attempt++) {
      try {
        final res = await _dio.get(path, queryParameters: query, options: _opts());
        return _handle(res);
      } on DioException catch (e) {
        throw ApiException.fromDio(e);
      } on ApiException catch (e) {
        if (e.code == 429 && attempt == 0) {
          await Future<void>.delayed(_rateLimitBackoff);
          continue;
        }
        rethrow;
      }
    }
  }

  Future<dynamic> _post(String path, [Map<String, dynamic>? body]) async {
    for (var attempt = 0; ; attempt++) {
      try {
        final res = await _dio.post(path, data: body ?? const {}, options: _opts());
        return _handle(res);
      } on DioException catch (e) {
        throw ApiException.fromDio(e);
      } on ApiException catch (e) {
        if (e.code == 429 && attempt == 0) {
          await Future<void>.delayed(_rateLimitBackoff);
          continue;
        }
        rethrow;
      }
    }
  }

  // ---------------------------------------------------------------- public

  Future<SiteInfo> publicSettings() async {
    final data = await _get('/api/public/settings');
    if (data is Map<String, dynamic>) return SiteInfo.fromJson(data);
    if (data is Map) return SiteInfo.fromJson(Map<String, dynamic>.from(data));
    return const SiteInfo(title: 'OpenList');
  }

  // ------------------------------------------------------------------ auth

  Future<String> login({required String username, required String password, String otpCode = ''}) async {
    final data = await _post('/api/auth/login', {
      'username': username,
      'password': password,
      if (otpCode.isNotEmpty) 'otp_code': otpCode,
    });
    final tokenValue = (data is Map ? data['token'] : null)?.toString();
    if (tokenValue == null || tokenValue.isEmpty) {
      throw const ApiException(-10, '服务器未返回 token');
    }
    token = tokenValue;
    return tokenValue;
  }

  Future<UserInfo> me() async {
    final data = await _get('/api/me');
    if (data is Map) return UserInfo.fromJson(Map<String, dynamic>.from(data));
    throw const ApiException(-11, '无法读取当前用户');
  }

  // -------------------------------------------------------------------- fs

  Future<FsListPage> list({
    String path = '/',
    String password = '',
    int page = 1,
    int perPage = 100,
    bool refresh = false,
    String orderBy = 'name',
    String orderDirection = 'asc',
  }) async {
    final data = await _post('/api/fs/list', {
      'path': path,
      'password': password,
      'page': page,
      'per_page': perPage,
      'refresh': refresh,
      'order_by': orderBy,
      'order_direction': orderDirection,
    });
    if (data is! Map) return const FsListPage(items: [], total: 0);
    final rawContent = data['content'];
    final items = <FileItem>[];
    if (rawContent is List) {
      for (final e in rawContent) {
        if (e is Map) items.add(FileItem.fromJson(Map<String, dynamic>.from(e)));
      }
    }
    return FsListPage(
      items: items,
      total: (data['total'] as num?)?.toInt() ?? items.length,
      write: data['write'] != false,
      provider: data['provider']?.toString(),
    );
  }

  Future<FileItem> get(String path, {String password = ''}) async {
    final data = await _post('/api/fs/get', {'path': path, 'password': password});
    if (data is Map) {
      final item = FileItem.fromJson({
        ...Map<String, dynamic>.from(data),
        'name': data['name'] ?? path.split('/').last,
        'is_dir': data['is_dir'] ?? false,
        'size': data['size'] ?? 0,
      });
      return item;
    }
    throw const ApiException(-12, '无法读取文件信息');
  }

  Future<List<FileItem>> search({
    required String parent,
    required String keywords,
    int scope = 0,
    int page = 1,
    int perPage = 50,
    String password = '',
  }) async {
    final data = await _post('/api/fs/search', {
      'parent': parent,
      'keywords': keywords,
      'scope': scope,
      'page': page,
      'per_page': perPage,
      'password': password,
    });
    if (data is Map && data['content'] is List) {
      return (data['content'] as List)
          .whereType<Map>()
          .map((e) => FileItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    return const [];
  }

  Future<List<DirNode>> dirs({String path = '/', String password = ''}) async {
    final data = await _post('/api/fs/dirs', {'path': path, 'password': password});
    // v1.0.33：兼容两种返回结构。
    //   AList v3：data 是数组 [{name, path}]
    //   OpenList v4 / 部分部署：data 是 {content: [...], total: n}
    // 之前只认数组，遇到 {content:[]} 就返回空列表 → 移动/复制弹窗永远进不去下一层。
    final raw = data is Map ? (data['content'] ?? data['data']) : data;
    if (raw is! List) return const [];
    final out = <DirNode>[];
    for (final e in raw) {
      if (e is Map) {
        final name = (e['name'] ?? '').toString();
        if (name.isEmpty) continue;
        final p = (e['path'] ?? '').toString();
        // 服务端没给 path 时按「当前目录 + 名称」拼，之前错误地回退成当前目录本身，
        // 点进去等于原地刷新，看起来就是「点不动」。
        out.add(DirNode(name, p.isEmpty ? joinPath(path, name) : p));
      }
    }
    return out;
  }

  Future<void> mkdir(String path) => _post('/api/fs/mkdir', {'path': path});

  Future<void> rename(String path, String name) => _post('/api/fs/rename', {'path': path, 'name': name});

  Future<void> move(String srcDir, String dstDir, List<String> names) =>
      _post('/api/fs/move', {'src_dir': srcDir, 'dst_dir': dstDir, 'names': names});

  Future<void> copy(String srcDir, String dstDir, List<String> names) =>
      _post('/api/fs/copy', {'src_dir': srcDir, 'dst_dir': dstDir, 'names': names});

  Future<void> remove(String dir, List<String> names) =>
      _post('/api/fs/remove', {'dir': dir, 'names': names});

  Future<void> addOfflineDownload({
    required List<String> urls,
    required String path,
    String deletePolicy = 'delete_on_upload_succeed',
  }) =>
      _post('/api/fs/add_offline_download', {
        'urls': urls,
        'path': path,
        'delete_policy': deletePolicy,
      });

  // ------------------------------------------------------------- admin (A)

  Future<List<StorageMount>> storages() async {
    final data = await _get('/api/admin/storage/list');
    if (data is List) {
      return data.whereType<Map>().map((e) => StorageMount.fromJson(Map<String, dynamic>.from(e))).toList();
    }
    if (data is Map && data['content'] is List) {
      return (data['content'] as List)
          .whereType<Map>()
          .map((e) => StorageMount.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    return const [];
  }

  Future<List<ServerTask>> tasks() async {
    final data = await _get('/api/task/list');
    if (data is List) {
      return data.whereType<Map>().map((e) => ServerTask.fromJson(Map<String, dynamic>.from(e))).toList();
    }
    return const [];
  }

  // -------------------------------------------------------------- urls

  static String _encodePath(String path) {
    final clean = path.startsWith('/') ? path.substring(1) : path;
    return clean.split('/').map(Uri.encodeComponent).join('/');
  }

  /// Signed direct link — supports Range, used for download and streaming.
  String downloadUrl(String path, {String? sign}) {
    final base = '$baseUrl/d/${_encodePath(path)}';
    if (sign == null || sign.isEmpty) return base;
    return '$base?sign=${Uri.encodeComponent(sign)}';
  }

  String proxyUrl(String path, {String? sign}) {
    final base = '$baseUrl/p/${_encodePath(path)}';
    if (sign == null || sign.isEmpty) return base;
    return '$base?sign=${Uri.encodeComponent(sign)}';
  }

  // ------------------------------------------------------------- transfer

  /// Download with optional resume. Streams to [sink] so the caller owns the
  /// file handle and can pause at any byte boundary.
  Future<int> downloadToFile({
    required String path,
    required String sign,
    required File target,
    required CancelToken cancelToken,
    required void Function(int received, int total) onProgress,
    int throttleBytesPerSecond = 0,
    int Function()? throttleRate,
  }) async {
    final existing = await target.exists() ? await target.length() : 0;
    final headers = <String, String>{};
    if (existing > 0) headers['Range'] = 'bytes=$existing-';
    Response<ResponseBody> res;
    try {
      res = await _dio.get<ResponseBody>(
        downloadUrl(path, sign: sign),
        options: Options(
          headers: headers,
          responseType: ResponseType.stream,
          followRedirects: true,
          // v1.0.36：原来只设了 receive/send 超时（1 天），没有连接超时。
          // 服务端不响应时请求会一直挂着，任务停在 running 0% 无法判断。
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(days: 1),
          sendTimeout: const Duration(days: 1),
          validateStatus: (s) => s != null && s < 400,
        ),
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      // 本地长度 ≥ 远端大小时服务端回 416。之前会被当成普通错误，
      // retry() 永远失败；这里给出可操作的提示。
      if (e.response?.statusCode == 416) {
        throw const ApiException(-1, '本地文件已完整或与服务器不一致，请删除后重新下载');
      }
      throw ApiException.fromDio(e);
    }

    final partial = res.statusCode == 206 && existing > 0;
    final totalHeader = res.headers.value('content-length');
    final contentLength = int.tryParse(totalHeader ?? '') ?? 0;
    var total = partial ? existing + contentLength : contentLength;
    var received = partial ? existing : 0;

    // v1.0.22：续传校验。只凭「本地有字节 + 返回 206」就往下追加，
    // 会在远端文件被替换时把新内容接到旧字节后面，产出静默损坏的文件。
    if (partial) {
      final contentRange = res.headers.value('content-range');
      final match = RegExp(r'bytes\s+(\d+)-(\d+)/(\d+|\*)').firstMatch(contentRange ?? '');
      final start = match == null ? null : int.tryParse(match.group(1)!);
      if (start != existing) {
        throw const ApiException(-1, '续传位置不匹配（文件可能已变化），请删除后重新下载');
      }
      // 用 ?. 而非 !：`start != existing` 抛错的路径虽然覆盖了 null 分支，
      // 但依赖「上面一定 throw」过于隐晦，改空安全更稳（v1.0.42）。
      final remoteTotal = match?.group(3);
      if (remoteTotal != null && remoteTotal != '*') {
        total = int.tryParse(remoteTotal) ?? total;
      }
    }

    // v1.0.22：先判空再打开 sink。之前顺序反了，`FileMode.write` 已经把
    // 本地同名文件截成 0 字节，然后才发现没有数据流。
    final body = res.data;
    if (body == null) {
      throw const ApiException(-13, '服务器未返回数据流');
    }
    final sink = target.openWrite(mode: partial ? FileMode.append : FileMode.write);
    var windowBytes = 0;
    var windowStart = DateTime.now();
    try {
      await for (final chunk in body.stream) {
        sink.add(chunk);
        received += chunk.length;
        windowBytes += chunk.length;
        // 每块都重新取限速值：设置页改完立刻作用于正在跑的下载。
        final rate = throttleRate?.call() ?? throttleBytesPerSecond;
        if (rate > 0) {
          final elapsed = DateTime.now().difference(windowStart).inMilliseconds;
          final expectedMs = windowBytes * 1000 / rate;
          if (elapsed < expectedMs) {
            await Future<void>.delayed(Duration(milliseconds: (expectedMs - elapsed).round()));
          }
          if (windowBytes > rate * 2) {
            windowBytes = 0;
            windowStart = DateTime.now();
          }
        }
        onProgress(received, total);
        if (cancelToken.isCancelled) {
          // v1.0.21：取消必须抛出去。之前是 break 后照常返回 received 长度，
          // 上层会把半截文件当成「已完成」（文件被静默截断且标记成功）。
          throw const ApiException(-1, '传输已取消');
        }
      }
    } finally {
      await sink.flush();
      await sink.close();
    }
    // v1.0.22：完整性断言。服务端提前关流 / 网络抖动时 `await for` 会正常结束，
    // 之前直接把「收了多少字节」当成功，半截文件就被标记为已完成。
    // v1.0.35：压缩传输（gzip/br）下 content-length 是压缩前长度，与实收字节不等，
    // 这种响应不做长度断言，避免把正常下载判成「不完整」。
    final encoding = (res.headers.value('content-encoding') ?? '').toLowerCase();
    final compressed = encoding.isNotEmpty && encoding != 'identity';
    if (!compressed && total > 0 && received < total) {
      throw ApiException(-1, '下载不完整（$received/$total 字节），可重试续传');
    }
    return received;
  }

  /// 上传单个文件。
  ///
  /// [throttleBytesPerSecond] 传 0 表示不限速。限速实现为「按累计字节数配额
  /// 放行」的节流流：把 openRead() 的分块按预算延迟后再交给 Dio，因此不会在
  /// 内核缓冲区里一次性把整份文件推出去（v2.3 修复「上传限速设置无效」）。
  Future<void> uploadFile({
    required String remotePath,
    required File source,
    required CancelToken cancelToken,
    required void Function(int sent, int total) onProgress,
    int throttleBytesPerSecond = 0,
    int Function()? throttleRate,
  }) async {
    final length = await source.length();
    final headers = <String, String>{
      'File-Path': Uri.encodeComponent(remotePath),
      'Content-Type': 'application/octet-stream',
      'Content-Length': '$length',
    };
    if (token != null && token!.isNotEmpty) headers['Authorization'] = token!;
    final rateOf = throttleRate ?? () => throttleBytesPerSecond;
    final stream = _throttle(source.openRead(), rateOf, cancelToken);
    try {
      final res = await _dio.put<dynamic>(
        '/api/fs/put',
        data: stream,
        options: Options(
          headers: headers,
          sendTimeout: const Duration(days: 1),
          receiveTimeout: const Duration(days: 1),
          // 与 _get/_post 一致：>=400 必须走错误分支，否则 401 会被当成功。
          validateStatus: (s) => s != null && s < 400,
        ),
        cancelToken: cancelToken,
        onSendProgress: onProgress,
      );
      _handle(res);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// 累计配额节流：第 n 个字节应在 n / rate 秒之后才发出。
  ///
  /// [rateOf] 每个分块都会重新取值，因此运行中修改限速立即生效
  /// （v2.6：之前只在任务开始时读一次，改限速要等下一个任务）。
  Stream<List<int>> _throttle(
    Stream<List<int>> input,
    int Function() rateOf,
    CancelToken cancelToken,
  ) async* {
    final watch = Stopwatch()..start();
    var sent = 0;
    await for (final chunk in input) {
      sent += chunk.length;
      final rate = rateOf();
      if (rate > 0) {
        final expectedMs = sent * 1000 / rate;
        final elapsedMs = watch.elapsedMilliseconds;
        if (expectedMs > elapsedMs) {
          await Future<void>.delayed(Duration(milliseconds: (expectedMs - elapsedMs).round()));
        }
      }
      if (cancelToken.isCancelled) return;
      yield chunk;
    }
  }
}
