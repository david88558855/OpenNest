import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';

import '../i18n/zh.dart';
import '../models/storage_source.dart';
import 'sidecar_paths.dart';

/// 存储源配置的导入 / 导出。
///
/// 设计稿 D8 的工具栏有「导入配置 / 导出配置」两个按钮，图例写明
/// 「配置可 JSON 导出分享，**不含任何密码**（Cyberduck 书签模型）」。
///
/// 因此导出时会把机密字段整条剔除（密码、令牌、私钥、Cookie…），
/// 导入时这些字段保持为空 —— 用户补齐后才能真正连上远端。
/// 这一点在导入结果里会逐条说明，不做静默失败。
/// 导入 / 导出失败：message 可直接展示给用户。
///
/// 0.5.11：以前 `pickAndParse` 把「用户取消」和「文件格式不对 / 选择器异常」
/// 全部收敛成 null，调用方只能静默 return —— 用户选了别的 JSON 之后界面
/// 一点反应都没有，看起来像没点上。
class SourceConfigException implements Exception {
  final String message;
  const SourceConfigException(this.message);

  @override
  String toString() => message;
}

class SourceConfigBundle {
  /// 导出文件的格式版本，便于将来扩展。
  static const formatVersion = 1;

  final List<StorageSource> sources;

  const SourceConfigBundle(this.sources);

  /// 序列化为可读的 JSON 文本。
  String encode() {
    final payload = {
      'format': 'opennest.source-config',
      'version': formatVersion,
      'exported_at': DateTime.now().toIso8601String(),
      // 明确声明不含机密，导入方据此提示用户补齐。
      'contains_secrets': false,
      'sources': sources.map(_encodeOne).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  static Map<String, dynamic> _encodeOne(StorageSource source) {
    return {
      'driver': source.driver,
      'remark': source.remark,
      'cache_expiration': source.cacheExpiration,
      'disabled': source.disabled,
      // 机密字段整条剔除，键名保留为占位以便用户知道要补什么。
      'addition': {
        for (final entry in source.addition.entries)
          entry.key: isSecretField(entry.key) ? '' : entry.value,
      },
      'missing_secret_fields': [
        for (final entry in source.addition.entries)
          if (isSecretField(entry.key)) entry.key,
      ],
    };
  }

  /// 解析导出的 JSON 文本。格式不对时抛出 [FormatException]。
  static SourceConfigBundle decode(String text) {
    final Object? raw;
    try {
      raw = jsonDecode(text);
    } catch (error) {
      throw const FormatException('不是合法的 JSON 文件');
    }
    if (raw is! Map) throw const FormatException('配置文件顶层不是对象');
    final list = raw['sources'];
    if (list is! List) throw const FormatException('配置文件缺少 sources 列表');

    final sources = <StorageSource>[];
    for (final entry in list) {
      if (entry is! Map) continue;
      final map = Map<String, dynamic>.from(entry);
      final addition = map['addition'];
      sources.add(
        StorageSource(
          mountPath: '',
          driver: (map['driver'] ?? '').toString(),
          remark: (map['remark'] ?? '').toString(),
          addition: StorageSource.decodeAddition(addition),
          disabled: map['disabled'] == true,
          cacheExpiration: (map['cache_expiration'] as num?)?.toInt() ?? 30,
        ),
      );
    }
    return SourceConfigBundle(sources);
  }

  /// 导出到文件：写到用户选定路径（桌面）或默认落到数据目录（移动端）。
  ///
  /// 返回实际写入的路径，失败返回 null。
  Future<String?> exportTo(String path) async {
    try {
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsString(encode(), flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  /// 选一个 JSON 文件并解析。
  ///
  /// 返回 null 只表示「用户取消」；选择器异常或文件格式错误会抛
  /// [SourceConfigException]，调用方应把 message 展示出来。
  static Future<SourceConfigBundle?> pickAndParse() async {
    final FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
    } catch (error) {
      throw SourceConfigException('无法打开文件选择器：$error');
    }
    final path = result?.files.single.path;
    if (path == null || path.isEmpty) return null;
    final String text;
    try {
      text = await File(path).readAsString();
    } catch (error) {
      throw SourceConfigException('读取文件失败：$error');
    }
    try {
      return decode(text);
    } catch (error) {
      throw SourceConfigException('不是有效的存储源配置文件：$error');
    }
  }

  /// 默认导出文件名（带时间戳，便于区分多次导出）。
  static String defaultFileName() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'opennest-sources-${now.year}${two(now.month)}${two(now.day)}'
        '-${two(now.hour)}${two(now.minute)}${two(now.second)}.json';
  }

  /// 导出到数据目录（无需用户选路径的场景）。
  Future<String?> exportToDataDir() async {
    final dir = await SidecarPaths.root();
    return exportTo('${dir.path}${Platform.pathSeparator}${defaultFileName()}');
  }
}

/// 字段名是否属于机密（导出时剔除）。
///
/// 判定规则集中在 i18n 层的 `isSecretFieldName`，与驱动表单共用一套，
/// 避免「表单里标了密码、导出却带出去了」这类漏洞。
bool isSecretField(String name) => isSecretFieldName(name);
