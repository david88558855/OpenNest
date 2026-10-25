import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 启动完成后的落点。
///
/// `redirect` 是同步闭包，而「有没有存储源」需要异步查引擎，所以由启动页
/// 判定一次后写入这里，路由只读结果。引擎重新启动时复位成 [unknown]。
enum BootEntry {
  /// 尚未判定：启动页还在拉引擎，redirect 不要抢跳。
  unknown,

  /// 首启且没有存储源、也没点过「稍后再说」→ 欢迎页。
  welcome,

  /// 已有存储源（或已跳过引导）→ 直接进文件页。
  files,
}

final bootEntryProvider = StateProvider<BootEntry>((ref) => BootEntry.unknown);

/// 「点过稍后再说」的标记。
///
/// 不能用 `app.` 前缀 —— 那个命名空间由 AppSettings 整体覆盖写，会被清理掉。
const String kOnboardDoneKey = 'ol_onboard_done';
