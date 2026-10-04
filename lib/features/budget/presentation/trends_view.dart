import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;

import '../../../core/format.dart';
import '../../../core/widgets/common.dart';
import '../application/budget_provider.dart';
import '../domain/period.dart';
import '../domain/summary.dart';

// Two-series palette, checked with the dataviz validator against the light
// and dark chart surfaces (colour-blind separation and contrast both pass).
const _incomeLight = Color(0xFF3F8EFC);
const _outLight = Color(0xFFD8623F);
const _incomeDark = Color(0xFF4A8DEB);
const _outDark = Color(0xFFDB6642);

final _compact = NumberFormat.compact();
final _monthShort = DateFormat('MMM');

class TrendsView extends ConsumerStatefulWidget {
  const TrendsView({super.key});

  @override
  ConsumerState<TrendsView> createState() => _TrendsViewState();
}

class _TrendsViewState extends ConsumerState<TrendsView> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(budgetProvider);
    final month = ref.watch(selectedMonthProvider);
    final cur = s.currency;
    final trend = monthlyTrend(s, month);
    final changes = categoryChanges(s, month);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final incomeColor = dark ? _incomeDark : _incomeLight;
    final outColor = dark ? _outDark : _outLight;
    final sel = _selected != null && _selected! < trend.length
        ? trend[_selected!]
        : trend.last;
    final hasData = trend.any((t) => t.income > 0 || t.out > 0);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: [
        const MonthBar(),
        const SectionHeader('Income vs money out'),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: !hasData
                ? const EmptyHint(Icons.bar_chart_rounded,
                    'Add income, bills and spending to see your trends.')
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      _Legend(incomeColor, 'Income'),
                      const SizedBox(width: 16),
                      _Legend(outColor, 'Money out (bills, debt, spending)'),
                    ]),
                    const SizedBox(height: 16),
                    LayoutBuilder(builder: (context, box) {
                      final chartW = box.maxWidth;
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (d) => setState(() => _selected =
                            (d.localPosition.dx / (chartW / trend.length))
                                .floor()
                                .clamp(0, trend.length - 1)),
                        child: SizedBox(
                          height: 190,
                          width: chartW,
                          child: CustomPaint(
                            painter: _TrendPainter(
                              trend: trend,
                              selected: trend.indexOf(sel),
                              incomeColor: incomeColor,
                              outColor: outColor,
                              gridColor: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.10),
                              textColor:
                                  Theme.of(context).colorScheme.onSurfaceVariant,
                              highlight: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.06),
                            ),
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 12),
                    _Detail(sel: sel, label: s.label(sel.month), cur: cur, income: incomeColor, out: outColor),
                    const SizedBox(height: 6),
                    Text('Tap a bar for the numbers of that period. Bills and debt use your current list for every period.',
                        style: Theme.of(context).textTheme.bodySmall),
                  ]),
          ),
        ),
        if (hasData) ...[
          const SectionHeader('Month by month'),
          Card(
            child: Column(children: [
              for (final t in trend.reversed)
                ListTile(
                  dense: true,
                  title: Text(s.label(t.month)),
                  subtitle: Text(
                      'In ${money(t.income, cur)} · Out ${money(t.out, cur)}'),
                  trailing: Text(
                    '${t.net >= 0 ? '+' : ''}${money(t.net, cur)}',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: t.net < 0 ? Semantic.bad : Semantic.good),
                  ),
                ),
            ]),
          ),
        ],
        SectionHeader('Spending vs last month'),
        Card(
          child: changes.isEmpty
              ? const EmptyHint(Icons.compare_arrows_rounded,
                  'Log some spending in two months to compare them.')
              : Column(children: [for (final c in changes.take(8)) _ChangeRow(c, cur)]),
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend(this.color, this.label);
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Flexible(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
          ),
          const SizedBox(width: 6),
          Flexible(
              child: Text(label,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall)),
        ]),
      );
}

class _Detail extends StatelessWidget {
  const _Detail({
    required this.sel,
    required this.label,
    required this.cur,
    required this.income,
    required this.out,
  });
  final String label;
  final MonthTrend sel;
  final String cur;
  final Color income;
  final Color out;

  @override
  Widget build(BuildContext context) {
    Widget row(Color c, String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Container(
                width: 10,
                height: 10,
                decoration:
                    BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 8),
            Expanded(child: Text(label)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
          ]),
        );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        row(income, 'Income', money(sel.income, cur)),
        row(out, 'Bills & debt', money(sel.committed, cur)),
        row(out, 'Spending and card payments', money(sel.spent, cur)),
      ]),
    );
  }
}

class _ChangeRow extends StatelessWidget {
  const _ChangeRow(this.c, this.cur);
  final CategoryChange c;
  final String cur;

  @override
  Widget build(BuildContext context) {
    final up = c.delta > 0;
    final flat = c.delta.abs() < 0.005;
    final color = flat ? null : (up ? Semantic.bad : Semantic.good);
    final pct = c.percent;
    return ListTile(
      leading: CategoryAvatar(c.category),
      title: Text(c.category.name),
      subtitle: Text('${money(c.current, cur)} this month · ${money(c.previous, cur)} last'),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(
                flat
                    ? Icons.remove_rounded
                    : up
                        ? Icons.arrow_upward_rounded
                        : Icons.arrow_downward_rounded,
                size: 16,
                color: color),
            Text(money(c.delta.abs(), cur),
                style: TextStyle(fontWeight: FontWeight.w700, color: color)),
          ]),
          if (pct != null && !flat)
            Text('${pct.abs().round()}%', style: Theme.of(context).textTheme.bodySmall)
          else if (pct == null && !flat)
            Text('new', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.trend,
    required this.selected,
    required this.incomeColor,
    required this.outColor,
    required this.gridColor,
    required this.textColor,
    required this.highlight,
  });

  final List<MonthTrend> trend;
  final int selected;
  final Color incomeColor;
  final Color outColor;
  final Color gridColor;
  final Color textColor;
  final Color highlight;

  static const _axisW = 40.0;
  static const _labelH = 20.0;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTRB(_axisW, 6, size.width, size.height - _labelH);
    final maxV = trend.fold<double>(
        0, (m, t) => math.max(m, math.max(t.income, t.out)));
    final top = _niceCeil(maxV <= 0 ? 1 : maxV);

    void text(String s, Offset at, {TextAlign align = TextAlign.left, bool bold = false}) {
      final tp = TextPainter(
        text: TextSpan(
            text: s,
            style: TextStyle(
                color: textColor,
                fontSize: 11,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
        textDirection: TextDirection.ltr,
      )..layout();
      final dx = align == TextAlign.right
          ? -tp.width
          : align == TextAlign.center
              ? -tp.width / 2
              : 0.0;
      tp.paint(canvas, at.translate(dx, -tp.height / 2));
    }

    // Recessive grid: baseline plus three guides, labelled on the left.
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = plot.bottom - plot.height * i / 3;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      text(_compact.format(top * i / 3), Offset(_axisW - 6, y), align: TextAlign.right);
    }

    final slot = plot.width / trend.length;
    final barW = math.min(slot * 0.28, 16.0);
    const gap = 2.0; // surface gap between the paired bars

    for (var i = 0; i < trend.length; i++) {
      final cx = plot.left + slot * (i + 0.5);
      if (i == selected) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTRB(plot.left + slot * i + 2, plot.top, plot.left + slot * (i + 1) - 2, plot.bottom),
              const Radius.circular(8)),
          Paint()..color = highlight,
        );
      }
      void bar(double value, double left, Color color) {
        final h = value / top * plot.height;
        if (h <= 0) return;
        // Rounded data end, flat against the baseline.
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTWH(left, plot.bottom - h, barW, h),
            topLeft: const Radius.circular(4),
            topRight: const Radius.circular(4),
          ),
          Paint()..color = color,
        );
      }

      bar(trend[i].income, cx - barW - gap / 2, incomeColor);
      bar(trend[i].out, cx + gap / 2, outColor);
      text(_monthShort.format(trend[i].month), Offset(cx, size.height - _labelH / 2 + 2),
          align: TextAlign.center, bold: i == selected);
    }
  }

  /// Rounds up to 1, 2, 2.5, 5 or 10 times a power of ten for tidy gridlines.
  double _niceCeil(double v) {
    final mag = math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
    for (final f in const [1, 2, 2.5, 3, 4, 5, 6, 8, 10]) {
      if (v <= f * mag) return f * mag;
    }
    return 10 * mag;
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.trend != trend ||
      old.selected != selected ||
      old.incomeColor != incomeColor ||
      old.outColor != outColor ||
      old.gridColor != gridColor ||
      old.textColor != textColor;
}
