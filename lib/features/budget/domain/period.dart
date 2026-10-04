import 'package:intl/intl.dart';

import '../../../core/format.dart';
import 'models.dart';

/// A budget period runs from one pay day to the day before the next, such as
/// 25 Sep to 24 Oct. It is identified by a "key": the first day of the calendar
/// month it starts in. With a start day of 1 a period is just a calendar month.

int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

/// First day of the period [key]. A start day past the end of a short month
/// falls on that month's last day.
DateTime periodStartOf(int startDay, DateTime key) => DateTime(
    key.year, key.month, startDay.clamp(1, daysInMonth(key.year, key.month)));

/// The day after the period [key] ends, which is also where the next begins.
DateTime periodEndOf(int startDay, DateTime key) =>
    periodStartOf(startDay, DateTime(key.year, key.month + 1));

/// Key of the period that contains [date].
DateTime periodKeyFor(int startDay, DateTime date) {
  final day = DateTime(date.year, date.month, date.day);
  final thisMonth = DateTime(day.year, day.month);
  return day.isBefore(periodStartOf(startDay, thisMonth))
      ? DateTime(day.year, day.month - 1)
      : thisMonth;
}

/// Whether [date] falls inside the period [key].
bool inPeriod(int startDay, DateTime key, DateTime date) {
  final day = DateTime(date.year, date.month, date.day);
  return !day.isBefore(periodStartOf(startDay, key)) &&
      day.isBefore(periodEndOf(startDay, key));
}

/// Last day of the period [key].
DateTime periodLastDay(int startDay, DateTime key) {
  final end = periodEndOf(startDay, key);
  return DateTime(end.year, end.month, end.day - 1);
}

/// A date inside the period [key] for something that happens on [day] of the
/// month (a bill due date or a pay day). Today, when the period is current.
DateTime dateInPeriod(int startDay, DateTime key, int? day, DateTime now) {
  if (periodKeyFor(startDay, now) == key) {
    return DateTime(now.year, now.month, now.day);
  }
  final start = periodStartOf(startDay, key);
  final want = day ?? start.day;
  var date = DateTime(start.year, start.month, want.clamp(1, daysInMonth(start.year, start.month)));
  if (date.isBefore(start)) {
    final next = DateTime(start.year, start.month + 1);
    date = DateTime(next.year, next.month, want.clamp(1, daysInMonth(next.year, next.month)));
  }
  return date;
}

/// Days left in the period, counting today. Null for past periods, the whole
/// period for future ones.
int? daysLeftInPeriod(int startDay, DateTime key, DateTime now) {
  final start = periodStartOf(startDay, key);
  final end = periodEndOf(startDay, key);
  final today = DateTime(now.year, now.month, now.day);
  if (!today.isBefore(end)) return null;
  if (today.isBefore(start)) return end.difference(start).inDays;
  return end.difference(today).inDays;
}

final _dayMonth = DateFormat('d MMM');
final _dayMonthYear = DateFormat('d MMM yyyy');

/// "September 2026" for calendar months, otherwise "25 Sep – 24 Oct 2026".
String periodLabel(int startDay, DateTime key) {
  if (startDay == 1) return monthLabel(key);
  final start = periodStartOf(startDay, key);
  final last = periodLastDay(startDay, key);
  final from = start.year == last.year ? _dayMonth : _dayMonthYear;
  return '${from.format(start)} – ${_dayMonthYear.format(last)}';
}

/// Where a period ends, for "by" style labels: "October 2027" for calendar
/// months, otherwise "24 Oct 2027".
String periodEndLabel(int startDay, DateTime key) => startDay == 1
    ? monthLabel(key)
    : _dayMonthYear.format(periodLastDay(startDay, key));

/// A run of periods, such as "Sep 2026 to Aug 2027" or "25 Sep 2026 to 24 Oct 2027".
String periodSpanLabel(int startDay, DateTime first, DateTime last) {
  if (first == last) return periodLabel(startDay, first);
  if (startDay == 1) return '${monthLabel(first)} to ${monthLabel(last)}';
  return '${_dayMonthYear.format(periodStartOf(startDay, first))} to '
      '${_dayMonthYear.format(periodLastDay(startDay, last))}';
}

/// Sort position of a bill's due day within a period that starts on
/// [startDay], so a bill due on the 3rd comes after one due on the 28th.
int dueOrder(int startDay, int? dueDay) =>
    dueDay == null ? 99 : (dueDay - startDay + 31) % 31;

extension PeriodX on BudgetState {
  /// The day of the month each period starts on. When not set it follows the
  /// pay day of the largest regular income, and falls back to the 1st.
  int get startDay {
    if (periodStartDay > 0) return periodStartDay.clamp(1, 31);
    final paid = incomes.where((i) => i.payDay != null && i.oneOffMonth == null).toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));
    return paid.isEmpty ? 1 : paid.first.payDay!.clamp(1, 31);
  }

  DateTime periodKey(DateTime date) => periodKeyFor(startDay, date);
  DateTime get currentPeriod => periodKey(DateTime.now());
  DateTime periodStart(DateTime key) => periodStartOf(startDay, key);
  DateTime periodEnd(DateTime key) => periodEndOf(startDay, key);
  bool inPeriodOf(DateTime key, DateTime date) => inPeriod(startDay, key, date);
  String label(DateTime key) => periodLabel(startDay, key);
  String endLabel(DateTime key) => periodEndLabel(startDay, key);
}

/// Names the periods a plan runs through: month 1 is the current period.
class PeriodClock {
  const PeriodClock(this.startDay, this.current);
  final int startDay;

  /// Key of the current period.
  final DateTime current;

  DateTime key(int month) => DateTime(current.year, current.month + month - 1);
  String label(int month) => periodLabel(startDay, key(month));
  String endLabel(int month) => periodEndLabel(startDay, key(month));
  String span(int first, int last) =>
      periodSpanLabel(startDay, key(first), key(last));
}
