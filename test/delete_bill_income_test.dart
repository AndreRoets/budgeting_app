import 'package:budgeting_app/app.dart';
import 'package:budgeting_app/core/router/app_router.dart';
import 'package:budgeting_app/features/budget/application/budget_provider.dart';
import 'package:budgeting_app/features/budget/domain/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _launch(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(412, 1600));
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
    ..saveIncome(const Income(id: 'i', name: 'Salary', amount: 20000, payDay: 25))
    ..saveIncome(const Income(id: 'i2', name: 'Side gig', amount: 500))
    ..saveBill(const Bill(id: 'r', name: 'Rent', amount: 6000, categoryId: 'housing'))
    ..saveBill(const Bill(
        id: 'l', name: 'Car loan', amount: 2500, categoryId: 'debt',
        isDebt: true, debtBalance: 60000, interestRate: 11));
  await tester.pumpAndSettle();
  await tester.tap(find.descendant(
      of: find.byType(NavigationBar), matching: find.text('Budget')));
  await tester.pumpAndSettle();
  return c;
}

Future<void> _swipe(WidgetTester tester, Finder finder) async {
  await tester.drag(finder, const Offset(-500, 0));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('swiping a monthly expense asks to confirm, then deletes it', (tester) async {
    final c = await _launch(tester);
    expect(c.read(budgetProvider).bills.any((b) => b.id == 'r'), isTrue);

    await _swipe(tester, find.widgetWithText(ListTile, 'Rent'));
    expect(find.text('Delete Rent?'), findsOneWidget);

    // Cancelling keeps the bill.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(c.read(budgetProvider).bills.any((b) => b.id == 'r'), isTrue);
    expect(find.text('Rent'), findsOneWidget);

    await _swipe(tester, find.widgetWithText(ListTile, 'Rent'));
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect(c.read(budgetProvider).bills.any((b) => b.id == 'r'), isFalse);
    expect(find.text('Rent'), findsNothing);
  });

  testWidgets('swiping a debt asks to confirm, then deletes it', (tester) async {
    final c = await _launch(tester);
    await _swipe(tester, find.widgetWithText(ListTile, 'Car loan'));
    expect(find.text('Delete Car loan?'), findsOneWidget);
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect(c.read(budgetProvider).bills.any((b) => b.id == 'l'), isFalse);
  });

  testWidgets('swiping an income asks to confirm, then deletes it', (tester) async {
    final c = await _launch(tester);
    await _swipe(tester, find.widgetWithText(ListTile, 'Side gig'));
    expect(find.text('Delete Side gig?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(c.read(budgetProvider).incomes.any((i) => i.id == 'i2'), isTrue);

    await _swipe(tester, find.widgetWithText(ListTile, 'Side gig'));
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect(c.read(budgetProvider).incomes.any((i) => i.id == 'i2'), isFalse);
    expect(find.text('Side gig'), findsNothing);
  });

  testWidgets('the read-only bill preview on Overview cannot be swiped away', (tester) async {
    final c = await _launch(tester);
    await tester.tap(find.descendant(
        of: find.byType(NavigationBar), matching: find.text('Overview')));
    await tester.pumpAndSettle();
    expect(find.text('Rent'), findsOneWidget);

    await _swipe(tester, find.widgetWithText(ListTile, 'Rent'));
    // Still there: this row only toggles paid, it does not delete.
    expect(c.read(budgetProvider).bills.any((b) => b.id == 'r'), isTrue);
    expect(find.text('Rent'), findsOneWidget);
  });
}
