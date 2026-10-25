enum TransferKind { download, upload }

enum TransferStatus { queued, running, paused, done, failed }

class TransferTask {
  final String id;
  final String serverId;
  final String serverLabel;
  final TransferKind kind;
  final String name;
  final String remotePath;
  final String localPath;

  /// 相对下载根的子目录（v1.0.31 文件夹递归下载用）。
  /// 空串表示直接落在下载根；多级用 `/` 分隔，每级都已在入队前清洗过。
  final String localSubdir;
  int total;
  int done;
  TransferStatus status;
  String? error;
  String? sign;
  double speed;
  bool resumable;
  final DateTime createdAt;

  TransferTask({
    required this.id,
    required this.serverId,
    required this.serverLabel,
    required this.kind,
    required this.name,
    required this.remotePath,
    required this.localPath,
    this.localSubdir = '',
    this.total = 0,
    this.done = 0,
    this.status = TransferStatus.queued,
    this.error,
    this.sign,
    this.speed = 0,
    this.resumable = true,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  double get progress {
    if (total <= 0) return 0;
    return (done / total).clamp(0.0, 1.0).toDouble();
  }

  bool get isActive => status == TransferStatus.running;

  TransferTask copyWith({TransferStatus? status}) => TransferTask(
        id: id,
        serverId: serverId,
        serverLabel: serverLabel,
        kind: kind,
        name: name,
        remotePath: remotePath,
        localPath: localPath,
        localSubdir: localSubdir,
        total: total,
        done: done,
        status: status ?? this.status,
        error: error,
        sign: sign,
        speed: speed,
        resumable: resumable,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'serverId': serverId,
        'serverLabel': serverLabel,
        'kind': kind.name,
        'name': name,
        'remotePath': remotePath,
        'localPath': localPath,
        'localSubdir': localSubdir,
        'total': total,
        'done': done,
        'status': status.name,
        'error': error,
        'sign': sign,
        'resumable': resumable,
        'createdAt': createdAt.toIso8601String(),
      };

  factory TransferTask.fromJson(Map<String, dynamic> j) => TransferTask(
        id: (j['id'] ?? '').toString(),
        serverId: (j['serverId'] ?? '').toString(),
        serverLabel: (j['serverLabel'] ?? '').toString(),
        kind: (j['kind'] ?? 'download') == 'upload' ? TransferKind.upload : TransferKind.download,
        name: (j['name'] ?? '').toString(),
        remotePath: (j['remotePath'] ?? '').toString(),
        localPath: (j['localPath'] ?? '').toString(),
        localSubdir: (j['localSubdir'] ?? '').toString(),
        total: (j['total'] as num?)?.toInt() ?? 0,
        done: (j['done'] as num?)?.toInt() ?? 0,
        status: TransferStatus.values.firstWhere(
          (e) => e.name == j['status'],
          orElse: () => TransferStatus.paused,
        ),
        error: j['error']?.toString(),
        sign: j['sign']?.toString(),
        resumable: j['resumable'] as bool? ?? true,
        createdAt: DateTime.tryParse((j['createdAt'] ?? '').toString()),
      );
}
