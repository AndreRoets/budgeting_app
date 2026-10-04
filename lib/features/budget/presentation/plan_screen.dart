import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format.dart';
import '../../../core/widgets/common.dart';
import '../application/budget_provider.dart';
import '../domain/models.dart';
import '../domain/period.dart';
import '../domain/summary.dart';
import 'bill_tile.dart';
import 'settings_sheet.dart';
import 'forms.dart';

/// The monthly plan: income, recurring expenses, debts and category budgets.
class PlanScreen extends ConsumerWidget {
  const PlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(budgetProvider);
    final month = ref.watch(selectedMonthProvider);
    final sum = summarize(s, month);
    final cur = s.currency;

    final incomes = s.incomes.where((i) => i.appliesTo(month)).toList();
    final expenses = s.bills.where((b) => !b.isDebt && b.appliesTo(month)).toList();
    final debts = s.bills.where((b) => b.isDebt && b.appliesTo(month)).toList();
    final creditCards = s.cards.where((c) => c.isCredit).toList();

    Widget add(String label, VoidCallback onTap) => TextButton.icon(
        onPressed: onTap, icon: const Icon(Icons.add_rounded), label: Text(label));

    return Scaffold(
      appBar: AppBar(title: const Text('Monthly budget')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          const MonthBar(),
          SectionHeader('Income',
              action: Row(mainAxisSize: MainAxisSize.min, children: [
                add('Extra', () => showExtraIncomeForm(context)),
                add('Add', () => showIncomeForm(context)),
              ])),
          Card(
            child: incomes.isEmpty
                ? const EmptyHint(Icons.account_balance_wallet_outlined,
                    'Add your salary or other money coming in.')
                : Column(children: [
                    for (final i in incomes) IncomeTile(i),
                  ]),
          ),
          _BudgetMonthCard(s: s),
          SectionHeader('Monthly expenses',
              action: add('Add', () => showBillForm(context))),
          Card(
            child: expenses.isEmpty
                ? const EmptyHint(Icons.receipt_long_outlined,
                    'Add rent, subscriptions, insurance and other fixed costs.')
                : Column(children: [for (final b in expenses) BillTile(b)]),
          ),
          SectionHeader('Debts',
              action: add('Add', () => showBillForm(context, isDebt: true))),
          Card(
            child: debts.isEmpty && creditCards.isEmpty
                ? const EmptyHint(Icons.account_balance_outlined,
                    'Add loans and other debts with their monthly payment.')
                : Column(children: [
                    for (final b in debts) BillTile(b),
                    for (final c in creditCards) CardDebtTile(c),
                  ]),
          ),
          SectionHeader('Spending budgets',
              action: TextButton(
                  onPressed: () => context.push('/budget/categories'),
                  child: const Text('Edit categories'))),
          Card(
            child: Column(children: [
              for (final c in sum.categories.where((c) => c.budget > 0))
                ListTile(
                  leading: CategoryAvatar(c.category),
                  title: Text(c.category.name),
                  trailing: Text(money(c.budget, cur),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  onTap: () => showCategoryForm(context, category: c.category),
                ),
              if (sum.categories.every((c) => c.budget <= 0))
                const EmptyHint(Icons.tune_rounded,
                    'Set how much you plan to spend per category, like groceries or fuel.'),
            ]),
          ),
          const SectionHeader('Plan summary'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                _line(context, 'Income', sum.income, cur),
                _line(context, 'Expenses', -sum.billsTotal, cur),
                _line(context, 'Debt payments', -sum.debtTotal, cur),
                _line(context, 'Spending budgets', -sum.budgeted, cur),
                const Divider(height: 24),
                _line(context, 'Unassigned', sum.unallocated, cur, bold: true),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _line(BuildContext context, String label, double v, String cur,
      {bool bold = false}) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
      fontSize: bold ? 16 : 14,
      color: bold ? (v < 0 ? Semantic.bad : Semantic.good) : null,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(child: Text(label, style: style)),
        Text(money(v, cur), style: style),
      ]),
    );
  }
}

/// Shows the current budget month and what decides it, right next to salary
/// and pay day so the connection between the two is obvious.
class _BudgetMonthCard extends StatelessWidget {
  const _BudgetMonthCard({required this.s});
  final BudgetState s;

  @override
  Widget build(BuildContext context) {
    final auto = s.periodStartDay == 0;
    final driver = s.incomes
        .where((i) => i.payDay != null && i.oneOffMonth == null)
        .toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));

    final String subtitle;
    if (!auto) {
      subtitle = 'Set manually to start on the ${ordinal(s.startDay)}. Tap to change.';
    } else if (driver.isNotEmpty) {
      subtitle =
          'Follows ${driver.first.name}\'s pay day, the ${ordinal(driver.first.payDay!)}. Tap to change.';
    } else {
      subtitle =
          'Add a pay day above to split your budget by pay period. Using the calendar month for now.';
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Card(
        child: ListTile(
          onTap: () => showBudgetMonthSheet(context),
          leading: const Icon(Icons.event_repeat_rounded),
          title: Text('Budget month: ${s.label(s.currentPeriod)}'),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right_rounded),
        ),
      ),
    );
  }
}
