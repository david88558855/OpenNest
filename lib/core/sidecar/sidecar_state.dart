/// 内嵌引擎的钥匙串键名与状态模型。
library;

/// 引擎管理员口令（仅首次初始化使用，之后用于重新登录）。
const String kSidecarAdminKey = 'on:sidecar:admin';

/// 引擎访问令牌（登录成功后写入，冷启动优先复用）。
const String kSidecarTokenKey = 'on:sidecar:token';

/// 引擎管理员的固定口令。
///
/// 0.5.4 起不再随机生成 32 位口令，统一固定成 `admin`：启动流程直接用这个
/// 口令登录引擎，**没有口令输入、校验或跨版本迁移环节**。
///
/// 为什么可以接受：引擎只监听 `127.0.0.1`（见 `SidecarConfig.build` 的
/// `scheme.address`），本机之外连不上。代价是**同机其它进程**可以拿到
/// 管理员权限，这是固定口令的固有取舍。
const String kDefaultAdminPassword = 'admin';

/// 引擎单实例使用的固定端口（单实例唤醒通道，端口探测时必须避开）。
const int kSidecarReservedPort = 47661;

enum SidecarStatus { idle, starting, ready, failed, stopped }

class SidecarState {
  final SidecarStatus status;

  /// 引擎监听端口（仅回环）。
  final int? port;

  /// 访问令牌（裸令牌，请求头直接携带）。
  final String? token;

  /// 引擎版本串（来自站点信息，可为空）。
  final String? engineVersion;

  final int? pid;
  final String? error;
  final String? logPath;
  final String? binaryPath;

  /// 启动过程的当前步骤文案。
  final String? step;

  const SidecarState({
    this.status = SidecarStatus.idle,
    this.port,
    this.token,
    this.engineVersion,
    this.pid,
    this.error,
    this.logPath,
    this.binaryPath,
    this.step,
  });

  bool get isReady => status == SidecarStatus.ready;

  String get endpoint => port == null ? '' : '127.0.0.1:$port';

  SidecarState copyWith({
    SidecarStatus? status,
    int? port,
    String? token,
    String? engineVersion,
    int? pid,
    String? error,
    String? logPath,
    String? binaryPath,
    String? step,
    bool clearError = false,
    bool clearStep = false,
  }) {
    return SidecarState(
      status: status ?? this.status,
      port: port ?? this.port,
      token: token ?? this.token,
      engineVersion: engineVersion ?? this.engineVersion,
      pid: pid ?? this.pid,
      error: clearError ? null : (error ?? this.error),
      logPath: logPath ?? this.logPath,
      binaryPath: binaryPath ?? this.binaryPath,
      step: clearStep ? null : (step ?? this.step),
    );
  }
}
