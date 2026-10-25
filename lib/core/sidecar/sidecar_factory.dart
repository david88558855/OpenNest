import 'dart:io';

import '../../platform/android/sidecar_bridge.dart';
import '../storage/secure_store.dart';
import 'sidecar_manager.dart';

/// 按平台选择实现：桌面用子进程，移动端走原生桥。
SidecarManager createSidecarManager(SecureStore secure, {void Function()? onExit}) {
  if (Platform.isAndroid) return AndroidSidecarManager(secure);
  return DesktopSidecarManager(secure, onExit: onExit);
}
