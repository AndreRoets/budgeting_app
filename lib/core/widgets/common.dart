import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/budget/application/budget_provider.dart';
import '../../features/budget/domain/models.dart';
import '../../features/budget/domain/period.dart';
import '../format.dart';

/// Colours that carry meaning across the app.
class Semantic {
  static const good = Color(0xFF2E9E5B);
  static const warn = Color(0xFFE39B1B);
  static const bad = Color(0xFFD64545);
}

Color progressColor(double ratio) => ratio >= 1
    ? Semantic.bad
    : ratio >= 0.85
        ? Semantic.warn
        : Semantic.good;

class CategoryAvatar extends StatelessWidget {
  const CategoryAvatar(this.category, {super.key, this.size = 40});
  final Category category;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: category.color.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(size * 0.32),
        ),
        child: Icon(category.icon, color: category.color, size: size * 0.55),
      );
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action});
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Row(children: [
          Expanded(
            child: Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ),
          ?action,
        ]),
      );
}

class EmptyHint extends StatelessWidget {
  const EmptyHint(this.icon, this.text, {super.key});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
      child: Column(children: [
        Icon(icon, size: 40, color: c.withValues(alpha: 0.6)),
        const SizedBox(height: 10),
        Text(text, textAlign: TextAlign.center, style: TextStyle(color: c)),
      ]),
    );
  }
}

/// Month switcher used at the top of the main screens.
class MonthBar extends ConsumerWidget {
  const MonthBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(selectedMonthProvider);
    final notifier = ref.read(selectedMonthProvider.notifier);
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      IconButton(
        tooltip: 'Previous month',
        onPressed: () => notifier.shift(-1),
        icon: const Icon(Icons.chevron_left_rounded),
      ),
      Flexible(
        child: TextButton(
          onPressed: notifier.reset,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(ref.watch(budgetProvider).label(month),
                maxLines: 1,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ),
        ),
      ),
      IconButton(
        tooltip: 'Next month',
        onPressed: () => notifier.shift(1),
        icon: const Icon(Icons.chevron_right_rounded),
      ),
    ]);
  }
}

class ProgressBar extends StatelessWidget {
  const ProgressBar({super.key, required this.value, this.color, this.height = 8, this.track});
  final double value;
  final Color? color;
  final double height;

  /// Track colour; defaults to a faint tint of the text colour.
  final Color? track;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: LinearProgressIndicator(
          value: value.clamp(0.0, 1.0),
          minHeight: height,
          color: color ?? progressColor(value),
          backgroundColor: track ??
              Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08),
        ),
      );
}

class DonutSlice {
  const DonutSlice(this.value, this.color);
  final double value;
  final Color color;
}

class DonutChart extends StatelessWidget {
  const DonutChart({
    super.key,
    required this.slices,
    this.size = 150,
    this.stroke = 20,
    this.child,
  });
  final List<DonutSlice> slices;
  final double size;
  final double stroke;
  final Widget? child;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _DonutPainter(
            slices,
            stroke,
            Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08),
          ),
          child: Center(child: child),
        ),
      );
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.slices, this.stroke, this.trackColor);
  final double stroke;
  final List<DonutSlice> slices;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {

    final rect = Offset.zero & size;
    final arcRect = rect.deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;

    canvas.drawArc(arcRect, 0, math.pi * 2, false, paint..color = trackColor);

    final total = slices.fold<double>(0, (a, s) => a + s.value);
    if (total <= 0) return;
    var start = -math.pi / 2;
    const gap = 0.03;
    for (final s in slices.where((s) => s.value > 0)) {
      final sweep = s.value / total * math.pi * 2;
      final drawn = slices.length > 1 ? math.max(sweep - gap, 0.001) : sweep;
      canvas.drawArc(arcRect, start + (sweep - drawn) / 2, drawn, false,
          paint..color = s.color);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.slices != slices || old.trackColor != trackColor || old.stroke != stroke;
}

/// A text field that accepts a positive money amount.
class AmountField extends StatelessWidget {
  const AmountField({
    super.key,
    required this.controller,
    this.label = 'Amount',
    this.allowZero = false,
    this.required = true,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String label;
  final bool allowZero;
  final bool required;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        autofocus: autofocus,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        validator: (v) {
          if ((v ?? '').trim().isEmpty) return required ? 'Enter an amount' : null;
          final n = parseAmount(v);
          if (n == null) return 'Not a valid number';
          if (n < 0 || (n == 0 && !allowZero)) return 'Must be more than 0';
          return null;
        },
      );
}

class CategoryDropdown extends StatelessWidget {
  const CategoryDropdown({
    super.key,
    required this.categories,
    required this.value,
    required this.onChanged,
    required this.onCreate,
  });

  final List<Category> categories;
  final String value;
  final ValueChanged<String> onChanged;

  /// Opens the new-category form; returns the created category id, if any.
  final Future<String?> Function() onCreate;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          DropdownButtonFormField<String>(
            isExpanded: true,
            // Keyed so a newly created/selected category is reflected.
            key: ValueKey('$value|${categories.length}'),
            initialValue: categories.any((c) => c.id == value) ? value : otherCategoryId,
            decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
            items: [
              for (final c in categories)
                DropdownMenuItem(
                  value: c.id,
                  child: Row(children: [
                    Icon(c.icon, color: c.color, size: 20),
                    const SizedBox(width: 10),
                    Text(c.name),
                  ]),
                ),
            ],
            onChanged: (v) => v == null ? null : onChanged(v),
          ),
          TextButton.icon(
            onPressed: () async {
              final id = await onCreate();
              if (id != null) onChanged(id);
            },
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('New category (e.g. Coffee)'),
          ),
        ],
      );
}

/// Shows a form in a keyboard-aware bottom sheet.
Future<T?> showFormSheet<T>(BuildContext context, Widget child) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 0, 20, MediaQuery.viewInsetsOf(ctx).bottom + 20),
        child: SingleChildScrollView(child: child),
      ),
    );

Future<bool> confirmDelete(BuildContext context, String what) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Delete $what?'),
      content: const Text('This cannot be undone.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Semantic.bad),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return ok ?? false;
}

Widget sheetTitle(BuildContext context, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(text,
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.w700)),
    );

/// Cyan-to-blue gradient used for progress and the main add button.
const auroraGradient = LinearGradient(colors: [Color(0xFF38BDF8), Color(0xFF3B82F6)]);

/// A progress bar whose fill is the aurora gradient.
class GradientBar extends StatelessWidget {
  const GradientBar({super.key, required this.value, this.height = 8, this.track});
  final double value;
  final double height;
  final Color? track;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: Container(
          height: height,
          color: track ?? Colors.white.withValues(alpha: 0.18),
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: value.clamp(0.02, 1.0),
            child: Container(
              decoration: BoxDecoration(
                gradient: auroraGradient,
                borderRadius: BorderRadius.circular(height),
              ),
            ),
          ),
        ),
      );
}

/// The app's main floating button: a gradient pill.
class AppFab extends StatelessWidget {
  const AppFab({super.key, required this.onPressed, required this.icon, required this.label});
  final VoidCallback onPressed;
  final Widget icon;
  final Widget label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: auroraGradient,
          borderRadius: BorderRadius.circular(99),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF3B82F6).withValues(alpha: 0.45),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(99),
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: IconTheme.merge(
                data: const IconThemeData(color: Color(0xFF04102A), size: 22),
                child: DefaultTextStyle.merge(
                  style: const TextStyle(
                      color: Color(0xFF04102A), fontWeight: FontWeight.w800, fontSize: 15),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    icon,
                    const SizedBox(width: 10),
                    label,
                  ]),
                ),
              ),
            ),
          ),
        ),
      );
}
