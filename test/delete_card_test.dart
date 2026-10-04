import 'package:budgeting_app/app.dart';
import 'package:budgeting_app/core/router/app_router.dart';
import 'package:budgeting_app/features/budget/application/budget_provider.dart';
import 'package:budgeting_app/features/budget/domain/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _launch(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(412, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  appRouter.go('/');
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [prefsProvider.overrideWithValue(prefs)],
    child: const App(),
  ));
  await tester.pumpAndSettle();
  final c = ProviderScope.containerOf(tester.element(find.byType(App)));
  c.read(budgetProvider.notifier)
    ..saveCard(const PaymentCard(id: 'c', name: 'Visa', colorIndex: 0, openingBalance: 500))
    ..saveTxn(Txn(id: 't', date: DateTime.now(), amount: 200, categoryId: 'groceries', cardId: 'c'));
  await tester.pumpAndSettle();
  return c;
}

Future<void> _swipe(WidgetTester tester, Finder finder) async {
  await tester.drag(finder, const Offset(-500, 0));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('swiping a card on the Cards tab asks to confirm, then deletes it and keeps its spending as cash',
      (tester) async {
    final c = await _launch(tester);
    await tester.tap(find.descendant(
        of: find.byType(NavigationBar), matching: find.text('Cards')));
    await tester.pumpAndSettle();
    expect(c.read(budgetProvider).cards.any((x) => x.id == 'c'), isTrue);

    await _swipe(tester, find.text('Visa'));
    expect(find.text('Delete Visa?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(c.read(budgetProvider).cards.any((x) => x.id == 'c'), isTrue);

    await _swipe(tester, find.text('Visa'));
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();

    expect(c.read(budgetProvider).cards.any((x) => x.id == 'c'), isFalse);
    expect(find.text('Visa'), findsNothing);
    final txn = c.read(budgetProvider).txns.single;
    expect(txn.cardId, isNull);
    expect(txn.amount, 200);
  });

  testWidgets('a credit card can be deleted from its menu on the Budget tab', (tester) async {
    final c = await _launch(tester);
    await tester.tap(find.descendant(
        of: find.byType(NavigationBar), matching: find.text('Budget')));
    await tester.pumpAndSettle();
    expect(find.text('Visa'), findsOneWidget);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('Delete card'), findsOneWidget);
    await tester.tap(find.text('Delete card'));
    await tester.pumpAndSettle();
    expect(find.text('Delete Visa?'), findsOneWidget);
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();

    expect(c.read(budgetProvider).cards, isEmpty);
    expect(find.text('Visa'), findsNothing);
  });

  testWidgets('cancelling from the Budget tab menu keeps the card', (tester) async {
    final c = await _launch(tester);
    await tester.tap(find.descendant(
        of: find.byType(NavigationBar), matching: find.text('Budget')));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete card'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(c.read(budgetProvider).cards.single.id, 'c');
  });
}
