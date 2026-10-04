import 'package:budgeting_app/app.dart';
import 'package:budgeting_app/core/router/app_router.dart';
import 'package:budgeting_app/features/budget/application/budget_provider.dart';
import 'package:budgeting_app/features/budget/domain/coach.dart';
import 'package:budgeting_app/features/budget/domain/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final sep = DateTime(2026, 9);

  group('Goal.isOverdue', () {
    test('is false with no deadline, false once reached, true once the month has passed', () {
      const noDeadline = Goal(id: 'a', name: 'a', target: 100);
      const reached = Goal(id: 'b', name: 'b', target: 100, saved: 100, deadline: null);
      final future = Goal(id: 'c', name: 'c', target: 100, deadline: DateTime(2026, 10));
      final past = Goal(id: 'd', name: 'd', target: 100, deadline: DateTime(2026, 6));
      final justEnded = Goal(id: 'e', name: 'e', target: 100, deadline: DateTime(2026, 8));

      expect(noDeadline.isOverdue(sep), isFalse);
      expect(reached.isOverdue(sep), isFalse);
      expect(future.isOverdue(sep), isFalse);
      expect(past.isOverdue(sep), isTrue);
      // The target month (August) has to fully end before it counts as overdue.
      expect(justEnded.isOverdue(DateTime(2026, 9, 2)), isTrue);
      expect(justEnded.isOverdue(DateTime(2026, 8, 31)), isFalse);
    });
  });

  group('goalsSavingsNeeded', () {
    test('sums what each on-track goal needs this period', () {
      final holiday = Goal(
          id: 'h', name: 'Holiday', target: 12000, saved: 2000, deadline: DateTime(2027, 3));
      final emergency =
          Goal(id: 'e', name: 'Emergency fund', target: 5000, saved: 500, deadline: DateTime(2026, 12));
      expect(holiday.monthlyNeeded(sep), closeTo(10000 / 7, 0.001));
      expect(emergency.monthlyNeeded(sep), closeTo(4500 / 4, 0.001));
      expect(
        goalsSavingsNeeded([holiday, emergency], sep, sep),
        closeTo(10000 / 7 + 4500 / 4, 0.001),
      );
    });

    test('a reached goal needs nothing, and an overdue one is left out of the total', () {
      final reached =
          Goal(id: 'r', name: 'Done', target: 100, saved: 100, deadline: DateTime(2027, 1));
      final overdue = Goal(id: 'o', name: 'Late', target: 5000, deadline: DateTime(2026, 1));
      expect(goalsSavingsNeeded([reached, overdue], sep, sep), 0);
    });

    test('a goal with no target date needs nothing', () {
      const g = Goal(id: 'g', name: 'Someday', target: 1000);
      expect(goalsSavingsNeeded([g], sep, sep), 0);
    });

    test('an empty goal list needs nothing', () {
      expect(goalsSavingsNeeded(const [], sep, sep), 0);
    });
  });

  group('goal savings inside the debt coach', () {
    BudgetState state({List<Goal> goals = const []}) => BudgetState.initial().copyWith(
          incomes: const [Income(id: 'i', name: 'Salary', amount: 20000)],
          bills: const [
            Bill(id: 'r', name: 'Rent', amount: 8000, categoryId: 'housing'),
            Bill(id: 'l', name: 'Car loan', amount: 4300, categoryId: 'debt',
                isDebt: true, debtBalance: 58000, interestRate: 11.5),
          ],
          goals: goals,
        );

    test('money set aside for a goal is not offered to debt', () {
      final none = coachBudget(state(), sep, intensity: 1);
      final holiday = Goal(id: 'h', name: 'Holiday', target: 8400, deadline: DateTime(2027, 3));
      final withGoal = coachBudget(state(goals: [holiday]), sep, intensity: 1);

      expect(withGoal.goalSavings, closeTo(1200, 0.001)); // 8400 over 7 months
      expect(withGoal.spare, closeTo(none.spare - 1200, 0.001));
      expect(withGoal.extra, lessThan(none.extra));
    });

    test('an overdue or undated goal does not reduce spare money', () {
      final overdue = Goal(id: 'o', name: 'Late', target: 5000, deadline: DateTime(2026, 1));
      const noDate = Goal(id: 'n', name: 'Someday', target: 5000);
      final b = coachBudget(state(goals: [overdue, noDate]), sep, intensity: 1);
      expect(b.goalSavings, 0);
    });

    test('a goal can use up all the spare money, leaving nothing for extra debt payments', () {
      final big = Goal(id: 'b', name: 'Big trip', target: 100000, deadline: DateTime(2026, 10));
      final b = coachBudget(state(goals: [big]), sep, intensity: 2);
      expect(b.spare, lessThan(0));
      expect(b.extra, 0);
    });
  });

  group('the Overview goals card', () {
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
        ..saveIncome(const Income(id: 'i', name: 'Salary', amount: 20000));
      await tester.pumpAndSettle();
      return c;
    }

    testWidgets('is absent with no goals at all', (tester) async {
      await launch(tester);
      expect(find.text('Save this period for your goals'), findsNothing);
      expect(find.text('Savings goals funded'), findsNothing);
    });

    testWidgets('shows what to save this period and opens the Goals tab', (tester) async {
      final c = await launch(tester);
      final now = DateTime.now();
      final deadline = DateTime(now.year, now.month + 3);
      c.read(budgetProvider.notifier).saveGoal(
          Goal(id: 'g', name: 'Holiday', target: 4000, deadline: deadline));
      await tester.pumpAndSettle();

      expect(find.text('Save this period for your goals'), findsOneWidget);
      expect(find.text('Holiday'), findsOneWidget);

      await tester.tap(find.text('Save this period for your goals'));
      await tester.pumpAndSettle();
      expect(find.text('Saved across all goals'), findsOneWidget);
    });

    testWidgets('says funded once every goal is reached', (tester) async {
      final c = await launch(tester);
      c.read(budgetProvider.notifier).saveGoal(
          const Goal(id: 'g', name: 'Holiday', target: 100, saved: 100));
      await tester.pumpAndSettle();
      expect(find.text('Savings goals funded'), findsOneWidget);
    });

    testWidgets('flags a goal whose target date has passed', (tester) async {
      final c = await launch(tester);
      c.read(budgetProvider.notifier).saveGoal(
          Goal(id: 'g', name: 'Old trip', target: 5000, deadline: DateTime(2020, 1)));
      await tester.pumpAndSettle();
      expect(find.textContaining('1 goal has passed its target date'), findsOneWidget);
    });
  });
}
