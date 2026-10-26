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
  bool _busy = false;
  String? _error;
  bool _created = false;

  /// 预填只做一次：用户改过之后重新选驱动不再覆盖。
  bool _prefillApplied = false;

  @override
  void initState() {
    super.initState();
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
    // common + additional 都要建控制器 —— 与 OpenList Web 端一致，
    // 那边的表单同样包含排序、缓存策略、WebDAV 策略等通用字段。
    for (final item in info.formFields) {
      if (item.isBool) {
        _bools[item.name] = item.defaultValue == 'true';
      } else if (item.isSelect && item.options.isNotEmpty) {
        _selects[item.name] = item.defaultValue?.isNotEmpty == true ? item.defaultValue! : item.options.first;
      } else {
        _ctrls[item.name] = TextEditingController(text: item.defaultValue ?? '');
      }
    }
    // 预填必须放在字段控制器重建之后（上面刚 dispose 过 _ctrls）。
    if (!_prefillApplied && widget.initialDriver == info.name && widget.initialPrefill != null) {
      final mapped = mapShareFields(widget.initialPrefill!, info.formFields);
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
      setState(() => _error = '请填写挂载路径');
      return;
    }
    // 挂载路径由用户填的名称派生：OpenList 的 Web 界面里，创建存储时
    // 填的挂载路径就是根文件夹显示的目录名。这里保持同样语义 ——
    // 用户填「本地存储6」，根目录里就显示「本地存储6」，点进去是它的内容。
    final mountPath = mountPathOf(name);
    // 挂载路径必须全局唯一。提交前先查一次已有存储，
    // 直接给出中文提示，不用等引擎回一句英文 SQL 约束错误。
    final existing = ref.read(sourcesProvider).valueOrNull ?? const <StorageSource>[];
    for (final source in existing) {
      if (source.mountPath == mountPath) {
        setState(() => _error = '该挂载路径已存在，请换一个名称');
        return;
      }
    }
    for (final item in info.formFields) {
      if (!item.required) continue;
      final value = item.isBool
          ? '${_bools[item.name] ?? false}'
          : item.isSelect
              ? (_selects[item.name] ?? '')
              : (_ctrls[item.name]?.text ?? '');
      if (value.trim().isEmpty) {
        setState(() => _error = '「${fieldLabelFor(info.name, item.name)}」为必填项');
        return;
      }
    }

    // common 字段（排序、缓存策略、WebDAV 策略……）在引擎里是**存储顶层字段**，
    // additional 字段才进 addition —— 两者不能混在一起提交。
    final addition = <String, dynamic>{};
    final options = <String, dynamic>{};
    for (final item in info.formFields) {
      final isTopLevel = kStorageOptionKeys.contains(item.name);
      if (item.isBool) {
        final value = _bools[item.name] ?? false;
        if (isTopLevel) {
          options[item.name] = value;
        } else {
          addition[item.name] = value;
        }
      } else if (item.isSelect) {
        final value = _selects[item.name] ?? '';
        if (isTopLevel) {
          options[item.name] = value;
        } else {
          addition[item.name] = value;
        }
      } else {
        final raw = _ctrls[item.name]?.text ?? '';
        if (raw.trim().isEmpty) continue;
        final value = coerceItemValue(item, raw);
        if (isTopLevel) {
          options[item.name] = value;
        } else {
          addition[item.name] = value;
        }
      }
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    final source = StorageSource(
      mountPath: mountPath,
      driver: info.name,
      remark: name,
      addition: addition,
      options: options,
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
          // 桌面端不再显示这根顶栏 —— 左侧栏顶部已有「返回」入口，顶栏再放
          // 一份是重复的。窄屏（移动端）没有侧栏，仍需要它。
          if (context.isNarrow) _PageTopBar(onBack: () => goBackOrFiles(context)),
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
            // 0.5.0：侧栏与主区背景对调 —— 侧栏改白底、主区改浅蓝灰，
            // 与文件页、传输页、设置页保持一致。
            color: p.card,
            border: Border(right: BorderSide(color: p.line)),
          ),
          // 0.5.0：返回入口移到左侧栏顶部，与设置页一致（chev-l + 「返回」文字）。
          // 桌面端顶栏已移除；窄屏（移动端）没有侧栏，顶栏的返回箭头仍保留。
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                child: _SideBackRow(onTap: () => goBackOrFiles(context)),
              ),
              Expanded(
                child: _DriverList(
                  names: names,
                  selected: _driver,
                  onSelect: (name) => setState(() => _selectDriver(drivers[name]!)),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ColoredBox(
            // 0.5.0：与侧栏对调，主区改浅蓝灰（表单卡片仍是白底，层次不变）。
            color: p.surface,
            child: info == null
                ? const Center(child: _Hint(text: '从左侧选择一种存储类型'))
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(38, 30, 38, 26),
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
        // 设计稿 D2 的路径感：面包屑「添加存储源 › 驱动名」+ 20/800 标题。
        Row(
          children: [
            Text('添加存储源', style: TextStyle(fontSize: 11.5, color: p.ink3)),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: OlIcon('chev-r', size: 10, color: Color(0xFF9DB2C4), strokeWidth: 3),
            ),
            Flexible(
              child: Text(
                driverLabel(info.name),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: p.ink),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
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
              _textField(
                label: '挂载路径',
                required: true,
                controller: _nameCtrl,
                hint: '根目录中显示的文件夹名称',
              ),
              _textField(
                // 与字段标签（cache_expiration → 缓存过期时间（秒））保持一致
                label: '缓存过期时间（秒）',
                controller: _cacheCtrl,
                hint: '目录列表缓存时间',
                keyboardType: TextInputType.number,
              ),
              for (final item in info.formFields) _buildItem(item, info.name),
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

  /// 渲染一个驱动字段。
  ///
  /// [driver] 传进来是为了让同名字段在不同驱动下显示不同的中文名
  /// （如 `url` 在 OpenList 驱动是「服务器链接地址」，在分享驱动是
  /// 「分享链接」）—— 见 `fieldLabelFor`。
  Widget _buildItem(DriverItem item, String driver) {
    final label = fieldLabelFor(driver, item.name);
    if (item.isBool) {
      return _SwitchField(
        label: label,
        help: fieldHelp(item.help),
        value: _bools[item.name] ?? false,
        onChanged: (value) => setState(() => _bools[item.name] = value),
      );
    }
    if (item.isSelect) {
      return _SelectField(
        label: label,
        help: fieldHelp(item.help),
        value: _selects[item.name] ?? (item.options.isEmpty ? '' : item.options.first),
        options: item.options,
        onChanged: (value) => setState(() => _selects[item.name] = value),
      );
    }
    final controller = _ctrls[item.name];
    if (controller == null) return const SizedBox.shrink();
    return _textField(
      label: label,
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
        // 机密字段强制单行：Flutter 的 TextField 不允许 obscureText 与
        // maxLines > 1 同时使用（会触发断言崩溃）。
        // 引擎里 type=text 的机密字段有 private_key / mail_cookies /
        // accesstoken / qrcode_token / gpg_private_key 五个 —— 选到
        // SFTP / 139Yun 等驱动时原本会直接把表单渲染崩掉。
        maxLines: (multiline && !secret) ? 4 : 1,
        minLines: (multiline && !secret) ? 3 : 1,
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
      // 设计稿 D2：左栏 padding 22/14，项宽 236。
      padding: const EdgeInsets.fromLTRB(14, 22, 14, 20),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          child: Text(
            '存储类型',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: p.ink3, letterSpacing: 1),
          ),
        ),
        for (final group in DriverGroup.values) ...[
          if (names.any((n) => driverGroupOf(n) == group))
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 5),
              child: Text(
                driverGroupLabel(group),
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF9DB2C4),
                  letterSpacing: 0.5,
                ),
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

/// 驱动行（设计稿 D2）：42 高、26×26 圆角图标块、选中白底 + 蓝描边 + 轻阴影 +「✓ 已选」。
class _DriverRow extends StatefulWidget {
  final String name;
  final bool active;
  final VoidCallback onTap;

  const _DriverRow({required this.name, required this.active, required this.onTap});

  @override
  State<_DriverRow> createState() => _DriverRowState();
}

class _DriverRowState extends State<_DriverRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    final tone = _driverTone(widget.name);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: 42,
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: widget.active ? p.card : (_hover ? OlTokens.hoverSoft : Colors.transparent),
            borderRadius: BorderRadius.circular(9),
            // 常驻透明描边：否则选中时加 1px 真边框会让行高从 42 跳到 44。
            border: Border.all(color: widget.active ? p.chipBorder : Colors.transparent),
            boxShadow: widget.active
                ? const [BoxShadow(color: Color(0x1A0EA5E9), blurRadius: 8, offset: Offset(0, 2))]
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(color: tone.bg, borderRadius: BorderRadius.circular(7)),
                child: Center(
                  child: OlIcon(_iconForDriver(widget.name), size: 14, color: tone.fg, strokeWidth: 2),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  driverLabel(widget.name),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: widget.active ? FontWeight.w700 : FontWeight.w400,
                    color: widget.active ? p.ink : p.ink2,
                  ),
                ),
              ),
              if (widget.active) ...[
                const SizedBox(width: 6),
                Text('✓ 已选', style: TextStyle(fontSize: 9.5, color: p.ink4)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 驱动分组的图标配色（设计稿四族）：本地 sky、对象 violet、网盘 amber、远程 teal。
({Color bg, Color fg}) _driverTone(String name) {
  switch (driverGroupOf(name)) {
    case DriverGroup.local:
      return (bg: OlTokens.tileSky, fg: OlTokens.sky600);
    case DriverGroup.object:
      return (bg: OlTokens.tileViolet, fg: OlTokens.violet);
    case DriverGroup.cloud:
      return (bg: OlTokens.tileAmber, fg: OlTokens.typeDoc);
    case DriverGroup.server:
      return (bg: OlTokens.tileTeal, fg: OlTokens.ok);
    case DriverGroup.other:
      return (bg: OlTokens.tileSlate, fg: const Color(0xFF6B7F94));
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
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: p.ink2),
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
      // 弹层内容必须套一层 Material。
      //
      // MaterialApp 在最外层把 DefaultTextStyle 设成了 Flutter 内部那个
      // _errorTextStyle（material/app.dart）：
      //   color 0xD0FF0000 / fontFamily monospace / fontSize 48 /
      //   decoration underline, decorationColor 0xFFFFFF00, style double
      // 它就是「红线 + 黄线」那个 fallback 样式，注释原话是
      // "consider putting your text in a Material widget"。
      // Text 只覆盖自己显式写了的字号/字重/颜色，decoration 与
      // decorationColor 会一路继承 —— 不套 Material 时每行字下面都挂一条黄线。
      // 本文件以外的弹层（_SourceEditDialog / _EnginePasswordDialog /
      // showOlMenu）都套了 Material，只有这里漏了。
      child: Material(
        type: MaterialType.transparency,
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

/// 左侧栏顶部的返回行。
///
/// 规格与设置页 `SettingsSidebar` 的返回项完全一致：chev-l 图标 15px +
/// 文字 12.5/600，padding 9/10、圆角 9。
class _SideBackRow extends StatelessWidget {
  final VoidCallback onTap;

  const _SideBackRow({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          margin: const EdgeInsets.only(bottom: 1),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            children: [
              OlIcon('chev-l', size: 15, color: p.ink3),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '返回',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.ink2),
                ),
              ),
            ],
          ),
        ),
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
