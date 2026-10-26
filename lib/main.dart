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
      // 默认窗口尺寸 1024×700。不做「启动即最大化」：用户可以自己
      // 最大化、缩放、拖拽调整大小，窗口状态完全由用户掌控。
      // 高度取 700 而不是 768，是为了在 1366×768 这类常见屏上
      // 放得下（去掉任务栏与标题栏后仍有富余），不会超出屏幕。
      size: Size(1024, 700),
      // 最小尺寸取 960×600：1366×768 与 1280×720 这类常见屏的工作区
      // 高度都不足 680，下限定太高会导致用户没法把窗口缩回可见范围。
      // 960 宽仍容得下侧栏（236）+ 主区（≥724）。
      minimumSize: Size(960, 600),
      center: true,
      title: 'OpenNest',
      titleBarStyle: TitleBarStyle.hidden,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
    );
    // 0.5.0：**不做窗口状态持久化** —— 不保存也不恢复窗口尺寸、位置与
    // 最大化状态，每次启动都用上面这组默认尺寸打开。窗口的大小与是否
    // 最大化完全由用户自己决定（标题栏按钮、双击标题栏、拖拽边缘）。
    //
    // 这里不把「显示」放进 waitUntilReadyToShow 的回调：那个回调是同步
    // 调用、返回值不被 await，时序不可控。
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

}

/// 全平台统一 edge-to-edge：内容自己画到状态栏/导航栏下方，再由 AppFrame 用
/// 安全区把内容让开。否则安卓 15+（targetSdk 36 强制 edge-to-edge）会出现
/// 内容压到状态栏、底部或多出一条系统底色带的问题。
Future<void> _configureSystemBars() async {
  if (!Platform.isAndroid) return;
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(olSystemBars);
}
