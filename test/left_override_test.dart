import 'package:budgeting_app/app.dart';
import 'package:budgeting_app/core/router/app_router.dart';
import 'package:budgeting_app/features/budget/application/budget_provider.dart';
import 'package:budgeting_app/features/budget/domain/models.dart';
import 'package:budgeting_app/features/budget/domain/period.dart';
import 'package:budgeting_app/features/budget/domain/summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final sep = DateTime(2026, 9);
  final oct = DateTime(2026, 10);

  BudgetState state() => BudgetState.initial().copyWith(
        periodStartDay: 1,
        incomes: const [Income(id: 'i', name: 'Salary', amount: 20000)],
        bills: const [Bill(id: 'r', name: 'Rent', amount: 8000, categoryId: 'housing')],
        txns: [Txn(id: 't', date: DateTime(2026, 9, 5), amount: 500, categoryId: 'groceries')],
      );

  group('leftAdjustments on BudgetState', () {
    test('is zero and absent with nothing set', () {
      final s = state();
      expect(s.leftAdjustmentFor(sep), 0);
      expect(s.hasLeftAdjustment(sep), isFalse);
    });

    test('is per period and survives a save/load round trip', () {
      final s = state().copyWith(leftAdjustments: {'2026-09': 1500, '2026-10': -300});
      expect(s.leftAdjustmentFor(sep), 1500);
      expect(s.leftAdjustmentFor(oct), -300);
      expect(s.hasLeftAdjustment(sep), isTrue);
      expect(s.hasLeftAdjustment(DateTime(2026, 11)), isFalse);

      final back = BudgetState.fromJson(s.toJson());
      expect(back.leftAdjustmentFor(sep), 1500);
      expect(back.leftAdjustmentFor(oct), -300);
    });

    test('an older save with no adjustments loads with none set', () {
      final old = state().toJson()..remove('leftAdjustments');
      final back = BudgetState.fromJson(old);
      expect(back.hasLeftAdjustment(sep), isFalse);
      expect(back.leftAdjustmentFor(sep), 0);
    });
  });

  group('the adjustment feeds into MonthSummary.left', () {
    test('with no adjustment, left is just the calculated figure', () {
      final sum = summarize(state(), sep);
      expect(sum.adjustment, 0);
      expect(sum.left, 20000 - 8000 - 500);
    });

    test('an adjustment shifts left by exactly that amount', () {
      final s = state().copyWith(leftAdjustments: {'2026-09': 1000});
      final sum = summarize(s, sep);
      expect(sum.adjustment, 1000);
      expect(sum.left, 20000 - 8000 - 500 + 1000);
    });

    test('a negative adjustment can push left below what was calculated', () {
      final s = state().copyWith(leftAdjustments: {'2026-09': -5000});
      expect(summarize(s, sep).left, 20000 - 8000 - 500 - 5000);
    });

    test('only applies to the period it was set for', () {
      final s = state().copyWith(leftAdjustments: {'2026-09': 1000});
      expect(summarize(s, oct).left, 20000 - 8000);
    });

    test('new spending after the adjustment still reduces left normally', () {
      var s = state().copyWith(leftAdjustments: {'2026-09': 1000});
      final before = summarize(s, sep).left;
      s = s.copyWith(txns: [
        ...s.txns,
        Txn(id: 't2', date: DateTime(2026, 9, 10), amount: 200, categoryId: 'groceries'),
      ]);
      expect(summarize(s, sep).left, before - 200);
    });
  });

  group('the override screen', () {
    Future<ProviderContainer> launch(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      appRouter.go('/');
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(ProviderScope(
        overrides: [prefsProvider.overrideWithValue(prefs)],
        child: const App(),
      ));
      await tester.pumpAndSettle();
      final c = ProviderScope.containerOf(tester.element(find.byType(App)));
      c.read(budgetProvider.notifier)
        ..setPeriodStartDay(1)
        ..saveIncome(const Income(id: 'i', name: 'Salary', amount: 20000))
        ..saveBill(const Bill(id: 'r', name: 'Rent', amount: 8000, categoryId: 'housing'));
      await tester.pumpAndSettle();
      return c;
    }

    testWidgets('setting a figure stores the right delta and updates the hero', (tester) async {
      final c = await launch(tester);
      final before = summarize(c.read(budgetProvider), c.read(budgetProvider).currentPeriod).left;
      expect(before, 12000);

      await tester.tap(find.byIcon(Icons.edit_rounded));
      await tester.pumpAndSettle();
      expect(find.text("Set what's left"), findsOneWidget);
      expect(find.text(before.toStringAsFixed(2)), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), '3000');
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final month = c.read(budgetProvider).currentPeriod;
      expect(c.read(budgetProvider).leftAdjustmentFor(month), 3000 - before);
      expect(summarize(c.read(budgetProvider), month).left, 3000);
      expect(find.text(r'$3,000.00'), findsWidgets);
      expect(find.textContaining('Manually adjusted'), findsOneWidget);
    });

    testWidgets('adding spending afterwards still reduces the overridden figure', (tester) async {
      final c = await launch(tester);
      final month = c.read(budgetProvider).currentPeriod;
      c.read(budgetProvider.notifier).setLeftAdjustment(month, 3000 - 12000);
      await tester.pumpAndSettle();
      expect(summarize(c.read(budgetProvider), month).left, 3000);

      await tester.tap(find.text('Add spending'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '250');
      await tester.pump();
      await tester.ensureVisible(find.text('Save'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(summarize(c.read(budgetProvider), month).left, 2750);
    });

    testWidgets('can be cleared to go back to the calculated amount', (tester) async {
      final c = await launch(tester);
      final month = c.read(budgetProvider).currentPeriod;
      c.read(budgetProvider.notifier).setLeftAdjustment(month, 500);
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.edit_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Use the calculated amount instead'), findsOneWidget);
      await tester.tap(find.text('Use the calculated amount instead'));
      await tester.pumpAndSettle();

      expect(c.read(budgetProvider).hasLeftAdjustment(month), isFalse);
      expect(find.textContaining('Manually adjusted'), findsNothing);
    });

    testWidgets('with no override yet, there is no "use calculated" option and no adjusted note',
        (tester) async {
      await launch(tester);
      expect(find.textContaining('Manually adjusted'), findsNothing);
      await tester.tap(find.byIcon(Icons.edit_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Use the calculated amount instead'), findsNothing);
    });
  });
}
