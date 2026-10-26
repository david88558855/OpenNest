import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/api_exception.dart';
import '../core/models/api_types.dart';
import '../core/storage/prefs.dart';
import '../core/storage/secure_store.dart';
import '../core/storage/server_store.dart';
import '../features/auth/session.dart';
import '../features/files/files_controller.dart';
import '../features/transfers/transfers_controller.dart';

/// 本机引擎的固定身份：浏览位置、下载目录都按它分桶。
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
  final int concurrency;
  final int downLimitKbps;
  final int upLimitKbps;
  final bool closeToTray;
  final bool resumePlayback;
  final bool autoPlayNext;
  final bool backgroundTransfer;
  final double playbackSpeed;
  final int? lastLatency;

  const AppSettings({
    this.concurrency = 3,
    this.downLimitKbps = 0,
    this.upLimitKbps = 0,
    this.closeToTray = true,
    this.resumePlayback = true,
    this.autoPlayNext = true,
    this.backgroundTransfer = true,
    this.playbackSpeed = 1,
    this.lastLatency,
  });

  AppSettings copyWith({
    int? concurrency,
    int? downLimitKbps,
    int? upLimitKbps,
    bool? closeToTray,
    bool? resumePlayback,
    bool? autoPlayNext,
    bool? backgroundTransfer,
    double? playbackSpeed,
    int? lastLatency,
  }) =>
      AppSettings(
        concurrency: concurrency ?? this.concurrency,
        downLimitKbps: downLimitKbps ?? this.downLimitKbps,
        upLimitKbps: upLimitKbps ?? this.upLimitKbps,
        closeToTray: closeToTray ?? this.closeToTray,
        resumePlayback: resumePlayback ?? this.resumePlayback,
        autoPlayNext: autoPlayNext ?? this.autoPlayNext,
        backgroundTransfer: backgroundTransfer ?? this.backgroundTransfer,
        playbackSpeed: playbackSpeed ?? this.playbackSpeed,
        lastLatency: lastLatency ?? this.lastLatency,
      );

  Map<String, dynamic> toJson() => {
        'concurrency': concurrency,
        'down_limit_kbps': downLimitKbps,
        'up_limit_kbps': upLimitKbps,
        'close_to_tray': closeToTray,
        'resume_playback': resumePlayback,
        'autoplay_next': autoPlayNext,
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
        concurrency: (raw['concurrency'] as num?)?.toInt() ?? 3,
        downLimitKbps: (raw['down_limit_kbps'] as num?)?.toInt() ?? 0,
        upLimitKbps: (raw['up_limit_kbps'] as num?)?.toInt() ?? 0,
        closeToTray: raw['close_to_tray'] as bool? ?? true,
        resumePlayback: raw['resume_playback'] as bool? ?? true,
        autoPlayNext: raw['autoplay_next'] as bool? ?? true,
        backgroundTransfer: raw['background_transfer'] as bool? ?? true,
        playbackSpeed: (raw['playback_speed'] as num?)?.toDouble() ?? 1,
        lastLatency: (raw['last_latency'] as num?)?.toInt(),
      );
    }
  }

  Future<void> _persist() => _prefs.setJsonMap(ServerStore.keyPrefs, state.toJson());

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

  void setResumePlayback(bool value) {
    state = state.copyWith(resumePlayback: value);
    _persist();
  }

  void setAutoPlayNext(bool value) {
    state = state.copyWith(autoPlayNext: value);
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
