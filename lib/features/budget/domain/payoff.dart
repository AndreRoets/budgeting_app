class Payoff {
  const Payoff({required this.months, required this.interest, required this.never});

  /// Months of payments needed (0 when there is nothing owed).
  final int months;

  /// Total interest paid over that time.
  final double interest;

  /// True when the payment never covers the interest, so the debt won't clear.
  final bool never;
}

const _maxMonths = 1200;

/// Simulates paying [payment] (+ [extra]) every month on [balance] at [apr]
/// percent a year, with interest added monthly before each payment.
Payoff payoff(double balance, double payment, double apr, {double extra = 0}) {
  if (balance <= 0) return const Payoff(months: 0, interest: 0, never: false);
  final pay = payment + extra;
  final rate = apr / 100 / 12;
  var owed = balance;
  var interest = 0.0;
  for (var m = 1; m <= _maxMonths; m++) {
    final i = owed * rate;
    interest += i;
    owed += i;
    if (pay >= owed - 0.005) {
      return Payoff(months: m, interest: interest, never: false);
    }
    owed -= pay;
    // A payment that doesn't even cover interest only ever grows the debt.
    if (m == 1 && pay <= i) {
      return Payoff(months: 0, interest: interest, never: true);
    }
  }
  return Payoff(months: _maxMonths, interest: interest, never: true);
}

/// Month [months] from [from], e.g. for a "debt-free by" label.
DateTime monthsFrom(DateTime from, int months) =>
    DateTime(from.year, from.month + months);
