import 'dart:convert';

import 'package:budgeting_app/features/budget/application/budget_provider.dart';
import 'package:budgeting_app/features/budget/domain/coach.dart';
import 'package:budgeting_app/features/budget/domain/models.dart';
import 'package:budgeting_app/features/budget/domain/period.dart';
import 'package:budgeting_app/features/budget/domain/summary.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A notifier over [saved] (or a fresh install when null).
Future<ProviderContainer> _container([BudgetState? saved]) async {
  SharedPreferences.setMockInitialValues({
    if (saved != null) 'budget_state_v1': jsonEncode(saved.toJson()),
  });
  final prefs = await SharedPreferences.getInstance();
  final c = ProviderContainer(overrides: [prefsProvider.overrideWithValue(prefs)]);
  addTearDown(c.dispose);
  return c;
}

DateTime _before(DateTime month) => DateTime(month.year, month.month - 1);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final sep = DateTime(2026, 9);
  final oct = DateTime(2026, 10);
  final nov = DateTime(2026, 11);

  const salary = Income(id: 'i', name: 'Salary', amount: 20000);
  const rent = Bill(id: 'r', name: 'Rent', amount: 8000, categoryId: 'housing');

  BudgetState state() => BudgetState.initial().copyWith(
        periodStartDay: 1,
        incomes: const [salary],
        bills: const [rent],
        txns: [Txn(id: 't', date: DateTime(2026, 9, 5), amount: 500, categoryId: 'groceries')],
      );

  group('extra income', () {
    test('adds to what is left, is marked received, and cleans up when deleted', () async {
      final c = await _container(state());
      final n = c.read(budgetProvider.notifier);
      final month = c.read(budgetProvider).currentPeriod;
      final before = summarize(c.read(budgetProvider), month);

      n.addExtraIncome('Gift from Gran', 100, DateTime.now());
      var s = c.read(budgetProvider);
      final gift = s.incomes.singleWhere((i) => i.name == 'Gift from Gran');
      final after = summarize(s, month);
      expect(after.left, before.left + 100);
      expect(after.oneOffIncome, 100);
      expect(after.incomeReceived, before.incomeReceived + 100);
      expect(s.receivedOn(gift, month), isNotNull);
      // One-time: the next period does not get it again as income.
      expect(summarize(s, DateTime(month.year, month.month + 1)).income, before.income);

      n.deleteIncome(gift.id);
      s = c.read(budgetProvider);
      expect(s.received.keys.where((k) => k.endsWith('|${gift.id}')), isEmpty);
      expect(s.pastIncomes, isEmpty);
      expect(summarize(s, month).left, before.left);
    });

    test('helps the Debt Coach this period only, not the ongoing plan', () {
      final base = state();
      final gifted = base.copyWith(incomes: const [
        salary,
        Income(id: 'g', name: 'Gift', amount: 1000, oneOffMonth: '2026-10'),
      ]);
      final plain = coachBudget(base, oct);
      final withGift = coachBudget(gifted, oct);
      expect(withGift.leftToSpend, plain.leftToSpend + 1000);
      expect(withGift.steadyLeftToSpend, plain.steadyLeftToSpend);
      expect(withGift.buffer, plain.buffer);
    });
  });

  group('amount history', () {
    test('an edited bill keeps its old amount in earlier months', () {
      final edited = rent.edited(
          const Bill(id: 'r', name: 'Rent', amount: 9000, categoryId: 'housing'), oct);
      expect(edited.amountIn(sep), 8000);
      expect(edited.amountIn(oct), 9000);
      expect(edited.amountIn(nov), 9000);

      // A second change in the same month still leaves September alone.
      final again = edited.edited(
          const Bill(id: 'r', name: 'Rent', amount: 9500, categoryId: 'housing'), oct);
      expect(again.amountIn(sep), 8000);
      expect(again.amountIn(oct), 9500);

      // A change made from an earlier month replaces what came after it.
      final back = again.edited(
          const Bill(id: 'r', name: 'Rent', amount: 7000, categoryId: 'housing'), sep);
      expect(back.amountIn(DateTime(2026, 8)), 8000);
      expect(back.amountIn(sep), 7000);
      expect(back.amountIn(oct), 7000);
    });

    test('history survives a save/load round trip, and older saves load without any', () {
      final edited = rent.edited(
          const Bill(id: 'r', name: 'Rent', amount: 9000, categoryId: 'housing'), oct);
      final s = state().copyWith(bills: [edited]);
      expect(BudgetState.fromJson(s.toJson()).bills.single.amountIn(sep), 8000);

      final old = state().toJson();
      for (final b in old['bills'] as List) {
        (b as Map)..remove('earlier')..remove('startMonth')..remove('endMonth');
      }
      old..remove('pastBills')..remove('pastIncomes')..remove('carryOver')..remove('carryOverFrom');
      final back = BudgetState.fromJson(old);
      expect(back.bills.single.amountIn(sep), 8000);
      expect(back.pastBills, isEmpty);
      expect(summarize(back, oct).carriedOver, 0);
    });

    test('editing through the app changes this month on, not the ones before', () async {
      final c = await _container(state());
      final n = c.read(budgetProvider.notifier);
      final month = c.read(budgetProvider).currentPeriod;

      n.saveBill(const Bill(id: 'r', name: 'Rent', amount: 9000, categoryId: 'housing'));
      n.saveIncome(const Income(id: 'i', name: 'Salary', amount: 25000));
      final s = c.read(budgetProvider);
      expect(summarize(s, month).committed, 9000);
      expect(summarize(s, month).income, 25000);
      expect(summarize(s, _before(month)).committed, 8000);
      expect(summarize(s, _before(month)).income, 20000);
      expect(monthlyTrend(s, month, count: 2).map((t) => t.committed), [8000, 9000]);
    });

    test('a new bill or income does not count in months before it was added', () async {
      final c = await _container(state());
      final n = c.read(budgetProvider.notifier);
      final month = c.read(budgetProvider).currentPeriod;

      n.saveBill(const Bill(id: 'g', name: 'Gym', amount: 400, categoryId: 'health'));
      n.saveIncome(const Income(id: 'i2', name: 'Side gig', amount: 1500));
      final s = c.read(budgetProvider);
      expect(summarize(s, month).committed, 8400);
      expect(summarize(s, month).income, 21500);
      expect(summarize(s, _before(month)).committed, 8000);
      expect(summarize(s, _before(month)).income, 20000);
    });

    test('a deleted bill or income still counts in the months it was there', () async {
      final c = await _container(state());
      final n = c.read(budgetProvider.notifier);
      final month = c.read(budgetProvider).currentPeriod;
      n.markIncomeReceived(salary, _before(month), DateTime(2026, 1, 1));
      n.markIncomeReceived(salary, month, DateTime(2026, 1, 2));

      n.deleteBill('r');
      n.deleteIncome('i');
      final s = c.read(budgetProvider);
      expect(s.bills, isEmpty);
      expect(s.incomes, isEmpty);
      expect(summarize(s, month).committed, 0);
      expect(summarize(s, month).income, 0);
      expect(summarize(s, _before(month)).committed, 8000);
      expect(summarize(s, _before(month)).income, 20000);
      // Only the received date for a month it still counts in is kept.
      expect(s.received.keys, ['${monthKey(_before(month))}|i']);
    });

    test('something added and deleted in the same month leaves nothing behind', () async {
      final c = await _container(state());
      final n = c.read(budgetProvider.notifier);
      n.saveBill(const Bill(id: 'g', name: 'Gym', amount: 400, categoryId: 'health'));
      n.deleteBill('g');
      expect(c.read(budgetProvider).pastBills, isEmpty);
    });

    test('setting a pay day that renames the current month keeps new items in it', () async {
      final c = await _container();
      final n = c.read(budgetProvider.notifier);
      n.saveBill(rent);
      // A pay day later this month means the current period began last month.
      final today = DateTime.now().day;
      n.saveIncome(Income(id: 'i', name: 'Salary', amount: 20000, payDay: today < 28 ? today + 1 : 1));
      final s = c.read(budgetProvider);
      final sum = summarize(s, s.currentPeriod);
      expect(sum.committed, 8000);
      expect(sum.income, 20000);
      expect(sum.carriedOver, 0);
      expect(s.carryOverFrom, monthKey(s.currentPeriod));
    });
  });

  group('carry-over', () {
    BudgetState carrying() => state().copyWith(carryOverFrom: '2026-09');

    test('what was left last month is added to this one', () {
      final s = carrying();
      expect(summarize(s, sep).carriedOver, 0);
      expect(summarize(s, sep).left, 11500);
      expect(summarize(s, oct).carriedOver, 11500);
      expect(summarize(s, oct).left, 11500 + 12000);
      expect(summarize(s, nov).carriedOver, 11500 + 12000);
    });

    test('overspending is taken off the next month', () {
      final s = carrying().copyWith(txns: [
        Txn(id: 't', date: DateTime(2026, 9, 5), amount: 13000, categoryId: 'groceries'),
      ]);
      expect(summarize(s, sep).left, -1000);
      expect(summarize(s, oct).left, 12000 - 1000);
    });

    test('follows the same rules as left to spend for cards and corrections', () {
      final s = carrying().copyWith(
        cards: const [PaymentCard(id: 'c', name: 'Visa', colorIndex: 0)],
        leftAdjustments: {'2026-09': -250},
        txns: [
          // On credit: debt, not money out of income.
          Txn(id: 'a', date: DateTime(2026, 9, 3), amount: 900, cardId: 'c'),
          // Paying the card does come out of income.
          Txn(id: 'b', date: DateTime(2026, 9, 20), amount: 300, cardId: 'c', isPayment: true),
          Txn(id: 'd', date: DateTime(2026, 9, 21), amount: 200),
        ],
      );
      expect(summarize(s, oct).carriedOver, summarize(s, sep).left);
      expect(summarize(s, oct).carriedOver, 20000 - 8000 - 300 - 200 - 250);
    });

    test('nothing from before it was switched on is rolled in, and it can be off', () {
      expect(summarize(carrying(), DateTime(2026, 8)).carriedOver, 0);
      expect(summarize(state(), oct).carriedOver, 0);
      expect(summarize(carrying().copyWith(carryOver: false), oct).left, 12000);
    });

    test('starts from the current month the first time the app runs with it', () async {
      final c = await _container(state());
      final s = c.read(budgetProvider);
      final month = s.currentPeriod;
      expect(s.carryOverFrom, monthKey(month));
      expect(summarize(s, month).carriedOver, 0);
      expect(summarize(s, DateTime(month.year, month.month + 1)).carriedOver,
          summarize(s, month).left);

      c.read(budgetProvider.notifier).setCarryOver(false);
      expect(summarize(c.read(budgetProvider), DateTime(month.year, month.month + 1)).carriedOver, 0);
    });

    test('carried money does not inflate the ongoing Debt Coach plan', () {
      final plain = coachBudget(state(), oct);
      final carried = coachBudget(carrying(), oct);
      expect(carried.leftToSpend, plain.leftToSpend + 11500);
      expect(carried.steadyLeftToSpend, plain.steadyLeftToSpend);
    });
  });
}
