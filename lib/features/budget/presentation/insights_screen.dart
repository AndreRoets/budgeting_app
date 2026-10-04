import 'package:flutter/material.dart';

import 'goals_view.dart';
import 'payoff_view.dart';
import 'trends_view.dart';

/// Trends, the debt payoff planner and savings goals, on one tab.
class InsightsScreen extends StatelessWidget {
  const InsightsScreen({super.key, this.initialTab = 0});

  /// Which tab opens first: 0 Trends, 1 Debt payoff, 2 Goals.
  final int initialTab;

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 3,
        initialIndex: initialTab,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Insights'),
            bottom: const TabBar(tabs: [
              Tab(text: 'Trends'),
              Tab(text: 'Debt payoff'),
              Tab(text: 'Goals'),
            ]),
          ),
          body: const TabBarView(children: [
            TrendsView(),
            PayoffView(),
            GoalsView(),
          ]),
        ),
      );
}
