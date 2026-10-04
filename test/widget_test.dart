import 'package:flutter/material.dart';
import 'package:budgeting_app/app.dart';
import 'package:budgeting_app/features/budget/application/budget_provider.dart';
import 'package:budgeting_app/features/budget/domain/models.dart';
import 'package:budgeting_app/features/budget/domain/period.dart';
import 'package:budgeting_app/features/budget/domain/summary.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

late SharedPreferences prefsForTest;

Future<void> main() async {
  SharedPreferences.setMockInitialValues({});
  prefsForTest = await SharedPreferences.getInstance();
  final may = DateTime(2026, 5);

  BudgetState sample() => BudgetState.initial().copyWith(
        incomes: const [Income(id: 'i', name: 'Salary', amount: 10000)],
        bills: const [
          Bill(id: 'b', name: 'Rent', amount: 4000, categoryId: 'housing'),
          Bill(id: 'd', name: 'Car', amount: 1500, categoryId: 'debt', isDebt: true),
        ],
        cards: const [
          PaymentCard(id: 'c', name: 'Visa', colorIndex: 0, limit: 5000, openingBalance: 1000),
        ],
        txns: [
          Txn(id: 't1', date: DateTime(2026, 5, 3), amount: 500, categoryId: 'groceries', cardId: 'c'),
          Txn(id: 't2', date: DateTime(2026, 5, 4), amount: 200, categoryId: 'groceries'),
          Txn(id: 't3', date: DateTime(2026, 4, 30), amount: 999, categoryId: 'groceries'),
          Txn(id: 't4', date: DateTime(2026, 5, 5), amount: 300, cardId: 'c', isPayment: true),
        ],
      );

  test('month summary: credit card purchases are debt, card payments come out of income', () {
    final sum = summarize(sample(), may);
    expect(sum.income, 10000);
    expect(sum.committed, 5500);
    expect(sum.spent, 700); // everything bought, for budgets
    expect(sum.creditSpent, 500); // charged to the credit card
    expect(sum.cashSpent, 200);
    expect(sum.cardPayments, 300);
    expect(sum.fromIncome, 500); // 200 cash + 300 paid to the card
    expect(sum.left, 4000);
  });

  test('card owed = opening + purchases - payments', () {
    final s = sample();
    final c = summarizeCard(s, s.cards.first, may);
    expect(c.usedThisMonth, 500);
    expect(c.owed, 1000 + 500 - 300);
    expect(c.available, 5000 - 1200);
  });

  test('pace spreads what is left over the remaining days', () {
    final s = sample().copyWith(periodStartDay: 1);
    final now = DateTime(2026, 5, 22); // 10 days left incl. today (May has 31)
    expect(daysLeftInPeriod(1, may, now), 10);
    expect(daysLeftInPeriod(1, DateTime(2026, 4), now), isNull);
    expect(daysLeftInPeriod(1, DateTime(2026, 6), now), 30);
    final p = paceFor(s, 1000, may, now)!;
    expect(p.perDay, 100);
    expect(p.perWeek, 700);
    expect(paceFor(s, -50, may, now)!.perDay, 0);
  });

  test('pace follows the pay period, not the calendar month', () {
    final s = sample().copyWith(periodStartDay: 25);
    final sep = DateTime(2026, 9);
    final now = DateTime(2026, 9, 26); // 29 days left in 25 Sep - 24 Oct
    expect(paceFor(s, 2900, sep, now)!.days, 29);
    expect(paceFor(s, 2900, sep, now)!.perDay, 100);
    expect(paceFor(s, 100, sep, DateTime(2026, 10, 25)), isNull);
  });

  test('focus category and pace mode persist; focus can be cleared', () {
    final s = sample().copyWith(focusCategoryId: 'coffee', paceMode: PaceMode.week);
    final back = BudgetState.fromJson(s.toJson());
    expect(back.focusCategoryId, 'coffee');
    expect(back.paceMode, PaceMode.week);
    expect(s.copyWith(focusCategoryId: null).focusCategoryId, isNull);
    expect(s.copyWith(paceMode: 0).focusCategoryId, 'coffee');
  });

  test('paying a debt records the date and can reduce then restore the balance', () {
    final container = ProviderContainer(overrides: [
      prefsProvider.overrideWithValue(prefsForTest),
    ]);
    addTearDown(container.dispose);
    final n = container.read(budgetProvider.notifier);
    const loan = Bill(
        id: 'l', name: 'Loan', amount: 500, categoryId: 'debt', isDebt: true, debtBalance: 2000);
    n.saveBill(loan);

    n.markBillPaid(loan, may, date: DateTime(2026, 5, 25), amount: 500, reduceBalance: true);
    var s = container.read(budgetProvider);
    expect(s.isPaid(loan, may), isTrue);
    expect(s.isPaid(loan, DateTime(2026, 6)), isFalse);
    expect(s.paidRecord(loan, may)!.date, DateTime(2026, 5, 25));
    expect(s.bills.single.debtBalance, 1500);
    expect(summarize(s, may).billsPaid, 500);

    n.unmarkBillPaid(loan, may);
    s = container.read(budgetProvider);
    expect(s.isPaid(loan, may), isFalse);
    expect(s.bills.single.debtBalance, 2000);

    // Without the reduce option the balance is left alone.
    n.markBillPaid(loan, may, date: DateTime(2026, 5, 25), amount: 500);
    expect(container.read(budgetProvider).bills.single.debtBalance, 2000);
  });

  test('income received dates are per month and survive a round trip', () {
    const inc = Income(id: 'i', name: 'Salary', amount: 100, payDay: 25);
    final s = BudgetState.initial().copyWith(
        incomes: [inc], received: {'2026-05|i': DateTime(2026, 5, 26)});
    final back = BudgetState.fromJson(s.toJson());
    expect(back.receivedOn(inc, may), DateTime(2026, 5, 26));
    expect(back.receivedOn(inc, DateTime(2026, 6)), isNull);
    expect(back.incomes.single.payDay, 25);
    expect(summarize(back, may).incomeReceived, 100);
  });

  test('saves from before payment dates existed still load', () {
    final old = BudgetState.initial().toJson()..['paid'] = ['2026-05|b'];
    (old as Map).remove('payments');
    final s = BudgetState.fromJson(old);
    const b = Bill(id: 'b', name: 'Rent', amount: 1, categoryId: 'housing');
    expect(s.isPaid(b, may), isTrue);
    expect(s.paidRecord(b, may)!.date, isNull);
  });

  test('dateInPeriod uses today for this period, else the due day', () {
    final now = DateTime(2026, 5, 10);
    expect(dateInPeriod(1, may, 25, now), DateTime(2026, 5, 10));
    expect(dateInPeriod(1, DateTime(2026, 2), 31, now), DateTime(2026, 2, 28));
    expect(dateInPeriod(1, DateTime(2026, 6), null, now), DateTime(2026, 6, 1));
  });

  test('theme mode persists and defaults to auto', () {
    final back = BudgetState.fromJson(sample().copyWith(themeMode: 2).toJson());
    expect(back.themeMode, 2);
    final old = sample().toJson()..remove('themeMode');
    expect(BudgetState.fromJson(old).themeMode, 0);
  });

  test('one-off income only applies to its month', () {
    const i = Income(id: 'x', name: 'Bonus', amount: 1, oneOffMonth: '2026-05');
    expect(i.appliesTo(may), isTrue);
    expect(i.appliesTo(DateTime(2026, 6)), isFalse);
  });

  test('state survives a JSON round trip', () {
    final back = BudgetState.fromJson(sample().toJson());
    expect(back.bills.length, 2);
    expect(back.txns.last.isPayment, isTrue);
    expect(back.cards.first.limit, 5000);
  });

  testWidgets('add a bill and see it reflected on the overview', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [prefsProvider.overrideWithValue(prefs)],
      child: const App(),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Left to spend'), findsOneWidget);

    final container = ProviderScope.containerOf(tester.element(find.byType(App)));
    container.read(budgetProvider.notifier)
      ..saveIncome(const Income(id: 'i', name: 'Salary', amount: 1000))
      ..saveBill(const Bill(id: 'b', name: 'Rent', amount: 400, categoryId: 'housing'));
    await tester.pumpAndSettle();

    expect(find.text(r'$600.00'), findsWidgets);
    await tester.scrollUntilVisible(find.text('Rent'), 300);
    expect(find.text('Rent'), findsOneWidget);
  });

  testWidgets('add spending shows amount left after the purchase', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [prefsProvider.overrideWithValue(prefs)],
      child: const App(),
    ));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(App)));
    container.read(budgetProvider.notifier)
        .saveIncome(const Income(id: 'i', name: 'Salary', amount: 1000));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add spending'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '250');
    await tester.pump();

    expect(find.text(r'$1,000.00'), findsWidgets); // left now
    expect(find.text(r'$750.00'), findsOneWidget); // after purchase
  });

  testWidgets('spending more than is left is refused with an error', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [prefsProvider.overrideWithValue(prefs)],
      child: const App(),
    ));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(App)));
    container.read(budgetProvider.notifier)
        .saveIncome(const Income(id: 'i', name: 'Salary', amount: 1000));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add spending'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '1500');
    await tester.pump();
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.textContaining('You do not have enough funds'), findsOneWidget);
    expect(container.read(budgetProvider).txns, isEmpty);

    await tester.enterText(find.byType(TextFormField).first, '900');
    await tester.pumpAndSettle();
    expect(find.textContaining('You do not have enough funds'), findsNothing);
    await tester.ensureVisible(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(container.read(budgetProvider).txns.single.amount, 900);
  });
}
