import 'package:dio/dio.dart';

class ApiException implements Exception {
  final int code;
  final String message;
  final bool network;
  final int? httpStatus;

  const ApiException(this.code, this.message, {this.network = false, this.httpStatus});

  /// 401 回登录、403 权限、404 路径失效、429 退避、5xx 服务端。
  String get friendly {
    if (network) return message;
    switch (code) {
      case 401:
        return '登录已失效，请重新连接';
      case 403:
        return '没有访问该路径的权限';
      case 404:
        return '路径不存在或已被移动';
      case 429:
        return '请求过于频繁，请稍后重试';
      default:
        if (code >= 500) return '服务端异常（$code）';
        return message.isEmpty ? '请求失败（$code）' : message;
    }
  }

  bool get needsReauth => code == 401;
  bool get rateLimited => code == 429;

  static ApiException fromDio(DioException e) {
    final status = e.response?.statusCode;
    if (e.type == DioExceptionType.connectionTimeout) {
      return const ApiException(-1, '连接超时，检查地址与网络', network: true);
    }
    if (e.type == DioExceptionType.receiveTimeout) {
      return const ApiException(-2, '服务器响应超时', network: true);
    }
    if (e.type == DioExceptionType.sendTimeout) {
      return const ApiException(-3, '上传超时', network: true);
    }
    if (e.type == DioExceptionType.connectionError) {
      return const ApiException(-4, '无法连接服务器，检查地址与网络', network: true);
    }
    if (e.type == DioExceptionType.badCertificate) {
      return const ApiException(-5, 'TLS 证书校验失败', network: true);
    }
    if (e.type == DioExceptionType.cancel) {
      return const ApiException(-6, '请求已取消', network: true);
    }
    final body = e.response?.data;
    if (body is Map && body['code'] is num) {
      final code = (body['code'] as num).toInt();
      final msg = (body['message'] ?? '').toString();
      if (code != 200) {
        return ApiException(code, msg, httpStatus: status);
      }
    }
    if (status != null && status >= 400) {
      final msg = body is Map ? (body['message'] ?? '').toString() : '';
      return ApiException(status, msg, httpStatus: status);
    }
    return ApiException(-7, e.message ?? '请求失败', network: true);
  }

  @override
  String toString() => 'ApiException($code, $message)';
}
