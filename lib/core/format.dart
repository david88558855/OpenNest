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

/// 带宽换算：1 Mbps = 1000 Kbps = 125 KB/s。
///
/// 限速用的是**带宽**口径（M 兆比特/秒），不是字节速率（MiB/s）。
const int kBytesPerMegabit = 125;

/// KB/s → Mbps（带宽口径）。
double limitMbps(int kbps) => kbps / kBytesPerMegabit;

/// Mbps（带宽口径）→ KB/s。
int limitKbpsFromMbps(double mbps) => (mbps * kBytesPerMegabit).round();

/// 限速文案：带宽口径，以 Mbps 为主。
///
/// 不足 1 Mbps 时用 Kbps（千比特/秒）表示，避免出现 0.1 Mbps 这类噪声。
/// 0 表示不限速。
///
/// 设置页与传输页共用，避免两处单位口径不一致。
String formatLimitSpeed(int kbps) {
  if (kbps <= 0) return '不限';
  final mbps = limitMbps(kbps);
  if (mbps < 1) return '${(kbps * 8).round()} Kbps';
  // 整数 Mbps 优先；有小数才显示一位（1.5 Mbps），避免 1.00 Mbps 这种噪声。
  if (mbps == mbps.roundToDouble()) return '${mbps.round()} Mbps';
  return '${mbps.toStringAsFixed(1)} Mbps';
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
  // 0.5.0：换成设计稿 D3/D4 的六组配色（此前是旧版蓝/玫红/琥珀/青/石板灰）。
  switch (tone) {
    case TileTone.sky:
      return const TileColors(kTileSky, kTypeFolder);
    case TileTone.violet:
      return const TileColors(kTileViolet, kTypeVideo);
    case TileTone.rose:
      return const TileColors(kTileTeal, kTypeImage);
    case TileTone.amber:
      return const TileColors(kTileAmber, kTypeDoc);
    case TileTone.teal:
      return const TileColors(kTilePink, kTypeAudio);
    case TileTone.slate:
      return const TileColors(kTileSlate, kTypeMuted);
  }
}

// 本地常量（避免 format.dart 反向依赖 theme/tokens，只镜像取值）
const kTileSky = Color(0xFFEAF8FE);
const kTileViolet = Color(0xFFF0EDFF);
const kTileTeal = Color(0xFFE8FBF3);
const kTileAmber = Color(0xFFFFF6E8);
const kTilePink = Color(0xFFFCE7F3);
const kTileSlate = Color(0xFFF1F6FB);
const kTypeFolder = Color(0xFF38BDF8);
const kTypeImage = Color(0xFF2DD4BF);
const kTypeVideo = Color(0xFF7C5CFC);
const kTypeDoc = Color(0xFFF97316);
const kTypeAudio = Color(0xFFEC4899);
const kTypeMuted = Color(0xFF6B7F94);

/// 表格「类型」列文案（设计稿 D3）：目录统一「文件夹」，图片带扩展名，
/// 文档按应用名，其余用中文类名。
String typeLabelOf(String name, bool isDir) {
  if (isDir) return '文件夹';
  final ext = extensionOf(name);
  final kind = kindOf(name, isDir);
  switch (kind) {
    case FileKind.video:
      return '视频';
    case FileKind.audio:
      return '音频';
    case FileKind.archive:
      return '压缩包';
    case FileKind.code:
      return '代码文件';
    case FileKind.image:
      return ext.isEmpty ? '图片' : '${ext.toUpperCase()} 图片';
    case FileKind.text:
      switch (ext) {
        case 'doc':
        case 'docx':
          return 'Word 文档';
        case 'xls':
        case 'xlsx':
          return 'Excel 表格';
        case 'ppt':
        case 'pptx':
          return 'PPT 演示';
        case 'pdf':
          return 'PDF 文档';
        case 'epub':
          return '电子书';
        case 'txt':
        case 'md':
        case 'log':
        case 'csv':
          return '文本文件';
        case 'ass':
        case 'srt':
        case 'vtt':
          return '字幕文件';
        default:
          return '文档';
      }
    case FileKind.folder:
      return '文件夹';
    case FileKind.other:
      return ext.isEmpty ? '文件' : '${ext.toUpperCase()} 文件';
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
