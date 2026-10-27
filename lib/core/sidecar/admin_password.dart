import '../api/openlist_api.dart';
import '../storage/secure_store.dart';
import 'sidecar_state.dart';

/// 口令统一的结果。
class AdminPasswordResult {
  /// 可用于后续请求的令牌（改口令后会换成新登录的令牌）。
  final String token;

  /// 当前生效的口令（通常是 [kDefaultAdminPassword]）。
  final String password;

  /// 本次是否真的把口令改成了默认值。
  final bool migrated;

  const AdminPasswordResult({
    required this.token,
    required this.password,
    this.migrated = false,
  });
}

/// 把引擎管理员口令统一成 [kDefaultAdminPassword]（默认 `admin`）。
///
/// 调用前提：已经用 [password] 成功登录，[token] 可用。
///
/// 老安装的引擎库里存的是 32 位随机口令（0.5.3 及以前），这里做一次性迁移：
/// 1. 口令已经是默认值 → 直接返回，零网络开销；
/// 2. 调 `/api/me/update` 改口令；
/// 3. **改库成功后立刻写钥匙串**，再用新口令重新登录换一个 token。
///    即使重新登录失败也必须落盘 —— 引擎库里的口令已经变了，钥匙串若还留着
///    旧口令，下次启动就会拿旧口令去登录一个已经换过口令的引擎，把自己锁死。
/// 4. 改库失败（接口不可用、被校验拒绝等）→ 保持原样，不写钥匙串、不换口令。
Future<AdminPasswordResult> ensureAdminPassword({
  required String baseUrl,
  required String token,
  required String password,
  required SecureStore secure,
}) async {
  if (password == kDefaultAdminPassword) {
    return AdminPasswordResult(token: token, password: password);
  }
  final api = OpenListApi(baseUrl: baseUrl, token: token);
  try {
    await api.updateCurrentUser(username: 'admin', password: kDefaultAdminPassword);
  } catch (_) {
    // 改不动就维持原口令：宁可还是随机口令，也不能让钥匙串和引擎库不一致。
    return AdminPasswordResult(token: token, password: password);
  }
  await secure.write(kSidecarAdminKey, kDefaultAdminPassword);
  try {
    final fresh = await api.login(username: 'admin', password: kDefaultAdminPassword);
    return AdminPasswordResult(
      token: fresh,
      password: kDefaultAdminPassword,
      migrated: true,
    );
  } catch (_) {
    // 口令已经改成功了，只是重新登录没成功：沿用旧 token（JWT 仍然有效）。
    return AdminPasswordResult(
      token: token,
      password: kDefaultAdminPassword,
      migrated: true,
    );
  }
}
