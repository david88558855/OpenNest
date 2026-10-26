import 'dart:async';
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
    // 真正的最大化在 runApp 之后做（见 [_maximizeAfterFirstFrame]）。
    //
    // 这里不把「显示 + 最大化」放进 waitUntilReadyToShow 的回调：
    // 那个回调是同步调用、返回值不被 await，时序不可控。
    await windowManager.waitUntilReadyToShow(options);
    await windowManager.show();
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

  // 0.5.0：窗口默认以最大化状态打开。
  //
  // 必须放在 runApp 之后：window_manager 的 maximize 在 Windows 上是
  // `PostMessage(WM_SYSCOMMAND, SC_MAXIMIZE)` —— 异步投递到窗口消息队列，
  // 需要平台消息循环在跑才会被处理。runApp 之前调用，消息还在队列里没人
  // 处理，窗口会以普通尺寸显示（实测 1280×788、IsZoomed=False）。
  //
  // 等首帧 + 一小段延迟，确保原生窗口已经显示出来。
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    unawaited(_maximizeAfterFirstFrame());
  }
}

/// 首帧后把窗口最大化。
///
/// 幂等且带重试：maximize 是异步投递的，第一次可能因为窗口尚未真正显示
/// 而没生效，这里校验一次，没成就在短暂延迟后再试一次。
Future<void> _maximizeAfterFirstFrame() async {
  try {
    await WidgetsBinding.instance.endOfFrame;
  } catch (_) {
    // endOfFrame 不可用时直接继续。
  }
  for (var attempt = 0; attempt < 4; attempt++) {
    try {
      await windowManager.show();
      await windowManager.maximize();
      if (await windowManager.isMaximized()) return;
    } catch (_) {
      // 平台不支持 maximize（如 Linux 未实现该方法）时保持原状即可。
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 150));
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
