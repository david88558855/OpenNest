import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/sidecar/sidecar_controller.dart';
import '../core/sidecar/sidecar_state.dart';
import '../core/theme/tokens.dart';
import '../features/boot/boot_page.dart';
import '../features/files/favorites_page.dart';
import '../features/files/files_page.dart';
import '../features/media/player_page.dart';
import '../features/search/search_page.dart';
import '../features/settings/settings_page.dart';
import '../features/sources/add_source_page.dart';
import '../features/sources/sources_page.dart';
import '../features/transfers/transfers_page.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.onDispose(refresh.dispose);
  // 引擎就绪 / 失败是唯一的路由门禁：没有账号，也就没有登录态。
  ref.listen<SidecarState>(sidecarProvider, (previous, next) {
    if (previous?.status != next.status) refresh.value++;
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
      if (status == SidecarStatus.ready && onBoot) return '/files';
      return null;
    },
    errorBuilder: (context, state) => _RouteError(message: state.error?.toString() ?? '页面不存在'),
    routes: [
      GoRoute(path: '/', redirect: (context, state) => '/boot'),
      GoRoute(path: '/boot', pageBuilder: (context, state) => _page(state, const BootPage())),
      GoRoute(
        path: '/files',
        pageBuilder: (context, state) => _page(state, FilesPage(initialPath: state.uri.queryParameters['path'])),
      ),
      GoRoute(path: '/transfers', pageBuilder: (context, state) => _page(state, const TransfersPage())),
      GoRoute(path: '/sources', pageBuilder: (context, state) => _page(state, const SourcesPage())),
      GoRoute(
        path: '/sources/add',
        pageBuilder: (context, state) => _page(
          state,
          AddSourcePage(initialDriver: state.uri.queryParameters['driver']),
        ),
      ),
      GoRoute(
        path: '/favorites',
        redirect: (context, state) {
          final tab = state.uri.queryParameters['tab'];
          if (tab == 'recent' || tab == 'share') return '/favorites';
          return null;
        },
        pageBuilder: (context, state) => _page(state, const FavoritesPage()),
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
      GoRoute(
        path: '/settings/:tab',
        pageBuilder: (context, state) => _page(state, SettingsPage(tab: state.pathParameters['tab'] ?? 'appearance')),
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
