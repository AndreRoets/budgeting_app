import 'dart:convert';

import 'package:budgeting_app/features/budget/application/budget_provider.dart';
import 'package:budgeting_app/features/budget/domain/coach.dart';
import 'package:budgeting_app/features/budget/domain/models.dart';
import 'package:budgeting_app/features/budget/domain/period.dart';
import 'package:budgeting_app/features/budget/domain/summary.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _json(BudgetState s) => jsonEncode(s.toJson());

Future<ProviderContainer> _containerFor(BudgetState s) async {
  SharedPreferences.setMockInitialValues({'budget_state_v1': _json(s)});
  final prefs = await SharedPreferences.getInstance();
  final c = ProviderContainer(overrides: [prefsProvider.overrideWithValue(prefs)]);
  return c;
}

void main() {
  final sep = DateTime(2026, 9);

  BudgetState baseState() => BudgetState.initial().copyWith(
        periodStartDay: 1,
        incomes: const [Income(id: 'i', name: 'Salary', amount: 20000)],
        bills: const [
          Bill(id: 'loan', name: 'Loan', amount: 500, categoryId: 'debt',
              isDebt: true, debtBalance: 500000, interestRate: 20),
        ],
        cards: const [
          PaymentCard(id: 'card', name: 'Visa', colorIndex: 0,
              openingBalance: 5000, interestRate: 10, minPayment: 200),
        ],
      );

  group('coachBudget excludes the confirmed bill from what it can see', () {
    test('a confirmed bill amount does not shrink its own future extra', () {
      final clean = coachBudget(baseState(), sep, intensity: 1);
      final withBill = baseState().copyWith(bills: [
        ...baseState().bills,
        const Bill(
          id: '__coach_extra__',
          name: 'Extra to Loan',
          amount: 3000,
          categoryId: 'debt',
          isCoachExtra: true,
          coachTargetId: 'loan',
        ),
      ]);
      final b = coachBudget(withBill, sep, intensity: 1);
      // Left to spend shown to the user still reflects the real bill.
      expect(b.leftToSpend, clean.leftToSpend - 3000);
      // But spare/extra are computed as if it were not committed yet, so a
      // confirmed amount is stable rather than shrinking every period.
      expect(b.reservedForCoachBill, 3000);
      expect(b.spare, closeTo(clean.spare, 0.01));
      expect(b.extra, clean.extra);
    });
  });

  group('confirmCoachPlan', () {
    test('creates a bill matching the live plan\'s target and amount', () async {
      final c = await _containerFor(baseState());
      addTearDown(c.dispose);
      final n = c.read(budgetProvider.notifier);
      final plan = buildCoachPlan(c.read(budgetProvider), sep);

      n.confirmCoachPlan(sep);
      final bill = c.read(budgetProvider).bills.where((b) => b.isCoachExtra).single;
      expect(bill.amount, plan.budget.extra);
      expect(bill.coachTargetId, isNotNull);
      expect(bill.dueDay, c.read(budgetProvider).startDay);
    });

    test('does nothing when the strategy is split evenly (no single target)', () async {
      final c = await _containerFor(baseState().copyWith(coachStrategy: Strategy.splitEvenly.index));
      addTearDown(c.dispose);
      c.read(budgetProvider.notifier).confirmCoachPlan(sep);
      expect(c.read(budgetProvider).bills.any((b) => b.isCoachExtra), isFalse);
    });

    test(
        'still confirms when only THIS period is squeezed by a correction, as long as a '
        'normal period has spare money (the reported bug: no Confirm button at all)', () async {
      final s = baseState().copyWith(
        leftAdjustments: {'2026-09': -1000000}, // wipes out this period's spare money
      );
      final b = coachBudget(s, sep, intensity: 1);
      expect(b.extra, 0); // this period specifically: nothing spare
      expect(b.steadyExtra, greaterThan(0)); // but a normal period has plenty

      final c = await _containerFor(s);
      addTearDown(c.dispose);
      c.read(budgetProvider.notifier).confirmCoachPlan(sep);
      final bill = c.read(budgetProvider).bills.where((b) => b.isCoachExtra).firstOrNull;
      expect(bill, isNotNull);
      expect(bill!.amount, 0); // honestly reflects this period, not the steady figure
    });

    test('does nothing when there is no spare money', () async {
      final broke = baseState().copyWith(
        incomes: const [Income(id: 'i', name: 'Salary', amount: 100)],
      );
      final c = await _containerFor(broke);
      addTearDown(c.dispose);
      c.read(budgetProvider.notifier).confirmCoachPlan(sep);
      expect(c.read(budgetProvider).bills.any((b) => b.isCoachExtra), isFalse);
    });

    test('unconfirmCoachPlan removes the bill', () async {
      final c = await _containerFor(baseState());
      addTearDown(c.dispose);
      final n = c.read(budgetProvider.notifier);
      n.confirmCoachPlan(sep);
      expect(n.coachPlanConfirmed, isTrue);
      n.unconfirmCoachPlan();
      expect(n.coachPlanConfirmed, isFalse);
      expect(c.read(budgetProvider).bills.any((b) => b.isCoachExtra), isFalse);
    });
  });

  group('paying the confirmed bill', () {
    test('paying the full amount against a bill-type target reduces its balance', () async {
      final c = await _containerFor(baseState());
      addTearDown(c.dispose);
      final n = c.read(budgetProvider.notifier);
      n.confirmCoachPlan(sep);
      final bill = c.read(budgetProvider).bills.where((b) => b.isCoachExtra).single;
      expect(bill.coachTargetIsCard, isFalse); // avalanche picks the 20% loan first
      final before = c.read(budgetProvider).bills
          .where((b) => b.id == bill.coachTargetId).single.debtBalance!;

      n.markBillPaid(bill, sep, date: sep, amount: bill.amount);
      final after = c.read(budgetProvider).bills
          .where((b) => b.id == bill.coachTargetId).single.debtBalance!;
      expect(after, closeTo(before - bill.amount, 0.01));
    });

    test('paying less only reduces the target by that lesser amount', () async {
      final c = await _containerFor(baseState());
      addTearDown(c.dispose);
      final n = c.read(budgetProvider.notifier);
      n.confirmCoachPlan(sep);
      final bill = c.read(budgetProvider).bills.where((b) => b.isCoachExtra).single;
      final before = c.read(budgetProvider).bills
          .where((b) => b.id == bill.coachTargetId).single.debtBalance!;

      n.markBillPaid(bill, sep, date: sep, amount: 100);
      final after = c.read(budgetProvider).bills
          .where((b) => b.id == bill.coachTargetId).single.debtBalance!;
      expect(after, closeTo(before - 100, 0.01));
    });

    test('unmarking paid reverses the reduction', () async {
      final c = await _containerFor(baseState());
      addTearDown(c.dispose);
      final n = c.read(budgetProvider.notifier);
      n.confirmCoachPlan(sep);
      final bill = c.read(budgetProvider).bills.where((b) => b.isCoachExtra).single;
      final before = c.read(budgetProvider).bills
          .where((b) => b.id == bill.coachTargetId).single.debtBalance!;

      n.markBillPaid(bill, sep, date: sep, amount: 250);
      n.unmarkBillPaid(bill, sep);
      final after = c.read(budgetProvider).bills
          .where((b) => b.id == bill.coachTargetId).single.debtBalance!;
      expect(after, closeTo(before, 0.01));
    });

    test('when the target is a card, paying it creates a payment that reduces what is owed',
        () async {
      // Force the card to be the target by giving the loan a much lower rate.
      final s = baseState().copyWith(bills: const [
        Bill(id: 'loan', name: 'Loan', amount: 500, categoryId: 'debt',
            isDebt: true, debtBalance: 500000, interestRate: 1),
      ]);
      final c = await _containerFor(s);
      addTearDown(c.dispose);
      final n = c.read(budgetProvider.notifier);
      n.confirmCoachPlan(sep);
      final bill = c.read(budgetProvider).bills.where((b) => b.isCoachExtra).single;
      expect(bill.coachTargetIsCard, isTrue);
      final card = c.read(budgetProvider).cards.single;
      final before = summarizeCard(c.read(budgetProvider), card, sep).owed;

      n.markBillPaid(bill, sep, date: sep, amount: bill.amount);
      final after = summarizeCard(c.read(budgetProvider), card, sep).owed;
      expect(after, closeTo(before - bill.amount, 0.01));

      n.unmarkBillPaid(bill, sep);
      final restored = summarizeCard(c.read(budgetProvider), card, sep).owed;
      expect(restored, closeTo(before, 0.01));
    });
  });

  group('refreshCoachBill', () {
    test('moves the bill to the next debt once its target is fully paid off', () async {
      final s = baseState().copyWith(bills: const [
        Bill(id: 'loan', name: 'Loan', amount: 500, categoryId: 'debt',
            isDebt: true, debtBalance: 100, interestRate: 20),
      ]);
      final c = await _containerFor(s);
      addTearDown(c.dispose);
      final n = c.read(budgetProvider.notifier);
      n.confirmCoachPlan(sep);
      final bill = c.read(budgetProvider).bills.where((b) => b.isCoachExtra).single;
      expect(bill.coachTargetId, 'loan'); // only debt at first

      // Clear the loan entirely, as if it had just been paid off.
      n.markBillPaid(bill, sep, date: sep, amount: 100);
      n.refreshCoachBill(sep);

      final refreshed = c.read(budgetProvider).bills.where((b) => b.isCoachExtra).single;
      expect(refreshed.coachTargetId, 'card');
      expect(refreshed.coachTargetIsCard, isTrue);
    });

    test('does nothing when nothing is confirmed', () async {
      final c = await _containerFor(baseState());
      addTearDown(c.dispose);
      c.read(budgetProvider.notifier).refreshCoachBill(sep);
      expect(c.read(budgetProvider).bills.any((b) => b.isCoachExtra), isFalse);
    });
  });

  group('saving', () {
    test('the coach bill fields survive a round trip', () {
      const b = Bill(
        id: '__coach_extra__',
        name: 'Extra to Visa',
        amount: 1234,
        categoryId: 'debt',
        isCoachExtra: true,
        coachTargetId: 'card',
        coachTargetIsCard: true,
      );
      final back = Bill.fromJson(b.toJson());
      expect(back.isCoachExtra, isTrue);
      expect(back.coachTargetId, 'card');
      expect(back.coachTargetIsCard, isTrue);
    });

    test('older saves without the new fields default to not-a-coach-bill', () {
      final j = const Bill(id: 'r', name: 'Rent', amount: 100, categoryId: 'housing').toJson()
        ..remove('isCoachExtra')
        ..remove('coachTargetId')
        ..remove('coachTargetIsCard');
      final back = Bill.fromJson(j);
      expect(back.isCoachExtra, isFalse);
      expect(back.coachTargetId, isNull);
      expect(back.coachTargetIsCard, isFalse);
    });
  });
}
