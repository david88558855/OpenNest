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
import '../../core/widgets/ol_dialogs.dart';
import '../../core/widgets/ol_icon.dart';
import '../sources/sources_controller.dart';
import 'boot_entry.dart';

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

  /// 安全模式失败时的额外提示（引擎日志之外的、我们能说清楚的那一句）。
  String? _safeModeError;

  /// 是否已经在推进落点（防止「后台就绪监听」与 `_bootstrap` 各跳一次）。
  bool _entering = false;

  /// 引擎状态订阅：本页可能停在这里等引擎，而引擎是**在别处**就绪的
  /// （崩溃自动重启成功、安全模式重启）。以前只靠 `_bootstrap` 那一次
  /// await，一旦 start() 因 `status == starting` 提前返回，本页就永远
  /// 停在「准备就绪」上不动了。
  ProviderSubscription<SidecarState>? _sidecarSub;

  /// 引擎就绪之后每一步的兜底上限。
  ///
  /// 注意：这些超时**不再是启动必经路径**。0.5.11 起启动页只等引擎进程
  /// 就绪（`/ping` 通），会话建立、存储源列表、目录加载全部挪到进入界面
  /// 之后的 AppWatchdog 里做 —— 引擎的 `StoragesLoaded` 中间件在「全部
  /// 存储源加载完」之前会挂住除 `/` 以外的全部接口，一个连不通的源就能把
  /// 这串等待拖到三四十秒（12 + 8 + 15），用户看到的就是「卡在启动页」。
  /// 这里只保留一个短预算，用于判定首启落点。
  static const Duration _entryProbeTimeout = Duration(seconds: 2);

  @override
  void initState() {
    super.initState();
    // 引擎在后台就绪时继续推进落点（_busy 为真说明本页流程自己在跑，别抢）。
    _sidecarSub = ref.listenManual<SidecarState>(sidecarProvider, (previous, next) {
      if (next.status != SidecarStatus.ready) return;
      if (previous?.status == SidecarStatus.ready) return;
      if (!mounted || _busy) return;
      unawaited(_enterApp(engineReady: true));
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _sidecarSub?.close();
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _progress = 0.08;
      _safeModeError = null;
    });
    _elapsed
      ..reset()
      ..start();
    _startTicker();

    try {
      _dataDir = (await SidecarPaths.root()).path;
    } catch (_) {}

    await ref.read(sidecarProvider.notifier).start();
    if (!mounted) return;

    if (ref.read(sidecarProvider).status != SidecarStatus.ready) {
      _stopTicker();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _progress = 0;
      });
      return;
    }
    await _enterApp(engineReady: true);
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      // 缓慢逼近 0.9，真正的完成由状态切换接管。
      setState(() => _progress = (_progress + (0.9 - _progress) * 0.08).clamp(0.08, 0.9).toDouble());
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  /// 引擎就绪（或用户选择降级）后走到落地页。
  ///
  /// 0.5.11：这里**只做落点判定**，不再等会话 / 存储源 / 目录 ——
  /// 那三者都会被引擎的 `StoragesLoaded` 中间件拦住，个别存储源失联时
  /// 能把启动页扣住几十秒。等待改由进入页面后的后台引导承担
  /// （静态页照常可用，文件页显示「正在加载存储源」并在就绪后自动刷新）。
  Future<void> _enterApp({required bool engineReady}) async {
    if (_entering) return;
    _entering = true;
    var hasSources = true;
    if (engineReady) {
      hasSources = await _probeHasSources();
      if (!mounted) return;
    }
    // 落点：有源直接进文件页；无源且没点过「稍后再说」→ 欢迎页。
    // 降级模式一律进文件页（欢迎页在引擎不可用时没有意义）。
    final skipped = ref.read(prefsProvider).getBool(kOnboardDoneKey);
    final entry = (!engineReady || hasSources || skipped) ? BootEntry.files : BootEntry.welcome;
    ref.read(bootEntryProvider.notifier).state = entry;
    _stopTicker();
    if (!mounted) return;
    setState(() => _progress = 1);
    context.go(entry == BootEntry.files ? '/files' : '/welcome');
  }

  /// 短预算判断「引擎里有没有存储源」。
  ///
  /// 只有首启才需要区分：没有源要落到欢迎页。判定超时（多半是某个源把
  /// 中间件挂住了）按「有源」处理 —— 那时用户一定不是首启，直接进文件页
  /// 才是对的；首启没有源，引擎不会阻塞，这一步通常 100ms 内就返回。
  Future<bool> _probeHasSources() async {
    try {
      if (!ref.read(sessionProvider).signedIn) {
        await ref.read(sessionProvider.notifier).boot().timeout(_entryProbeTimeout);
      }
      if (!mounted || !ref.read(sessionProvider).signedIn) return true;
      final sources = await ref.read(sourcesProvider.future).timeout(_entryProbeTimeout);
      return sources.isNotEmpty;
    } catch (_) {
      return true;
    }
  }

  /// 引擎失败时仍然进入主界面（降级模式）。
  ///
  /// 路由在 `failed` 状态会把页面弹回启动页，所以先打开降级开关再跳：
  /// 用户至少能进设置看日志、重启引擎、去「存储源」停用肇事的那个源。
  void _enterDegraded() {
    ref.read(degradedModeProvider.notifier).state = true;
    ref.read(bootEntryProvider.notifier).state = BootEntry.files;
    _stopTicker();
    context.go('/files');
  }

  /// 安全模式：停用全部存储源后再启动引擎，成功后直接落到「存储源」分区。
  Future<void> _startSafeMode() async {
    if (_busy) return;
    final confirmed = await showOlDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('安全模式启动', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
        content: const Text(
          '先把引擎库里全部存储源标记为「停用」，再启动引擎。\n\n'
          '启动后可在「设置 → 存储源」逐个启用；若是某个源把引擎打崩，'
          '启用它时会被自动改回停用，这样就能定位到具体是哪一个。\n\n'
          '改动前会把 data.db 备份成 data.db.bak-<时间戳>。',
          style: TextStyle(fontSize: 12, height: 1.65),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('停用并启动'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _progress = 0.15;
      _safeModeError = null;
    });
    _startTicker();

    final result = await ref.read(sidecarProvider.notifier).startInSafeMode();
    if (!mounted) return;
    if (!result.ok) {
      _stopTicker();
      setState(() {
        _busy = false;
        _progress = 0;
        _safeModeError = result.error;
      });
      return;
    }

    // 安全模式下所有源已停用，引擎不会卡在中间件上，登录很快；
    // boot() 内部对 /api/me 还有 12 秒上限，这里不再叠加外层超时。
    try {
      await ref.read(sessionProvider.notifier).boot();
    } catch (_) {}
    if (!mounted) return;
    ref.read(bootEntryProvider.notifier).state = BootEntry.files;
    _stopTicker();
    setState(() => _progress = 1);
    // 直接落到「存储源」分区：用户马上看到被停用的那几条，逐个启用即可。
    context.go('/settings/sources');
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
                                
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '常见原因：内嵌引擎（openlist.exe）未与主程序放在同一目录；本机安全软件拦截了子进程；'
                          '或某个存储源的驱动在加载时崩溃（此时每次启动都会在同一处失败）。',
                          style: TextStyle(fontSize: 10.5, height: 1.6, color: p.ink3),
                        ),
                        if (_safeModeError != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _safeModeError!,
                            style: const TextStyle(fontSize: 10.5, height: 1.6, color: OlTokens.dangerDeep),
                          ),
                        ],
                        const SizedBox(height: 16),
                        // 用 Wrap 而不是 Row：三个操作 + 退出在窄窗口下会溢出。
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            OlPrimaryButton(
                              label: '重试',
                              icon: 'refresh',
                              height: 34,
                              onTap: _bootstrap,
                            ),
                            // 引擎「启动即崩」多半是某个存储源的驱动把进程带走了。
                            // 引擎没有「跳过某个源启动」的开关，只能先全部停用
                            // （改前备份 data.db），起来后再逐个启用排查。
                            OlGhostButton(
                              label: '安全模式启动',
                              icon: 'shield',
                              height: 34,
                              onTap: _startSafeMode,
                            ),
                            // 引擎起不来也不该挡着界面：进主界面后仍可看日志、
                            // 重启引擎、停用肇事的存储源（那些正是修复入口）。
                            OlGhostButton(
                              label: '先进入界面',
                              icon: 'external',
                              height: 34,
                              onTap: _enterDegraded,
                            ),
                            if (sidecar.logPath != null)
                              OlGhostButton(
                                label: '打开日志目录',
                                icon: 'folder',
                                height: 34,
                                onTap: () => _revealLog(sidecar),
                              ),
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
    // 0.5.1：与顶栏共用同一个品牌标记（品牌母版图片），
    // 不再手绘「渐变方块 + layers 线条图标」那套旧 Logo。
    return const OlMark(size: 42, radius: 12);
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
