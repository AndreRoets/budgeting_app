import 'package:budgeting_app/features/budget/domain/models.dart';
import 'package:budgeting_app/features/budget/domain/summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final may = DateTime(2026, 5);
  DateTime day(int d) => DateTime(2026, 5, d);

  BudgetState base({List<Txn> txns = const []}) => BudgetState.initial().copyWith(
        categories: [
          for (final c in BudgetState.initial().categories)
            c.copyWith(budget: c.id == 'groceries' ? 2000 : 0),
        ],
        incomes: const [Income(id: 'i', name: 'Salary', amount: 10000)],
        bills: const [Bill(id: 'r', name: 'Rent', amount: 4000, categoryId: 'housing')],
        cards: const [
          PaymentCard(id: 'cc', name: 'Visa', colorIndex: 0, limit: 8000),
          PaymentCard(id: 'db', name: 'Debit', colorIndex: 1, isCredit: false),
        ],
        txns: txns,
      );

  double left(BudgetState s) => summarize(s, may).left;
  double owed(BudgetState s) => summarizeCard(s, s.cards.first, may).owed;

  test('left to spend starts as income minus bills', () {
    expect(left(base()), 6000);
  });

  test('a cash purchase comes out of left to spend', () {
    final s = base(txns: [Txn(id: '1', date: day(2), amount: 250, categoryId: 'groceries')]);
    expect(left(s), 5750);
  });

  test('a debit card purchase comes out of left to spend', () {
    final s = base(txns: [
      Txn(id: '1', date: day(2), amount: 250, categoryId: 'groceries', cardId: 'db'),
    ]);
    expect(left(s), 5750);
  });

  test('a credit card purchase leaves left to spend alone and adds to debt', () {
    final s = base(txns: [
      Txn(id: '1', date: day(2), amount: 900, categoryId: 'groceries', cardId: 'cc'),
    ]);
    expect(left(s), 6000);
    expect(owed(s), 900);
    expect(summarize(s, may).creditSpent, 900);
  });

  test('paying the credit card comes out of left to spend and lowers the debt', () {
    final s = base(txns: [
      Txn(id: '1', date: day(2), amount: 900, categoryId: 'groceries', cardId: 'cc'),
      Txn(id: '2', date: day(20), amount: 400, cardId: 'cc', isPayment: true),
    ]);
    expect(left(s), 5600);
    expect(owed(s), 500);
  });

  test('a credit card purchase still counts against its category budget', () {
    final s = base(txns: [
      Txn(id: '1', date: day(2), amount: 900, categoryId: 'groceries', cardId: 'cc'),
      Txn(id: '2', date: day(3), amount: 100, categoryId: 'groceries'),
    ]);
    final groceries =
        summarize(s, may).categories.firstWhere((c) => c.category.id == 'groceries');
    expect(groceries.spent, 1000);
    expect(groceries.remaining, 1000);
    expect(groceries.creditSpent, 900);
    expect(groceries.fromIncome, 100);
  });

  test('a split purchase on credit is treated as credit in every category', () {
    final s = base(txns: [
      Txn(
        id: '1', date: day(2), amount: 600, categoryId: 'groceries', cardId: 'cc',
        splits: const [SplitPart('groceries', 400), SplitPart('fun', 200)],
      ),
    ]);
    final sum = summarize(s, may);
    expect(sum.left, 6000);
    expect(sum.creditSpent, 600);
    expect(sum.categories.firstWhere((c) => c.category.id == 'fun').creditSpent, 200);
  });

  test('a card that was deleted no longer counts as credit', () {
    final s = base(txns: [
      Txn(id: '1', date: day(2), amount: 300, categoryId: 'groceries', cardId: 'gone'),
    ]);
    expect(left(s), 5700);
  });

  test('the monthly trend counts money that left income, not credit purchases', () {
    final s = base(txns: [
      Txn(id: '1', date: day(2), amount: 900, categoryId: 'groceries', cardId: 'cc'),
      Txn(id: '2', date: day(3), amount: 100, categoryId: 'groceries'),
      Txn(id: '3', date: day(20), amount: 400, cardId: 'cc', isPayment: true),
    ]);
    final m = monthlyTrend(s, may).last;
    expect(m.spent, 500); // 100 cash + 400 paid to the card
    expect(m.out, 4500);
    expect(m.net, 5500);
  });

  test('left to spend can go below zero when payments exceed income', () {
    final s = base(txns: [
      Txn(id: '1', date: day(2), amount: 7000, cardId: 'cc', isPayment: true),
    ]);
    expect(left(s), -1000);
  });
}
