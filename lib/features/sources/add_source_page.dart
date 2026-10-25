import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/frame.dart';
import '../../app/providers.dart';
import '../../core/i18n/zh.dart';
import '../../core/models/driver_schema.dart';
import '../../core/models/storage_source.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/ol_controls.dart';
import '../../core/widgets/ol_dialogs.dart';
import '../../core/widgets/ol_icon.dart';
import 'share_link.dart';
import 'sources_controller.dart';

/// 添加存储源：左侧驱动分组，右侧由驱动字段定义生成的表单。
class AddSourcePage extends ConsumerStatefulWidget {
  const AddSourcePage({super.key, this.initialDriver, this.initialPrefill});

  final String? initialDriver;

  /// 分享链接识别出的通用字段（share_id / share_pwd / url）。
  /// 选中驱动后按字段别名映射进表单，用户补齐剩余字段即可保存。
  final Map<String, String>? initialPrefill;

  @override
  ConsumerState<AddSourcePage> createState() => _AddSourcePageState();
}

class _AddSourcePageState extends ConsumerState<AddSourcePage> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _cacheCtrl = TextEditingController(text: '30');
  final Map<String, TextEditingController> _ctrls = {};
  final Map<String, bool> _bools = {};
  final Map<String, String> _selects = {};

  String? _driver;
  String _mountPath = '';
  bool _busy = false;
  String? _error;
  bool _created = false;

  /// 预填只做一次：用户改过之后重新选驱动不再覆盖。
  bool _prefillApplied = false;

  @override
  void initState() {
    super.initState();
    _mountPath = _newMountPath();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _cacheCtrl.dispose();
    for (final controller in _ctrls.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String _newMountPath() {
    final random = Random.secure();
    final suffix = List.generate(8, (_) => random.nextInt(16).toRadixString(16)).join();
    return '/s_$suffix';
  }

  DriverInfo? _info(Map<String, DriverInfo> catalog) {
    final name = _driver;
    if (name == null) return null;
    return catalog[name];
  }

  void _selectDriver(DriverInfo info, {bool force = false}) {
    if (_driver == info.name && !force) return;
    for (final controller in _ctrls.values) {
      controller.dispose();
    }
    _ctrls.clear();
    _bools.clear();
    _selects.clear();
    _driver = info.name;
    _error = null;
    _created = false;
    _mountPath = _newMountPath();
    for (final item in info.additional) {
      if (item.isBool) {
        _bools[item.name] = item.defaultValue == 'true';
      } else if (item.isSelect && item.options.isNotEmpty) {
        _selects[item.name] = item.defaultValue?.isNotEmpty == true ? item.defaultValue! : item.options.first;
      } else {
        _ctrls[item.name] = TextEditingController(text: item.defaultValue ?? '');
      }
    }
    if (_nameCtrl.text.trim().isEmpty) {
      _nameCtrl.text = driverLabel(info.name);
    }
    // 预填必须放在字段控制器重建之后（上面刚 dispose 过 _ctrls）。
    if (!_prefillApplied && widget.initialDriver == info.name && widget.initialPrefill != null) {
      final mapped = mapShareFields(widget.initialPrefill!, info.additional);
      mapped.forEach((name, value) {
        final controller = _ctrls[name];
        if (controller != null && controller.text.trim().isEmpty) controller.text = value;
      });
      _prefillApplied = true;
    }
  }

  Future<void> _submit(DriverInfo info) async {
    if (_busy) return;
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '请填写显示名称');
      return;
    }
    for (final item in info.additional) {
      if (!item.required) continue;
      final value = item.isBool
          ? '${_bools[item.name] ?? false}'
          : item.isSelect
              ? (_selects[item.name] ?? '')
              : (_ctrls[item.name]?.text ?? '');
      if (value.trim().isEmpty) {
        setState(() => _error = '「${fieldLabel(item.name)}」为必填项');
        return;
      }
    }

    final addition = <String, dynamic>{};
    for (final item in info.additional) {
      if (item.isBool) {
        addition[item.name] = _bools[item.name] ?? false;
      } else if (item.isSelect) {
        addition[item.name] = _selects[item.name] ?? '';
      } else {
        final raw = _ctrls[item.name]?.text ?? '';
        if (raw.trim().isNotEmpty) addition[item.name] = coerceItemValue(item, raw);
      }
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    final source = StorageSource(
      mountPath: _mountPath,
      driver: info.name,
      remark: name,
      addition: addition,
      cacheExpiration: int.tryParse(_cacheCtrl.text.trim()) ?? 30,
    );
    final error = await ref.read(sourceActionsProvider).create(source);
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _busy = false;
        _error = error;
      });
      return;
    }
    setState(() {
      _busy = false;
      _created = true;
    });
    try {
      await ref.read(filesProvider.notifier).refresh();
    } catch (_) {}
    if (!mounted) return;
    context.go('/files');
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(driverCatalogProvider);
    return AppFrame(
      showNav: false,
      handleBack: true,
      child: Column(
        children: [
          // 0.5.0：整页只被 push 进来，此前「选类型 / 加载 / 失败」三态都没有返回入口。
          _PageTopBar(onBack: () => goBackOrFiles(context)),
          Expanded(
            child: catalog.when(
              loading: () => const Center(child: _Loading(text: '正在读取驱动列表')),
              error: (error, _) => _Failed(message: '$error'),
              data: (drivers) {
                if (drivers.isEmpty) {
                  return const _Failed(message: '引擎没有返回任何驱动');
                }
                if (widget.initialDriver != null && _driver == null) {
                  final info = drivers[widget.initialDriver];
                  if (info != null) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) setState(() => _selectDriver(info));
                    });
                  }
                }
                final sorted = drivers.keys.toList()..sort();
                return context.isNarrow
                    ? _buildMobile(drivers, sorted)
                    : _buildDesktop(drivers, sorted);
              },
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ 桌面

  Widget _buildDesktop(Map<String, DriverInfo> drivers, List<String> names) {
    final p = context.ol;
    final info = _info(drivers);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 264,
          decoration: BoxDecoration(
            color: p.surface,
            border: Border(right: BorderSide(color: p.line)),
          ),
          child: _DriverList(
            names: names,
            selected: _driver,
            onSelect: (name) => setState(() => _selectDriver(drivers[name]!)),
          ),
        ),
        Expanded(
          child: ColoredBox(
            color: p.card,
            child: info == null
                ? const Center(child: _Hint(text: '从左侧选择一种存储类型'))
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(38, 26, 38, 30),
                    child: _buildForm(info),
                  ),
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------ 移动

  Widget _buildMobile(Map<String, DriverInfo> drivers, List<String> names) {
    final p = context.ol;
    final info = _info(drivers);
    return ColoredBox(
      color: p.card,
      child: info == null
          ? ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
                Text('添加存储源', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: p.ink)),
                const SizedBox(height: 4),
                Text('选择一种存储类型', style: TextStyle(fontSize: 11.5, color: p.ink3)),
                const SizedBox(height: 14),
                for (final group in DriverGroup.values)
                  if (names.any((n) => driverGroupOf(n) == group)) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 6),
                      child: Text(
                        driverGroupLabel(group),
                        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: p.ink4, letterSpacing: 0.6),
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final name in names.where((n) => driverGroupOf(n) == group))
                          SizedBox(
                            width: (MediaQuery.sizeOf(context).width - 40) / 2,
                            child: _MobileDriverCard(
                              name: name,
                              onTap: () => setState(() => _selectDriver(drivers[name]!)),
                            ),
                          ),
                      ],
                    ),
                  ],
              ],
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 96),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      OlGhostButton(
                        label: '换类型',
                        icon: 'chev-l',
                        height: 30,
                        onTap: () => setState(() => _driver = null),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          driverLabel(info.name),
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: p.ink),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _buildForm(info),
                ],
              ),
            ),
    );
  }

  // ------------------------------------------------------------------ 表单

  Widget _buildForm(DriverInfo info) {
    final p = context.ol;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('连接${driverLabel(info.name)}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: p.ink)),
        const SizedBox(height: 6),
        Text(
          '字段由驱动自身定义生成，共 ${info.additional.length} 项',
          style: TextStyle(fontSize: 11.5, color: p.ink3),
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final twoColumn = constraints.maxWidth > 520;
            final fields = <Widget>[
              _textField(label: '显示名称', required: true, controller: _nameCtrl, hint: '侧边栏中展示的名称'),
              _textField(
                label: '缓存时长（秒）',
                controller: _cacheCtrl,
                hint: '目录列表缓存时间',
                keyboardType: TextInputType.number,
              ),
              for (final item in info.additional) _buildItem(item),
            ];
            if (!twoColumn) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [for (final f in fields) Padding(padding: const EdgeInsets.only(bottom: 14), child: f)],
              );
            }
            final children = <Widget>[];
            for (var i = 0; i < fields.length; i += 2) {
              children.add(
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: fields[i]),
                      const SizedBox(width: 14),
                      Expanded(child: i + 1 < fields.length ? fields[i + 1] : const SizedBox.shrink()),
                    ],
                  ),
                ),
              );
            }
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
          },
        ),
        if (_error != null) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: OlTokens.dangerSurface,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: OlTokens.dangerBorder),
            ),
            child: Text(_error!, style: const TextStyle(fontSize: 10.5, height: 1.5, color: OlTokens.dangerInk)),
          ),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            OlPrimaryButton(
              label: _busy ? '正在测试并保存…' : '测试并保存',
              icon: 'check',
              height: 38,
              onTap: _busy ? null : () => _submit(info),
            ),
            const SizedBox(width: 10),
            const Spacer(),
            if (_created)
              Text('已保存', style: TextStyle(fontSize: 10.5, color: OlTokens.ok)),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          '保存时会先建临时挂载并列出根目录，连不通就自动回滚；凭据保存在本机引擎数据库中。',
          style: TextStyle(fontSize: 10, height: 1.6, color: p.ink4),
        ),
      ],
    );
  }

  Widget _buildItem(DriverItem item) {
    if (item.isBool) {
      return _SwitchField(
        label: fieldLabel(item.name),
        help: fieldHelp(item.help),
        value: _bools[item.name] ?? false,
        onChanged: (value) => setState(() => _bools[item.name] = value),
      );
    }
    if (item.isSelect) {
      return _SelectField(
        label: fieldLabel(item.name),
        help: fieldHelp(item.help),
        value: _selects[item.name] ?? (item.options.isEmpty ? '' : item.options.first),
        options: item.options,
        onChanged: (value) => setState(() => _selects[item.name] = value),
      );
    }
    final controller = _ctrls[item.name];
    if (controller == null) return const SizedBox.shrink();
    return _textField(
      label: fieldLabel(item.name),
      required: item.required,
      controller: controller,
      hint: fieldHelp(item.help),
      secret: item.isSecret,
      multiline: item.isMultiline,
      keyboardType: item.isNumber ? TextInputType.number : null,
    );
  }

  Widget _textField({
    required String label,
    required TextEditingController controller,
    bool required = false,
    bool secret = false,
    bool multiline = false,
    String? hint,
    TextInputType? keyboardType,
  }) {
    return _FieldShell(
      label: label,
      required: required,
      secret: secret,
      hint: hint,
      child: TextField(
        controller: controller,
        obscureText: secret,
        maxLines: multiline ? 4 : 1,
        minLines: multiline ? 3 : 1,
        keyboardType: keyboardType,
        style: TextStyle(fontSize: 12.5, color: context.ol.ink),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          hintText: hint,
          hintStyle: TextStyle(fontSize: 11, color: context.ol.ink4),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(OlTokens.rField),
            borderSide: BorderSide(color: context.ol.fieldBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(OlTokens.rField),
            borderSide: BorderSide(color: context.ol.fieldBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(OlTokens.rField),
            borderSide: const BorderSide(color: OlTokens.sky),
          ),
        ),
      ),
    );
  }
}

// --------------------------------------------------------------------- 零件

class _DriverList extends StatelessWidget {
  final List<String> names;
  final String? selected;
  final ValueChanged<String> onSelect;

  const _DriverList({required this.names, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 20),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
          child: Text(
            '存储类型',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: p.ink4, letterSpacing: 1),
          ),
        ),
        for (final group in DriverGroup.values) ...[
          if (names.any((n) => driverGroupOf(n) == group))
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
              child: Text(
                driverGroupLabel(group),
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: p.ink4),
              ),
            ),
          for (final name in names.where((n) => driverGroupOf(n) == group))
            _DriverRow(
              name: name,
              active: name == selected,
              onTap: () => onSelect(name),
            ),
        ],
      ],
    );
  }
}

class _DriverRow extends StatelessWidget {
  final String name;
  final bool active;
  final VoidCallback onTap;

  const _DriverRow({required this.name, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(9),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: active ? p.card : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: active ? p.fieldBorder : Colors.transparent),
            ),
            child: Row(
              children: [
                OlIcon(_iconForDriver(name), size: 14, color: active ? OlTokens.sky600 : p.ink3),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    driverLabel(name),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      color: active ? p.ink : p.ink2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileDriverCard extends StatelessWidget {
  final String name;
  final VoidCallback onTap;

  const _MobileDriverCard({required this.name, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: p.line),
          ),
          child: Row(
            children: [
              OlIcon(_iconForDriver(name), size: 16, color: OlTokens.sky600),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  driverLabel(name),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.ink),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FieldShell extends StatelessWidget {
  final String label;
  final bool required;
  final bool secret;
  final String? hint;
  final Widget child;

  const _FieldShell({
    required this.label,
    required this.child,
    this.required = false,
    this.secret = false,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: p.ink2),
              ),
            ),
            if (required)
              const Padding(
                padding: EdgeInsets.only(left: 3),
                child: Text('*', style: TextStyle(fontSize: 11, color: OlTokens.dangerDeep)),
              ),
            if (secret) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  '仅本机',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Color(0xFFB7791F)),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 5),
        child,
        if (hint != null && hint!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              hint!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 9.5, height: 1.4, color: p.ink4),
            ),
          ),
      ],
    );
  }
}

class _SwitchField extends StatelessWidget {
  final String label;
  final String? help;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchField({required this.label, required this.value, required this.onChanged, this.help});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: p.fieldBg,
        borderRadius: BorderRadius.circular(OlTokens.rField),
        border: Border.all(color: p.fieldBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: p.ink2)),
                if (help != null && help!.isNotEmpty)
                  Text(help!, style: TextStyle(fontSize: 9.5, color: p.ink4)),
              ],
            ),
          ),
          OlSwitch(value: value, onChanged: onChanged, small: true),
        ],
      ),
    );
  }
}

class _SelectField extends StatelessWidget {
  final String label;
  final String? help;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  const _SelectField({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.help,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return _FieldShell(
      label: label,
      hint: help,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(OlTokens.rField),
          onTap: () async {
            final picked = await showOlDialog<String>(
              context: context,
              builder: (ctx) => _OptionDialog(title: label, options: options, current: value),
            );
            if (picked != null) onChanged(picked);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: p.fieldBg,
              borderRadius: BorderRadius.circular(OlTokens.rField),
              border: Border.all(color: p.fieldBorder),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    optionLabel(value),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: p.ink),
                  ),
                ),
                OlIcon('chev-d', size: 12, color: p.ink4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OptionDialog extends StatelessWidget {
  final String title;
  final List<String> options;
  final String current;

  const _OptionDialog({required this.title, required this.options, required this.current});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Center(
      child: Container(
        width: 380,
        constraints: const BoxConstraints(maxHeight: 460),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: p.line),
          boxShadow: const [BoxShadow(color: Color(0x330B1622), blurRadius: 40, offset: Offset(0, 18))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: p.ink)),
            const SizedBox(height: 10),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final option in options)
                    InkWell(
                      onTap: () => Navigator.of(context).pop(option),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                        decoration: BoxDecoration(
                          color: option == current ? p.rowSel : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                optionLabel(option),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: option == current ? FontWeight.w700 : FontWeight.w500,
                                  color: p.ink,
                                ),
                              ),
                            ),
                            if (option == current) const OlIcon('check', size: 13, color: OlTokens.ok),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  final String text;
  const _Hint({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(text, style: TextStyle(fontSize: 12, color: context.ol.ink3));
  }
}

/// 添加存储源页面级顶栏：返回 + 标题 + 取消。
///
/// 设计稿 D2 没有这一条（稿面靠窗口标题栏），但整页只被 push 进来，
/// 没有返回会让用户卡在「选类型 / 加载失败」这两态里出不去。
class _PageTopBar extends StatelessWidget {
  final VoidCallback onBack;

  const _PageTopBar({required this.onBack});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: p.card,
        border: Border(bottom: BorderSide(color: p.line)),
      ),
      child: Row(
        children: [
          OlBackButton(onTap: onBack),
          const SizedBox(width: 12),
          if (!context.isNarrow)
            Expanded(
              child: Text(
                '添加存储源',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: p.ink),
              ),
            )
          else
            const Spacer(),
          OlGhostButton(label: '取消', height: 32, fontSize: 12, onTap: onBack),
        ],
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  final String text;
  const _Loading({required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: OlTokens.sky600),
          ),
          const SizedBox(height: 10),
          Text(text, style: TextStyle(fontSize: 11.5, color: context.ol.ink3)),
        ],
      ),
    );
  }
}

class _Failed extends StatelessWidget {
  final String message;
  const _Failed({required this.message});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const OlIcon('alert', size: 22, color: OlTokens.dangerDeep),
            const SizedBox(height: 10),
            Text('无法读取驱动列表', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: p.ink)),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: p.ink3)),
          ],
        ),
      ),
    );
  }
}

String _iconForDriver(String name) {
  switch (driverGroupOf(name)) {
    case DriverGroup.local:
      return name == 'Local' ? 'hard-drive' : 'server';
    case DriverGroup.object:
      return 'layers';
    case DriverGroup.cloud:
      return 'cloud';
    case DriverGroup.server:
      return 'globe';
    case DriverGroup.other:
      return 'folder';
  }
}
