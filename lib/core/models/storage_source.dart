import 'dart:convert';

/// 一条存储源，对应引擎侧的一条 storage 记录。
///
/// 展示名用 `remark`，挂载路径由客户端生成（`/s_<8位>`），对用户不可见。
class StorageSource {
  final int id;
  final String mountPath;
  final String driver;
  final String remark;
  final Map<String, dynamic> addition;
  final String status;
  final bool disabled;
  final int cacheExpiration;
  final int order;

  const StorageSource({
    this.id = 0,
    required this.mountPath,
    required this.driver,
    this.remark = '',
    this.addition = const {},
    this.status = '',
    this.disabled = false,
    this.cacheExpiration = 30,
    this.order = 0,
  });

  String get displayName => remark.trim().isEmpty ? mountPath : remark.trim();

  bool get isHealthy {
    final s = status.toLowerCase();
    return s == 'work' || s == 'ok' || s == '1';
  }

  StorageSource copyWith({
    int? id,
    String? mountPath,
    String? driver,
    String? remark,
    Map<String, dynamic>? addition,
    String? status,
    bool? disabled,
    int? cacheExpiration,
    int? order,
  }) {
    return StorageSource(
      id: id ?? this.id,
      mountPath: mountPath ?? this.mountPath,
      driver: driver ?? this.driver,
      remark: remark ?? this.remark,
      addition: addition ?? this.addition,
      status: status ?? this.status,
      disabled: disabled ?? this.disabled,
      cacheExpiration: cacheExpiration ?? this.cacheExpiration,
      order: order ?? this.order,
    );
  }

  static Map<String, dynamic> decodeAddition(Object? raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return <String, dynamic>{};
  }

  factory StorageSource.fromJson(Map<String, dynamic> json) => StorageSource(
        id: (json['id'] as num?)?.toInt() ?? 0,
        mountPath: (json['mount_path'] ?? '').toString(),
        driver: (json['driver'] ?? '').toString(),
        remark: (json['remark'] ?? '').toString(),
        addition: decodeAddition(json['addition']),
        status: (json['status'] ?? '').toString(),
        disabled: json['disabled'] == true,
        cacheExpiration: (json['cache_expiration'] as num?)?.toInt() ?? 30,
        order: (json['order'] as num?)?.toInt() ?? 0,
      );

  /// 提交给引擎的请求体。
  ///
  /// `addition` 必须是 JSON 字符串；公共字段（代理策略、排序、签名开关、缓存）
  /// 一个都不能少，否则部分驱动的直链与排序会表现异常。
  Map<String, dynamic> toRequestJson({bool withId = false}) => {
        if (withId && id > 0) 'id': id,
        'mount_path': mountPath,
        'order': order,
        'driver': driver,
        'cache_expiration': cacheExpiration,
        'custom_cache_policies': '',
        'status': status,
        'addition': jsonEncode(addition),
        'remark': remark,
        'disabled': disabled,
        'disable_index': false,
        'enable_sign': false,
        'web_proxy': false,
        'webdav_policy': '302_redirect',
        'proxy_range': false,
        'down_proxy_url': '',
        'disable_proxy_sign': false,
        'order_by': '',
        'order_direction': '',
        'extract_folder': '',
        'seed_policy': 'inherit',
      };
}
