import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/frame.dart';
import '../../app/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/ol_controls.dart';
import 'server_form.dart';

class ServerEditPage extends ConsumerWidget {
  final String serverId;
  const ServerEditPage({super.key, required this.serverId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servers = ref.watch(serverListProvider).servers;
    final profile = servers.where((e) => e.id == serverId).toList();
    final narrow = MediaQuery.sizeOf(context).width < 900;
    final form = ServerForm(
      profile: profile.isEmpty ? null : profile.first,
      // v1.0.16：从服务器管理 push 进来 → 回列表；从登录页 / 标题栏直接进来（无栈）
      // → 进文件页。之前无条件 go('/files')，从列表点「编辑」保存后会莫名跳到文件页。
      onSaved: () => _back(context),
      onDeleted: () => _back(context),
    );

    if (!narrow) {
      final p = context.ol;
      return AppFrame(
        showNav: false,
        child: Column(
          children: [
            // v2.6：独立页面的返回栏。之前这里复用了设置侧栏，
            // 从标题栏进来后会看不到回文件页的入口。
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.hairline))),
              child: Row(
                children: [
                  OlIconButton(icon: 'chev-l', size: 30, iconSize: 18, onTap: () => _back(context)),
                  const SizedBox(width: 6),
                  Text(
                    profile.isEmpty ? '添加服务器' : '编辑服务器',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: p.ink),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                color: p.card,
                alignment: Alignment.topCenter,
                padding: const EdgeInsets.only(top: 20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Container(
                    decoration: BoxDecoration(
                      color: p.surfaceAlt,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: p.line2),
                    ),
                    child: form,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final p = context.ol;
    return Scaffold(
      backgroundColor: p.card,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  OlIconButton(icon: 'chev-l', size: 30, iconSize: 18, onTap: () => _back(context)),
                  const SizedBox(width: 4),
                  Text(
                    profile.isEmpty ? '添加服务器' : '编辑服务器',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: p.ink),
                  ),
                ],
              ),
            ),
            Expanded(child: form),
          ],
        ),
      ),
    );
  }
}

/// 编辑页返回：优先出栈（从服务器列表 push 进来时），否则直接进文件页。
///
/// v2.6：之前兜底是 go('/servers')，从标题栏 / 登录页直接进来时（没有栈）
/// 保存完会停在服务器列表动不了；现在保存后直接回到文件页，切换即时生效。
void _back(BuildContext context) {
  if (GoRouter.of(context).canPop()) {
    context.pop();
  } else {
    context.go('/files');
  }
}
