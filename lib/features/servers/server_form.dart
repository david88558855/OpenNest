import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/models/server_profile.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/ol_controls.dart';
import '../../core/widgets/ol_dialogs.dart';
import '../../core/widgets/ol_icon.dart';

/// Add / edit form used by the W8 right rail and the mobile edit route.
class ServerForm extends ConsumerStatefulWidget {
  final ServerProfile? profile;
  final VoidCallback? onSaved;
  final VoidCallback? onDeleted;
  final VoidCallback? onClose;

  const ServerForm({super.key, this.profile, this.onSaved, this.onDeleted, this.onClose});

  @override
  ConsumerState<ServerForm> createState() => _ServerFormState();
}

class _ServerFormState extends ConsumerState<ServerForm> {
  late final TextEditingController _name = TextEditingController(text: widget.profile?.name ?? '');
  late final TextEditingController _url = TextEditingController(text: widget.profile?.baseUrl ?? '');
  late final TextEditingController _user = TextEditingController(text: widget.profile?.username ?? '');
  final _secret = TextEditingController();
  late AuthMode _mode = widget.profile?.mode ?? AuthMode.password;
  late bool _isolatedDownload = widget.profile?.isolatedDownload ?? true;
  late bool _isolatedCache = widget.profile?.isolatedCache ?? true;
  late bool _rememberBrowse = widget.profile?.rememberBrowse ?? true;
  bool _obscure = true;
  bool _saving = false;
  String? _error;
  int? _latency;
  bool _testing = false;

  bool get _isNew => widget.profile == null;

  /// 显示名称是否已被其它条目占用（v1.0.18）。
  ///
  /// 唯一的约束落在**显示名称**上：地址允许重复（同一个实例可以用不同账号 /
  /// 不同备注各存一条），但列表里不能出现两个同名条目，否则切换与删除时分不清。
  /// 编辑时排除自身。
  bool _nameTaken(String name, {String? exceptId}) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return false;
    return ref.read(serverListProvider).servers.any((s) => s.id != exceptId && s.name.trim() == trimmed);
  }

  @override
  void didUpdateWidget(covariant ServerForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile?.id != widget.profile?.id) {
      _name.text = widget.profile?.name ?? '';
      _url.text = widget.profile?.baseUrl ?? '';
      _user.text = widget.profile?.username ?? '';
      _secret.clear();
      _mode = widget.profile?.mode ?? AuthMode.password;
      _isolatedDownload = widget.profile?.isolatedDownload ?? true;
      _isolatedCache = widget.profile?.isolatedCache ?? true;
      _rememberBrowse = widget.profile?.rememberBrowse ?? true;
      _error = null;
      _latency = null;
      setState(() {});
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _user.dispose();
    _secret.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _latency = null;
      _error = null;
    });
    final result = await ref.read(sessionProvider.notifier).probe(_url.text);
    if (!mounted) return;
    setState(() {
      _testing = false;
      _latency = result.ok ? result.latencyMs : null;
      if (!result.ok) _error = result.error;
    });
  }

  Future<void> _save() async {
    final urlError = validateBaseUrl(_url.text);
    if (urlError != null) {
      setState(() => _error = urlError);
      return;
    }
    final base = normalizeBaseUrl(_url.text);
    final existing = widget.profile;
    final desiredName = _name.text.trim();

    // v1.0.18：提交时先校验显示名称唯一（地址不做限制）。
    // 名称留空时最终会用服务端站点标题，那种情况交给 session.connect 里再判一次。
    if (_nameTaken(desiredName, exceptId: existing?.id)) {
      setState(() => _error = '该显示名称已存在');
      return;
    }

    final urlChanged = existing != null && base != existing.baseUrl;
    final needsAuth = existing == null ||
        urlChanged ||
        _user.text.trim() != existing.username ||
        _mode != existing.mode ||
        _secret.text.isNotEmpty;

    setState(() {
      _saving = true;
      _error = null;
    });

    if (needsAuth) {
      if (_secret.text.isEmpty) {
        setState(() {
          _saving = false;
          _error = _mode == AuthMode.token ? '请填写 API Token' : '请填写密码以验证连接';
        });
        return;
      }
      final error = await ref.read(sessionProvider.notifier).connect(
            mode: _mode,
            baseUrl: base,
            username: _user.text,
            secret: _secret.text,
            displayName: _name.text,
            existingId: existing?.id,
          );
      if (!mounted) return;
      if (error != null) {
        setState(() {
          _saving = false;
          _error = error;
        });
        return;
      }
      final profile = ref.read(sessionProvider).profile;
      if (profile != null) {
        await ref.read(serverListProvider.notifier).upsert(profile.copyWith(
              isolatedDownload: _isolatedDownload,
              isolatedCache: _isolatedCache,
              rememberBrowse: _rememberBrowse,
            ));
      }
    } else {
      await ref.read(serverListProvider.notifier).upsert(existing.copyWith(
            name: _name.text.trim().isEmpty ? existing.name : _name.text.trim(),
            baseUrl: base,
            username: _user.text.trim(),
            mode: _mode,
            isolatedDownload: _isolatedDownload,
            isolatedCache: _isolatedCache,
            rememberBrowse: _rememberBrowse,
          ));
    }

    if (!mounted) return;
    setState(() => _saving = false);
    olToast(context, _isNew ? '服务器已添加' : '已保存更改');
    widget.onSaved?.call();
  }

  Future<void> _delete() async {
    final profile = widget.profile;
    if (profile == null) return;
    final confirmed = await olConfirm(
      context,
      title: '删除「${profile.name}」',
      message: '只移除本地配置与系统钥匙串中的凭据，不影响服务端数据。删除后如果它是当前服务器，会自动切换。',
      confirm: '删除',
      danger: true,
    );
    if (!confirmed) return;
    final wasActive = ref.read(serverListProvider).activeId == profile.id;
    await ref.read(serverListProvider.notifier).remove(profile.id);
    if (wasActive) {
      await ref.read(sessionProvider.notifier).retry();
    }
    if (!mounted) return;
    olToast(context, '已删除 ${profile.name}');
    widget.onDeleted?.call();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(color: p.isDark ? const Color(0xFF12202F) : const Color(0xFFE9F8FF), borderRadius: BorderRadius.circular(8)),
                child: Center(child: OlIcon('server', size: 13, color: const Color(0xFF0A93C4))),
              ),
              const SizedBox(width: 8),
              Text(
                _isNew ? '添加服务器' : '编辑服务器',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: p.ink),
              ),
              const Spacer(),
              if (!_isNew && ref.watch(serverListProvider).activeId == widget.profile?.id)
                const OlBadge(label: '当前连接'),
              if (widget.onClose != null)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: OlIconButton(icon: 'x', size: 22, iconSize: 12, onTap: widget.onClose),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _label('显示名称'),
          OlField(
            controller: _name,
            icon: 'edit',
            hint: '家庭主服务器',
            dense: true,
            // 改名即清掉上一次的重名提示，避免「改好了还挂着红字」
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          const SizedBox(height: 8),
          _label('服务器地址'),
          OlField(controller: _url, icon: 'globe', hint: 'https://pan.mydomain.com', dense: true, keyboardType: TextInputType.url),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _label('用户名'),
                    OlField(controller: _user, icon: 'user', hint: 'admin', dense: true),
                  ],
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _label(_mode == AuthMode.token ? 'API Token' : '密码', trailing: _isNew ? null : '留空不改'),
                    OlField(
                      controller: _secret,
                      icon: _mode == AuthMode.token ? 'key' : 'lock',
                      hint: _mode == AuthMode.token ? 'token' : '••••••••',
                      dense: true,
                      obscure: _obscure,
                      trailing: GestureDetector(
                        onTap: () => setState(() => _obscure = !_obscure),
                        child: Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: OlIcon(_obscure ? 'eye' : 'eye-off', size: 13, color: p.ink4),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _label('认证方式'),
          OlSeg<AuthMode>(
            items: const [OlSegItem(AuthMode.password, '密码'), OlSegItem(AuthMode.token, 'API Token')],
            value: _mode,
            onChanged: (v) => setState(() => _mode = v),
            height: 22,
          ),
          const SizedBox(height: 8),
          _label('隔离选项'),
          _SwitchRow(label: '独立下载目录', value: _isolatedDownload, onChanged: (v) => setState(() => _isolatedDownload = v)),
          _SwitchRow(label: '独立媒体缓存', value: _isolatedCache, onChanged: (v) => setState(() => _isolatedCache = v)),
          _SwitchRow(label: '记住浏览位置', value: _rememberBrowse, onChanged: (v) => setState(() => _rememberBrowse = v)),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(padding: EdgeInsets.only(top: 1), child: OlIcon('alert', size: 11, color: Color(0xFFE8476F))),
                  const SizedBox(width: 5),
                  Expanded(child: Text(_error!, style: const TextStyle(fontSize: 9.5, height: 1.5, color: Color(0xFFE8476F), fontWeight: FontWeight.w600))),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: p.line2, style: BorderStyle.solid))),
            child: Row(
              children: [
                Text(
                  _testing ? '连接测试中…' : (_latency != null ? '连接测试 正常 · $_latency ms' : '连接测试'),
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: _latency != null ? OlTokens.okDeep : p.ink4),
                ),
                const Spacer(),
                OlChip(label: _testing ? '测试中' : '重新测试', selected: false, height: 22, onTap: _testing ? null : _test),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OlPrimaryButton(
                  label: _isNew ? '添加并登录' : '保存更改',
                  expand: true,
                  busy: _saving,
                  onTap: _saving ? null : _save,
                ),
              ),
              if (!_isNew) ...[
                const SizedBox(width: 7),
                OlDangerButton(label: '删除', icon: 'trash', onTap: _saving ? null : _delete),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _label(String text, {String? trailing}) {
    final p = context.ol;
    return Padding(
      padding: const EdgeInsets.only(left: 1, bottom: 4),
      child: Row(
        children: [
          Text(text, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: p.ink3)),
          const Spacer(),
          if (trailing != null) Text(trailing, style: TextStyle(fontSize: 8.5, color: p.ink4)),
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchRow({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: p.ink2)),
          const Spacer(),
          OlSwitch(value: value, onChanged: onChanged, small: true),
        ],
      ),
    );
  }
}
