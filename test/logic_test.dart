import 'dart:convert';
import 'package:budgeting_app/features/budget/application/budget_provider.dart';
import 'package:budgeting_app/features/budget/domain/models.dart';
import 'package:budgeting_app/features/budget/domain/payoff.dart';
import 'package:budgeting_app/features/budget/domain/recurring.dart';
import 'package:budgeting_app/features/budget/domain/summary.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final may = DateTime(2026, 5);

  group('recurring spending', () {
    RecurringSpend rule(Repeat r, DateTime start) =>
        RecurringSpend(id: 'r', amount: 30, repeat: r, start: start, categoryId: 'coffee');

    test('daily covers start through today', () {
      final d = occurrences(rule(Repeat.daily, DateTime(2026, 5, 1)), DateTime(2026, 5, 4));
      expect(d, [for (var i = 1; i <= 4; i++) DateTime(2026, 5, i)]);
    });

    test('nothing before the start date', () {
      expect(occurrences(rule(Repeat.daily, DateTime(2026, 5, 10)), DateTime(2026, 5, 4)),
          isEmpty);
    });

    test('weekly keeps the weekday', () {
      final d = occurrences(rule(Repeat.weekly, DateTime(2026, 5, 1)), DateTime(2026, 5, 20));
      expect(d, [DateTime(2026, 5, 1), DateTime(2026, 5, 8), DateTime(2026, 5, 15)]);
    });

    test('monthly on the 31st clamps to short months', () {
      final d = occurrences(rule(Repeat.monthly, DateTime(2026, 1, 31)), DateTime(2026, 4, 30));
      expect(d, [
        DateTime(2026, 1, 31),
        DateTime(2026, 2, 28),
        DateTime(2026, 3, 31),
        DateTime(2026, 4, 30),
      ]);
    });

    test('materializing twice adds nothing the second time', () {
      final first = materializeRecurring(
          [rule(Repeat.daily, DateTime(2026, 5, 1))], DateTime(2026, 5, 3));
      expect(first.txns.length, 3);
      expect(first.txns.first.categoryId, 'coffee');
      final second = materializeRecurring(first.rules, DateTime(2026, 5, 3));
      expect(second.txns, isEmpty);
      final later = materializeRecurring(first.rules, DateTime(2026, 5, 5));
      expect(later.txns.map((t) => t.date.day), [4, 5]);
    });

    test('paused rules produce nothing', () {
      final r = rule(Repeat.daily, DateTime(2026, 5, 1)).copyWith(active: false);
      expect(materializeRecurring([r], DateTime(2026, 5, 9)).txns, isEmpty);
    });

    test('the app logs due spending on load, once', () async {
      final r = rule(Repeat.daily, DateTime.now().subtract(const Duration(days: 2)));
      final before = BudgetState.initial().copyWith(recurring: [r]);
      SharedPreferences.setMockInitialValues({
        'budget_state_v1': _json(before),
      });
      final prefs = await SharedPreferences.getInstance();
      ProviderContainer make() => ProviderContainer(
          overrides: [prefsProvider.overrideWithValue(prefs)]);

      final c1 = make();
      addTearDown(c1.dispose);
      expect(c1.read(budgetProvider).txns.length, 3); // 2 days ago, yesterday, today

      final c2 = make(); // "reopening" the app reads what was saved
      addTearDown(c2.dispose);
      expect(c2.read(budgetProvider).txns.length, 3);
    });
  });

  group('split purchases', () {
    final split = Txn(
      id: 's',
      date: DateTime(2026, 5, 2),
      amount: 100,
      categoryId: 'groceries',
      splits: const [SplitPart('groceries', 60), SplitPart('extras', 40)],
    );
    final state = BudgetState.initial().copyWith(txns: [split]);

    test('each category gets its share; the total is unchanged', () {
      final sum = summarize(state, may);
      double spent(String id) =>
          sum.categories.firstWhere((c) => c.category.id == id).spent;
      expect(spent('groceries'), 60);
      expect(spent('extras'), 40);
      expect(sum.spent, 100);
    });

    test('filter by category matches any part', () {
      expect(filterTxns(state, categoryId: 'extras'), [split]);
      expect(filterTxns(state, categoryId: 'coffee'), isEmpty);
    });

    test('deleting a category moves its share to Other', () {
      final gone = split.withoutCategory('extras');
      expect(gone.parts.map((p) => p.categoryId), ['groceries', otherCategoryId]);
      expect(gone.parts.fold<double>(0, (a, p) => a + p.amount), 100);
    });

    test('survives a JSON round trip', () {
      final back = BudgetState.fromJson(state.toJson());
      expect(back.txns.single.isSplit, isTrue);
      expect(back.txns.single.parts.last.amount, 40);
    });
  });

  group('search and filters', () {
    final s = BudgetState.initial().copyWith(
      cards: const [PaymentCard(id: 'c', name: 'Visa', colorIndex: 0)],
      txns: [
        Txn(id: '1', date: DateTime(2026, 5, 2), amount: 45, categoryId: 'coffee', note: 'Latte'),
        Txn(id: '2', date: DateTime(2026, 5, 3), amount: 1250, categoryId: 'groceries', cardId: 'c'),
        Txn(id: '3', date: DateTime(2026, 4, 3), amount: 20, categoryId: 'coffee'),
        Txn(id: '4', date: DateTime(2026, 5, 4), amount: 10, cardId: 'c', isPayment: true),
      ],
    );

    List<String> ids(List<Txn> l) => l.map((t) => t.id).toList();

    test('month scope and all time', () {
      expect(ids(filterTxns(s, month: may)), ['2', '1']);
      expect(ids(filterTxns(s)), ['2', '1', '3']);
    });

    test('text search covers note, category, card and amount', () {
      expect(ids(filterTxns(s, query: 'latte')), ['1']);
      expect(ids(filterTxns(s, query: 'grocer')), ['2']);
      expect(ids(filterTxns(s, query: 'visa')), ['2']);
      expect(ids(filterTxns(s, query: '1,250')), ['2']);
    });

    test('card and cash filters', () {
      expect(ids(filterTxns(s, cardId: 'c')), ['2']);
      expect(ids(filterTxns(s, cashOnly: true)), ['1', '3']);
    });
  });

  group('debt payoff', () {
    test('no interest: balance / payment', () {
      final p = payoff(1000, 250, 0);
      expect(p.months, 4);
      expect(p.interest, 0);
      expect(p.never, isFalse);
    });

    test('interest makes it longer and costs money', () {
      final p = payoff(1000, 250, 12);
      expect(p.months, 5);
      expect(p.interest, greaterThan(0));
    });

    test('extra payments shorten it and save interest', () {
      final base = payoff(10000, 300, 18);
      final more = payoff(10000, 300, 18, extra: 200);
      expect(more.months, lessThan(base.months));
      expect(more.interest, lessThan(base.interest));
    });

    test('a payment that only covers the interest never clears it', () {
      expect(payoff(10000, 100, 12).never, isTrue); // interest is 100/month
    });

    test('nothing owed is already done', () {
      expect(payoff(0, 100, 10).months, 0);
    });
  });

  group('savings goals', () {
    test('monthly amount spreads the remainder over months left, inclusive', () {
      final g = Goal(
          id: 'g', name: 'Trip', target: 3000, saved: 600, deadline: DateTime(2026, 12));
      // May..December = 8 months, 2400 to go.
      expect(g.monthlyNeeded(DateTime(2026, 5, 10)), 300);
      expect(g.progress, closeTo(0.2, 1e-9));
    });

    test('reached goals need nothing; no deadline gives no figure', () {
      expect(
          const Goal(id: 'g', name: 'x', target: 10, saved: 10).monthlyNeeded(may), isNull);
      expect(const Goal(id: 'g', name: 'x', target: 10).monthlyNeeded(may), isNull);
    });

    test('adding funds can log spending, withdrawing never goes below zero', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(overrides: [prefsProvider.overrideWithValue(prefs)]);
      addTearDown(c.dispose);
      final n = c.read(budgetProvider.notifier);
      const g = Goal(id: 'g', name: 'Trip', target: 1000);
      n.saveGoal(g);

      n.addToGoal(g, 200, asSpending: true);
      expect(c.read(budgetProvider).goals.single.saved, 200);
      expect(c.read(budgetProvider).txns.single.amount, 200);
      expect(c.read(budgetProvider).txns.single.categoryId, 'savings');

      n.addToGoal(g, -500);
      expect(c.read(budgetProvider).goals.single.saved, 0);
      expect(c.read(budgetProvider).txns.length, 1);
    });
  });

  group('trends', () {
    final s = BudgetState.initial().copyWith(
      incomes: const [Income(id: 'i', name: 'Salary', amount: 1000)],
      bills: const [Bill(id: 'b', name: 'Rent', amount: 400, categoryId: 'housing')],
      txns: [
        Txn(id: '1', date: DateTime(2026, 5, 2), amount: 50, categoryId: 'coffee'),
        Txn(id: '2', date: DateTime(2026, 4, 2), amount: 20, categoryId: 'coffee'),
        Txn(id: '3', date: DateTime(2026, 4, 5), amount: 30, categoryId: 'groceries'),
      ],
    );

    test('six months ending at the selected month, oldest first', () {
      final t = monthlyTrend(s, may);
      expect(t.length, 6);
      expect(t.first.month, DateTime(2025, 12));
      expect(t.last.month, may);
      expect(t.last.spent, 50);
      expect(t.last.out, 450);
      expect(t.last.net, 550);
      expect(t[4].spent, 50); // April: 20 + 30
    });

    test('category changes are sorted by size and flag new spending', () {
      final c = categoryChanges(s, may);
      final coffee = c.firstWhere((x) => x.category.id == 'coffee');
      expect(coffee.delta, 30);
      expect(coffee.percent, 150);
      final groceries = c.firstWhere((x) => x.category.id == 'groceries');
      expect(groceries.delta, -30);
      expect(c.every((x) => x.current > 0 || x.previous > 0), isTrue);
    });
  });

  test('older saves without new fields still load', () {
    final j = BudgetState.initial().toJson()
      ..remove('recurring')
      ..remove('goals');
    final s = BudgetState.fromJson(j);
    expect(s.recurring, isEmpty);
    expect(s.goals, isEmpty);
  });

  group('repaying a debt from spending', () {
    Future<ProviderContainer> make() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(overrides: [prefsProvider.overrideWithValue(prefs)]);
      addTearDown(c.dispose);
      c.read(budgetProvider.notifier).saveBill(const Bill(
          id: 'loan', name: 'Car loan', amount: 300, categoryId: 'transport',
          isDebt: true, debtBalance: 1000));
      return c;
    }

    double owed(ProviderContainer c) =>
        c.read(budgetProvider).bills.single.debtBalance!;

    test('saving lowers the balance, editing applies the difference, deleting restores it', () async {
      final c = await make();
      final n = c.read(budgetProvider.notifier);
      final t = Txn(id: 't', date: DateTime(2026, 5, 2), amount: 200, debtId: 'loan');

      n.saveTxn(t);
      expect(owed(c), 800);

      n.saveTxn(Txn(id: 't', date: t.date, amount: 250, debtId: 'loan'));
      expect(owed(c), 750);

      n.deleteTxn('t');
      expect(owed(c), 1000);
    });

    test('never goes below zero and counts as money spent', () async {
      final c = await make();
      c.read(budgetProvider.notifier)
          .saveTxn(Txn(id: 't', date: DateTime(2026, 5, 2), amount: 1500, debtId: 'loan'));
      expect(owed(c), 0);
      expect(summarize(c.read(budgetProvider), may).spent, 1500);
    });

    test('the link survives saving and loading', () {
      final t = Txn(id: 't', date: DateTime(2026, 5, 2), amount: 5, debtId: 'loan');
      expect(Txn.fromJson(t.toJson()).debtId, 'loan');
    });
  });
}

String _json(BudgetState s) => jsonEncode(s.toJson());
