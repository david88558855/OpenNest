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
    await windowManager.waitUntilReadyToShow(options, () async {
      // 0.5.0：窗口默认以最大化状态打开，且**不做窗口状态持久化** ——
      // 不保存也不恢复窗口尺寸、位置与最大化状态，每次启动都是最大化。
      //
      // 先 maximize 再 show：waitUntilReadyToShow 的回调在窗口创建完成、
      // 尚未显示之前执行，这样不会先闪出一个小窗口再放大。
      await _maximizeWindow();
      await windowManager.show();
      await windowManager.focus();
      await windowManager.setPreventClose(true);
    });
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

/// 让窗口以最大化状态显示。
///
/// window_manager 的 `maximize` 只在 Windows / macOS 上实现，Linux 上
/// 会抛 MissingPluginException —— 那里退回「按屏幕尺寸铺满」的近似做法，
/// 保证任何桌面平台都不会因为这一步失败而启动不了。
Future<void> _maximizeWindow() async {
  try {
    await windowManager.maximize();
  } catch (_) {
    try {
      final size = await windowManager.getSize();
      await windowManager.setSize(Size(size.width * 1.6, size.height * 1.4));
    } catch (_) {
      // 连近似都失败就保持原尺寸，至少窗口能正常显示。
    }
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
