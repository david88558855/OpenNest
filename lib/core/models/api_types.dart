/// Types mirroring the OpenList v4 JSON envelopes.
library;

class SiteInfo {
  final String title;
  final String? logo;
  final String? version;
  final String? apiVersion;
  final bool allowIndexed;
  final String? favicon;

  const SiteInfo({
    required this.title,
    this.logo,
    this.version,
    this.apiVersion,
    this.allowIndexed = false,
    this.favicon,
  });

  factory SiteInfo.fromJson(Map<String, dynamic> j) => SiteInfo(
        title: (j['site_title'] ?? j['title'] ?? 'OpenList').toString(),
        logo: j['logo']?.toString(),
        version: j['version']?.toString(),
        apiVersion: j['api_version']?.toString(),
        allowIndexed: j['allow_indexed'] == true,
        favicon: j['favicon']?.toString(),
      );
}

class UserInfo {
  final int id;
  final String username;
  final String? basePath;
  final int role;
  final int permission;
  final bool disabled;
  final String? ssoId;
  final bool otp;

  const UserInfo({
    required this.id,
    required this.username,
    this.basePath,
    this.role = 0,
    this.permission = 0,
    this.disabled = false,
    this.ssoId,
    this.otp = false,
  });

  bool get isAdmin => role >= 2 || (permission & 1) == 1;
  bool get canWrite => (permission & 4) == 4 || permission == 0 || isAdmin;

  factory UserInfo.fromJson(Map<String, dynamic> j) {
    final username = (j['username'] ?? j['name'] ?? '').toString();
    final basePath = (j['base_path'] ?? j['basePath'])?.toString();
    return UserInfo(
      id: (j['id'] as num?)?.toInt() ?? 0,
      username: username.isEmpty ? 'user' : username,
      basePath: (basePath == null || basePath.isEmpty) ? null : basePath,
      role: (j['role'] as num?)?.toInt() ?? 0,
      permission: (j['permission'] as num?)?.toInt() ?? 0,
      disabled: j['disabled'] == true,
      ssoId: j['sso_id']?.toString(),
      otp: j['otp'] == true,
    );
  }

  static const guest = UserInfo(id: 0, username: 'guest');
}

class FileItem {
  final String name;
  final int size;
  final bool isDir;
  final DateTime? modified;
  final String? sign;
  final String? thumb;
  final String? type;
  final String? hashInfo;
  final String? parent;
  final String? provider;

  const FileItem({
    required this.name,
    required this.size,
    required this.isDir,
    this.modified,
    this.sign,
    this.thumb,
    this.type,
    this.hashInfo,
    this.parent,
    this.provider,
  });

  factory FileItem.fromJson(Map<String, dynamic> j) {
    final modifiedRaw = j['modified']?.toString();
    DateTime? modified;
    if (modifiedRaw != null && modifiedRaw.isNotEmpty) {
      final parsed = DateTime.tryParse(modifiedRaw)?.toLocal();
      if (parsed != null && parsed.year > 1970) modified = parsed;
    }
    String? hash;
    final rawHash = j['hash_info'] ?? j['hashinfo'];
    if (rawHash is Map) {
      final entries = rawHash.entries.take(2).map((e) => '${e.key}: ${e.value}');
      hash = entries.join(' · ');
    } else if (rawHash != null) {
      hash = rawHash.toString();
    }
    return FileItem(
      name: (j['name'] ?? '').toString(),
      size: (j['size'] as num?)?.toInt() ?? 0,
      isDir: j['is_dir'] == true,
      modified: modified,
      sign: j['sign']?.toString(),
      thumb: j['thumb']?.toString(),
      type: j['type']?.toString(),
      hashInfo: hash,
      parent: j['parent']?.toString(),
      provider: j['provider']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'size': size,
        'is_dir': isDir,
        'modified': modified?.toUtc().toIso8601String(),
        'sign': sign,
        'thumb': thumb,
        'type': type,
        'hash_info': hashInfo,
        'parent': parent,
        'provider': provider,
      };
}

class FsListPage {
  final List<FileItem> items;
  final int total;
  final bool write;
  final String? provider;

  const FsListPage({
    required this.items,
    required this.total,
    this.write = true,
    this.provider,
  });
}

class DirNode {
  final String name;
  final String path;
  const DirNode(this.name, this.path);
}

class StorageMount {
  final int id;
  final String mountPath;
  final String driver;
  final String status;
  final int? totalSpace;
  final int? usedSpace;

  const StorageMount({
    required this.id,
    required this.mountPath,
    required this.driver,
    required this.status,
    this.totalSpace,
    this.usedSpace,
  });

  bool get isUp => status.toLowerCase() == 'work' || status.toLowerCase() == 'ok' || status == '1';
  double? get usageRatio {
    final total = totalSpace;
    final used = usedSpace;
    if (total == null || used == null || total <= 0) return null;
    return (used / total).clamp(0.0, 1.0).toDouble();
  }

  factory StorageMount.fromJson(Map<String, dynamic> j) => StorageMount(
        id: (j['id'] as num?)?.toInt() ?? 0,
        mountPath: (j['mount_path'] ?? j['path'] ?? '/').toString(),
        driver: (j['driver'] ?? '').toString(),
        status: (j['status'] ?? '').toString(),
        totalSpace: (j['total_space'] as num?)?.toInt(),
        usedSpace: (j['used_space'] as num?)?.toInt(),
      );
}

class ServerTask {
  final String id;
  final String name;
  final String state;
  final int progress;
  final int totalBytes;
  final int doneBytes;
  final String? error;

  const ServerTask({
    required this.id,
    required this.name,
    required this.state,
    required this.progress,
    this.totalBytes = 0,
    this.doneBytes = 0,
    this.error,
  });

  factory ServerTask.fromJson(Map<String, dynamic> j) => ServerTask(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        state: (j['state'] ?? '').toString(),
        progress: (j['progress'] as num?)?.toInt() ?? 0,
        totalBytes: (j['total_bytes'] as num?)?.toInt() ?? 0,
        doneBytes: (j['done_bytes'] as num?)?.toInt() ?? 0,
        error: j['error']?.toString(),
      );
}
