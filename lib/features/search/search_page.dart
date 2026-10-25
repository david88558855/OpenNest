import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/frame.dart';
import '../../app/providers.dart';
import '../../core/api/api_exception.dart';
import '../../core/format.dart';
import '../../core/models/api_types.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/file_widgets.dart';
import '../../core/widgets/ol_controls.dart';
import '../../core/widgets/ol_icon.dart';
import '../files/file_actions.dart';

class SearchPage extends ConsumerStatefulWidget {
  final String initialQuery;
  const SearchPage({super.key, this.initialQuery = ''});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  late final TextEditingController _controller = TextEditingController(text: widget.initialQuery);
  final _focus = FocusNode();
  Timer? _debounce;
  List<FileItem> _results = const [];
  bool _loading = false;
  bool _searched = false;
  String? _error;
  int _scope = 0;
  int _cursor = 0;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focus.requestFocus();
      if (widget.initialQuery.isNotEmpty) _run();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      // v1.0.21：清空必须让在途请求作废（++_seq）并结束 loading，
      // 否则上一个关键字的结果会在清空后回填，搜索框空着却列出一堆结果。
      _seq++;
      setState(() {
        _results = const [];
        _searched = false;
        _error = null;
        _loading = false;
        _cursor = 0;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), _run);
  }

  Future<void> _run() async {
    final keyword = _controller.text.trim();
    final api = ref.read(sessionProvider).api;
    if (api == null) {
      // 未连接时给明确反馈，而不是静默什么都不发生
      if (!mounted) return;
      setState(() {
        _loading = false;
        _searched = true;
        _error = '尚未连接服务器，无法搜索';
      });
      return;
    }
    if (keyword.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    // 设计稿 06：scope 0 = 全部挂载，scope 1 = 当前目录。
    // 本页 _scope 是 UI 语义（0 当前目录 / 1 全部挂载），必须转成接口语义，
    // 否则「当前目录」会搜全盘、「全部挂载」只在根目录里找。
    final currentOnly = _scope == 0;
    final parent = currentOnly ? ref.read(filesProvider).path : '/';
    final seq = ++_seq;
    try {
      // v1.0.22：默认 50 条会把结果静默截断，提到 100（分页仍未做，页面会提示）
      final results = await api.search(
        parent: parent,
        keywords: keyword,
        scope: currentOnly ? 1 : 0,
        perPage: 100,
      );
      // 防抖期间可能有多个请求在飞，只接受最后一次的结果。
      if (!mounted || seq != _seq) return;
      setState(() {
        // 文件夹排前面，与渲染分组保持一致（光标索引用同一份顺序）
        _results = [
          ...results.where((e) => e.isDir),
          ...results.where((e) => !e.isDir),
        ];
        _loading = false;
        _searched = true;
        _cursor = 0;
      });
    } on ApiException catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _loading = false;
        _searched = true;
        _error = e.friendly;
      });
    } catch (e) {
      // v1.0.21：非 ApiException（Socket / Timeout / 解析异常）之前没有任何兜底，
      // loading 会永久卡住，页面再也搜不动。
      if (!mounted || seq != _seq) return;
      setState(() {
        _loading = false;
        _searched = true;
        _error = '搜索失败：$e';
      });
    }
  }

  Future<void> _open(FileItem item) async {
    if (item.isDir) {
      final path = item.parent ?? joinPath(ref.read(filesProvider).path, item.name);
      await ref.read(filesProvider.notifier).open(path);
      // 带上 path 回到文件页，保证跨目录定位后地址栏与列表一致。
      if (mounted) context.go('/files?path=${Uri.encodeComponent(path)}');
    } else {
      await openItem(context, ref, item);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      context.go('/files');
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown && _results.isNotEmpty) {
      setState(() => _cursor = (_cursor + 1).clamp(0, _results.length - 1).toInt());
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp && _results.isNotEmpty) {
      setState(() => _cursor = (_cursor - 1).clamp(0, _results.length - 1).toInt());
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter && _results.isNotEmpty) {
      _open(_results[_cursor]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 900;
    return AppFrame(
      showNav: false,
      // v2.5：系统返回先回文件页（搜索是从文件页 go 过来的），再按才退出应用。
      handleBack: true,
      onBack: () async {
        context.go('/files');
        return true;
      },
      child: Focus(
        onKeyEvent: _onKey,
        child: narrow ? _buildMobile(context) : _buildDesktop(context),
      ),
    );
  }

  Widget _buildDesktop(BuildContext context) {
    final p = context.ol;
    return Container(
      color: const Color(0x26091424),
      alignment: Alignment.topCenter,
      padding: const EdgeInsets.only(top: 74),
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxHeight: 560),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: p.line),
          boxShadow: const [BoxShadow(color: Color(0x66061321), blurRadius: 60, offset: Offset(0, 30))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.line2))),
              child: Row(
                children: [
                  const OlIcon('search', size: 18, color: OlTokens.sky600),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focus,
                      onChanged: _onChanged,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.ink),
                      cursorColor: OlTokens.sky600,
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        isCollapsed: true,
                        hintText: '搜索文件名，支持跨挂载点',
                        hintStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: p.ink4),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OlSeg<int>(
                    items: const [OlSegItem(0, '当前目录'), OlSegItem(1, '全部挂载')],
                    value: _scope,
                    onChanged: (v) {
                      setState(() => _scope = v);
                      _run();
                    },
                    height: 22,
                  ),
                  const SizedBox(width: 8),
                  OlKbd('Esc'),
                ],
              ),
            ),
            Flexible(child: _buildResults(context, compact: false)),
            Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(color: p.surfaceAlt, border: Border(top: BorderSide(color: p.line2))),
              child: Row(
                children: [
                  _Hint(kbd: '↑↓', label: '选择'),
                  const SizedBox(width: 14),
                  _Hint(kbd: 'Enter', label: '打开'),
                  const SizedBox(width: 14),
                  _Hint(kbd: 'Esc', label: '关闭'),
                  const Spacer(),
                  Text(
                    _searched ? '${_results.length} 个结果' : '输入关键词开始搜索',
                    style: TextStyle(fontSize: 9.5, color: p.ink4),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobile(BuildContext context) {
    final p = context.ol;
    return Column(
      children: [
        Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: [
              GestureDetector(onTap: () => context.go('/files'), child: OlIcon('chev-l', size: 18, color: p.ink3)),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: p.surfaceAlt,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: p.line2),
                  ),
                  child: Row(
                    children: [
                      const OlIcon('search', size: 16, color: OlTokens.sky600),
                      const SizedBox(width: 9),
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          focusNode: _focus,
                          onChanged: _onChanged,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.ink),
                          cursorColor: OlTokens.sky600,
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            isCollapsed: true,
                            hintText: '搜索文件名',
                            hintStyle: TextStyle(fontSize: 12, color: p.ink4),
                          ),
                        ),
                      ),
                      if (_controller.text.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            _controller.clear();
                            _onChanged('');
                          },
                          child: Container(
                            width: 18,
                            height: 18,
                            decoration: const BoxDecoration(color: Color(0xFFDCE8F2), shape: BoxShape.circle),
                            child: const Center(child: OlIcon('x', size: 10, color: Color(0xFF7C8FA3))),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: [
              OlChip(label: '当前目录', selected: _scope == 0, onTap: () {
                setState(() => _scope = 0);
                _run();
              }),
              const SizedBox(width: 6),
              OlChip(label: '全部挂载', selected: _scope == 1, onTap: () {
                setState(() => _scope = 1);
                _run();
              }),
              const Spacer(),
              Text(_searched ? '${_results.length} 个结果' : '', style: TextStyle(fontSize: 9, color: p.ink4)),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Expanded(child: _buildResults(context, compact: true)),
      ],
    );
  }

  Widget _buildResults(BuildContext context, {required bool compact}) {
    final p = context.ol;
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const OlIcon('alert', size: 20, color: OlTokens.dangerDeep),
            const SizedBox(height: 8),
            Text(_error!, textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: p.ink3)),
            const SizedBox(height: 10),
            OlGhostButton(label: '重试', icon: 'refresh', onTap: _run),
          ],
        ),
      );
    }
    if (!_searched) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('搜索范围', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1, color: p.ink4)),
            const SizedBox(height: 6),
            _Suggestion(label: ref.read(filesProvider).path, icon: 'folder', onTap: () {
              _controller.text = baseName(ref.read(filesProvider).path);
              _onChanged(_controller.text);
            }),
            _Suggestion(label: 'mp4', icon: 'film', onTap: () {
              _controller.text = 'mp4';
              _onChanged('mp4');
            }),
            _Suggestion(label: 'jpg', icon: 'image', onTap: () {
              _controller.text = 'jpg';
              _onChanged('jpg');
            }),
            const SizedBox(height: 10),
            Text(
              '服务端未建立索引时，搜索可能返回空结果。可在网页端「索引」中开启。',
              style: TextStyle(fontSize: 9, height: 1.6, color: p.ink4),
            ),
          ],
        ),
      );
    }
    if (_results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(28),
        child: OlEmptyState(
          icon: 'search',
          title: '没有匹配的文件',
          subtitle: '换个关键词，或把范围切到「全部挂载」。若服务端未建立索引，跨盘搜索会降级为空结果。',
        ),
      );
    }

    // v1.0.23：结果在写入时就按「文件夹 → 文件」排好，`_results` 与渲染顺序、
    // 键盘光标三者一致。之前是渲染时临时分组、光标按原始顺序，导致 ↓ 跳到
    // 视觉不相邻的行，Enter 打开的也不是高亮那条；同名文件还会同时高亮。
    final dirs = _results.where((e) => e.isDir).toList();
    final files = _results.where((e) => !e.isDir).toList();

    return ListView(
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 8, vertical: 8),
      children: [
        if (dirs.isNotEmpty) _GroupLabel('文件夹 · ${dirs.length}'),
        for (var i = 0; i < dirs.length; i++)
          _ResultRow(item: dirs[i], selected: _cursor == i, onTap: () => _open(dirs[i])),
        if (files.isNotEmpty) _GroupLabel('文件 · ${files.length}'),
        for (var j = 0; j < files.length; j++)
          _ResultRow(
            item: files[j],
            selected: _cursor == dirs.length + j,
            onTap: () => _open(files[j]),
          ),
      ],
    );
  }
}

class _GroupLabel extends StatelessWidget {
  final String text;
  const _GroupLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
      child: Text(text.toUpperCase(), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1, color: context.ol.ink4)),
    );
  }
}

class _ResultRow extends StatelessWidget {
  final FileItem item;
  final bool selected;
  final VoidCallback onTap;

  const _ResultRow({required this.item, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    final path = item.parent ?? '';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(color: selected ? p.navOnBg : Colors.transparent, borderRadius: BorderRadius.circular(9)),
        child: Row(
          children: [
            FileGlyph(item: item, size: 28, radius: 8, iconSize: 14),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: p.ink)),
                  const SizedBox(height: 1),
                  Row(
                    children: [
                      OlIcon('folder', size: 11, color: p.ink4),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          path.isEmpty ? '/' : path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 9.5, color: p.ink4),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(item.isDir ? '文件夹' : formatBytes(item.size), style: TextStyle(fontSize: 9, color: p.ink4)),
            const SizedBox(width: 6),
            OlIcon('chev-r', size: 12, color: p.ink4),
          ],
        ),
      ),
    );
  }
}

class _Suggestion extends StatelessWidget {
  final String label;
  final String icon;
  final VoidCallback onTap;

  const _Suggestion({required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(7),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
        child: Row(
          children: [
            OlIcon(icon, size: 13, color: p.ink4),
            const SizedBox(width: 9),
            Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: p.ink2))),
            Text('范围', style: TextStyle(fontSize: 9, color: p.ink4)),
          ],
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  final String kbd;
  final String label;
  const _Hint({required this.kbd, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        OlKbd(kbd),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 9, color: context.ol.ink4)),
      ],
    );
  }
}
