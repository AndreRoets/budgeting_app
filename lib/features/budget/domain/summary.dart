
import 'models.dart';
import 'period.dart';

/// True when [t] was charged to a credit card, so it becomes debt instead of
/// coming out of income.
bool onCreditCard(BudgetState s, Txn t) =>
    t.cardId != null && s.cards.any((c) => c.id == t.cardId && c.isCredit);

class CategoryTotals {
  const CategoryTotals({
    required this.category,
    required this.fixed,
    required this.spent,
    this.creditSpent = 0,
  });

  final Category category;

  /// Recurring bills/debt payments in this category for the month.
  final double fixed;

  /// Day-to-day spending logged this month, whatever it was paid with.
  final double spent;

  /// The part of [spent] that was charged to credit cards.
  final double creditSpent;

  double get budget => category.budget;
  double get remaining => budget - spent;

  /// Bills plus everything spent, including on credit.
  double get total => fixed + spent;

  /// Bills plus the spending that really came out of income.
  double get fromIncome => fixed + spent - creditSpent;
}

class MonthSummary {
  const MonthSummary({
    required this.income,
    required this.incomeReceived,
    required this.billsTotal,
    required this.debtTotal,
    required this.billsPaid,
    required this.spent,
    required this.budgeted,
    required this.categories,
    this.creditSpent = 0,
    this.cardPayments = 0,
    this.adjustment = 0,
    this.oneOffIncome = 0,
    this.carriedOver = 0,
  });

  final double income;

  /// The part of [income] that is one-time money, like a gift.
  final double oneOffIncome;

  /// Left over (or, when negative, overspent) in earlier periods and rolled
  /// into this one. See [carriedInto].
  final double carriedOver;

  /// Income that comes in every period.
  double get regularIncome => income - oneOffIncome;

  /// All the money this period has to work with.
  double get available => income + carriedOver;

  /// Part of [income] the user has marked as received this month.
  final double incomeReceived;
  final double billsTotal;
  final double debtTotal;
  final double billsPaid;

  /// Everything bought this month, including on credit cards.
  final double spent;

  /// The part of [spent] charged to credit cards. It adds to debt and does not
  /// come out of income.
  final double creditSpent;

  /// Money paid towards credit cards this month, which does come out of income.
  final double cardPayments;

  /// Sum of category spending budgets.
  final double budgeted;
  final List<CategoryTotals> categories;

  /// Manual correction to [left] for a period that had already started before
  /// everything was entered. See [BudgetState.leftAdjustments].
  final double adjustment;

  double get committed => billsTotal + debtTotal;

  /// Spending paid from income (cash or debit), without credit card purchases.
  double get cashSpent => spent - creditSpent;

  /// Everything that left income this month apart from bills: cash spending
  /// plus payments made to credit cards.
  double get fromIncome => cashSpent + cardPayments;

  /// What is actually still available: income and anything carried over,
  /// minus commitments and the money that has really come out of it, plus any
  /// manual correction.
  double get left => available - committed - fromIncome + adjustment;

  /// Income not yet assigned to any bill, debt or spending budget.
  double get unallocated => income - committed - budgeted;

  double get billsOutstanding => committed - billsPaid;
}

double _incomeIn(BudgetState s, DateTime month) =>
    s.allIncomes.fold<double>(0, (a, i) => a + i.amountIn(month));

double _committedIn(BudgetState s, DateTime month) =>
    s.allBills.fold<double>(0, (a, b) => a + b.amountIn(month));

/// What was left over (negative when overspent) across every period from
/// [BudgetState.carryOverFrom] up to, but not including, [month].
double carriedInto(BudgetState s, DateTime month) {
  final from = s.carryOverFrom;
  if (!s.carryOver || from == null) return 0;
  final first = DateTime.parse('$from-01');
  if (!first.isBefore(month)) return 0;
  var total = 0.0;
  for (var m = first; m.isBefore(month); m = DateTime(m.year, m.month + 1)) {
    total += _incomeIn(s, m) - _committedIn(s, m) + s.leftAdjustmentFor(m);
  }
  // Money that left income in those periods: see [MonthSummary.fromIncome].
  final start = s.periodStart(first), end = s.periodStart(month);
  for (final t in s.txns) {
    final day = DateTime(t.date.year, t.date.month, t.date.day);
    if (day.isBefore(start) || !day.isBefore(end)) continue;
    if (t.isPayment == onCreditCard(s, t)) total -= t.amount;
  }
  return total;
}

MonthSummary summarize(BudgetState s, DateTime month) {
  final income = _incomeIn(s, month);

  var bills = 0.0, debt = 0.0, paid = 0.0;
  for (final b in s.allBills) {
    final amount = b.amountIn(month);
    if (b.isDebt) {
      debt += amount;
    } else {
      bills += amount;
    }
    final rec = s.paidRecord(b, month);
    if (rec != null) paid += rec.amount ?? amount;
  }

  final all = txnsInMonth(s, month);
  final monthTxns = all.where((t) => !t.isPayment).toList();
  final spent = monthTxns.fold<double>(0, (a, t) => a + t.amount);
  final creditTxns = monthTxns.where((t) => onCreditCard(s, t)).toList();
  final creditSpent = creditTxns.fold<double>(0, (a, t) => a + t.amount);
  final cardPayments = all
      .where((t) => t.isPayment && onCreditCard(s, t))
      .fold<double>(0, (a, t) => a + t.amount);

  double inCategory(Iterable<Txn> txns, String id) => txns
      .expand((t) => t.parts)
      .where((p) => p.categoryId == id)
      .fold<double>(0, (a, p) => a + p.amount);

  final cats = [
    for (final c in s.categories)
      CategoryTotals(
        category: c,
        fixed: s.allBills
            .where((b) => b.categoryId == c.id)
            .fold<double>(0, (a, b) => a + b.amountIn(month)),
        spent: inCategory(monthTxns, c.id),
        creditSpent: inCategory(creditTxns, c.id),
      ),
  ];

  return MonthSummary(
    income: income,
    oneOffIncome: s.incomes
        .where((i) => i.oneOffMonth != null)
        .fold<double>(0, (a, i) => a + i.amountIn(month)),
    carriedOver: carriedInto(s, month),
    incomeReceived: s.allIncomes
        .where((i) => s.receivedOn(i, month) != null)
        .fold<double>(0, (a, i) => a + i.amountIn(month)),
    billsTotal: bills,
    debtTotal: debt,
    billsPaid: paid,
    spent: spent,
    creditSpent: creditSpent,
    cardPayments: cardPayments,
    adjustment: s.leftAdjustmentFor(month),
    budgeted: s.categories.fold<double>(0, (a, c) => a + c.budget),
    categories: cats,
  );
}

List<Txn> txnsInMonth(BudgetState s, DateTime month) => s.txns
    .where((t) => s.inPeriodOf(month, t.date))
    .toList()
  ..sort((a, b) => b.date.compareTo(a.date));

class CardSummary {
  const CardSummary({
    required this.card,
    required this.usedThisMonth,
    required this.owed,
  });

  final PaymentCard card;
  final double usedThisMonth;

  /// Opening balance + all purchases − all payments (credit cards only).
  final double owed;

  double get available => card.limit - owed;
  double get utilisation =>
      card.limit <= 0 ? 0 : (owed / card.limit).clamp(0.0, 1.0);
}

CardSummary summarizeCard(BudgetState s, PaymentCard card, DateTime month) {
  var owed = card.openingBalance;
  var used = 0.0;
  for (final t in s.txns.where((t) => t.cardId == card.id)) {
    owed += t.isPayment ? -t.amount : t.amount;
    if (!t.isPayment && s.inPeriodOf(month, t.date)) {
      used += t.amount;
    }
  }
  return CardSummary(card: card, usedThisMonth: used, owed: owed);
}

class DebtTotals {
  const DebtTotals({required this.loans, required this.cards});

  /// Remaining balance across debts that have a "total owed" entered.
  final double loans;

  /// Owed on credit cards.
  final double cards;

  double get total => loans + cards;
}

DebtTotals totalDebt(BudgetState s, DateTime month) => DebtTotals(
      loans: s.bills
          .where((b) => b.isDebt)
          .fold<double>(0, (a, b) => a + (b.debtBalance ?? 0)),
      cards: s.cards
          .where((c) => c.isCredit)
          .fold<double>(0, (a, c) => a + summarizeCard(s, c, month).owed),
    );


class Pace {
  const Pace({required this.perDay, required this.perWeek, required this.days});
  final double perDay;
  final double perWeek;
  final int days;
}

/// What can be spent per day/week to make [left] last the rest of the period.
Pace? paceFor(BudgetState s, double left, DateTime month, DateTime now) {
  final days = daysLeftInPeriod(s.startDay, month, now);
  if (days == null || days <= 0) return null;
  final perDay = left > 0 ? left / days : 0.0;
  return Pace(perDay: perDay, perWeek: perDay * 7, days: days);
}

class MonthTrend {
  const MonthTrend({
    required this.month,
    required this.income,
    required this.committed,
    required this.spent,
  });

  final DateTime month;
  final double income;

  /// Bills and debt payments, as they were in that month.
  final double committed;
  final double spent;

  double get out => committed + spent;
  double get net => income - out;
}

/// The [count] months ending at [end], oldest first.
List<MonthTrend> monthlyTrend(BudgetState s, DateTime end, {int count = 6}) => [
      for (var i = count - 1; i >= 0; i--)
        () {
          final m = DateTime(end.year, end.month - i);
          final sum = summarize(s, m);
          return MonthTrend(
            month: m,
            income: sum.income,
            committed: sum.committed,
            // Money that left income: cash spending plus card payments. Credit
            // card purchases are debt, so they only count once they are paid.
            spent: sum.fromIncome,
          );
        }(),
    ];

class CategoryChange {
  const CategoryChange(this.category, this.current, this.previous);
  final Category category;
  final double current;
  final double previous;

  double get delta => current - previous;

  /// Percent change, or null when there was nothing last month to compare to.
  double? get percent => previous <= 0 ? null : delta / previous * 100;
}

/// Day-to-day spending per category for [month] against the month before,
/// biggest movers first. Categories with no spending in either are left out.
List<CategoryChange> categoryChanges(BudgetState s, DateTime month) {
  final cur = summarize(s, month).categories;
  final prev = summarize(s, DateTime(month.year, month.month - 1)).categories;
  final out = [
    for (var i = 0; i < cur.length; i++)
      CategoryChange(
        cur[i].category,
        cur[i].spent,
        prev.where((p) => p.category.id == cur[i].category.id).firstOrNull?.spent ?? 0,
      ),
  ].where((c) => c.current > 0 || c.previous > 0).toList()
    ..sort((a, b) => b.delta.abs().compareTo(a.delta.abs()));
  return out;
}

/// Filters purchases (never card payments). [month] null searches all time.
/// [query] matches the note, category names, card name or amount.
List<Txn> filterTxns(
  BudgetState s, {
  DateTime? month,
  String query = '',
  String? categoryId,
  String? cardId,
  bool cashOnly = false,
}) {
  final q = query.trim().toLowerCase().replaceAll(',', '');
  bool matches(Txn t) {
    if (t.isPayment) return false;
    if (month != null && !s.inPeriodOf(month, t.date)) {
      return false;
    }
    if (categoryId != null && !t.parts.any((p) => p.categoryId == categoryId)) {
      return false;
    }
    if (cashOnly && t.cardId != null) return false;
    if (cardId != null && t.cardId != cardId) return false;
    if (q.isEmpty) return true;
    final hay = [
      t.note,
      for (final p in t.parts) s.category(p.categoryId).name,
      s.cards.where((c) => c.id == t.cardId).firstOrNull?.name ?? '',
      t.amount.toStringAsFixed(2),
    ].join(' ').toLowerCase();
    return hay.contains(q);
  }

  return s.txns.where(matches).toList()..sort((a, b) => b.date.compareTo(a.date));
}
