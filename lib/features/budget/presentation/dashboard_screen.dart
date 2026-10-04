import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../application/budget_provider.dart';
import '../domain/models.dart';
import '../domain/period.dart';
import '../domain/summary.dart';
import 'bill_tile.dart';
import 'forms.dart';
import 'left_override_sheet.dart';
import 'settings_sheet.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(budgetProvider);
    final month = ref.watch(selectedMonthProvider);
    final sum = summarize(s, month);
    final cur = s.currency;
    final theme = Theme.of(context);

    final unpaid =
        s.bills.where((b) => b.appliesTo(month) && !s.isPaid(b, month)).toList()
      ..sort((a, b) => dueOrder(s.startDay, a.dueDay).compareTo(dueOrder(s.startDay, b.dueDay)));
    final withBudget = sum.categories.where((c) => c.budget > 0).toList();
    final isEmpty = s.incomes.isEmpty && s.bills.isEmpty && s.txns.isEmpty;
    final focus = sum.categories
        .where((c) => c.category.id == s.focusCategoryId)
        .firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Overview'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.tune_rounded),
            onPressed: () => showSettingsSheet(context),
          ),
        ],
      ),
      floatingActionButton: AppFab(
        onPressed: () => showTxnForm(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add spending'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
        children: [
          const MonthBar(),
          _HeroCard(
            sum: sum,
            debt: totalDebt(s, month),
            cur: cur,
            spentLabel: focus == null ? 'Spent' : '${focus.category.name} spent',
            spentValue: focus == null ? sum.fromIncome : focus.spent,
            pace: s.paceMode == PaceMode.off ? null : paceFor(s, sum.left, month, DateTime.now()),
            paceMode: s.paceMode,
            hasOverride: s.hasLeftAdjustment(month),
            onAdjust: () => showLeftOverrideSheet(context),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => showExtraIncomeForm(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add extra income'),
            ),
          ),
          _DebtCard(debt: totalDebt(s, month), cur: cur),
          if (s.goals.isNotEmpty) _GoalsCard(goals: s.goals, month: month, cur: cur),
          if (isEmpty) ...[
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: const Icon(Icons.rocket_launch_rounded),
                title: const Text('Get started'),
                subtitle: const Text(
                    'Add your income and monthly expenses in the Budget tab, then log spending here.'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.go('/budget'),
              ),
            ),
          ],
          SectionHeader('Where your money goes'),
          _Breakdown(sum: sum, cur: cur),
          if (withBudget.isNotEmpty) ...[
            const SectionHeader('Spending budgets'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  for (final c in withBudget) _BudgetRow(c: c, cur: cur),
                ]),
              ),
            ),
          ],
          if (unpaid.isNotEmpty) ...[
            SectionHeader('Bills still to pay',
                action: Text(money(sum.billsOutstanding, cur),
                    style: theme.textTheme.titleSmall)),
            Card(
              child: Column(children: [
                for (final b in unpaid.take(5)) BillTile(b, editable: false),
              ]),
            ),
            if (unpaid.length > 5)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                    onPressed: () => context.go('/budget'),
                    child: Text('See all ${unpaid.length}')),
              ),
          ],
          if (s.cards.isNotEmpty) ...[
            SectionHeader('Cards',
                action: TextButton(
                    onPressed: () => context.go('/cards'),
                    child: const Text('Manage'))),
            for (final c in s.cards)
              _CardRow(summary: summarizeCard(s, c, month), cur: cur),
          ],
        ],
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.sum,
    required this.debt,
    required this.cur,
    required this.spentLabel,
    required this.spentValue,
    required this.pace,
    required this.paceMode,
    required this.hasOverride,
    required this.onAdjust,
  });
  final String spentLabel;
  final double spentValue;
  final Pace? pace;
  final int paceMode;
  final DebtTotals debt;
  final MonthSummary sum;
  final String cur;
  final bool hasOverride;
  final VoidCallback onAdjust;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final used = sum.available <= 0 ? (sum.committed + sum.fromIncome > 0 ? 1.0 : 0.0)
        : (sum.committed + sum.fromIncome) / sum.available;
    final over = sum.left < 0;
    const on = AppTheme.onHero;

    Widget stat(String label, double v) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(color: on.withValues(alpha: 0.7), fontSize: 12)),
            const SizedBox(height: 2),
            Text(money(v, cur),
                style: TextStyle(color: on, fontWeight: FontWeight.w700, fontSize: 15)),
          ]),
        );

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        gradient: AppTheme.heroGradient(brightness),
        border: AppTheme.heroBorder,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppTheme.heroShadowColor
                .withValues(alpha: brightness == Brightness.dark ? 0.45 : 0.30),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(over ? 'Over budget by' : 'Left to spend',
                  style: TextStyle(color: on.withValues(alpha: 0.8))),
            ),
            InkWell(
              onTap: onAdjust,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.edit_rounded, size: 16, color: on.withValues(alpha: 0.7)),
              ),
            ),
          ]),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (r) => LinearGradient(
                colors: over
                    ? const [Color(0xFFFFD6D6), Color(0xFFFFD6D6)]
                    : const [Colors.white, Color(0xFFC4DEFF), Color(0xFF9CCBFF)],
              ).createShader(r),
              child: Text(money(over ? -sum.left : sum.left, cur),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 42,
                      letterSpacing: -1,
                      fontWeight: FontWeight.w800)),
            ),
          ),
          if (hasOverride)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: GestureDetector(
                onTap: onAdjust,
                child: Text('Manually adjusted · tap to change',
                    style: TextStyle(color: on.withValues(alpha: 0.7), fontSize: 12)),
              ),
            ),
          const SizedBox(height: 14),
          GradientBar(value: used, height: 10),
          if (pace != null) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (paceMode == PaceMode.day || paceMode == PaceMode.both)
                _PaceChip('${money(pace!.perDay, cur)} / day'),
              if (paceMode == PaceMode.week || paceMode == PaceMode.both)
                _PaceChip('${money(pace!.perWeek, cur)} / week'),
              _PaceChip('${pace!.days} days left', subtle: true),
            ]),
          ],
          const SizedBox(height: 16),
          Row(children: [
            stat('Total income', sum.income),
            stat('Bills & debt', sum.committed),
            stat(spentLabel, spentValue),
          ]),
          if (sum.income > 0)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(children: [
                Icon(
                    sum.incomeReceived >= sum.income
                        ? Icons.check_circle_rounded
                        : Icons.schedule_rounded,
                    size: 16,
                    color: on.withValues(alpha: 0.8)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                      'Received ${money(sum.incomeReceived, cur)} of ${money(sum.income, cur)}',
                      style: TextStyle(color: on.withValues(alpha: 0.8), fontSize: 13)),
                ),
              ]),
            ),
          if (sum.carriedOver != 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.redo_rounded, size: 16, color: on.withValues(alpha: 0.8)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                      sum.carriedOver > 0
                          ? 'Includes ${money(sum.carriedOver, cur)} carried over from before'
                          : '${money(-sum.carriedOver, cur)} overspent before has been taken off',
                      style: TextStyle(color: on.withValues(alpha: 0.8), fontSize: 13)),
                ),
              ]),
            ),
          if (sum.creditSpent > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.credit_card_rounded,
                    size: 16, color: on.withValues(alpha: 0.8)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                      '${money(sum.creditSpent, cur)} spent on credit cards, added to your debt',
                      style: TextStyle(color: on.withValues(alpha: 0.8), fontSize: 13)),
                ),
              ]),
            ),
          if (sum.income > 0) ...[
            const Divider(height: 28),
            Row(children: [
              Icon(
                sum.unallocated < 0
                    ? Icons.warning_amber_rounded
                    : Icons.tune_rounded,
                size: 18,
                color: sum.unallocated < 0 ? const Color(0xFFFFD6D6) : on,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  sum.unallocated < 0
                      ? 'Your plan is ${money(-sum.unallocated, cur)} more than your income'
                      : '${money(sum.unallocated, cur)} not yet assigned to a budget',
                  style: TextStyle(color: on, fontSize: 13),
                ),
              ),
            ]),
          ],
        ]),
      ),
    );
  }
}


/// Always-visible figure for everything the user owes, so it stays front of mind.
class _DebtCard extends StatelessWidget {
  const _DebtCard({required this.debt, required this.cur});
  final DebtTotals debt;
  final String cur;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final owed = AppTheme.owed(theme.brightness);
    final free = debt.total <= 0;
    final color = free ? Semantic.good : owed;
    final loanShare = debt.total > 0 ? debt.loans / debt.total : 0.0;

    Widget part(String label, double v) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: theme.textTheme.bodySmall),
            Text(money(v, cur),
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          ]),
        );

    return Card(
      color: color.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: color.withValues(alpha: 0.45)),
      ),
      child: InkWell(
        onTap: () => context.push('/coach'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.account_balance_rounded, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(free ? 'Debt free' : 'Total debt you owe',
                    style: theme.textTheme.titleSmall?.copyWith(color: color)),
              ),
              if (!free)
                Icon(Icons.chevron_right_rounded, color: theme.colorScheme.onSurfaceVariant),
            ]),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(money(debt.total, cur),
                  style: TextStyle(
                      color: color, fontSize: 34, fontWeight: FontWeight.w800, height: 1.1)),
            ),
            if (!free) ...[
              const SizedBox(height: 12),
              ProgressBar(
                  value: loanShare,
                  height: 6,
                  color: color,
                  track: color.withValues(alpha: 0.25)),
              const SizedBox(height: 10),
              Row(children: [
                part('Loans', debt.loans),
                part('Credit cards', debt.cards),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Icon(Icons.route_rounded, size: 16, color: color),
                const SizedBox(width: 6),
                Text('Get my payoff plan',
                    style: theme.textTheme.labelLarge?.copyWith(color: color)),
              ]),
            ],
          ]),
        ),
      ),
    );
  }
}
class _Breakdown extends StatelessWidget {
  const _Breakdown({required this.sum, required this.cur});
  final MonthSummary sum;
  final String cur;

  @override
  Widget build(BuildContext context) {
    final items = <(String, Color, double)>[
      for (final c in sum.categories)
        if (c.fromIncome > 0) (c.category.name, c.category.color, c.fromIncome),
      if (sum.cardPayments > 0)
        ('Credit card payments', const Color(0xFF8DB8FF), sum.cardPayments),
    ]
      ..sort((a, b) => b.$3.compareTo(a.$3));
    if (items.isEmpty) {
      return const Card(
          child: EmptyHint(Icons.pie_chart_outline_rounded,
              'Add expenses and spending to see where your money goes.'));
    }
    final theme = Theme.of(context);
    final left = sum.left > 0 ? sum.left : 0.0;
    final base = sum.available > 0 ? sum.available : sum.committed + sum.fromIncome;
    double pct(double v) => base > 0 ? v / base * 100 : 0;
    final shown = items.take(4).toList();
    final rest = items.length - shown.length;
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.35);

    Widget legend(Color c, String name, double value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 8),
            Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis)),
            Text('${pct(value).round()}%',
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ]),
        );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          DonutChart(
            size: 116,
            stroke: 15,
            slices: [
              for (final i in items) DonutSlice(i.$3, i.$2),
              DonutSlice(left, muted),
            ],
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(
                  '${base > 0 ? ((sum.committed + sum.fromIncome) / base * 100).round() : 0}%',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              Text('used', style: theme.textTheme.bodySmall),
            ]),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(children: [
              for (final i in shown) legend(i.$2, i.$1, i.$3),
              if (rest > 0)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2, bottom: 2),
                    child: Text('+$rest more',
                        style: theme.textTheme.bodySmall),
                  ),
                ),
              legend(muted, 'Left to spend', left),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _BudgetRow extends StatelessWidget {
  const _BudgetRow({required this.c, required this.cur});
  final CategoryTotals c;
  final String cur;

  @override
  Widget build(BuildContext context) {
    final ratio = c.spent / c.budget;
    final over = c.remaining < 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(children: [
        Row(children: [
          CategoryAvatar(c.category, size: 30),
          const SizedBox(width: 12),
          Expanded(
              child: Text(c.category.name,
                  style: const TextStyle(fontWeight: FontWeight.w600))),
          Text(
            over
                ? '${money(-c.remaining, cur)} over'
                : '${money(c.remaining, cur)} left',
            style: TextStyle(
                color: over ? Semantic.bad : null, fontWeight: FontWeight.w600),
          ),
        ]),
        const SizedBox(height: 8),
        ProgressBar(value: ratio),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: Text('${money(c.spent, cur)} of ${money(c.budget, cur)}',
              style: Theme.of(context).textTheme.bodySmall),
        ),
      ]),
    );
  }
}

class _CardRow extends StatelessWidget {
  const _CardRow({required this.summary, required this.cur});
  final CardSummary summary;
  final String cur;

  @override
  Widget build(BuildContext context) {
    final c = summary.card;
    return Card(
      child: ListTile(
        onTap: () => context.push('/cards/${c.id}'),
        leading: CircleAvatar(
          backgroundColor: c.color.withValues(alpha: 0.18),
          child: Icon(Icons.credit_card_rounded, color: c.color),
        ),
        title: Text(c.name),
        subtitle: Text(c.isCredit
            ? 'Owed ${money(summary.owed, cur)}'
            : 'Debit / other'),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(money(summary.usedThisMonth, cur),
                style: const TextStyle(fontWeight: FontWeight.w700)),
            Text('this month', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _PaceChip extends StatelessWidget {
  const _PaceChip(this.text, {this.subtle = false});
  final String text;
  final bool subtle;

  @override
  Widget build(BuildContext context) {
    const on = AppTheme.onHero;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: subtle ? Colors.transparent : on.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: subtle ? Border.all(color: on.withValues(alpha: 0.25)) : null,
      ),
      child: Text(text,
          style: TextStyle(
              color: on,
              fontSize: 13,
              fontWeight: subtle ? FontWeight.w500 : FontWeight.w700)),
    );
  }
}

/// How much to set aside this period for savings goals with a target date
/// (a holiday, an emergency fund, ...), so it stays in view alongside debt.
class _GoalsCard extends StatelessWidget {
  const _GoalsCard({required this.goals, required this.month, required this.cur});
  final List<Goal> goals;
  final DateTime month;
  final String cur;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final unreached = goals.where((g) => !g.reached).toList();
    final done = unreached.isEmpty;
    final color = done ? Semantic.good : Semantic.warn;

    final withDeadline = unreached.where((g) => g.deadline != null && !g.isOverdue(now)).toList()
      ..sort((a, b) => (b.monthlyNeeded(month) ?? 0).compareTo(a.monthlyNeeded(month) ?? 0));
    final overdueCount = unreached.where((g) => g.isOverdue(now)).length;
    final total = goalsSavingsNeeded(goals, month, now);
    final shown = withDeadline.take(2).toList();
    final rest = withDeadline.length - shown.length;
    final hasPlan = withDeadline.isNotEmpty || overdueCount > 0;

    return Card(
      color: color.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: color.withValues(alpha: 0.45)),
      ),
      child: InkWell(
        onTap: () => context.push('/insights?tab=2'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.savings_rounded, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(done ? 'Savings goals funded' : 'Save this period for your goals',
                    style: theme.textTheme.titleSmall?.copyWith(color: color)),
              ),
              Icon(Icons.chevron_right_rounded, color: theme.colorScheme.onSurfaceVariant),
            ]),
            const SizedBox(height: 4),
            if (done)
              Text('Every goal is reached, or has no target date to save towards.',
                  style: theme.textTheme.bodyMedium)
            else if (!hasPlan)
              Text('Add a target date to a goal to see what to save this period.',
                  style: theme.textTheme.bodyMedium)
            else
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(money(total, cur),
                    style: TextStyle(
                        color: color, fontSize: 34, fontWeight: FontWeight.w800, height: 1.1)),
              ),
            if (shown.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final g in shown)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    Expanded(
                        child: Text(g.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium)),
                    Text(money(g.monthlyNeeded(month) ?? 0, cur),
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                  ]),
                ),
              if (rest > 0)
                Text('+$rest more', style: theme.textTheme.bodySmall),
            ],
            if (overdueCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  overdueCount == 1
                      ? '1 goal has passed its target date. Tap to update.'
                      : '$overdueCount goals have passed their target dates. Tap to update.',
                  style: theme.textTheme.bodySmall?.copyWith(color: Semantic.bad),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
