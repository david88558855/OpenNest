import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/sidecar/sidecar_controller.dart';
import '../core/sidecar/sidecar_state.dart';
import '../features/sources/storage_health.dart';
import 'providers.dart';

/// 应用级看护：挂在 MaterialApp 外层，跨页面常驻。
///
/// 两件事，都不允许挡住启动：
/// 1. **引擎就绪后的后台引导**（0.5.11）：建立会话 → 打开目录。
///    引擎的 `StoragesLoaded` 中间件在「全部存储源加载完」之前会挂住除 `/`
///    以外的接口，一个连不通的源就能把这串调用拖几十秒。启动页因此只等
///    引擎进程就绪，剩下的在这里按需重试 —— 界面早已可用，不让「某个存储
///    连不上」变成「应用打不开」。
/// 2. **存储源状态刷新**：会话就绪之后才开始轮询 + 深度探测。以前在
///    initState 就 attach，引擎还在加载存储源时就去打 `fs/list`，
///    等于在启动最忙的时候又压上一层真实远端访问。
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
  ProviderSubscription<SidecarState>? _sidecarSub;
  Timer? _retryTimer;

  /// 后台引导是否正在跑（同一时刻只允许一轮）。
  bool _working = false;

  /// 已重试次数；会话建立成功后归零。
  int _attempts = 0;

  /// 存储源健康探测是否已经启动（attach 只能调一次，见 _establish）。
  bool _healthAttached = false;

  /// 重试节奏：起步 3 秒，随失败次数退避到 10 秒，最多 60 轮（约 8 分钟）。
  ///
  /// 超过这个时长说明引擎侧卡得比「源加载慢」更严重，继续静默重试只是白耗
  /// 电量与连接。此时停下 —— 骨架屏与下拉刷新仍然可用，用户手动刷新会再
  /// 走一轮会话重建。
  static const int _maxAttempts = 60;

  Duration get _retryGap {
    if (_attempts <= 3) return const Duration(seconds: 3);
    if (_attempts <= 15) return const Duration(seconds: 6);
    return const Duration(seconds: 10);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _health = ref.read(storageHealthProvider.notifier);
    // 引擎就绪（含冷启动首次就绪、设置页重启后再次就绪）就推进一轮后台引导。
    _sidecarSub = ref.listenManual<SidecarState>(
      sidecarProvider,
      (previous, next) {
        if (next.status != SidecarStatus.ready) return;
        if (previous?.status == SidecarStatus.ready) return;
        _attempts = 0;
        _kick();
      },
      fireImmediately: true,
    );
  }

  void _kick({Duration delay = Duration.zero}) {
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () => unawaited(_establish()));
  }

  void _scheduleRetry() {
    if (_attempts >= _maxAttempts) return;
    _attempts++;
    _kick(delay: _retryGap);
  }

  /// 引擎就绪后的后台引导：会话 → 存储源状态 → 目录。
  Future<void> _establish() async {
    if (!mounted) return;
    if (_working) {
      // 上一轮还在等引擎接口（可能正被中间件挂住）：排队，别丢这次触发。
      _scheduleRetry();
      return;
    }
    if (ref.read(sidecarProvider).status != SidecarStatus.ready) return;
    _working = true;
    try {
      final sidecar = ref.read(sidecarProvider);
      var session = ref.read(sessionProvider);
      // 引擎重启后端口会重新分配，而 `signedIn` 仍是 true —— 只判 signedIn
      // 会让会话一直指向已经死掉的旧端口（之后所有请求都是连接失败）。
      // 端口不一致即视为过期，重建会话。
      final stale = session.signedIn && sidecar.port != null && session.port != sidecar.port;
      if (!session.signedIn || stale) {
        if (stale) {
          // 先清空，让 boot() 走完整的重建路径（否则 boot 里的早退分支会复用旧状态）。
          await ref.read(sessionProvider.notifier).retry();
        } else {
          await ref.read(sessionProvider.notifier).boot();
        }
        if (!mounted) return;
        session = ref.read(sessionProvider);
      }
      if (!session.signedIn) {
        // 会话仍建立不起来：引擎在等存储源加载完（或引擎刚重启）。
        _scheduleRetry();
        return;
      }
      _attempts = 0;
      // 会话就绪 → 存储源的健康轮询 / 深度探测可以开始了。
      // 只 attach 一次：attach 内部会立刻跑一轮 probeAll，每次 _establish
      // 都调等于每 3 秒给每个源打一次真实远端访问。
      if (!_healthAttached) {
        _healthAttached = true;
        _health?.attach();
      }
      // 冷启动时目录还没加载过，这里补一次。用 serverId 判定「从未附着」——
      // 只要用户已经开始浏览（哪怕某个空目录 items 为空），就不要把他弹回
      // 上次浏览位置。
      final files = ref.read(filesProvider);
      if (files.serverId.isEmpty && !files.loading) {
        try {
          await ref.read(filesProvider.notifier).attach();
        } catch (_) {
          // 目录打不开（源失联）不影响界面：文件页自己会显示错误条与重试。
        }
      }
    } finally {
      _working = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // 回到前台：先把会话补上（后台期间引擎可能被系统杀过 / 重启过），
    // 再让存储健康刷新一轮（3 秒合并）。
    unawaited(_establish());
    _health?.scheduleRefresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sidecarSub?.close();
    _retryTimer?.cancel();
    _retryTimer = null;
    _health?.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
