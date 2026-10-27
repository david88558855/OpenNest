/// 客户端版本信息。
///
/// 这里是唯一来源：pubspec.yaml 的 version 必须与之保持一致（CI 的
/// 「版本号一致性」步骤会校验，避免设置页与产物版本串出现偏差）。
class AppInfo {
  const AppInfo._();

  static const version = '0.5.2';
  static const build = 8;

  static const name = 'OpenNest';

  /// 设置页 / 关于页展示用：1.0.12 (13)
  static String get versionLabel => '$version ($build)';

  /// 侧栏页脚：OpenNest 0.1.0
  static String get shortLabel => '$name $version';

  /// 服务端版本串的短形式。
  ///
  /// OpenList 的 /api/public/settings 会返回形如
  /// `dev (Commit: unknown) - Frontend: rolling - Build at: unknown` 的长串，
  /// 直接塞进列表行会把标题挤成竖排（v2.3 修复）。这里只保留第一段，
  /// 并截到 18 个字符。
  static String shortVersion(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return '—';
    // 先按换行 / 破折号 / 括号切断，只取「主版本」那一段。
    var head = value.split(RegExp(r'[\r\n]')).first;
    head = head.split(RegExp(r'\s+-\s+')).first;
    head = head.split(' (').first.trim();
    if (head.isEmpty) head = value;
    if (head.length > 18) head = '${head.substring(0, 17)}…';
    return head;
  }

  /// 服务端版本是否有信息量。
  ///
  /// 未发布实例会返回 `dev (Commit: unknown) …`，截短后只剩「dev」，
  /// 拼在地址后面变成 `127.0.0.1:5244 · dev` —— 对用户没有意义（v2.6）。
  static bool hasMeaningfulVersion(String? raw) {
    final head = shortVersion(raw).trim().toLowerCase();
    if (head.isEmpty || head == '—') return false;
    if (head.length <= 1) return false;
    const noise = {'dev', 'unknown', 'none', 'null', 'n/a', 'na', '-', '0'};
    if (noise.contains(head)) return false;
    // dev 分支带后缀的形态（dev+abc123 / dev.20260101）同样视为占位。
    if (RegExp(r'^dev([\s.+-]|$)').hasMatch(head)) return false;
    return true;
  }

  /// 地址 + 版本：版本无意义时只显示地址，不留下孤零零的分隔点。
  static String hostWithVersion(String host, String? raw) =>
      hasMeaningfulVersion(raw) ? '$host · ${shortVersion(raw)}' : host;
}
