import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/openlist_api.dart';
import '../../core/models/api_types.dart';
import '../../core/models/server_profile.dart';
import '../../core/storage/secure_store.dart';

class SessionState {
  final ServerProfile? profile;
  final UserInfo? user;
  final SiteInfo? site;
  final OpenListApi? api;
  final bool connecting;
  final bool signedIn;

  /// 冷启动时网络不可达：凭据仍在，允许进入只读离线态（v2.3）。
  final bool offline;
  final String? error;
  final int? latencyMs;

  const SessionState({
    this.profile,
    this.user,
    this.site,
    this.api,
    this.connecting = false,
    this.signedIn = false,
    this.offline = false,
    this.error,
    this.latencyMs,
  });

  SessionState copyWith({
    ServerProfile? profile,
    UserInfo? user,
    SiteInfo? site,
    OpenListApi? api,
    bool? connecting,
    bool? signedIn,
    bool? offline,
    String? error,
    int? latencyMs,
  }) =>
      SessionState(
        profile: profile ?? this.profile,
        user: user ?? this.user,
        site: site ?? this.site,
        api: api ?? this.api,
        connecting: connecting ?? this.connecting,
        signedIn: signedIn ?? this.signedIn,
        offline: offline ?? this.offline,
        error: error,
        latencyMs: latencyMs ?? this.latencyMs,
      );
}

class ProbeResult {
  final bool ok;
  final SiteInfo? site;
  final int latencyMs;
  final String? error;

  const ProbeResult({required this.ok, this.site, this.latencyMs = 0, this.error});
}

class SessionNotifier extends StateNotifier<SessionState> {
  final Ref ref;
  final SecureStore _secure;

  SessionNotifier(this.ref)
      : _secure = ref.read(secureStoreProvider),
        super(const SessionState());

  Future<ProbeResult> probe(String rawUrl) async {
    final urlError = validateBaseUrl(rawUrl);
    if (urlError != null) return ProbeResult(ok: false, error: urlError);
    final api = OpenListApi(baseUrl: normalizeBaseUrl(rawUrl));
    final watch = Stopwatch()..start();
    try {
      final site = await api.publicSettings();
      watch.stop();
      return ProbeResult(ok: true, site: site, latencyMs: watch.elapsedMilliseconds);
    } on ApiException catch (e) {
      watch.stop();
      return ProbeResult(ok: false, error: e.friendly, latencyMs: watch.elapsedMilliseconds);
    }
  }

  /// Restores the last active server from the keychain on cold start.
  Future<void> boot() async {
    final list = ref.read(serverListProvider);
    final profile = list.active;
    if (profile == null) {
      state = const SessionState();
      return;
    }
    final token = await _secure.read(profile.tokenKey);
    if (token == null || token.isEmpty) {
      state = SessionState(profile: profile);
      return;
    }
    final api = OpenListApi(baseUrl: profile.baseUrl, token: token);
    state = SessionState(profile: profile, api: api, connecting: true);
    final watch = Stopwatch()..start();
    try {
      // v1.0.44：两个请求并行，省掉一个 RTT。
      // 但错误语义要分开：`me()` 决定成败（401/403 才算登出），
      // `publicSettings()` 只是站点信息，失败不应影响登录 —— 单独吞掉。
      // 注意不能直接用 Future.wait：它会把异常包成 ParallelWaitError，
      // 下面的 `on ApiException` 就捕获不到，会被误判成「离线模式」。
      final meFuture = api.me();
      final siteFuture = api.publicSettings().then<SiteInfo?>((s) => s).catchError((Object _) => null);
      final user = await meFuture;
      final site = await siteFuture;
      watch.stop();
      state = SessionState(
        profile: profile,
        user: user,
        site: site,
        api: api,
        signedIn: true,
        latencyMs: watch.elapsedMilliseconds,
      );
      await ref.read(serverListProvider.notifier).touch(
            profile.id,
            latencyMs: watch.elapsedMilliseconds,
            health: ServerHealth.ok,
            siteTitle: site?.title,
            version: site?.version ?? site?.apiVersion,
          );
      ref.read(appSettingsProvider.notifier).rememberLatency(watch.elapsedMilliseconds);
    } on ApiException catch (e) {
      watch.stop();
      if (e.needsReauth) {
        // 只有明确的 401/403 才算登出；其余一律保留凭据。
        await _secure.delete(profile.tokenKey);
        state = SessionState(profile: profile, error: '登录已失效，请重新连接');
      } else {
        // v2.3：网络 / 超时 / DNS / 5xx 不再把用户踢回登录页。
        // 凭据还在，进入只读离线态：目录列表走本地缓存，写操作由各自的
        // 错误提示兜底，顶部黄色条提示「离线模式」。
        state = SessionState(
          profile: profile,
          api: api,
          signedIn: true,
          offline: true,
          error: e.friendly,
          connecting: false,
        );
      }
    } catch (_) {
      // 非 ApiException（例如 TLS 握手失败、SocketException 包装异常）
      watch.stop();
      state = SessionState(
        profile: profile,
        api: api,
        signedIn: true,
        offline: true,
        error: '网络不可用，已进入离线模式',
        connecting: false,
      );
    }
  }

  /// Password / token login. Returns an inline error message, or null on success.
  Future<String?> connect({
    required AuthMode mode,
    required String baseUrl,
    required String username,
    required String secret,
    String otp = '',
    String displayName = '',
    String? existingId,
    bool persistToken = true,
  }) async {
    final urlError = validateBaseUrl(baseUrl);
    if (urlError != null) return urlError;
    final base = normalizeBaseUrl(baseUrl);
    if (mode == AuthMode.password && username.trim().isEmpty) return '请填写用户名';
    if (secret.isEmpty) return mode == AuthMode.token ? '请填写 API Token' : '请填写密码';

    state = state.copyWith(connecting: true, error: null);
    final api = OpenListApi(baseUrl: base);
    try {
      final site = await api.publicSettings();
      String token;
      if (mode == AuthMode.token) {
        token = secret.trim();
        api.token = token;
      } else {
        token = await api.login(username: username.trim(), password: secret, otpCode: otp);
      }
      final user = await api.me();
      // v1.0.18：显示名称唯一，地址允许重复（同一实例可存多条不同账号/备注）。
      // 名称留空时最终会用站点标题，所以这里用「最终名称」再判一次，
      // 避免绕过表单层的校验。
      final finalName = displayName.trim().isEmpty ? site.title : displayName.trim();
      final duplicated = ref.read(serverListProvider).servers.any(
            (s) => s.id != existingId && s.name.trim() == finalName.trim(),
          );
      if (duplicated) {
        state = state.copyWith(connecting: false, error: '该显示名称已存在');
        return '该显示名称已存在';
      }
      final profile = ServerProfile(
        id: existingId ?? newServerId(),
        name: finalName,
        baseUrl: base,
        username: username.trim().isEmpty ? user.username : username.trim(),
        mode: mode,
        siteTitle: site.title,
        version: site.version ?? site.apiVersion,
        lastUsed: DateTime.now(),
        health: ServerHealth.ok,
        latencyMs: state.latencyMs,
      );
      if (persistToken) {
        await _secure.write(profile.tokenKey, token);
      } else {
        await _secure.delete(profile.tokenKey);
      }
      final servers = ref.read(serverListProvider.notifier);
      await servers.upsert(profile);
      await servers.setActive(profile.id);
      state = SessionState(
        profile: profile,
        user: user,
        site: site,
        api: api,
        signedIn: true,
        latencyMs: state.latencyMs,
      );
      // v2.6：新建 / 重新登录后立刻把文件列表绑到该实例。
      // 之前只有「切换服务器」会 attach，添加完新服务器后文件页还停在旧实例，
      // 用户看到的现象就是「加完了但没切过去」。
      // 列表拉取失败不算登录失败：文件页自己有错误态与离线缓存。
      try {
        await ref.read(filesProvider.notifier).attach();
      } catch (_) {}
      return null;
    } on ApiException catch (e) {
      state = state.copyWith(connecting: false, error: e.friendly);
      return e.friendly;
    } catch (e) {
      const message = '连接失败，请检查地址与网络';
      state = state.copyWith(connecting: false, error: message);
      return message;
    }
  }

  Future<void> switchTo(String serverId) async {
    if (state.profile?.id == serverId) return;
    await ref.read(serverListProvider.notifier).setActive(serverId);
    state = const SessionState();
    await boot();
    // v2.6：切换与登录走同一条收尾路径，文件列表始终跟随当前实例。
    try {
      await ref.read(filesProvider.notifier).attach();
    } catch (_) {}
  }

  Future<void> refreshUser() async {
    final api = state.api;
    final profile = state.profile;
    if (api == null || profile == null) return;
    try {
      final user = await api.me();
      state = SessionState(
        profile: profile,
        user: user,
        site: state.site,
        api: api,
        signedIn: true,
        offline: false,
        latencyMs: state.latencyMs,
      );
    } on ApiException catch (_) {
      // keep the current session; a stale /api/me must not log the user out
    }
  }

  /// Called by any request that came back 401.
  Future<void> expire() async {
    final profile = state.profile;
    if (profile != null) await _secure.delete(profile.tokenKey);
    state = SessionState(profile: profile, error: '登录已失效，请重新连接');
  }

  Future<void> signOut() async {
    final profile = state.profile;
    if (profile != null) await _secure.delete(profile.tokenKey);
    state = SessionState(profile: profile);
  }

  Future<void> retry() async {
    state = const SessionState();
    await boot();
  }
}
