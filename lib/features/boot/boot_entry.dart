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

/// 降级模式：引擎起不来时仍然放行到主界面。
///
/// 主题不是「引擎坏了就什么都不给看」—— 引擎失败时用户至少还要能：
/// 看到错误原因、打开日志目录、重启引擎、去「存储源」停用肇事的那个源。
/// 这些都在设置页里，而路由此前把 `failed` 一律拦回启动页，等于把唯一的
/// 修复入口也锁掉了。开启后启动页与路由都不再拦截。
final degradedModeProvider = StateProvider<bool>((ref) => false);

/// 「点过稍后再说」的标记。
///
/// 不能用 `app.` 前缀 —— 那个命名空间由 AppSettings 整体覆盖写，会被清理掉。
const String kOnboardDoneKey = 'ol_onboard_done';
