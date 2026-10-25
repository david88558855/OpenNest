import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/tokens.dart';
import '../features/auth/login_page.dart';
import '../features/auth/session.dart';
import '../features/files/favorites_page.dart';
import '../features/files/files_page.dart';
import '../features/media/player_page.dart';
import '../features/search/search_page.dart';
import '../features/servers/server_edit_page.dart';
import '../features/servers/servers_page.dart';
import '../features/settings/settings_page.dart';
import '../features/transfers/transfers_page.dart';
import 'providers.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.onDispose(refresh.dispose);
  ref.listen<SessionState>(sessionProvider, (previous, next) {
    if (previous?.signedIn != next.signedIn) refresh.value++;
  });

  return GoRouter(
    initialLocation: '/files',
    refreshListenable: refresh,
    redirect: (context, state) {
      final signedIn = ref.read(sessionProvider).signedIn;
      final path = state.uri.path;
      final onLogin = path == '/login';
      // 服务器管理在未登录时也必须可进：首次运行要能添加实例，否则登录页的
      // 「服务器管理」入口会被登录守卫弹回 /login（v1.0.5 的 bug）。
      final serverArea = path == '/servers' || path.startsWith('/servers/');
      if (!signedIn && !onLogin && !serverArea) return '/login';
      if (signedIn && onLogin) return '/files';
      return null;
    },
    errorBuilder: (context, state) => _RouteError(message: state.error?.toString() ?? '页面不存在'),
    routes: [
      GoRoute(path: '/', redirect: (context, state) => '/files'),
      GoRoute(path: '/login', pageBuilder: (context, state) => _page(state, const LoginPage())),
      GoRoute(
        path: '/files',
        pageBuilder: (context, state) => _page(state, FilesPage(initialPath: state.uri.queryParameters['path'])),
      ),
      GoRoute(path: '/transfers', pageBuilder: (context, state) => _page(state, const TransfersPage())),
      GoRoute(
        path: '/favorites',
        // v1.0.18：「最近使用」已移除；v1.0.26：分享功能整体移除。
        // 旧链接（?tab=recent / ?tab=share）统一回到收藏。
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
        // v1.0.14：'root' 是显式哨兵——Android 用它判定「显示我的列表」，
        // 桌面用它归一化成外观分区。之前这里传 'appearance'，移动端把根列表整个跳过了。
        pageBuilder: (context, state) => _page(state, SettingsPage(tab: state.uri.queryParameters['tab'] ?? 'root')),
      ),
      // 设置分区用独立路径：只改 query 时同一条路由不会重建页面，
      // 表现为「点了没反应」（v1.0.5 的 bug）。
      GoRoute(
        path: '/settings/:tab',
        pageBuilder: (context, state) => _page(state, SettingsPage(tab: state.pathParameters['tab'] ?? 'appearance')),
      ),
      GoRoute(path: '/servers', pageBuilder: (context, state) => _page(state, const ServersPage())),
      GoRoute(
        path: '/servers/edit/:id',
        pageBuilder: (context, state) => _page(state, ServerEditPage(serverId: state.pathParameters['id'] ?? 'new')),
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

/// v1.0.50：所有路由都用「零时长」的页面。
///
/// `PageTransitionsTheme` 只能改**画面**（transitionsBuilder 直接返回 child），
/// 但 `MaterialPageRoute` 的 `transitionDuration` 仍是 300ms —— 返回时即使一帧都没变，
/// Navigator 也要空转满这 300ms 才真正出栈。这就是「服务器管理点返回卡一下、
/// 而从设置回主页（走 go，无出栈动画）却很快」的原因。
/// 把正/反向时长都设为 0，pop 立即完成。
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
