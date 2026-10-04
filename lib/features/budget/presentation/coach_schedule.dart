import 'package:flutter/material.dart';

import '../../../core/format.dart';
import '../../../core/widgets/common.dart';
import '../domain/coach.dart';
import '../domain/period.dart';

/// Plain-language steps: which debt gets the extra money, and for how long.
class CoachHowItWorks extends StatelessWidget {
  const CoachHowItWorks({
    super.key,
    required this.plan,
    required this.result,
    required this.cur,
    required this.clock,
  });
  final CoachPlan plan;
  final PlanResult result;
  final String cur;
  final PeriodClock clock;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phases = planPhases(result, plan.debts);
    String months(int n) => '$n ${n == 1 ? 'month' : 'months'}';
    String range(PlanPhase p) => clock.span(p.firstMonth, p.lastMonth);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            'Every month you pay each debt its minimum. All the extra goes to one debt at a time. When that debt is paid off, its whole payment moves to the next one.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < phases.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == phases.length - 1 ? 0 : 14),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.18),
                  child: Text('${i + 1}',
                      style: TextStyle(
                          color: theme.colorScheme.primary, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${range(phases[i])} · ${months(phases[i].length)}',
                        style: theme.textTheme.bodySmall),
                    const SizedBox(height: 2),
                    Text(
                      'Pay ${money(phases[i].targetPayment, cur)} ${phases[i].length > 1 ? 'a month ' : ''}to ${phases[i].target.name}',
                      style: theme.textTheme.titleSmall,
                    ),
                    if (phases[i].others.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          'Minimums only on ${phases[i].others.map((d) => '${d.name} (${money(d.minPayment, cur)})').join(', ')}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    if (phases[i].clearsAtEnd)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          phases[i].nextTarget == null
                              ? '${phases[i].target.name} is paid off in ${clock.endLabel(phases[i].lastMonth)}. You are debt-free.'
                              : '${phases[i].target.name} is paid off in ${clock.endLabel(phases[i].lastMonth)}. Its payment then moves to ${phases[i].nextTarget!.name}.',
                          style: theme.textTheme.bodySmall?.copyWith(color: Semantic.good),
                        ),
                      ),
                  ]),
                ),
              ]),
            ),
        ]),
      ),
    );
  }
}

/// One card per month with exactly what to pay each debt, grouped by year.
List<Widget> coachScheduleWidgets(
  BuildContext context,
  CoachPlan plan,
  PlanResult result,
  String cur,
  PeriodClock clock,
) {
  final theme = Theme.of(context);
  final out = <Widget>[];
  int? year;

  for (final m in result.schedule) {
    final date = clock.key(m.month);
    if (date.year != year) {
      year = date.year;
      out.add(Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
        child: Text('${date.year}',
            style: theme.textTheme.titleSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ));
    }

    final debtFree = m.totalOwed <= 0.005;
    final next = m.month < result.schedule.length ? result.schedule[m.month] : null;
    final nextTarget = (!debtFree && next != null)
        ? plan.debts.where((d) => d.id == next.targetId).firstOrNull
        : null;

    out.add(Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(clock.label(m.month), style: theme.textTheme.titleSmall),
                Text('Month ${m.month}', style: theme.textTheme.bodySmall),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('Pay ${money(m.totalPaid, cur)}',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              Text('Owed after: ${money(m.totalOwed, cur)}', style: theme.textTheme.bodySmall),
            ]),
          ]),
          const Divider(height: 20),
          for (final d in plan.debts)
            if ((m.paid[d.id] ?? 0) > 0.005)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(d.name, style: theme.textTheme.bodyMedium)),
                    Text(money(m.paid[d.id]!, cur),
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  ]),
                  const SizedBox(height: 2),
                  Text(_splitOf(d, m.paid[d.id]!, cur), style: theme.textTheme.bodySmall),
                  const SizedBox(height: 2),
                  if (m.cleared.any((c) => c.id == d.id))
                    const Text('Paid off',
                        style: TextStyle(
                            color: Semantic.good, fontSize: 12, fontWeight: FontWeight.w700))
                  else
                    Text('${money(m.balance[d.id] ?? 0, cur)} left',
                        style: theme.textTheme.bodySmall),
                ]),
              ),
          if (m.cleared.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(Icons.check_circle_rounded, size: 16, color: Semantic.good),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    debtFree
                        ? '${m.cleared.map((d) => d.name).join(' and ')} paid off. You are debt-free.'
                        : nextTarget != null
                            ? '${m.cleared.map((d) => d.name).join(' and ')} paid off. From next month that payment goes to ${nextTarget.name}.'
                            : '${m.cleared.map((d) => d.name).join(' and ')} paid off. That payment now joins the rest.',
                    style: theme.textTheme.bodySmall?.copyWith(color: Semantic.good),
                  ),
                ),
              ]),
            ),
        ]),
      ),
    ));
  }
  return out;
}

/// "$300 minimum + $255 extra", or "Minimum payment", for one payment.
String _splitOf(CoachDebt d, double paid, String cur) {
  final min = d.minPayment;
  if (paid <= min + 0.005) return 'Minimum payment';
  return '${money(min, cur)} minimum + ${money(paid - min, cur)} extra';
}
