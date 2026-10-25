import 'package:flutter/material.dart';

import '../format.dart';
import '../models/api_types.dart';
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
    final bg = tone.bg;
    final fg = tone.fg;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(radius)),
      child: Center(child: OlIcon(iconOfKind(kind), size: iconSize, color: fg, strokeWidth: 1.9)),
    );
  }
}
