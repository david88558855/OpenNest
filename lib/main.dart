import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'core/storage/prefs.dart';
import 'core/theme/theme.dart';
import 'platform/windows/single_instance.dart';
import 'platform/windows/tray.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await _configureSystemBars();

  final prefs = await Prefs.load();
  final container =
      ProviderContainer(overrides: [prefsProvider.overrideWithValue(prefs)]);

  if (Platform.isWindows) {
    // 单实例：锁文件已被占用就说明已有实例（哪怕它缩在托盘里、或者唤醒包没送达），
    // 本进程一律退出，绝不创建第二个窗口。v1.0.16 之前只有「ping 有应答」才退出，
    // 端口被占用或冷启动竞态时会重复拉起新实例。
    final primary = await SingleInstance.becomePrimary(
      onActivate: TrayService.instance.requestShow,
    );
    if (!primary) {
      await SingleInstance.activateExisting();
      exit(0);
    }
  }

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      // 初始尺寸只是「窗口创建瞬间」的占位：下面紧接着就 maximize，
      // 不会真的以这个尺寸显示。取值保守一些，避免在小分辨率屏上
      // （如 1366×768）创建瞬间超出屏幕边缘。
      size: Size(1280, 800),
      // 最小尺寸取 960×600：1366×768 与 1280×720 这类常见屏的工作区
      // 高度都不足 680，下限定太高会导致用户取消最大化后没法把窗口
      // 缩回可见范围。960 宽仍容得下侧栏（236）+ 主区（≥724）。
      minimumSize: Size(960, 600),
      center: true,
      title: 'OpenNest',
      titleBarStyle: TitleBarStyle.hidden,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
    );
    // 0.5.0：窗口默认以最大化状态打开，且**不做窗口状态持久化** ——
    // 不保存也不恢复窗口尺寸、位置与最大化状态，每次启动都是最大化。
    //
    // 顺序很关键：**先 show 再 maximize**。
    // Windows 上第一次 ShowWindow 会忽略调用参数（改用启动时的
    // nCmdShow），对尚未显示的窗口调 maximize 是无效的 —— 实测
    // 先 maximize 会得到一个 1280×788 的普通窗口（IsZoomed=False），
    // 先 show 再 maximize 才真正铺满工作区。
    //
    // window_manager 的 waitUntilReadyToShow 会同步调用回调、且不等待
    // 回调的返回值，所以这里不把「显示 + 最大化」放进回调 —— 改成在
    // 它返回之后显式 await，时序完全可控，也只执行一次。
    await windowManager.waitUntilReadyToShow(options);
    await _showMaximized();
    await windowManager.setPreventClose(true);
    if (Platform.isWindows) {
      await TrayService.instance.attach(container);
      TrayService.instance.markWindowReady();
    }
  }

  // 引擎启动与首次会话放在启动页里跑：先出画面，避免冷启动白窗。
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const OpenNestApp(),
    ),
  );
}

/// 显示窗口并立即最大化。
///
/// 幂等：重复调用只会把窗口重新显示并置为最大化，不会叠加副作用。
Future<void> _showMaximized() async {
  try {
    await windowManager.show();
    await windowManager.focus();
    // 首次 ShowWindow 之后，maximize 才对窗口生效。
    await windowManager.maximize();
  } catch (_) {
    // 某些平台/驱动不支持 maximize（例如 Linux 上该方法未实现），
    // 至少保证窗口能正常显示，不让应用卡在启动阶段。
  }
}

/// 全平台统一 edge-to-edge：内容自己画到状态栏/导航栏下方，再由 AppFrame 用
/// 安全区把内容让开。否则安卓 15+（targetSdk 36 强制 edge-to-edge）会出现
/// 内容压到状态栏、底部或多出一条系统底色带的问题。
Future<void> _configureSystemBars() async {
  if (!Platform.isAndroid) return;
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(olSystemBars);
}
