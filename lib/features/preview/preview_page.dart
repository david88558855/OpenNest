import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/frame.dart';
import '../../app/providers.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/openlist_api.dart';
import '../../core/format.dart';
import '../../core/i18n/zh.dart';
import '../../core/models/api_types.dart';
import '../../core/models/storage_source.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/ol_controls.dart';
import '../../core/widgets/ol_dialogs.dart';
import '../../core/widgets/ol_icon.dart';
import '../files/file_actions.dart';
import '../sources/sources_controller.dart';

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
                  // 设计稿 D6：徽标固定「快速预览」。
                  OlBadge(
                    label: '快速预览',
                    fg: const Color(0xFF08799F),
                    bg: const Color(0xFFEAF8FE),
                    radius: 99,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    fontSize: 9.5,
                  ),
                  const Spacer(),
                  OlGhostButton(
                    label: '下载',
                    icon: 'download',
                    height: 32,
                    fontSize: 12,
                    horizontalPadding: 14,
                    fgColor: p.ink,
                    onTap: item == null ? null : () => downloadItem(context, ref, item),
                  ),
                  const SizedBox(width: 8),
                  OlGhostButton(
                    label: '打开方式',
                    icon: 'link',
                    height: 32,
                    fontSize: 12,
                    horizontalPadding: 14,
                    fgColor: p.ink,
                    onTap: item == null ? null : () => _openWith(context, item),
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
                    padding: const EdgeInsets.all(20),
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
      // 设计稿 D6：舞台 padding 26，画布 640×420、圆角 14、白底描边 + 阴影，
      // 顶部 38 高画布头（三个圆点 + 文件名 · 尺寸）。
      return Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(26),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640, maxHeight: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: p.card,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                        border: Border.all(color: p.line),
                      ),
                      child: Row(
                        children: [
                          _Dot(color: const Color(0xFFF87C6E)),
                          const SizedBox(width: 7),
                          _Dot(color: const Color(0xFFF9C25B)),
                          const SizedBox(width: 7),
                          _Dot(color: const Color(0xFF5FD08A)),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              widget.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 10.5, color: p.ink4),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: p.card,
                          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
                          border: Border.all(color: p.line),
                          boxShadow: const [
                            BoxShadow(color: Color(0x240E3A46), blurRadius: 50, offset: Offset(0, 18)),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: InteractiveViewer(
                          maxScale: 4,
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
                  ],
                ),
              ),
            ),
          ),
          // 快捷键提示条（设计稿 D6 `.hint`）：绝对定位底部居中。
          Positioned(
            left: 0,
            right: 0,
            bottom: 14,
            child: Center(child: _ShortcutHint()),
          ),
        ],
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

  /// 信息侧栏（设计稿 D6 `.info`）：padding 20、gap 14、白底、可滚动，
  /// 底部两按钮吸底。稿面内容会溢出约 50px，所以滚动区与吸底区必须分离。
  Widget _buildInfo(FileItem? item) {
    final p = context.ol;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '文件信息',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: p.ink4, letterSpacing: 1),
                ),
                const SizedBox(height: 14),
                // 缩略卡 120 高、渐变底 + 描边（设计稿 `.preview-box`）
                Container(
                  width: double.infinity,
                  height: 120,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFDDF6F2), Color(0xFFBDE7FA)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFD8ECF8)),
                  ),
                  child: Center(
                    child: OlIcon(_iconFor(), size: 46, color: const Color(0xFF0E9F6E), strokeWidth: 1.4),
                  ),
                ),
                const SizedBox(height: 14),
                _kv('名称', widget.name),
                _kv('类型', _typeText()),
                _kv('大小', item == null ? '—' : formatBytes(item.size)),
                _kv('修改时间', item == null ? '—' : formatDate(item.modified)),
                const SizedBox(height: 14),
                Container(height: 1, color: p.line2),
                const SizedBox(height: 14),
                _kv('所在存储源', _sourceText()),
                _kv('路径', widget.path, mono: true),
                _kv('直链', '/d${widget.path}?sign=…', mono: true),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        // 吸底动作区（设计稿 `.acts`）：主按钮 + 次按钮竖排。
        OlPrimaryButton(
          label: '下载到本地',
          icon: 'download',
          height: 32,
          expand: true,
          fontSize: 12,
          onTap: item == null ? null : () => downloadItem(context, ref, item),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OlGhostButton(
            label: '复制路径',
            icon: 'copy',
            height: 32,
            fontSize: 12,
            fgColor: p.ink,
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: widget.path));
              if (context.mounted) olToast(context, '路径已复制');
            },
          ),
        ),
      ],
    );
  }

  /// 类型文案：图片带扩展名，文本按扩展名细分。
  String _typeText() {
    if (_isImage) {
      final ext = extensionOf(widget.name);
      return ext.isEmpty ? '图片' : '${ext.toUpperCase()} 图片';
    }
    if (_isText) return '文本文件';
    return '文件';
  }

  /// 所在存储源：取当前路径所属的挂载点与协议。
  String _sourceText() {
    final mount = _mountPath();
    if (mount.isEmpty) return '本机引擎';
    final sources = ref.read(sourcesProvider).valueOrNull ?? const <StorageSource>[];
    for (final source in sources) {
      if (mount == source.mountPath) {
        return '${source.displayName} · ${driverShortTag(source.driver)}';
      }
    }
    return mount;
  }

  /// 当前路径所属的挂载点（第一个 '/xxx' 段）。
  String _mountPath() {
    final segments = widget.path.split('/').where((e) => e.isNotEmpty).toList();
    if (segments.isEmpty) return '';
    return '/${segments.first}';
  }

  /// 「打开方式」：把直链交给系统默认程序。
  Future<void> _openWith(BuildContext context, FileItem item) async {
    final url = _url;
    if (url == null) return;
    try {
      // launchUrl 失败时返回 false 而不抛异常 —— 以前返回值没看，
      // 系统没有对应处理器时点「打开方式」完全没反馈。
      final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        olToast(context, '系统里没有能打开这种文件的应用', error: true);
      }
    } catch (_) {
      if (context.mounted) olToast(context, '无法打开外部程序', error: true);
    }
  }

  Widget _kv(String label, String value, {bool mono = false}) {
    final p = context.ol;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: p.ink4)),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              fontSize: mono ? 11 : 12,
              height: 1.4,
              fontWeight: mono ? FontWeight.w400 : FontWeight.w600,
              color: mono ? p.ink2 : p.ink,
            ),
          ),
        ],
      ),
    );
  }

  String _iconFor() {
    if (_isImage) return 'image';
    if (_isText) return 'file-text';
    return 'file';
  }
}


/// 画布头的小圆点（设计稿 `.cd`）：9×9。
class _Dot extends StatelessWidget {
  final Color color;

  const _Dot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// 快捷键提示条（设计稿 D6 `.hint`）：深色半透明胶囊，底部居中。
class _ShortcutHint extends StatelessWidget {
  const _ShortcutHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xD21D1B2A),
        borderRadius: BorderRadius.circular(99),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _HintKey('空格'),
          SizedBox(width: 4),
          Text('关闭', style: TextStyle(fontSize: 11, color: Colors.white)),
          SizedBox(width: 12),
          Text('流式加载 · 无需下载完整文件', style: TextStyle(fontSize: 11, color: Colors.white)),
        ],
      ),
    );
  }
}

/// 提示条里的键帽。
class _HintKey extends StatelessWidget {
  final String label;

  const _HintKey(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: const Color(0x2EFFFFFF),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(label, style: const TextStyle(fontSize: 10, color: Colors.white)),
    );
  }
}
