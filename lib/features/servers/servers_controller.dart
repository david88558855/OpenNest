import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/server_profile.dart';
import '../../core/storage/secure_store.dart';
import '../../core/storage/server_store.dart';

class ServerListState {
  final List<ServerProfile> servers;
  final String? activeId;
  final bool ready;

  const ServerListState({this.servers = const [], this.activeId, this.ready = false});

  ServerProfile? get active {
    if (activeId == null) return null;
    for (final s in servers) {
      if (s.id == activeId) return s;
    }
    return null;
  }

  int get count => servers.length;

  ServerListState copyWith({List<ServerProfile>? servers, String? activeId, bool? ready}) => ServerListState(
        servers: servers ?? this.servers,
        activeId: activeId ?? this.activeId,
        ready: ready ?? this.ready,
      );
}

class ServerListNotifier extends StateNotifier<ServerListState> {
  final ServerStore _store;
  final SecureStore _secure;

  ServerListNotifier(this._store, this._secure) : super(const ServerListState()) {
    final servers = _store.loadServers();
    var activeId = _store.loadActiveId();
    if (activeId == null || !servers.any((s) => s.id == activeId)) {
      activeId = servers.isEmpty ? null : servers.first.id;
    }
    state = ServerListState(servers: servers, activeId: activeId, ready: true);
  }

  Future<ServerProfile> upsert(ServerProfile profile) async {
    final list = [...state.servers];
    final index = list.indexWhere((e) => e.id == profile.id);
    if (index >= 0) {
      list[index] = profile;
    } else {
      list.insert(0, profile);
    }
    await _store.saveServers(list);
    state = ServerListState(servers: list, activeId: state.activeId, ready: true);
    return profile;
  }

  Future<void> setActive(String id) async {
    final list = [...state.servers];
    final index = list.indexWhere((e) => e.id == id);
    if (index < 0) return;
    list[index] = list[index].copyWith(lastUsed: DateTime.now());
    await _store.saveServers(list);
    await _store.saveActiveId(id);
    state = ServerListState(servers: list, activeId: id, ready: true);
  }

  /// Deletes only the local profile + keychain entry, never server data.
  Future<void> remove(String id) async {
    final list = state.servers.where((e) => e.id != id).toList();
    await _store.saveServers(list);
    await _secure.delete('ol_srv_${id}_token');
    var activeId = state.activeId;
    if (activeId == id) {
      activeId = list.isEmpty ? null : list.first.id;
      await _store.saveActiveId(activeId);
    }
    state = ServerListState(servers: list, activeId: activeId, ready: true);
  }

  Future<void> touch(
    String id, {
    int? latencyMs,
    ServerHealth? health,
    String? siteTitle,
    String? version,
  }) async {
    final list = [...state.servers];
    final index = list.indexWhere((e) => e.id == id);
    if (index < 0) return;
    list[index] = list[index].copyWith(
      latencyMs: latencyMs,
      health: health,
      siteTitle: siteTitle,
      version: version,
    );
    await _store.saveServers(list);
    state = ServerListState(servers: list, activeId: state.activeId, ready: true);
  }

  Future<void> saveAll(List<ServerProfile> servers) async {
    await _store.saveServers(servers);
    state = ServerListState(servers: servers, activeId: state.activeId, ready: true);
  }
}
