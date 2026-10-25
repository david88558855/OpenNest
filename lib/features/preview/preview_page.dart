import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/frame.dart';
import '../../app/providers.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/openlist_api.dart';
import '../../core/format.dart';
import '../../core/models/api_types.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/ol_controls.dart';
import '../../core/widgets/ol_dialogs.dart';
import '../../core/widgets/ol_icon.dart';
import '../files/file_actions.dart';

/// 预览页：顶栏 + 舞台 + 信息侧栏（对齐效果图 D6）。
class PreviewPage extends ConsumerStatefulWidget {
  const PreviewPage({super.key, required this.path, required this.name});

  final String path;
  final String name;

  @override
  ConsumerState<PreviewPage> createState() => _PreviewPageState();
}

class _PreviewPageState extends ConsumerState<PreviewPage> {
  FileItem? _item;
  String? _url;
  String? _error;
  String? _text;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = ref.read(sessionProvider).api;
    if (api == null) {
      setState(() {
        _loading = false;
        _error = '引擎未就绪';
      });
      return;
    }
    try {
      final item = await api.get(widget.path);
      final url = api.downloadUrl(widget.path, sign: item.sign);
      String? text;
      if (_isText) {
        text = await _fetchText(api, url);
      }
      if (!mounted) return;
      setState(() {
        _item = item;
        _url = url;
        _text = text;
        _loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.friendly;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  Future<String> _fetchText(OpenListApi api, String url) async {
    try {
      final response = await api.dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          headers: const {'Range': 'bytes=0-262143'},
          receiveTimeout: const Duration(seconds: 20),
        ),
      );
      final bytes = response.data;
      if (bytes == null) return '';
      return utf8.decode(Uint8List.fromList(bytes), allowMalformed: true);
    } catch (_) {
      return '（无法读取文本内容）';
    }
  }

  bool get _isImage => kindOf(widget.name, false) == FileKind.image;
  bool get _isText => kindOf(widget.name, false) == FileKind.text;

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    final item = _item;
    final favorites = ref.watch(favoritesProvider);
    final profile = ref.watch(sessionProvider).profile;
    final isFavorite = item != null && favorites.any((e) => e.path == widget.path);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => goBackOrFiles(context),
      },
      child: AppFrame(
        showNav: false,
        handleBack: true,
        child: Column(
          children: [
            // 顶栏
            Container(
              height: 54,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: p.card,
                border: Border(bottom: BorderSide(color: p.line)),
              ),
              child: Row(
                children: [
                  OlBackButton(onTap: () => goBackOrFiles(context)),
                  const SizedBox(width: 10),
                  OlIcon(_iconFor(), size: 15, color: OlTokens.typeImage),
                  const SizedBox(width: 9),
                  Flexible(
                    child: Text(
                      widget.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: p.ink),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OlBadge(
                    label: _isImage ? '图片' : (_isText ? '文本' : '文件'),
                    fg: const Color(0xFF08799F),
                    bg: const Color(0xFFEAF8FE),
                  ),
                  const Spacer(),
                  OlGhostButton(
                    label: '下载',
                    icon: 'download',
                    height: 32,
                    fontSize: 12,
                    onTap: item == null ? null : () => downloadItem(context, ref, item),
                  ),
                  const SizedBox(width: 8),
                  OlGhostButton(
                    label: isFavorite ? '已收藏' : '收藏',
                    icon: 'star',
                    height: 32,
                    fontSize: 12,
                    onTap: item == null
                        ? null
                        : () async {
                            await ref.read(favoritesProvider.notifier).toggle(
                                  profile?.id ?? 'local',
                                  item,
                                  _parentDir(),
                                );
                          },
                  ),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: ColoredBox(
                      color: p.surface,
                      child: _buildStage(),
                    ),
                  ),
                  // 信息侧栏
                  Container(
                    width: 264,
                    decoration: BoxDecoration(
                      color: p.card,
                      border: Border(left: BorderSide(color: p.line)),
                    ),
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                    child: _buildInfo(item),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStage() {
    final p = context.ol;
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: OlTokens.sky600),
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const OlIcon('alert', size: 22, color: OlTokens.dangerDeep),
            const SizedBox(height: 8),
            Text('无法预览', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: p.ink)),
            const SizedBox(height: 4),
            Text(_error!, style: TextStyle(fontSize: 11, color: p.ink3)),
          ],
        ),
      );
    }
    final url = _url;
    if (url == null) {
      return Center(child: Text('没有可用的直链', style: TextStyle(fontSize: 11.5, color: p.ink3)));
    }
    if (_isImage) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: InteractiveViewer(
            maxScale: 4,
            child: Container(
              decoration: BoxDecoration(
                color: p.card,
                borderRadius: BorderRadius.circular(OlTokens.rPanel),
                border: Border.all(color: p.line),
                boxShadow: const [BoxShadow(color: Color(0x140E3A46), blurRadius: 40, offset: Offset(0, 18))],
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.network(
                url,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stack) => Padding(
                  padding: const EdgeInsets.all(40),
                  child: Text('图片加载失败', style: TextStyle(fontSize: 11.5, color: p.ink3)),
                ),
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return const Padding(
                    padding: EdgeInsets.all(40),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: OlTokens.sky600),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
    }
    if (_isText) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(OlTokens.rPanel),
            border: Border.all(color: p.line),
          ),
          child: SingleChildScrollView(
            child: SelectableText(
              _text ?? '',
              style: TextStyle(fontSize: 11.5, height: 1.7, color: p.ink2),
            ),
          ),
        ),
      );
    }
    return Center(
      child: Text('该类型暂不支持内嵌预览，可用「下载」在本机打开。', style: TextStyle(fontSize: 11.5, color: p.ink3)),
    );
  }

  Widget _buildInfo(FileItem? item) {
    final p = context.ol;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '文件信息',
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: p.ink4),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          height: 96,
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: p.line),
          ),
          child: Center(
            child: OlIcon(_iconFor(), size: 34, color: OlTokens.typeImage),
          ),
        ),
        const SizedBox(height: 14),
        _kv('名称', widget.name),
        _kv('类型', _isImage ? '图片' : (_isText ? '文本' : '文件')),
        _kv('大小', item == null ? '—' : formatBytes(item.size)),
        _kv('修改时间', item == null ? '—' : formatDate(item.modified)),
        const SizedBox(height: 10),
        Divider(height: 1, color: p.line2),
        const SizedBox(height: 10),
        _kv('所在路径', widget.path, mono: true),
        _kv('直链参数', '临时签名', mono: true),
        const Spacer(),
        OlGhostButton(
          label: '复制路径',
          icon: 'copy',
          height: 32,
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: widget.path));
            if (context.mounted) olToast(context, '路径已复制');
          },
        ),
      ],
    );
  }

  Widget _kv(String label, String value, {bool mono = false}) {
    final p = context.ol;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: p.ink4)),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: mono ? 10 : 11.5,
              height: 1.4,
              color: p.ink,
            ),
          ),
        ],
      ),
    );
  }

  String _parentDir() {
    final index = widget.path.lastIndexOf('/');
    return index <= 0 ? '/' : widget.path.substring(0, index);
  }

  String _iconFor() {
    if (_isImage) return 'image';
    if (_isText) return 'file-text';
    return 'file';
  }
}
