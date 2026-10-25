part of '../settings_page.dart';

/// 引擎状态分区：本机内嵌服务的运行信息与运维动作。
///
/// 这里取代了原有的「服务器管理」——新形态没有账号，也没有远端实例列表，
/// 用户需要看的是「引擎有没有跑起来、跑在哪个端口、数据落在哪」。
class _ServersSection extends ConsumerWidget {
  const _ServersSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final sidecar = ref.watch(sidecarProvider);
    final session = ref.watch(sessionProvider);
    final ready = sidecar.status == SidecarStatus.ready;
    final statusText = switch (sidecar.status) {
      SidecarStatus.ready => '运行中',
      SidecarStatus.starting => '启动中',
      SidecarStatus.failed => '已失败',
      SidecarStatus.stopped => '已停止',
      SidecarStatus.idle => '未启动',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHead(
          title: '引擎状态',
          subtitle: '内嵌引擎只监听本机回环地址，不对外开放',
          action: OlGhostButton(
            label: ready ? '重启引擎' : '启动引擎',
            icon: 'refresh',
            height: 28,
            fontSize: 10.5,
            onTap: () async {
              await ref.read(sidecarProvider.notifier).start(restart: ready);
              if (!context.mounted) return;
              await ref.read(sessionProvider.notifier).retry();
              if (!context.mounted) return;
              try {
                await ref.read(filesProvider.notifier).attach();
              } catch (_) {}
            },
          ),
        ),
        _Card(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  OlDot(
                    color: ready
                        ? OlTokens.ok
                        : (sidecar.status == SidecarStatus.failed ? OlTokens.dangerDeep : OlTokens.warn),
                    size: 7,
                  ),
                  const SizedBox(width: 8),
                  Text(statusText, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: p.ink)),
                  const SizedBox(width: 10),
                  OlBadge(
                    label: sidecar.engineVersion == null
                        ? 'OpenList 引擎'
                        : 'OpenList ${AppInfo.shortVersion(sidecar.engineVersion)}',
                    fg: const Color(0xFF075E7E),
                    bg: const Color(0xFFEAF8FE),
                  ),
                  const Spacer(),
                  if (sidecar.pid != null)
                    Text('进程 ${sidecar.pid}', style: TextStyle(fontSize: 10, color: p.ink4)),
                ],
              ),
              const SizedBox(height: 14),
              _EngineKv(
                label: '监听地址',
                value: sidecar.endpoint.isEmpty ? '—' : sidecar.endpoint,
                mono: true,
              ),
              _EngineKv(
                label: '引擎版本',
                value: AppInfo.shortVersion(sidecar.engineVersion ?? session.site?.version),
                mono: true,
              ),
              _EngineKv(label: '数据目录', value: ref.watch(prefsProvider).storagePath, mono: true),
              _EngineKv(label: '日志文件', value: sidecar.logPath ?? '—', mono: true),
              if (sidecar.error != null) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: OlTokens.dangerSurface,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: OlTokens.dangerBorder),
                  ),
                  child: Text(
                    sidecar.error!,
                    style: const TextStyle(
                      fontSize: 10,
                      height: 1.6,
                      color: OlTokens.dangerInk,
                      
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  OlGhostButton(
                    label: '打开日志目录',
                    icon: 'folder',
                    height: 28,
                    fontSize: 10.5,
                    onTap: () => _openPath(context, _dirOf(sidecar.logPath)),
                  ),
                  const SizedBox(width: 8),
                  OlGhostButton(
                    label: '打开数据目录',
                    icon: 'hard-drive',
                    height: 28,
                    fontSize: 10.5,
                    onTap: () => _openPath(context, _dirOf(ref.watch(prefsProvider).storagePath)),
                  ),
                ],
              ),
            ],
          ),
        ),
        _Card(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  OlIcon('key', size: 16, color: p.ink3),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('内核密码', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: p.ink)),
                        const SizedBox(height: 2),
                        Text(
                          '当前内嵌 OpenList 实例的管理员口令，明文显示',
                          style: TextStyle(fontSize: 10.5, color: p.ink3),
                        ),
                      ],
                    ),
                  ),
                  OlGhostButton(
                    label: '查看密码',
                    icon: 'eye',
                    height: 28,
                    fontSize: 10.5,
                    onTap: () => _showEnginePassword(context, ref),
                  ),
                ],
              ),
            ],
          ),
        ),
        _Card(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            children: [
              OlIcon('folder', size: 16, color: p.ink3),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('存储源', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: p.ink)),
                    const SizedBox(height: 2),
                    Text(
                      '添加本地目录、WebDAV、对象存储或网盘等存储源',
                      style: TextStyle(fontSize: 10.5, color: p.ink3),
                    ),
                  ],
                ),
              ),
              OlGhostButton(
                label: '管理',
                icon: 'chev-r',
                height: 28,
                fontSize: 10.5,
                onTap: () => context.push('/sources'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 展示当前内核实例的管理员口令。
  ///
  /// 口令明文显示（用户明确要求）：这是本机单用户场景，口令只对回环地址
  /// 上的内嵌引擎有效，展示它是为了让用户能手工调用引擎管理接口。
  /// 引擎未运行或钥匙串里没有这一条目时，给出明确的空状态说明，
  /// 而不是弹一个空框。
  Future<void> _showEnginePassword(BuildContext context, WidgetRef ref) async {
    final sidecar = ref.read(sidecarProvider);
    final ready = sidecar.status == SidecarStatus.ready;

    String? password;
    String? error;
    if (!ready) {
      error = '内核当前未运行，无法读取正在使用的实例口令。';
    } else {
      try {
        password = await ref.read(sidecarProvider.notifier).readAdminPassword();
      } catch (e) {
        error = '读取本机钥匙串失败：$e';
      }
      if (password == null && error == null) {
        error = '本机钥匙串中没有该实例的口令记录（可能换过机器或清过钥匙串）。';
      }
    }
    if (!context.mounted) return;

    await showOlDialog<void>(
      context: context,
      builder: (dialogContext) => _EnginePasswordDialog(
        password: password,
        error: error,
        endpoint: ready ? sidecar.endpoint : '',
      ),
    );
  }

  String _dirOf(String? path) {
    if (path == null || path.isEmpty) return '';
    final index = path.lastIndexOf(Platform.pathSeparator);
    return index <= 0 ? path : path.substring(0, index);
  }

  Future<void> _openPath(BuildContext context, String path) async {
    if (path.isEmpty) {
      olToast(context, '路径不可用');
      return;
    }
    try {
      if (Platform.isWindows) {
        await Process.run('explorer', [path]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [path]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [path]);
      } else {
        olToast(context, path);
      }
    } catch (error) {
      if (context.mounted) olToast(context, '无法打开：$error');
    }
  }
}

class _EngineKv extends StatelessWidget {
  final String label;
  final String value;
  final bool mono;

  const _EngineKv({required this.label, required this.value, this.mono = false});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 72, child: Text(label, style: TextStyle(fontSize: 10.5, color: p.ink3))),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: mono ? 10.5 : 11.5,
                color: p.ink2,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 「查看内核密码」对话框：明文显示口令，带复制按钮。
///
/// 口令缺失或引擎未运行时显示空状态说明（红色提示块），不弹空白内容。
class _EnginePasswordDialog extends StatelessWidget {
  final String? password;
  final String? error;
  final String endpoint;

  const _EnginePasswordDialog({this.password, this.error, this.endpoint = ''});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    final failed = password == null || password!.isEmpty;
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 420,
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: p.line),
            boxShadow: const [
              BoxShadow(color: Color(0x1F0E3A46), blurRadius: 40, offset: Offset(0, 14)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  OlIcon('key', size: 16, color: failed ? OlTokens.dangerDeep : p.ink2),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      '内核 OpenList 密码',
                      style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: p.ink),
                    ),
                  ),
                  OlIconButton(icon: 'x', size: 28, iconSize: 13, onTap: () => context.pop()),
                ],
              ),
              const SizedBox(height: 12),
              if (failed)
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: OlTokens.dangerSurface,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: OlTokens.dangerBorder),
                  ),
                  child: Text(
                    error ?? '暂无可用的内核密码。',
                    style: const TextStyle(fontSize: 11.5, height: 1.6, color: OlTokens.dangerInk),
                  ),
                )
              else ...[
                Text(
                  endpoint.isEmpty ? '管理员账号：admin' : '管理员账号：admin · 实例地址：$endpoint',
                  style: TextStyle(fontSize: 11, color: p.ink3),
                ),
                const SizedBox(height: 8),
                // 明文展示（用户明确要求）：不做掩码，右侧一键复制。
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                  decoration: BoxDecoration(
                    color: p.surface,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: p.line),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          password!,
                          style: const TextStyle(fontSize: 12.5, height: 1.5, color: Color(0xFF0D1B2A)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: () async {
                          await copyToClipboard(password!);
                          if (context.mounted) olToast(context, '密码已复制到剪贴板');
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                          decoration: BoxDecoration(
                            color: p.card,
                            borderRadius: BorderRadius.circular(7),
                            border: Border.all(color: p.line),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              OlIcon('copy', size: 12, color: p.ink3),
                              const SizedBox(width: 5),
                              Text('复制', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: p.ink2)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  '口令仅存于本机系统钥匙串，只对本机回环地址上的内嵌引擎有效。',
                  style: TextStyle(fontSize: 10.5, height: 1.6, color: p.ink4),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OlGhostButton(label: '关闭', height: 32, fontSize: 12, onTap: () => context.pop()),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
