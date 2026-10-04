import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../features/budget/domain/models.dart';
import '../features/budget/domain/period.dart';
import '../features/budget/domain/summary.dart';

const _androidProvider = 'com.example.budgeting_app.BudgetWidgetProvider';

/// Saves what is left in the current pay period, and when that period starts
/// and ends, for the Android home-screen widget, then asks it to redraw. The
/// widget works out the per-day figure itself from those dates.
///
/// Best-effort: on platforms without the widget (or in tests) this is a no-op.
Future<void> syncHomeWidget(BudgetState s, [DateTime? now]) async {
  if (defaultTargetPlatform != TargetPlatform.android) return;
  final today = now ?? DateTime.now();
  final period = s.periodKey(today);
  try {
    await HomeWidget.saveWidgetData<String>('currency', s.currency);
    await HomeWidget.saveWidgetData<String>(
        'period_start', s.periodStart(period).millisecondsSinceEpoch.toString());
    await HomeWidget.saveWidgetData<String>(
        'period_end', s.periodEnd(period).millisecondsSinceEpoch.toString());
    await HomeWidget.saveWidgetData<String>(
        'left_period', summarize(s, period).left.toString());
    await HomeWidget.updateWidget(qualifiedAndroidName: _androidProvider);
  } catch (e) {
    debugPrint('Home widget update skipped: $e');
  }
}
