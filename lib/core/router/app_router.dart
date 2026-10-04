import 'package:go_router/go_router.dart';

import '../../features/budget/presentation/cards_screen.dart';
import '../../features/budget/presentation/coach_screen.dart';
import '../../features/budget/presentation/categories_screen.dart';
import '../../features/budget/presentation/dashboard_screen.dart';
import '../../features/budget/presentation/insights_screen.dart';
import '../../features/budget/presentation/plan_screen.dart';
import '../../features/budget/presentation/recurring_screen.dart';
import '../../features/budget/presentation/shell_screen.dart';
import '../../features/budget/presentation/spending_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => ShellScreen(shell: shell),
      branches: [
        StatefulShellBranch(routes: [
          GoRoute(path: '/', builder: (_, _) => const DashboardScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/budget', builder: (_, _) => const PlanScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/spending', builder: (_, _) => const SpendingScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/cards', builder: (_, _) => const CardsScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/insights',
            builder: (_, state) => InsightsScreen(
                initialTab: int.tryParse(state.uri.queryParameters['tab'] ?? '') ?? 0),
          ),
        ]),
      ],
    ),
    GoRoute(
      path: '/spending/recurring',
      builder: (_, _) => const RecurringScreen(),
    ),
    GoRoute(path: '/coach', builder: (_, _) => const CoachScreen()),
    GoRoute(
      path: '/budget/categories',
      builder: (_, _) => const CategoriesScreen(),
    ),
    GoRoute(
      path: '/cards/:id',
      builder: (_, state) => CardDetailScreen(cardId: state.pathParameters['id']!),
    ),
  ],
);
