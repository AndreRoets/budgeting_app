import 'package:budgeting_app/app.dart';
import 'package:budgeting_app/features/budget/application/budget_provider.dart';
import 'package:budgeting_app/features/budget/domain/models.dart';
import 'package:budgeting_app/features/budget/presentation/trends_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _launch(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(412, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [prefsProvider.overrideWithValue(prefs)],
    child: const App(),
  ));
  await tester.pumpAndSettle();
  final c = ProviderScope.containerOf(tester.element(find.byType(App)));
  final now = DateTime.now();
  c.read(budgetProvider.notifier)
    ..setPeriodStartDay(1)
    ..saveIncome(const Income(id: 'i', name: 'Salary', amount: 20000, payDay: 25))
    ..saveBill(const Bill(id: 'r', name: 'Rent', amount: 6000, categoryId: 'housing'))
    ..saveBill(const Bill(
        id: 'l',
        name: 'Car loan',
        amount: 2500,
        categoryId: 'debt',
        isDebt: true,
        debtBalance: 60000,
        interestRate: 11))
    ..saveTxn(Txn(id: 't1', date: now, amount: 45, categoryId: 'coffee', note: 'Latte'))
    ..saveTxn(Txn(
        id: 't2',
        date: DateTime(now.year, now.month - 1, 10),
        amount: 30,
        categoryId: 'coffee'))
    ..saveGoal(Goal(
        id: 'g',
        name: 'Holiday',
        target: 5000,
        saved: 1000,
        deadline: DateTime(now.year + 1, 1)));
  await tester.pumpAndSettle();
  return c;
}

Future<void> _openTab(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(
      of: find.byType(NavigationBar), matching: find.text(label)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Insights tab shows trends, payoff plan and goals', (tester) async {
    await _launch(tester);
    await _openTab(tester, 'Insights');
    await tester.pumpAndSettle();

    expect(find.text('Income vs money out'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Spending vs last month'),
      300,
      scrollable: find.descendant(
          of: find.byType(TrendsView), matching: find.byType(Scrollable)),
    );
    expect(find.text('Spending vs last month'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Debt payoff'));
    await tester.pumpAndSettle();
    expect(find.text('Debt-free by'), findsOneWidget);
    expect(find.text('Car loan'), findsOneWidget);
    expect(find.text('What if I pay extra each month?'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Goals'));
    await tester.pumpAndSettle();
    expect(find.text('Holiday'), findsOneWidget);
    expect(find.text('20%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('spending can be searched and filtered', (tester) async {
    await _launch(tester);
    await _openTab(tester, 'Spending');
    await tester.pumpAndSettle();
    expect(find.text('Latte'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'nothing like this');
    await tester.pumpAndSettle();
    expect(find.text('Latte'), findsNothing);
    expect(find.textContaining('Nothing matches'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'latte');
    await tester.pumpAndSettle();
    expect(find.text('Latte'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a purchase can be split across two categories', (tester) async {
    final c = await _launch(tester);
    await _openTab(tester, 'Spending');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add spending'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, '100');
    await tester.tap(find.text('Split across categories'));
    await tester.pumpAndSettle();
    // The extra row's amount field is the second amount field on the form.
    await tester.enterText(find.byType(TextFormField).at(1), '40');
    await tester.pumpAndSettle();
    expect(find.textContaining('gets'), findsOneWidget);

    await tester.ensureVisible(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final saved = c.read(budgetProvider).txns.firstWhere((t) => t.isSplit);
    expect(saved.amount, 100);
    expect(saved.parts.map((p) => p.amount), [60, 40]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('choosing Repeat creates a recurring rule and logs it today', (tester) async {
    final c = await _launch(tester);
    await _openTab(tester, 'Spending');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add spending'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, '35');
    await tester.scrollUntilVisible(find.text('Does not repeat'), 200,
        scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('Does not repeat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Every day').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final s = c.read(budgetProvider);
    expect(s.recurring.single.repeat, Repeat.daily);
    expect(s.txns.where((t) => t.id.startsWith('rec-')).length, 1);
    expect(tester.takeException(), isNull);
  });
}
