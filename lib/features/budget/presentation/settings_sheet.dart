import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/widgets/common.dart';
import '../application/budget_provider.dart';
import '../domain/models.dart';
import '../domain/period.dart';

Future<void> showSettingsSheet(BuildContext context) =>
    showFormSheet(context, const _SettingsSheet());

/// Just the "which day does your budget month start on" picker, on its own.
Future<void> showBudgetMonthSheet(BuildContext context) =>
    showFormSheet(
        context,
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          sheetTitle(context, 'Budget month'),
          const BudgetMonthPicker(),
        ]));

/// The budget-month start-day dropdown, with its explanation. Shared by the
/// Settings sheet and the Income tab, where it sits next to salary and pay day.
class BudgetMonthPicker extends ConsumerWidget {
  const BudgetMonthPicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(budgetProvider);
    final n = ref.read(budgetProvider.notifier);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(
        'Pick the day your budget month starts, usually your pay day. Right now it runs ${s.label(s.currentPeriod)}.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 10),
      DropdownButtonFormField<int>(
        key: ValueKey('startDay${s.periodStartDay}'),
        isExpanded: true,
        initialValue: s.periodStartDay.clamp(0, 31),
        decoration: const InputDecoration(border: OutlineInputBorder()),
        items: [
          DropdownMenuItem(value: 0, child: Text(_autoLabel(s))),
          for (var d = 1; d <= 31; d++)
            DropdownMenuItem(
              value: d,
              child: Text(d == 1 ? 'Calendar month (the 1st)' : 'Starts on the ${ordinal(d)}'),
            ),
        ],
        onChanged: (v) => n.setPeriodStartDay(v ?? 0),
      ),
    ]);
  }
}

class _SettingsSheet extends ConsumerWidget {
  const _SettingsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(budgetProvider);
    final n = ref.read(budgetProvider.notifier);
    final label = Theme.of(context).textTheme.titleSmall;
    const gap = SizedBox(height: 22);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      sheetTitle(context, 'Settings'),
      Text('Appearance', style: label),
      const SizedBox(height: 10),
      SegmentedButton<int>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: 0, icon: Icon(Icons.brightness_auto_rounded), label: Text('Auto')),
          ButtonSegment(value: 1, icon: Icon(Icons.light_mode_rounded), label: Text('Light')),
          ButtonSegment(value: 2, icon: Icon(Icons.dark_mode_rounded), label: Text('Dark')),
        ],
        selected: {s.themeMode},
        onSelectionChanged: (v) => n.setThemeMode(v.first),
      ),
      gap,
      Text('Budget month', style: label),
      const SizedBox(height: 4),
      const BudgetMonthPicker(),
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text('Salary and pay day are set on the Budget tab, under Income.',
            style: Theme.of(context).textTheme.bodySmall),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: s.carryOver,
        onChanged: n.setCarryOver,
        title: const Text('Carry over what is left'),
        subtitle: const Text(
            'Money left at the end of a budget month is added to the next one, and overspending is taken off it.'),
      ),
      gap,
      Text('Overview: spending highlight', style: label),
      const SizedBox(height: 4),
      Text('Choose what the "Spent" figure on the overview shows.',
          style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 10),
      DropdownButtonFormField<String?>(
        isExpanded: true,
        initialValue: s.categories.any((c) => c.id == s.focusCategoryId)
            ? s.focusCategoryId
            : null,
        decoration: const InputDecoration(border: OutlineInputBorder()),
        items: [
          const DropdownMenuItem(value: null, child: Text('All spending')),
          for (final c in s.categories)
            DropdownMenuItem(
              value: c.id,
              child: Row(children: [
                Icon(c.icon, color: c.color, size: 20),
                const SizedBox(width: 10),
                Text(c.name),
              ]),
            ),
        ],
        onChanged: n.setFocusCategory,
      ),
      gap,
      Text('Overview: what I can spend', style: label),
      const SizedBox(height: 4),
      Text('Spreads what is left this month over the days remaining.',
          style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 10),
      SegmentedButton<int>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: PaceMode.off, label: Text('Off')),
          ButtonSegment(value: PaceMode.day, label: Text('Day')),
          ButtonSegment(value: PaceMode.week, label: Text('Week')),
          ButtonSegment(value: PaceMode.both, label: Text('Both')),
        ],
        selected: {s.paceMode},
        onSelectionChanged: (v) => n.setPaceMode(v.first),
      ),
      gap,
      Text('Currency', style: label),
      const SizedBox(height: 10),
      Wrap(spacing: 8, children: [
        for (final c in const [r'$', 'R', '€', '£', '¥', '₹'])
          ChoiceChip(
            label: Text(c),
            selected: s.currency == c,
            onSelected: (_) => n.setCurrency(c),
          ),
      ]),
      const SizedBox(height: 12),
    ]);
  }
}

/// Label for the option that follows the main income's pay day.
String _autoLabel(BudgetState s) {
  final auto = s.copyWith(periodStartDay: 0).startDay;
  final hasPayDay = s.incomes.any((i) => i.payDay != null && i.oneOffMonth == null);
  return hasPayDay
      ? 'Follow my pay day (${ordinal(auto)})'
      : 'Follow my pay day (none set yet)';
}
