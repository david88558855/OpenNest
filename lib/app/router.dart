import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/sidecar/sidecar_controller.dart';
import '../core/sidecar/sidecar_state.dart';
import '../core/theme/tokens.dart';
import '../features/boot/boot_entry.dart';
import '../features/boot/boot_page.dart';
import '../features/files/files_page.dart';
import '../features/media/player_page.dart';
import '../features/onboarding/onboarding_page.dart';
import '../features/preview/preview_page.dart';
import '../features/search/search_page.dart';
import '../features/settings/settings_page.dart';
import '../features/sources/add_source_page.dart';
import '../features/transfers/transfers_page.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.onDispose(refresh.dispose);
  // 引擎就绪 / 失败是唯一的路由门禁：没有账号，也就没有登录态。
  ref.listen<SidecarState>(sidecarProvider, (previous, next) {
    if (previous?.status != next.status) {
      // 引擎离开就绪（设置页重启、崩溃）时把落点判定复位：
      // 否则重启后 redirect 会按上一次的判定抢跳 /files，而此时会话还没 boot。
      if (next.status != SidecarStatus.ready) {
        ref.read(bootEntryProvider.notifier).state = BootEntry.unknown;
      }
      refresh.value++;
    }
  });

  return GoRouter(
    initialLocation: '/boot',
    refreshListenable: refresh,
    redirect: (context, state) {
      final status = ref.read(sidecarProvider).status;
      final path = state.uri.path;
      final onBoot = path == '/boot';
      // 只有「明确不可用」才拦到启动页；「启动中」允许停留在当前页面
      // （从设置里重启引擎时不会被弹走）。
      final blocked = status == SidecarStatus.failed ||
          status == SidecarStatus.idle ||
          status == SidecarStatus.stopped;
      if (blocked && !onBoot) return '/boot';
      if (status == SidecarStatus.ready && onBoot) {
        // 落点由启动页判定一次后写入；判定前（unknown）留在启动页，不要抢跳。
        switch (ref.read(bootEntryProvider)) {
          case BootEntry.unknown:
            return null;
          case BootEntry.welcome:
            return '/welcome';
          case BootEntry.files:
            return '/files';
        }
      }
      return null;
    },
    errorBuilder: (context, state) => _RouteError(message: state.error?.toString() ?? '页面不存在'),
    routes: [
      GoRoute(path: '/', redirect: (context, state) => '/boot'),
      GoRoute(path: '/boot', pageBuilder: (context, state) => _page(state, const BootPage())),
      // 首启空状态（D1/M1）。不做 redirect 守卫：首启只在启动页判定一次，
      // 手动进入（自测）也要能打开。
      GoRoute(path: '/welcome', pageBuilder: (context, state) => _page(state, const OnboardingPage())),
      GoRoute(
        path: '/files',
        pageBuilder: (context, state) => _page(state, FilesPage(initialPath: state.uri.queryParameters['path'])),
      ),
      GoRoute(path: '/transfers', pageBuilder: (context, state) => _page(state, const TransfersPage())),
      // 0.5.0：存储源并入设置页，成为一个分区。旧地址保留为重定向，
      // 外部深链与书签不会 404。
      GoRoute(path: '/sources', redirect: (context, state) => '/settings/sources'),
      GoRoute(
        path: '/sources/add',
        pageBuilder: (context, state) {
          final query = state.uri.queryParameters;
          // 分享链接导入：把识别出的通用字段带进表单（share_id / share_pwd / url）。
          final prefill = <String, String>{
            for (final key in const ['share_id', 'share_pwd', 'url'])
              if ((query[key] ?? '').trim().isNotEmpty) key: query[key]!.trim(),
          };
          return _page(
            state,
            AddSourcePage(
              initialDriver: query['driver'],
              initialPrefill: prefill.isEmpty ? null : prefill,
            ),
          );
        },
      ),
      GoRoute(
        path: '/search',
        pageBuilder: (context, state) => _page(state, SearchPage(initialQuery: state.uri.queryParameters['q'] ?? '')),
      ),
      GoRoute(
        path: '/settings',
        // 'root' 是显式哨兵：移动端用它判定「显示我的列表」，桌面归一化成外观分区。
        pageBuilder: (context, state) => _page(state, SettingsPage(tab: state.uri.queryParameters['tab'] ?? 'root')),
      ),
      // 设置分区用独立路径：只改 query 时同一条路由不会重建页面。
      //
      // 0.5.0：分区按设计稿 D8 重划为 通用 / 存储源 / 传输 / 播放 / 关于。
      // 旧分区名（servers / download / appearance）保留重定向，避免深链 404。
      GoRoute(
        path: '/settings/:tab',
        redirect: (context, state) {
          final tab = state.pathParameters['tab'] ?? 'general';
          return '/settings/${SettingsPage.normalizeTab(tab)}';
        },
        pageBuilder: (context, state) => _page(state, SettingsPage(tab: state.pathParameters['tab'] ?? 'general')),
      ),
      GoRoute(
        path: '/preview',
        pageBuilder: (context, state) => _page(
          state,
          PreviewPage(
            path: state.uri.queryParameters['path'] ?? '',
            name: state.uri.queryParameters['name'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: '/player',
        pageBuilder: (context, state) => _page(
          state,
          PlayerPage(
            path: state.uri.queryParameters['path'] ?? '',
            name: state.uri.queryParameters['name'] ?? '',
          ),
        ),
      ),
    ],
  );
});

/// 所有路由都用「零时长」页面，避免返回时 Navigator 空转 300ms。
Page<void> _page(GoRouterState state, Widget child) => CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      transitionsBuilder: (context, animation, secondaryAnimation, child) => child,
    );

class _RouteError extends StatelessWidget {
  final String message;
  const _RouteError({required this.message});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Scaffold(
      backgroundColor: p.card,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('404', style: TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: p.ink)),
            const SizedBox(height: 8),
            Text(message, style: TextStyle(fontSize: 12, color: p.ink3)),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => context.go('/files'),
              child: const Text('返回文件'),
            ),
          ],
        ),
      ),
    );
  }
}
