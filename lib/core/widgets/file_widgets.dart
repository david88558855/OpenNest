import 'package:flutter/material.dart';

import '../format.dart';
import '../models/api_types.dart';
import '../theme/tokens.dart';
import 'ol_icon.dart';

/// The tinted 29×29 (desktop) / 36×36 (mobile) file glyph tile.
class FileGlyph extends StatelessWidget {
  final FileItem? item;
  final String? name;
  final bool isDir;
  final double size;
  final double radius;
  final double iconSize;

  const FileGlyph({
    super.key,
    this.item,
    this.name,
    this.isDir = false,
    this.size = 29,
    this.radius = 8,
    this.iconSize = 15,
  });

  @override
  Widget build(BuildContext context) {
    final n = item?.name ?? name ?? '';
    final dir = item?.isDir ?? isDir;
    final kind = kindOf(n, dir);
    final tone = tileColors(toneOfKind(kind));
    final bg = context.ol.isDark ? _darkTone(kind) : tone.bg;
    final fg = context.ol.isDark ? _darkFg(kind) : tone.fg;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(radius)),
      child: Center(child: OlIcon(iconOfKind(kind), size: iconSize, color: fg, strokeWidth: 1.9)),
    );
  }

  Color _darkTone(FileKind k) {
    switch (k) {
      case FileKind.folder:
        return const Color(0xFF0E2C40);
      case FileKind.video:
        return const Color(0xFF211C3F);
      case FileKind.image:
        return const Color(0xFF3A1B27);
      case FileKind.audio:
        return const Color(0xFF0E2E2B);
      case FileKind.text:
        return const Color(0xFF33260F);
      default:
        return const Color(0xFF17293D);
    }
  }

  Color _darkFg(FileKind k) {
    switch (k) {
      case FileKind.folder:
        return const Color(0xFF7DD3FC);
      case FileKind.video:
        return const Color(0xFFB9A7FF);
      case FileKind.image:
        return const Color(0xFFFF9DB4);
      case FileKind.audio:
        return const Color(0xFF5EEAD4);
      case FileKind.text:
        return const Color(0xFFF7C873);
      default:
        return const Color(0xFF9FB3C7);
    }
  }
}
