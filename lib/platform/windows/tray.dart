import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../../app/providers.dart';
import '../../core/sidecar/sidecar_controller.dart';
import '../../features/transfers/transfers_controller.dart';

/// W9 — Windows 托盘。
///
/// 交互约定（v1.0.16 按用户反馈修订）：
///   - 启动后常驻托盘图标（四态：空闲 / 传输中 / 失败 / 暂停）；
///   - 左键**单击不做任何响应**，左键**双击**才显示主界面；
///   - 右键菜单两项：显示主界面、退出；
///   - 双击与右键菜单「显示主界面」走同一个入口 [TrayService.revealFromTray]；
///   - 关闭窗口、Alt+F4、任务栏关闭一律只收进托盘，只有菜单「退出」结束进程。
///
/// 09 已知问题：
///   - K-01 图标资源必须是 .ico。tray_manager 在 Windows 上走
///     `LoadImage(..., IMAGE_ICON, ..., LR_LOADFROMFILE)`，PNG 会加载失败并
///     留下空白占位图标，四种状态全部不可见。
///   - K-02 退出必须单次、幂等、按序释放（prefs → 单实例锁 → NIM_DELETE →
///     exit），且托盘菜单回调不能被处理两次。
enum TrayIconState { idle, transferring, error, paused }

class TrayService with TrayListener {
  TrayService._();
  static final TrayService instance = TrayService._();

  ProviderContainer? _container;
  bool _ready = false;
  bool _quitting = false;
  bool _windowReady = false;
  bool _pendingShow = false;
  TrayIconState _state = TrayIconState.idle;
  ProviderSubscription<TransfersState>? _subscription;
  _OlWindowListener? _windowListener;
  Timer? _watchdog;

  /// 托盘左键最近一次按下的时间，用来识别双击。
  DateTime? _lastTrayDownAt;

  /// 双击判定窗口（Windows 默认双击间隔 500ms，取 450ms 略保守）。
  static const _doubleClickWindow = Duration(milliseconds: 450);

  bool get isQuitting => _quitting;

  Future<void> attach(ProviderContainer container) async {
    if (_ready) return;
    _container = container;
    trayManager.addListener(this);
    _windowListener = _OlWindowListener(this);
    windowManager.addListener(_windowListener!);
    await _applyIcon(TrayIconState.idle);
    await _rebuildMenu();
    _subscription = container.listen<TransfersState>(transfersProvider, (previous, next) {
      final state = _deriveState(next);
      if (state != _state) {
        _applyIcon(state);
      } else {
        // 只更新提示文字。菜单内容固定（显示 / 退出），
        // 之前这里每次都 setContextMenu，菜单弹出期间被替换掉，
        // 点击就落空——表现为「右键菜单点了没反应」「退出要点好几次」。
        unawaited(_applyTooltip(state));
      }
    });
    _ready = true;
    _startWatchdog();
  }

  /// Explorer 重启后任务栏重建，`Shell_NotifyIcon` 注册的图标会被清掉，
  /// 而 tray_manager 0.2.x 不监听 `TaskbarCreated`（插件里没有这段代码），
  /// 图标就永久消失、右键菜单也弹不出来（v2.3 修复 P2-16）。
  ///
  /// 兜底做法：每 25s 查一次图标在通知区域的矩形。拿不到（或被
  /// `getBounds` 返回 0 尺寸）说明注册已失效，于是 `destroy()` 把插件的
  /// `tray_icon_setted` 复位，再 `setIcon` 走一次 `NIM_ADD` 重新挂上。
  void _startWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer.periodic(const Duration(seconds: 25), (_) => _ensureIconAlive());
  }

  Future<void> _ensureIconAlive() async {
    if (!_ready || _quitting) return;
    var alive = false;
    try {
      final bounds = await trayManager.getBounds();
      // 图标真的在通知区域时宽高必然大于 0；Explorer 重启后这里会是 0 或 null。
      alive = bounds != null && bounds.width > 0 && bounds.height > 0;
    } catch (_) {
      alive = false;
    }
    if (alive) return;
    debugPrint('tray: icon missing (Explorer restarted?), re-adding');
    await _recreateIcon();
  }

  /// 重新注册托盘图标与菜单（NIM_DELETE → NIM_ADD）。
  Future<void> _recreateIcon() async {
    try {
      await trayManager.destroy();
    } catch (_) {}
    await _applyIcon(_state);
    await _rebuildMenu();
  }

  Future<void> dispose() async {
    _watchdog?.cancel();
    _watchdog = null;
    _subscription?.close();
    _subscription = null;
    if (_windowListener != null) {
      windowManager.removeListener(_windowListener!);
      _windowListener = null;
    }
    trayManager.removeListener(this);
    _ready = false;
    _windowReady = false;
  }

  TrayIconState _deriveState(TransfersState state) {
    // 运行中优先：否则一个历史失败任务会让图标永远停在「失败」态。
    if (state.active.isNotEmpty) return TrayIconState.transferring;
    if (state.failed.isNotEmpty) return TrayIconState.error;
    if (state.paused.isNotEmpty) return TrayIconState.paused;
    return TrayIconState.idle;
  }

  /// Windows 通知区域只认 ICO/BMP；PNG 会得到 NULL HICON（K-01 根因）。
  String _iconAsset(TrayIconState state) {
    final ext = Platform.isWindows ? 'ico' : 'png';
    return 'assets/tray/tray_${state.name}.$ext';
  }

  Future<void> _applyIcon(TrayIconState state) async {
    _state = state;
    // 图标在主 isolate ready 之后创建；失败重试，避免 Explorer 尚未就绪时
    // 留下空白占位（K-01 修复方向 ②）。
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await trayManager.setIcon(_iconAsset(state));
        await trayManager.setToolTip(_tooltip(state));
        return;
      } catch (error) {
        if (attempt >= 2) {
          debugPrint('tray: setIcon failed ($error)');
          return;
        }
        await Future<void>.delayed(Duration(milliseconds: 120 * (attempt + 1)));
      }
    }
  }

  Future<void> _applyTooltip(TrayIconState state) async {
    try {
      await trayManager.setToolTip(_tooltip(state));
    } catch (_) {
      // 托盘不可用时忽略
    }
  }

  String _tooltip(TrayIconState state) {    final transfers = _container?.read(transfersProvider);
    switch (state) {
      case TrayIconState.transferring:
        return 'OpenNest · 传输中 ${transfers?.active.length ?? 0}';
      case TrayIconState.error:
        return 'OpenNest · ${transfers?.failed.length ?? 0} 个任务失败';
      case TrayIconState.paused:
        return 'OpenNest · 已暂停';
      case TrayIconState.idle:
        return 'OpenNest';
    }
  }

  /// 只有两项：显示主界面 / 退出。菜单只在 attach / 重建图标时设置一次。
  ///
  /// 动作不挂在 MenuItem.onClick 上：tray_manager 的 Windows 实现会在
  /// `_methodCallHandler` 里调用一次 onClick，同时又回调 [onTrayMenuItemClick]，
  /// 双通道容易互相打架（v2.1 就出现过「退出执行两遍」）。现在统一由
  /// [onTrayMenuItemClick] 按 key 分发，MenuItem 只带 key。
  Future<void> _rebuildMenu() async {
    final menu = Menu(
      items: [
        MenuItem(key: 'show', label: '显示主界面'),
        MenuItem.separator(),
        MenuItem(key: 'quit', label: '退出'),
      ],
    );
    try {
      await trayManager.setContextMenu(menu);
    } catch (_) {
      // 托盘不可用时忽略，主窗口行为不受影响
    }
  }

  /// 托盘唤出主界面的**唯一入口**。
  ///
  /// 左键双击、右键菜单「显示主界面」、第二个进程的激活请求，全部走这里，
  /// 保证三者的恢复顺序（show → restore → 置顶 → 聚焦）完全一致。
  Future<void> revealFromTray() => showMainWindow();

  /// 主实例就绪前收到的「显示」请求先暂存，等托盘/窗口 ready 后再执行。
  void requestShow() {
    if (!_windowReady) {
      _pendingShow = true;
      return;
    }
    revealFromTray();
  }

  void markWindowReady() {
    _windowReady = true;
    if (_pendingShow) {
      _pendingShow = false;
      revealFromTray();
    }
  }

  /// 把主窗口唤到前台（v2.1 修复：托盘「显示主界面」无响应）。
  ///
  /// 从托盘唤回时窗口可能处于 隐藏 / 最小化 / 被其他窗口遮挡 三种状态，
  /// 单独 show() 在 Windows 前台锁下不会真正置前，因此按序恢复、置顶再取消。
  Future<void> showMainWindow() async {
    if (_quitting) return;
    try {
      // 0.5.0：不做「唤起即最大化」—— 窗口的大小与是否最大化完全由
      // 用户决定（标题栏按钮、双击标题栏、拖拽边缘）。重复启动（再次
      // 双击 / 命令行再次启动）走这条唤醒路径，也只把窗口唤回前台，
      // 不改变它的尺寸。
      if (!await windowManager.isVisible()) await windowManager.show();
      if (await windowManager.isMinimized()) await windowManager.restore();
      await windowManager.setSkipTaskbar(false);
      await windowManager.show();
      await windowManager.focus();
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setAlwaysOnTop(false);
      await windowManager.focus();
    } catch (error) {
      debugPrint('tray: showMainWindow failed ($error)');
    }
  }

  /// 唯一退出入口：幂等、单次执行（K-02）。
  ///
  /// v2.6：清理改为并行 + 总超时 1.2s。之前四步串行、每步各自超时，
  /// 最坏要等近 3 秒才 exit，用户以为「点了没退出」于是反复点菜单。
  Future<void> _quit() async {
    if (_quitting) return;
    _quitting = true;
    _watchdog?.cancel();
    _watchdog = null;

    // 1. 断开数据订阅，避免退出过程中还有 UI 回调（close() 是同步 void）
    try {
      _subscription?.close();
      _subscription = null;
    } catch (_) {}

    // 2~5 并行：偏好落盘 / 停引擎 / 关闭窗口拦截 / 移除托盘图标（NIM_DELETE）
    final cleanup = <Future<void>>[
      _ignore(() {
        final container = _container;
        if (container == null) return Future<void>.value();
        return container.read(prefsProvider).flush();
      }),
      // 引擎是本进程的子进程：不主动停会留下孤儿，下次冷启动抢同一份数据库。
      _ignore(() {
        final container = _container;
        if (container == null) return Future<void>.value();
        return container.read(sidecarProvider.notifier).stop();
      }),
      _ignore(() => windowManager.setPreventClose(false)),
      _ignore(() => trayManager.destroy()),
    ];
    try {
      await Future.wait(cleanup).timeout(const Duration(milliseconds: 1200));
    } catch (_) {
      // 超时也继续：退出比清理完整更重要
    }

    // 5. 释放窗口，最后进程退出
    await _ignore(() => windowManager.destroy());
    exit(0);
  }

  /// 清理步骤一律不抛异常、不阻塞退出。
  Future<void> _ignore(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {}
  }

  @override
  void onTrayIconMouseDown() {
    // v1.0.16：左键单击不做任何响应，只有双击才唤出主界面。
    // tray_manager 在 Windows 上把单击与双击都送成 mouseDown，
    // 所以这里用时间差自行识别双击，并「消费」掉第二次按下避免三击重复触发。
    final now = DateTime.now();
    final last = _lastTrayDownAt;
    if (last != null && now.difference(last) <= _doubleClickWindow) {
      _lastTrayDownAt = null;
      revealFromTray();
      return;
    }
    _lastTrayDownAt = now;
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    // 唯一的动作入口：按 key 分发，靠 _quitting / showMainWindow 的幂等性
    // 保证即使插件同时触发 onClick 也只执行一次。
    switch (menuItem.key) {
      case 'show':
        // 与左键双击同一入口
        revealFromTray();
        break;
      case 'quit':
        _quit();
        break;
      default:
        break;
    }
  }
}

/// Small bridge so tray menu entries can drive the router.
final trayNavigateProvider = StateProvider<String?>((ref) => null);

/// 关闭窗口一律收进托盘；只有托盘菜单「退出」会结束进程。
class _OlWindowListener extends WindowListener {
  final TrayService service;
  _OlWindowListener(this.service);

  @override
  void onWindowClose() async {
    if (service.isQuitting) return;
    await windowManager.hide();
  }
}
