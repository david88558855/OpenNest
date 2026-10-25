import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/secure_store.dart';
import 'sidecar_manager.dart';
import 'sidecar_paths.dart';
import 'sidecar_state.dart';

final sidecarProvider = StateNotifierProvider<SidecarNotifier, SidecarState>((ref) {
  final notifier = SidecarNotifier();
  ref.onDispose(notifier.disposeSidecar);
  return notifier;
});

/// 引擎生命周期：启动、重启、停止、崩溃兜底。
class SidecarNotifier extends StateNotifier<SidecarState> {
  SidecarNotifier() : super(const SidecarState());

  final SecureStore _secure = SecureStore();
  SidecarManager? _manager;
  bool _autoRestarted = false;
  bool _stopping = false;

  SidecarManager get _managerOrCreate =>
      _manager ??= createSidecarManager(_secure, onExit: _onEngineExit);

  Future<void> start({bool restart = false}) async {
    if (state.status == SidecarStatus.starting) return;
    _stopping = false;
    state = state.copyWith(
      status: SidecarStatus.starting,
      clearError: true,
      step: restart ? '正在重启引擎' : '正在准备引擎',
    );
    try {
      if (restart) {
        await _managerOrCreate.stop();
      }
      final launch = await _managerOrCreate.start(onStep: (step) {
        if (!mounted) return;
        state = state.copyWith(status: SidecarStatus.starting, step: step);
      });
      if (!mounted) return;
      state = SidecarState(
        status: SidecarStatus.ready,
        port: launch.port,
        token: launch.token,
        engineVersion: launch.version,
        pid: launch.pid,
        logPath: launch.logPath,
        binaryPath: launch.binaryPath,
      );
    } on SidecarException catch (error) {
      if (!mounted) return;
      final tail = await SidecarPaths.tailLog();
      state = state.copyWith(
        status: SidecarStatus.failed,
        error: tail.isEmpty ? error.message : '${error.message}\n\n—— 引擎日志 ——\n$tail',
        logPath: error.logPath ?? state.logPath,
        clearStep: true,
      );
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(
        status: SidecarStatus.failed,
        error: '引擎启动异常：$error',
        clearStep: true,
      );
    }
  }

  Future<void> restart() => start(restart: true);

  Future<void> stop() async {
    _stopping = true;
    try {
      await _managerOrCreate.stop();
    } catch (_) {}
    if (!mounted) return;
    state = state.copyWith(status: SidecarStatus.stopped, clearStep: true);
  }

  /// 令牌失效时重新登录（口令仍在本机钥匙串里）。
  Future<String?> refreshToken() async {
    try {
      final launch = await _managerOrCreate.relogin();
      if (mounted) {
        state = state.copyWith(status: SidecarStatus.ready, token: launch.token, port: launch.port);
      }
      return launch.token;
    } catch (error) {
      if (mounted) {
        state = state.copyWith(status: SidecarStatus.failed, error: '$error');
      }
      return null;
    }
  }

  void _onEngineExit() {
    if (!mounted || _stopping) return;
    state = state.copyWith(
      status: SidecarStatus.failed,
      error: '引擎进程已退出。',
      clearStep: true,
    );
    // 崩溃自动重启一次；再失败就停在错误态，交给用户手动重试。
    if (!_autoRestarted) {
      _autoRestarted = true;
      start(restart: true);
    }
  }

  Future<void> disposeSidecar() async {
    if (_stopping) return;
    try {
      await _manager?.stop();
    } catch (_) {}
  }
}
