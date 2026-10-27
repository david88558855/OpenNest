import 'dart:convert';

/// 存储的顶层可配置项（引擎 storage 模型的公共字段）。
///
/// 这些字段**不在 `addition` 里** —— 引擎把它们定义在 storage 顶层，
/// 与驱动无关但每个存储都能单独配置（排序、缓存策略、WebDAV 策略、
/// 下载代理网址、种子策略……）。OpenList 的 Web 端表单会把它们显示出来。
///
/// 键是引擎的字段名；值缺省表示「沿用引擎默认值」。
const Set<String> kStorageOptionKeys = {
  'order',
  'custom_cache_policies',
  'disable_index',
  'enable_sign',
  'web_proxy',
  'webdav_policy',
  'proxy_range',
  'down_proxy_url',
  'disable_proxy_sign',
  'order_by',
  'order_direction',
  'extract_folder',
  'seed_policy',
};

/// 一条存储源，对应引擎侧的一条 storage 记录。
///
/// 展示名用 `remark`，挂载路径由用户命名（与 OpenList Web 端一致）。
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

  /// 顶层可配置项（见 [kStorageOptionKeys]）。
  final Map<String, dynamic> options;

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
    this.options = const {},
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
    Map<String, dynamic>? options,
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
      options: options ?? this.options,
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
        options: {
          for (final key in kStorageOptionKeys)
            if (json.containsKey(key)) key: json[key],
        },
      );

  /// 提交给引擎的请求体。
  ///
  /// `addition` 必须是 JSON 字符串；公共字段（代理策略、排序、签名开关、缓存）
  /// 一个都不能少，否则部分驱动的直链与排序会表现异常。
  Map<String, dynamic> toRequestJson({bool withId = false}) {
    final json = <String, dynamic>{
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
      // 0.5.10：与表单默认值保持一致（禁用索引 / 启用签名默认开启）。
      // 引擎返回的 storage 一定带这两个键，正常路径下会被 options 覆盖；
      // 这里的值只是「引擎没给字段」时的兜底。
      'disable_index': true,
      'enable_sign': true,
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
    // 用户在表单里改了顶层项就覆盖默认值；没改的保持引擎默认。
    for (final key in kStorageOptionKeys) {
      final value = options[key];
      if (value != null) json[key] = value;
    }
    return json;
  }
}
