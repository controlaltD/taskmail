import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/accounts/accounts_screen.dart';
import '../../features/auth/auth_controller.dart';
import '../../features/auth/login_screen.dart';
import '../../features/board/board_screen.dart';
import '../../features/inbox/inbox_screen.dart';

class _HomeShell extends StatelessWidget {
  const _HomeShell({required this.child, required this.location});

  final Widget child;
  final String location;

  @override
  Widget build(BuildContext context) {
    final index = switch (location) {
      '/board' => 1,
      '/accounts' => 2,
      _ => 0,
    };
    return Scaffold(
      body: SafeArea(child: child),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) {
          switch (i) {
            case 0:
              context.go('/inbox');
            case 1:
              context.go('/board');
            case 2:
              context.go('/accounts');
          }
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.inbox_rounded), label: 'Postafiók'),
          NavigationDestination(icon: Icon(Icons.view_kanban_rounded), label: 'Board'),
          NavigationDestination(icon: Icon(Icons.settings_rounded), label: 'Fiókok'),
        ],
      ),
    );
  }
}

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/inbox',
    redirect: (context, state) {
      final loggedIn = ref.read(currentUserProvider) != null;
      final loggingIn = state.matchedLocation == '/login';
      if (!loggedIn && !loggingIn) return '/login';
      if (loggedIn && loggingIn) return '/inbox';
      return null;
    },
    refreshListenable: _GoRouterRefreshStream(ref),
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      ShellRoute(
        builder: (context, state, child) => _HomeShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(path: '/inbox', builder: (context, state) => const InboxScreen()),
          GoRoute(path: '/board', builder: (context, state) => const BoardScreen()),
          GoRoute(path: '/accounts', builder: (context, state) => const AccountsScreen()),
        ],
      ),
    ],
  );
});

class _GoRouterRefreshStream extends ChangeNotifier {
  _GoRouterRefreshStream(this.ref) {
    ref.listen(authStateProvider, (_, __) => notifyListeners());
  }

  final Ref ref;
}
