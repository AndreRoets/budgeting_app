import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/widgets/common.dart';
import '../application/budget_provider.dart';
import '../domain/models.dart';
import 'forms.dart';

String _repeatLabel(Repeat r) => switch (r) {
      Repeat.daily => 'Every day',
      Repeat.weekly => 'Every week',
      Repeat.monthly => 'Every month',
    };

class RecurringScreen extends ConsumerWidget {
  const RecurringScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(budgetProvider);
    final n = ref.read(budgetProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: const Text('Recurring spending')),
      floatingActionButton: AppFab(
        onPressed: () => showTxnForm(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 4, 4, 8),
            child: Text(
                'These are added to your spending automatically each time they fall due. '
                'To create one, choose “Repeat” when adding spending.'),
          ),
          if (s.recurring.isEmpty)
            const Card(
                child: EmptyHint(Icons.repeat_rounded,
                    'Nothing repeating yet. A daily coffee or weekly fuel are good ones to add.'))
          else
            Card(
              child: Column(children: [
                for (final r in s.recurring)
                  Dismissible(
                    key: ValueKey(r.id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      color: Semantic.bad,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
                    ),
                    onDismissed: (_) => n.deleteRecurring(r.id),
                    child: ListTile(
                      leading: CategoryAvatar(s.category(r.categoryId)),
                      title: Text(r.note.isEmpty ? s.category(r.categoryId).name : r.note),
                      subtitle: Text(
                          '${_repeatLabel(r.repeat)} · ${money(r.amount, s.currency)}'
                          '${r.active ? '' : ' · paused'}'),
                      trailing: Switch(
                        value: r.active,
                        onChanged: (v) => n.saveRecurring(r.copyWith(active: v)),
                      ),
                    ),
                  ),
              ]),
            ),
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
                'Swipe left to delete. Pausing stops new entries; '
                'anything already logged stays in your spending.',
                style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
