import 'package:budgeting_app/app.dart';
import 'package:budgeting_app/core/router/app_router.dart';
import 'package:budgeting_app/features/budget/application/budget_provider.dart';
import 'package:budgeting_app/features/budget/domain/models.dart';
import 'package:budgeting_app/features/budget/domain/summary.dart';
import 'package:budgeting_app/features/budget/presentation/forms.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _launch(WidgetTester tester, {double income = 20000}) async {
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
    ..saveIncome(Income(id: 'i', name: 'Salary', amount: income))
    ..saveCard(const PaymentCard(
        id: 'c', name: 'Visa', colorIndex: 0, openingBalance: 1000));
  await tester.pumpAndSettle();
  return c;
}

Future<void> _openFormAndPickVisa(WidgetTester tester) async {
  await tester.tap(find.text('Add spending'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Repay a debt or card (optional)'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Repay a debt or card (optional)'));
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining('Visa · owed').last);
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Save'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Save'));
  await tester.pumpAndSettle();
}

double _owed(ProviderContainer c) {
  final s = c.read(budgetProvider);
  return summarizeCard(s, s.cards.single, DateTime.now()).owed;
}

void main() {
  testWidgets('a credit card that owes money can be paid from Add spending', (tester) async {
    final c = await _launch(tester);
    await _openFormAndPickVisa(tester);

    expect(find.text('Pay Visa'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, '300');
    await tester.pumpAndSettle();
    expect(find.textContaining('Owed \$1,000.00 → \$700.00'), findsOneWidget);
    await _save(tester);

    final t = c.read(budgetProvider).txns.single;
    expect(t.isPayment, isTrue);
    expect(t.cardId, 'c');
    expect(t.amount, 300);
    expect(_owed(c), 700);
  });

  testWidgets('paying more than the card owes is refused', (tester) async {
    final c = await _launch(tester);
    await _openFormAndPickVisa(tester);
    await tester.enterText(find.byType(TextFormField).first, '1500');
    await tester.pumpAndSettle();
    await _save(tester);

    expect(find.textContaining('You only owe'), findsOneWidget);
    expect(c.read(budgetProvider).txns, isEmpty);
    expect(_owed(c), 1000);
  });

  testWidgets('paying a card comes out of what is left, so it needs the money', (tester) async {
    final c = await _launch(tester, income: 100);
    await _openFormAndPickVisa(tester);
    await tester.enterText(find.byType(TextFormField).first, '500');
    await tester.pumpAndSettle();
    await _save(tester);

    expect(find.textContaining('do not have enough funds'), findsOneWidget);
    expect(c.read(budgetProvider).txns, isEmpty);
    expect(_owed(c), 1000);
  });

  testWidgets('paying a card lowers left to spend as well as the debt', (tester) async {
    final c = await _launch(tester);
    final before = summarize(c.read(budgetProvider), DateTime.now()).left;
    await _openFormAndPickVisa(tester);
    await tester.enterText(find.byType(TextFormField).first, '300');
    await tester.pumpAndSettle();
    await _save(tester);

    expect(_owed(c), 700);
    expect(summarize(c.read(budgetProvider), DateTime.now()).left, before - 300);
  });

  testWidgets('the card payment form checks the balance and the money left', (tester) async {
    final c = await _launch(tester, income: 400);
    final card = c.read(budgetProvider).cards.single;
    final ctx = tester.element(find.byType(NavigationBar));
    showCardPaymentForm(ctx, card, suggested: 500);
    await tester.pumpAndSettle();
    await _save(tester);
    expect(find.textContaining('do not have enough funds'), findsOneWidget);
    expect(c.read(budgetProvider).txns, isEmpty);

    await tester.enterText(find.byType(TextFormField).first, '5000');
    await tester.pumpAndSettle();
    await _save(tester);
    expect(find.textContaining('You only owe'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, '250');
    await tester.pumpAndSettle();
    await _save(tester);
    expect(_owed(c), 750);
  });

  testWidgets('a purchase charged to a credit card adds to debt and leaves left to spend alone',
      (tester) async {
    final c = await _launch(tester);
    final before = summarize(c.read(budgetProvider), DateTime.now()).left;

    await tester.tap(find.text('Add spending'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '900');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Paid with'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paid with'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Visa').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('adds to your debt'), findsOneWidget);
    expect(find.textContaining('Owed on Visa'), findsOneWidget);
    await _save(tester);

    expect(_owed(c), 1900);
    expect(summarize(c.read(budgetProvider), DateTime.now()).left, before);
  });

  testWidgets('a credit card purchase can exceed what is left, because it is debt',
      (tester) async {
    final c = await _launch(tester, income: 100);
    await tester.tap(find.text('Add spending'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '900');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Paid with'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paid with'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Visa').last);
    await tester.pumpAndSettle();
    await _save(tester);

    expect(find.textContaining('do not have enough funds'), findsNothing);
    expect(_owed(c), 1900);
  });

  testWidgets('a card that owes nothing is listed but cannot be picked', (tester) async {
    final c = await _launch(tester);
    c.read(budgetProvider.notifier).saveCard(
        const PaymentCard(id: 'c', name: 'Visa', colorIndex: 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add spending'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Repay a debt or card (optional)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Repay a debt or card (optional)'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Visa · nothing owed'), findsWidgets);
    await tester.tap(find.textContaining('Visa · nothing owed').last);
    await tester.pumpAndSettle();
    // Nothing was chosen, so the form is still a normal spending form.
    expect(find.text('Pay Visa'), findsNothing);
  });

  testWidgets('credit cards are listed under Debts in the Budget tab', (tester) async {
    final c = await _launch(tester);
    c.read(budgetProvider.notifier).saveBill(const Bill(
        id: 'l', name: 'Car loan', amount: 2000, categoryId: 'debt',
        isDebt: true, debtBalance: 30000));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(NavigationBar), matching: find.text('Budget')));
    await tester.pumpAndSettle();

    expect(find.text('Car loan'), findsWidgets);
    expect(find.text('Visa'), findsOneWidget);
    expect(find.text('Credit card'), findsOneWidget);

    // Its menu offers a payment, which opens the card payment form.
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Make payment'));
    await tester.pumpAndSettle();
    expect(find.text('Pay Visa'), findsOneWidget);
  });
}
