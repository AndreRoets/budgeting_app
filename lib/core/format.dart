import 'package:intl/intl.dart';

final _num = NumberFormat('#,##0.00');
final _monthFmt = DateFormat('MMMM yyyy');
final _dayFmt = DateFormat('EEE, d MMM');

String money(double v, String symbol) {
  final neg = v < -0.004;
  return '${neg ? '-' : ''}$symbol${_num.format(v.abs())}';
}

String monthLabel(DateTime d) => _monthFmt.format(d);
String dayLabel(DateTime d) => _dayFmt.format(d);

/// Parses user input such as "1,250.50"; returns null if not a valid number.
double? parseAmount(String? s) {
  if (s == null) return null;
  return double.tryParse(s.trim().replaceAll(',', '').replaceAll(' ', ''));
}

String ordinal(int n) {
  if (n >= 11 && n <= 13) return '${n}th';
  return switch (n % 10) { 1 => '${n}st', 2 => '${n}nd', 3 => '${n}rd', _ => '${n}th' };
}

final _shortFmt = DateFormat('d MMM');
String shortDate(DateTime d) => _shortFmt.format(d);

final _dayYearFmt = DateFormat('EEE, d MMM yyyy');
String dayLabelWithYear(DateTime d) => _dayYearFmt.format(d);
