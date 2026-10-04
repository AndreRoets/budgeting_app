import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format.dart';
import '../../../core/widgets/common.dart';
import '../application/budget_provider.dart';
import '../domain/summary.dart';
import 'forms.dart';

class CardsScreen extends ConsumerWidget {
  const CardsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(budgetProvider);
    final month = ref.watch(selectedMonthProvider);
    final summaries = [for (final c in s.cards) summarizeCard(s, c, month)];
    final owed = summaries
        .where((c) => c.card.isCredit)
        .fold<double>(0, (a, c) => a + c.owed);
    final used = summaries.fold<double>(0, (a, c) => a + c.usedThisMonth);

    return Scaffold(
      appBar: AppBar(title: const Text('Cards')),
      floatingActionButton: AppFab(
        onPressed: () => showCardForm(context),
        icon: const Icon(Icons.add_card_rounded),
        label: const Text('Add card'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
        children: [
          const MonthBar(),
          if (s.cards.isEmpty)
            const EmptyHint(Icons.credit_card_off_outlined,
                'Add your credit cards and extra cards to see how much you use on each one.')
          else ...[
            Row(children: [
              Expanded(child: _Stat('Used this month', used, s.currency)),
              const SizedBox(width: 12),
              Expanded(child: _Stat('Total owed on credit', owed, s.currency)),
            ]),
            const SizedBox(height: 8),
            for (final c in summaries)
              _CardTile(summary: c, cur: s.currency),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.cur);
  final String label;
  final double value;
  final String cur;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            FittedBox(
              child: Text(money(value, cur),
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
            ),
          ]),
        ),
      );
}

class _CardTile extends ConsumerWidget {
  const _CardTile({required this.summary, required this.cur});
  final CardSummary summary;
  final String cur;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = summary.card;
    final hasLimit = c.isCredit && c.limit > 0;
    return Dismissible(
      key: ValueKey(c.id),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: Semantic.bad,
          borderRadius: BorderRadius.circular(20),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      confirmDismiss: (_) => confirmDelete(context, c.name),
      onDismissed: (_) => ref.read(budgetProvider.notifier).deleteCard(c.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => context.push('/cards/${c.id}'),
          child: Ink(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [c.color, Color.lerp(c.color, Colors.black, 0.35)!],
              ),
            ),
            child: DefaultTextStyle.merge(
              style: const TextStyle(color: Colors.white),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                      child: Text(c.name,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w700))),
                  Icon(c.isCredit ? Icons.credit_score_rounded : Icons.credit_card_rounded,
                      color: Colors.white70),
                ]),
                const SizedBox(height: 18),
                Row(children: [
                  _col('Used this month', money(summary.usedThisMonth, cur)),
                  if (c.isCredit) _col('Owed', money(summary.owed, cur)),
                ]),
                if (hasLimit) ...[
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: summary.utilisation,
                      minHeight: 6,
                      color: Colors.white,
                      backgroundColor: Colors.white24,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                      '${money(summary.available, cur)} available of ${money(c.limit, cur)}',
                      style: const TextStyle(fontSize: 12, color: Colors.white70)),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _col(String label, String value) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.white70)),
          const SizedBox(height: 2),
          FittedBox(
            child: Text(value,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          ),
        ]),
      );
}

class CardDetailScreen extends ConsumerWidget {
  const CardDetailScreen({super.key, required this.cardId});
  final String cardId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(budgetProvider);
    final month = ref.watch(selectedMonthProvider);
    final card = s.cards.where((c) => c.id == cardId).firstOrNull;
    if (card == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Card not found')));
    }
    final sum = summarizeCard(s, card, month);
    final txns = s.txns.where((t) => t.cardId == cardId).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final cur = s.currency;

    return Scaffold(
      appBar: AppBar(
        title: Text(card.name),
        actions: [
          IconButton(
            tooltip: 'Edit card',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => showCardForm(context, card: card),
          ),
        ],
      ),
      floatingActionButton: AppFab(
        onPressed: () => showTxnForm(context, cardId: cardId),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add purchase'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          _CardTile(summary: sum, cur: cur),
          if (card.isCredit)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: FilledButton.tonalIcon(
                onPressed: sum.owed > 0
                    ? () => showCardPaymentForm(context, card, suggested: sum.owed)
                    : null,
                icon: const Icon(Icons.payments_rounded),
                label: const Text('Record a payment'),
              ),
            ),
          const SectionHeader('Activity'),
          Card(
            child: txns.isEmpty && card.openingBalance <= 0
                ? const EmptyHint(Icons.receipt_long_outlined, 'No activity yet.')
                : Column(children: [
                    for (final t in txns)
                      ListTile(
                        onTap: t.isPayment ? null : () => showTxnForm(context, txn: t),
                        leading: t.isPayment
                            ? const CircleAvatar(child: Icon(Icons.check_rounded))
                            : CategoryAvatar(s.category(t.categoryId)),
                        title: Text(t.isPayment
                            ? 'Payment'
                            : (t.note.isEmpty ? s.category(t.categoryId).name : t.note)),
                        subtitle: Text(dayLabel(t.date)),
                        trailing: Text(
                          '${t.isPayment ? '-' : ''}${money(t.amount, cur)}',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: t.isPayment ? Semantic.good : null),
                        ),
                        onLongPress: t.isPayment
                            ? () async {
                                if (await confirmDelete(context, 'this payment') &&
                                    context.mounted) {
                                  ref.read(budgetProvider.notifier).deleteTxn(t.id);
                                }
                              }
                            : null,
                      ),
                    if (card.openingBalance > 0)
                      ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.flag_outlined)),
                        title: const Text('Opening balance'),
                        trailing: Text(money(card.openingBalance, cur),
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                  ]),
          ),
        ],
      ),
    );
  }
}
