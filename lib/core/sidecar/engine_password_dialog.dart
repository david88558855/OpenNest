import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/sidecar/sidecar_controller.dart';
import '../../core/sidecar/sidecar_state.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/ol_controls.dart';
import '../../core/widgets/ol_dialogs.dart';
import '../../core/widgets/ol_icon.dart';

/// 「查看内核 OpenList 密码」入口。
///
/// 引擎的管理员口令在首次初始化时随机生成，存进本机系统钥匙串
/// （`on:sidecar:admin`），此后每次启动都用它登录引擎 —— 因此钥匙串里
/// 的这一份就是「当前实例实际使用的口令」。用户偶尔需要它去手工调用
/// 引擎的管理接口（改口令、看任务等），所以提供明文查看。
///
/// 两种空状态都给出明确文案，不弹空白框：
/// - 内核未运行：无法确认「当前运行实例」的口令；
/// - 钥匙串里没有这一条目：换过机器或清过钥匙串。
Future<void> showEnginePasswordDialog(BuildContext context, WidgetRef ref) async {
  final sidecar = ref.read(sidecarProvider);
  final ready = sidecar.status == SidecarStatus.ready;

  String? password;
  String? error;
  if (!ready) {
    error = '内核当前未运行，无法读取正在使用的实例口令。启动引擎后再试。';
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

/// 明文展示口令的对话框，带一键复制。
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
