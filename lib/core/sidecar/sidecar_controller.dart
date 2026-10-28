import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/secure_store.dart';
import 'engine_store.dart';
import 'sidecar_factory.dart';
import 'sidecar_manager.dart';
import 'sidecar_paths.dart';
import 'sidecar_state.dart';

final sidecarProvider = StateNotifierProvider<SidecarNotifier, SidecarState>((ref) {
  final notifier = SidecarNotifier();
  ref.onDispose(notifier.disposeSidecar);
  return notifier;
});

/// 安全模式启动的结果。
class SafeModeResult {
  /// null 表示引擎已经起来；否则是可展示的错误文案。
  final String? error;

  /// 本次被停用的存储源条数。
  final int disabled;

  const SafeModeResult({this.error, this.disabled = 0});

  bool get ok => error == null;
}

/// 引擎生命周期：启动、重启、停止、崩溃兜底。
class SidecarNotifier extends StateNotifier<SidecarState> {
  SidecarNotifier() : super(const SidecarState());

  final SecureStore _secure = SecureStore();
  SidecarManager? _manager;
  bool _autoRestarted = false;
  bool _stopping = false;

  /// 进行中的「存储源启用 / 停用」操作数。
  ///
  /// 这类操作会让引擎当场 `LoadStorage` —— 如果该源驱动在加载时崩掉，
  /// 引擎进程会直接死。此时**不要**自动重启：先让调用方把肇事记录改回
  /// 停用，否则重启必然在同一处再崩一次，用户就被锁死在「启动即崩」。
  int _storageOps = 0;

  bool get storageOpInFlight => _storageOps > 0;

  void beginStorageOp() => _storageOps++;

  void endStorageOp() {
    if (_storageOps > 0) _storageOps--;
  }

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
      // 启动成功就复位自动重启闸门：否则本进程内只会在第一次崩溃时自愈一次。
      _autoRestarted = false;
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

  /// 读取当前内核实例配置的管理员口令（明文）。
  ///
  /// 0.5.4：口令已固定为 [kDefaultAdminPassword]（`admin`），启动时直接用它
  /// 登录引擎，**没有任何口令输入、校验或迁移环节**。这里读到的就是
  /// 「当前实例实际使用的口令」—— 用户偶尔需要它去手工调用引擎管理接口。
  ///
  /// 返回 null 表示钥匙串里没有这一条目（例如换了机器或清过钥匙串；
  /// 下次启动会补写为默认口令）。
  Future<String?> readAdminPassword() async {
    final value = await _secure.read(kSidecarAdminKey);
    if (value == null || value.isEmpty) return null;
    return value;
  }

  Future<void> restart() => start(restart: true);

  Future<void> stop() async {
    _stopping = true;
    try {
      await _managerOrCreate.stop();
    } catch (_) {}
    if (!mounted) return;
    // 端点与令牌一起清空：否则设置页仍显示旧端口，会话层也可能拿旧令牌重试。
    state = state.copyWith(
      status: SidecarStatus.stopped,
      clearStep: true,
      clearPort: true,
      clearToken: true,
    );
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
      // 进程已经没了：端口即失效，清掉免得界面继续显示一个连不上的端点。
      clearPort: true,
      error: '引擎进程已退出。如果刚启用过某个存储源，多半是该源的驱动在这台机器上崩溃 —— '
          '重启时可在启动页用「安全模式启动」先把它们全部停用。',
      clearStep: true,
    );
    // 崩溃自动重启一次；再失败就停在错误态，交给用户手动重试。
    // 存储源操作进行中不自动重启：等调用方把肇事那条改回停用再说。
    if (!_autoRestarted && !storageOpInFlight) {
      _autoRestarted = true;
      start(restart: true);
    }
  }

  /// 安全模式：停用引擎库里**全部**存储源，然后再启动引擎。
  ///
  /// 适用场景：某个存储源的驱动在加载时把引擎打崩，导致每次启动都失败、
  /// 连界面都进不去。停用后引擎能干净起来，用户进「设置 → 存储源」逐个
  /// 启用即可定位具体是哪一个（启用失败时会被自动改回停用，见
  /// `SourceActions.toggle`）。
  ///
  /// 改库之前会先把 `data.db` 备份成 `data.db.bak-<时间戳>`。
  Future<SafeModeResult> startInSafeMode() async {
    int count = 0;
    try {
      // 先确保引擎没在跑：与引擎争写同一份 SQLite 是唯一会写坏数据的路径。
      await stop();
      final store = await EngineStore.open();
      count = await store.disableAll();
    } catch (error) {
      return SafeModeResult(error: '安全模式不可用：$error', disabled: count);
    }
    _autoRestarted = false;
    await start(restart: true);
    if (state.status != SidecarStatus.ready) {
      return SafeModeResult(error: state.error ?? '引擎仍未启动', disabled: count);
    }
    return SafeModeResult(disabled: count);
  }

  /// 把一个存储源在引擎库里改回「停用」（引擎必须已退出）。
  ///
  /// 用于「启用它 → 引擎当场崩溃」之后的补救：库里那条记录此时是
  /// `disabled = 0`，不纠正的话下次启动会再次被打崩。
  Future<bool> quarantine(int id) async {
    try {
      // 0.5.9：改库前先确认引擎进程已经退出。刚崩的进程可能还在收尾，
      // 这时写它的 data.db 会与引擎争写同一份 SQLite。
      final pidFile = await SidecarPaths.pid();
      if (await pidFile.exists()) {
        final pid = int.tryParse((await pidFile.readAsString()).trim());
        if (pid != null) {
          await SidecarManager.waitProcessGone(pid);
        }
      }
      final store = await EngineStore.open();
      return await store.setDisabled(id, true);
    } catch (_) {
      return false;
    }
  }

  Future<void> disposeSidecar() async {
    if (_stopping) return;
    try {
      await _manager?.stop();
    } catch (_) {}
  }
}
