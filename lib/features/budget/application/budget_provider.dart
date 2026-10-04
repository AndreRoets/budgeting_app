import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/coach.dart';
import '../domain/models.dart';
import '../domain/period.dart';
import '../domain/recurring.dart' as recurring_logic;

const _storageKey = 'budget_state_v1';
const _coachBillId = '__coach_extra__';
String _coachTxnId(DateTime month) => 'coach-pay-${monthKey(month)}';

/// Overridden in main() with the loaded instance.
final prefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('prefsProvider must be overridden'),
);

final budgetProvider =
    NotifierProvider<BudgetNotifier, BudgetState>(BudgetNotifier.new);

/// The pay period being looked at, named by the month it starts in. It goes
/// back to the current period whenever the start day changes.
class SelectedMonth extends Notifier<DateTime> {
  @override
  DateTime build() {
    final startDay = ref.watch(budgetProvider.select((s) => s.startDay));
    return periodKeyFor(startDay, DateTime.now());
  }

  void shift(int months) => state = DateTime(state.year, state.month + months);
  void reset() => state = ref.read(budgetProvider).currentPeriod;
}

final selectedMonthProvider =
    NotifierProvider<SelectedMonth, DateTime>(SelectedMonth.new);

List<T> _upsert<T>(List<T> list, T item, String Function(T) id) {
  final i = list.indexWhere((e) => id(e) == id(item));
  if (i < 0) return [...list, item];
  return [...list]..[i] = item;
}

class BudgetNotifier extends Notifier<BudgetState> {
  @override
  BudgetState build() {
    final prefs = ref.read(prefsProvider);
    final raw = prefs.getString(_storageKey);
    var loaded = BudgetState.initial();
    if (raw != null) {
      try {
        loaded = BudgetState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        // Corrupt data: fall through to a fresh state rather than crash.
      }
    }
    var current = _withRecurring(loaded, DateTime.now());
    current = _withCoachBillRefreshed(current, DateTime.now());
    if (!identical(current, loaded)) {
      prefs.setString(_storageKey, jsonEncode(current.toJson()));
    }
    return current;
  }

  void _set(BudgetState s) {
    state = s;
    ref.read(prefsProvider).setString(_storageKey, jsonEncode(s.toJson()));
  }

  // Categories
  void saveCategory(Category c) => _set(
      state.copyWith(categories: _upsert(state.categories, c, (e) => e.id)));

  /// Items in a deleted category move to "Other".
  void deleteCategory(String id) {
    if (id == otherCategoryId) return;
    _set(state.copyWith(
      categories: state.categories.where((c) => c.id != id).toList(),
      focusCategoryId: state.focusCategoryId == id ? null : state.focusCategoryId,
      bills: [
        for (final b in state.bills)
          b.categoryId == id ? b.copyWith(categoryId: otherCategoryId) : b,
      ],
      txns: [for (final t in state.txns) t.withoutCategory(id)],
      recurring: [
        for (final r in state.recurring)
          r.categoryId == id ? r.copyWith(categoryId: otherCategoryId) : r,
      ],
    ));
  }

  // Bills & debts
  void saveBill(Bill b) =>
      _set(state.copyWith(bills: _upsert(state.bills, b, (e) => e.id)));
  void deleteBill(String id) =>
      _set(state.copyWith(bills: state.bills.where((b) => b.id != id).toList()));


  /// Records a payment made on [date]. For a debt with a known balance,
  /// [reduceBalance] also takes the paid amount off what is still owed. For
  /// the confirmed Debt Coach bill, the payment is applied to whatever debt
  /// it is currently aimed at instead (see [coachTargetId]).
  void markBillPaid(
    Bill b,
    DateTime month, {
    required DateTime date,
    required double amount,
    bool reduceBalance = false,
  }) {
    final live = state.bills.where((e) => e.id == b.id).firstOrNull ?? b;
    final owed = live.debtBalance;
    final reduced =
        reduceBalance && b.isDebt && owed != null ? amount.clamp(0, owed).toDouble() : 0.0;
    var bills = reduced > 0
        ? _upsert(state.bills, live.copyWith(debtBalance: owed! - reduced), (e) => e.id)
        : state.bills;
    var txns = state.txns;
    if (live.isCoachExtra && live.coachTargetId != null) {
      if (live.coachTargetIsCard) {
        txns = [
          ...txns,
          Txn(
            id: _coachTxnId(month),
            date: date,
            amount: amount,
            categoryId: 'debt',
            cardId: live.coachTargetId,
            isPayment: true,
            note: live.name,
          ),
        ];
      } else {
        bills = _shiftDebt(bills, live.coachTargetId, -amount);
      }
    }
    _set(state.copyWith(
      paid: {
        ...state.paid,
        '${monthKey(month)}|${b.id}':
            PaidRecord(date: date, amount: amount, reduced: reduced),
      },
      bills: bills,
      txns: txns,
    ));
  }

  /// Undoes a recorded payment, restoring any balance it had reduced.
  void unmarkBillPaid(Bill b, DateTime month) {
    final key = '${monthKey(month)}|${b.id}';
    final rec = state.paid[key];
    if (rec == null) return;
    // Read the live bill: its balance may have changed since [b] was captured.
    final live = state.bills.where((e) => e.id == b.id).firstOrNull;
    var bills = rec.reduced > 0 && live != null
        ? _upsert(
            state.bills,
            live.copyWith(debtBalance: (live.debtBalance ?? 0) + rec.reduced),
            (e) => e.id)
        : state.bills;
    var txns = state.txns;
    if (live != null && live.isCoachExtra && live.coachTargetId != null) {
      if (live.coachTargetIsCard) {
        txns = txns.where((t) => t.id != _coachTxnId(month)).toList();
      } else {
        bills = _shiftDebt(bills, live.coachTargetId, rec.amount ?? live.amount);
      }
    }
    _set(state.copyWith(paid: {...state.paid}..remove(key), bills: bills, txns: txns));
  }

  /// Adds spending/borrowing to a debt, increasing what's owed.
  void addToDebtBalance(Bill b, double amount) {
    if (!b.isDebt || b.debtBalance == null) return;
    final live = state.bills.where((e) => e.id == b.id).firstOrNull ?? b;
    _set(state.copyWith(
      bills: _upsert(
        state.bills,
        live.copyWith(debtBalance: live.debtBalance! + amount),
        (e) => e.id,
      ),
    ));
  }

  void markIncomeReceived(Income i, DateTime month, DateTime date) => _set(
      state.copyWith(received: {...state.received, '${monthKey(month)}|${i.id}': date}));

  void unmarkIncomeReceived(Income i, DateTime month) => _set(state.copyWith(
      received: {...state.received}..remove('${monthKey(month)}|${i.id}')));

  // Income
  void saveIncome(Income i) =>
      _set(state.copyWith(incomes: _upsert(state.incomes, i, (e) => e.id)));
  void deleteIncome(String id) => _set(
      state.copyWith(incomes: state.incomes.where((i) => i.id != id).toList()));

  // Transactions
  /// Saving spending that repays a debt also lowers that debt's balance; an
  /// edit only applies the difference.
  void saveTxn(Txn t) {
    final old = state.txns.where((e) => e.id == t.id).firstOrNull;
    var bills = state.bills;
    bills = _shiftDebt(bills, old?.debtId, old?.amount ?? 0);
    bills = _shiftDebt(bills, t.debtId, -t.amount);
    _set(state.copyWith(txns: _upsert(state.txns, t, (e) => e.id), bills: bills));
  }

  void deleteTxn(String id) {
    final old = state.txns.where((t) => t.id == id).firstOrNull;
    _set(state.copyWith(
      txns: state.txns.where((t) => t.id != id).toList(),
      bills: _shiftDebt(state.bills, old?.debtId, old?.amount ?? 0),
    ));
  }

  /// Adds [delta] to a debt's balance (never below zero).
  List<Bill> _shiftDebt(List<Bill> bills, String? debtId, double delta) {
    if (debtId == null || delta == 0) return bills;
    final b = bills.where((e) => e.id == debtId).firstOrNull;
    if (b == null || b.debtBalance == null) return bills;
    final next = (b.debtBalance! + delta).clamp(0, double.infinity).toDouble();
    return _upsert(bills, b.copyWith(debtBalance: next), (e) => e.id);
  }

  // Cards
  void saveCard(PaymentCard c) =>
      _set(state.copyWith(cards: _upsert(state.cards, c, (e) => e.id)));

  /// Removing a card keeps its purchases as ordinary (cash) spending and drops
  /// its payments, since they only made sense against the card balance.
  void deleteCard(String id) => _set(state.copyWith(
        cards: state.cards.where((c) => c.id != id).toList(),
        txns: [
          for (final t in state.txns)
            if (t.cardId != id)
              t
            else if (!t.isPayment)
              t.copyWith(clearCard: true),
        ],
        recurring: [
          for (final r in state.recurring)
            r.cardId == id ? r.copyWith(clearCard: true) : r,
        ],
      ));

  // Recurring spending
  void saveRecurring(RecurringSpend r) {
    _set(state.copyWith(recurring: _upsert(state.recurring, r, (e) => e.id)));
    materializeRecurring();
  }

  void deleteRecurring(String id) => _set(state.copyWith(
      recurring: state.recurring.where((r) => r.id != id).toList()));

  /// Logs any recurring spending that has come due since it last ran.
  void materializeRecurring([DateTime? now]) {
    final next = _withRecurring(state, now ?? DateTime.now());
    if (!identical(next, state)) _set(next);
  }

  /// [s] with due recurring spending added; returns [s] itself if none was due.
  BudgetState _withRecurring(BudgetState s, DateTime now) {
    final result = recurring_logic.materializeRecurring(s.recurring, now);
    if (result.txns.isEmpty) return s;
    final have = {for (final t in s.txns) t.id};
    return s.copyWith(
      recurring: result.rules,
      txns: [...s.txns, ...result.txns.where((t) => !have.contains(t.id))],
    );
  }

  /// [s] with a confirmed Debt Coach bill brought up to date for the current
  /// period; returns [s] itself if nothing is confirmed or nothing changed.
  BudgetState _withCoachBillRefreshed(BudgetState s, DateTime now) {
    if (!s.bills.any((b) => b.isCoachExtra)) return s;
    final updated = _coachBillFor(s, periodKeyFor(s.startDay, now));
    if (updated == null) return s;
    final existing = s.bills.where((b) => b.isCoachExtra).firstOrNull;
    if (existing != null &&
        existing.amount == updated.amount &&
        existing.coachTargetId == updated.coachTargetId) {
      return s;
    }
    return s.copyWith(bills: _upsert(s.bills, updated, (e) => e.id));
  }

  // Goals
  void saveGoal(Goal g) =>
      _set(state.copyWith(goals: _upsert(state.goals, g, (e) => e.id)));
  void deleteGoal(String id) =>
      _set(state.copyWith(goals: state.goals.where((g) => g.id != id).toList()));

  /// Adds (or, if negative, withdraws) money from a goal. With [asSpending],
  /// the same amount is logged as spending so it leaves "left to spend".
  void addToGoal(Goal g, double amount, {bool asSpending = false}) {
    final live = state.goals.where((e) => e.id == g.id).firstOrNull;
    if (live == null) return;
    final saved = (live.saved + amount).clamp(0, double.infinity).toDouble();
    _set(state.copyWith(
      goals: _upsert(state.goals, live.copyWith(saved: saved), (e) => e.id),
      txns: asSpending && amount > 0
          ? [
              ...state.txns,
              Txn(
                id: newId(),
                date: DateTime.now(),
                amount: amount,
                categoryId: 'savings',
                note: 'Savings: ${live.name}',
              ),
            ]
          : null,
    ));
  }

  void setCurrency(String symbol) => _set(state.copyWith(currency: symbol));
  void setFocusCategory(String? id) => _set(state.copyWith(focusCategoryId: id));
  void setPaceMode(int mode) => _set(state.copyWith(paceMode: mode));
  void setThemeMode(int mode) => _set(state.copyWith(themeMode: mode));
  void setPeriodStartDay(int day) => _set(state.copyWith(periodStartDay: day));

  /// Sets a manual correction to "left to spend" for [period], as a delta on
  /// top of what's calculated (see [BudgetState.leftAdjustmentFor]).
  void setLeftAdjustment(DateTime period, double adjustment) => _set(state.copyWith(
      leftAdjustments: {...state.leftAdjustments, monthKey(period): adjustment}));

  void clearLeftAdjustment(DateTime period) => _set(state.copyWith(
      leftAdjustments: {...state.leftAdjustments}..remove(monthKey(period))));

  /// Which order to pay debts off in. See [BudgetState.coachStrategy].
  void setCoachStrategy(int strategy) => _set(state.copyWith(coachStrategy: strategy));

  /// The debt to prioritize first when the strategy is "pick one first".
  void setCoachPriorityDebt(String? debtId) =>
      _set(state.copyWith(coachPriorityDebtId: debtId));

  void setCoach({int? intensity, double? buffer}) =>
      _set(state.copyWith(coachIntensity: intensity, coachBuffer: buffer));

  /// True once the Debt Coach plan has been confirmed as a recurring bill.
  bool get coachPlanConfirmed => state.bills.any((b) => b.isCoachExtra);

  /// Turns the coach's current live suggestion into a recurring bill, due on
  /// payday, that this period and every period after keeps in sync with the
  /// plan (see [refreshCoachBill]).
  void confirmCoachPlan(DateTime month) {
    final updated = _coachBillFor(state, month);
    if (updated == null) return;
    _set(state.copyWith(bills: _upsert(state.bills, updated, (e) => e.id)));
  }

  /// Removes the confirmed bill; it stops being tracked or shown.
  void unconfirmCoachPlan() =>
      _set(state.copyWith(bills: state.bills.where((b) => !b.isCoachExtra).toList()));

  /// Keeps an already-confirmed bill's amount and target in sync with the
  /// live plan - e.g. once a debt is paid off, the same bill moves on to
  /// whatever the plan targets next. Safe to call anytime; a no-op if nothing
  /// is confirmed, or if nothing has actually changed.
  void refreshCoachBill([DateTime? month]) {
    if (!coachPlanConfirmed) return;
    final updated = _coachBillFor(state, month ?? state.currentPeriod);
    if (updated == null) return;
    final existing = state.bills.where((b) => b.isCoachExtra).firstOrNull;
    if (existing != null &&
        existing.amount == updated.amount &&
        existing.coachTargetId == updated.coachTargetId) {
      return;
    }
    _set(state.copyWith(bills: _upsert(state.bills, updated, (e) => e.id)));
  }

  /// The bill a confirm/refresh should upsert, or null if there's nothing
  /// worth confirming right now (no debts, nothing spare, or a strategy with
  /// no single target).
  Bill? _coachBillFor(BudgetState s, DateTime month) {
    final plan = buildCoachPlan(s, month, priorityDebtId: s.coachPriorityDebtId);
    // A confirmed bill is a recurring, ongoing commitment - it should not be
    // blocked just because this one period happens to be squeezed (its own
    // amount can still legitimately come out at 0 for that period alone).
    if (!plan.hasDebts || plan.budget.steadyExtra <= 0) return null;
    final strategy =
        s.coachStrategy < 0 ? plan.recommended : Strategy.values[s.coachStrategy];
    if (strategy == Strategy.splitEvenly) return null;
    final result = plan.of(strategy);
    final targetId = result.schedule.isEmpty ? null : result.schedule.first.targetId;
    if (targetId == null) return null;
    final target = plan.debts.where((d) => d.id == targetId).firstOrNull;
    if (target == null) return null;
    final existing = s.bills.where((b) => b.isCoachExtra).firstOrNull;
    return Bill(
      id: _coachBillId,
      name: 'Extra to ${target.name}',
      amount: plan.budget.extra,
      categoryId: existing?.categoryId ?? 'debt',
      isCoachExtra: true,
      coachTargetId: target.id,
      coachTargetIsCard: target.isCard,
      dueDay: existing?.dueDay ?? s.startDay,
    );
  }
}
