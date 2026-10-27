/// 驱动元数据：来自引擎的 `/api/admin/driver/list`，用于动态生成表单。
library;

import '../i18n/zh.dart';

/// 由客户端自己处理、不走通用字段渲染的引擎字段。
const Set<String> kHandledStorageFields = {'mount_path', 'cache_expiration', 'remark'};

class DriverItem {
  final String name;
  final String type; // string | number | bool | select | text
  final String? defaultValue;
  final List<String> options;
  final bool required;
  final String? help;

  const DriverItem({
    required this.name,
    required this.type,
    this.defaultValue,
    this.options = const [],
    this.required = false,
    this.help,
  });

  bool get isBool => type == 'bool';
  bool get isNumber => type == 'number';
  bool get isSelect => type == 'select' && options.isNotEmpty;
  bool get isMultiline => type == 'text';

  /// 引擎没有 password 类型，只能按字段名判断敏感项。
  ///
  /// 判定规则集中在 `isSecretFieldName`（i18n 层），与配置导出共用一套，
  /// 避免两处各写一份后判定漂移 —— 那会造成「表单里标了密码、导出却带出去了」。
  bool get isSecret => isSecretFieldName(name);

  factory DriverItem.fromJson(Map<String, dynamic> json) {
    final rawOptions = json['options'];
    final options = <String>[];
    if (rawOptions is String) {
      options.addAll(rawOptions.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty));
    } else if (rawOptions is List) {
      for (final entry in rawOptions) {
        if (entry is Map) {
          final value = entry['value'] ?? entry['label'] ?? '';
          if ('$value'.isNotEmpty) options.add('$value');
        } else if (entry != null && '$entry'.isNotEmpty) {
          options.add('$entry');
        }
      }
    }
    final rawDefault = json['default'];
    return DriverItem(
      name: (json['name'] ?? '').toString(),
      type: (json['type'] ?? 'string').toString().toLowerCase(),
      defaultValue: rawDefault == null ? null : '$rawDefault',
      options: options,
      required: json['required'] == true,
      help: json['help']?.toString(),
    );
  }
}

class DriverInfo {
  final String name;
  final List<DriverItem> common;
  final List<DriverItem> additional;
  final Map<String, dynamic> config;

  const DriverInfo({
    required this.name,
    this.common = const [],
    this.additional = const [],
    this.config = const {},
  });

  /// 表单要渲染的字段：引擎的 common + additional。
  ///
  /// OpenList 的 Web 端添加存储表单 = 存储顶层字段（驱动 / 挂载路径 / 序号 /
  /// 备注 / 缓存过期时间）+ 驱动 common 字段 + 驱动特有（additional）字段。
  /// 客户端此前只渲染 additional，把 common 那一整组（排序、备注、缓存策略、
  /// WebDAV 策略、下载代理网址、种子策略……）整组漏掉了，用户无法配置。
  ///
  /// 这里排除三个由客户端自己手写、不走通用字段渲染的字段：
  /// - `mount_path`：客户端由「名称」派生，语义同 Web 端（见 mountPathOf）
  /// - `cache_expiration`：客户端有独立的「缓存过期时间（秒）」输入框
  /// - `remark`：客户端用名称作为备注（与 Web 端「备注」字段语义重合）
  List<DriverItem> get formFields => [
        ...common.where((e) => !kHandledStorageFields.contains(e.name)),
        ...additional.where((e) => !kHandledStorageFields.contains(e.name)),
      ];

  factory DriverInfo.fromJson(String name, Map<String, dynamic> json) {
    List<DriverItem> parse(Object? raw) {
      if (raw is! List) return const [];
      return raw.whereType<Map>().map((e) => DriverItem.fromJson(Map<String, dynamic>.from(e))).toList();
    }

    return DriverInfo(
      name: name,
      common: parse(json['common']),
      additional: parse(json['additional']),
      config: json['config'] is Map ? Map<String, dynamic>.from(json['config'] as Map) : const {},
    );
  }

  /// 驱动是否支持本地排序（决定是否显示排序字段）。
  bool get localSort => config['local_sort'] == true;
}

/// 客户端对个别引擎字段默认值的覆盖。
///
/// 只在「引擎给的默认值不符合本应用预期」时登记，其余字段一律沿用引擎默认。
/// 目前只有一条：
/// - `Local.show_hidden`：引擎默认 `true`（显示隐藏文件）。本地存储常被挂在
///   磁盘根目录（`C:\`、`/`），隐藏项（`$RECYCLE.BIN`、`System Volume
///   Information`、`.git`、`.DS_Store`）会把列表塞满；客户端默认关，
///   需要时用户在表单里自行打开即可。
const Map<String, Map<String, String>> kDriverDefaultOverrides = {
  'Local': {'show_hidden': 'false'},
};

/// 取某驱动字段在「新建存储」表单里的默认值：先看客户端覆盖表，再退回引擎值。
String? formDefaultOf(String driver, DriverItem item) =>
    kDriverDefaultOverrides[driver]?[item.name] ?? item.defaultValue;

enum DriverGroup { local, object, cloud, server, other }

String driverGroupLabel(DriverGroup group) => switch (group) {
      DriverGroup.local => '本地与文件协议',
      DriverGroup.object => '对象存储',
      DriverGroup.cloud => '网盘与分享',
      DriverGroup.server => '远程服务器',
      DriverGroup.other => '其它',
    };

DriverGroup driverGroupOf(String name) {
  const local = {'Local', 'WebDav', 'Sftp', 'FTP', 'SMB'};
  const object = {'S3', 'Doge', 'Azure Blob Storage', 'USS', 'Bunny Storage', 'Seafile'};
  const server = {'OpenList', 'AList V3', 'Alias', 'Virtual'};
  if (local.contains(name)) return DriverGroup.local;
  if (object.contains(name)) return DriverGroup.object;
  if (server.contains(name)) return DriverGroup.server;

  final n = name.toLowerCase();
  const cloudHints = [
    'ali', 'baidu', 'quark', 'uc', '115', '123', '139', '189', 'thunder', 'pikpak',
    'onedrive', 'google', 'dropbox', 'mega', 'lanzou', 'weiyun', 'yandex', 'box',
    'cloud', 'drive', 'pan', 'share', 'terabox', 'mediafire', 'github', 'teambition',
  ];
  if (cloudHints.any(n.contains)) return DriverGroup.cloud;
  return DriverGroup.other;
}

/// 字段取值转换：引擎侧 addition 是 JSON，布尔/数字都要按真实类型提交。
Object? coerceItemValue(DriverItem item, String raw) {
  if (item.isBool) return raw == 'true';
  if (item.isNumber) {
    final parsed = int.tryParse(raw.trim());
    if (parsed != null) return parsed;
    final dbl = double.tryParse(raw.trim());
    return dbl ?? 0;
  }
  return raw;
}
