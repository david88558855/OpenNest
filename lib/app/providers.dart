import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/api_exception.dart';
import '../core/models/api_types.dart';
import '../core/storage/prefs.dart';
import '../core/storage/secure_store.dart';
import '../core/storage/server_store.dart';
import '../features/auth/session.dart';
import '../features/files/files_controller.dart';
import '../features/transfers/transfers_controller.dart';

/// 本机引擎的固定身份：浏览位置、下载目录、收藏都按它分桶。
const String kLocalSourceId = 'local';

final prefsProvider = Provider<Prefs>((ref) => throw UnimplementedError('prefs overridden in main'));
final secureStoreProvider = Provider<SecureStore>((ref) => SecureStore());
final serverStoreProvider = Provider<ServerStore>((ref) => ServerStore(ref.watch(prefsProvider)));

final sessionProvider = StateNotifierProvider<SessionNotifier, SessionState>((ref) {
  return SessionNotifier(ref);
});

final filesProvider = StateNotifierProvider<FilesNotifier, FilesState>((ref) {
  return FilesNotifier(ref);
});

final transfersProvider = StateNotifierProvider<TransfersNotifier, TransfersState>((ref) {
  return TransfersNotifier(ref);
});

final appSettingsProvider = StateNotifierProvider<AppSettingsNotifier, AppSettings>((ref) {
  return AppSettingsNotifier(ref.watch(prefsProvider));
});

final favoritesProvider = StateNotifierProvider<FavoritesNotifier, List<FavoriteEntry>>((ref) {
  return FavoritesNotifier(ref.watch(serverStoreProvider));
});

/// Read-only admin surface (decision A): mount health and capacity only.
final storagesProvider = FutureProvider<List<StorageMount>>((ref) async {
  final session = ref.watch(sessionProvider);
  final api = session.api;
  if (api == null || !session.signedIn) return const [];
  try {
    return await api.storages();
  } on ApiException catch (_) {
    return const [];
  }
});

class AppSettings {
  final ThemeMode themeMode;
  final int concurrency;
  final int downLimitKbps;
  final int upLimitKbps;
  final bool closeToTray;
  final bool trayNotify;
  final bool resumePlayback;
  final bool autoPlayNext;
  final bool pauseOnSwitch;
  final bool wifiOnly;
  final bool backgroundTransfer;
  final double playbackSpeed;
  final int? lastLatency;

  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.concurrency = 3,
    this.downLimitKbps = 0,
    this.upLimitKbps = 0,
    this.closeToTray = true,
    this.trayNotify = true,
    this.resumePlayback = true,
    this.autoPlayNext = true,
    this.pauseOnSwitch = true,
    this.wifiOnly = false,
    this.backgroundTransfer = true,
    this.playbackSpeed = 1,
    this.lastLatency,
  });

  AppSettings copyWith({
    ThemeMode? themeMode,
    int? concurrency,
    int? downLimitKbps,
    int? upLimitKbps,
    bool? closeToTray,
    bool? trayNotify,
    bool? resumePlayback,
    bool? autoPlayNext,
    bool? pauseOnSwitch,
    bool? wifiOnly,
    bool? backgroundTransfer,
    double? playbackSpeed,
    int? lastLatency,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        concurrency: concurrency ?? this.concurrency,
        downLimitKbps: downLimitKbps ?? this.downLimitKbps,
        upLimitKbps: upLimitKbps ?? this.upLimitKbps,
        closeToTray: closeToTray ?? this.closeToTray,
        trayNotify: trayNotify ?? this.trayNotify,
        resumePlayback: resumePlayback ?? this.resumePlayback,
        autoPlayNext: autoPlayNext ?? this.autoPlayNext,
        pauseOnSwitch: pauseOnSwitch ?? this.pauseOnSwitch,
        wifiOnly: wifiOnly ?? this.wifiOnly,
        backgroundTransfer: backgroundTransfer ?? this.backgroundTransfer,
        playbackSpeed: playbackSpeed ?? this.playbackSpeed,
        lastLatency: lastLatency ?? this.lastLatency,
      );

  Map<String, dynamic> toJson() => {
        'theme': themeMode.name,
        'concurrency': concurrency,
        'down_limit_kbps': downLimitKbps,
        'up_limit_kbps': upLimitKbps,
        'close_to_tray': closeToTray,
        'tray_notify': trayNotify,
        'resume_playback': resumePlayback,
        'autoplay_next': autoPlayNext,
        'pause_on_switch': pauseOnSwitch,
        'wifi_only': wifiOnly,
        'background_transfer': backgroundTransfer,
        'playback_speed': playbackSpeed,
        // v1.0.22：读取侧一直在读 last_latency，写入侧之前漏了，导致值永远拿不到
        if (lastLatency != null) 'last_latency': lastLatency,
      };
}

class AppSettingsNotifier extends StateNotifier<AppSettings> {
  final Prefs _prefs;

  AppSettingsNotifier(this._prefs) : super(const AppSettings()) {
    final raw = _prefs.getJsonMap(ServerStore.keyPrefs);
    if (raw.isNotEmpty) {
      state = AppSettings(
        themeMode: switch (raw['theme']) {
          'light' => ThemeMode.light,
          'dark' => ThemeMode.dark,
          _ => ThemeMode.system,
        },
        concurrency: (raw['concurrency'] as num?)?.toInt() ?? 3,
        downLimitKbps: (raw['down_limit_kbps'] as num?)?.toInt() ?? 0,
        upLimitKbps: (raw['up_limit_kbps'] as num?)?.toInt() ?? 0,
        closeToTray: raw['close_to_tray'] as bool? ?? true,
        trayNotify: raw['tray_notify'] as bool? ?? true,
        resumePlayback: raw['resume_playback'] as bool? ?? true,
        autoPlayNext: raw['autoplay_next'] as bool? ?? true,
        pauseOnSwitch: raw['pause_on_switch'] as bool? ?? true,
        wifiOnly: raw['wifi_only'] as bool? ?? false,
        backgroundTransfer: raw['background_transfer'] as bool? ?? true,
        playbackSpeed: (raw['playback_speed'] as num?)?.toDouble() ?? 1,
        lastLatency: (raw['last_latency'] as num?)?.toInt(),
      );
    }
  }

  Future<void> _persist() => _prefs.setJsonMap(ServerStore.keyPrefs, state.toJson());

  void setTheme(ThemeMode mode) {
    state = state.copyWith(themeMode: mode);
    _persist();
  }

  void setConcurrency(int value) {
    state = state.copyWith(concurrency: value.clamp(1, 8).toInt());
    _persist();
  }

  void setDownLimit(int kbps) {
    state = state.copyWith(downLimitKbps: kbps.clamp(0, 1024 * 200).toInt());
    _persist();
  }

  void setUpLimit(int kbps) {
    state = state.copyWith(upLimitKbps: kbps.clamp(0, 1024 * 200).toInt());
    _persist();
  }

  void setCloseToTray(bool value) {
    state = state.copyWith(closeToTray: value);
    _persist();
  }

  void setTrayNotify(bool value) {
    state = state.copyWith(trayNotify: value);
    _persist();
  }

  void setResumePlayback(bool value) {
    state = state.copyWith(resumePlayback: value);
    _persist();
  }

  void setAutoPlayNext(bool value) {
    state = state.copyWith(autoPlayNext: value);
    _persist();
  }

  void setPauseOnSwitch(bool value) {
    state = state.copyWith(pauseOnSwitch: value);
    _persist();
  }

  void setWifiOnly(bool value) {
    state = state.copyWith(wifiOnly: value);
    _persist();
  }

  void setBackgroundTransfer(bool value) {
    state = state.copyWith(backgroundTransfer: value);
    _persist();
  }

  void setPlaybackSpeed(double value) {
    state = state.copyWith(playbackSpeed: value);
    _persist();
  }

  void rememberLatency(int ms) {
    state = state.copyWith(lastLatency: ms);
  }
}

class FavoriteEntry {
  final String serverId;
  final String path;
  final String name;
  final bool isDir;
  final int size;
  final DateTime addedAt;

  const FavoriteEntry({
    required this.serverId,
    required this.path,
    required this.name,
    required this.isDir,
    this.size = 0,
    required this.addedAt,
  });

  Map<String, dynamic> toJson() => {
        'path': path,
        'name': name,
        'is_dir': isDir,
        'size': size,
        'added_at': addedAt.toIso8601String(),
      };

  factory FavoriteEntry.fromJson(String serverId, Map<String, dynamic> j) => FavoriteEntry(
        serverId: serverId,
        path: (j['path'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        isDir: j['is_dir'] == true,
        size: (j['size'] as num?)?.toInt() ?? 0,
        addedAt: DateTime.tryParse((j['added_at'] ?? '').toString()) ?? DateTime.now(),
      );

  FileItem toItem() => FileItem(
        name: name,
        size: size,
        isDir: isDir,
        parent: path.contains('/') ? path.substring(0, path.lastIndexOf('/')) : '/',
      );
}

class FavoritesNotifier extends StateNotifier<List<FavoriteEntry>> {
  final ServerStore _store;

  FavoritesNotifier(this._store) : super(const []) {
    final all = <FavoriteEntry>[];
    for (final raw in _store.readFavorites(kLocalSourceId)) {
      final entry = FavoriteEntry.fromJson(kLocalSourceId, raw);
      if (entry.path.isNotEmpty) all.add(entry);
    }
    state = all;
  }

  List<FavoriteEntry> forServer(String? serverId) =>
      state.where((e) => e.serverId == serverId).toList();

  bool isFavorite(String? serverId, String path) =>
      state.any((e) => e.serverId == serverId && e.path == path);

  Future<void> toggle(String serverId, FileItem item, String dir) async {
    final fullPath = item.parent ?? (dir == '/' ? '/${item.name}' : '$dir/${item.name}');
    final exists = state.any((e) => e.serverId == serverId && e.path == fullPath);
    List<FavoriteEntry> next;
    if (exists) {
      next = state.where((e) => !(e.serverId == serverId && e.path == fullPath)).toList();
    } else {
      next = [
        ...state,
        FavoriteEntry(
          serverId: serverId,
          path: fullPath,
          name: item.name,
          isDir: item.isDir,
          size: item.size,
          addedAt: DateTime.now(),
        ),
      ];
    }
    state = next;
    await _store.saveFavorites(
      serverId,
      next.where((e) => e.serverId == serverId).map((e) => e.toJson()).toList(),
    );
  }

  Future<void> removeEntry(FavoriteEntry entry) async {
    final next = state.where((e) => !(e.serverId == entry.serverId && e.path == entry.path)).toList();
    state = next;
    await _store.saveFavorites(
      entry.serverId,
      next.where((e) => e.serverId == entry.serverId).map((e) => e.toJson()).toList(),
    );
  }
}
