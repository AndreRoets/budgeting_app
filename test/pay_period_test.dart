import 'package:budgeting_app/app.dart';
import 'package:budgeting_app/core/format.dart';
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
  final aug = DateTime(2026, 8);
  final sep = DateTime(2026, 9);
  final oct = DateTime(2026, 10);

  // Paid on the 25th, so a period runs 25th to 24th.
  BudgetState state() => BudgetState.initial().copyWith(
        periodStartDay: 25,
        incomes: const [Income(id: 'i', name: 'Salary', amount: 10000, payDay: 25)],
        bills: const [Bill(id: 'r', name: 'Rent', amount: 4000, categoryId: 'housing')],
        cards: const [PaymentCard(id: 'cc', name: 'Visa', colorIndex: 0)],
        txns: [
          Txn(id: 'a', date: DateTime(2026, 9, 20), amount: 300, categoryId: 'groceries'),
          Txn(id: 'b', date: DateTime(2026, 9, 25), amount: 200, categoryId: 'groceries'),
          Txn(id: 'c', date: DateTime(2026, 9, 30), amount: 500, categoryId: 'groceries', cardId: 'cc'),
          Txn(id: 'd', date: DateTime(2026, 10, 24), amount: 100, categoryId: 'coffee'),
          Txn(id: 'e', date: DateTime(2026, 10, 25), amount: 700, categoryId: 'groceries'),
          Txn(id: 'f', date: DateTime(2026, 10, 2), amount: 250, cardId: 'cc', isPayment: true),
        ],
      );

  group('summaries follow the pay period', () {
    test('a purchase belongs to the period it falls in, not the calendar month', () {
      final s = state();
      // 20 Sep is before the 25th, so it is in the period that started in August.
      expect(summarize(s, aug).cashSpent, 300);
      // 25 Sep to 24 Oct: 200 + 100 cash, 500 on the card, 250 paid to the card.
      final sum = summarize(s, sep);
      expect(sum.cashSpent, 300);
      expect(sum.creditSpent, 500);
      expect(sum.cardPayments, 250);
      expect(summarize(s, oct).cashSpent, 700);
    });

    test('left to spend is worked out per period', () {
      final s = state();
      expect(summarize(s, aug).left, 5700); // 10000 - 4000 - 300
      expect(summarize(s, sep).left, 5450); // 10000 - 4000 - 300 - 250
      expect(summarize(s, oct).left, 5300); // 10000 - 4000 - 700
    });

    test('the first and last day of a period are both included', () {
      final s = state();
      expect(txnsInMonth(s, sep).map((t) => t.id), containsAll(['b', 'd']));
      expect(txnsInMonth(s, sep).map((t) => t.id), isNot(contains('e')));
      expect(txnsInMonth(s, oct).map((t) => t.id), contains('e'));
    });

    test('every purchase is counted in exactly one period', () {
      final s = state();
      var total = 0.0;
      for (var m = 1; m <= 12; m++) {
        total += summarize(s, DateTime(2026, m)).spent;
      }
      final all = s.txns.where((t) => !t.isPayment).fold<double>(0, (a, t) => a + t.amount);
      expect(total, all);
    });

    test('card use this period only counts that period', () {
      final s = state();
      final visa = s.cards.single;
      expect(summarizeCard(s, visa, sep).usedThisMonth, 500);
      expect(summarizeCard(s, visa, aug).usedThisMonth, 0);
      // What is owed does not depend on the period.
      expect(summarizeCard(s, visa, sep).owed, 250);
      expect(summarizeCard(s, visa, aug).owed, 250);
    });

    test('search and filters use the period', () {
      final s = state();
      expect(filterTxns(s, month: sep).map((t) => t.id).toSet(), {'b', 'c', 'd'});
      expect(filterTxns(s, month: aug).map((t) => t.id).toSet(), {'a'});
      expect(filterTxns(s).length, 5); // all time, never card payments
    });

    test('the trend runs through periods, oldest first', () {
      final trend = monthlyTrend(state(), oct, count: 3);
      expect(trend.map((t) => t.month), [aug, sep, oct]);
      expect(trend.map((t) => t.spent), [300, 550, 700]);
    });

    test('a calendar month start day gives the old behaviour', () {
      final s = state().copyWith(periodStartDay: 1);
      expect(summarize(s, sep).cashSpent, 200 + 300); // 20 Sep, 25 Sep
      expect(summarize(s, oct).cashSpent, 100 + 700); // 24 Oct, 25 Oct
    });

    test('changing the pay day moves purchases between periods', () {
      final s = state();
      expect(summarize(s, aug).cashSpent, 300);
      final moved = s.copyWith(periodStartDay: 21);
      // With a 21st start: 20 Sep still ends the August period, 25 Sep is in September,
      // and 24 Oct has moved on into the October period (21 Oct to 20 Nov).
      expect(summarize(moved, aug).cashSpent, 300);
      expect(summarize(moved, sep).cashSpent, 200);
      expect(summarize(moved, oct).cashSpent, 100 + 700);
    });
  });

  group('screens show pay periods', () {
    Future<ProviderContainer> launch(WidgetTester tester, {int startDay = 25}) async {
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
        ..saveIncome(const Income(id: 'i', name: 'Salary', amount: 10000, payDay: 25))
        ..setPeriodStartDay(startDay);
      await tester.pumpAndSettle();
      return c;
    }

    testWidgets('the month bar shows the current pay period and steps back and forward',
        (tester) async {
      final c = await launch(tester);
      final s = c.read(budgetProvider);
      final key = s.currentPeriod;
      expect(find.text(s.label(key)), findsWidgets);
      expect(s.label(key), contains('–'));

      await tester.tap(find.byTooltip('Previous month').first);
      await tester.pumpAndSettle();
      expect(find.text(s.label(DateTime(key.year, key.month - 1))), findsWidgets);

      await tester.tap(find.byTooltip('Next month').first);
      await tester.pumpAndSettle();
      expect(find.text(s.label(key)), findsWidgets);
    });

    testWidgets('a start day of 1 shows the calendar month name', (tester) async {
      final c = await launch(tester, startDay: 1);
      final key = c.read(budgetProvider).currentPeriod;
      expect(find.text(monthLabel(key)), findsWidgets);
    });

    testWidgets('with no start day chosen it follows the income pay day', (tester) async {
      final c = await launch(tester, startDay: 0);
      expect(c.read(budgetProvider).startDay, 25);
      final key = c.read(budgetProvider).currentPeriod;
      expect(find.text(c.read(budgetProvider).label(key)), findsWidgets);
    });

    testWidgets('the start day can be changed in settings', (tester) async {
      final c = await launch(tester);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Budget month'), findsOneWidget);

      await tester.tap(find.textContaining('Starts on the 25th').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Calendar month (the 1st)').last);
      await tester.pumpAndSettle();

      expect(c.read(budgetProvider).periodStartDay, 1);
      expect(c.read(budgetProvider).startDay, 1);
    });

    testWidgets('the selected period returns to the current one when the start day changes',
        (tester) async {
      final c = await launch(tester);
      await tester.tap(find.byTooltip('Previous month').first);
      await tester.pumpAndSettle();
      expect(c.read(selectedMonthProvider), isNot(c.read(budgetProvider).currentPeriod));

      c.read(budgetProvider.notifier).setPeriodStartDay(10);
      await tester.pumpAndSettle();
      expect(c.read(selectedMonthProvider), c.read(budgetProvider).currentPeriod);
    });

    testWidgets('Add spending shows what is left in the pay period', (tester) async {
      final c = await launch(tester);
      await tester.tap(find.text('Add spending'));
      await tester.pumpAndSettle();
      final s = c.read(budgetProvider);
      expect(find.text('Left in ${s.label(s.currentPeriod)} now'), findsOneWidget);
    });

    testWidgets('the Budget tab shows a budget-month card next to Income that follows salary',
        (tester) async {
      final c = await launch(tester, startDay: 0);
      await tester.tap(find.descendant(
          of: find.byType(NavigationBar), matching: find.text('Budget')));
      await tester.pumpAndSettle();

      final s = c.read(budgetProvider);
      expect(find.text('Budget month: ${s.label(s.currentPeriod)}'), findsOneWidget);
      expect(find.textContaining("Follows Salary's pay day, the 25th"), findsOneWidget);

      await tester.tap(find.text('Budget month: ${s.label(s.currentPeriod)}'));
      await tester.pumpAndSettle();
      expect(find.text('Budget month'), findsOneWidget);
      expect(find.textContaining('Right now it runs'), findsOneWidget);

      await tester.tap(find.textContaining('Follow my pay day').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Calendar month (the 1st)').last);
      await tester.pumpAndSettle();
      expect(c.read(budgetProvider).periodStartDay, 1);
    });

    testWidgets('the budget-month card explains when no pay day is set yet', (tester) async {
      await launch(tester, startDay: 0);
      final c = ProviderScope.containerOf(tester.element(find.byType(App)));
      c.read(budgetProvider.notifier).saveIncome(
          const Income(id: 'i', name: 'Salary', amount: 10000));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
          of: find.byType(NavigationBar), matching: find.text('Budget')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Add a pay day above'), findsOneWidget);
    });

    testWidgets('the pay day field explains it sets the budget month', (tester) async {
      await launch(tester);
      await tester.tap(find.descendant(
          of: find.byType(NavigationBar), matching: find.text('Budget')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salary'));
      await tester.pumpAndSettle();
      expect(find.textContaining('sets your budget month'), findsOneWidget);
    });
  });
}
