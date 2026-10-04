import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format.dart';
import '../../../core/widgets/common.dart';
import '../application/budget_provider.dart';
import '../domain/models.dart';
import '../domain/summary.dart';
import 'forms.dart';

/// Special value in the "paid with" filter meaning cash / bank.
const _cashFilter = '__cash__';

class SpendingScreen extends ConsumerStatefulWidget {
  const SpendingScreen({super.key});

  @override
  ConsumerState<SpendingScreen> createState() => _SpendingScreenState();
}

class _SpendingScreenState extends ConsumerState<SpendingScreen> {
  final _search = TextEditingController();
  String? _category;
  String? _card; // a card id, _cashFilter, or null for any
  bool _allTime = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool get _filtering =>
      _search.text.trim().isNotEmpty || _category != null || _card != null;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(budgetProvider);
    final month = ref.watch(selectedMonthProvider);
    final txns = filterTxns(
      s,
      month: _allTime ? null : month,
      query: _search.text,
      categoryId: _category,
      cardId: _card == _cashFilter ? null : _card,
      cashOnly: _card == _cashFilter,
    );
    final total = txns.fold<double>(0, (a, t) => a + t.amount);

    // Group by calendar day (already sorted newest first).
    final groups = <DateTime, List<Txn>>{};
    for (final t in txns) {
      groups.putIfAbsent(DateTime(t.date.year, t.date.month, t.date.day), () => []).add(t);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Spending'),
        actions: [
          IconButton(
            tooltip: 'Recurring spending',
            icon: Badge(
              isLabelVisible: s.recurring.isNotEmpty,
              label: Text('${s.recurring.length}'),
              child: const Icon(Icons.repeat_rounded),
            ),
            onPressed: () => context.push('/spending/recurring'),
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
          if (_allTime) const SizedBox(height: 12) else const MonthBar(),
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Search notes, categories, amounts',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => setState(_search.clear),
                    ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(28)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _FilterMenu<String>(
                label: 'Category',
                value: _category,
                display: _category == null ? null : s.category(_category!).name,
                options: {for (final c in s.categories) c.id: c.name},
                onChanged: (v) => setState(() => _category = v),
              ),
              const SizedBox(width: 8),
              _FilterMenu<String>(
                label: 'Paid with',
                value: _card,
                display: _card == null
                    ? null
                    : _card == _cashFilter
                        ? 'Cash / bank'
                        : s.cards.where((c) => c.id == _card).firstOrNull?.name,
                options: {
                  _cashFilter: 'Cash / bank',
                  for (final c in s.cards) c.id: c.name,
                },
                onChanged: (v) => setState(() => _card = v),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('All months'),
                selected: _allTime,
                onSelected: (v) => setState(() => _allTime = v),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              title: Text(_filtering
                  ? '${txns.length} matching ${txns.length == 1 ? 'purchase' : 'purchases'}'
                  : _allTime
                      ? 'Total spent, all time'
                      : 'Total spent this month'),
              subtitle: const Text('Excludes fixed bills and debt payments'),
              trailing: Text(money(total, s.currency),
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
            ),
          ),
          if (txns.isEmpty)
            EmptyHint(
                _filtering ? Icons.search_off_rounded : Icons.shopping_bag_outlined,
                _filtering
                    ? 'Nothing matches. Try clearing a filter or searching all months.'
                    : 'Nothing logged this month.\nTap “Add spending” when you buy something.'),
          for (final e in groups.entries) ...[
            SectionHeader(_allTime ? dayLabelWithYear(e.key) : dayLabel(e.key),
                action: Text(
                    money(e.value.fold<double>(0, (a, t) => a + t.amount), s.currency),
                    style: Theme.of(context).textTheme.bodyMedium)),
            Card(
              child: Column(children: [
                for (final t in e.value) _TxnTile(t, s),
              ]),
            ),
          ],
        ],
      ),
    );
  }
}

/// A chip that opens a menu of choices, with an "Any" option to clear it.
class _FilterMenu<T> extends StatelessWidget {
  const _FilterMenu({
    required this.label,
    required this.value,
    required this.display,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final T? value;
  final String? display;
  final Map<T, String> options;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) => PopupMenuButton<T?>(
        tooltip: label,
        onSelected: onChanged,
        itemBuilder: (_) => [
          PopupMenuItem<T?>(value: null, child: Text('Any ${label.toLowerCase()}')),
          for (final e in options.entries)
            PopupMenuItem<T?>(value: e.key, child: Text(e.value)),
        ],
        child: IgnorePointer(
          child: FilterChip(
            label: Text(display ?? label),
            selected: value != null,
            onSelected: (_) {},
            avatar: const Icon(Icons.arrow_drop_down_rounded),
          ),
        ),
      );
}

class _TxnTile extends ConsumerWidget {
  const _TxnTile(this.t, this.s);
  final Txn t;
  final BudgetState s;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cat = s.category(t.categoryId);
    final card = s.cards.where((c) => c.id == t.cardId).firstOrNull;
    final catNames = t.isSplit
        ? t.parts.map((p) => s.category(p.categoryId).name).join(' + ')
        : cat.name;
    return Dismissible(
      key: ValueKey(t.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Semantic.bad,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      onDismissed: (_) => ref.read(budgetProvider.notifier).deleteTxn(t.id),
      child: ListTile(
        onTap: () => showTxnForm(context, txn: t),
        leading: t.isSplit
            ? CircleAvatar(
                backgroundColor: cat.color.withValues(alpha: 0.16),
                child: Icon(Icons.call_split_rounded, color: cat.color),
              )
            : CategoryAvatar(cat),
        title: Text(t.note.isEmpty ? catNames : t.note),
        subtitle: Text([catNames, card?.name ?? 'Cash / bank'].join(' · '),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Text(money(t.amount, s.currency),
            style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}
