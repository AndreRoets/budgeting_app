import 'models.dart';
import 'summary.dart';

/// Which order debts get the extra money.
///
/// Every strategy pays each debt its own minimum every month regardless -
/// nothing is ever paused. Only the leftover "extra" money is directed
/// differently: to the most expensive debt, the smallest one, a debt the
/// user chose, or split evenly across everything still open.
enum Strategy { avalanche, snowball, custom, splitEvenly }

/// Share of spare money that goes to debt for each seriousness level.
const coachShares = [0.25, 0.5, 0.9];

/// Backup money kept aside by default, as a share of income.
const defaultBufferShare = 0.05;

/// Minimum payment assumed for a card that has none entered.
const _assumedMinShare = 0.03;

const _maxMonths = 600;

/// A debt as the coach sees it: a loan or a credit card with a balance.
class CoachDebt {
  const CoachDebt({
    required this.id,
    required this.name,
    required this.balance,
    required this.apr,
    required this.minPayment,
    this.isCard = false,
    this.minEstimated = false,
  });

  final String id;
  final String name;
  final double balance;

  /// Yearly interest in percent. Zero means none was entered.
  final double apr;
  final double minPayment;
  final bool isCard;

  /// True when [minPayment] was guessed because the card has none entered.
  final bool minEstimated;

  bool get rateMissing => apr <= 0;
}

/// Everything the user still owes, loans and credit cards together.
List<CoachDebt> coachDebts(BudgetState s, DateTime month) => [
      for (final b in s.bills)
        if (b.isDebt && (b.debtBalance ?? 0) > 0)
          CoachDebt(
            id: b.id,
            name: b.name,
            balance: b.debtBalance!,
            apr: b.interestRate ?? 0,
            minPayment: b.amount,
          ),
      for (final c in s.cards)
        if (c.isCredit && summarizeCard(s, c, month).owed > 0)
          () {
            final owed = summarizeCard(s, c, month).owed;
            final entered = c.minPayment > 0;
            return CoachDebt(
              id: c.id,
              name: c.name,
              balance: owed,
              apr: c.interestRate,
              minPayment: entered
                  ? c.minPayment
                  : (owed * _assumedMinShare).clamp(0, owed).toDouble(),
              isCard: true,
              minEstimated: !entered,
            );
          }(),
    ];

/// A typical period's money, split into what is spoken for and what is spare.
///
/// This starts from exactly what Overview shows as "left to spend" for the
/// period ([leftToSpend]: income, minus bills and loan payments, minus
/// everything actually spent or paid so far, plus any manual correction the
/// user made there). Anything not already covered by that figure - credit
/// card minimums, backup money, savings goals - is subtracted from it to
/// find what's truly spare for extra debt payments.
class CoachBudget {
  const CoachBudget({
    required this.leftToSpend,
    required this.steadyLeftToSpend,
    required this.cardMinimums,
    required this.buffer,
    required this.bufferIsDefault,
    required this.goalSavings,
    required this.share,
    this.reservedForCoachBill = 0,
  });

  /// What Overview shows as "left to spend" for this period, including any
  /// one-off manual correction the user made there.
  final double leftToSpend;

  /// The same figure, but without a one-off manual correction: what a typical
  /// period looks like. A correction fixes up a period already under way, so
  /// it should not decide what the whole future payoff plan can afford - only
  /// this period's own numbers should.
  final double steadyLeftToSpend;

  /// Minimum payments on credit cards, which "left to spend" does not cover.
  final double cardMinimums;

  /// Backup money kept aside each period.
  final double buffer;
  final bool bufferIsDefault;

  /// Set aside this period for savings goals with a target date (a holiday,
  /// an emergency fund, ...), so debt payoff never eats into money you are
  /// deliberately putting away for something else.
  final double goalSavings;

  /// Share of spare money that goes to debt.
  final double share;

  /// Money already committed to a confirmed Debt Coach bill (see
  /// [BudgetState] `coachTargetId`/`isCoachExtra`), added back before working
  /// out what's spare - it is already subtracted from [leftToSpend] like any
  /// other bill, so without this a confirmed amount would keep shrinking
  /// itself every period it stays committed.
  final double reservedForCoachBill;

  double get spare =>
      leftToSpend - cardMinimums - buffer - goalSavings + reservedForCoachBill;
  double get steadySpare =>
      steadyLeftToSpend - cardMinimums - buffer - goalSavings + reservedForCoachBill;

  /// Extra put towards debt this period, in whole units.
  double get extra => spare > 0 ? (spare * share).floorToDouble() : 0;

  /// Extra put towards debt in a typical period - what the ongoing plan is
  /// built around, from next period onwards.
  double get steadyExtra => steadySpare > 0 ? (steadySpare * share).floorToDouble() : 0;

  /// Spare money left for the user after the extra payment.
  double get flexible => spare > 0 ? spare - extra : 0;
}

CoachBudget coachBudget(
  BudgetState s,
  DateTime month, {
  int? intensity,
  double? buffer,
}) {
  final sum = summarize(s, month);
  final debts = coachDebts(s, month);
  final mins = debts.where((d) => d.isCard).fold<double>(0, (a, d) => a + d.minPayment);
  final chosen = buffer ?? s.coachBuffer;
  final level = (intensity ?? s.coachIntensity).clamp(0, coachShares.length - 1);
  final coachBill = s.bills.where((b) => b.isCoachExtra).firstOrNull;
  return CoachBudget(
    leftToSpend: sum.left,
    steadyLeftToSpend: sum.left - sum.adjustment,
    cardMinimums: mins,
    buffer: chosen ?? sum.income * defaultBufferShare,
    bufferIsDefault: chosen == null,
    goalSavings: goalsSavingsNeeded(s.goals, month, DateTime.now()),
    share: coachShares[level],
    reservedForCoachBill: coachBill?.amount ?? 0,
  );
}

/// One debt being cleared: which month (1 = next payment) it reaches zero.
class PayoffStep {
  const PayoffStep(this.debt, this.month);
  final CoachDebt debt;
  final int month;
}

/// What happens in one month of a plan.
class PlanMonth {
  const PlanMonth({
    required this.month,
    required this.paid,
    required this.balance,
    required this.interest,
    required this.cleared,
    required this.targetId,
  });

  /// 1 is this month.
  final int month;

  /// Money paid to each debt this month, by debt id.
  final Map<String, double> paid;

  /// What is still owed on each debt after this month's payments.
  final Map<String, double> balance;

  /// Interest added this month across all debts.
  final double interest;

  /// Debts that reach zero this month.
  final List<CoachDebt> cleared;

  /// The debt receiving the extra money this month.
  final String? targetId;

  double get totalPaid => paid.values.fold(0, (a, v) => a + v);
  double get totalOwed => balance.values.fold(0, (a, v) => a + v);
}

class PlanResult {
  const PlanResult({
    required this.months,
    required this.interest,
    required this.never,
    required this.steps,
    required this.totals,
    required this.firstMonthExtra,
    this.schedule = const [],
  });

  /// Months until every debt is cleared (0 when nothing is owed).
  final int months;
  final double interest;

  /// True when the debts don't clear at these payments.
  final bool never;

  /// Debts in the order they clear.
  final List<PayoffStep> steps;

  /// Total owed at the start, then after each month.
  final List<double> totals;

  /// How the extra money is split this month, by debt id.
  final Map<String, double> firstMonthExtra;

  /// Every month of the plan, in order.
  final List<PlanMonth> schedule;
}

/// Simulates paying the minimums plus [extra] every month.
///
/// With [rollover] the money freed when a debt clears moves to the next one,
/// which is what makes a plan fast. Without it every debt just keeps its own
/// payment, which is "what happens if nothing changes".
///
/// [firstMonthExtra], if given, replaces [extra] for month 1 only - so a
/// one-off dip or boost this period does not get baked into every future
/// month of the plan.
PlanResult simulatePlan(
  List<CoachDebt> debts, {
  required double extra,
  double? firstMonthExtra,
  Strategy strategy = Strategy.avalanche,
  bool rollover = true,
  String? priorityDebtId,
}) {
  final bal = {for (final d in debts) d.id: d.balance};
  final start = bal.values.fold<double>(0, (a, v) => a + v);
  if (debts.isEmpty || start <= 0) {
    return const PlanResult(
        months: 0, interest: 0, never: false, steps: [], totals: [0], firstMonthExtra: {});
  }

  final minSum = debts.fold<double>(0, (a, d) => a + d.minPayment);
  final pool = minSum + extra;
  final firstPool = minSum + (firstMonthExtra ?? extra);
  final totals = <double>[start];
  final steps = <PayoffStep>[];
  final schedule = <PlanMonth>[];
  final firstExtra = <String, double>{};
  final cleared = <String>{};
  var interest = 0.0;

  int byPriority(CoachDebt a, CoachDebt b) {
    if (strategy == Strategy.custom && priorityDebtId != null) {
      if (a.id == priorityDebtId && b.id != priorityDebtId) return -1;
      if (b.id == priorityDebtId && a.id != priorityDebtId) return 1;
    }
    return strategy == Strategy.snowball
        ? bal[a.id]!.compareTo(bal[b.id]!)
        : (b.apr != a.apr ? b.apr.compareTo(a.apr) : bal[a.id]!.compareTo(bal[b.id]!));
  }

  PlanResult finish(int months, bool never) => PlanResult(
      months: months,
      interest: interest,
      never: never,
      steps: steps,
      totals: totals,
      firstMonthExtra: firstExtra,
      schedule: schedule);

  for (var m = 1; m <= _maxMonths; m++) {
    final active = debts.where((d) => !cleared.contains(d.id)).toList();
    final paidNow = <String, double>{};
    var interestNow = 0.0;
    for (final d in active) {
      final i = bal[d.id]! * d.apr / 100 / 12;
      interestNow += i;
      bal[d.id] = bal[d.id]! + i;
    }
    interest += interestNow;

    final monthExtra = m == 1 ? (firstMonthExtra ?? extra) : extra;
    var left = rollover ? (m == 1 ? firstPool : pool) : 0.0;
    for (final d in active) {
      final pay = d.minPayment.clamp(0, bal[d.id]!).toDouble();
      bal[d.id] = bal[d.id]! - pay;
      paidNow[d.id] = pay;
      if (rollover) left -= pay;
    }
    if (!rollover && monthExtra > 0) left = monthExtra;

    String? targetId;
    if (strategy == Strategy.splitEvenly) {
      // Water-fill: split what's left evenly across every open debt. A debt
      // that needs less than an equal share just gets what it needs, and the
      // rest keeps being split across whoever is still open.
      var pool2 = left;
      var pending = List<CoachDebt>.from(active);
      while (pool2 > 0.005 && pending.isNotEmpty) {
        final share = pool2 / pending.length;
        final settled = <String>{};
        for (final d in pending) {
          final need = bal[d.id]!;
          if (need <= share + 0.005 && need > 0) {
            paidNow[d.id] = (paidNow[d.id] ?? 0) + need;
            if (m == 1) firstExtra[d.id] = (firstExtra[d.id] ?? 0) + need;
            bal[d.id] = 0;
            pool2 -= need;
            settled.add(d.id);
          }
        }
        if (settled.isEmpty) {
          for (final d in pending) {
            bal[d.id] = bal[d.id]! - share;
            paidNow[d.id] = (paidNow[d.id] ?? 0) + share;
            if (m == 1) firstExtra[d.id] = (firstExtra[d.id] ?? 0) + share;
          }
          pool2 = 0;
        } else {
          pending = pending.where((d) => !settled.contains(d.id)).toList();
        }
      }
    } else {
      final ranked = [...active]..sort(byPriority);
      targetId = ranked.isEmpty ? null : ranked.first.id;
      for (final d in ranked) {
        if (left <= 0.005) break;
        final pay = left.clamp(0, bal[d.id]!).toDouble();
        if (pay <= 0) continue;
        bal[d.id] = bal[d.id]! - pay;
        paidNow[d.id] = (paidNow[d.id] ?? 0) + pay;
        left -= pay;
        if (m == 1) firstExtra[d.id] = (firstExtra[d.id] ?? 0) + pay;
      }
    }

    final clearedNow = <CoachDebt>[];
    for (final d in active) {
      if (bal[d.id]! <= 0.005) {
        bal[d.id] = 0;
        cleared.add(d.id);
        clearedNow.add(d);
        steps.add(PayoffStep(d, m));
      }
    }

    final total = bal.values.fold<double>(0, (a, v) => a + v);
    totals.add(total);
    schedule.add(PlanMonth(
      month: m,
      paid: paidNow,
      balance: Map.of(bal),
      interest: interestNow,
      cleared: clearedNow,
      targetId: targetId,
    ));
    if (cleared.length == debts.length) return finish(m, false);
    // A year with no progress means the payments never catch up with interest.
    if (m >= 12 && total >= totals[m - 12] - 0.01) return finish(m, true);
  }
  return finish(_maxMonths, true);
}

/// A stretch of months where the extra money goes to the same debt.
class PlanPhase {
  const PlanPhase({
    required this.firstMonth,
    required this.lastMonth,
    required this.target,
    required this.targetPayment,
    required this.others,
    required this.clearsAtEnd,
    required this.nextTarget,
  });

  final int firstMonth;
  final int lastMonth;
  final CoachDebt target;

  /// What is paid to [target] each month at the start of the phase.
  final double targetPayment;

  /// Other debts still open during the phase, which get only their minimums.
  final List<CoachDebt> others;

  /// True when [target] is paid off in the last month of the phase.
  final bool clearsAtEnd;

  /// The debt that takes over the extra money afterwards, if any.
  final CoachDebt? nextTarget;

  int get length => lastMonth - firstMonth + 1;
}

/// Groups a plan's months into phases, one per debt that gets the extra money.
List<PlanPhase> planPhases(PlanResult r, List<CoachDebt> debts) {
  final byId = {for (final d in debts) d.id: d};
  final phases = <PlanPhase>[];
  final done = <String>{};
  var i = 0;
  while (i < r.schedule.length) {
    final first = r.schedule[i];
    final id = first.targetId;
    if (id == null) break;
    var j = i;
    while (j + 1 < r.schedule.length && r.schedule[j + 1].targetId == id) {
      j++;
    }
    final last = r.schedule[j];
    final target = byId[id]!;
    final open = debts.where((d) => !done.contains(d.id) && d.id != id).toList();
    final next = j + 1 < r.schedule.length ? byId[r.schedule[j + 1].targetId] : null;
    phases.add(PlanPhase(
      firstMonth: first.month,
      lastMonth: last.month,
      target: target,
      targetPayment: first.paid[id] ?? 0,
      others: open,
      clearsAtEnd: last.cleared.any((d) => d.id == id),
      nextTarget: next,
    ));
    for (final d in last.cleared) {
      done.add(d.id);
    }
    i = j + 1;
  }
  return phases;
}

/// The full picture the coach screen shows.
class CoachPlan {
  const CoachPlan({
    required this.budget,
    required this.debts,
    required this.baseline,
    required this.avalanche,
    required this.snowball,
    required this.custom,
    required this.splitEvenly,
    required this.priorityDebtId,
  });

  final CoachBudget budget;
  final List<CoachDebt> debts;

  /// What happens if nothing changes: each debt keeps only its own payment.
  final PlanResult baseline;
  final PlanResult avalanche;
  final PlanResult snowball;

  /// A debt the user chose to prioritize first (see [priorityDebtId]); if
  /// none has been chosen yet, this is the same as [avalanche].
  final PlanResult custom;

  /// The extra money split evenly across every open debt at once.
  final PlanResult splitEvenly;

  /// The debt behind [custom], if one has been chosen.
  final String? priorityDebtId;

  PlanResult of(Strategy s) => switch (s) {
        Strategy.avalanche => avalanche,
        Strategy.snowball => snowball,
        Strategy.custom => custom,
        Strategy.splitEvenly => splitEvenly,
      };

  /// The cheaper of the two automatic orders. Ties go to highest interest
  /// first. This is the baseline "you could pay less" is measured against;
  /// [custom] and [splitEvenly] are the user's own choice, not candidates.
  Strategy get recommended =>
      snowball.interest < avalanche.interest - 0.5 ? Strategy.snowball : Strategy.avalanche;

  PlanResult get best => of(recommended);

  bool get hasDebts => debts.isNotEmpty;
  bool get anyRateMissing => debts.any((d) => d.rateMissing);
  bool get anyMinEstimated => debts.any((d) => d.minEstimated);
}

CoachPlan buildCoachPlan(
  BudgetState s,
  DateTime month, {
  int? intensity,
  double? buffer,
  String? priorityDebtId,
}) {
  final debts = coachDebts(s, month);
  final budget = coachBudget(s, month, intensity: intensity, buffer: buffer);
  return CoachPlan(
    budget: budget,
    debts: debts,
    baseline: simulatePlan(debts, extra: 0, rollover: false),
    avalanche: simulatePlan(debts,
        extra: budget.steadyExtra, firstMonthExtra: budget.extra, strategy: Strategy.avalanche),
    snowball: simulatePlan(debts,
        extra: budget.steadyExtra, firstMonthExtra: budget.extra, strategy: Strategy.snowball),
    custom: simulatePlan(debts,
        extra: budget.steadyExtra,
        firstMonthExtra: budget.extra,
        strategy: Strategy.custom,
        priorityDebtId: priorityDebtId),
    splitEvenly: simulatePlan(debts,
        extra: budget.steadyExtra, firstMonthExtra: budget.extra, strategy: Strategy.splitEvenly),
    priorityDebtId: priorityDebtId,
  );
}
