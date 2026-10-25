import 'package:flutter/material.dart';

String formatBytes(num? bytes, {int digits = 1}) {
  if (bytes == null) return '—';
  final v = bytes.toDouble();
  if (v <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
  var i = 0;
  var n = v;
  while (n >= 1024 && i < units.length - 1) {
    n /= 1024;
    i++;
  }
  final text = (i == 0 || n >= 100) ? n.toStringAsFixed(0) : n.toStringAsFixed(digits);
  return '$text ${units[i]}';
}

String formatSpeed(double bytesPerSecond) {
  if (bytesPerSecond <= 0) return '0 B/s';
  return '${formatBytes(bytesPerSecond)}/s';
}

String formatCountdown(int seconds) {
  if (seconds <= 0) return '—';
  if (seconds < 60) return '$seconds 秒';
  if (seconds < 3600) return '${(seconds / 60).ceil()} 分';
  return '${(seconds / 3600).toStringAsFixed(1)} 小时';
}

String two(int v) => v < 10 ? '0$v' : '$v';

String formatDate(DateTime? d) {
  if (d == null) return '—';
  final now = DateTime.now();
  if (d.year == now.year) {
    return '${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }
  return '${d.year}-${two(d.month)}-${two(d.day)}';
}

String relativeTime(DateTime? d) {
  if (d == null) return '从未';
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
  if (diff.inHours < 24) return '${diff.inHours} 小时前';
  if (diff.inDays == 1) return '昨天';
  if (diff.inDays < 30) return '${diff.inDays} 天前';
  return formatDate(d);
}

String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  if (h > 0) return '$h:${two(m)}:${two(s)}';
  return '$m:${two(s)}';
}

/// File kind drives both the icon and the tinted tile used across boards.
enum FileKind { folder, video, image, audio, text, archive, code, other }

const _videoExt = {'mkv', 'mp4', 'avi', 'mov', 'webm', 'flv', 'wmv', 'm4v', 'ts', 'm2ts', 'rmvb', 'mpg', 'mpeg'};
const _imageExt = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'svg', 'heic', 'avif', 'ico', 'tiff'};
const _audioExt = {'mp3', 'flac', 'wav', 'aac', 'ogg', 'm4a', 'ape', 'opus', 'wma'};
const _textExt = {'txt', 'md', 'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'ass', 'srt', 'vtt', 'log', 'csv', 'epub'};
const _archiveExt = {'zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz', 'iso'};
const _codeExt = {'dart', 'js', 'ts', 'json', 'yaml', 'yml', 'xml', 'html', 'css', 'py', 'go', 'rs', 'java', 'kt', 'c', 'cpp', 'h', 'sh'};

String extensionOf(String name) {
  final i = name.lastIndexOf('.');
  if (i <= 0 || i == name.length - 1) return '';
  return name.substring(i + 1).toLowerCase();
}

FileKind kindOf(String name, bool isDir) {
  if (isDir) return FileKind.folder;
  final ext = extensionOf(name);
  if (_videoExt.contains(ext)) return FileKind.video;
  if (_imageExt.contains(ext)) return FileKind.image;
  if (_audioExt.contains(ext)) return FileKind.audio;
  if (_codeExt.contains(ext)) return FileKind.code;
  if (_archiveExt.contains(ext)) return FileKind.archive;
  if (_textExt.contains(ext)) return FileKind.text;
  return FileKind.other;
}

String iconOfKind(FileKind k) {
  switch (k) {
    case FileKind.folder:
      return 'folder';
    case FileKind.video:
      return 'film';
    case FileKind.image:
      return 'image';
    case FileKind.audio:
      return 'music';
    case FileKind.text:
      return 'file-text';
    case FileKind.archive:
      return 'archive';
    case FileKind.code:
      return 'file-code';
    case FileKind.other:
      return 'file';
  }
}

/// Tile tone — t-sky / t-violet / t-rose / t-amber / t-teal / t-slate.
enum TileTone { sky, violet, rose, amber, teal, slate }

TileTone toneOfKind(FileKind k) {
  switch (k) {
    case FileKind.folder:
      return TileTone.sky;
    case FileKind.video:
      return TileTone.violet;
    case FileKind.image:
      return TileTone.rose;
    case FileKind.audio:
      return TileTone.teal;
    case FileKind.text:
      return TileTone.amber;
    case FileKind.archive:
      return TileTone.slate;
    case FileKind.code:
      return TileTone.slate;
    case FileKind.other:
      return TileTone.slate;
  }
}

class TileColors {
  final Color bg;
  final Color fg;
  const TileColors(this.bg, this.fg);
}

TileColors tileColors(TileTone tone) {
  switch (tone) {
    case TileTone.sky:
      return const TileColors(Color(0xFFE6F7FE), Color(0xFF0A93C4));
    case TileTone.violet:
      return const TileColors(Color(0xFFF1EDFF), Color(0xFF7C5CFC));
    case TileTone.rose:
      return const TileColors(Color(0xFFFFEDF2), Color(0xFFE8476F));
    case TileTone.amber:
      return const TileColors(Color(0xFFFFF5E2), Color(0xFFD98A06));
    case TileTone.teal:
      return const TileColors(Color(0xFFE4FBF5), Color(0xFF0DA98F));
    case TileTone.slate:
      return const TileColors(Color(0xFFEFF3F8), Color(0xFF63788E));
  }
}

String joinPath(String dir, String name) {
  if (dir == '/' || dir.isEmpty) return '/$name';
  if (dir.endsWith('/')) return '$dir$name';
  return '$dir/$name';
}

String parentOf(String path) {
  if (path.isEmpty || path == '/') return '/';
  final normalized = path.endsWith('/') ? path.substring(0, path.length - 1) : path;
  final i = normalized.lastIndexOf('/');
  if (i <= 0) return '/';
  return normalized.substring(0, i);
}

String baseName(String path) {
  if (path.isEmpty || path == '/') return '/';
  final normalized = path.endsWith('/') ? path.substring(0, path.length - 1) : path;
  final i = normalized.lastIndexOf('/');
  return i < 0 ? normalized : normalized.substring(i + 1);
}
