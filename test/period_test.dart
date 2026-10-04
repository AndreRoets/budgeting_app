import 'package:budgeting_app/features/budget/domain/models.dart';
import 'package:budgeting_app/features/budget/domain/period.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final sep = DateTime(2026, 9);

  group('period boundaries with a 25th start', () {
    test('a period runs from the 25th to the 24th', () {
      expect(periodStartOf(25, sep), DateTime(2026, 9, 25));
      expect(periodEndOf(25, sep), DateTime(2026, 10, 25));
      expect(periodLastDay(25, sep), DateTime(2026, 10, 24));
    });

    test('a date belongs to the period it falls in', () {
      expect(periodKeyFor(25, DateTime(2026, 9, 25)), sep);
      expect(periodKeyFor(25, DateTime(2026, 10, 24)), sep);
      expect(periodKeyFor(25, DateTime(2026, 9, 24)), DateTime(2026, 8));
      expect(periodKeyFor(25, DateTime(2026, 10, 25)), DateTime(2026, 10));
      expect(periodKeyFor(25, DateTime(2026, 9, 26, 15, 30)), sep);
    });

    test('a period can cross the new year', () {
      final dec = DateTime(2026, 12);
      expect(periodKeyFor(25, DateTime(2027, 1, 3)), dec);
      expect(periodKeyFor(25, DateTime(2027, 1, 25)), DateTime(2027, 1));
      expect(periodLastDay(25, dec), DateTime(2027, 1, 24));
    });

    test('inPeriod includes the first day and excludes the next start', () {
      expect(inPeriod(25, sep, DateTime(2026, 9, 25)), isTrue);
      expect(inPeriod(25, sep, DateTime(2026, 10, 24, 23, 59)), isTrue);
      expect(inPeriod(25, sep, DateTime(2026, 10, 25)), isFalse);
      expect(inPeriod(25, sep, DateTime(2026, 9, 24)), isFalse);
    });

    test('with a start day of 1 a period is a calendar month', () {
      expect(periodStartOf(1, sep), DateTime(2026, 9, 1));
      expect(periodLastDay(1, sep), DateTime(2026, 9, 30));
      expect(periodKeyFor(1, DateTime(2026, 9, 30)), sep);
      expect(periodKeyFor(1, DateTime(2026, 10, 1)), DateTime(2026, 10));
    });
  });

  group('a start day that some months do not have', () {
    test('it falls on the last day of a short month and periods stay joined', () {
      expect(periodStartOf(31, DateTime(2026, 2)), DateTime(2026, 2, 28));
      expect(periodStartOf(31, DateTime(2026, 4)), DateTime(2026, 4, 30));
      expect(periodStartOf(31, DateTime(2028, 2)), DateTime(2028, 2, 29));
      for (var m = 1; m <= 12; m++) {
        final key = DateTime(2026, m);
        expect(periodEndOf(31, key), periodStartOf(31, DateTime(2026, m + 1)));
      }
    });

    test('every day of the year belongs to exactly one period', () {
      for (final start in [1, 15, 25, 29, 30, 31]) {
        var day = DateTime(2026);
        while (day.year == 2026) {
          final key = periodKeyFor(start, day);
          expect(inPeriod(start, key, day), isTrue, reason: '$day start $start');
          expect(inPeriod(start, DateTime(key.year, key.month + 1), day), isFalse);
          expect(inPeriod(start, DateTime(key.year, key.month - 1), day), isFalse);
          day = DateTime(day.year, day.month, day.day + 1);
        }
      }
    });
  });

  group('dates and days left', () {
    test('today is used when the period is current', () {
      final now = DateTime(2026, 9, 26, 10);
      expect(dateInPeriod(25, sep, 5, now), DateTime(2026, 9, 26));
    });

    test('a due day is placed on the right side of the pay day', () {
      final later = DateTime(2027, 1, 1);
      expect(dateInPeriod(25, sep, 28, later), DateTime(2026, 9, 28));
      expect(dateInPeriod(25, sep, 25, later), DateTime(2026, 9, 25));
      expect(dateInPeriod(25, sep, 5, later), DateTime(2026, 10, 5));
      expect(dateInPeriod(25, sep, 24, later), DateTime(2026, 10, 24));
      expect(dateInPeriod(25, sep, null, later), DateTime(2026, 9, 25));
    });

    test('a due day of 31 is clamped in a short month', () {
      expect(dateInPeriod(25, DateTime(2026, 1), 31, DateTime(2027, 1, 1)), DateTime(2026, 1, 31));
      expect(dateInPeriod(1, DateTime(2026, 2), 31, DateTime(2027, 1, 1)), DateTime(2026, 2, 28));
    });

    test('days left counts today and runs to the day before the next pay day', () {
      expect(daysLeftInPeriod(25, sep, DateTime(2026, 9, 26)), 29);
      expect(daysLeftInPeriod(25, sep, DateTime(2026, 10, 24)), 1);
      expect(daysLeftInPeriod(25, sep, DateTime(2026, 9, 25)), 30);
      expect(daysLeftInPeriod(25, sep, DateTime(2026, 10, 25)), isNull);
      expect(daysLeftInPeriod(25, DateTime(2026, 10), DateTime(2026, 9, 26)), 31);
    });

    test('days left for a calendar month matches the old behaviour', () {
      expect(daysLeftInPeriod(1, DateTime(2026, 5), DateTime(2026, 5, 22)), 10);
      expect(daysLeftInPeriod(1, DateTime(2026, 4), DateTime(2026, 5, 22)), isNull);
      expect(daysLeftInPeriod(1, DateTime(2026, 6), DateTime(2026, 5, 22)), 30);
    });

    test('bills are ordered from the pay day round to the day before it', () {
      final days = <int?>[3, 28, 25, 24, 10, null];
      days.sort((a, b) => dueOrder(25, a).compareTo(dueOrder(25, b)));
      expect(days, [25, 28, 3, 10, 24, null]);
    });
  });

  group('labels', () {
    test('a pay-day period is written as a date range', () {
      expect(periodLabel(25, sep), '25 Sep – 24 Oct 2026');
      expect(periodLabel(25, DateTime(2026, 12)), '25 Dec 2026 – 24 Jan 2027');
    });

    test('a calendar month keeps its name', () {
      expect(periodLabel(1, sep), 'September 2026');
      expect(periodEndLabel(1, sep), 'September 2026');
    });

    test('the end label is the last day of the period', () {
      expect(periodEndLabel(25, sep), '24 Oct 2026');
    });

    test('a run of periods is summarised', () {
      expect(periodSpanLabel(1, sep, DateTime(2027, 2)), 'September 2026 to February 2027');
      expect(periodSpanLabel(25, sep, DateTime(2027, 2)), '25 Sep 2026 to 24 Mar 2027');
      expect(periodSpanLabel(25, sep, sep), '25 Sep – 24 Oct 2026');
    });
  });

  group('choosing the start day', () {
    BudgetState with_(List<Income> incomes, {int start = 0}) =>
        BudgetState.initial().copyWith(incomes: incomes, periodStartDay: start);

    test('it follows the pay day of the largest regular income', () {
      final s = with_(const [
        Income(id: 'a', name: 'Side', amount: 2000, payDay: 10),
        Income(id: 'b', name: 'Salary', amount: 20000, payDay: 25),
      ]);
      expect(s.startDay, 25);
    });

    test('it falls back to the 1st with no pay day, and ignores one-off income', () {
      expect(with_(const []).startDay, 1);
      expect(with_(const [Income(id: 'a', name: 'Salary', amount: 100)]).startDay, 1);
      expect(
          with_(const [
            Income(id: 'a', name: 'Bonus', amount: 9000, payDay: 15, oneOffMonth: '2026-09'),
          ]).startDay,
          1);
    });

    test('a chosen day wins over the pay day', () {
      final s = with_(const [Income(id: 'a', name: 'Salary', amount: 100, payDay: 25)], start: 1);
      expect(s.startDay, 1);
    });

    test('it is saved, and older saves load as follow-my-pay-day', () {
      final s = with_(const [], start: 20);
      expect(BudgetState.fromJson(s.toJson()).periodStartDay, 20);
      final old = s.toJson()..remove('periodStartDay');
      expect(BudgetState.fromJson(old).periodStartDay, 0);
    });

    test('the state helpers use the resolved start day', () {
      final s = with_(const [Income(id: 'a', name: 'Salary', amount: 100, payDay: 25)]);
      expect(s.periodKey(DateTime(2026, 9, 24)), DateTime(2026, 8));
      expect(s.periodStart(sep), DateTime(2026, 9, 25));
      expect(s.label(sep), '25 Sep – 24 Oct 2026');
    });
  });
}
