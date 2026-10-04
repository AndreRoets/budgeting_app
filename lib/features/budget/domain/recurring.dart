import 'models.dart';

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// The dates a rule falls on, after [after] (exclusive; null = from the start)
/// up to and including [today].
List<DateTime> occurrences(RecurringSpend r, DateTime today, {DateTime? after}) {
  final end = _day(today);
  final start = _day(r.start);
  final from = after == null ? null : _day(after);
  final out = <DateTime>[];

  bool wanted(DateTime d) => from == null || d.isAfter(from);

  switch (r.repeat) {
    case Repeat.daily:
      for (var d = start; !d.isAfter(end); d = DateTime(d.year, d.month, d.day + 1)) {
        if (wanted(d)) out.add(d);
      }
    case Repeat.weekly:
      for (var d = start; !d.isAfter(end); d = DateTime(d.year, d.month, d.day + 7)) {
        if (wanted(d)) out.add(d);
      }
    case Repeat.monthly:
      // Keep the start day, clamped for short months (31st -> 28th/30th).
      for (var i = 0;; i++) {
        final last = DateTime(start.year, start.month + i + 1, 0).day;
        final d = DateTime(start.year, start.month + i,
            start.day > last ? last : start.day);
        if (d.isAfter(end)) break;
        if (wanted(d)) out.add(d);
      }
  }
  return out;
}

/// Transactions to add (and updated rules) so every active rule is logged up
/// to [today]. Ids are derived from rule + date so running twice adds nothing.
({List<Txn> txns, List<RecurringSpend> rules}) materializeRecurring(
  List<RecurringSpend> rules,
  DateTime today,
) {
  final txns = <Txn>[];
  final updated = <RecurringSpend>[];
  for (final r in rules) {
    if (!r.active) {
      updated.add(r);
      continue;
    }
    final dates = occurrences(r, today, after: r.through);
    for (final d in dates) {
      txns.add(Txn(
        id: 'rec-${r.id}-${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}',
        date: d,
        amount: r.amount,
        categoryId: r.categoryId,
        cardId: r.cardId,
        note: r.note,
      ));
    }
    updated.add(dates.isEmpty ? r : r.copyWith(through: dates.last));
  }
  return (txns: txns, rules: updated);
}
