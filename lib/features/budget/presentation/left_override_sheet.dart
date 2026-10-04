import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/widgets/common.dart';
import '../application/budget_provider.dart';
import '../domain/period.dart';
import '../domain/summary.dart';

/// Lets the user correct "left to spend" for the selected period in one go,
/// for when the period has already started and re-entering everything that
/// happened so far isn't worth the effort. Saved as a delta on top of what's
/// calculated, so it keeps applying as more is logged afterwards.
Future<void> showLeftOverrideSheet(BuildContext context) =>
    showFormSheet(context, const _LeftOverrideForm());

class _LeftOverrideForm extends ConsumerStatefulWidget {
  const _LeftOverrideForm();

  @override
  ConsumerState<_LeftOverrideForm> createState() => _LeftOverrideFormState();
}

class _LeftOverrideFormState extends ConsumerState<_LeftOverrideForm> {
  final _key = GlobalKey<FormState>();
  late final TextEditingController _amount;

  @override
  void initState() {
    super.initState();
    final s = ref.read(budgetProvider);
    final month = ref.read(selectedMonthProvider);
    _amount = TextEditingController(text: summarize(s, month).left.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(budgetProvider);
    final month = ref.watch(selectedMonthProvider);
    final cur = s.currency;
    final sum = summarize(s, month);
    final hasOverride = s.hasLeftAdjustment(month);
    // What it would be without the override, so the difference the user
    // enters is what gets stored (and it stays valid as more is logged).
    final calculated = sum.left - sum.adjustment;

    return Form(
      key: _key,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        sheetTitle(context, "Set what's left"),
        Text(
          "If ${s.label(month)} has already started and entering everything "
          "so far is a hassle, just say how much you actually have left. "
          "It'll keep adjusting as you log anything new.",
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _amount,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]'))],
          decoration: const InputDecoration(
              labelText: "What's actually left", border: OutlineInputBorder()),
          validator: (v) {
            if ((v ?? '').trim().isEmpty) return 'Enter an amount';
            return parseAmount(v) == null ? 'Not a valid number' : null;
          },
        ),
        const SizedBox(height: 10),
        Text('Calculated from what you have entered: ${money(calculated, cur)}',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 16),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          onPressed: () {
            if (!_key.currentState!.validate()) return;
            final entered = parseAmount(_amount.text)!;
            ref.read(budgetProvider.notifier).setLeftAdjustment(month, entered - calculated);
            Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
        if (hasOverride) ...[
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () {
              ref.read(budgetProvider.notifier).clearLeftAdjustment(month);
              Navigator.pop(context);
            },
            child: const Text('Use the calculated amount instead'),
          ),
        ],
      ]),
    );
  }
}
