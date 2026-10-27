import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/openlist_api.dart';
import '../../core/models/api_types.dart';
import '../../core/models/server_profile.dart';
import '../../core/sidecar/sidecar_controller.dart';
import '../../core/sidecar/sidecar_state.dart';
import '../../core/storage/secure_store.dart';

/// 本机会话：不再有账号与登录页，只有「内嵌引擎是否就绪」。
///
/// `profile` 保留下来作为一个稳定的本机身份（id 固定为 `local`），
/// 浏览位置、下载目录等按它分桶。
class SessionState {
  final ServerProfile? profile;
  final UserInfo? user;
  final SiteInfo? site;
  final OpenListApi? api;
  final bool connecting;
  final bool signedIn;
  final bool offline;
  final String? error;
  final int? latencyMs;
  final int? port;

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
    this.port,
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
    bool clearError = false,
    int? latencyMs,
    int? port,
  }) {
    return SessionState(
      profile: profile ?? this.profile,
      user: user ?? this.user,
      site: site ?? this.site,
      api: api ?? this.api,
      connecting: connecting ?? this.connecting,
      signedIn: signedIn ?? this.signedIn,
      offline: offline ?? this.offline,
      // 0.5.9：以前这里写的是 `error: error`，任何一次 copyWith 都会把
      // 上一次的错误提示清成 null（语义陷阱）。现在与项目里其它状态类
      // 统一：默认保留旧错误，要清必须显式 clearError。
      error: clearError ? null : (error ?? this.error),
      latencyMs: latencyMs ?? this.latencyMs,
      port: port ?? this.port,
    );
  }
}

class SessionNotifier extends StateNotifier<SessionState> {
  SessionNotifier(this.ref)
      : _secure = ref.read(secureStoreProvider),
        super(const SessionState());

  final Ref ref;
  final SecureStore _secure;

  /// 会话探测上限。
  ///
  /// 引擎的 `StoragesLoaded` 中间件在存储源加载完之前会挂住 `/api/me`
  /// 等全部接口（只放行 `/`）。换过网络、原地址已不可达的存储源能把
  /// 这一步卡几分钟，所以这里必须自己限时，否则启动页与界面都会一起干等。
  static const Duration _probeTimeout = Duration(seconds: 12);

  /// 连接本机引擎并建立会话。引擎未就绪时只记录错误，不抛异常。
  Future<void> boot() async {
    final sidecar = ref.read(sidecarProvider);
    final port = sidecar.port;
    if (sidecar.status != SidecarStatus.ready || port == null) {
      state = SessionState(error: sidecar.error ?? '内嵌引擎尚未就绪', port: port);
      return;
    }

    final token = sidecar.token ?? await _secure.read(kSidecarTokenKey);
    final base = 'http://127.0.0.1:$port';
    final api = OpenListApi(baseUrl: base, token: token);
    state = SessionState(api: api, connecting: true, port: port);

    final watch = Stopwatch()..start();
    try {
      final user = await api.me().timeout(_probeTimeout);
      SiteInfo? site;
      try {
        site = await api.publicSettings().timeout(const Duration(seconds: 5));
      } on ApiException catch (_) {
        // 站点信息只是装饰，失败不影响会话。
      } on TimeoutException catch (_) {}
      watch.stop();
      state = SessionState(
        profile: _profileFor(base, port, user, site, watch.elapsedMilliseconds),
        user: user,
        site: site,
        api: api,
        signedIn: true,
        latencyMs: watch.elapsedMilliseconds,
        port: port,
      );
      ref.read(appSettingsProvider.notifier).rememberLatency(watch.elapsedMilliseconds);
    } on TimeoutException {
      // 进程与 HTTP 都活着，但接口被「存储源尚未加载完」挡住 —
      // 这不是引擎故障，界面上给一条可操作的原因即可。
      watch.stop();
      state = SessionState(
        api: api,
        connecting: false,
        offline: true,
        error: '引擎仍在加载存储源（换过网络、原地址已不可达的存储源会卡很久）。'
            '加载完成后点重试即可；也可在「设置 → 存储源」停用该源。',
        port: port,
      );
    } on ApiException catch (error) {
      watch.stop();
      if (error.needsReauth) {
        // 令牌失效：用钥匙串里的口令重新登录一次再试。
        final refreshed = await ref.read(sidecarProvider.notifier).refreshToken();
        if (refreshed != null && refreshed.isNotEmpty) {
          api.token = refreshed;
          try {
            final user = await api.me().timeout(_probeTimeout);
            state = SessionState(
              profile: _profileFor(base, port, user, null, null),
              user: user,
              api: api,
              signedIn: true,
              port: port,
            );
            return;
          } catch (_) {}
        }
        state = SessionState(error: '引擎令牌已失效，请重启应用', port: port);
      } else {
        state = SessionState(
          api: api,
          offline: true,
          error: error.friendly,
          port: port,
        );
      }
    } catch (_) {
      watch.stop();
      state = SessionState(api: api, offline: true, error: '引擎连接中断', port: port);
    }
  }

  ServerProfile _profileFor(String base, int port, UserInfo user, SiteInfo? site, int? latency) {
    return ServerProfile(
      id: 'local',
      name: '本机存储',
      baseUrl: base,
      username: user.username.isEmpty ? 'admin' : user.username,
      mode: AuthMode.token,
      lastUsed: DateTime.now(),
      siteTitle: site?.title,
      version: site?.version ?? site?.apiVersion,
      latencyMs: latency,
      health: ServerHealth.ok,
    );
  }

  Future<void> retry() async {
    state = const SessionState();
    await boot();
  }

  Future<void> refreshUser() async {
    final api = state.api;
    if (api == null) return;
    try {
      final user = await api.me();
      state = state.copyWith(user: user, signedIn: true, offline: false, clearError: true);
    } on ApiException catch (_) {
      // 保留当前会话，健康探测失败不改变登录语义。
    }
  }

  /// 请求返回 401 时调用：先尝试用本机口令换新令牌，再重建会话。
  Future<void> expire() async {
    final refreshed = await ref.read(sidecarProvider.notifier).refreshToken();
    if (refreshed == null) {
      state = state.copyWith(signedIn: false, error: '引擎令牌失效，请重启应用');
      return;
    }
    await boot();
  }
}
