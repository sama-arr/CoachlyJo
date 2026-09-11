import 'package:flutter/material.dart';

/// Small dashboard widgets built with plain layout primitives — no chart
/// dependency, so behaviour is fully predictable across Flutter versions.
/// Used by the admin Reports dashboards (item 8) and coach Dashboard (item 9).

/// A single headline metric card.
class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? color;
  const StatCard({super.key, required this.label, required this.value, required this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    // (v0.8) Gradient-tinted stat tile with a colored icon chip.
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c.withValues(alpha: 0.20), const Color(0xFF16161C)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 15, color: c),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(label, style: Theme.of(context).textTheme.bodySmall, overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: 8),
          Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        ]),
      ),
    );
  }
}

/// A responsive grid of StatCards, two per row.
class StatGrid extends StatelessWidget {
  final List<StatCard> cards;
  const StatGrid({super.key, required this.cards});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < cards.length; i += 2) {
      rows.add(Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: cards[i]),
        const SizedBox(width: 8),
        Expanded(child: i + 1 < cards.length ? cards[i + 1] : const SizedBox()),
      ]));
    }
    return Column(children: rows);
  }
}

/// A vertical bar chart drawn with plain Containers.
/// [data] is a list of (label, value) pairs.
class SimpleBarChart extends StatelessWidget {
  final String title;
  final List<MapEntry<String, num>> data;
  final String Function(num)? valueFormat;
  final double height;
  const SimpleBarChart({super.key, required this.title, required this.data, this.valueFormat, this.height = 140});

  @override
  Widget build(BuildContext context) {
    final fmt = valueFormat ?? (num v) => v == v.roundToDouble() ? '${v.toInt()}' : v.toStringAsFixed(1);
    final maxV = data.fold<num>(0, (m, e) => e.value > m ? e.value : m);
    final barColor = Theme.of(context).colorScheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          if (data.isEmpty)
            const Padding(padding: EdgeInsets.all(8), child: Text('No data in this period'))
          else
            SizedBox(
              height: height,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: data.map((e) {
                  final frac = maxV <= 0 ? 0.0 : (e.value / maxV).toDouble();
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                        Text(fmt(e.value), style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 2),
                        Container(
                          height: (height - 44) * frac + 4,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [barColor.withValues(alpha: 0.65), const Color(0xFFF20FB6)],
                            ),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(e.key, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ]),
                    ),
                  );
                }).toList(),
              ),
            ),
        ]),
      ),
    );
  }
}

/// 7 / 30 / 90 day range selector used by both dashboards.
class RangePicker extends StatelessWidget {
  final int days;
  final ValueChanged<int> onChanged;
  const RangePicker({super.key, required this.days, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<int>(
      segments: const [
        ButtonSegment(value: 7, label: Text('7d')),
        ButtonSegment(value: 30, label: Text('30d')),
        ButtonSegment(value: 90, label: Text('90d')),
      ],
      selected: {days},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}
