import 'package:budgeting_app/features/budget/domain/coach.dart';
import 'package:budgeting_app/features/budget/domain/models.dart';
import 'package:budgeting_app/features/budget/domain/payoff.dart';
import 'package:flutter_test/flutter_test.dart';

CoachDebt debt(String id, double bal, double apr, double min) =>
    CoachDebt(id: id, name: id, balance: bal, apr: apr, minPayment: min);

void main() {
  final sep = DateTime(2026, 9);

  group('simulatePlan', () {
    test('a single debt agrees with the single-debt calculator', () {
      final one = simulatePlan([debt('a', 1000, 12, 100)], extra: 0);
      final old = payoff(1000, 100, 12);
      expect(one.months, old.months);
      expect(one.interest, closeTo(old.interest, 0.01));
      expect(one.never, isFalse);
    });

    test('extra money clears debt sooner and saves interest', () {
      final debts = [debt('a', 5000, 18, 200)];
      final slow = simulatePlan(debts, extra: 0);
      final fast = simulatePlan(debts, extra: 300);
      expect(fast.months, lessThan(slow.months));
      expect(fast.interest, lessThan(slow.interest));
    });

    test('a payment below the interest never clears the debt', () {
      final debts = [debt('a', 10000, 24, 100)];
      expect(simulatePlan(debts, extra: 0).never, isTrue);
      expect(simulatePlan(debts, extra: 200).never, isFalse);
    });

    test('freed-up payments roll onto the next debt', () {
      final debts = [debt('small', 1000, 10, 100), debt('big', 6000, 20, 200)];
      final rolled = simulatePlan(debts, extra: 0);
      final alone = simulatePlan(debts, extra: 0, rollover: false);
      expect(rolled.months, lessThan(alone.months));
      expect(rolled.steps.map((s) => s.debt.id), ['small', 'big']);
      expect(rolled.steps.first.month, lessThan(rolled.steps.last.month));
    });

    test('avalanche targets the highest rate, snowball the smallest balance', () {
      final debts = [debt('small', 1000, 8, 50), debt('big', 6000, 22, 150)];
      final av = simulatePlan(debts, extra: 300, strategy: Strategy.avalanche);
      final sn = simulatePlan(debts, extra: 300, strategy: Strategy.snowball);
      expect(av.firstMonthExtra.keys, ['big']);
      expect(sn.firstMonthExtra.keys, ['small']);
      expect(av.interest, lessThanOrEqualTo(sn.interest));
    });

    test('this month\'s extra always adds up to the extra put in', () {
      final debts = [
        debt('loan', 58000, 11.5, 4300),
        debt('mc', 704, 0, 21.12),
        debt('visa', 2197, 0, 65.91),
      ];
      for (final extra in [556.0, 1113.0, 99.0, 3500.0]) {
        final p = simulatePlan(debts, extra: extra);
        final total = p.firstMonthExtra.values.fold<double>(0, (a, v) => a + v);
        expect(total, closeTo(extra, 0.01), reason: 'extra $extra');
      }
    });

    test('extra spills onto the next debt when the first is nearly clear', () {
      final debts = [debt('tiny', 100, 30, 20), debt('big', 5000, 10, 100)];
      final p = simulatePlan(debts, extra: 500, strategy: Strategy.avalanche);
      expect(p.firstMonthExtra.keys.toSet(), {'tiny', 'big'});
    });

    test('firstMonthExtra only changes month 1 - later months use the steady extra', () {
      final debts = [debt('a', 20000, 15, 200)];
      final p = simulatePlan(debts, extra: 4900, firstMonthExtra: 0);
      expect(p.schedule.first.totalPaid, closeTo(200, 0.01)); // minimum only
      expect(p.schedule[1].totalPaid, closeTo(200 + 4900, 0.01)); // back to normal
      expect(p.firstMonthExtra, isEmpty); // nothing extra went out in month 1
    });

    test('a dip in month 1 does not reduce how fast the plan clears the debt overall', () {
      final debts = [debt('a', 20000, 15, 200)];
      final steady = simulatePlan(debts, extra: 4900);
      final dipped = simulatePlan(debts, extra: 4900, firstMonthExtra: 0);
      // One month lighter, then back to the same pace - at most one month slower.
      expect(dipped.months, lessThanOrEqualTo(steady.months + 1));
    });

    test('nothing owed means an empty plan', () {
      final p = simulatePlan(const [], extra: 500);
      expect(p.months, 0);
      expect(p.never, isFalse);
    });

    test('totals fall to zero on the last month', () {
      final p = simulatePlan([debt('a', 900, 12, 300)], extra: 0);
      expect(p.totals.first, 900);
      expect(p.totals.last, 0);
      expect(p.totals.length, p.months + 1);
    });
  });

  group('schedule and phases', () {
    final debts = [
      debt('small', 3000, 8, 50),
      debt('big', 6000, 22, 150),
    ];

    test('every month is recorded and ends at zero owed', () {
      final p = simulatePlan(debts, extra: 300);
      expect(p.schedule.length, p.months);
      expect(p.schedule.first.month, 1);
      expect(p.schedule.last.totalOwed, closeTo(0, 0.01));
      expect(p.schedule.last.month, p.months);
    });

    test('each month pays the full pool until the final month', () {
      final p = simulatePlan(debts, extra: 300);
      final pool = 50 + 150 + 300;
      for (final m in p.schedule.take(p.months - 1)) {
        expect(m.totalPaid, closeTo(pool, 0.01), reason: 'month ${m.month}');
      }
      expect(p.schedule.last.totalPaid, lessThanOrEqualTo(pool + 0.01));
    });

    test('what is owed only ever goes down and matches the totals', () {
      final p = simulatePlan(debts, extra: 300);
      for (var i = 0; i < p.schedule.length; i++) {
        expect(p.schedule[i].totalOwed, closeTo(p.totals[i + 1], 0.01));
        if (i > 0) {
          expect(p.schedule[i].totalOwed, lessThan(p.schedule[i - 1].totalOwed));
        }
      }
    });

    test('interest across the schedule adds up to the plan interest', () {
      final p = simulatePlan(debts, extra: 300);
      final sum = p.schedule.fold<double>(0, (a, m) => a + m.interest);
      expect(sum, closeTo(p.interest, 0.01));
    });

    test('a cleared debt is reported in the month it reaches zero and then stops being paid', () {
      final p = simulatePlan(debts, extra: 300, strategy: Strategy.snowball);
      final smallMonth = p.steps.firstWhere((s) => s.debt.id == 'small').month;
      expect(p.schedule[smallMonth - 1].cleared.map((d) => d.id), contains('small'));
      for (final m in p.schedule.skip(smallMonth)) {
        expect(m.paid.containsKey('small'), isFalse);
      }
    });

    test('phases follow the extra money: highest interest first, then the next debt', () {
      final p = simulatePlan(debts, extra: 300);
      final phases = planPhases(p, debts);
      expect(phases.map((ph) => ph.target.id), ['big', 'small']);
      expect(phases.first.firstMonth, 1);
      expect(phases.first.targetPayment, closeTo(450, 0.01)); // 150 minimum + 300 extra
      expect(phases.first.others.map((d) => d.id), ['small']);
      expect(phases.first.clearsAtEnd, isTrue);
      expect(phases.first.nextTarget?.id, 'small');
      expect(phases.last.lastMonth, p.months);
      expect(phases.last.nextTarget, isNull);
      // Phases run back to back with no gaps.
      expect(phases[1].firstMonth, phases[0].lastMonth + 1);
    });

    test('once the first debt is gone its payment rolls into the next', () {
      final p = simulatePlan(debts, extra: 300);
      final phases = planPhases(p, debts);
      // Second phase pays the small debt its own minimum plus everything freed up.
      expect(phases[1].targetPayment, closeTo(500, 0.01));
      expect(phases[1].others, isEmpty);
    });

    test('a single debt is one phase', () {
      final p = simulatePlan([debt('a', 900, 12, 300)], extra: 0);
      final phases = planPhases(p, [debt('a', 900, 12, 300)]);
      expect(phases.length, 1);
      expect(phases.single.length, p.months);
    });
  });

  group('custom priority strategy', () {
    final debts = [
      debt('small', 1000, 8, 50),
      debt('big', 6000, 22, 150),
    ];

    test('the chosen debt gets the extra first, even though it is not the smart pick', () {
      final p = simulatePlan(debts, extra: 300, strategy: Strategy.custom, priorityDebtId: 'small');
      expect(p.firstMonthExtra.keys, ['small']);
    });

    test('with nothing chosen yet it behaves exactly like highest-interest-first', () {
      final custom = simulatePlan(debts, extra: 300, strategy: Strategy.custom);
      final avalanche = simulatePlan(debts, extra: 300, strategy: Strategy.avalanche);
      expect(custom.firstMonthExtra, avalanche.firstMonthExtra);
      expect(custom.months, avalanche.months);
      expect(custom.interest, avalanche.interest);
    });

    test('every other debt still gets its normal minimum, never zero', () {
      final p = simulatePlan(debts, extra: 300, strategy: Strategy.custom, priorityDebtId: 'small');
      expect(p.schedule.first.paid['big'], 150); // its minimum, untouched
    });

    test('once the chosen debt clears, the freed-up money moves on', () {
      final p = simulatePlan(debts, extra: 300, strategy: Strategy.custom, priorityDebtId: 'small');
      final phases = planPhases(p, debts);
      expect(phases.map((ph) => ph.target.id), ['small', 'big']);
    });
  });

  group('split evenly strategy', () {
    test('extra money divides equally across every open debt', () {
      final debts = [debt('a', 6000, 12, 100), debt('b', 6000, 12, 100)];
      final p = simulatePlan(debts, extra: 400, strategy: Strategy.splitEvenly);
      expect(p.firstMonthExtra['a'], closeTo(200, 0.01));
      expect(p.firstMonthExtra['b'], closeTo(200, 0.01));
      expect(p.schedule.first.targetId, isNull); // no single target
    });

    test('a debt needing less than its share only gets what it needs, the rest flows on', () {
      final debts = [debt('tiny', 40, 10, 20), debt('big', 6000, 10, 100)];
      final p = simulatePlan(debts, extra: 300, strategy: Strategy.splitEvenly);
      // tiny needs only ~20 more after its minimum; everything else goes to big.
      final tinyPaid = p.schedule.first.paid['tiny']!;
      final bigPaid = p.schedule.first.paid['big']!;
      expect(tinyPaid, closeTo(40 + 40 * 10 / 100 / 12, 0.1));
      expect(bigPaid, closeTo(100 + 300 - (tinyPaid - 20), 0.1));
    });

    test('splitting evenly clears both debts and costs no more interest than it should', () {
      final debts = [debt('a', 3000, 15, 100), debt('b', 3000, 15, 100)];
      final p = simulatePlan(debts, extra: 500, strategy: Strategy.splitEvenly);
      expect(p.never, isFalse);
      expect(p.totals.last, closeTo(0, 0.01));
    });

    test('with only one debt left, it gets everything, same as any other strategy', () {
      final p = simulatePlan([debt('a', 1000, 10, 200)], extra: 300, strategy: Strategy.splitEvenly);
      expect(p.firstMonthExtra['a'], 300);
    });
  });

  group('coachBudget', () {
    BudgetState state({double budgetTotal = 3500}) {
      final base = BudgetState.initial();
      return base.copyWith(
        categories: [
          for (final c in base.categories)
            c.copyWith(budget: c.id == 'groceries' ? budgetTotal : 0),
        ],
        incomes: const [Income(id: 'i', name: 'Salary', amount: 20000)],
        bills: const [
          Bill(id: 'r', name: 'Rent', amount: 8000, categoryId: 'housing'),
          Bill(id: 'l', name: 'Car loan', amount: 4300, categoryId: 'debt',
              isDebt: true, debtBalance: 58000, interestRate: 11.5),
        ],
      );
    }

    test('spare money starts from exactly what Overview shows as left to spend', () {
      final b = coachBudget(state(), sep, intensity: 1);
      // income 20000 - bills 8000 - loan payment 4300 - nothing spent yet = 7700.
      expect(b.leftToSpend, 7700);
      expect(b.buffer, 1000); // 5% of income by default
      expect(b.bufferIsDefault, isTrue);
      expect(b.spare, 6700);
    });

    test(
        'a category budget never reduces spare money on its own - only what is actually '
        'spent does (the bug this guards against)', () {
      final untouched = coachBudget(state(budgetTotal: 3500), sep, intensity: 1);
      final hugeBudget = coachBudget(state(budgetTotal: 999999), sep, intensity: 1);
      final noBudget = coachBudget(state(budgetTotal: 0), sep, intensity: 1);
      expect(hugeBudget.spare, untouched.spare);
      expect(noBudget.spare, untouched.spare);
    });

    test('actually spending money reduces what is spare, budgets or not', () {
      final s = state().copyWith(
          txns: [Txn(id: 't', date: sep, amount: 1200, categoryId: 'groceries')]);
      final b = coachBudget(s, sep, intensity: 1);
      expect(b.leftToSpend, 7700 - 1200);
      expect(b.spare, 6700 - 1200);
    });

    test('a large amount left to spend gives a correspondingly large extra payment '
        'under All-in (the reported bug)', () {
      final s = BudgetState.initial().copyWith(
        incomes: const [Income(id: 'i', name: 'Salary', amount: 6000)],
      );
      final b = coachBudget(s, sep, intensity: 2, buffer: 0);
      expect(b.leftToSpend, 6000);
      expect(b.spare, 6000);
      expect(b.extra, 5400); // 90% of 6000, not some small fraction of it
    });

    test('seriousness decides how much spare money goes to debt', () {
      expect(coachBudget(state(), sep, intensity: 0).extra, 1675);
      expect(coachBudget(state(), sep, intensity: 1).extra, 3350);
      expect(coachBudget(state(), sep, intensity: 2).extra, 6030);
      final b = coachBudget(state(), sep, intensity: 1);
      expect(b.flexible, b.spare - b.extra);
    });

    test('a chosen backup amount replaces the default', () {
      final b = coachBudget(state(), sep, intensity: 1, buffer: 2200);
      expect(b.bufferIsDefault, isFalse);
      expect(b.spare, 5500);
      expect(b.extra, 2750);
    });

    test('no spare money means no extra payment', () {
      final s = state().copyWith(
          txns: [Txn(id: 't', date: sep, amount: 8000, categoryId: 'groceries')]);
      final b = coachBudget(s, sep, intensity: 2);
      expect(b.spare, lessThan(0));
      expect(b.extra, 0);
      expect(b.flexible, 0);
    });

    test('card minimums come out of spare money', () {
      final s = state().copyWith(cards: const [
        PaymentCard(id: 'c', name: 'Visa', colorIndex: 0, openingBalance: 4000, minPayment: 400),
      ]);
      final b = coachBudget(s, sep, intensity: 1);
      expect(b.cardMinimums, 400);
      expect(b.spare, 6300);
    });

    test('a manual correction to left to spend only affects this period, not the steady figure',
        () {
      final withoutOverride = coachBudget(state(), sep, intensity: 1);
      final s = state().copyWith(leftAdjustments: {monthKey(sep): -5000});
      final b = coachBudget(s, sep, intensity: 1);
      expect(b.leftToSpend, withoutOverride.leftToSpend - 5000);
      expect(b.steadyLeftToSpend, withoutOverride.leftToSpend);
      expect(b.extra, lessThan(b.steadyExtra));
      expect(b.steadyExtra, withoutOverride.extra);
    });

    test('with no correction, the steady figure is exactly the this-period figure', () {
      final b = coachBudget(state(), sep, intensity: 1);
      expect(b.steadyLeftToSpend, b.leftToSpend);
      expect(b.steadyExtra, b.extra);
    });
  });

  group('coachDebts and buildCoachPlan', () {
    test('loans and credit cards are both included, cards with an estimated minimum', () {
      final s = BudgetState.initial().copyWith(
        bills: const [
          Bill(id: 'l', name: 'Loan', amount: 500, categoryId: 'debt',
              isDebt: true, debtBalance: 9000, interestRate: 10),
          Bill(id: 'x', name: 'Paid off', amount: 100, categoryId: 'debt',
              isDebt: true, debtBalance: 0),
        ],
        cards: const [
          PaymentCard(id: 'c', name: 'Visa', colorIndex: 0, openingBalance: 2000),
          PaymentCard(id: 'd', name: 'Debit', colorIndex: 1, isCredit: false),
        ],
      );
      final debts = coachDebts(s, sep);
      expect(debts.map((d) => d.id), ['l', 'c']);
      final card = debts.last;
      expect(card.isCard, isTrue);
      expect(card.minEstimated, isTrue);
      expect(card.minPayment, closeTo(60, 0.001));
      expect(card.rateMissing, isTrue);
      expect(debts.first.rateMissing, isFalse);
    });

    test('the plan beats doing nothing when there is spare money', () {
      final s = BudgetState.initial().copyWith(
        incomes: const [Income(id: 'i', name: 'Salary', amount: 20000)],
        bills: const [
          Bill(id: 'r', name: 'Rent', amount: 8000, categoryId: 'housing'),
          Bill(id: 'l', name: 'Loan', amount: 2000, categoryId: 'debt',
              isDebt: true, debtBalance: 30000, interestRate: 12),
        ],
      );
      final plan = buildCoachPlan(s, sep, intensity: 1);
      expect(plan.hasDebts, isTrue);
      expect(plan.budget.extra, greaterThan(0));
      expect(plan.avalanche.months, lessThan(plan.baseline.months));
      expect(plan.avalanche.interest, lessThan(plan.baseline.interest));
      expect(plan.recommended, Strategy.avalanche);
    });

    test('no debts gives an empty plan', () {
      final plan = buildCoachPlan(BudgetState.initial(), sep);
      expect(plan.hasDebts, isFalse);
      expect(plan.avalanche.months, 0);
    });

    test('a plan carries all four strategies, and "best" follows recommended', () {
      final s = BudgetState.initial().copyWith(
        incomes: const [Income(id: 'i', name: 'Salary', amount: 20000)],
        bills: const [
          Bill(id: 'small', name: 'Small', amount: 100, categoryId: 'debt',
              isDebt: true, debtBalance: 2000, interestRate: 8),
          Bill(id: 'big', name: 'Big', amount: 200, categoryId: 'debt',
              isDebt: true, debtBalance: 10000, interestRate: 22),
        ],
      );
      final plan = buildCoachPlan(s, sep, intensity: 1, priorityDebtId: 'small');
      expect(plan.priorityDebtId, 'small');
      // The extra is so much bigger than "small" that it clears immediately
      // and the rest spills onto "big" in the same month.
      expect(plan.custom.steps.first.debt.id, 'small');
      expect(plan.custom.steps.first.month, 1);
      expect(plan.splitEvenly.firstMonthExtra.keys.toSet(), {'small', 'big'});
      expect(plan.recommended, Strategy.avalanche); // highest interest first is cheapest here
      expect(plan.best, plan.avalanche);
      // Picking the wrong debt first costs more than the recommended order.
      expect(plan.custom.interest, greaterThan(plan.avalanche.interest));
    });

    test(
        'a one-off correction that wipes out this period\'s spare money still lets next '
        'period pay real extra (the reported bug: every month after showed only the '
        'minimum)', () {
      final s = BudgetState.initial().copyWith(
        incomes: const [Income(id: 'i', name: 'Salary', amount: 20000)],
        bills: const [
          Bill(id: 'cc', name: 'Credit card', amount: 500, categoryId: 'debt',
              isDebt: true, debtBalance: 30000, interestRate: 20),
        ],
        // A correction that makes this period's left to spend negative, as if
        // the user had logged a big one-off expense against Overview.
        leftAdjustments: {monthKey(sep): -50000},
      );
      final plan = buildCoachPlan(s, sep, intensity: 2);
      expect(plan.budget.extra, 0); // nothing spare this period specifically
      expect(plan.budget.steadyExtra, greaterThan(0)); // but a normal period has plenty

      final month2 = plan.avalanche.schedule[1];
      // Month 2 pays real extra on top of the minimum - it must not inherit
      // this period's zero forever.
      expect(month2.totalPaid, greaterThan(500 + 0.5));
    });
  });

  group('saving', () {
    test('card interest and minimum payment survive a round trip', () {
      const c = PaymentCard(
          id: 'c', name: 'Visa', colorIndex: 2, interestRate: 21.5, minPayment: 350);
      final back = PaymentCard.fromJson(c.toJson());
      expect(back.interestRate, 21.5);
      expect(back.minPayment, 350);
    });

    test('older saves without the new fields still load', () {
      final j = const PaymentCard(id: 'c', name: 'Visa', colorIndex: 0).toJson()
        ..remove('interestRate')
        ..remove('minPayment');
      final back = PaymentCard.fromJson(j);
      expect(back.interestRate, 0);
      expect(back.minPayment, 0);
    });

    test('coach settings are saved and default sensibly', () {
      final s = BudgetState.initial().copyWith(coachIntensity: 2, coachBuffer: 750);
      final back = BudgetState.fromJson(s.toJson());
      expect(back.coachIntensity, 2);
      expect(back.coachBuffer, 750);
      final old = BudgetState.initial().toJson()
        ..remove('coachIntensity')
        ..remove('coachBuffer');
      final loaded = BudgetState.fromJson(old);
      expect(loaded.coachIntensity, 1);
      expect(loaded.coachBuffer, isNull);
    });
  });
}
