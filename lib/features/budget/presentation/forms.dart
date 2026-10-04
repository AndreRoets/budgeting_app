import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/widgets/common.dart';
import '../application/budget_provider.dart';
import '../domain/models.dart';
import '../domain/period.dart';
import '../domain/summary.dart';

/// A red message shown at the top of a form when it can't be saved.
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Semantic.bad.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.error_outline_rounded, color: Semantic.bad, size: 20),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text,
                  style: const TextStyle(
                      color: Semantic.bad, fontWeight: FontWeight.w700))),
        ]),
      );
}

String _notEnoughFunds(double left, double amount, String cur, String period) =>
    'You do not have enough funds. '
    'You have ${money(left < 0 ? 0 : left, cur)} left in $period '
    'and this is ${money(amount, cur)}.';

/// Shared scaffolding: title, form key, save/delete buttons.
class _FormShell extends StatelessWidget {
  const _FormShell({
    required this.title,
    required this.formKey,
    required this.children,
    required this.onSave,
    this.onDelete,
  });

  final String title;
  final GlobalKey<FormState> formKey;
  final List<Widget> children;
  final VoidCallback onSave;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) => Form(
        key: formKey,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          sheetTitle(context, title),
          for (final c in children) ...[c, const SizedBox(height: 14)],
          const SizedBox(height: 4),
          Row(children: [
            if (onDelete != null) ...[
              IconButton.outlined(
                tooltip: 'Delete',
                color: Semantic.bad,
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: FilledButton(
                onPressed: () {
                  if (formKey.currentState!.validate()) onSave();
                },
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                child: const Text('Save'),
              ),
            ),
          ]),
        ]),
      );
}

String? _required(String? v) => (v ?? '').trim().isEmpty ? 'Required' : null;

// ---------------------------------------------------------------- Bill/debt

Future<void> showBillForm(BuildContext context, {Bill? bill, bool isDebt = false}) =>
    showFormSheet(context, _BillForm(bill: bill, isDebt: bill?.isDebt ?? isDebt));

class _BillForm extends ConsumerStatefulWidget {
  const _BillForm({this.bill, required this.isDebt});
  final Bill? bill;
  final bool isDebt;

  @override
  ConsumerState<_BillForm> createState() => _BillFormState();
}

class _BillFormState extends ConsumerState<_BillForm> {
  final _key = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.bill?.name);
  late final _amount = TextEditingController(text: widget.bill?.amount.toStringAsFixed(2));
  late final _balance = TextEditingController(
      text: widget.bill?.debtBalance?.toStringAsFixed(2));
  late final _due = TextEditingController(text: widget.bill?.dueDay?.toString());
  late final _apr = TextEditingController(
      text: widget.bill?.interestRate?.toString());
  late String _cat = widget.bill?.categoryId ??
      (widget.isDebt ? 'debt' : 'housing');

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _balance.dispose();
    _due.dispose();
    _apr.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cats = ref.watch(budgetProvider).categories;
    final debt = widget.isDebt;
    return _FormShell(
      title: '${widget.bill == null ? 'Add' : 'Edit'} ${debt ? 'debt' : 'monthly expense'}',
      formKey: _key,
      onDelete: widget.bill == null
          ? null
          : () async {
              if (await confirmDelete(context, widget.bill!.name) && context.mounted) {
                ref.read(budgetProvider.notifier).deleteBill(widget.bill!.id);
                Navigator.pop(context);
              }
            },
      onSave: () {
        ref.read(budgetProvider.notifier).saveBill(Bill(
              id: widget.bill?.id ?? newId(),
              name: _name.text.trim(),
              amount: parseAmount(_amount.text)!,
              categoryId: _cat,
              isDebt: debt,
              dueDay: int.tryParse(_due.text.trim()),
              debtBalance: debt ? parseAmount(_balance.text) : null,
              interestRate: debt ? parseAmount(_apr.text) : null,
            ));
        Navigator.pop(context);
      },
      children: [
        TextFormField(
          controller: _name,
          autofocus: widget.bill == null,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
              labelText: debt ? 'Debt name (e.g. Car loan)' : 'Name (e.g. Rent)',
              border: const OutlineInputBorder()),
          validator: _required,
        ),
        AmountField(controller: _amount, label: debt ? 'Monthly payment' : 'Monthly amount'),
        if (debt)
          AmountField(
              controller: _balance,
              label: 'Total still owed (optional)',
              required: false,
              allowZero: true),
        if (debt)
          AmountField(
              controller: _apr,
              label: 'Interest rate per year, % (optional)',
              required: false,
              allowZero: true),
        CategoryDropdown(
            categories: cats,
            value: _cat,
            onChanged: (v) => setState(() => _cat = v),
            onCreate: () => showCategoryForm(context)),
        TextFormField(
          controller: _due,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
              labelText: 'Due day of month, 1-31 (optional)',
              border: OutlineInputBorder()),
          validator: (v) {
            if ((v ?? '').trim().isEmpty) return null;
            final n = int.tryParse(v!.trim());
            return n == null || n < 1 || n > 31 ? 'Enter 1 to 31' : null;
          },
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------- Income

Future<void> showIncomeForm(BuildContext context, {Income? income}) =>
    showFormSheet(context, _IncomeForm(income: income));

class _IncomeForm extends ConsumerStatefulWidget {
  const _IncomeForm({this.income});
  final Income? income;

  @override
  ConsumerState<_IncomeForm> createState() => _IncomeFormState();
}

class _IncomeFormState extends ConsumerState<_IncomeForm> {
  final _key = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.income?.name);
  late final _amount =
      TextEditingController(text: widget.income?.amount.toStringAsFixed(2));
  late final _payDay = TextEditingController(text: widget.income?.payDay?.toString());
  late bool _oneOff = widget.income?.oneOffMonth != null;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _payDay.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final month = ref.watch(selectedMonthProvider);
    return _FormShell(
      title: widget.income == null ? 'Add income' : 'Edit income',
      formKey: _key,
      onDelete: widget.income == null
          ? null
          : () async {
              if (await confirmDelete(context, widget.income!.name) && context.mounted) {
                ref.read(budgetProvider.notifier).deleteIncome(widget.income!.id);
                Navigator.pop(context);
              }
            },
      onSave: () {
        ref.read(budgetProvider.notifier).saveIncome(Income(
              id: widget.income?.id ?? newId(),
              name: _name.text.trim(),
              amount: parseAmount(_amount.text)!,
              oneOffMonth: _oneOff ? (widget.income?.oneOffMonth ?? monthKey(month)) : null,
              payDay: int.tryParse(_payDay.text.trim()),
            ));
        Navigator.pop(context);
      },
      children: [
        TextFormField(
          controller: _name,
          autofocus: widget.income == null,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
              labelText: 'Source (e.g. Salary)', border: OutlineInputBorder()),
          validator: _required,
        ),
        AmountField(controller: _amount),
        TextFormField(
          controller: _payDay,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
              labelText: 'Pay day of month, 1-31 (optional)',
              helperText:
                  'Your largest regular income\'s pay day sets your budget month, e.g. the 25th to the 24th.',
              helperMaxLines: 2,
              border: OutlineInputBorder()),
          validator: (v) {
            if ((v ?? '').trim().isEmpty) return null;
            final n = int.tryParse(v!.trim());
            return n == null || n < 1 || n > 31 ? 'Enter 1 to 31' : null;
          },
        ),
        SegmentedButton<bool>(
          segments: [
            const ButtonSegment(value: false, label: Text('Every month')),
            ButtonSegment(
                value: true,
                label: Text(
                    'Only ${ref.watch(budgetProvider).label(DateTime.parse('${widget.income?.oneOffMonth ?? monthKey(month)}-01'))}')),
          ],
          selected: {_oneOff},
          onSelectionChanged: (s) => setState(() => _oneOff = s.first),
        ),
      ],
    );
  }
}

// -------------------------------------------------------------- Transaction

/// [debtId] and [amount] pre-fill a repayment towards that debt.
Future<void> showTxnForm(BuildContext context,
        {Txn? txn, String? cardId, String? debtId, double? amount}) =>
    showFormSheet(
        context, _TxnForm(txn: txn, cardId: cardId, debtId: debtId, amount: amount));

class _TxnForm extends ConsumerStatefulWidget {
  const _TxnForm({this.txn, this.cardId, this.debtId, this.amount});
  final Txn? txn;
  final String? cardId;
  final String? debtId;
  final double? amount;

  @override
  ConsumerState<_TxnForm> createState() => _TxnFormState();
}

/// An extra category a purchase is split into (the main category gets the rest).
class _SplitRow {
  _SplitRow(this.categoryId, [String amount = '']) : amount = TextEditingController(text: amount);
  String categoryId;
  final TextEditingController amount;
}

class _TxnFormState extends ConsumerState<_TxnForm> {
  final _key = GlobalKey<FormState>();
  late final _amount =
      TextEditingController(text: (widget.txn?.amount ?? widget.amount)?.toStringAsFixed(2));
  late final _note = TextEditingController(text: widget.txn?.note);
  late String _cat = widget.txn?.categoryId ?? 'groceries';
  late String? _card = widget.txn?.cardId ?? widget.cardId;
  late DateTime _date = widget.txn?.date ?? DateTime.now();
  late String? _debt = widget.txn?.debtId ?? widget.debtId;

  /// Credit card being paid off, when this entry is a card payment.
  String? _payCard;
  String? _error;
  Repeat? _repeat;
  late final List<_SplitRow> _extras = [
    // For an existing split purchase, everything after the first part.
    for (final p in (widget.txn?.splits ?? const <SplitPart>[]).skip(1))
      _SplitRow(p.categoryId, p.amount.toStringAsFixed(2)),
  ];

  @override
  void initState() {
    super.initState();
    if (widget.txn == null && widget.debtId != null) {
      final debt = ref
          .read(budgetProvider)
          .bills
          .where((b) => b.id == widget.debtId)
          .firstOrNull;
      if (debt != null) _cat = debt.categoryId;
    }
    _amount.addListener(_refresh);
    for (final r in _extras) {
      r.amount.addListener(_refresh);
    }
  }

  void _refresh() => setState(() => _error = null);

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    for (final r in _extras) {
      r.amount.dispose();
    }
    super.dispose();
  }

  double get _total => parseAmount(_amount.text) ?? 0;
  double get _extraSum =>
      _extras.fold<double>(0, (a, r) => a + (parseAmount(r.amount.text) ?? 0));

  void _addSplit(List<Category> cats) {
    final other = cats.firstWhere((c) => c.id != _cat, orElse: () => cats.first);
    final row = _SplitRow(other.id)..amount.addListener(_refresh);
    setState(() => _extras.add(row));
  }

  void _save() {
    final n = ref.read(budgetProvider.notifier);
    final total = _total;
    final chosenDebt =
        ref.read(budgetProvider).bills.where((b) => b.id == _debt).firstOrNull;
    if (_payCard != null) {
      n.saveTxn(Txn(
        id: newId(),
        date: _date,
        amount: total,
        cardId: _payCard,
        isPayment: true,
        note: _note.text.trim().isEmpty ? 'Payment' : _note.text.trim(),
      ));
      Navigator.pop(context);
      return;
    }
    if (_repeat != null) {
      n.saveRecurring(RecurringSpend(
        id: newId(),
        amount: total,
        repeat: _repeat!,
        start: _date,
        categoryId: _cat,
        cardId: _card,
        note: _note.text.trim(),
      ));
    } else {
      final splits = _extras.isEmpty
          ? const <SplitPart>[]
          : [
              SplitPart(_cat, total - _extraSum),
              for (final r in _extras)
                SplitPart(r.categoryId, parseAmount(r.amount.text) ?? 0),
            ];
      n.saveTxn(Txn(
        id: widget.txn?.id ?? newId(),
        date: _date,
        amount: total,
        categoryId: _cat,
        cardId: _card,
        note: _note.text.trim().isEmpty && chosenDebt != null
            ? 'Payment: ${chosenDebt.name}'
            : _note.text.trim(),
        splits: splits,
        debtId: _debt,
      ));
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(budgetProvider);
    final cur = s.currency;
    final isNew = widget.txn == null;
    final splitting = _extras.isNotEmpty;
    final mainPart = _total - _extraSum;
    final debts = s.bills
        .where((b) => b.isDebt && ((b.debtBalance ?? 0) > 0 || b.id == _debt))
        .toList();
    final chosen = debts.where((d) => d.id == _debt).firstOrNull;
    // Balance before this entry, so editing an existing repayment previews correctly.
    final wasPaid = widget.txn?.debtId == _debt ? (widget.txn?.amount ?? 0) : 0;
    final owedNow = (chosen?.debtBalance ?? 0) + wasPaid;
    final cardsOwing = [
      for (final c in s.cards)
        if (c.isCredit) c,
    ];
    double owedOn(PaymentCard c) =>
        summarizeCard(s, c, s.periodKey(_date)).owed;
    final payCard = cardsOwing.where((c) => c.id == _payCard).firstOrNull;
    final payOwed = payCard == null
        ? 0.0
        : owedOn(payCard);

    return _FormShell(
      title: payCard != null
          ? 'Pay ${payCard.name}'
          : (isNew ? 'Add spending' : 'Edit spending'),
      formKey: _key,
      onDelete: isNew
          ? null
          : () {
              ref.read(budgetProvider.notifier).deleteTxn(widget.txn!.id);
              Navigator.pop(context);
            },
      onSave: () {
        if (splitting && mainPart <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('The split amounts must add up to less than the total')));
          return;
        }
        final onCredit =
            s.cards.where((c) => c.id == _card).firstOrNull?.isCredit ?? false;
        final period = s.periodKey(_date);
        final left = summarize(
          s.copyWith(txns: s.txns.where((t) => t.id != widget.txn?.id).toList()),
          period,
        ).left;
        if (payCard != null) {
          if (_total > payOwed + 0.005) {
            setState(() => _error = 'You only owe ${money(payOwed, cur)} on '
                '${payCard.name}, and this payment is ${money(_total, cur)}.');
            return;
          }
          // Paying a card comes out of income, so it needs the money to be there.
          if (_total > left) {
            setState(() => _error = _notEnoughFunds(left, _total, cur, s.label(period)));
            return;
          }
          _save();
          return;
        }
        // A credit card purchase becomes debt, so it needs no money from income.
        if (!onCredit && _total > left) {
          setState(() => _error = _notEnoughFunds(left, _total, cur, s.label(period)));
          return;
        }
        _save();
      },
      children: [
        if (_error != null) _ErrorBanner(_error!),
        AmountField(controller: _amount, label: 'Total amount', autofocus: isNew),
        if (payCard == null)
          CategoryDropdown(
            categories: s.categories,
            value: _cat,
            onChanged: (v) => setState(() => _cat = v),
            onCreate: () => showCategoryForm(context)),
        if (_repeat == null && _debt == null && payCard == null) ...[
          for (var i = 0; i < _extras.length; i++)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                flex: 5,
                child: DropdownButtonFormField<String>(
                  key: ValueKey('split$i${_extras[i].categoryId}'),
                  initialValue: s.categories.any((c) => c.id == _extras[i].categoryId)
                      ? _extras[i].categoryId
                      : otherCategoryId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'Also in', border: OutlineInputBorder()),
                  items: [
                    for (final c in s.categories)
                      DropdownMenuItem(
                        value: c.id,
                        child: Row(children: [
                          Icon(c.icon, color: c.color, size: 18),
                          const SizedBox(width: 8),
                          Flexible(child: Text(c.name, overflow: TextOverflow.ellipsis)),
                        ]),
                      ),
                  ],
                  onChanged: (v) =>
                      setState(() => _extras[i].categoryId = v ?? otherCategoryId),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(flex: 4, child: AmountField(controller: _extras[i].amount)),
              IconButton(
                tooltip: 'Remove split',
                onPressed: () => setState(() => _extras.removeAt(i).amount.dispose()),
                icon: const Icon(Icons.close_rounded),
              ),
            ]),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _addSplit(s.categories),
              icon: const Icon(Icons.call_split_rounded, size: 18),
              label: Text(splitting
                  ? 'Split into another category'
                  : 'Split across categories'),
            ),
          ),
          if (splitting)
            Text(
              '${s.category(_cat).name} gets ${money(mainPart, cur)}',
              style: TextStyle(
                  color: mainPart <= 0 ? Semantic.bad : null,
                  fontWeight: FontWeight.w600),
            ),
        ],
        if (payCard == null)
          _SpendPreview(
          state: s,
          editing: widget.txn?.id,
          date: _date,
          categoryId: _cat,
          amount: _total,
          categoryAmount: splitting ? mainPart : null,
          creditCard: s.cards.where((c) => c.id == _card && c.isCredit).firstOrNull,
        ),
        if (!splitting && _repeat == null && (debts.isNotEmpty || cardsOwing.isNotEmpty))
          DropdownButtonFormField<String?>(
            key: ValueKey('target${_payCard ?? _debt}'),
            isExpanded: true,
            initialValue: payCard != null
                ? 'c:${payCard.id}'
                : (chosen != null ? 'd:${chosen.id}' : null),
            decoration: InputDecoration(
              labelText: 'Repay a debt or card (optional)',
              helperText: payCard != null
                  ? 'Owed ${money(payOwed, cur)} → '
                      '${money((payOwed - _total).clamp(0, double.infinity), cur)}'
                  : chosen == null
                      ? null
                      : 'Owed ${money(owedNow, cur)} → '
                          '${money((owedNow - _total).clamp(0, double.infinity), cur)}',
            ),
            items: [
              const DropdownMenuItem(value: null, child: Text('Not a debt or card payment')),
              for (final d in debts)
                DropdownMenuItem(
                  value: 'd:${d.id}',
                  child: Text('${d.name} · owed ${money(d.debtBalance ?? 0, cur)}',
                      overflow: TextOverflow.ellipsis),
                ),
              for (final c in cardsOwing)
                DropdownMenuItem(
                  value: 'c:${c.id}',
                  enabled: owedOn(c) > 0.005 || c.id == _payCard,
                  child: Row(children: [
                    Icon(Icons.credit_card_rounded, color: c.color, size: 18),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                          owedOn(c) > 0.005
                              ? '${c.name} · owed ${money(owedOn(c), cur)}'
                              : '${c.name} · nothing owed',
                          overflow: TextOverflow.ellipsis),
                    ),
                  ]),
                ),
            ],
            onChanged: (v) => setState(() {
              _debt = null;
              _payCard = null;
              if (v == null) return;
              _repeat = null;
              if (v.startsWith('c:')) {
                _payCard = v.substring(2);
                _card = null;
              } else {
                _debt = v.substring(2);
                _cat = debts.firstWhere((b) => b.id == _debt).categoryId;
              }
            }),
          ),
        if (payCard == null)
          DropdownButtonFormField<String?>(
            isExpanded: true,
            initialValue: s.cards.any((c) => c.id == _card) ? _card : null,
            decoration: const InputDecoration(
                labelText: 'Paid with', border: OutlineInputBorder()),
            items: [
              const DropdownMenuItem(value: null, child: Text('Cash / bank account')),
              for (final c in s.cards)
                DropdownMenuItem(
                  value: c.id,
                  child: Row(children: [
                    Icon(Icons.credit_card_rounded, color: c.color, size: 20),
                    const SizedBox(width: 10),
                    Text(c.name),
                  ]),
                ),
            ],
            onChanged: (v) => setState(() => _card = v),
          ),
        TextFormField(
          controller: _note,
          decoration: const InputDecoration(
              labelText: 'Note (optional)', border: OutlineInputBorder()),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.event_rounded),
          label: Text(dayLabel(_date)),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: _date,
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (d != null) setState(() => _date = d);
          },
        ),
        if (isNew && !splitting && _debt == null && payCard == null)
          DropdownButtonFormField<Repeat?>(
            isExpanded: true,
            initialValue: _repeat,
            decoration: const InputDecoration(
                labelText: 'Repeat',
                helperText: 'Repeating spending is logged for you automatically',
                border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: null, child: Text('Does not repeat')),
              DropdownMenuItem(value: Repeat.daily, child: Text('Every day')),
              DropdownMenuItem(value: Repeat.weekly, child: Text('Every week')),
              DropdownMenuItem(value: Repeat.monthly, child: Text('Every month')),
            ],
            onChanged: (v) => setState(() => _repeat = v),
          ),
      ],
    );
  }
}

// --------------------------------------------------------------------- Card

Future<void> showCardForm(BuildContext context, {PaymentCard? card}) =>
    showFormSheet(context, _CardForm(card: card));

class _CardForm extends ConsumerStatefulWidget {
  const _CardForm({this.card});
  final PaymentCard? card;

  @override
  ConsumerState<_CardForm> createState() => _CardFormState();
}

class _CardFormState extends ConsumerState<_CardForm> {
  final _key = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.card?.name);
  late final _limit = TextEditingController(
      text: (widget.card?.limit ?? 0) > 0 ? widget.card!.limit.toStringAsFixed(2) : '');
  late final _opening = TextEditingController(
      text: (widget.card?.openingBalance ?? 0) > 0
          ? widget.card!.openingBalance.toStringAsFixed(2)
          : '');
  late final _rate = TextEditingController(
      text: (widget.card?.interestRate ?? 0) > 0
          ? widget.card!.interestRate.toString()
          : '');
  late final _min = TextEditingController(
      text: (widget.card?.minPayment ?? 0) > 0
          ? widget.card!.minPayment.toStringAsFixed(2)
          : '');
  late bool _credit = widget.card?.isCredit ?? true;
  late int _color = widget.card?.colorIndex ?? 0;

  @override
  void dispose() {
    _name.dispose();
    _limit.dispose();
    _opening.dispose();
    _rate.dispose();
    _min.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _FormShell(
        title: widget.card == null ? 'Add card' : 'Edit card',
        formKey: _key,
        onDelete: widget.card == null
            ? null
            : () async {
                if (await confirmDelete(context, widget.card!.name) && context.mounted) {
                  ref.read(budgetProvider.notifier).deleteCard(widget.card!.id);
                  // Pop the form, then the card detail page beneath it.
                  Navigator.pop(context);
                  if (Navigator.canPop(context)) Navigator.pop(context);
                }
              },
        onSave: () {
          ref.read(budgetProvider.notifier).saveCard(PaymentCard(
                id: widget.card?.id ?? newId(),
                name: _name.text.trim(),
                colorIndex: _color,
                isCredit: _credit,
                limit: _credit ? (parseAmount(_limit.text) ?? 0) : 0,
                openingBalance: _credit ? (parseAmount(_opening.text) ?? 0) : 0,
                interestRate: _credit ? (parseAmount(_rate.text) ?? 0) : 0,
                minPayment: _credit ? (parseAmount(_min.text) ?? 0) : 0,
              ));
          Navigator.pop(context);
        },
        children: [
          TextFormField(
            controller: _name,
            autofocus: widget.card == null,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
                labelText: 'Card name (e.g. Visa Gold)', border: OutlineInputBorder()),
            validator: _required,
          ),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                  value: true,
                  icon: Icon(Icons.credit_score_rounded),
                  label: Text('Credit')),
              ButtonSegment(
                  value: false,
                  icon: Icon(Icons.credit_card_rounded),
                  label: Text('Debit / other')),
            ],
            selected: {_credit},
            onSelectionChanged: (s) => setState(() => _credit = s.first),
          ),
          if (_credit) ...[
            AmountField(
                controller: _limit,
                label: 'Credit limit (optional)',
                required: false),
            AmountField(
                controller: _opening,
                label: 'Amount already owed (optional)',
                required: false,
                allowZero: true),
            AmountField(
                controller: _rate,
                label: 'Interest rate, % a year (optional)',
                required: false,
                allowZero: true),
            AmountField(
                controller: _min,
                label: 'Minimum monthly payment (optional)',
                required: false,
                allowZero: true),
          ],
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (var i = 0; i < kCategoryColors.length; i++)
              GestureDetector(
                onTap: () => setState(() => _color = i),
                child: CircleAvatar(
                  radius: 16,
                  backgroundColor: kCategoryColors[i],
                  child: _color == i
                      ? const Icon(Icons.check, size: 18, color: Colors.white)
                      : null,
                ),
              ),
          ]),
        ],
      );
}

// ------------------------------------------------------------ Card payment

Future<void> showCardPaymentForm(BuildContext context, PaymentCard card,
        {double? suggested}) =>
    showFormSheet(context, _PaymentForm(card: card, suggested: suggested));

class _PaymentForm extends ConsumerStatefulWidget {
  const _PaymentForm({required this.card, this.suggested});
  final PaymentCard card;
  final double? suggested;

  @override
  ConsumerState<_PaymentForm> createState() => _PaymentFormState();
}

class _PaymentFormState extends ConsumerState<_PaymentForm> {
  final _key = GlobalKey<FormState>();
  late final _amount = TextEditingController(
      text: (widget.suggested ?? 0) > 0 ? widget.suggested!.toStringAsFixed(2) : '');
  String? _error;

  @override
  void initState() {
    super.initState();
    _amount.addListener(() {
      if (_error != null) setState(() => _error = null);
    });
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(budgetProvider);
    final cur = s.currency;
    final now = DateTime.now();
    final month = s.periodKey(now);
    final left = summarize(s, month).left;

    return _FormShell(
      title: 'Pay ${widget.card.name}',
      formKey: _key,
      onSave: () {
        final amount = parseAmount(_amount.text)!;
        final owed = summarizeCard(s, widget.card, month).owed;
        if (amount > owed + 0.005) {
          setState(() => _error = 'You only owe ${money(owed, cur)} on '
              '${widget.card.name}, and this payment is ${money(amount, cur)}.');
          return;
        }
        if (amount > left) {
          setState(() => _error = _notEnoughFunds(left, amount, cur, s.label(month)));
          return;
        }
        ref.read(budgetProvider.notifier).saveTxn(Txn(
              id: newId(),
              date: now,
              amount: amount,
              cardId: widget.card.id,
              isPayment: true,
              note: 'Payment',
            ));
        Navigator.pop(context);
      },
      children: [
        if (_error != null) _ErrorBanner(_error!),
        AmountField(controller: _amount, label: 'Payment amount', autofocus: true),
        Text(
          'This comes out of what you have left this month: ${money(left < 0 ? 0 : left, cur)}.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------- Category

Future<String?> showCategoryForm(BuildContext context, {Category? category}) =>
    showFormSheet<String>(context, _CategoryForm(category: category));

class _CategoryForm extends ConsumerStatefulWidget {
  const _CategoryForm({this.category});
  final Category? category;

  @override
  ConsumerState<_CategoryForm> createState() => _CategoryFormState();
}

class _CategoryFormState extends ConsumerState<_CategoryForm> {
  final _key = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.category?.name);
  late final _budget = TextEditingController(
      text: (widget.category?.budget ?? 0) > 0
          ? widget.category!.budget.toStringAsFixed(2)
          : '');
  late int _icon = widget.category?.iconIndex ?? 10;
  late int _color = widget.category?.colorIndex ?? 0;

  @override
  void dispose() {
    _name.dispose();
    _budget.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isOther = widget.category?.id == otherCategoryId;
    return _FormShell(
      title: widget.category == null ? 'New category' : 'Edit category',
      formKey: _key,
      onDelete: widget.category == null || isOther
          ? null
          : () async {
              if (await confirmDelete(context, widget.category!.name) && context.mounted) {
                ref.read(budgetProvider.notifier).deleteCategory(widget.category!.id);
                Navigator.pop(context);
              }
            },
      onSave: () {
        final id = widget.category?.id ?? newId();
        ref.read(budgetProvider.notifier).saveCategory(Category(
              id: id,
              name: _name.text.trim(),
              iconIndex: _icon,
              colorIndex: _color,
              budget: parseAmount(_budget.text) ?? 0,
            ));
        Navigator.pop(context, id);
      },
      children: [
        TextFormField(
          controller: _name,
          autofocus: widget.category == null,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
              labelText: 'Name', border: OutlineInputBorder()),
          validator: _required,
        ),
        AmountField(
            controller: _budget,
            label: 'Monthly spending budget (optional)',
            required: false,
            allowZero: true),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (var i = 0; i < kCategoryIcons.length; i++)
            ChoiceChip(
              showCheckmark: false,
              label: Icon(kCategoryIcons[i], size: 20),
              selected: _icon == i,
              onSelected: (_) => setState(() => _icon = i),
            ),
        ]),
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (var i = 0; i < kCategoryColors.length; i++)
            GestureDetector(
              onTap: () => setState(() => _color = i),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: kCategoryColors[i],
                child: _color == i
                    ? const Icon(Icons.check, size: 18, color: Colors.white)
                    : null,
              ),
            ),
        ]),
      ],
    );
  }
}

/// Shows how much of the month will be left if this purchase is saved.
class _SpendPreview extends StatelessWidget {
  const _SpendPreview({
    required this.state,
    required this.editing,
    required this.date,
    required this.categoryId,
    required this.amount,
    this.categoryAmount,
    this.creditCard,
  });

  final BudgetState state;

  /// Id of the transaction being edited, so it isn't counted twice.
  final String? editing;
  final DateTime date;
  final String categoryId;
  final double amount;

  /// Part of [amount] that lands in [categoryId] when the purchase is split.
  final double? categoryAmount;

  /// Credit card the purchase is charged to: it adds to debt, not to spending from income.
  final PaymentCard? creditCard;

  @override
  Widget build(BuildContext context) {
    final base = state.copyWith(
        txns: state.txns.where((t) => t.id != editing).toList());
    final period = base.periodKey(date);
    final sum = summarize(base, period);
    final cur = state.currency;
    final credit = creditCard?.isCredit == true ? creditCard : null;
    final owedBefore = credit == null ? 0.0 : summarizeCard(base, credit, period).owed;
    // A credit card purchase becomes debt, so left to spend does not change.
    final after = credit != null ? sum.left : sum.left - amount;
    final cat = sum.categories.where((c) => c.category.id == categoryId).firstOrNull;
    final catAfter =
        cat == null ? null : cat.remaining - (categoryAmount ?? amount);
    final color = after < 0 ? Semantic.bad : Semantic.good;

    Widget row(String label, String value, {Color? c, bool big = false}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Expanded(child: Text(label)),
            Text(value,
                style: TextStyle(
                    fontWeight: big ? FontWeight.w800 : FontWeight.w600,
                    fontSize: big ? 18 : null,
                    color: c)),
          ]),
        );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(children: [
        row('Left in ${base.label(period)} now', money(sum.left, cur)),
        row('After this purchase', money(after, cur), c: color, big: true),
        if (credit != null)
          row('Owed on ${credit.name}',
              '${money(owedBefore, cur)} → ${money(owedBefore + amount, cur)}',
              c: Semantic.bad),
        if (cat != null && cat.budget > 0 && catAfter != null)
          row('${cat.category.name} budget left', money(catAfter, cur),
              c: catAfter < 0 ? Semantic.bad : null),
        if (credit != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.credit_card_rounded, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                    'Charged to your card, so it adds to your debt and not to what you spend from income.',
                    style: const TextStyle(fontSize: 12)),
              ),
            ]),
          ),
        if (credit == null && after < 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(children: [
              const Icon(Icons.warning_amber_rounded, size: 16, color: Semantic.bad),
              const SizedBox(width: 6),
              Expanded(
                child: Text('This puts you ${money(-after, cur)} over for the month.',
                    style: const TextStyle(color: Semantic.bad, fontSize: 12)),
              ),
            ]),
          ),
      ]),
    );
  }
}

// ------------------------------------------------------------ Bill payment

/// Asks when (and how much) was paid, then records it.
Future<void> showBillPaymentForm(BuildContext context, Bill bill, DateTime month) =>
    showFormSheet(context, _BillPaymentForm(bill: bill, month: month));

class _BillPaymentForm extends ConsumerStatefulWidget {
  const _BillPaymentForm({required this.bill, required this.month});
  final Bill bill;
  final DateTime month;

  @override
  ConsumerState<_BillPaymentForm> createState() => _BillPaymentFormState();
}

class _BillPaymentFormState extends ConsumerState<_BillPaymentForm> {
  final _key = GlobalKey<FormState>();
  late final _amount =
      TextEditingController(text: widget.bill.amount.toStringAsFixed(2));
  late DateTime _date = dateInPeriod(ref.read(budgetProvider).startDay, widget.month,
      widget.bill.dueDay, DateTime.now());
  bool _reduce = true;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.bill;
    final cur = ref.watch(budgetProvider).currency;
    final canReduce = b.isDebt && b.debtBalance != null;
    return _FormShell(
      title: 'Mark ${b.name} as paid',
      formKey: _key,
      onSave: () {
        ref.read(budgetProvider.notifier).markBillPaid(
              b,
              widget.month,
              date: _date,
              amount: parseAmount(_amount.text)!,
              reduceBalance: canReduce && _reduce,
            );
        Navigator.pop(context);
      },
      children: [
        OutlinedButton.icon(
          icon: const Icon(Icons.event_rounded),
          label: Text('Paid on ${dayLabel(_date)}'),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: _date,
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (d != null) setState(() => _date = d);
          },
        ),
        AmountField(controller: _amount, label: 'Amount paid'),
        if (canReduce)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _reduce,
            onChanged: (v) => setState(() => _reduce = v ?? true),
            title: const Text('Reduce the amount I still owe'),
            subtitle: Text('Currently ${money(b.debtBalance!, cur)}'),
          ),
      ],
    );
  }
}

// ----------------------------------------------------------------- Add to debt

Future<void> showAddToDebtForm(BuildContext context, Bill debt) =>
    showFormSheet(context, _AddToDebtForm(debt: debt));

class _AddToDebtForm extends ConsumerStatefulWidget {
  const _AddToDebtForm({required this.debt});
  final Bill debt;

  @override
  ConsumerState<_AddToDebtForm> createState() => _AddToDebtFormState();
}

class _AddToDebtFormState extends ConsumerState<_AddToDebtForm> {
  final _key = GlobalKey<FormState>();
  late final _amount = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _FormShell(
        title: 'Add to ${widget.debt.name}',
        formKey: _key,
        onSave: () {
          ref.read(budgetProvider.notifier).addToDebtBalance(
              widget.debt, parseAmount(_amount.text)!);
          Navigator.pop(context);
        },
        children: [
          AmountField(controller: _amount, label: 'Amount to add', autofocus: true)
        ],
      );
}

// -------------------------------------------------------------------- Goals

Future<void> showGoalForm(BuildContext context, {Goal? goal}) =>
    showFormSheet(context, _GoalForm(goal: goal));

class _GoalForm extends ConsumerStatefulWidget {
  const _GoalForm({this.goal});
  final Goal? goal;

  @override
  ConsumerState<_GoalForm> createState() => _GoalFormState();
}

class _GoalFormState extends ConsumerState<_GoalForm> {
  final _key = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.goal?.name);
  late final _target =
      TextEditingController(text: widget.goal?.target.toStringAsFixed(2));
  late final _saved = TextEditingController(
      text: (widget.goal?.saved ?? 0) > 0 ? widget.goal!.saved.toStringAsFixed(2) : '');
  late DateTime? _deadline = widget.goal?.deadline;
  late int _color = widget.goal?.colorIndex ?? 9;

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    _saved.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.goal == null;
    return _FormShell(
      title: isNew ? 'New savings goal' : 'Edit goal',
      formKey: _key,
      onDelete: isNew
          ? null
          : () async {
              if (await confirmDelete(context, widget.goal!.name) && context.mounted) {
                ref.read(budgetProvider.notifier).deleteGoal(widget.goal!.id);
                Navigator.pop(context);
              }
            },
      onSave: () {
        ref.read(budgetProvider.notifier).saveGoal(Goal(
              id: widget.goal?.id ?? newId(),
              name: _name.text.trim(),
              target: parseAmount(_target.text)!,
              saved: isNew ? (parseAmount(_saved.text) ?? 0) : widget.goal!.saved,
              deadline: _deadline,
              colorIndex: _color,
            ));
        Navigator.pop(context);
      },
      children: [
        TextFormField(
          controller: _name,
          autofocus: isNew,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
              labelText: 'Goal (e.g. Holiday)', border: OutlineInputBorder()),
          validator: _required,
        ),
        AmountField(controller: _target, label: 'Target amount'),
        if (isNew)
          AmountField(
              controller: _saved,
              label: 'Already saved (optional)',
              required: false,
              allowZero: true),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.event_rounded),
              label: Text(_deadline == null
                  ? 'Target month (optional)'
                  : 'By ${monthLabel(_deadline!)}'),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: () async {
                final d = await showDatePicker(
                  context: context,
                  helpText: 'Pick any day in the target month',
                  initialDate: _deadline ?? DateTime.now(),
                  firstDate: DateTime(DateTime.now().year - 1),
                  lastDate: DateTime(2100),
                );
                if (d != null) setState(() => _deadline = DateTime(d.year, d.month));
              },
            ),
          ),
          if (_deadline != null)
            IconButton(
              tooltip: 'Clear date',
              icon: const Icon(Icons.close_rounded),
              onPressed: () => setState(() => _deadline = null),
            ),
        ]),
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (var i = 0; i < kCategoryColors.length; i++)
            GestureDetector(
              onTap: () => setState(() => _color = i),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: kCategoryColors[i],
                child: _color == i
                    ? const Icon(Icons.check, size: 18, color: Colors.white)
                    : null,
              ),
            ),
        ]),
      ],
    );
  }
}

Future<void> showGoalFundsForm(BuildContext context, Goal goal) =>
    showFormSheet(context, _GoalFundsForm(goal: goal));

class _GoalFundsForm extends ConsumerStatefulWidget {
  const _GoalFundsForm({required this.goal});
  final Goal goal;

  @override
  ConsumerState<_GoalFundsForm> createState() => _GoalFundsFormState();
}

class _GoalFundsFormState extends ConsumerState<_GoalFundsForm> {
  final _key = GlobalKey<FormState>();
  final _amount = TextEditingController();
  bool _withdraw = false;
  bool _asSpending = true;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cur = ref.watch(budgetProvider).currency;
    final g = widget.goal;
    return _FormShell(
      title: g.name,
      formKey: _key,
      onSave: () {
        final v = parseAmount(_amount.text)!;
        ref.read(budgetProvider.notifier).addToGoal(
              g,
              _withdraw ? -v : v,
              asSpending: !_withdraw && _asSpending,
            );
        Navigator.pop(context);
      },
      children: [
        Text('Saved ${money(g.saved, cur)} of ${money(g.target, cur)}'),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, icon: Icon(Icons.add_rounded), label: Text('Add')),
            ButtonSegment(
                value: true, icon: Icon(Icons.remove_rounded), label: Text('Withdraw')),
          ],
          selected: {_withdraw},
          onSelectionChanged: (v) => setState(() => _withdraw = v.first),
        ),
        AmountField(controller: _amount, autofocus: true),
        if (!_withdraw)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _asSpending,
            onChanged: (v) => setState(() => _asSpending = v ?? true),
            title: const Text('Take it out of what I have left'),
            subtitle: const Text('Logged as savings spending this month'),
          ),
      ],
    );
  }
}
