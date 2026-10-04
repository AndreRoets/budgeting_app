import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/widgets/common.dart';
import '../application/budget_provider.dart';
import '../domain/models.dart';
import 'forms.dart';

class GoalsView extends ConsumerWidget {
  const GoalsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(budgetProvider);
    final now = DateTime.now();
    final saved = s.goals.fold<double>(0, (a, g) => a + g.saved);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        if (s.goals.isEmpty)
          const Card(
            child: EmptyHint(Icons.savings_outlined,
                'Save for something specific, like a holiday or an emergency fund. '
                'Set a target and a date and we’ll work out what to put away each month.'),
          )
        else ...[
          Card(
            child: ListTile(
              leading: const Icon(Icons.savings_rounded),
              title: const Text('Saved across all goals'),
              trailing: Text(money(saved, s.currency),
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(height: 4),
          for (final g in s.goals) _GoalCard(goal: g, cur: s.currency, now: now),
        ],
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          onPressed: () => showGoalForm(context),
          icon: const Icon(Icons.add_rounded),
          label: const Text('New goal'),
        ),
      ],
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.goal, required this.cur, required this.now});
  final Goal goal;
  final String cur;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final need = goal.monthlyNeeded(now);
    final overdue = goal.isOverdue(now);

    return Card(
      child: InkWell(
        onTap: () => showGoalForm(context, goal: goal),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CircleAvatar(
                backgroundColor: goal.color.withValues(alpha: 0.18),
                child: Icon(goal.reached ? Icons.check_rounded : Icons.savings_rounded,
                    color: goal.color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(goal.name,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  if (goal.deadline != null)
                    Text('By ${monthLabel(goal.deadline!)}', style: theme.textTheme.bodySmall),
                ]),
              ),
              Text('${(goal.progress * 100).round()}%',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 14),
            ProgressBar(value: goal.progress, color: goal.color, height: 10),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                  child: Text('${money(goal.saved, cur)} of ${money(goal.target, cur)}',
                      style: const TextStyle(fontWeight: FontWeight.w600))),
              if (!goal.reached)
                Text('${money(goal.remaining, cur)} to go', style: theme.textTheme.bodySmall),
            ]),
            if (goal.reached)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Goal reached 🎉',
                    style: TextStyle(color: Semantic.good, fontWeight: FontWeight.w700)),
              )
            else if (overdue)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('The target month has passed. Edit the goal to set a new date.',
                    style: TextStyle(color: Semantic.warn, fontSize: 13)),
              )
            else if (need != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Put away about ${money(need, cur)} a month',
                    style: theme.textTheme.bodyMedium),
              ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonal(
                onPressed: () => showGoalFundsForm(context, goal),
                child: const Text('Add or withdraw'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
