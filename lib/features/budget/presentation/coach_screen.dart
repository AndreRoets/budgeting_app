import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../application/budget_provider.dart';
import '../domain/coach.dart';
import '../domain/models.dart';
import '../domain/period.dart';
import '../domain/summary.dart';
import 'coach_schedule.dart';
import 'forms.dart';
import 'left_override_sheet.dart';

const _levels = [
  ('Gentle', 'Steady. A quarter of your spare money goes to debt and most stays yours.'),
  ('Balanced', 'Half of your spare money goes to debt. A good mix of progress and breathing room.'),
  ('All-in', 'Nine tenths of your spare money goes to debt. Fastest, with very little left over.'),
];

/// Suggests how to clear debt fastest with the money that is really spare.
class CoachScreen extends ConsumerStatefulWidget {
  const CoachScreen({super.key});

  @override
  ConsumerState<CoachScreen> createState() => _CoachScreenState();
}

class _CoachScreenState extends ConsumerState<CoachScreen> {
  @override
  void initState() {
    super.initState();
    // Brings an already-confirmed bill up to date for the current period -
    // e.g. moves it on if its target debt was paid off since last time.
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => ref.read(budgetProvider.notifier).refreshCoachBill());
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(budgetProvider);
    final n = ref.read(budgetProvider.notifier);
    final cur = s.currency;
    final month = s.periodKey(DateTime.now());
    final clock = PeriodClock(s.startDay, month);
    final plan = buildCoachPlan(s, month, priorityDebtId: s.coachPriorityDebtId);
    final strategy =
        s.coachStrategy < 0 ? plan.recommended : Strategy.values[s.coachStrategy];
    final result = plan.of(strategy);
    final confirmedBill = s.bills.where((b) => b.isCoachExtra).firstOrNull;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Debt coach')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          if (!plan.hasDebts)
            const Card(
              child: EmptyHint(
                Icons.flag_outlined,
                'You have no debts to plan. Add a loan with the total still owed in the Budget tab, or a credit card with an amount owed.',
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
              child: Text(
                'Tell me how serious you are and how much backup money you want to keep. I will work out the fastest way out of debt with what is really spare.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            _Answer(plan: plan, result: result, cur: cur, clock: clock),
            if (plan.budget.extra > 0 && result.firstMonthExtra.isNotEmpty)
              _ThisMonth(plan: plan, result: result, strategy: strategy, cur: cur),
            _ConfirmPlan(
              plan: plan,
              strategy: strategy,
              confirmedBill: confirmedBill,
              cur: cur,
              onConfirm: () => n.confirmCoachPlan(month),
              onUnconfirm: () => n.unconfirmCoachPlan(),
            ),
            const SectionHeader('How serious are you?'),
            _Seriousness(level: s.coachIntensity, plan: plan, cur: cur),
            const SectionHeader('Your safety net'),
            _SafetyNet(plan: plan, cur: cur),
            const SectionHeader('Where your money goes'),
            _Breakdown(budget: plan.budget, cur: cur),
            const SectionHeader('Which debt first?'),
            _StrategyPicker(
              plan: plan,
              selected: strategy,
              cur: cur,
              clock: clock,
              onPick: (v) => n.setCoachStrategy(v.index),
              onPickDebt: (id) => n.setCoachPriorityDebt(id),
            ),
            _Guidance(plan: plan, strategy: strategy, result: result, cur: cur, clock: clock),
            if (result.steps.isNotEmpty || result.never) ...[
              const SectionHeader('Order they clear'),
              _Order(plan: plan, result: result, cur: cur, clock: clock),
            ],
            if (!result.never && result.months > 1) ...[
              const SectionHeader('Total owed over time'),
              _Chart(plan: plan, result: result, cur: cur, clock: clock),
            ],
            if (!result.never && result.schedule.isNotEmpty) ...[
              const SectionHeader('How the plan works'),
              if (strategy == Strategy.splitEvenly)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Every month, each open debt gets its own minimum payment, then the '
                      'extra money is divided evenly between them. A debt that needs less than '
                      'its share just gets what it needs, and the rest goes to whoever is still '
                      'open, so nothing sits idle.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                )
              else
                CoachHowItWorks(plan: plan, result: result, cur: cur, clock: clock),
              const SectionHeader('Every month, step by step'),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: Text(
                  'These are the amounts to pay each month. They include the minimums you already pay.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
              ...coachScheduleWidgets(context, plan, result, cur, clock),
            ],
            const SectionHeader('Things to know'),
            _Notes(plan: plan, state: s, month: month),
          ],
        ],
      ),
    );
  }
}

/// Rounds away floating-point dust so amounts add up exactly.
double _cents(double v) => (v * 100).round() / 100;

String _payoffLabel(PeriodClock clock, int months) =>
    clock.endLabel(months);

String _duration(int m) {
  final y = m ~/ 12, r = m % 12;
  final parts = [
    if (y > 0) '$y ${y == 1 ? 'year' : 'years'}',
    if (r > 0) '$r ${r == 1 ? 'month' : 'months'}',
  ];
  return parts.isEmpty ? 'this month' : parts.join(' ');
}

// ------------------------------------------------------------------ Answer

class _Answer extends StatelessWidget {
  const _Answer({required this.plan, required this.result, required this.cur, required this.clock});
  final CoachPlan plan;
  final PlanResult result;
  final String cur;
  final PeriodClock clock;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    const on = AppTheme.onHero;
    final b = plan.budget;
    final base = plan.baseline;

    // The plan itself (months, interest) is built on the steady, ongoing
    // extra, not this period's - a one-off dip or boost this period should
    // not decide whether there is a plan at all.
    String title, big, sub;
    if (b.steadySpare <= 0) {
      title = 'Not enough spare money';
      big = 'No extra yet';
      sub = 'After bills, backup money and spending, nothing is left over.';
    } else if (result.never) {
      title = 'Debt-free by';
      big = 'Not at this pace';
      sub = 'The payments do not keep up with the interest. Try a more serious level.';
    } else {
      title = 'Debt-free by';
      big = _payoffLabel(clock, result.months);
      sub = '${_duration(result.months)} · ${money(result.interest, cur)} interest in total';
    }

    final savedInterest = !base.never ? base.interest - result.interest : 0.0;
    final monthsSooner = !base.never ? base.months - result.months : 0;
    final showCompare = b.steadySpare > 0 && !result.never;
    final periodDiffers = b.steadyExtra > 0 && (b.steadyExtra - b.extra).abs() > 0.5;

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
          Text(title, style: TextStyle(color: on.withValues(alpha: 0.8))),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(big,
                style: const TextStyle(
                    color: on, fontSize: 36, fontWeight: FontWeight.w800, height: 1.1)),
          ),
          const SizedBox(height: 6),
          Text(sub, style: TextStyle(color: on.withValues(alpha: 0.85))),
          if (b.steadyExtra > 0) ...[
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _HeroChip('${money(b.steadyExtra, cur)} extra a month'),
              if (showCompare && savedInterest > 1)
                _HeroChip('saves ${money(savedInterest, cur)} interest'),
              if (showCompare && monthsSooner > 0)
                _HeroChip('${_duration(monthsSooner)} sooner'),
            ]),
          ],
          if (showCompare) ...[
            const SizedBox(height: 14),
            Text(
              base.never
                  ? 'If nothing changes, your current payments would not clear these debts.'
                  : 'If nothing changes: ${_payoffLabel(clock, base.months)}, ${money(base.interest, cur)} interest.',
              style: TextStyle(color: on.withValues(alpha: 0.75), fontSize: 13),
            ),
          ],
          if (periodDiffers) ...[
            const SizedBox(height: 10),
            Text(
              b.extra < b.steadyExtra
                  ? 'This period specifically, only ${money(b.extra, cur)} is actually spare, '
                      'so this step is smaller - the plan above assumes ${money(b.steadyExtra, cur)} '
                      'a month again from next period.'
                  : 'This period you have more spare than usual - ${money(b.extra, cur)} - the plan '
                      'above assumes the usual ${money(b.steadyExtra, cur)} a month from next period.',
              style: TextStyle(color: on.withValues(alpha: 0.75), fontSize: 13),
            ),
          ],
        ]),
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text,
            style: const TextStyle(
                color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
      );
}

// -------------------------------------------------------------- This month

class _ThisMonth extends ConsumerWidget {
  const _ThisMonth({
    required this.plan,
    required this.result,
    required this.strategy,
    required this.cur,
  });
  final Strategy strategy;
  final CoachPlan plan;
  final PlanResult result;
  final String cur;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(budgetProvider);
    final theme = Theme.of(context);
    // Whoever gets the most extra this month goes at the top.
    final items = [
      for (final d in plan.debts)
        if ((result.firstMonthExtra[d.id] ?? 0) > 0) (d, result.firstMonthExtra[d.id]!),
    ]..sort((a, b) => b.$2.compareTo(a.$2));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.bolt_rounded, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text('This month\'s move', style: theme.textTheme.titleMedium),
          ]),
          const SizedBox(height: 4),
          Text('Keep paying your normal minimums, and on top of that:',
              style: theme.textTheme.bodySmall),
          const SizedBox(height: 10),
          for (final (d, amount) in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Pay ${money(_cents(amount), cur)} extra',
                        style: theme.textTheme.titleSmall),
                    Text('to ${d.name}', style: theme.textTheme.bodySmall),
                  ]),
                ),
                FilledButton.tonal(
                  onPressed: () {
                    final whole = _cents(amount);
                    if (d.isCard) {
                      final card = s.cards.where((c) => c.id == d.id).firstOrNull;
                      if (card != null) showCardPaymentForm(context, card, suggested: whole);
                    } else {
                      showTxnForm(context, debtId: d.id, amount: whole);
                    }
                  },
                  child: const Text('Record it'),
                ),
              ]),
            ),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------- Confirm plan

/// Turns the live suggestion into a real recurring bill, due on payday, that
/// stays in sync with the plan and applies whatever you pay against it
/// straight to the debt it's aimed at.
class _ConfirmPlan extends StatelessWidget {
  const _ConfirmPlan({
    required this.plan,
    required this.strategy,
    required this.confirmedBill,
    required this.cur,
    required this.onConfirm,
    required this.onUnconfirm,
  });
  final CoachPlan plan;
  final Strategy strategy;
  final Bill? confirmedBill;
  final String cur;
  final VoidCallback onConfirm;
  final VoidCallback onUnconfirm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (confirmedBill == null) {
      if (strategy == Strategy.splitEvenly || plan.budget.steadyExtra <= 0) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Make this a bill to pay', style: theme.textTheme.titleSmall),
              const SizedBox(height: 6),
              Text(
                'Confirm it and this extra payment shows up as a real bill on payday, '
                'every period, and whatever you pay against it comes straight off the debt.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(onPressed: onConfirm, child: const Text('Confirm this plan')),
              ),
            ]),
          ),
        ),
      );
    }

    final pausedForSplit = strategy == Strategy.splitEvenly;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.check_circle_rounded, color: Semantic.good, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Confirmed: ${confirmedBill!.name}',
                    style: theme.textTheme.titleSmall),
              ),
            ]),
            const SizedBox(height: 6),
            Text(
              pausedForSplit
                  ? 'Paused while "Split evenly" is selected - pick a single debt to '
                      'prioritize to keep it moving.'
                  : confirmedBill!.amount > 0
                      ? 'Shows as ${money(confirmedBill!.amount, cur)} in your Bills list each '
                          'period. Pay less and the rest of the plan adjusts automatically.'
                      : 'Nothing spare this period specifically, so it shows as ${money(0, cur)} '
                          'this time - it will pick back up to ${money(plan.budget.steadyExtra, cur)} '
                          'once a normal period comes around.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(onPressed: onUnconfirm, child: const Text('Stop tracking')),
            ),
          ]),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------- Seriousness

class _Seriousness extends ConsumerWidget {
  const _Seriousness({required this.level, required this.plan, required this.cur});
  final int level;
  final CoachPlan plan;
  final String cur;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final i = level.clamp(0, _levels.length - 1);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              segments: [
                for (var k = 0; k < _levels.length; k++)
                  ButtonSegment(value: k, label: Text(_levels[k].$1)),
              ],
              selected: {i},
              onSelectionChanged: (v) =>
                  ref.read(budgetProvider.notifier).setCoach(intensity: v.first),
            ),
          ),
          const SizedBox(height: 12),
          Text(_levels[i].$2, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 8),
          Text(
            plan.budget.steadyExtra > 0
                ? 'That is ${money(plan.budget.steadyExtra, cur)} extra to debt each month.'
                : 'There is no spare money to put towards debt yet.',
            style: theme.textTheme.titleSmall,
          ),
        ]),
      ),
    );
  }
}

// -------------------------------------------------------------- Safety net

class _SafetyNet extends ConsumerWidget {
  const _SafetyNet({required this.plan, required this.cur});
  final CoachPlan plan;
  final String cur;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final b = plan.budget;
    return Card(
      child: Column(children: [
        ListTile(
          onTap: () => showLeftOverrideSheet(context),
          leading: const Icon(Icons.wallet_outlined),
          title: const Text('Left to spend'),
          subtitle: const Text('What Overview shows for this period. Tap to correct it.'),
          trailing: Text(money(b.leftToSpend, cur),
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
        ),
        const Divider(height: 1),
        ListTile(
          onTap: () => showFormSheet(context, const _BufferSheet()),
          leading: const Icon(Icons.shield_outlined),
          title: const Text('Backup money'),
          subtitle: Text(b.bufferIsDefault
              ? 'Kept aside each period. Suggested: ${(defaultBufferShare * 100).round()}% of income. Tap to change.'
              : 'Kept aside each period. Tap to change.'),
          trailing: Text(money(b.buffer, cur),
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
        ),
      ]),
    );
  }
}

class _BufferSheet extends ConsumerStatefulWidget {
  const _BufferSheet();

  @override
  ConsumerState<_BufferSheet> createState() => _BufferSheetState();
}

class _BufferSheetState extends ConsumerState<_BufferSheet> {
  final _key = GlobalKey<FormState>();
  late final _amount = TextEditingController(
      text: coachBudget(ref.read(budgetProvider), ref.read(budgetProvider).currentPeriod).buffer.toStringAsFixed(2));

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(budgetProvider);
    final income = summarize(s, s.currentPeriod).income;
    void set(double v) => setState(() => _amount.text = v.toStringAsFixed(2));

    return Form(
      key: _key,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        sheetTitle(context, 'Backup money'),
        Text(
          'Money you keep aside every month for surprises, so paying debt never leaves you stuck.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 14),
        AmountField(
            controller: _amount, label: 'Backup money each month', allowZero: true, autofocus: true),
        const SizedBox(height: 10),
        Wrap(spacing: 8, children: [
          ActionChip(label: const Text('None'), onPressed: () => set(0)),
          ActionChip(
              label: const Text('5% of income'), onPressed: () => set(income * 0.05)),
          ActionChip(
              label: const Text('10% of income'), onPressed: () => set(income * 0.10)),
        ]),
        const SizedBox(height: 16),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          onPressed: () {
            if (!_key.currentState!.validate()) return;
            ref.read(budgetProvider.notifier).setCoach(buffer: parseAmount(_amount.text) ?? 0);
            Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ]),
    );
  }
}

// --------------------------------------------------------------- Breakdown

class _Breakdown extends StatelessWidget {
  const _Breakdown({required this.budget, required this.cur});
  final CoachBudget budget;
  final String cur;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = budget;
    Widget row(String label, double v,
            {bool minus = false, bool plus = false, bool bold = false, Color? color}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Expanded(
                child: Text(label,
                    style: bold ? theme.textTheme.titleSmall : theme.textTheme.bodyMedium)),
            Text('${minus ? '− ' : plus ? '+ ' : ''}${money(v.abs(), cur)}',
                style: TextStyle(
                    fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: color)),
          ]),
        );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          row('Left to spend this period', b.leftToSpend),
          if (b.cardMinimums > 0) row('Card minimum payments', b.cardMinimums, minus: true),
          row('Backup money', b.buffer, minus: true),
          if (b.goalSavings > 0) row('Savings goals', b.goalSavings, minus: true),
          if (b.reservedForCoachBill > 0)
            row('Already committed to the confirmed plan', b.reservedForCoachBill, plus: true),
          const Divider(height: 22),
          row(b.spare < 0 ? 'Short by' : 'Spare money', b.spare,
              bold: true, color: b.spare < 0 ? Semantic.bad : null),
          if (b.spare > 0) ...[
            row('Extra to debt (${(b.share * 100).round()}%)', b.extra),
            row('Yours to keep', b.flexible),
          ],
          if ((b.extra - b.steadyExtra).abs() > 0.5) ...[
            const SizedBox(height: 4),
            Text(
              'A typical period: ${money(b.steadyExtra, cur)} extra to debt. '
              'This period is different because of a correction to Left to spend.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- Strategy

class _StrategyPicker extends StatelessWidget {
  const _StrategyPicker({
    required this.plan,
    required this.selected,
    required this.cur,
    required this.clock,
    required this.onPick,
    required this.onPickDebt,
  });
  final CoachPlan plan;
  final Strategy selected;
  final String cur;
  final PeriodClock clock;
  final ValueChanged<Strategy> onPick;
  final ValueChanged<String?> onPickDebt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget option(Strategy st, String title, String blurb, {String? placeholder}) {
      final r = plan.of(st);
      final on = selected == st;
      final cheapest = plan.recommended == st;
      final noPick = st == Strategy.custom && plan.priorityDebtId == null;
      return Card(
        color: on ? theme.colorScheme.primary.withValues(alpha: 0.16) : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(
              color: on ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
              width: on ? 1.5 : 1),
        ),
        child: Column(children: [
          InkWell(
            onTap: () => onPick(st),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(on ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                      color: on ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 10),
                  Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
                  if (cheapest)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: Semantic.good.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text('Cheapest',
                          style: TextStyle(
                              color: Semantic.good, fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                ]),
                const SizedBox(height: 6),
                Text(blurb, style: theme.textTheme.bodySmall),
                const SizedBox(height: 10),
                Text(
                  noPick
                      ? (placeholder ?? 'Choose a debt below.')
                      : r.never
                          ? 'Does not clear at this pace'
                          : '${_payoffLabel(clock, r.months)} · ${money(r.interest, cur)} interest',
                  style: theme.textTheme.titleSmall,
                ),
              ]),
            ),
          ),
          if (st == Strategy.custom && on)
            _PriorityDebtList(plan: plan, cur: cur, onPick: onPickDebt),
        ]),
      );
    }

    return Column(children: [
      option(Strategy.avalanche, 'Highest interest first',
          'Attack the most expensive debt first. Costs the least in interest.'),
      option(Strategy.snowball, 'Smallest balance first',
          'Clear small debts quickly for early wins. Can cost a little more.'),
      option(Strategy.custom, 'Pick one to prioritize',
          'Choose a debt yourself. Every other debt still gets its normal minimum, it just does not get the extra.'),
      option(Strategy.splitEvenly, 'Split evenly across all',
          'Every open debt gets a share of the extra at the same time, instead of one at a time.'),
    ]);
  }
}

/// Shown under "Pick one to prioritize" once it's selected: every open debt,
/// ranked by how much interest it's costing right now, so the better choice
/// is obvious before picking rather than only explained afterwards.
class _PriorityDebtList extends StatelessWidget {
  const _PriorityDebtList({required this.plan, required this.cur, required this.onPick});
  final CoachPlan plan;
  final String cur;
  final ValueChanged<String?> onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final debts = [...plan.debts]
      ..sort((a, b) => _monthlyInterest(b).compareTo(_monthlyInterest(a)));

    return Column(children: [
      const Divider(height: 1),
      for (final d in debts)
        ListTile(
          key: ValueKey('coach-priority-${d.id}'),
          dense: true,
          onTap: () => onPick(d.id),
          leading: Icon(
            d.id == plan.priorityDebtId
                ? Icons.radio_button_checked_rounded
                : Icons.radio_button_off_rounded,
            color: d.id == plan.priorityDebtId
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
          title: Text(d.name),
          subtitle: Text(
            d.rateMissing
                ? '${money(d.balance, cur)} owed · no interest rate entered'
                : '${money(d.balance, cur)} owed · ${_aprText(d)}% a year · '
                    'about ${money(_monthlyInterest(d), cur)}/month in interest',
          ),
        ),
    ]);
  }
}

double _monthlyInterest(CoachDebt d) => d.balance * d.apr / 100 / 12;
String _aprText(CoachDebt d) => d.apr.toStringAsFixed(d.apr % 1 == 0 ? 0 : 1);

/// Points out when the chosen order costs more than the cheapest one, and
/// names the specific debt that would do better, with real numbers.
class _Guidance extends StatelessWidget {
  const _Guidance({
    required this.plan,
    required this.strategy,
    required this.result,
    required this.cur,
    required this.clock,
  });
  final CoachPlan plan;
  final Strategy strategy;
  final PlanResult result;
  final String cur;
  final PeriodClock clock;

  @override
  Widget build(BuildContext context) {
    if (strategy == plan.recommended) return const SizedBox.shrink();
    final best = plan.best;
    if (result.never || best.never) return const SizedBox.shrink();
    final diffInterest = result.interest - best.interest;
    if (diffInterest <= 0.5) return const SizedBox.shrink();

    final betterId = best.schedule.isNotEmpty ? best.schedule.first.targetId : null;
    final better = plan.debts.where((d) => d.id == betterId).firstOrNull;
    if (better == null) return const SizedBox.shrink();

    final chosenId = result.schedule.isNotEmpty ? result.schedule.first.targetId : null;
    final chosen = plan.debts.where((d) => d.id == chosenId).firstOrNull;
    final diffMonths = result.months - best.months;
    final theme = Theme.of(context);

    final lead = strategy == Strategy.splitEvenly
        ? 'Splitting your extra money evenly'
        : chosen != null
            ? 'Paying off ${chosen.name} first'
            : 'This order';

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Card(
        color: Semantic.warn.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: Semantic.warn.withValues(alpha: 0.4)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.lightbulb_outline_rounded, color: Semantic.warn, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text('A cheaper order is available',
                    style: theme.textTheme.titleSmall?.copyWith(color: Semantic.warn)),
              ),
            ]),
            const SizedBox(height: 8),
            Text(
              '$lead costs ${money(diffInterest, cur)} more in interest'
              '${diffMonths > 0 ? ' and takes ${_duration(diffMonths)} longer' : ''} '
              'than paying off ${better.name} first. ${better.name} charges ${_aprText(better)}% '
              'a year${better.apr > 0 ? ', costing about ${money(_monthlyInterest(better), cur)} a month in interest right now' : ''}.',
              style: theme.textTheme.bodyMedium,
            ),
          ]),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------- Order

class _Order extends StatelessWidget {
  const _Order({required this.plan, required this.result, required this.cur, required this.clock});
  final CoachPlan plan;
  final PlanResult result;
  final String cur;
  final PeriodClock clock;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final clearedIds = result.steps.map((s) => s.debt.id).toSet();
    final rest = plan.debts.where((d) => !clearedIds.contains(d.id)).toList();
    var n = 0;

    Widget tile(CoachDebt d, String when) => ListTile(
          leading: CircleAvatar(
            radius: 15,
            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.18),
            child: Text('${++n}',
                style: TextStyle(
                    color: theme.colorScheme.primary, fontWeight: FontWeight.w800)),
          ),
          title: Text(d.name),
          subtitle: Text(
              '${money(d.balance, cur)} owed · ${d.apr > 0 ? '${d.apr.toStringAsFixed(d.apr % 1 == 0 ? 0 : 1)}% a year' : 'no interest entered'}'),
          trailing: Text(when, style: theme.textTheme.titleSmall),
        );

    return Card(
      child: Column(children: [
        for (final st in result.steps) tile(st.debt, _payoffLabel(clock, st.month)),
        for (final d in rest) tile(d, 'not cleared'),
      ]),
    );
  }
}

// ------------------------------------------------------------------- Chart

class _Chart extends StatelessWidget {
  const _Chart({required this.plan, required this.result, required this.cur, required this.clock});
  final CoachPlan plan;
  final PlanResult result;
  final String cur;
  final PeriodClock clock;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = plan.baseline;
    final showBase = !base.never && base.months > result.months;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Starting at ${money(result.totals.first, cur)}',
              style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          Wrap(spacing: 14, runSpacing: 4, children: [
            const _Key(color: Color(0xFF38BDF8), label: 'With the plan'),
            if (showBase)
              _Key(color: theme.colorScheme.onSurfaceVariant, label: 'If nothing changes'),
          ]),
          const SizedBox(height: 10),
          SizedBox(
            height: 150,
            width: double.infinity,
            child: CustomPaint(
              painter: _ChartPainter(
                plan: result.totals,
                baseline: showBase ? base.totals : const [],
                line: const Color(0xFF38BDF8),
                muted: theme.colorScheme.onSurfaceVariant,
                grid: theme.colorScheme.outlineVariant,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(children: [
            Text('Now', style: theme.textTheme.bodySmall),
            const Spacer(),
            Text(clock.endLabel(showBase ? base.months : result.months),
                style: theme.textTheme.bodySmall),
          ]),
        ]),
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ]);
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.plan,
    required this.baseline,
    required this.line,
    required this.muted,
    required this.grid,
  });
  final List<double> plan;
  final List<double> baseline;
  final Color line;
  final Color muted;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    final maxX = ((baseline.length > plan.length ? baseline.length : plan.length) - 1)
        .clamp(1, 1 << 30)
        .toDouble();
    final maxY = plan.first <= 0 ? 1.0 : plan.first;

    Offset pt(int i, double v) =>
        Offset(i / maxX * size.width, size.height - (v / maxY).clamp(0, 1) * size.height);

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final f in [0.0, 0.5, 1.0]) {
      final y = size.height - f * size.height;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    Path pathOf(List<double> v) {
      final step = (v.length / 80).ceil().clamp(1, 1 << 30);
      final p = Path()..moveTo(pt(0, v.first).dx, pt(0, v.first).dy);
      for (var i = step; i < v.length; i += step) {
        final o = pt(i, v[i]);
        p.lineTo(o.dx, o.dy);
      }
      final end = pt(v.length - 1, v.last);
      p.lineTo(end.dx, end.dy);
      return p;
    }

    if (baseline.length > 1) {
      final p = pathOf(baseline);
      final dashed = Path();
      for (final PathMetric m in p.computeMetrics()) {
        for (var d = 0.0; d < m.length; d += 10) {
          dashed.addPath(m.extractPath(d, (d + 5).clamp(0, m.length)), Offset.zero);
        }
      }
      canvas.drawPath(
          dashed,
          Paint()
            ..color = muted
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
    }

    final p = pathOf(plan);
    final area = Path.from(p)
      ..lineTo(pt(plan.length - 1, 0).dx, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [line.withValues(alpha: 0.35), line.withValues(alpha: 0.02)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
        p,
        Paint()
          ..color = line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.plan != plan || old.baseline != baseline || old.line != line;
}

// ------------------------------------------------------------------- Notes

class _Notes extends StatelessWidget {
  const _Notes({required this.plan, required this.state, required this.month});
  final CoachPlan plan;
  final BudgetState state;
  final DateTime month;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = plan.budget;
    final over = summarize(state, month)
        .categories
        .where((c) => c.budget > 0 && c.remaining < 0)
        .map((c) => c.category.name)
        .toList();
    final noRate = plan.debts.where((d) => d.rateMissing).map((d) => d.name).toList();
    final estMin = plan.debts.where((d) => d.minEstimated).map((d) => d.name).toList();

    final notes = <String>[
      if (b.spare <= 0)
        'To free up money you could lower your backup money, spend less for the rest of this period${over.isEmpty ? '' : ' (you are over budget on ${over.join(', ')})'}${b.goalSavings > 0 ? ', push out a savings goal\'s date' : ''}, or add more income.',
      if (b.goalSavings > 0)
        '${money(b.goalSavings, state.currency)} is set aside for your savings goals before working out what is spare for debt.',
      if (noRate.isNotEmpty)
        'No interest rate is entered for ${noRate.join(', ')}, so I treated ${noRate.length == 1 ? 'it' : 'them'} as interest-free. Add the rate for a more accurate plan.',
      if (estMin.isNotEmpty)
        'No minimum payment is entered for ${estMin.join(', ')}, so I assumed 3% of the balance each month.',
      'This is an estimate based on the figures you entered, with interest added monthly. It is not financial advice, and your lender\'s numbers may differ.',
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          for (final n in notes)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Icon(Icons.info_outline_rounded,
                      size: 16, color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(n, style: theme.textTheme.bodySmall)),
              ]),
            ),
        ]),
      ),
    );
  }
}
