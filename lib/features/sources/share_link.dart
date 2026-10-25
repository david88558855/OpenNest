/// 分享链接识别：把「链接（含提取码）」解析成驱动名 + 通用字段值。
///
/// 设计稿的「粘贴分享链接直接导入」只做**识别 + 预填**，不替用户建源：
/// 分享链接的可用字段与引擎驱动字段名对不上时，自动建源会造出打不开的挂载。
/// 因此这里输出通用键（`share_id` / `share_pwd` / `url`），由
/// [mapShareFields] 按驱动真实 schema 映射后填进表单。
///
/// 刻意不识别百度 / 115 分享：它们的驱动需要 cookie，粘链接根本连不通，
/// 识别了反而误导用户。
library;

import '../../core/models/driver_schema.dart';

/// 通用键 → 驱动字段别名（引擎侧同义写法都出现过，按 schema 实际存在的命中）。
const Map<String, List<String>> kShareFieldAliases = {
  'share_id': ['share_id', 'shareid', 'share_folder_id', 'file_id'],
  'share_pwd': ['share_pwd', 'share_password', 'share_pass', 'pwd', 'password'],
  'url': ['url', 'share_link', 'share_url', 'link', 'sharelink'],
};

final RegExp _aliShare = RegExp(
  r'https?://(?:www\.)?(?:aliyundrive|alipan)\.com/s/([0-9a-zA-Z]+)',
  caseSensitive: false,
);

final RegExp _oneDrive = RegExp(
  r'https?://(?:1drv\.ms|onedrive\.live\.com|[a-z0-9-]+\.sharepoint\.com)/\S+',
  caseSensitive: false,
);

final RegExp _pwdQuery = RegExp(
  r'[?&](?:pwd|password|passwd|passcode)=([0-9a-zA-Z]{4})',
  caseSensitive: false,
);

final RegExp _pwdText = RegExp(
  r'(?:提取码|密码|访问码|口令|passcode)\s*[:：]?\s*([0-9a-zA-Z]{4})',
  caseSensitive: false,
);

class ShareLink {
  /// 引擎侧的驱动名（`/api/admin/driver/list` 的键）。
  final String driver;

  /// 通用键值：share_id / share_pwd / url。
  final Map<String, String> values;

  const ShareLink({required this.driver, required this.values});
}

/// 解析失败返回 null（交给界面提示用户手动选类型）。
ShareLink? parseShareLink(String input) {
  final text = input.trim();
  if (text.isEmpty) return null;

  final ali = _aliShare.firstMatch(text);
  if (ali != null) {
    final values = <String, String>{'share_id': ali.group(1)!};
    // 提取码可能在 query（?pwd=ab12），也可能写在正文（「提取码: ab12」）。
    final pwd = _pwdQuery.firstMatch(text)?.group(1) ?? _pwdText.firstMatch(text)?.group(1);
    if (pwd != null && pwd.isNotEmpty) values['share_pwd'] = pwd;
    return ShareLink(driver: 'AliyundriveShare', values: values);
  }

  final oneDrive = _oneDrive.firstMatch(text);
  if (oneDrive != null) {
    return ShareLink(driver: 'Onedrive Sharelink', values: {'url': oneDrive.group(0)!});
  }

  return null;
}

/// 把通用键映射到驱动真实字段名；命中不到就丢弃（宁可空着，也不填错格）。
Map<String, String> mapShareFields(Map<String, String> values, List<DriverItem> fields) {
  final byLower = <String, String>{for (final field in fields) field.name.toLowerCase(): field.name};
  final mapped = <String, String>{};
  values.forEach((generic, value) {
    for (final alias in kShareFieldAliases[generic] ?? const <String>[]) {
      final real = byLower[alias];
      if (real != null) {
        mapped[real] = value;
        break;
      }
    }
  });
  return mapped;
}
