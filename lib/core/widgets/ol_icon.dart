import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/tokens.dart';

/// All icons are stroke-only vector glyphs drawn on a 24×24 grid to match the
/// app's line style. No raster assets, no icon fonts.
class _Glyph {
  final String body;
  final bool fillable;
  const _Glyph(this.body, {this.fillable = false});
}

const Map<String, _Glyph> _glyphs = {
  'layers': _Glyph('<path d="m12 2 9 5-9 5-9-5 9-5Z"/><path d="m3 12 9 5 9-5"/><path d="m3 17 9 5 9-5"/>'),
  'folder': _Glyph('<path d="M4 20h16a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.7-.9L9.3 3.9A2 2 0 0 0 7.6 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z"/>'),
  'folder-plus': _Glyph('<path d="M4 20h16a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.7-.9L9.3 3.9A2 2 0 0 0 7.6 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z"/><path d="M12 10v6M9 13h6"/>'),
  'file': _Glyph('<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8Z"/><path d="M14 2v6h6"/>'),
  'file-text': _Glyph('<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8Z"/><path d="M14 2v6h6M8 13h8M8 17h5"/>'),
  'file-code': _Glyph('<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8Z"/><path d="M14 2v6h6"/><path d="m10 13-2 2 2 2M14 13l2 2-2 2"/>'),
  'film': _Glyph('<rect x="2" y="3" width="20" height="18" rx="2"/><path d="M7 3v18M17 3v18M2 8h5M2 16h5M17 8h5M17 16h5"/>'),
  'image': _Glyph('<rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="8.5" cy="8.5" r="1.5"/><path d="m21 15-5-5L5 21"/>'),
  'music': _Glyph('<path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/>'),
  'archive': _Glyph('<rect x="2" y="4" width="20" height="5" rx="1"/><path d="M4 9v11h16V9M10 13h4"/>'),
  'search': _Glyph('<circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/>'),
  'upload': _Glyph('<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><path d="m17 8-5-5-5 5M12 3v12"/>'),
  'download': _Glyph('<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><path d="m7 10 5 5 5-5M12 15V3"/>'),
  'clock': _Glyph('<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>'),
  'star': _Glyph('<path d="m12 3 2.7 5.6 6.1.9-4.4 4.3 1 6.1-5.4-2.9-5.4 2.9 1-6.1L3.2 9.5l6.1-.9L12 3Z"/>', fillable: true),
  'trash': _Glyph('<path d="M3 6h18M8 6V4a1 1 0 0 1 1-1h6a1 1 0 0 1 1 1v2M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6"/><path d="M10 11v6M14 11v6"/>'),
  'more': _Glyph('<circle cx="5" cy="12" r="1.4"/><circle cx="12" cy="12" r="1.4"/><circle cx="19" cy="12" r="1.4"/>'),
  'more-v': _Glyph('<circle cx="12" cy="5" r="1.4"/><circle cx="12" cy="12" r="1.4"/><circle cx="12" cy="19" r="1.4"/>'),
  'settings': _Glyph('<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.9l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.9-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1A1.7 1.7 0 0 0 9 19.4a1.7 1.7 0 0 0-1.9.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.9 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1A1.7 1.7 0 0 0 4.6 9a1.7 1.7 0 0 0-.3-1.9l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.9.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.9-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.9V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1Z"/>'),
  'grid': _Glyph('<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/>'),
  'list': _Glyph('<path d="M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01"/>'),
  'chev-r': _Glyph('<path d="m9 18 6-6-6-6"/>'),
  'chev-l': _Glyph('<path d="m15 18-6-6 6-6"/>'),
  'chev-d': _Glyph('<path d="m6 9 6 6 6-6"/>'),
  'chev-u': _Glyph('<path d="m18 15-6-6-6 6"/>'),
  'plus': _Glyph('<path d="M12 5v14M5 12h14"/>'),
  'check': _Glyph('<path d="m20 6-11 11-5-5"/>'),
  'play': _Glyph('<path d="M6 3.5 20 12 6 20.5v-17Z"/>', fillable: true),
  'pause': _Glyph('<rect x="6" y="4" width="4" height="16" rx="1"/><rect x="14" y="4" width="4" height="16" rx="1"/>', fillable: true),
  'hard-drive': _Glyph('<path d="M22 12H2M5.45 5.11 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11Z"/><path d="M6 16h.01M10 16h.01"/>'),
  'server': _Glyph('<rect x="2" y="2" width="20" height="8" rx="2"/><rect x="2" y="14" width="20" height="8" rx="2"/><path d="M6 6h.01M6 18h.01"/>'),
  'wifi': _Glyph('<path d="M5 12.5a10 10 0 0 1 14 0M8.5 16a5.5 5.5 0 0 1 7 0M2 9a15 15 0 0 1 20 0"/><path d="M12 20h.01"/>'),
  'bell': _Glyph('<path d="M6 8a6 6 0 1 1 12 0c0 7 3 8 3 8H3s3-1 3-8"/><path d="M10.3 21a2 2 0 0 0 3.4 0"/>'),
  'user': _Glyph('<circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/>'),
  'lock': _Glyph('<rect x="4" y="11" width="16" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/>'),
  'eye': _Glyph('<path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7-10-7-10-7Z"/><circle cx="12" cy="12" r="3"/>'),
  'eye-off': _Glyph('<path d="M3 3l18 18"/><path d="M10.6 6.2A9.8 9.8 0 0 1 12 6c6.5 0 10 6 10 6a17 17 0 0 1-3.2 3.9M6.2 7.6A17 17 0 0 0 2 12s3.5 6 10 6a9.7 9.7 0 0 0 4-0.8"/><path d="M9.9 9.9a3 3 0 0 0 4.2 4.2"/>'),
  'refresh': _Glyph('<path d="M21 12a9 9 0 1 1-2.6-6.4M21 3v6h-6"/>'),
  'link': _Glyph('<path d="M10 13a5 5 0 0 0 7.5.5l3-3a5 5 0 0 0-7-7l-1.7 1.7"/><path d="M14 11a5 5 0 0 0-7.5-.5l-3 3a5 5 0 0 0 7 7l1.7-1.7"/>'),
  'move': _Glyph('<path d="M5 9V5h4M15 5h4v4M19 15v4h-4M9 19H5v-4"/><path d="M9 12h6M12 9v6"/>'),
  'copy': _Glyph('<rect x="9" y="9" width="12" height="12" rx="2"/><path d="M5 15H4a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1h10a1 1 0 0 1 1 1v1"/>'),
  'edit': _Glyph('<path d="M12 20h9"/><path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4Z"/>'),
  'x': _Glyph('<path d="M18 6 6 18M6 6l12 12"/>'),
  'minus': _Glyph('<path d="M5 12h14"/>'),
  'minimize': _Glyph('<path d="M4 14h6v6M20 10h-6V4M14 10l7-7M3 21l7-7"/>'),
  'square': _Glyph('<rect x="4" y="4" width="16" height="16" rx="1"/>'),
  'restore': _Glyph('<rect x="3" y="7" width="14" height="14" rx="1"/><path d="M7 3h14v14"/>'),
  'filter': _Glyph('<path d="M3 5h18l-7 8v6l-4 2v-8Z"/>'),
  'sort': _Glyph('<path d="M4 7h11M4 12h8M4 17h5"/><path d="M18 5v14M15 16l3 3 3-3"/>'),
  'globe': _Glyph('<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a15 15 0 0 1 0 18 15 15 0 0 1 0-18Z"/>'),
  'sun': _Glyph('<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/>'),
  'moon': _Glyph('<path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8Z"/>'),
  'monitor': _Glyph('<rect x="2" y="3" width="20" height="14" rx="2"/><path d="M8 21h8M12 17v4"/>'),
  'smartphone': _Glyph('<rect x="6" y="2" width="12" height="20" rx="2"/><path d="M11 18h2"/>'),
  'zap': _Glyph('<path d="M13 2 3 14h7l-1 8 10-12h-7l1-8Z"/>'),
  'shield': _Glyph('<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10Z"/><path d="m9 12 2 2 4-4"/>'),
  'key': _Glyph('<circle cx="7.5" cy="15.5" r="4.5"/><path d="m10.7 12.3 9.8-9.8M16 7l3 3M14 9l3 3"/>'),
  'logout': _Glyph('<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><path d="m16 17 5-5-5-5M21 12H9"/>'),
  'cloud': _Glyph('<path d="M17.5 19a4.5 4.5 0 0 0 .5-9 6 6 0 0 0-11.6 1.6A4 4 0 0 0 7 19Z"/>'),
  'arrow-up': _Glyph('<path d="M12 19V5M5 12l7-7 7 7"/>'),
  'arrow-down': _Glyph('<path d="M12 5v14M19 12l-7 7-7-7"/>'),
  'pie': _Glyph('<path d="M21.2 15.9A10 10 0 1 1 8 2.8"/><path d="M22 12A10 10 0 0 0 12 2v10Z"/>'),
  'command': _Glyph('<path d="M18 3a3 3 0 0 0-3 3v12a3 3 0 1 0 3-3H6a3 3 0 1 0 3 3V6a3 3 0 1 0-3 3h12a3 3 0 0 0 0-6Z"/>'),
  'external': _Glyph('<path d="M15 3h6v6M10 14 21 3"/><path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/>'),
  'alert': _Glyph('<circle cx="12" cy="12" r="9"/><path d="M12 8v5M12 16h.01"/>'),
  'info': _Glyph('<circle cx="12" cy="12" r="9"/><path d="M12 11v5M12 8h.01"/>'),
  'heart': _Glyph('<path d="M20.8 5.6a5 5 0 0 0-7.1 0L12 7.3l-1.7-1.7a5 5 0 1 0-7.1 7.1L12 21.5l8.8-8.8a5 5 0 0 0 0-7.1Z"/>'),
  'menu': _Glyph('<path d="M4 6h16M4 12h16M4 18h16"/>'),
  'stop': _Glyph('<rect x="5" y="5" width="14" height="14" rx="2"/>'),
  'database': _Glyph('<ellipse cx="12" cy="5" rx="9" ry="3"/><path d="M3 5v14c0 1.7 4 3 9 3s9-1.3 9-3V5"/><path d="M3 12c0 1.7 4 3 9 3s9-1.3 9-3"/>'),
  'panel': _Glyph('<rect x="3" y="3" width="18" height="18" rx="2"/><path d="M15 3v18"/>'),
  'volume': _Glyph('<path d="M11 5 6 9H2v6h4l5 4V5Z"/><path d="M15.5 8.5a5 5 0 0 1 0 7M18.5 5.5a9 9 0 0 1 0 13"/>'),
  'volume-off': _Glyph('<path d="M11 5 6 9H2v6h4l5 4V5Z"/><path d="m16 9 5 6M21 9l-5 6"/>'),
  'maximize': _Glyph('<path d="M8 3H3v5M16 3h5v5M21 16v5h-5M3 16v5h5"/>'),
  'pip': _Glyph('<rect x="3" y="4" width="18" height="16" rx="2"/><rect x="12" y="11" width="8" height="8" rx="1"/>'),
  'cloud-dl': _Glyph('<path d="M12 13v8M8 17l4 4 4-4"/><path d="M20.9 18.4A5 5 0 0 0 18 9h-1.3A8 8 0 1 0 4 16.3"/>'),
  'rotate': _Glyph('<path d="M3 12a9 9 0 1 0 3-6.7M3 4v5h5"/>'),
  'anchor': _Glyph('<circle cx="12" cy="5" r="3"/><path d="M12 22V8M5 12H2a10 10 0 0 0 20 0h-3"/>'),
  'inbox': _Glyph('<path d="M22 12h-6l-2 3h-4l-2-3H2"/><path d="M5.45 5.11 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11Z"/>'),
};

final Map<String, String> _svgCache = {};

class OlIcon extends StatelessWidget {
  final String name;
  final double size;
  final Color? color;
  final double strokeWidth;
  final bool filled;

  const OlIcon(
    this.name, {
    super.key,
    this.size = 18,
    this.color,
    this.strokeWidth = 1.8,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final resolved = color ?? Theme.of(context).colorScheme.onSurface;
    final glyph = _glyphs[name] ?? _glyphs['file']!;
    final paint = filled && glyph.fillable;
    final key = '$name|$strokeWidth|$paint';
    final svg = _svgCache.putIfAbsent(key, () {
      final fillAttr = paint ? 'fill="#000000"' : 'fill="none"';
      return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" '
          '$fillAttr stroke="#000000" '
          'stroke-width="$strokeWidth" stroke-linecap="round" stroke-linejoin="round">'
          '${glyph.body}</svg>';
    });
    return SvgPicture.string(
      svg,
      width: size,
      height: size,
      fit: BoxFit.contain,
      colorFilter: ColorFilter.mode(resolved, BlendMode.srcIn),
    );
  }
}

/// The gradient app mark — gradient square with the layers glyph.
class OlMark extends StatelessWidget {
  final double size;
  final double radius;
  final double iconSize;

  const OlMark({super.key, this.size = 30, this.radius = 9, this.iconSize = 15});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: OlTokens.gradientBrand,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: const [
          BoxShadow(color: Color(0x6638BDF8), blurRadius: 18, offset: Offset(0, 8)),
        ],
      ),
      child: Center(
        child: OlIcon('layers', size: iconSize, color: const Color(0xFFFFFFFF), strokeWidth: 2.1),
      ),
    );
  }
}
