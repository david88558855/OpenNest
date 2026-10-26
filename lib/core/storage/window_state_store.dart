import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import '../storage/prefs.dart';

/// 桌面端窗口状态：普通窗口尺寸 + 上次是否为最大化。
///
/// 只在桌面平台有意义，移动端没有窗口概念。
class WindowState {
  /// 上次退出时的普通窗口尺寸（未最大化时的尺寸）。
  final Size size;

  /// 上次退出时是否处于最大化状态。
  final bool maximized;

  const WindowState({required this.size, required this.maximized});
}

/// 窗口状态的持久化。
///
/// 0.5.0 之前应用没有保存过窗口状态，每次启动都是固定的 1440×900。
/// 现在按需求改成：首次启动最大化，之后按上次保存的尺寸打开。
///
/// **最大化与尺寸持久化的优先级**：
/// - 最大化时**不**覆盖已保存的普通尺寸 —— 最大化后的尺寸等于屏幕分辨率，
///   把它当成用户偏好存下来，下次启动就会得到一个「莫名其妙很大」的窗口；
/// - 最大化状态单独用一个标记记录，下次启动据此恢复；
/// - 用户拖拽调整窗口（未最大化）时才更新保存的尺寸。
///
/// 放在 `core/storage` 而不是 `platform/windows`，是为了让 Linux / macOS
/// 也能复用同一套逻辑（它们同样走 window_manager）。
class WindowStateStore {
  const WindowStateStore._();

  static const _keyWidth = 'window.width';
  static const _keyHeight = 'window.height';
  static const _keyMaximized = 'window.maximized';

  /// 首次启动时的默认尺寸（仅在还没有任何记录时用作回退）。
  static const Size defaultSize = Size(1440, 900);

  /// 窗口最小尺寸，与启动时的 `minimumSize` 保持一致。
  static const Size minimumSize = Size(1024, 680);

  /// 读取上次保存的窗口状态。
  ///
  /// 返回 null 表示「首次启动」—— 没有任何记录。
  static WindowState? read(Prefs prefs) {
    final width = prefs.getInt(_keyWidth);
    final height = prefs.getInt(_keyHeight);
    if (width <= 0 || height <= 0) return null;
    // 兜底：分辨率变小或显示器被拔掉后，保存的尺寸可能超出当前屏幕，
    // 这时退回默认尺寸，别让窗口开在屏幕外。
    final size = Size(width.toDouble(), height.toDouble());
    if (size.width < minimumSize.width || size.height < minimumSize.height) {
      return null;
    }
    return WindowState(
      size: size,
      maximized: prefs.getBool(_keyMaximized),
    );
  }

  /// 保存普通窗口尺寸（不改动最大化标记）。
  static Future<void> saveSize(Prefs prefs, Size size) async {
    await prefs.setInt(_keyWidth, size.width.round());
    await prefs.setInt(_keyHeight, size.height.round());
  }

  /// 只记录最大化状态。
  static Future<void> saveMaximized(Prefs prefs, bool maximized) async {
    await prefs.setBool(_keyMaximized, maximized);
  }

  /// 启动时用的窗口选项。
  ///
  /// - 首次启动（无记录）：用默认尺寸创建，随后立即最大化；
  /// - 之后启动：用上次保存的尺寸创建；上次是最大化则随后最大化。
  static WindowOptions buildOptions(WindowState? state) {
    return WindowOptions(
      size: state?.size ?? defaultSize,
      minimumSize: minimumSize,
      // 有历史尺寸时不再强制居中 —— 沿用系统记录的窗口位置更自然。
      // 首次启动用默认尺寸居中，随后会被最大化覆盖。
      center: state == null,
      title: 'OpenNest',
      titleBarStyle: TitleBarStyle.hidden,
      backgroundColor: const Color(0x00000000),
      skipTaskbar: false,
    );
  }

  /// 是否需要在显示后最大化。
  ///
  /// 首次启动（无记录）→ 最大化；之后按上次的状态。
  static bool shouldMaximize(WindowState? state) =>
      state == null || state.maximized;

  /// 立即捕获当前窗口状态并写入偏好。
  ///
  /// 退出流程会在 flush 之前调用它：窗口尺寸的常规写入是异步的
  /// （监听 → setInt → 250ms 合并落库），如果用户「刚调完窗口就退出」，
  /// flush 可能先跑完，尺寸就丢了。这里先同步写进 dirty 集合，
  /// 随后的 flush 就能带上。
  static Future<void> captureNow(Prefs prefs) async {
    try {
      final maximized = await windowManager.isMaximized();
      await saveMaximized(prefs, maximized);
      // 最大化状态下不覆盖已保存的普通尺寸（见类注释的优先级说明）。
      if (!maximized) {
        final size = await windowManager.getSize();
        await saveSize(prefs, size);
      }
    } catch (_) {
      // 窗口可能已经被销毁，读不到尺寸不影响退出。
    }
  }

  /// 监听窗口变化并持久化。
  ///
  /// 必须在窗口显示之后调用。
  static void attach(Prefs prefs) {
    windowManager.addListener(_WindowStateListener(prefs));
  }
}

class _WindowStateListener extends WindowListener {
  _WindowStateListener(this._prefs);

  final Prefs _prefs;

  /// 正在自己写盘时忽略回调，避免「保存 → 触发 resize → 再保存」的死循环。
  bool _writing = false;

  @override
  void onWindowResize() {
    _scheduleSize();
  }

  @override
  void onWindowMaximize() {
    // 只记标记，不覆盖普通尺寸。
    _write(() => WindowStateStore.saveMaximized(_prefs, true));
  }

  @override
  void onWindowUnmaximize() {
    _write(() => WindowStateStore.saveMaximized(_prefs, false));
    // 从最大化还原回来时，窗口尺寸才是用户真正看到的那个 —— 记下来。
    _scheduleSize();
  }

  void _scheduleSize() {
    if (_writing) return;
    _writing = true;
    Future<void>(() async {
      try {
        // 最大化状态下不更新保存的普通尺寸（见类注释的优先级说明）。
        if (!await windowManager.isMaximized()) {
          final size = await windowManager.getSize();
          await WindowStateStore.saveSize(_prefs, size);
        }
      } catch (_) {
        // 读窗口尺寸失败不影响主流程。
      } finally {
        _writing = false;
      }
    });
  }

  void _write(Future<void> Function() action) {
    if (_writing) return;
    _writing = true;
    action()
        .catchError((_) {})
        .whenComplete(() => _writing = false);
  }
}

/// 只有桌面平台才有窗口。移动端调用这些函数是空操作。
bool get supportsWindowState =>
    Platform.isWindows || Platform.isLinux || Platform.isMacOS;
