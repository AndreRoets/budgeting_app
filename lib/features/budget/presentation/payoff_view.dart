import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../application/budget_provider.dart';
import '../domain/models.dart';
import '../domain/payoff.dart';
import '../domain/period.dart';
import 'forms.dart';

/// Payoff dates for each debt, with a "what if I paid extra" slider.
class PayoffView extends ConsumerStatefulWidget {
  const PayoffView({super.key});

  @override
  ConsumerState<PayoffView> createState() => _PayoffViewState();
}

class _PayoffViewState extends ConsumerState<PayoffView> {
  final Map<String, double> _extra = {};

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(budgetProvider);
    final cur = s.currency;
    final clock = PeriodClock(s.startDay, s.currentPeriod);
    final debts = s.bills.where((b) => b.isDebt).toList();
    final planned = debts.where((b) => (b.debtBalance ?? 0) > 0).toList();

    // Debt-free date: when the last debt with a workable plan is cleared.
    var months = 0;
    var blocked = false;
    for (final b in planned) {
      final p = payoff(b.debtBalance!, b.amount, b.interestRate ?? 0,
          extra: _extra[b.id] ?? 0);
      if (p.never) {
        blocked = true;
      } else if (p.months > months) {
        months = p.months;
      }
    }
    final totalOwed = planned.fold<double>(0, (a, b) => a + b.debtBalance!);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        if (planned.isEmpty)
          Card(
            child: EmptyHint(
                Icons.flag_outlined,
                debts.isEmpty
                    ? 'Add a debt in the Budget tab, with the total still owed, to see when you could be debt-free.'
                    : 'Edit your debts and fill in “Total still owed” (and the interest rate) to see a payoff plan.'),
          )
        else ...[
          _Hero(
            totalOwed: totalOwed,
            months: months,
            blocked: blocked,
            clock: clock,
            cur: cur,
          ),
          Card(
            child: ListTile(
              onTap: () => context.push('/coach'),
              leading: const Icon(Icons.route_rounded),
              title: const Text('Get my payoff plan'),
              subtitle: const Text(
                  'Fastest way out of debt, based on your income, backup money and spending.'),
              trailing: const Icon(Icons.chevron_right_rounded),
            ),
          ),
          const SectionHeader('Your debts'),
          for (final b in planned)
            _DebtCard(
              bill: b,
              cur: cur,
              clock: clock,
              extra: _extra[b.id] ?? 0,
              onExtra: (v) => setState(() => _extra[b.id] = v),
            ),
        ],
        if (debts.length > planned.length) ...[
          const SectionHeader('Needs more info'),
          Card(
            child: Column(children: [
              for (final b in debts.where((b) => (b.debtBalance ?? 0) <= 0))
                ListTile(
                  leading: const Icon(Icons.info_outline_rounded),
                  title: Text(b.name),
                  subtitle: const Text('Add the total still owed to include it'),
                  onTap: () => showBillForm(context, bill: b),
                ),
            ]),
          ),
        ],
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text(
              'Estimates assume you pay the same amount every month and that interest '
              'is charged monthly at the rate you enter. Your lender’s figures may differ.',
              style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }
}

String _monthsText(int m) {
  final y = m ~/ 12, r = m % 12;
  return [
    if (y > 0) '$y ${y == 1 ? 'year' : 'years'}',
    if (r > 0) '$r ${r == 1 ? 'month' : 'months'}',
  ].join(' ');
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.totalOwed,
    required this.months,
    required this.blocked,
    required this.clock,
    required this.cur,
  });

  final double totalOwed;
  final int months;
  final bool blocked;
  final PeriodClock clock;
  final String cur;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    const on = AppTheme.onHero;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        gradient: AppTheme.heroGradient(brightness),
        border: AppTheme.heroBorder,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppTheme.heroShadowColor.withValues(alpha: 0.35),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Debt-free by', style: TextStyle(color: on.withValues(alpha: 0.8))),
          const SizedBox(height: 4),
          Text(
            months == 0
                ? (blocked ? 'Not at this pace' : 'Done')
                : clock.endLabel(months),
            style: TextStyle(color: on, fontSize: 32, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            [
              'Owed ${money(totalOwed, cur)}',
              if (months > 0) _monthsText(months),
            ].join(' · '),
            style: TextStyle(color: on.withValues(alpha: 0.8)),
          ),
          if (blocked && months > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                  'One or more debts is not being paid down at the current payment, so they are left out of this date.',
                  style: TextStyle(color: on, fontSize: 12)),
            ),
        ]),
      ),
    );
  }
}

class _DebtCard extends StatelessWidget {
  const _DebtCard({
    required this.bill,
    required this.cur,
    required this.clock,
    required this.extra,
    required this.onExtra,
  });

  final Bill bill;
  final String cur;
  final PeriodClock clock;
  final double extra;
  final ValueChanged<double> onExtra;

  @override
  Widget build(BuildContext context) {
    final apr = bill.interestRate ?? 0;
    final base = payoff(bill.debtBalance!, bill.amount, apr);
    final boosted = extra > 0
        ? payoff(bill.debtBalance!, bill.amount, apr, extra: extra)
        : null;
    final maxExtra = ((bill.amount * 2) / 10).ceil() * 10.0;
    final theme = Theme.of(context);

    Widget stat(String label, String value, {Color? color}) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: theme.textTheme.bodySmall),
            const SizedBox(height: 2),
            Text(value,
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: color)),
          ]),
        );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text(bill.name,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
            Text('${money(bill.amount, cur)} / month'),
          ]),
          const SizedBox(height: 4),
          Text(
              'Owed ${money(bill.debtBalance!, cur)}'
              '${apr > 0 ? ' · ${apr.toStringAsFixed(apr % 1 == 0 ? 0 : 1)}% a year' : ' · no interest entered'}',
              style: theme.textTheme.bodySmall),
          const SizedBox(height: 14),
          if (base.never)
            Row(children: [
              const Icon(Icons.warning_amber_rounded, color: Semantic.bad, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                    'This payment doesn’t cover the interest, so the balance won’t go down. Try paying extra.',
                    style: const TextStyle(color: Semantic.bad, fontSize: 13)),
              ),
            ])
          else
            Row(children: [
              stat('Paid off', clock.endLabel(base.months)),
              stat('Time', _monthsText(base.months)),
              stat('Interest', money(base.interest, cur)),
            ]),
          const Divider(height: 28),
          Text('What if I pay extra each month?', style: theme.textTheme.titleSmall),
          Row(children: [
            Expanded(
              child: Slider(
                value: extra.clamp(0, maxExtra),
                max: maxExtra,
                divisions: (maxExtra / 10).round(),
                label: money(extra, cur),
                onChanged: onExtra,
              ),
            ),
            SizedBox(
              width: 76,
              child: Text('+${money(extra, cur)}',
                  textAlign: TextAlign.end,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ]),
          if (boosted != null && !boosted.never)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Semantic.good.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                [
                  'Paid off ${clock.endLabel(boosted.months)}',
                  if (!base.never && base.months > boosted.months)
                    '${_monthsText(base.months - boosted.months)} sooner',
                  if (!base.never && base.interest > boosted.interest)
                    'saves ${money(base.interest - boosted.interest, cur)} interest',
                ].join(' · '),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
        ]),
      ),
    );
  }
}
