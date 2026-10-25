import 'dart:math';

enum AuthMode { password, token }

enum ServerHealth { unknown, ok, timeout, unauthorized }

/// One OpenList instance. Everything except the token lives in plain prefs,
/// the token lives in the OS keychain keyed by `ol_srv_<id>_token`.
class ServerProfile {
  final String id;
  final String name;
  final String baseUrl;
  final String username;
  final AuthMode mode;
  final bool isolatedDownload;
  final bool isolatedCache;
  final bool rememberBrowse;
  final DateTime? lastUsed;
  final String? siteTitle;
  final String? version;
  final int? latencyMs;
  final ServerHealth health;

  const ServerProfile({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.username,
    this.mode = AuthMode.password,
    this.isolatedDownload = true,
    this.isolatedCache = true,
    this.rememberBrowse = true,
    this.lastUsed,
    this.siteTitle,
    this.version,
    this.latencyMs,
    this.health = ServerHealth.unknown,
  });

  String get host {
    final uri = Uri.tryParse(baseUrl);
    return uri?.host ?? baseUrl;
  }

  String get displayHost {
    final uri = Uri.tryParse(baseUrl);
    if (uri == null || uri.host.isEmpty) return baseUrl;
    final port = uri.hasPort ? ':${uri.port}' : '';
    final path = uri.path == '/' ? '' : uri.path;
    return '${uri.host}$port$path';
  }

  String get tokenKey => 'ol_srv_${id}_token';
  String get downloadKey => 'ol_srv_${id}_download';
  String get browseKey => 'ol_srv_${id}_browse';
  String get cacheKey => 'ol_srv_${id}_cache';
  String get favoritesKey => 'ol_srv_${id}_favorites';

  ServerProfile copyWith({
    String? name,
    String? baseUrl,
    String? username,
    AuthMode? mode,
    bool? isolatedDownload,
    bool? isolatedCache,
    bool? rememberBrowse,
    DateTime? lastUsed,
    String? siteTitle,
    String? version,
    int? latencyMs,
    ServerHealth? health,
  }) {
    return ServerProfile(
      id: id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      username: username ?? this.username,
      mode: mode ?? this.mode,
      isolatedDownload: isolatedDownload ?? this.isolatedDownload,
      isolatedCache: isolatedCache ?? this.isolatedCache,
      rememberBrowse: rememberBrowse ?? this.rememberBrowse,
      lastUsed: lastUsed ?? this.lastUsed,
      siteTitle: siteTitle ?? this.siteTitle,
      version: version ?? this.version,
      latencyMs: latencyMs ?? this.latencyMs,
      health: health ?? this.health,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'username': username,
        'mode': mode.name,
        'isolatedDownload': isolatedDownload,
        'isolatedCache': isolatedCache,
        'rememberBrowse': rememberBrowse,
        'lastUsed': lastUsed?.toIso8601String(),
        'siteTitle': siteTitle,
        'version': version,
        'latencyMs': latencyMs,
        'health': health.name,
      };

  factory ServerProfile.fromJson(Map<String, dynamic> j) => ServerProfile(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        baseUrl: (j['baseUrl'] ?? '').toString(),
        username: (j['username'] ?? '').toString(),
        mode: (j['mode'] ?? 'password') == 'token' ? AuthMode.token : AuthMode.password,
        isolatedDownload: j['isolatedDownload'] as bool? ?? true,
        isolatedCache: j['isolatedCache'] as bool? ?? true,
        rememberBrowse: j['rememberBrowse'] as bool? ?? true,
        lastUsed: DateTime.tryParse((j['lastUsed'] ?? '').toString()),
        siteTitle: j['siteTitle']?.toString(),
        version: j['version']?.toString(),
        latencyMs: (j['latencyMs'] as num?)?.toInt(),
        health: ServerHealth.values.firstWhere(
          (e) => e.name == j['health'],
          orElse: () => ServerHealth.unknown,
        ),
      );
}

String newServerId() {
  final rnd = Random();
  return '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}${rnd.nextInt(9999).toRadixString(36)}';
}

/// Adds a scheme when missing, drops trailing slashes, keeps sub-path deploys.
String normalizeBaseUrl(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return '';
  final lower = s.toLowerCase();
  if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
    s = 'https://$s';
  }
  while (s.endsWith('/')) {
    s = s.substring(0, s.length - 1);
  }
  return s;
}

/// Returns null when the URL is usable, otherwise an inline error message.
String? validateBaseUrl(String raw) {
  final s = normalizeBaseUrl(raw);
  if (s.isEmpty) return '请填写服务器地址';
  final uri = Uri.tryParse(s);
  if (uri == null || uri.host.isEmpty) return '地址格式不正确，例如 https://pan.example.com';
  if (uri.scheme != 'http' && uri.scheme != 'https') return '仅支持 http / https';
  if (uri.scheme == 'http' && !isPrivateHost(uri.host)) {
    return 'HTTP 仅允许内网地址，公网请使用 HTTPS';
  }
  return null;
}

bool isPrivateHost(String host) {
  if (host == 'localhost' || host == '127.0.0.1' || host == '::1') return true;
  final parts = host.split('.');
  if (parts.length != 4) return host.endsWith('.local') || host.endsWith('.lan');
  final a = int.tryParse(parts[0]);
  final b = int.tryParse(parts[1]);
  if (a == null || b == null || parts.length != 4) return false;
  if (a == 10) return true;
  if (a == 192 && b == 168) return true;
  if (a == 172 && b >= 16 && b <= 31) return true;
  if (a == 127) return true;
  return false;
}
