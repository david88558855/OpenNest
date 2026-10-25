import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:window_manager/window_manager.dart';

import '../../app/providers.dart';
import '../../core/app_info.dart';
import '../../core/sidecar/sidecar_controller.dart';
import '../../core/sidecar/sidecar_paths.dart';
import '../../core/sidecar/sidecar_state.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/ol_controls.dart';
import '../../core/widgets/ol_icon.dart';
import '../sources/sources_controller.dart';

/// 启动页：先出画面，再在后台拉起内嵌引擎，失败时给出可操作错误。
class BootPage extends ConsumerStatefulWidget {
  const BootPage({super.key});

  @override
  ConsumerState<BootPage> createState() => _BootPageState();
}

class _BootPageState extends ConsumerState<BootPage> {
  bool _busy = false;
  String _dataDir = '';
  double _progress = 0.08;
  Timer? _ticker;
  final Stopwatch _elapsed = Stopwatch();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _progress = 0.08;
    });
    _elapsed
      ..reset()
      ..start();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      // 缓慢逼近 0.9，真正的完成由状态切换接管。
      setState(() => _progress = (_progress + (0.9 - _progress) * 0.08).clamp(0.08, 0.9).toDouble());
    });

    try {
      _dataDir = (await SidecarPaths.root()).path;
    } catch (_) {}

    await ref.read(sidecarProvider.notifier).start();
    if (!mounted) return;

    final sidecar = ref.read(sidecarProvider);
    if (sidecar.status == SidecarStatus.ready) {
      await ref.read(sessionProvider.notifier).boot();
      if (!mounted) return;
      var hasSources = false;
      try {
        final sources = await ref.read(sourcesProvider.future);
        hasSources = sources.isNotEmpty;
      } catch (_) {}
      if (!mounted) return;
      if (hasSources) {
        try {
          await ref.read(filesProvider.notifier).attach();
        } catch (_) {}
      }
      if (!mounted) return;
      _ticker?.cancel();
      setState(() => _progress = 1);
      if (mounted) context.go(hasSources ? '/files' : '/sources/add');
      return;
    }

    _ticker?.cancel();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _progress = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    final sidecar = ref.watch(sidecarProvider);
    final failed = sidecar.status == SidecarStatus.failed;

    return Scaffold(
      backgroundColor: p.bg,
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.6, -0.8),
                  radius: 1.1,
                  colors: [const Color(0xFFF2F9FF), p.bg],
                ),
              ),
            ),
          ),
          // 无边框窗口需要一个拖动区
          if (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 38,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onPanStart: (_) => windowManager.startDragging(),
                child: const SizedBox.expand(),
              ),
            ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(28, 26, 28, 22),
                  decoration: BoxDecoration(
                    color: p.card,
                    borderRadius: BorderRadius.circular(OlTokens.rCard),
                    border: Border.all(color: p.line),
                    boxShadow: const [
                      BoxShadow(color: Color(0x140E3A46), blurRadius: 40, offset: Offset(0, 18)),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const _Mark(),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'OpenNest',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: p.ink),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '免账户 · 直连存储',
                                style: TextStyle(fontSize: 10.5, color: p.ink3),
                              ),
                            ],
                          ),
                          const Spacer(),
                          Text(
                            AppInfo.versionLabel,
                            style: TextStyle(fontSize: 10, color: p.ink4),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      if (!failed) ...[
                        Text(
                          _busy ? '正在启动内嵌引擎' : '准备就绪',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: p.ink),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          sidecar.step ?? '首次启动需要初始化本机数据目录，通常不超过 10 秒。',
                          style: TextStyle(fontSize: 11.5, height: 1.6, color: p.ink3),
                        ),
                        const SizedBox(height: 16),
                        OlProgress(value: _progress, height: 5),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 16,
                          runSpacing: 6,
                          children: [
                            _Meta(icon: 'server', text: sidecar.endpoint.isEmpty ? '本机回环' : sidecar.endpoint),
                            _Meta(
                              icon: 'hard-drive',
                              text: sidecar.engineVersion == null
                                  ? '引擎 v4'
                                  : '引擎 ${AppInfo.shortVersion(sidecar.engineVersion)}',
                            ),
                            if (_dataDir.isNotEmpty) _Meta(icon: 'folder', text: _shorten(_dataDir)),
                          ],
                        ),
                      ] else ...[
                        Row(
                          children: [
                            const OlIcon('alert', size: 16, color: OlTokens.dangerDeep),
                            const SizedBox(width: 8),
                            Text(
                              '引擎启动失败',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: p.ink),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          constraints: const BoxConstraints(maxHeight: 220),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: OlTokens.dangerSurface,
                            borderRadius: BorderRadius.circular(OlTokens.rPanel),
                            border: Border.all(color: OlTokens.dangerBorder),
                          ),
                          child: SingleChildScrollView(
                            child: Text(
                              sidecar.error ?? '未知错误',
                              style: const TextStyle(
                                fontSize: 10.5,
                                height: 1.6,
                                color: OlTokens.dangerInk,
                                fontFamily: 'Consolas',
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '常见原因：内嵌引擎（openlist.exe）未与主程序放在同一目录；或本机安全软件拦截了子进程。',
                          style: TextStyle(fontSize: 10.5, height: 1.6, color: p.ink3),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            OlPrimaryButton(
                              label: '重试',
                              icon: 'refresh',
                              height: 34,
                              onTap: _bootstrap,
                            ),
                            const SizedBox(width: 10),
                            if (sidecar.logPath != null)
                              OlGhostButton(
                                label: '打开日志目录',
                                icon: 'folder',
                                height: 34,
                                onTap: () => _revealLog(sidecar),
                              ),
                            const Spacer(),
                            if (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
                              OlGhostButton(
                                label: '退出',
                                height: 34,
                                onTap: () async {
                                  await ref.read(sidecarProvider.notifier).stop();
                                  exit(0);
                                },
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _shorten(String path) {
    if (path.length <= 34) return path;
    return '…${path.substring(path.length - 33)}';
  }

  Future<void> _revealLog(SidecarState sidecar) async {
    final logPath = sidecar.logPath;
    if (logPath == null) return;
    final dir = File(logPath).parent.path;
    try {
      if (Platform.isWindows) {
        await Process.run('explorer', [dir]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [dir]);
      } else {
        await Process.run('xdg-open', [dir]);
      }
    } catch (_) {}
  }
}

class _Mark extends StatelessWidget {
  const _Mark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        gradient: OlTokens.gradientBrand,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Color(0x552DD4BF), blurRadius: 18, offset: Offset(0, 6))],
      ),
      child: const Center(child: OlIcon('layers', size: 20, color: Colors.white)),
    );
  }
}

class _Meta extends StatelessWidget {
  final String icon;
  final String text;

  const _Meta({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OlIcon(icon, size: 12, color: p.ink4),
        const SizedBox(width: 5),
        Text(text, style: TextStyle(fontSize: 10.5, color: p.ink3)),
      ],
    );
  }
}
