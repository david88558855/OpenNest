import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import '../../app/providers.dart';
import '../../core/api/api_exception.dart';
import '../../core/format.dart';
import '../../core/models/api_types.dart';
import '../../core/storage/server_store.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/ol_controls.dart';
import '../../core/widgets/ol_dialogs.dart';
import '../../core/widgets/ol_icon.dart';
import '../files/files_controller.dart';

/// 播放页（效果图 D7）：浅色外壳 + 深色视频舞台 + 白色控制条 + 280 播放列表侧栏。
///
/// 舞台保持深色是刻意的：视频周围需要低亮度，浅色背景会让画面显得发灰。
/// 页面其余部分跟随全局单一浅色主题。
class PlayerPage extends ConsumerStatefulWidget {
  final String path;
  final String name;

  const PlayerPage({super.key, required this.path, this.name = ''});

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage> {
  late final Player _player = Player();
  late final VideoController _controller = VideoController(_player);
  String? _error;
  String _currentPath = '';
  String _currentName = '';
  bool _loading = true;
  bool _fullscreen = false;
  double _rate = 1;
  double _volume = 100;
  final List<FileItem> _playlist = [];
  bool _subtitleAttached = false;
  bool _subtitleOff = false;

  /// 播过的文件时长（path → 秒）。media_kit 只暴露当前文件时长，
  /// 列表里其它文件拿不到，只能播一个记一个，没记到的降级成类型文案。
  final Map<String, int> _durations = {};

  /// 每次 `_boot()` 递增，用来丢弃过期的异步结果（快速切换视频时）。
  int _bootSeq = 0;

  /// 播放器错误流：解码失败 / 链接失效只会从这里出来，`await open()` 不抛。
  StreamSubscription<String>? _errorSub;

  // dispose() 里不能再用 ref（Riverpod 会抛「used after dispose」），
  // 所以把保存续播所需的对象提前缓存下来。
  ServerStore? _store;
  String? _serverId;
  bool _resumeEnabled = true;

  @override
  void initState() {
    super.initState();
    _currentPath = widget.path;
    _currentName = widget.name.isEmpty ? baseName(widget.path) : widget.name;
    _rate = ref.read(appSettingsProvider).playbackSpeed;
    _volume = 100;
    _store = ref.read(serverStoreProvider);
    _serverId = ref.read(sessionProvider).profile?.id;
    _resumeEnabled = ref.read(appSettingsProvider).resumePlayback;
    // 解码错误 / 404 / 流中断都走这个流，不订阅的话界面上看不到任何原因。
    _errorSub = _player.stream.error.listen((message) {
      if (!mounted) return;
      final text = message.trim();
      setState(() {
        _loading = false;
        _error = text.isEmpty ? '播放失败，请检查链接或媒体格式' : '播放失败：$text';
      });
    });
    _boot();
  }

  Future<void> _boot() async {
    // v1.0.22：每次 bootstrap 带一个序号。连续切换两个视频时，
    // 后完成的 open 不能覆盖前一次的状态（否则画面与标题会错位）。
    final seq = ++_bootSeq;
    final api = ref.read(sessionProvider).api;
    if (api == null) {
      setState(() {
        _loading = false;
        _error = '尚未连接服务器';
      });
      return;
    }
    try {
      final files = ref.read(filesProvider);
      String? sign;
      for (final item in files.items) {
        // 只按完整路径匹配。之前还有 `item.name == _currentName` 兜底，
        // 从搜索打开其它目录的同名文件时会取到那份文件的 sign。
        if (joinPath(files.path, item.name) == _currentPath) {
          sign = item.sign;
          break;
        }
      }
      if (sign == null || sign.isEmpty) {
        final info = await api.get(_currentPath);
        if (seq != _bootSeq) return;
        sign = info.sign;
      }
      _buildPlaylist(files);
      final url = api.downloadUrl(_currentPath, sign: sign);
      await _player.open(Media(url), play: true);
      if (seq != _bootSeq) return;
      await _player.setRate(_rate);
      await _player.setVolume(_volume);
      if (!mounted || seq != _bootSeq) return;
      setState(() => _loading = false);
      final resumeAt = ref.read(appSettingsProvider).resumePlayback
          ? ref.read(serverStoreProvider).readResume(ref.read(sessionProvider).profile?.id ?? '', _currentPath)
          : 0;
      final duration = _player.state.duration.inSeconds;
      if (duration > 0) _durations[_currentPath] = duration;
      // 上次是在片尾退出的（存的就是结尾位置）就不要 seek，否则一打开就播完。
      if (resumeAt > 5 && (duration <= 0 || resumeAt < duration - 10)) {
        await _player.seek(Duration(seconds: resumeAt));
      }
      if (mounted && seq == _bootSeq) await _attachSubtitle(api, seq);
    } on ApiException catch (e) {
      if (!mounted || seq != _bootSeq) return;
      setState(() {
        _loading = false;
        _error = e.friendly;
      });
    } catch (_) {
      if (!mounted || seq != _bootSeq) return;
      setState(() {
        _loading = false;
        _error = '播放器初始化失败，检查网络或媒体格式';
      });
    }
  }

  /// 同目录可播放文件：视频 + 音频进播放列表，图片也列出（点击走预览页，
  /// 塞进 `_player.open` 只会得到一块空舞台）。
  void _buildPlaylist(FilesState files) {
    _playlist
      ..clear()
      ..addAll(files.items.where((e) {
        if (e.isDir) return false;
        final kind = kindOf(e.name, false);
        return kind == FileKind.video || kind == FileKind.audio || kind == FileKind.image;
      }).take(30));
  }

  bool _isPlayable(FileItem item) {
    final kind = kindOf(item.name, false);
    return kind == FileKind.video || kind == FileKind.audio;
  }

  /// 条目的完整路径。
  ///
  /// 0.5.11：引擎的 `parent` 可能是空串（不是 null），`??` 不会回退 ——
  /// 拼出空路径后播放器直接报「无法播放」。
  String _pathOf(FileItem item) {
    final parent = item.parent?.trim();
    if (parent == null || parent.isEmpty) {
      return joinPath(ref.read(filesProvider).path, item.name);
    }
    return parent;
  }

  /// 元信息：播过的显示真实时长，没播过的只能给类型（不能为了时长去对
  /// 30 个文件各发一次签名请求）。
  String _metaOf(FileItem item) {
    final size = formatBytes(item.size);
    final seconds = _durations[_pathOf(item)];
    if (seconds != null) return '$size · ${formatDuration(Duration(seconds: seconds))}';
    return switch (kindOf(item.name, false)) {
      FileKind.video => '$size · 视频',
      FileKind.audio => '$size · 音频',
      FileKind.image => '$size · 图片',
      _ => size,
    };
  }

  Future<void> _attachSubtitle(dynamic api, int seq, {bool force = false}) async {
    if (_subtitleOff) return;
    if (_subtitleAttached && !force) return;
    if (!mounted || seq != _bootSeq) return;
    final files = ref.read(filesProvider);
    final subtitles = files.items
        .where((e) => !e.isDir && const ['ass', 'srt', 'vtt', 'ssa'].contains(extensionOf(e.name)))
        .toList();
    if (subtitles.isEmpty) return;
    final item = subtitles.first;
    final path = joinPath(files.path, item.name);
    String? sign = item.sign;
    if (sign == null || sign.isEmpty) {
      try {
        sign = (await api.get(path)).sign as String?;
      } catch (_) {
        return;
      }
    }
    if (!mounted || seq != _bootSeq) return;
    final url = api.downloadUrl(path, sign: sign) as String;
    try {
      await _player.setSubtitleTrack(SubtitleTrack.uri(url, title: item.name));
      _subtitleAttached = true;
    } catch (_) {
      // 字幕格式不受支持时静默跳过
    }
  }

  Future<void> _setSubtitle(bool on) async {
    setState(() => _subtitleOff = !on);
    if (!on) {
      await _player.setSubtitleTrack(SubtitleTrack.no());
      _subtitleAttached = false;
      return;
    }
    final api = ref.read(sessionProvider).api;
    if (api == null) return;
    await _attachSubtitle(api, _bootSeq, force: true);
  }

  Future<void> _playAnother(FileItem item) async {
    // 先存正在播的这一条的进度，再切（原来的实现只有 dispose 才存，
    // 切完 _currentPath 已经变了，上一个视频的续播点就丢了）。
    _saveProgress();
    final seconds = _player.state.duration.inSeconds;
    if (seconds > 0) _durations[_currentPath] = seconds;
    setState(() {
      _loading = true;
      _error = null;
      _currentPath = _pathOf(item);
      _currentName = item.name;
      _subtitleAttached = false;
    });
    await _player.stop();
    await _boot();
  }

  void _saveProgress() {
    final store = _store;
    final serverId = _serverId;
    if (store == null || serverId == null || !_resumeEnabled) return;
    final position = _player.state.position;
    if (position.inSeconds > 5) {
      store.saveResume(serverId, _currentPath, position.inSeconds);
    }
  }

  @override
  void dispose() {
    _saveProgress();
    _errorSub?.cancel();
    // 退出播放页要把窗口的全屏状态还回去，否则回到文件页整个窗口仍是全屏
    if (_fullscreen) {
      _fullscreen = false;
      windowManager.setFullScreen(false).catchError((_) {});
    }
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggleFullscreen() async {
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) return;
    _fullscreen = !_fullscreen;
    await windowManager.setFullScreen(_fullscreen);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 900;
    // 页面整体是浅色：套一层 Theme 后，页内 `context.ol` 与倍速/字幕这类
    // 弹层都会自动用浅色调色板，不必逐处改色。
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: olSystemBars,
      child: Theme(
        data: olTheme(),
        child: Builder(
          builder: (context) {
            final p = context.ol;
            return Scaffold(
              backgroundColor: p.bg,
              body: SafeArea(
                child: Stack(
                  children: [
                    Column(
                      children: [
                        if (!_fullscreen) _topBar(context),
                        Expanded(
                          child: Row(
                        children: [
                          Expanded(
                            child: Padding(
                              // 全屏时不留白，让画面顶到窗口边缘。
                              padding: EdgeInsets.all(_fullscreen ? 0 : 22),
                              child: Column(
                                children: [
                                  Expanded(child: _stage(context)),
                                  if (!_fullscreen) const SizedBox(height: 14),
                                  if (!_fullscreen) _controls(context, narrow),
                                ],
                              ),
                            ),
                          ),
                              if (!narrow && !_fullscreen) _sidePanel(context),
                            ],
                          ),
                        ),
                      ],
                    ),
                    // 全屏时顶栏整体隐藏，这里补一个悬浮返回，避免无路可退。
                    if (_fullscreen)
                      Positioned(
                        left: 12,
                        top: 12,
                        child: GestureDetector(
                          onTap: () => context.pop(),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: const Color(0x66000000),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Center(
                              child: OlIcon('chev-l', size: 15, color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _topBar(BuildContext context) {
    final p = context.ol;
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: p.card,
        border: Border(bottom: BorderSide(color: p.line)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => context.pop(),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: p.card,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: p.line),
              ),
              child: Center(child: OlIcon('chev-l', size: 15, color: p.ink2)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '播放器',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: p.ink),
            ),
          ),
          OlIconButton(
            icon: 'pip',
            iconSize: 16,
            color: p.ink2,
            onTap: () => olToast(context, '画中画：Android 端在系统设置中允许后生效'),
          ),
          OlIconButton(icon: 'maximize', iconSize: 16, color: p.ink2, onTap: _toggleFullscreen),
        ],
      ),
    );
  }

  Widget _stage(BuildContext context) {
    final isAudio = kindOf(_currentName, false) == FileKind.audio;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_fullscreen ? 0 : 14),
        boxShadow: _fullscreen
            ? null
            : const [BoxShadow(color: Color(0x400E3A46), blurRadius: 50, offset: Offset(0, 18))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_fullscreen ? 0 : 14),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0B1622), Color(0xFF0E3A46)],
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 视频永远挂在树上（拆掉再挂会重建纹理，切歌时闪黑）。
              // fill 必须给透明：默认是黑色，会把舞台渐变整块压掉。
              if (_error == null)
                Center(
                  child: Video(
                    controller: _controller,
                    controls: NoVideoControls,
                    fit: BoxFit.contain,
                    fill: Colors.transparent,
                  ),
                ),
              // 音频没有画面，叠一层标题块（不卸载 Video）。
              if (isAudio && _error == null)
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const OlIcon('music', size: 30, color: Color(0xFF7FE7D4)),
                      const SizedBox(height: 10),
                      Text(
                        _currentName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFD7E4EF)),
                      ),
                    ],
                  ),
                ),
              // 左上角：文件名 + 边下边播徽标
              Positioned(
                left: 18,
                top: 16,
                right: 18,
                child: Row(
                  children: [
                    const OlIcon('zap', size: 15, color: Color(0xFF7FE7D4)),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        _currentName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFD7E4EF)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0x292DD4BF),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: const Color(0x662DD4BF)),
                      ),
                      child: const Text(
                        '边下边播',
                        style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Color(0xFF7FE7D4)),
                      ),
                    ),
                  ],
                ),
              ),
              // 暂停时才出现的中央播放钮（效果图是暂停帧）。
              if (_error == null && !isAudio)
                Center(
                  child: StreamBuilder<bool>(
                    stream: _player.stream.playing,
                    builder: (context, snapshot) {
                      final playing = snapshot.data ?? false;
                      if (playing) return const SizedBox.shrink();
                      return GestureDetector(
                        onTap: () => _player.play(),
                        child: Container(
                          width: 74,
                          height: 74,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0x24FFFFFF),
                            border: Border.all(color: const Color(0x8CFFFFFF), width: 2),
                          ),
                          child: const Center(
                            child: OlIcon('play', size: 30, color: Colors.white, filled: true),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              if (_loading)
                const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF7DD3FC))),
              if (_error != null)
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const OlIcon('alert', size: 24, color: Color(0xFFF43F5E)),
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12, color: Color(0xFF9DB4C8)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _loading = true;
                            _error = null;
                            // 重试会重新 open，轨道被清空，字幕标记必须一起复位
                            _subtitleAttached = false;
                          });
                          _boot();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0x1FFFFFFF),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            '重试',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFBFE6F5)),
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

  Widget _sidePanel(BuildContext context) {
    final p = context.ol;
    final dir = ref.watch(filesProvider).path;
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: p.card,
        border: Border(left: BorderSide(color: p.line)),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text(
                '播放列表',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1, color: Color(0xFF9DB2C4)),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '· $dir',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: p.ink4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _playlist.isEmpty
                ? Center(
                    child: Text('同目录没有可播放的文件', style: TextStyle(fontSize: 10.5, color: p.ink4)),
                  )
                : ListView.builder(
                    itemCount: _playlist.length,
                    itemBuilder: (context, index) {
                      final item = _playlist[index];
                      final path = _pathOf(item);
                      final active = path == _currentPath;
                      return _PlaylistRow(
                        item: item,
                        meta: active ? _liveMeta(item, path) : _metaOf(item),
                        active: active,
                        onTap: () {
                          if (_isPlayable(item)) {
                            _playAnother(item);
                            return;
                          }
                          // 图片：交给预览页，避免空舞台。
                          context.push(
                            '/preview?path=${Uri.encodeComponent(path)}&name=${Uri.encodeComponent(item.name)}',
                          );
                        },
                      );
                    },
                  ),
          ),
          const SizedBox(height: 10),
          Text(
            '续播位置按文件记忆 · 跨会话恢复\n直链有效期 4 小时，过期自动重签',
            style: TextStyle(fontSize: 10.5, height: 1.6, color: p.ink4),
          ),
        ],
      ),
    );
  }

  /// 正在播的那一条用已知时长（列表里其它文件只能等播过才知道时长）。
  String _liveMeta(FileItem item, String path) {
    final seconds = _durations[path];
    final size = formatBytes(item.size);
    return seconds == null ? '$size · 播放中' : '$size · ${formatDuration(Duration(seconds: seconds))}';
  }

  Widget _controls(BuildContext context, bool narrow) {
    final p = context.ol;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.line),
      ),
      child: StreamBuilder<Duration>(
        stream: _player.stream.position,
        builder: (context, positionSnapshot) {
          final position = positionSnapshot.data ?? Duration.zero;
          return StreamBuilder<Duration>(
            stream: _player.stream.duration,
            builder: (context, durationSnapshot) {
              final duration = durationSnapshot.data ?? Duration.zero;
              return StreamBuilder<Duration>(
                stream: _player.stream.buffer,
                builder: (context, bufferSnapshot) {
                  final buffered = bufferSnapshot.data ?? Duration.zero;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _SeekBar(
                              position: position,
                              duration: duration,
                              buffered: buffered,
                              height: 7,
                              trackColor: const Color(0xFFEDF2F8),
                              bufferColor: const Color(0xFFD8ECF8),
                              knobSize: 13,
                              knobBorder: const Color(0xFF0EA5E9),
                              knobBorderWidth: 2.5,
                              onSeek: (fraction) {
                                if (duration.inMilliseconds <= 0) return;
                                _player.seek(Duration(milliseconds: (duration.inMilliseconds * fraction).round()));
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '${formatDuration(position)} / ${formatDuration(duration)}',
                            style: TextStyle(fontSize: 11.5, color: p.ink2),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          StreamBuilder<bool>(
                            stream: _player.stream.playing,
                            builder: (context, snapshot) {
                              final playing = snapshot.data ?? false;
                              return _CtrlBtn(
                                icon: playing ? 'pause' : 'play',
                                filled: true,
                                onTap: () => playing ? _player.pause() : _player.play(),
                              );
                            },
                          ),
                          const SizedBox(width: 8),
                          _CtrlBtn(
                            icon: 'rotate',
                            onTap: () {
                              final seconds = _player.state.position.inSeconds - 10;
                              _player.seek(Duration(seconds: seconds < 0 ? 0 : seconds));
                            },
                          ),
                          const SizedBox(width: 8),
                          _CtrlBtn(
                            icon: 'arrow-down',
                            onTap: () => _player.seek(_player.state.position + const Duration(seconds: 10)),
                          ),
                          const Spacer(),
                          if (!narrow)
                            StreamBuilder<double>(
                              stream: _player.stream.volume,
                              builder: (context, snapshot) {
                                final volume = snapshot.data ?? 100;
                                return Row(
                                  children: [
                                    GestureDetector(
                                      onTap: () {
                                        final next = volume > 0 ? 0.0 : 100.0;
                                        _player.setVolume(next);
                                        setState(() => _volume = next);
                                      },
                                      child: OlIcon(
                                        volume > 0 ? 'volume' : 'volume-off',
                                        size: 15,
                                        color: p.ink2,
                                      ),
                                    ),
                                    SizedBox(
                                      width: 92,
                                      child: _SeekBar(
                                        position: Duration(milliseconds: (volume * 10).round()),
                                        duration: const Duration(milliseconds: 1000),
                                        height: 3,
                                        trackColor: const Color(0xFFEDF2F8),
                                        onSeek: (fraction) {
                                          final next = (fraction * 100).roundToDouble();
                                          _player.setVolume(next);
                                          setState(() => _volume = next);
                                        },
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          const SizedBox(width: 8),
                          _CtrlSelect(
                            label: '倍速 ${_rate.toStringAsFixed(1)}x',
                            onTapDown: (position) async {
                              await showOlMenu(context, position: position, items: [
                                for (final rate in const [0.75, 1.0, 1.25, 1.5, 2.0])
                                  OlMenuItem('${rate.toStringAsFixed(2)}×', 'zap', () {
                                    setState(() => _rate = rate);
                                    _player.setRate(rate);
                                    ref.read(appSettingsProvider.notifier).setPlaybackSpeed(rate);
                                  }),
                              ]);
                            },
                          ),
                          // 窄屏一行放不下第四组控件（320dp 会溢出），字幕只在桌面出现；
                          // 移动端字幕仍会自动匹配，只是不给手动开关。
                          if (!narrow) ...[
                            const SizedBox(width: 8),
                            _CtrlSelect(
                              label: _subtitleOff ? '字幕：关' : '字幕：自动',
                              onTapDown: (position) async {
                                await showOlMenu(context, position: position, items: [
                                  OlMenuItem('字幕：关', 'x', () => _setSubtitle(false)),
                                  OlMenuItem('字幕：自动匹配', 'file-text', () => _setSubtitle(true)),
                                ]);
                              },
                            ),
                          ],
                          if (!narrow) ...[
                            const SizedBox(width: 8),
                            _CtrlBtn(icon: 'maximize', onTap: _toggleFullscreen),
                          ],
                        ],
                      ),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

/// 控制条上的方按钮 34×34、圆角 9、细描边。
class _CtrlBtn extends StatelessWidget {
  final String icon;
  final VoidCallback onTap;
  final bool filled;

  const _CtrlBtn({required this.icon, required this.onTap, this.filled = false});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: p.line),
        ),
        child: Center(child: OlIcon(icon, size: 15, color: p.ink2, filled: filled)),
      ),
    );
  }
}

/// 控制条上的下拉（倍速 / 字幕）：30 高、圆角 8、11px/700。
class _CtrlSelect extends StatelessWidget {
  final String label;
  final ValueChanged<Offset> onTapDown;

  const _CtrlSelect({required this.label, required this.onTapDown});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return GestureDetector(
      onTapDown: (details) => onTapDown(details.globalPosition),
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: p.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: p.ink2)),
            const SizedBox(width: 4),
            OlIcon('chev-d', size: 10, color: p.ink4),
          ],
        ),
      ),
    );
  }
}

/// 播放列表一行：56×36 渐变缩略图 + 名称两行 + 元信息 + 当前项播放指示条。
class _PlaylistRow extends StatelessWidget {
  final FileItem item;
  final String meta;
  final bool active;
  final VoidCallback onTap;

  const _PlaylistRow({required this.item, required this.meta, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    final kind = kindOf(item.name, false);
    final icon = switch (kind) {
      FileKind.video => 'film',
      FileKind.audio => 'music',
      FileKind.image => 'image',
      _ => 'file',
    };
    final iconColor = switch (kind) {
      FileKind.video => const Color(0xFF7C5CFC),
      FileKind.audio => const Color(0xFFEC4899),
      FileKind.image => const Color(0xFF2DD4BF),
      _ => p.ink3,
    };
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: active ? p.rowSel : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: active ? p.chipBorder : Colors.transparent),
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 36,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFFDDF6F2), Color(0xFFBDE7FA)]),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Center(
                child: OlIcon(icon, size: 16, color: iconColor, filled: kind == FileKind.video),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.3,
                      fontWeight: active ? FontWeight.w800 : FontWeight.w700,
                      color: active ? p.ink : p.ink2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(meta, style: TextStyle(fontSize: 9.5, color: p.ink4)),
                ],
              ),
            ),
            if (active) ...[
              const SizedBox(width: 6),
              const _PlayingBars(),
            ],
          ],
        ),
      ),
    );
  }
}

/// 当前项的「正在播放」指示：4 根不等高竖条（效果图静态高度 6/12/9/14）。
class _PlayingBars extends StatelessWidget {
  const _PlayingBars();

  @override
  Widget build(BuildContext context) {
    const heights = [6.0, 12.0, 9.0, 14.0];
    return SizedBox(
      height: 14,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final h in heights)
            Container(
              width: 2.5,
              height: h,
              margin: const EdgeInsets.only(left: 2),
              decoration: BoxDecoration(
                color: OlTokens.sky600,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
        ],
      ),
    );
  }
}

class _SeekBar extends StatelessWidget {
  final Duration position;
  final Duration duration;
  final ValueChanged<double> onSeek;
  final double height;
  final Color trackColor;
  final Color? bufferColor;
  final double knobSize;
  final Color knobBorder;
  final double knobBorderWidth;

  /// 已缓冲到的位置（可选，只有进度条会传）。
  final Duration? buffered;

  const _SeekBar({
    required this.position,
    required this.duration,
    required this.onSeek,
    this.height = 3,
    this.trackColor = const Color(0xFFEDF2F8),
    this.bufferColor,
    this.knobSize = 9,
    this.knobBorder = Colors.transparent,
    this.knobBorderWidth = 0,
    this.buffered,
  });

  @override
  Widget build(BuildContext context) {
    final total = duration.inMilliseconds;
    final fraction = total <= 0 ? 0.0 : (position.inMilliseconds / total).clamp(0.0, 1.0).toDouble();
    final bufferedFraction = total <= 0
        ? fraction
        : ((buffered?.inMilliseconds ?? 0) / total).clamp(fraction, 1.0).toDouble();
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite ? constraints.maxWidth : 200.0;
        void seekTo(Offset local) {
          if (width <= 0) return;
          onSeek((local.dx / width).clamp(0.0, 1.0).toDouble());
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) => seekTo(details.localPosition),
          onHorizontalDragUpdate: (details) => seekTo(details.localPosition),
          child: SizedBox(
            height: 16,
            child: Center(
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Container(
                    height: height,
                    decoration: BoxDecoration(color: trackColor, borderRadius: BorderRadius.circular(99)),
                  ),
                  if (bufferColor != null)
                    FractionallySizedBox(
                      widthFactor: bufferedFraction,
                      child: Container(
                        height: height,
                        decoration: BoxDecoration(color: bufferColor, borderRadius: BorderRadius.circular(99)),
                      ),
                    ),
                  FractionallySizedBox(
                    widthFactor: fraction,
                    child: Container(
                      height: height,
                      decoration: BoxDecoration(
                        gradient: OlTokens.gradientBrand,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment(fraction * 2 - 1, 0),
                    child: Container(
                      width: knobSize,
                      height: knobSize,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: knobBorderWidth > 0 ? Border.all(color: knobBorder, width: knobBorderWidth) : null,
                        boxShadow: const [BoxShadow(color: Color(0x400EA5E9), blurRadius: 6)],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
