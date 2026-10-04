import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format.dart';
import '../../../core/widgets/common.dart';
import '../application/budget_provider.dart';
import '../domain/models.dart';
import '../domain/period.dart';
import '../domain/summary.dart';
import 'forms.dart';

/// A recurring bill/debt row for the selected month. Ticking it asks when it
/// was paid; unticking it undoes the recorded payment.
class BillTile extends ConsumerWidget {
  const BillTile(this.bill, {super.key, this.editable = true});
  final Bill bill;

  /// When false, tapping the row toggles paid instead of opening the editor.
  final bool editable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(budgetProvider);
    final month = ref.watch(selectedMonthProvider);
    final rec = s.paidRecord(bill, month);
    final paid = rec != null;

    void toggle() {
      if (paid) {
        ref.read(budgetProvider.notifier).unmarkBillPaid(bill, month);
      } else {
        showBillPaymentForm(context, bill, month);
      }
    }

    final details = [
      if (paid)
        rec.date == null ? 'Paid' : 'Paid ${shortDate(rec.date!)}'
      else if (bill.dueDay != null)
        'Due ${ordinal(bill.dueDay!)}',
      if (paid && rec.amount != null && rec.amount != bill.amount)
        money(rec.amount!, s.currency),
      if (bill.isCoachExtra) 'From Debt coach',
    ].join(' · ');
    final owedLine = bill.isDebt && bill.debtBalance != null
        ? 'Owed ${money(bill.debtBalance!, s.currency)}'
        : null;
    final subtitle = [if (details.isNotEmpty) details, ?owedLine].join('\n');

    final tile = ListTile(
      onTap: editable ? () => showBillForm(context, bill: bill) : toggle,
      leading: CategoryAvatar(s.category(bill.categoryId)),
      title: Text(
        bill.name,
        style: TextStyle(
          decoration: paid ? TextDecoration.lineThrough : null,
          color: paid ? Theme.of(context).disabledColor : null,
        ),
      ),
      subtitle: subtitle.isEmpty ? null : Text(subtitle),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(money(bill.amount, s.currency),
            style: const TextStyle(fontWeight: FontWeight.w700)),
        if (bill.isDebt && bill.debtBalance != null)
          PopupMenuButton(
            itemBuilder: (ctx) => [
              PopupMenuItem(
                child: const Row(children: [Icon(Icons.payments_rounded, size: 18), SizedBox(width: 12), Text('Make payment')]),
                onTap: () => showBillPaymentForm(context, bill, month),
              ),
              PopupMenuItem(
                child: const Row(children: [Icon(Icons.add_rounded, size: 18), SizedBox(width: 12), Text('Add to debt')]),
                onTap: () => showAddToDebtForm(context, bill),
              ),
            ],
          )
        else
          Checkbox(
            value: paid,
            tristate: false,
            onChanged: (_) => toggle(),
          ),
      ]),
    );

    // Swiping to delete only makes sense where this is the bill's home (the
    // Budget tab); the read-only preview on Overview just toggles paid.
    if (!editable) return tile;
    return Dismissible(
      key: ValueKey(bill.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Semantic.bad,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      confirmDismiss: (_) => confirmDelete(context, bill.name),
      onDismissed: (_) => ref.read(budgetProvider.notifier).deleteBill(bill.id),
      child: tile,
    );
  }
}

/// An income row: shows the pay day and lets the user record when it arrived.
class IncomeTile extends ConsumerWidget {
  const IncomeTile(this.income, {super.key});
  final Income income;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(budgetProvider);
    final month = ref.watch(selectedMonthProvider);
    final got = s.receivedOn(income, month);
    final notifier = ref.read(budgetProvider.notifier);

    Future<void> toggle() async {
      if (got != null) return notifier.unmarkIncomeReceived(income, month);
      final d = await showDatePicker(
        context: context,
        helpText: 'When did you get paid?',
        initialDate: dateInPeriod(s.startDay, month, income.payDay, DateTime.now()),
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
      );
      if (d != null) notifier.markIncomeReceived(income, month, d);
    }

    final details = [
      income.oneOffMonth == null ? 'Every month' : 'One-time',
      if (got != null)
        'Received ${shortDate(got)}'
      else if (income.payDay != null)
        'Expected ${ordinal(income.payDay!)}',
    ].join(' · ');

    final tile = ListTile(
      onTap: () => showIncomeForm(context, income: income),
      leading: CircleAvatar(
        backgroundColor:
            got != null ? Semantic.good.withValues(alpha: 0.18) : null,
        child: Icon(
          got != null ? Icons.check_rounded : Icons.arrow_downward_rounded,
          color: got != null ? Semantic.good : null,
        ),
      ),
      title: Text(income.name),
      subtitle: Text(details),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(money(income.amount, s.currency),
            style: const TextStyle(
                fontWeight: FontWeight.w700, color: Semantic.good)),
        Checkbox(
          value: got != null,
          tristate: false,
          onChanged: (_) => toggle(),
        ),
      ]),
    );

    return Dismissible(
      key: ValueKey(income.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Semantic.bad,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      confirmDismiss: (_) => confirmDelete(context, income.name),
      onDismissed: (_) => notifier.deleteIncome(income.id),
      child: tile,
    );
  }
}

/// A credit card shown among the debts: what is owed, with quick ways to pay
/// it down or add spending to it.
class CardDebtTile extends ConsumerWidget {
  const CardDebtTile(this.card, {super.key});
  final PaymentCard card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(budgetProvider);
    final month = ref.watch(selectedMonthProvider);
    final owed = summarizeCard(s, card, month).owed;
    final rate = card.interestRate;
    final details = [
      'Credit card',
      if (rate > 0) '${rate.toStringAsFixed(rate % 1 == 0 ? 0 : 1)}% a year',
      if (card.minPayment > 0) 'min ${money(card.minPayment, s.currency)}',
    ].join(' · ');

    return ListTile(
      onTap: () => context.push('/cards/${card.id}'),
      leading: CircleAvatar(
        backgroundColor: card.color.withValues(alpha: 0.18),
        child: Icon(Icons.credit_card_rounded, color: card.color),
      ),
      title: Text(card.name),
      subtitle: Text(details),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(money(owed, s.currency),
            style: TextStyle(
                fontWeight: FontWeight.w700, color: owed > 0 ? Semantic.bad : null)),
        PopupMenuButton<String>(
          onSelected: (v) async {
            if (v == 'pay') showCardPaymentForm(context, card, suggested: owed);
            if (v == 'spend') showTxnForm(context, cardId: card.id);
            if (v == 'edit') showCardForm(context, card: card);
            if (v == 'delete') {
              if (await confirmDelete(context, card.name)) {
                ref.read(budgetProvider.notifier).deleteCard(card.id);
              }
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'pay',
              enabled: owed > 0,
              child: const Row(children: [
                Icon(Icons.payments_rounded, size: 18),
                SizedBox(width: 12),
                Text('Make payment'),
              ]),
            ),
            const PopupMenuItem(
              value: 'spend',
              child: Row(children: [
                Icon(Icons.add_rounded, size: 18),
                SizedBox(width: 12),
                Text('Add spending'),
              ]),
            ),
            const PopupMenuItem(
              value: 'edit',
              child: Row(children: [
                Icon(Icons.edit_outlined, size: 18),
                SizedBox(width: 12),
                Text('Edit card'),
              ]),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(children: [
                Icon(Icons.delete_outline_rounded, size: 18, color: Semantic.bad),
                SizedBox(width: 12),
                Text('Delete card', style: TextStyle(color: Semantic.bad)),
              ]),
            ),
          ],
        ),
      ]),
    );
  }
}
