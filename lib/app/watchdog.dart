import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/sources/storage_health.dart';

/// 应用级看护：挂在 MaterialApp 外层，跨页面常驻。
///
/// 只负责驱动「存储源状态」的自动刷新，让状态不再依赖用户手动点
/// 「测试连接」：
/// - 启动后开始周期轮询（引擎列表）+ 深度探测（逐源真访问）；
/// - 应用回到前台时立刻补一轮（桌面切窗口、手机切回来都算）；
/// - 应用退出时停掉定时器。
///
/// 之所以放在这里而不是设置页：用户可能一直停在文件页，10 分钟后
/// 某个存储远端失联了，状态也必须已经更新过。
class AppWatchdog extends ConsumerStatefulWidget {
  const AppWatchdog({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppWatchdog> createState() => _AppWatchdogState();
}

class _AppWatchdogState extends ConsumerState<AppWatchdog> with WidgetsBindingObserver {
  /// 提前取好 notifier：dispose 阶段不适合再走 ref.read。
  StorageHealthNotifier? _health;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _health = ref.read(storageHealthProvider.notifier);
    // 引擎还没起来时 attach 也不会白转：探测入口会自行判断会话是否就绪。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _health?.attach();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // 后台期间定时器可能被系统节流，回到前台立刻补一轮（3 秒合并）。
    _health?.scheduleRefresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _health?.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
