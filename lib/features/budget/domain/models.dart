import 'package:flutter/material.dart';

/// Icons a category can use. Stored by index so persisted data stays stable.
const kCategoryIcons = <IconData>[
  Icons.home_rounded,
  Icons.bolt_rounded,
  Icons.shopping_cart_rounded,
  Icons.directions_car_rounded,
  Icons.shield_rounded,
  Icons.account_balance_rounded,
  Icons.favorite_rounded,
  Icons.movie_rounded,
  Icons.restaurant_rounded,
  Icons.savings_rounded,
  Icons.category_rounded,
  Icons.school_rounded,
  Icons.pets_rounded,
  Icons.flight_rounded,
  Icons.child_care_rounded,
  Icons.phone_iphone_rounded,
  Icons.checkroom_rounded,
  Icons.fitness_center_rounded,
  Icons.local_cafe_rounded,
  Icons.shopping_bag_rounded,
  Icons.card_giftcard_rounded,
];

const kCategoryColors = <Color>[
  Color(0xFF3F8EFC),
  Color(0xFFF4B942),
  Color(0xFF2EC4B6),
  Color(0xFF8E6CEF),
  Color(0xFFEF6C6C),
  Color(0xFFE07A5F),
  Color(0xFF5DBB63),
  Color(0xFFEC6FB3),
  Color(0xFFFF9F45),
  Color(0xFF26A69A),
  Color(0xFF90A4AE),
  Color(0xFF5C6BC0),
];

const otherCategoryId = 'other';

String newId() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);

/// "yyyy-MM" key for a month.
String monthKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

class Category {
  const Category({
    required this.id,
    required this.name,
    required this.iconIndex,
    required this.colorIndex,
    this.budget = 0,
  });

  final String id;
  final String name;
  final int iconIndex;
  final int colorIndex;

  /// Monthly limit for day-to-day spending in this category.
  final double budget;

  IconData get icon => kCategoryIcons[iconIndex % kCategoryIcons.length];
  Color get color => kCategoryColors[colorIndex % kCategoryColors.length];

  Category copyWith({
    String? name,
    int? iconIndex,
    int? colorIndex,
    double? budget,
  }) =>
      Category(
        id: id,
        name: name ?? this.name,
        iconIndex: iconIndex ?? this.iconIndex,
        colorIndex: colorIndex ?? this.colorIndex,
        budget: budget ?? this.budget,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'icon': iconIndex,
        'color': colorIndex,
        'budget': budget,
      };

  factory Category.fromJson(Map<String, dynamic> j) => Category(
        id: j['id'] as String,
        name: j['name'] as String,
        iconIndex: j['icon'] as int,
        colorIndex: j['color'] as int,
        budget: (j['budget'] as num).toDouble(),
      );
}

/// A recurring monthly commitment: a bill/expense, or a debt repayment.
class Bill {
  const Bill({
    required this.id,
    required this.name,
    required this.amount,
    required this.categoryId,
    this.isDebt = false,
    this.dueDay,
    this.debtBalance,
    this.interestRate,
    this.isCoachExtra = false,
    this.coachTargetId,
    this.coachTargetIsCard = false,
  });

  final String id;
  final String name;
  final double amount;
  final String categoryId;
  final bool isDebt;

  /// Day of month (1-31) the payment is due.
  final int? dueDay;

  /// Total still owed, for debts.
  final double? debtBalance;

  /// Yearly interest rate in percent, for debts (used by the payoff planner).
  final double? interestRate;

  /// True for the single recurring bill created by confirming a Debt Coach
  /// plan - its amount and target are kept in sync with the live plan rather
  /// than edited by hand like a normal bill.
  final bool isCoachExtra;

  /// The debt (bill or card) this bill's payments are actually applied to,
  /// for [isCoachExtra] bills.
  final String? coachTargetId;
  final bool coachTargetIsCard;

  Bill copyWith({
    double? debtBalance,
    String? categoryId,
    double? amount,
    String? name,
    String? coachTargetId,
    bool? coachTargetIsCard,
  }) =>
      Bill(
        id: id,
        name: name ?? this.name,
        amount: amount ?? this.amount,
        categoryId: categoryId ?? this.categoryId,
        isDebt: isDebt,
        dueDay: dueDay,
        debtBalance: debtBalance ?? this.debtBalance,
        interestRate: interestRate,
        isCoachExtra: isCoachExtra,
        coachTargetId: coachTargetId ?? this.coachTargetId,
        coachTargetIsCard: coachTargetIsCard ?? this.coachTargetIsCard,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'amount': amount,
        'categoryId': categoryId,
        'isDebt': isDebt,
        'dueDay': dueDay,
        'debtBalance': debtBalance,
        'interestRate': interestRate,
        'isCoachExtra': isCoachExtra,
        'coachTargetId': coachTargetId,
        'coachTargetIsCard': coachTargetIsCard,
      };

  factory Bill.fromJson(Map<String, dynamic> j) => Bill(
        id: j['id'] as String,
        name: j['name'] as String,
        amount: (j['amount'] as num).toDouble(),
        categoryId: j['categoryId'] as String,
        isDebt: j['isDebt'] as bool,
        dueDay: j['dueDay'] as int?,
        debtBalance: (j['debtBalance'] as num?)?.toDouble(),
        interestRate: (j['interestRate'] as num?)?.toDouble(),
        isCoachExtra: j['isCoachExtra'] as bool? ?? false,
        coachTargetId: j['coachTargetId'] as String?,
        coachTargetIsCard: j['coachTargetIsCard'] as bool? ?? false,
      );
}

class Income {
  const Income({
    required this.id,
    required this.name,
    required this.amount,
    this.oneOffMonth,
    this.payDay,
  });

  final String id;
  final String name;
  final double amount;

  /// "yyyy-MM" when this is a one-time payment; null means every month.
  final String? oneOffMonth;

  /// Day of month (1-31) this income normally arrives.
  final int? payDay;

  bool appliesTo(DateTime month) =>
      oneOffMonth == null || oneOffMonth == monthKey(month);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'amount': amount,
        'oneOffMonth': oneOffMonth,
        'payDay': payDay,
      };

  factory Income.fromJson(Map<String, dynamic> j) => Income(
        id: j['id'] as String,
        name: j['name'] as String,
        amount: (j['amount'] as num).toDouble(),
        oneOffMonth: j['oneOffMonth'] as String?,
        payDay: j['payDay'] as int?,
      );
}

class PaymentCard {
  const PaymentCard({
    required this.id,
    required this.name,
    required this.colorIndex,
    this.isCredit = true,
    this.limit = 0,
    this.openingBalance = 0,
    this.interestRate = 0,
    this.minPayment = 0,
  });

  final String id;
  final String name;
  final int colorIndex;

  /// Credit cards accrue a balance owed; debit/extra cards just track use.
  final bool isCredit;
  final double limit;

  /// Amount already owed when the card was added.
  final double openingBalance;

  /// Yearly interest rate in percent (0 = not entered).
  final double interestRate;

  /// Smallest amount that must be paid each month (0 = not entered).
  final double minPayment;

  Color get color => kCategoryColors[colorIndex % kCategoryColors.length];

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'color': colorIndex,
        'isCredit': isCredit,
        'limit': limit,
        'openingBalance': openingBalance,
        'interestRate': interestRate,
        'minPayment': minPayment,
      };

  factory PaymentCard.fromJson(Map<String, dynamic> j) => PaymentCard(
        id: j['id'] as String,
        name: j['name'] as String,
        colorIndex: j['color'] as int,
        isCredit: j['isCredit'] as bool,
        limit: (j['limit'] as num).toDouble(),
        openingBalance: (j['openingBalance'] as num).toDouble(),
        interestRate: (j['interestRate'] as num?)?.toDouble() ?? 0,
        minPayment: (j['minPayment'] as num?)?.toDouble() ?? 0,
      );
}

/// One category's share of a purchase.
class SplitPart {
  const SplitPart(this.categoryId, this.amount);
  final String categoryId;
  final double amount;

  Map<String, dynamic> toJson() => {'categoryId': categoryId, 'amount': amount};
  factory SplitPart.fromJson(Map<String, dynamic> j) =>
      SplitPart(j['categoryId'] as String, (j['amount'] as num).toDouble());
}

/// A purchase, or (when [isPayment]) a payment made towards a card balance.
class Txn {
  const Txn({
    required this.id,
    required this.date,
    required this.amount,
    this.categoryId = otherCategoryId,
    this.cardId,
    this.note = '',
    this.isPayment = false,
    this.splits = const [],
    this.debtId,
  });

  final String id;
  final DateTime date;
  final double amount;

  /// Set when this spending is an extra payment towards a debt.
  final String? debtId;

  /// Main category (the first split when the purchase is split).
  final String categoryId;
  final String? cardId;
  final String note;
  final bool isPayment;

  /// When non-empty, how [amount] is divided between categories (sums to it).
  final List<SplitPart> splits;

  bool get isSplit => splits.length > 1;

  /// How this purchase is attributed to categories.
  List<SplitPart> get parts =>
      splits.isEmpty ? [SplitPart(categoryId, amount)] : splits;

  /// This purchase with [id] replaced by 'Other' in its category and splits.
  Txn withoutCategory(String id) => Txn(
        id: this.id,
        date: date,
        amount: amount,
        categoryId: categoryId == id ? otherCategoryId : categoryId,
        cardId: cardId,
        note: note,
        isPayment: isPayment,
        debtId: debtId,
        splits: [
          for (final p in splits)
            SplitPart(p.categoryId == id ? otherCategoryId : p.categoryId, p.amount),
        ],
      );

  Txn copyWith({String? categoryId, bool clearCard = false}) => Txn(
        id: id,
        date: date,
        amount: amount,
        categoryId: categoryId ?? this.categoryId,
        cardId: clearCard ? null : cardId,
        note: note,
        isPayment: isPayment,
        splits: splits,
        debtId: debtId,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'amount': amount,
        'categoryId': categoryId,
        'cardId': cardId,
        'note': note,
        'isPayment': isPayment,
        'debtId': debtId,
        'splits': splits.map((e) => e.toJson()).toList(),
      };

  factory Txn.fromJson(Map<String, dynamic> j) => Txn(
        id: j['id'] as String,
        date: DateTime.parse(j['date'] as String),
        amount: (j['amount'] as num).toDouble(),
        categoryId: j['categoryId'] as String,
        cardId: j['cardId'] as String?,
        note: j['note'] as String,
        isPayment: j['isPayment'] as bool,
        debtId: j['debtId'] as String?,
        splits: [
          for (final e in (j['splits'] as List? ?? const []))
            SplitPart.fromJson(Map<String, dynamic>.from(e as Map)),
        ],
      );
}

enum Repeat { daily, weekly, monthly }

/// Spending that repeats and is logged automatically (e.g. a daily coffee).
class RecurringSpend {
  const RecurringSpend({
    required this.id,
    required this.amount,
    required this.repeat,
    required this.start,
    this.categoryId = otherCategoryId,
    this.cardId,
    this.note = '',
    this.through,
    this.active = true,
  });

  final String id;
  final double amount;
  final Repeat repeat;

  /// First occurrence. Weekly repeats keep this weekday, monthly this day.
  final DateTime start;
  final String categoryId;
  final String? cardId;
  final String note;

  /// Last day already turned into transactions (null = nothing yet).
  final DateTime? through;
  final bool active;

  RecurringSpend copyWith({
    DateTime? through,
    bool? active,
    String? categoryId,
    bool clearCard = false,
  }) =>
      RecurringSpend(
        id: id,
        amount: amount,
        repeat: repeat,
        start: start,
        categoryId: categoryId ?? this.categoryId,
        cardId: clearCard ? null : cardId,
        note: note,
        through: through ?? this.through,
        active: active ?? this.active,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'amount': amount,
        'repeat': repeat.name,
        'start': start.toIso8601String(),
        'categoryId': categoryId,
        'cardId': cardId,
        'note': note,
        'through': through?.toIso8601String(),
        'active': active,
      };

  factory RecurringSpend.fromJson(Map<String, dynamic> j) => RecurringSpend(
        id: j['id'] as String,
        amount: (j['amount'] as num).toDouble(),
        repeat: Repeat.values.byName(j['repeat'] as String),
        start: DateTime.parse(j['start'] as String),
        categoryId: j['categoryId'] as String,
        cardId: j['cardId'] as String?,
        note: j['note'] as String,
        through: j['through'] == null ? null : DateTime.parse(j['through'] as String),
        active: j['active'] as bool,
      );
}

class Goal {
  const Goal({
    required this.id,
    required this.name,
    required this.target,
    this.saved = 0,
    this.deadline,
    this.colorIndex = 9,
  });

  final String id;
  final String name;
  final double target;
  final double saved;

  /// Month the goal should be reached by (any day within it).
  final DateTime? deadline;
  final int colorIndex;

  Color get color => kCategoryColors[colorIndex % kCategoryColors.length];
  double get remaining => (target - saved).clamp(0, double.infinity);
  double get progress => target <= 0 ? 0 : (saved / target).clamp(0.0, 1.0);
  bool get reached => saved >= target;

  Goal copyWith({double? saved}) => Goal(
        id: id,
        name: name,
        target: target,
        saved: saved ?? this.saved,
        deadline: deadline,
        colorIndex: colorIndex,
      );

  /// Amount to set aside each month, counting this month, to hit the deadline.
  double? monthlyNeeded(DateTime now) {
    if (deadline == null || reached) return null;
    final months =
        (deadline!.year - now.year) * 12 + deadline!.month - now.month + 1;
    return months <= 0 ? remaining : remaining / months;
  }

  /// True when the target month has passed without the goal being reached.
  bool isOverdue(DateTime now) =>
      deadline != null &&
      !reached &&
      DateTime(deadline!.year, deadline!.month + 1).isBefore(now);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'target': target,
        'saved': saved,
        'deadline': deadline?.toIso8601String(),
        'color': colorIndex,
      };

  factory Goal.fromJson(Map<String, dynamic> j) => Goal(
        id: j['id'] as String,
        name: j['name'] as String,
        target: (j['target'] as num).toDouble(),
        saved: (j['saved'] as num).toDouble(),
        deadline:
            j['deadline'] == null ? null : DateTime.parse(j['deadline'] as String),
        colorIndex: j['color'] as int,
      );
}

/// Total that should be set aside this period across savings goals that are
/// on track. A reached goal needs nothing; an overdue one needs a one-off
/// catch-up instead of a steady monthly amount, so it is left out here too
/// (see [Goal.isOverdue]) - the goals screen prompts for a new date instead.
double goalsSavingsNeeded(List<Goal> goals, DateTime period, DateTime now) => goals
    .where((g) => !g.isOverdue(now))
    .map((g) => g.monthlyNeeded(period))
    .whereType<double>()
    .fold(0.0, (a, v) => a + v);

const _unset = Object();

/// A bill or debt payment the user has recorded for one month.
class PaidRecord {
  const PaidRecord({this.date, this.amount, this.reduced = 0});

  /// When it was paid (null for records made before dates were tracked).
  final DateTime? date;

  /// Amount actually paid; null means the bill's usual amount.
  final double? amount;

  /// How much this payment took off a debt's remaining balance, so that
  /// undoing it can put the same amount back.
  final double reduced;

  Map<String, dynamic> toJson() => {
        'date': date?.toIso8601String(),
        'amount': amount,
        'reduced': reduced,
      };

  factory PaidRecord.fromJson(Map<String, dynamic> j) => PaidRecord(
        date: j['date'] == null ? null : DateTime.parse(j['date'] as String),
        amount: (j['amount'] as num?)?.toDouble(),
        reduced: (j['reduced'] as num?)?.toDouble() ?? 0,
      );
}

abstract final class PaceMode {
  static const off = 0;
  static const day = 1;
  static const week = 2;
  static const both = 3;
}

class BudgetState {
  const BudgetState({
    this.categories = const [],
    this.bills = const [],
    this.incomes = const [],
    this.cards = const [],
    this.txns = const [],
    this.paid = const {},
    this.received = const {},
    this.recurring = const [],
    this.goals = const [],
    this.currency = r'$',
    this.focusCategoryId,
    this.paceMode = PaceMode.both,
    this.themeMode = 0,
    this.coachIntensity = 1,
    this.coachBuffer,
    this.periodStartDay = 0,
    this.leftAdjustments = const {},
    this.coachStrategy = -1,
    this.coachPriorityDebtId,
  });

  final List<Category> categories;
  final List<Bill> bills;
  final List<Income> incomes;
  final List<PaymentCard> cards;
  final List<Txn> txns;

  /// Payments recorded per month, keyed "yyyy-MM|billId".
  final Map<String, PaidRecord> paid;

  /// When income arrived, keyed "yyyy-MM|incomeId".
  final Map<String, DateTime> received;
  final List<RecurringSpend> recurring;
  final List<Goal> goals;
  final String currency;

  /// Category whose spending is highlighted on the overview (null = all spending).
  final String? focusCategoryId;

  /// Whether the overview shows a per-day and/or per-week allowance.
  final int paceMode;

  /// 0 = follow the phone, 1 = always light, 2 = always dark.
  final int themeMode;

  /// Debt coach: 0 = gentle, 1 = balanced, 2 = all-in.
  final int coachIntensity;

  /// Debt coach: backup money kept aside each month (null = use the default).
  final double? coachBuffer;

  /// Day of the month each budget period starts on (1-31). 0 follows the pay
  /// day of the main income; see [PeriodX.startDay].
  final int periodStartDay;

  /// Manual correction to "left to spend" for a period, keyed "yyyy-MM", for
  /// when a period has already started and entering everything that's
  /// happened so far isn't worth the effort. It is a delta on top of what's
  /// calculated, not a fixed value, so it keeps applying as more is logged.
  final Map<String, double> leftAdjustments;

  /// Debt coach: which order to pay debts off in. -1 = the cheapest of
  /// highest-interest-first or smallest-balance-first (whichever wins);
  /// 0 = highest interest first; 1 = smallest balance first; 2 = a debt the
  /// user picked first ([coachPriorityDebtId]); 3 = split evenly across all.
  final int coachStrategy;

  /// Debt coach: the debt to prioritize first when [coachStrategy] is 2.
  final String? coachPriorityDebtId;

  Category category(String id) => categories.firstWhere(
        (c) => c.id == id,
        orElse: () => categories.firstWhere((c) => c.id == otherCategoryId),
      );

  PaidRecord? paidRecord(Bill b, DateTime month) => paid['${monthKey(month)}|${b.id}'];
  bool isPaid(Bill b, DateTime month) => paidRecord(b, month) != null;

  DateTime? receivedOn(Income i, DateTime month) => received['${monthKey(month)}|${i.id}'];

  double leftAdjustmentFor(DateTime period) => leftAdjustments[monthKey(period)] ?? 0;
  bool hasLeftAdjustment(DateTime period) => leftAdjustments.containsKey(monthKey(period));

  BudgetState copyWith({
    List<Category>? categories,
    List<Bill>? bills,
    List<Income>? incomes,
    List<PaymentCard>? cards,
    List<Txn>? txns,
    Map<String, PaidRecord>? paid,
    Map<String, DateTime>? received,
    List<RecurringSpend>? recurring,
    List<Goal>? goals,
    String? currency,
    Object? focusCategoryId = _unset,
    int? paceMode,
    int? themeMode,
    int? coachIntensity,
    double? coachBuffer,
    int? periodStartDay,
    Map<String, double>? leftAdjustments,
    int? coachStrategy,
    Object? coachPriorityDebtId = _unset,
  }) =>
      BudgetState(
        categories: categories ?? this.categories,
        bills: bills ?? this.bills,
        incomes: incomes ?? this.incomes,
        cards: cards ?? this.cards,
        txns: txns ?? this.txns,
        paid: paid ?? this.paid,
        received: received ?? this.received,
        recurring: recurring ?? this.recurring,
        goals: goals ?? this.goals,
        currency: currency ?? this.currency,
        focusCategoryId: identical(focusCategoryId, _unset)
            ? this.focusCategoryId
            : focusCategoryId as String?,
        paceMode: paceMode ?? this.paceMode,
        themeMode: themeMode ?? this.themeMode,
        coachIntensity: coachIntensity ?? this.coachIntensity,
        coachBuffer: coachBuffer ?? this.coachBuffer,
        periodStartDay: periodStartDay ?? this.periodStartDay,
        leftAdjustments: leftAdjustments ?? this.leftAdjustments,
        coachStrategy: coachStrategy ?? this.coachStrategy,
        coachPriorityDebtId: identical(coachPriorityDebtId, _unset)
            ? this.coachPriorityDebtId
            : coachPriorityDebtId as String?,
      );

  Map<String, dynamic> toJson() => {
        'categories': categories.map((e) => e.toJson()).toList(),
        'bills': bills.map((e) => e.toJson()).toList(),
        'incomes': incomes.map((e) => e.toJson()).toList(),
        'cards': cards.map((e) => e.toJson()).toList(),
        'txns': txns.map((e) => e.toJson()).toList(),
        'payments': paid.map((k, v) => MapEntry(k, v.toJson())),
        'received': received.map((k, v) => MapEntry(k, v.toIso8601String())),
        'recurring': recurring.map((e) => e.toJson()).toList(),
        'goals': goals.map((e) => e.toJson()).toList(),
        'currency': currency,
        'focusCategoryId': focusCategoryId,
        'paceMode': paceMode,
        'themeMode': themeMode,
        'coachIntensity': coachIntensity,
        'coachBuffer': coachBuffer,
        'periodStartDay': periodStartDay,
        'leftAdjustments': leftAdjustments,
        'coachStrategy': coachStrategy,
        'coachPriorityDebtId': coachPriorityDebtId,
      };

  factory BudgetState.fromJson(Map<String, dynamic> j) {
    List<T> list<T>(String k, T Function(Map<String, dynamic>) f) =>
        (j[k] as List).map((e) => f(e as Map<String, dynamic>)).toList();
    return BudgetState(
      categories: list('categories', Category.fromJson),
      bills: list('bills', Bill.fromJson),
      incomes: list('incomes', Income.fromJson),
      cards: list('cards', PaymentCard.fromJson),
      txns: list('txns', Txn.fromJson),
      paid: {
        // Older saves stored just a list of paid keys, with no date.
        for (final k in (j['paid'] as List? ?? const []).cast<String>())
          k: const PaidRecord(),
        for (final e in (j['payments'] as Map? ?? const {}).entries)
          e.key as String:
              PaidRecord.fromJson(Map<String, dynamic>.from(e.value as Map)),
      },
      recurring: [
        for (final e in (j['recurring'] as List? ?? const []))
          RecurringSpend.fromJson(Map<String, dynamic>.from(e as Map)),
      ],
      goals: [
        for (final e in (j['goals'] as List? ?? const []))
          Goal.fromJson(Map<String, dynamic>.from(e as Map)),
      ],
      received: {
        for (final e in (j['received'] as Map? ?? const {}).entries)
          e.key as String: DateTime.parse(e.value as String),
      },
      currency: j['currency'] as String,
      focusCategoryId: j['focusCategoryId'] as String?,
      paceMode: (j['paceMode'] as int?) ?? PaceMode.both,
      themeMode: (j['themeMode'] as int?) ?? 0,
      coachIntensity: (j['coachIntensity'] as int?) ?? 1,
      coachBuffer: (j['coachBuffer'] as num?)?.toDouble(),
      periodStartDay: (j['periodStartDay'] as int?) ?? 0,
      leftAdjustments: {
        for (final e in (j['leftAdjustments'] as Map? ?? const {}).entries)
          e.key as String: (e.value as num).toDouble(),
      },
      coachStrategy: (j['coachStrategy'] as int?) ?? -1,
      coachPriorityDebtId: j['coachPriorityDebtId'] as String?,
    );
  }

  factory BudgetState.initial() => const BudgetState(categories: [
        Category(id: 'housing', name: 'Housing', iconIndex: 0, colorIndex: 0),
        Category(id: 'utilities', name: 'Utilities', iconIndex: 1, colorIndex: 1),
        Category(id: 'groceries', name: 'Groceries', iconIndex: 2, colorIndex: 2),
        Category(id: 'transport', name: 'Transport', iconIndex: 3, colorIndex: 3),
        Category(id: 'insurance', name: 'Insurance', iconIndex: 4, colorIndex: 4),
        Category(id: 'debt', name: 'Debt', iconIndex: 5, colorIndex: 5),
        Category(id: 'health', name: 'Health', iconIndex: 6, colorIndex: 6),
        Category(id: 'fun', name: 'Entertainment', iconIndex: 7, colorIndex: 7),
        Category(id: 'eating', name: 'Eating Out', iconIndex: 8, colorIndex: 8),
        Category(id: 'savings', name: 'Savings', iconIndex: 9, colorIndex: 9),
        Category(id: 'coffee', name: 'Coffee', iconIndex: 18, colorIndex: 11),
        Category(id: 'extras', name: 'Extras', iconIndex: 19, colorIndex: 1),
        Category(id: otherCategoryId, name: 'Other', iconIndex: 10, colorIndex: 10),
      ]);
}
