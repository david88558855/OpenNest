import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';
import 'ol_icon.dart';

// ---------------------------------------------------------------------------
// 移动端（v2.3）：安卓真机上 30px 的桌面按钮点不中、9–11px 的字看不清。
// 这里只改「组件自带尺寸」，调用方显式传的更大值保持不动；桌面完全不受影响。
// ---------------------------------------------------------------------------
bool _isMobile(BuildContext context) => MediaQuery.sizeOf(context).width < 900;

/// 默认 30 → 42；行内紧凑（≤26）→ 34；调用方显式 28/34 等中间值按 34/42 抬。
double _mobileHeight(BuildContext context, double height) {
  if (!_isMobile(context)) return height;
  if (height <= 26) return OlMobile.buttonCompact;
  if (height <= 34) return OlMobile.buttonHeight;
  return height;
}

/// 按钮文字下限 12（实际渲染仍会被全局 textScaler 再放大到 ~15）。
double _mobileFont(BuildContext context, double fontSize) {
  if (!_isMobile(context)) return fontSize;
  return fontSize < 12 ? 12.0 : fontSize;
}


class OlPrimaryButton extends StatelessWidget {
  final String label;
  final String? icon;
  final VoidCallback? onTap;
  final double height;
  final bool expand;
  final bool busy;
  final double fontSize;

  const OlPrimaryButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.height = 30,
    this.expand = false,
    this.busy = false,
    this.fontSize = 11.5,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !busy;
    final h = _mobileHeight(context, height);
    final font = _mobileFont(context, fontSize);
    final content = Container(
      height: h,
      padding: EdgeInsets.symmetric(horizontal: _isMobile(context) ? 16 : 12),
      decoration: BoxDecoration(
        gradient: enabled ? OlTokens.gradientPrimary : const LinearGradient(colors: [Color(0xFFB8D9EA), Color(0xFFB8E3E1)]),
        borderRadius: BorderRadius.circular(8),
        boxShadow: enabled
            ? const [BoxShadow(color: Color(0x5938BDF8), blurRadius: 16, offset: Offset(0, 7))]
            : null,
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (busy)
            const SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(strokeWidth: 1.8, color: Colors.white),
            )
          else if (icon != null)
            OlIcon(icon!, size: _isMobile(context) ? 16 : 14, color: Colors.white, strokeWidth: 2),
          if (busy || icon != null) const SizedBox(width: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: font, fontWeight: FontWeight.w800, color: Colors.white),
          ),
        ],
      ),
    );
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(onTap: enabled ? onTap : null, child: content),
    );
  }
}

class OlGhostButton extends StatelessWidget {
  final String label;
  final String? icon;
  final VoidCallback? onTap;
  final double height;
  final double fontSize;

  const OlGhostButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.height = 30,
    this.fontSize = 11.5,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    final mobile = _isMobile(context);
    // v1.0.57：onTap 为 null 时进入禁用态——底色/描边/文字图标一起置灰，
    // 光标改为不可点。之前禁用态与可用态长得一模一样，点不动却看不出来。
    // 既有调用点全部传非空闭包，只有文件页「返回上层目录」在根目录时传 null。
    final enabled = onTap != null;
    final bg = enabled
        ? (p.isDark ? const Color(0xFF12202F) : Colors.white)
        : (p.isDark ? const Color(0xFF0F1D2C) : const Color(0xFFF4F7FA));
    final border = enabled
        ? p.line
        : (p.isDark ? const Color(0xFF142435) : const Color(0xFFEEF3F8));
    final fg = enabled ? p.ink2 : p.ink4;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: _mobileHeight(context, height),
          padding: EdgeInsets.symmetric(horizontal: mobile ? 14 : 11),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                OlIcon(icon!, size: mobile ? 16 : 14, color: fg),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: _mobileFont(context, fontSize),
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class OlSoftButton extends StatelessWidget {
  final String label;
  final String? icon;
  final VoidCallback? onTap;
  final double height;

  const OlSoftButton({super.key, required this.label, this.icon, this.onTap, this.height = 30});

  @override
  Widget build(BuildContext context) {
    final mobile = _isMobile(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: _mobileHeight(context, height),
          padding: EdgeInsets.symmetric(horizontal: mobile ? 14 : 11),
          decoration: BoxDecoration(
            color: const Color(0xFFEAF8FE),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                OlIcon(icon!, size: mobile ? 16 : 14, color: const Color(0xFF08799F)),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: _mobileFont(context, 11.5),
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF08799F),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class OlDangerButton extends StatelessWidget {
  final String label;
  final String? icon;
  final VoidCallback? onTap;
  final double height;

  const OlDangerButton({super.key, required this.label, this.icon, this.onTap, this.height = 30});

  @override
  Widget build(BuildContext context) {
    final mobile = _isMobile(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: _mobileHeight(context, height),
          padding: EdgeInsets.symmetric(horizontal: mobile ? 14 : 11),
          decoration: BoxDecoration(
            color: OlTokens.dangerSurface,
            border: Border.all(color: const Color(0xFFFFD9E0)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                OlIcon(icon!, size: mobile ? 16 : 14, color: OlTokens.dangerDeep),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: _mobileFont(context, 11.5),
                  fontWeight: FontWeight.w700,
                  color: OlTokens.dangerDeep,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class OlIconButton extends StatelessWidget {
  final String icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final double size;
  final bool squared;
  final Color? color;
  final double iconSize;

  const OlIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.tooltip,
    this.size = 30,
    this.squared = false,
    this.color,
    this.iconSize = 15,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    // 移动端图标按钮补到 40×40（原 30 太小，经常点空）。
    final mobile = _isMobile(context);
    final side = mobile ? (size < OlMobile.iconButton ? OlMobile.iconButton : size) : size;
    final glyph = mobile ? (iconSize < 18 ? 18.0 : iconSize) : iconSize;
    final child = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: side,
          height: side,
          decoration: BoxDecoration(
            color: squared ? (p.isDark ? const Color(0xFF12202F) : Colors.white) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: squared ? Border.all(color: p.isDark ? p.fieldBorder : const Color(0xFFE6EDF5)) : null,
          ),
          child: Center(
            child: OlIcon(icon, size: glyph, color: color ?? (p.isDark ? p.nav : const Color(0xFF5E7288))),
          ),
        ),
      ),
    );
    if (tooltip == null) return child;
    return Tooltip(message: tooltip!, waitDuration: const Duration(milliseconds: 500), child: child);
  }
}

class OlSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool small;

  const OlSwitch({super.key, required this.value, this.onChanged, this.small = false});

  @override
  Widget build(BuildContext context) {
    final w = small ? 32.0 : 36.0;
    final h = small ? 19.0 : 21.0;
    final knob = small ? 14.0 : 16.0;
    return MouseRegion(
      cursor: onChanged == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        // v1.0.42：全项目移除动画/转场，开关改为瞬时切换（不再有滑块过渡）
        child: Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            gradient: value ? OlTokens.gradientPrimary : null,
            color: value ? null : (context.ol.isDark ? const Color(0xFF20364C) : const Color(0xFFDFE8F1)),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Align(
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.5),
              child: Container(
                width: knob,
                height: knob,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 1))],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class OlSegItem<T> {
  final T value;
  final String label;
  final String? icon;
  const OlSegItem(this.value, this.label, {this.icon});
}

class OlSeg<T> extends StatelessWidget {
  final List<OlSegItem<T>> items;
  final T value;
  final ValueChanged<T> onChanged;
  final double height;

  /// v1.0.32：等分模式。[expand] 为 true 时每个选项均分可用宽度并允许文字省略。
  ///
  /// 之前只有自适应宽度（`MainAxisSize.min` + 文本不压缩）：移动端字号放大后，
  /// 「进行中 / 已完成 / 失败」三段总宽会超过容器，最后一段的选中白块被顶出灰底
  /// （用户截图里的溢出）。放进 `Expanded` 的场景都应该传 true。
  final bool expand;

  const OlSeg({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
    this.height = 24,
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    // v2.3：移动端分段控件同样抬到 30，文案 12。
    final mobile = _isMobile(context);
    final segHeight = mobile ? (height < 30 ? 30.0 : height) : height;
    // 裁剪兜底：即使某段内容再宽，也不会画到灰底外面（选中块的阴影/圆角一并被裁）。
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: p.isDark ? const Color(0xFF101F31) : const Color(0xFFF3F7FB),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          children: [
            for (final item in items)
              if (expand)
                Expanded(child: _segItem(context, item, p, mobile, segHeight))
              else
                _segItem(context, item, p, mobile, segHeight),
          ],
        ),
      ),
    );
  }

  Widget _segItem(BuildContext context, OlSegItem<T> item, OlPalette p, bool mobile, double segHeight) {
    final selected = item.value == value;
    return GestureDetector(
      onTap: () => onChanged(item.value),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          height: segHeight,
          padding: EdgeInsets.symmetric(horizontal: expand ? 6 : (mobile ? 12 : 8)),
          alignment: expand ? Alignment.center : null,
          decoration: BoxDecoration(
            color: selected ? (p.isDark ? const Color(0xFF1B2F45) : Colors.white) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: expand ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              if (item.icon != null) ...[
                OlIcon(
                  item.icon!,
                  size: 12,
                  color: selected ? (p.isDark ? const Color(0xFFE3EEF7) : const Color(0xFF1C3044)) : p.ink3,
                ),
                const SizedBox(width: 5),
              ],
              Flexible(
                child: Text(
                  item.label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: mobile ? 12 : (height < 23 ? 9.5 : 10.5),
                    fontWeight: FontWeight.w700,
                    color: selected ? (p.isDark ? const Color(0xFFE3EEF7) : const Color(0xFF1C3044)) : p.ink3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class OlChip extends StatelessWidget {
  final String label;
  final String? icon;
  final bool selected;
  final bool teal;
  final VoidCallback? onTap;
  final double height;

  const OlChip({
    super.key,
    required this.label,
    this.icon,
    this.selected = false,
    this.teal = false,
    this.onTap,
    this.height = 26,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    Color bg;
    Color fg;
    Color border;
    if (selected) {
      bg = p.isDark ? const Color(0xFFE3EEF7) : const Color(0xFF0D1B2A);
      fg = p.isDark ? const Color(0xFF0D1B2A) : Colors.white;
      border = bg;
    } else if (teal) {
      bg = const Color(0xFFE7FBF5);
      fg = OlTokens.okDeep;
      border = const Color(0xFFCDEFE7);
    } else {
      bg = p.isDark ? const Color(0xFF101F31) : const Color(0xFFF3F8FC);
      fg = p.ink2;
      border = p.chipBorder;
    }
    final mobile = _isMobile(context);
    return MouseRegion(
      cursor: onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: mobile ? OlMobile.chipHeight : height,
          // v2.4：移动端 11（14 会让「全/视频/图片/文档 + 批量」超出 360dp 视口）。
          padding: EdgeInsets.symmetric(horizontal: mobile ? 11 : 10),
          decoration: BoxDecoration(color: bg, border: Border.all(color: border), borderRadius: BorderRadius.circular(99)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                OlIcon(icon!, size: mobile ? 13 : 11, color: fg),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: mobile ? 12 : 10.5,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class OlProgress extends StatelessWidget {
  final double value;
  final double height;
  final bool darkTrack;
  final LinearGradient? gradient;

  const OlProgress({super.key, required this.value, this.height = 6, this.darkTrack = false, this.gradient});

  @override
  Widget build(BuildContext context) {
    final track = darkTrack ? const Color(0x22FFFFFF) : (context.ol.isDark ? const Color(0xFF1A2A3C) : const Color(0xFFEAF0F6));
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: Container(
        height: height,
        color: track,
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: value.clamp(0.0, 1.0).toDouble(),
          child: Container(
            decoration: BoxDecoration(
              gradient: gradient ?? const LinearGradient(colors: [Color(0xFF38BDF8), Color(0xFF2DD4BF)]),
            ),
          ),
        ),
      ),
    );
  }
}

class OlCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final double size;

  const OlCheckbox({super.key, required this.value, this.onChanged, this.size = 13});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: value ? OlTokens.sky600 : (p.isDark ? const Color(0xFF16273C) : Colors.white),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: value ? OlTokens.sky600 : (p.isDark ? const Color(0xFF2A4058) : const Color(0xFFD4E0EC)), width: 1.5),
          ),
          child: value
              ? Center(child: OlIcon('check', size: size * 0.66, color: Colors.white, strokeWidth: 3.2))
              : null,
        ),
      ),
    );
  }
}

class OlKbd extends StatelessWidget {
  final String label;
  const OlKbd(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: p.isDark ? const Color(0xFF16273C) : Colors.white,
        border: Border.all(color: p.isDark ? const Color(0xFF243A52) : const Color(0xFFE3EBF3)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 8.5, height: 1.4, fontFamily: 'monospace', color: p.ink3, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class OlBadge extends StatelessWidget {
  final String label;
  final Color fg;
  final Color bg;
  final Color? border;

  const OlBadge({super.key, required this.label, this.fg = OlTokens.okDeep, this.bg = const Color(0xFFE7FBF5), this.border});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border ?? const Color(0xFFCBEFE6)),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(label, style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, color: fg, letterSpacing: 0.2)),
    );
  }
}

class OlDot extends StatelessWidget {
  final Color color;
  final double size;
  const OlDot({super.key, this.color = OlTokens.ok, this.size = 5});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class OlSkeleton extends StatelessWidget {
  final double height;
  final double? width;
  final double radius;

  const OlSkeleton({super.key, this.height = 10, this.width, this.radius = 4});

  @override
  Widget build(BuildContext context) {
    // v1.0.42：去掉原来的 1.4s 呼吸动画（repeat 反向），改为静态占位色块。
    final base = context.ol.isDark ? const Color(0xFF16273C) : const Color(0xFFE8F0F7);
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class OlEmptyState extends StatelessWidget {
  final String icon;
  final String title;
  final String subtitle;
  final Widget? action;

  const OlEmptyState({super.key, required this.icon, required this.title, required this.subtitle, this.action});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: p.isDark ? const Color(0xFF243A52) : const Color(0xFFC9D9E6), width: 1.5, style: BorderStyle.solid),
            ),
            child: Center(child: OlIcon(icon, size: 24, color: p.isDark ? const Color(0xFF3E5872) : const Color(0xFFB2C6D8))),
          ),
          const SizedBox(height: 14),
          Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: p.ink)),
          const SizedBox(height: 5),
          SizedBox(
            width: 300,
            child: Text(subtitle, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, height: 1.6, color: p.ink3)),
          ),
          if (action != null) ...[const SizedBox(height: 14), action!],
        ],
      ),
    );
  }
}

class OlSectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const OlSectionLabel(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(9, 10, 9, 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: OlText.label.copyWith(color: context.ol.isDark ? const Color(0xFF5E7488) : const Color(0xFFA2B2C2)),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Focus-aware text field used by login, servers and dialogs.
class OlField extends StatefulWidget {
  final TextEditingController controller;
  final String? hint;
  final String icon;
  final bool obscure;
  final Widget? trailing;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputType? keyboardType;
  final bool dense;
  final bool enabled;
  final bool autofocus;
  final int? maxLines;
  final String? prefixText;

  const OlField({
    super.key,
    required this.controller,
    required this.icon,
    this.hint,
    this.obscure = false,
    this.trailing,
    this.onChanged,
    this.onSubmitted,
    this.keyboardType,
    this.dense = false,
    this.enabled = true,
    this.autofocus = false,
    this.maxLines = 1,
    this.prefixText,
  });

  @override
  State<OlField> createState() => _OlFieldState();
}

class _OlFieldState extends State<OlField> {
  late final FocusNode _node = FocusNode()..addListener(_onFocus);

  void _onFocus() => setState(() {});

  @override
  void dispose() {
    _node.removeListener(_onFocus);
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    final focused = _node.hasFocus;
    final height = widget.dense ? 34.0 : 40.0;
    return Container(
      constraints: BoxConstraints(minHeight: height),
      decoration: BoxDecoration(
        color: p.isDark ? const Color(0xFF101F31) : const Color(0xFFFCFDFF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: focused ? const Color(0xFF7DD3FC) : (p.isDark ? const Color(0xFF1C2E43) : const Color(0xFFDFE9F3))),
        boxShadow: focused ? const [BoxShadow(color: Color(0x2438BDF8), blurRadius: 0, spreadRadius: 3)] : null,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 11),
      child: Row(
        children: [
          OlIcon(widget.icon, size: 14, color: focused ? OlTokens.sky600 : (p.isDark ? p.ink3 : const Color(0xFF8FA1B3))),
          const SizedBox(width: 8),
          if (widget.prefixText != null)
            Text(widget.prefixText!, style: TextStyle(fontSize: 10.5, fontFamily: 'monospace', color: p.ink4)),
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _node,
              obscureText: widget.obscure,
              enabled: widget.enabled,
              autofocus: widget.autofocus,
              maxLines: widget.obscure ? 1 : widget.maxLines,
              keyboardType: widget.keyboardType,
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
              cursorColor: OlTokens.sky600,
              cursorWidth: 1.4,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.3,
                fontWeight: FontWeight.w600,
                color: p.ink,
              ),
              decoration: InputDecoration(
                hintText: widget.hint,
                hintStyle: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: p.ink4),
                border: InputBorder.none,
                isCollapsed: true,
                contentPadding: EdgeInsets.symmetric(vertical: widget.dense ? 9 : 12),
              ),
            ),
          ),
          if (widget.trailing != null) widget.trailing!,
        ],
      ),
    );
  }
}

/// Dark glass field for the immersive login boards (W1 / A1).
class OlDarkField extends StatefulWidget {
  final TextEditingController controller;
  final String icon;
  final String hint;
  final bool obscure;
  final Widget? trailing;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputType? keyboardType;
  final double height;

  const OlDarkField({
    super.key,
    required this.controller,
    required this.icon,
    required this.hint,
    this.obscure = false,
    this.trailing,
    this.onChanged,
    this.onSubmitted,
    this.keyboardType,
    this.height = 44,
  });

  @override
  State<OlDarkField> createState() => _OlDarkFieldState();
}

class _OlDarkFieldState extends State<OlDarkField> {
  late final FocusNode _node = FocusNode()..addListener(_onFocus);

  void _onFocus() => setState(() {});

  @override
  void dispose() {
    _node.removeListener(_onFocus);
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = _node.hasFocus;
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: const Color(0x12FFFFFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: focused ? const Color(0x6638BDF8) : const Color(0x1AFFFFFF)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          OlIcon(widget.icon, size: 15, color: focused ? const Color(0xFF7DD3FC) : const Color(0xFF6E879C)),
          const SizedBox(width: 9),
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _node,
              obscureText: widget.obscure,
              keyboardType: widget.keyboardType,
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
              cursorColor: const Color(0xFF7DD3FC),
              cursorWidth: 1.4,
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFFE3EEF7)),
              decoration: InputDecoration(
                hintText: widget.hint,
                hintStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: Color(0xFF6E879C)),
                border: InputBorder.none,
                isCollapsed: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          if (widget.trailing != null) widget.trailing!,
        ],
      ),
    );
  }
}

class OlTooltipText extends StatelessWidget {
  final String text;
  const OlTooltipText(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Tooltip(message: text, child: Text(text, overflow: TextOverflow.ellipsis));
  }
}

/// Copies text without any plugin.
Future<void> copyToClipboard(String text) => Clipboard.setData(ClipboardData(text: text));
