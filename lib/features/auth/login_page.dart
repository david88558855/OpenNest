import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app.dart';
import '../../app/frame.dart';
import '../../app/providers.dart';
import '../../core/models/server_profile.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/ol_controls.dart';
import '../../core/widgets/ol_icon.dart';

/// W1（Windows 连接服务器）/ A1（Android 沉浸式登录）。
///
/// 设计稿约束：
///   - 左侧 56% 深色品牌区（品牌行 / 主张 / 三条卖点 / 挂载点卡），右侧白底表单 326；
///   - 地址、用户名、密码、保持登录、主按钮、OR、Token 登录、服务器管理入口；
///   - 「服务器管理」入口在 0 个已保存服务器时也必须显示（08 验收标准）；
///   - 校验失败一律内联提示，不弹窗。
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _url = TextEditingController();
  final _user = TextEditingController(text: 'admin');
  final _secret = TextEditingController();
  final _name = TextEditingController();

  AuthMode _mode = AuthMode.password;
  bool _keepSignedIn = true;
  bool _obscure = true;
  bool _busy = false;

  String? _inlineError;
  String? _probeOk;
  int? _probeMs;

  @override
  void initState() {
    super.initState();
    final active = ref.read(serverListProvider).active;
    if (active != null) {
      _url.text = active.baseUrl;
      _user.text = active.username;
      _name.text = active.name;
      _mode = active.mode;
    }
  }

  @override
  void dispose() {
    _url.dispose();
    _user.dispose();
    _secret.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final urlError = validateBaseUrl(_url.text);
    if (urlError != null) {
      setState(() => _inlineError = urlError);
      return;
    }
    setState(() {
      _busy = true;
      _inlineError = null;
    });
    final error = await ref.read(sessionProvider.notifier).connect(
          mode: _mode,
          baseUrl: _url.text,
          username: _user.text,
          secret: _secret.text.trim(),
          displayName: _name.text.trim(),
          persistToken: _keepSignedIn,
        );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _inlineError = error;
    });
    if (error == null) context.go('/files');
  }

  Future<void> _probe() async {
    final raw = _url.text.trim();
    if (raw.isEmpty) return;
    final result = await ref.read(sessionProvider.notifier).probe(raw);
    if (!mounted) return;
    setState(() {
      _inlineError = result.ok ? null : result.error;
      _probeOk = result.ok ? (result.site?.title ?? 'OpenList') : null;
      _probeMs = result.ok ? result.latencyMs : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (context.isNarrow) return _buildMobile(context);
    return _buildDesktop(context);
  }

  // ------------------------------------------------------------- W1 · Windows
  Widget _buildDesktop(BuildContext context) {
    final p = context.ol;
    return Scaffold(
      backgroundColor: p.card,
      body: Column(
        children: [
          const OlTitleBar(),
          Expanded(
            child: Row(
              children: [
                const Expanded(flex: 56, child: _BrandPanel()),
                Expanded(
                  flex: 44,
                  child: ColoredBox(
                    color: p.card,
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                        child: SizedBox(width: 326, child: _buildForm(context)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- A1 · Android
  Widget _buildMobile(BuildContext context) {
    return OlDarkScaffold(
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          children: [
            SizedBox(height: MediaQuery.paddingOf(context).top + 28),
            const Row(
              children: [
                OlMark(size: 30, radius: 9, iconSize: 15),
                SizedBox(width: 9),
                Text('OpenList', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFFEAF5FC), letterSpacing: -0.2)),
              ],
            ),
            const SizedBox(height: 46),
            const Text('SELF-HOSTED CLOUD', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 2.2, color: Color(0xFF7DD3FC))),
            const SizedBox(height: 11),
            RichText(
              text: const TextSpan(
                style: TextStyle(fontSize: 34, height: 1.06, letterSpacing: -1.4, fontWeight: FontWeight.w800, color: Colors.white),
                children: [
                  TextSpan(text: '所有云盘，\n收进'),
                  TextSpan(text: '一个窗口', style: TextStyle(color: Color(0xFF5EEAD4))),
                  TextSpan(text: '。'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '连接自建 OpenList，聚合阿里云盘、夸克、OneDrive 与 NAS。文件直连，不经过第三方。',
              style: TextStyle(fontSize: 11.5, height: 1.65, color: Color(0xFF8FA8BD)),
            ),
            const SizedBox(height: 26),
            OlDarkField(
              controller: _url,
              icon: 'globe',
              hint: 'https://pan.mydomain.com',
              keyboardType: TextInputType.url,
              onSubmitted: (_) => _probe(),
            ),
            const SizedBox(height: 10),
            OlDarkField(controller: _user, icon: 'user', hint: _mode == AuthMode.token ? '账号（可选）' : 'admin'),
            const SizedBox(height: 10),
            OlDarkField(
              controller: _secret,
              icon: _mode == AuthMode.token ? 'key' : 'lock',
              hint: _mode == AuthMode.token ? 'API Token' : '••••••••',
              obscure: _obscure,
              onSubmitted: (_) => _submit(),
              trailing: GestureDetector(
                onTap: () => setState(() => _obscure = !_obscure),
                child: OlIcon(_obscure ? 'eye-off' : 'eye', size: 16, color: const Color(0xFF6E879C)),
              ),
            ),
            if (_inlineError != null) ...[
              const SizedBox(height: 10),
              _InlineError(_inlineError!),
            ],
            if (_probeOk != null) ...[
              const SizedBox(height: 10),
              _ProbeOk(_probeOk!, _probeMs),
            ],
            const SizedBox(height: 18),
            OlPrimaryButton(
              label: '连接并登录',
              icon: 'zap',
              height: 46,
              fontSize: 13,
              expand: true,
              busy: _busy,
              onTap: _busy ? null : _submit,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                OlSwitch(value: _keepSignedIn, small: true, onChanged: (v) => setState(() => _keepSignedIn = v)),
                const SizedBox(width: 8),
                const Text('保持登录', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFF8FA8BD))),
                const Spacer(),
                _ModeLink(mode: _mode, onTap: () => setState(() => _mode = _mode == AuthMode.password ? AuthMode.token : AuthMode.password)),
              ],
            ),
            const SizedBox(height: 22),
            const _ServerEntry(dark: true),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------ 共享表单主体
  Widget _buildForm(BuildContext context) {
    final p = context.ol;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('WELCOME BACK', style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, letterSpacing: 2.2, color: OlTokens.sky600)),
        const SizedBox(height: 9),
        Text('连接到你的服务器', style: TextStyle(fontSize: 25, height: 1.15, letterSpacing: -0.9, fontWeight: FontWeight.w800, color: p.ink)),
        const SizedBox(height: 7),
        Text('输入 OpenList 地址，客户端会自动探测版本与站点名称。', style: TextStyle(fontSize: 10.5, height: 1.6, color: p.ink3)),
        const SizedBox(height: 22),
        const _FieldLabel('服务器地址', hint: '含协议与端口'),
        const SizedBox(height: 6),
        OlField(
          controller: _url,
          icon: 'globe',
          hint: 'https://pan.mydomain.com',
          keyboardType: TextInputType.url,
          onSubmitted: (_) => _probe(),
          trailing: _ProbePill(ok: _probeOk, onTap: _probe),
        ),
        if (_inlineError != null) ...[const SizedBox(height: 8), _InlineError(_inlineError!)],
        if (_probeOk != null) ...[const SizedBox(height: 8), _ProbeOk(_probeOk!, _probeMs)],
        const SizedBox(height: 12),
        const _FieldLabel('用户名'),
        const SizedBox(height: 6),
        OlField(controller: _user, icon: 'user', hint: 'admin'),
        const SizedBox(height: 12),
        _FieldLabel(_mode == AuthMode.token ? 'API Token' : '密码'),
        const SizedBox(height: 6),
        OlField(
          controller: _secret,
          icon: _mode == AuthMode.token ? 'key' : 'lock',
          hint: _mode == AuthMode.token ? '粘贴服务端生成的 Token' : '••••••••',
          obscure: _obscure,
          onSubmitted: (_) => _submit(),
          trailing: GestureDetector(
            onTap: () => setState(() => _obscure = !_obscure),
            child: OlIcon(_obscure ? 'eye-off' : 'eye', size: 15, color: p.ink4),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            OlSwitch(value: _keepSignedIn, small: true, onChanged: (v) => setState(() => _keepSignedIn = v)),
            const SizedBox(width: 8),
            Text('保持登录', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: p.ink2)),
            const Spacer(),
            _ModeLink(mode: _mode, onTap: () => setState(() => _mode = _mode == AuthMode.password ? AuthMode.token : AuthMode.password)),
          ],
        ),
        const SizedBox(height: 18),
        OlPrimaryButton(
          label: '连接并登录',
          icon: 'arrow-up',
          height: 42,
          fontSize: 12,
          expand: true,
          busy: _busy,
          onTap: _busy ? null : _submit,
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: Container(height: 1, color: p.line2)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9),
              child: Text('OR', style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, letterSpacing: 1.4, color: p.ink4)),
            ),
            Expanded(child: Container(height: 1, color: p.line2)),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: OlGhostButton(
            label: '使用 API Token 登录',
            icon: 'key',
            height: 36,
            fontSize: 10.5,
            onTap: () => setState(() => _mode = _mode == AuthMode.token ? AuthMode.password : AuthMode.token),
          ),
        ),
        const SizedBox(height: 22),
        const _ServerEntry(dark: false),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 表单零件
// ---------------------------------------------------------------------------
class _FieldLabel extends StatelessWidget {
  final String text;
  final String? hint;
  const _FieldLabel(this.text, {this.hint});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Row(
        children: [
          Text(text, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: p.ink3)),
          if (hint != null) ...[
            const Spacer(),
            Text(hint!, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: p.ink4)),
          ],
        ],
      ),
    );
  }
}

class _ModeLink extends StatelessWidget {
  final AuthMode mode;
  final VoidCallback onTap;
  const _ModeLink({required this.mode, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    final token = mode == AuthMode.token;
    return GestureDetector(
      onTap: onTap,
      child: Text(
        token ? '改用密码登录' : '忘记密码？',
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: token ? OlTokens.sky700 : p.ink3),
      ),
    );
  }
}

class _ProbePill extends StatelessWidget {
  final String? ok;
  final VoidCallback onTap;
  const _ProbePill({required this.ok, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final done = ok != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: done ? const Color(0xFFE7FBF5) : const Color(0xFFF3F8FC),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OlDot(color: done ? OlTokens.teal600 : const Color(0xFFB2C1CF), size: 4),
            const SizedBox(width: 4),
            Text(
              done ? '已连接' : '探测',
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: done ? OlTokens.okDeep : const Color(0xFF8FA1B3)),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  final String message;
  const _InlineError(this.message);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const OlIcon('alert', size: 13, color: OlTokens.dangerDeep),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(fontSize: 10.5, height: 1.5, fontWeight: FontWeight.w600, color: OlTokens.dangerDeep),
          ),
        ),
      ],
    );
  }
}

class _ProbeOk extends StatelessWidget {
  final String title;
  final int? ms;
  const _ProbeOk(this.title, this.ms);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const OlIcon('check', size: 13, color: OlTokens.okDeep),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            ms == null ? '$title · 已连接' : '$title · 已连接 ${ms}ms',
            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: OlTokens.okDeep),
          ),
        ),
      ],
    );
  }
}

/// 「服务器管理」入口 —— 0 个已保存时也必须可见（08 验收标准）。
class _ServerEntry extends StatelessWidget {
  final bool dark;
  const _ServerEntry({required this.dark});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    final fg = dark ? const Color(0xFFCFE6F3) : p.ink;
    final sub = dark ? const Color(0xFF6E879C) : p.ink4;
    final bg = dark ? const Color(0x0FFFFFFF) : p.surfaceAlt;
    final border = dark ? const Color(0x1AFFFFFF) : p.line;
    return GestureDetector(
      onTap: () => context.push('/servers'),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: dark ? const Color(0x1A7DD3FC) : const Color(0xFFE9F8FF),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Center(child: OlIcon('server', size: 15, color: dark ? const Color(0xFF7DD3FC) : const Color(0xFF0A93C4))),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('服务器管理', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: fg)),
                    const SizedBox(height: 2),
                    Text('切换 / 添加 / 编辑，数量不限', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: sub)),
                  ],
                ),
              ),
              OlIcon('chev-r', size: 14, color: sub),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// W1 · 左侧品牌区
// ---------------------------------------------------------------------------
class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF08141F), Color(0xFF07121C), Color(0xFF05101A)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(left: -120, top: -160, child: _glow(460, const Color(0x330C3A4E))),
          Positioned(right: -140, top: -40, child: _glow(360, const Color(0x382DD4BF))),
          Padding(
            padding: const EdgeInsets.fromLTRB(40, 36, 32, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    OlMark(size: 30, radius: 9, iconSize: 15),
                    SizedBox(width: 9),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('OpenNest', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Color(0xFFE8F2FA), letterSpacing: -0.2)),
                        SizedBox(height: 1),
                        Text('WINDOWS EDITION', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 1.4, color: Color(0xFF7E97AC))),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 68),
                const Text('YOUR CLOUDS, ONE WINDOW', style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, letterSpacing: 2.6, color: Color(0xFF7DD3FC))),
                const SizedBox(height: 14),
                RichText(
                  text: const TextSpan(
                    style: TextStyle(fontSize: 41, height: 1.06, letterSpacing: -1.8, fontWeight: FontWeight.w800, color: Color(0xFFF4FAFF)),
                    children: [
                      TextSpan(text: '所有云盘，\n收进'),
                      TextSpan(text: '一个窗口', style: TextStyle(color: Color(0xFF5EEAD4))),
                      TextSpan(text: '。'),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const SizedBox(
                  width: 330,
                  child: Text(
                    '直连你自建的 OpenList 服务。文件不中转、不落第三方，速度只取决于你的带宽。',
                    style: TextStyle(fontSize: 11.5, height: 1.8, color: Color(0xFF8FA8BD)),
                  ),
                ),
                const Spacer(),
                const _Feature(icon: 'zap', title: '原生多线程传输', desc: '断点续传、并发可调、托盘后台不中断'),
                const _Feature(icon: 'play', title: '边下边播', desc: '支持 4K HDR 与字幕轨道，Range 直读不落地'),
                const _Feature(icon: 'shield', title: '凭据本地保存', desc: 'Token 写入 Windows 凭据管理器，可随时吊销'),
                const SizedBox(height: 20),
                const _MountedCard(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _glow(double size, Color color) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [color, color.withAlpha(0)])),
      );
}

class _Feature extends StatelessWidget {
  final String icon;
  final String title;
  final String desc;
  const _Feature({required this.icon, required this.title, required this.desc});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: const Color(0x1A7DD3FC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0x297DD3FC)),
            ),
            child: Center(child: OlIcon(icon, size: 13, color: const Color(0xFF7DD3FC))),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFFD6E4EF))),
                const SizedBox(height: 2),
                Text(desc, style: const TextStyle(fontSize: 9, height: 1.5, color: Color(0xFF7E97AC))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MountedCard extends StatelessWidget {
  const _MountedCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 330,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0x0FFFFFFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x1AFFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('MOUNTED', style: TextStyle(fontSize: 7.5, fontWeight: FontWeight.w800, letterSpacing: 2, color: Color(0xFF5E82A0))),
              const Spacer(),
              const Text('5 SOURCES', style: TextStyle(fontSize: 7.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: Color(0xFF3E6480))),
            ],
          ),
          const SizedBox(height: 8),
          const _MountRow('阿里云盘', '2.4 TB', Color(0xFF38BDF8)),
          const _MountRow('OneDrive', '1.0 TB', Color(0xFF7DD3FC)),
          const _MountRow('本地 NAS', '8.0 TB', Color(0xFFC4B5FD)),
          const SizedBox(height: 6),
          Row(
            children: [
              Container(width: 14, height: 1, color: const Color(0x5538BDF8)),
              const SizedBox(width: 5),
              const Text('统一命名空间 · 一棵目录树', style: TextStyle(fontSize: 7.5, letterSpacing: 0.4, color: Color(0xFF5E82A0))),
            ],
          ),
        ],
      ),
    );
  }
}

class _MountRow extends StatelessWidget {
  final String name;
  final String size;
  final Color color;
  const _MountRow(this.name, this.size, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0x8C0A1A28),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0x217DD3FC)),
      ),
      child: Row(
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 7),
          Expanded(child: Text(name, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFFC3D8E8)))),
          Text(size, style: const TextStyle(fontSize: 8, color: Color(0xFF6E8DA6))),
          const SizedBox(width: 6),
          Container(width: 4, height: 4, decoration: const BoxDecoration(color: Color(0xE62DD4BF), shape: BoxShape.circle)),
        ],
      ),
    );
  }
}
