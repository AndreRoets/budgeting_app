import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/home_widget_sync.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/budget/application/budget_provider.dart';

class App extends ConsumerStatefulWidget {
  const App({super.key});

  @override
  ConsumerState<App> createState() => _AppState();
}

class _AppState extends ConsumerState<App> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Push the current numbers to the home-screen widget once we're running.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) syncHomeWidget(ref.read(budgetProvider));
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// A new day may have started while the app was in the background.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(budgetProvider.notifier).materializeRecurring();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(budgetProvider, (_, next) => syncHomeWidget(next));
    final mode = ref.watch(budgetProvider.select((s) => s.themeMode));
    return MaterialApp.router(
      title: 'Ledgerly',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: switch (mode) {
        1 => ThemeMode.light,
        2 => ThemeMode.dark,
        _ => ThemeMode.system,
      },
      routerConfig: appRouter,
      // Slightly larger text everywhere, on top of the phone's own setting.
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
              textScaler: TextScaler.linear(mq.textScaler.scale(1) * 1.12)),
          child: AuroraBackground(child: child!),
        );
      },
    );
  }
}
