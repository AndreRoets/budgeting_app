import 'package:budgeting_app/app.dart';
import 'package:budgeting_app/core/router/app_router.dart';
import 'package:budgeting_app/features/budget/application/budget_provider.dart';
import 'package:budgeting_app/features/budget/domain/coach.dart';
import 'package:budgeting_app/features/budget/domain/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _launch(WidgetTester tester, {bool withDebt = true}) async {
  await tester.binding.setSurfaceSize(const Size(412, 3600));
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
  final n = c.read(budgetProvider.notifier)
    ..saveIncome(const Income(id: 'i', name: 'Salary', amount: 20000));
  if (withDebt) {
    n
      ..saveBill(const Bill(id: 'r', name: 'Rent', amount: 6000, categoryId: 'housing'))
      ..saveBill(const Bill(
          id: 'l', name: 'Car loan', amount: 2500, categoryId: 'debt',
          isDebt: true, debtBalance: 60000, interestRate: 11))
      ..saveCard(const PaymentCard(
          id: 'c', name: 'Visa', colorIndex: 0,
          openingBalance: 5000, interestRate: 22, minPayment: 250));
  }
  await tester.pumpAndSettle();
  return c;
}

Future<void> _openCoach(WidgetTester tester) async {
  GoRouter.of(tester.element(find.byType(NavigationBar))).push('/coach');
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('with no debts the coach explains there is nothing to plan', (tester) async {
    await _launch(tester, withDebt: false);
    await _openCoach(tester);
    expect(find.textContaining('You have no debts to plan'), findsOneWidget);
  });

  testWidgets('the home debt card opens the coach', (tester) async {
    await _launch(tester);
    await tester.tap(find.text('Get my payoff plan'));
    await tester.pumpAndSettle();
    expect(find.text('Debt coach'), findsOneWidget);
  });

  testWidgets('the coach shows an answer, the money split and both strategies', (tester) async {
    await _launch(tester);
    await _openCoach(tester);

    expect(find.text('Debt-free by'), findsOneWidget);
    expect(find.text('How serious are you?'), findsOneWidget);
    expect(find.text('Backup money'), findsWidgets);
    expect(find.text('Left to spend'), findsWidgets);
    expect(find.text('Highest interest first'), findsOneWidget);
    expect(find.text('Smallest balance first'), findsOneWidget);
    // Loans and cards are both in the order list; the 22% card is first.
    expect(find.text('Car loan'), findsWidgets);
    expect(find.text('Visa'), findsWidgets);
  });

  testWidgets('the extra in the answer matches the extra in this month\'s move', (tester) async {
    final c = await _launch(tester);
    c.read(budgetProvider.notifier).setCoach(intensity: 1, buffer: 9000);
    await tester.pumpAndSettle();
    await _openCoach(tester);

    final chip = find.textContaining('extra a month');
    expect(chip, findsOneWidget);
    final amount = RegExp(r'\$[\d,]+\.\d\d')
        .firstMatch(tester.widget<Text>(chip).data!)!
        .group(0)!;
    // The single target (the 22% card) is asked for that same amount.
    expect(find.text('Pay $amount extra'), findsOneWidget);
  });

  testWidgets('every month of the plan is listed, ending with the last payment',
      (tester) async {
    final c = await _launch(tester);
    await _openCoach(tester);

    final list = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.text('How the plan works'), 600, scrollable: list);
    expect(find.text('How the plan works'), findsOneWidget);
    expect(find.textContaining('Its payment then moves to'), findsWidgets);

    await tester.scrollUntilVisible(find.text('Month 1'), 600, scrollable: list);
    expect(find.text('Every month, step by step'), findsWidgets);
    expect(find.text('Month 1'), findsOneWidget);

    final now = DateTime.now();
    final plan = buildCoachPlan(c.read(budgetProvider), DateTime(now.year, now.month));
    final months = plan.of(plan.recommended).months;
    expect(months, greaterThan(3));

    await tester.scrollUntilVisible(find.text('Month $months'), 600,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Month $months'), findsOneWidget);
    expect(find.textContaining('You are debt-free'), findsWidgets);
  });

  testWidgets('choosing a seriousness level is saved', (tester) async {
    final c = await _launch(tester);
    await _openCoach(tester);

    await tester.tap(find.text('All-in'));
    await tester.pumpAndSettle();
    expect(c.read(budgetProvider).coachIntensity, 2);
    expect(find.textContaining('Nine tenths'), findsOneWidget);

    await tester.tap(find.text('Gentle'));
    await tester.pumpAndSettle();
    expect(c.read(budgetProvider).coachIntensity, 0);
  });

  testWidgets('backup money can be changed', (tester) async {
    final c = await _launch(tester);
    await _openCoach(tester);

    await tester.tap(find.text('Backup money').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '2500');
    await tester.pump();
    await tester.ensureVisible(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(c.read(budgetProvider).coachBuffer, 2500);
  });

  testWidgets('Record it opens a payment for the first target with the extra filled in',
      (tester) async {
    await _launch(tester);
    await _openCoach(tester);

    // The 22% card is the highest interest, so it gets the extra money first.
    await tester.tap(find.text('Record it').first);
    await tester.pumpAndSettle();
    expect(find.text('Pay Visa'), findsOneWidget);
    final field = tester.widget<TextFormField>(find.byType(TextFormField).first);
    expect(double.parse(field.controller!.text), greaterThan(0));
  });

  testWidgets('the strategy picker offers a custom order and splitting evenly', (tester) async {
    await _launch(tester);
    await _openCoach(tester);
    final list = find.byType(Scrollable).first;

    await tester.scrollUntilVisible(find.text('Which debt first?'), 600, scrollable: list);
    expect(find.text('Pick one to prioritize'), findsOneWidget);
    expect(find.text('Split evenly across all'), findsOneWidget);
  });

  testWidgets('picking "pick one" shows every debt ranked by what it costs right now',
      (tester) async {
    await _launch(tester);
    await _openCoach(tester);
    final list = find.byType(Scrollable).first;

    await tester.scrollUntilVisible(find.text('Pick one to prioritize'), 600, scrollable: list);
    expect(find.text('Choose a debt below.'), findsOneWidget);
    await tester.tap(find.text('Pick one to prioritize'));
    await tester.pumpAndSettle();

    // Car loan owes far more (R60,000 at 11%) than Visa (R5,000-ish at 22%),
    // so in plain money it is costing more interest right now, even though
    // Visa's rate is higher - that is exactly what this list should surface.
    expect(find.textContaining('about'), findsWidgets);
    expect(find.textContaining('/month in interest'), findsWidgets);
  });

  testWidgets('choosing a debt to prioritize is saved and drives this month\'s move',
      (tester) async {
    final c = await _launch(tester);
    await _openCoach(tester);
    final list = find.byType(Scrollable).first;

    await tester.scrollUntilVisible(find.text('Pick one to prioritize'), 600, scrollable: list);
    await tester.tap(find.text('Pick one to prioritize'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const ValueKey('coach-priority-l')), 600, scrollable: list);
    await tester.tap(find.byKey(const ValueKey('coach-priority-l')));
    await tester.pumpAndSettle();

    expect(c.read(budgetProvider).coachStrategy, Strategy.custom.index);
    expect(c.read(budgetProvider).coachPriorityDebtId, 'l');
    // Scrolling down unmounts what's now off-screen, so scroll back up to it.
    await tester.scrollUntilVisible(find.text("This month's move"), -600, scrollable: list);
    expect(find.text("This month's move"), findsOneWidget);
    expect(find.textContaining('to Car loan'), findsWidgets);
  });

  testWidgets('picking a strategy is remembered after leaving and reopening the coach',
      (tester) async {
    final c = await _launch(tester);
    await _openCoach(tester);
    final list = find.byType(Scrollable).first;

    await tester.scrollUntilVisible(find.text('Split evenly across all'), 600, scrollable: list);
    await tester.tap(find.text('Split evenly across all'));
    await tester.pumpAndSettle();
    expect(c.read(budgetProvider).coachStrategy, Strategy.splitEvenly.index);

    await tester.tap(find.byTooltip('Back').first);
    await tester.pumpAndSettle();
    await _openCoach(tester);
    expect(c.read(budgetProvider).coachStrategy, Strategy.splitEvenly.index);
  });

  testWidgets('picking a worse debt to prioritize explains the cheaper alternative',
      (tester) async {
    final c = await _launch(tester);
    await _openCoach(tester);
    final list = find.byType(Scrollable).first;

    // Recommended (highest interest first) is not shown as "a cheaper order
    // is available" against itself.
    expect(find.textContaining('A cheaper order is available'), findsNothing);

    await tester.scrollUntilVisible(find.text('Pick one to prioritize'), 600, scrollable: list);
    await tester.tap(find.text('Pick one to prioritize'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const ValueKey('coach-priority-l')), 600, scrollable: list);
    await tester.tap(find.byKey(const ValueKey('coach-priority-l')));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
        find.textContaining('A cheaper order is available'), 600, scrollable: list);
    expect(find.textContaining('A cheaper order is available'), findsOneWidget);
    expect(find.textContaining('Paying off Car loan first costs'), findsOneWidget);
    expect(find.textContaining('than paying off Visa first'), findsOneWidget);
    expect(c.read(budgetProvider).coachPriorityDebtId, 'l');
  });

  testWidgets('confirming the plan adds it as a bill, shown as confirmed on reopening',
      (tester) async {
    final c = await _launch(tester);
    await _openCoach(tester);
    final list = find.byType(Scrollable).first;

    await tester.scrollUntilVisible(find.text('Confirm this plan'), 600, scrollable: list);
    await tester.tap(find.text('Confirm this plan'));
    await tester.pumpAndSettle();

    expect(c.read(budgetProvider).bills.any((b) => b.isCoachExtra), isTrue);
    await tester.scrollUntilVisible(find.textContaining('Confirmed:'), 600, scrollable: list);
    expect(find.textContaining('Confirmed:'), findsOneWidget);
    expect(find.text('Stop tracking'), findsOneWidget);

    await tester.tap(find.byTooltip('Back').first);
    await tester.pumpAndSettle();
    await _openCoach(tester);
    await tester.scrollUntilVisible(find.textContaining('Confirmed:'), 600,
        scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('Confirmed:'), findsOneWidget);

    await tester.tap(find.text('Stop tracking'));
    await tester.pumpAndSettle();
    expect(c.read(budgetProvider).bills.any((b) => b.isCoachExtra), isFalse);
  });

  testWidgets('splitting evenly explains itself instead of a numbered order', (tester) async {
    await _launch(tester);
    await _openCoach(tester);
    final list = find.byType(Scrollable).first;

    await tester.scrollUntilVisible(find.text('Split evenly across all'), 600, scrollable: list);
    await tester.tap(find.text('Split evenly across all'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('How the plan works'), 600, scrollable: list);
    expect(find.textContaining('divided evenly between them'), findsOneWidget);
    expect(find.textContaining('Its payment then moves to'), findsNothing);
  });
}
