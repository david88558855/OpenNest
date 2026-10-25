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
import '../../core/widgets/ol_controls.dart';
import '../../core/widgets/ol_dialogs.dart';
import '../../core/widgets/ol_icon.dart';
import '../files/files_controller.dart';

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
        // 从搜索/收藏打开其它目录的同名文件时会取到那份文件的 sign。
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

  void _buildPlaylist(FilesState files) {
    _playlist
      ..clear()
      ..addAll(files.items.where((e) => !e.isDir && kindOf(e.name, false) == FileKind.video).take(30));
  }

  Future<void> _attachSubtitle(dynamic api, int seq) async {
    if (_subtitleAttached) return;
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

  Future<void> _playAnother(FileItem item) async {
    // 先存正在播的这一条的进度，再切（原来的实现只有 dispose 才存，
    // 切完 _currentPath 已经变了，上一个视频的续播点就丢了）。
    _saveProgress();
    setState(() {
      _loading = true;
      _error = null;
      _currentPath = joinPath(ref.read(filesProvider).path, item.name);
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
    // 播放页是纯深色全屏界面：系统栏图标固定浅色，配 SafeArea 让开系统栏。
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: olDarkSystemBars,
      child: Scaffold(
      backgroundColor: const Color(0xFF07101B),
      body: SafeArea(
        child: Column(
          children: [
            _topBar(context),
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _stage(context)),
                  if (!narrow) _sidePanel(context),
                ],
              ),
            ),
            _controls(context, narrow),
          ],
        ),
      ),
      ),
    );
  }

  Widget _topBar(BuildContext context) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xE6040A12), Color(0x00040A12)]),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => context.pop(),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: const Color(0x17FFFFFF), borderRadius: BorderRadius.circular(9), border: Border.all(color: const Color(0x1FFFFFFF))),
              child: const Center(child: OlIcon('chev-l', size: 15, color: Color(0xFFE8F2FA))),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(_currentName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFE8F2FA))),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const OlDot(size: 5, color: Color(0xFF5EEAD4)),
                    const SizedBox(width: 5),
                    Text(
                      '${ref.read(sessionProvider).profile?.name ?? 'OpenNest'} · 边下边播',
                      style: const TextStyle(fontSize: 9.5, color: Color(0xFF7E97AC)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          OlIconButton(icon: 'pip', iconSize: 16, color: const Color(0xFFB9CAD8), onTap: () => olToast(context, '画中画：Android 端在系统设置中允许后生效')),
          OlIconButton(
            icon: 'maximize',
            iconSize: 16,
            color: const Color(0xFFB9CAD8),
            onTap: _toggleFullscreen,
          ),
        ],
      ),
    );
  }

  Widget _stage(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(-0.4, -0.8),
          radius: 1.1,
          colors: [Color(0xFF132B4D), Color(0xFF071322), Color(0xFF050D16)],
          stops: [0, 0.6, 1],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_error == null)
            Center(
              child: Video(
                controller: _controller,
                controls: NoVideoControls,
                fit: BoxFit.contain,
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
                  Text(_error!, style: const TextStyle(fontSize: 12, color: Color(0xFF9DB4C8))),
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
                      decoration: BoxDecoration(color: const Color(0x1FFFFFFF), borderRadius: BorderRadius.circular(8)),
                      child: const Text('重试', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFBFE6F5))),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _sidePanel(BuildContext context) {
    return Container(
      width: 250,
      decoration: const BoxDecoration(
        color: Color(0xDB091421),
        border: Border(left: BorderSide(color: Color(0x12FFFFFF))),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: const [
              Text('播放列表', style: TextStyle(fontSize: 9.5, letterSpacing: 1, fontWeight: FontWeight.w800, color: Color(0xFF7E97AC))),
              Spacer(),
              Text('同目录视频', style: TextStyle(fontSize: 9, color: Color(0xFF6E879C))),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _playlist.isEmpty
                ? const Center(child: Text('同目录没有其他视频', style: TextStyle(fontSize: 10, color: Color(0xFF6E879C))))
                : ListView.builder(
                    itemCount: _playlist.length,
                    itemBuilder: (context, index) {
                      final item = _playlist[index];
                      final active = item.name == _currentName;
                      return InkWell(
                        onTap: () => _playAnother(item),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 3),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
                          decoration: BoxDecoration(
                            color: active ? const Color(0x1F38BDF8) : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: active ? const Color(0x2E38BDF8) : Colors.transparent),
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 18,
                                child: Text(
                                  '${index + 1}',
                                  style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFF6E879C)),
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: active ? const Color(0xFF7DD3FC) : const Color(0xFFD6E4EF)),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(formatBytes(item.size), style: const TextStyle(fontSize: 8.5, color: Color(0xFF6E879C))),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0x0FFFFFFF), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0x14FFFFFF))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('播放信息', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: Color(0xFF7E97AC))),
                const SizedBox(height: 6),
                Text(
                  '倍速 ${_rate.toStringAsFixed(2)}× · 音量 ${_volume.round()}%',
                  style: const TextStyle(fontSize: 9.5, color: Color(0xFFB9CAD8)),
                ),
                const SizedBox(height: 3),
                const Text('字幕自动匹配同目录 ass / srt', style: TextStyle(fontSize: 9, color: Color(0xFF6E879C))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _controls(BuildContext context, bool narrow) {
    return Container(
      height: 76,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      decoration: const BoxDecoration(
        color: Color(0xF5060E18),
        border: Border(top: BorderSide(color: Color(0x0FFFFFFF))),
      ),
      child: StreamBuilder<Duration>(
        stream: _player.stream.position,
        builder: (context, positionSnapshot) {
          final position = positionSnapshot.data ?? Duration.zero;
          return StreamBuilder<Duration>(
            stream: _player.stream.duration,
            builder: (context, durationSnapshot) {
              final duration = durationSnapshot.data ?? Duration.zero;
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _SeekBar(
                          position: position,
                          duration: duration,
                          onSeek: (fraction) {
                            if (duration.inMilliseconds <= 0) return;
                            _player.seek(Duration(milliseconds: (duration.inMilliseconds * fraction).round()));
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${formatDuration(position)} / ${formatDuration(duration)}',
                        style: const TextStyle(fontSize: 9, color: Color(0xFF93A8BB)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      StreamBuilder<bool>(
                        stream: _player.stream.playing,
                        builder: (context, snapshot) {
                          final playing = snapshot.data ?? false;
                          return GestureDetector(
                            onTap: () => playing ? _player.pause() : _player.play(),
                            child: Container(
                              width: 34,
                              height: 34,
                              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                              child: Center(
                                child: OlIcon(playing ? 'pause' : 'play', size: 14, color: const Color(0xFF07101B), filled: true),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 14),
                      OlIconButton(
                        icon: 'rotate',
                        iconSize: 16,
                        color: const Color(0xFFB9CAD8),
                        onTap: () {
                          final seconds = _player.state.position.inSeconds - 10;
                          _player.seek(Duration(seconds: seconds < 0 ? 0 : seconds));
                        },
                      ),
                      const SizedBox(width: 4),
                      OlIconButton(
                        icon: 'arrow-down',
                        iconSize: 16,
                        color: const Color(0xFFB9CAD8),
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
                                  child: OlIcon(volume > 0 ? 'volume' : 'volume-off', size: 15, color: const Color(0xFFB9CAD8)),
                                ),
                                SizedBox(
                                  width: 92,
                                  child: _SeekBar(
                                    position: Duration(milliseconds: (volume * 10).round()),
                                    duration: const Duration(milliseconds: 1000),
                                    height: 3,
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
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTapDown: (details) async {
                          await showOlMenu(context, position: details.globalPosition, items: [
                            for (final rate in const [0.75, 1.0, 1.25, 1.5, 2.0])
                              OlMenuItem('${rate.toStringAsFixed(2)}×', 'zap', () {
                                setState(() => _rate = rate);
                                _player.setRate(rate);
                                ref.read(appSettingsProvider.notifier).setPlaybackSpeed(rate);
                              }),
                          ]);
                        },
                        child: Container(
                          height: 24,
                          padding: const EdgeInsets.symmetric(horizontal: 9),
                          decoration: BoxDecoration(color: const Color(0x17FFFFFF), borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0x1FFFFFFF))),
                          child: Center(
                            child: Text('${_rate.toStringAsFixed(2)}×', style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: Color(0xFFCFE6F3))),
                          ),
                        ),
                      ),
                      if (!narrow) ...[
                        const SizedBox(width: 8),
                        OlIconButton(icon: 'maximize', iconSize: 16, color: const Color(0xFFB9CAD8), onTap: _toggleFullscreen),
                      ],
                    ],
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _SeekBar extends StatelessWidget {
  final Duration position;
  final Duration duration;
  final ValueChanged<double> onSeek;
  final double height;

  const _SeekBar({required this.position, required this.duration, required this.onSeek, this.height = 3});

  @override
  Widget build(BuildContext context) {
    final total = duration.inMilliseconds;
    final fraction = total <= 0 ? 0.0 : (position.inMilliseconds / total).clamp(0.0, 1.0).toDouble();
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
                    decoration: BoxDecoration(color: const Color(0x24FFFFFF), borderRadius: BorderRadius.circular(2)),
                  ),
                  FractionallySizedBox(
                    widthFactor: fraction,
                    child: Container(
                      height: height,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFF38BDF8), Color(0xFF2DD4BF)]),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment(fraction * 2 - 1, 0),
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: const Color(0x4D38BDF8), blurRadius: 6, spreadRadius: 2)],
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
