import 'package:decimal/decimal.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../widgets/brand_tooltip.dart';
import 'dashboard_providers.dart';

/// HR analytics dashboard. Mirrors the PeopleOS reference layout:
/// header → 4 KPI cards → headcount/distribution charts →
/// attendance + payroll → movement → footer.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(dashboardDataProvider);
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(dashboardDataProvider),
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Error: $e', style: const TextStyle(color: Colors.red)),
            ),
          ),
          data: (d) => SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: _DashboardBody(data: d),
          ),
        ),
      ),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  final DashboardData data;
  const _DashboardBody({required this.data});

  @override
  Widget build(BuildContext context) {
    final periodLabel = DateFormat('MMMM yyyy').format(data.periodStart);
    final updatedLabel =
        DateFormat('MMM d, yyyy, h:mm a').format(data.generatedAt);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Dashboard',
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('HR Analytics for $periodLabel',
                      style: const TextStyle(color: Colors.grey)),
                ],
              ),
            ),
            Text('Last updated: $updatedLabel',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        const SizedBox(height: 24),
        // Row 1: KPIs
        _ResponsiveRow(
          minColWidth: 240,
          children: [
            _KpiCard(
              icon: Icons.groups_outlined,
              iconBg: const Color(0xFFDDE7FF),
              iconColor: const Color(0xFF3B82F6),
              label: 'Active Employees',
              value: data.activeEmployees.toString(),
              subtitle: '${data.totalEmployees} total',
            ),
            _KpiCard(
              icon: Icons.trending_up,
              iconBg: const Color(0xFFD1FADF),
              iconColor: const Color(0xFF12B76A),
              label: 'Avg Tenure',
              value: '${data.avgTenureMonths.toStringAsFixed(1)} mo',
              subtitle: 'across active staff',
            ),
            _KpiCard(
              icon: Icons.work_outline,
              iconBg: const Color(0xFFEDE0FF),
              iconColor: const Color(0xFF7C3AED),
              label: 'Open Positions',
              value: data.openPositions.toString(),
              subtitle: '${data.newApplicantsThisMonth} applicants this month',
            ),
            _KpiCard(
              icon: Icons.access_time,
              iconBg: const Color(0xFFFFF1CE),
              iconColor: const Color(0xFFF59E0B),
              label: 'Attendance Rate',
              value: '${data.attendanceRatePct.toStringAsFixed(1)}%',
              subtitle: '${data.overtimeHours.toStringAsFixed(1)} OT hours',
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Row 2: Headcount + Employment Type
        _ResponsiveRow(
          minColWidth: 360,
          children: [
            _SectionCard(
              title: 'Headcount by Department',
              icon: Icons.bar_chart,
              child: _DeptBars(counts: data.headcountByDepartment),
            ),
            _SectionCard(
              title: 'Employment Type Distribution',
              child: _DonutWithLegend(
                counts: data.employmentTypeCounts,
                centerLabel: 'Total',
                palette: const [
                  Color(0xFF3B82F6),
                  Color(0xFF10B981),
                  Color(0xFFF59E0B),
                  Color(0xFFEF4444),
                  Color(0xFF8B5CF6),
                  Color(0xFF06B6D4),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Row 3: Hiring Entity + Tenure
        _ResponsiveRow(
          minColWidth: 360,
          children: [
            _SectionCard(
              title: 'Employees by Hiring Entity',
              child: _DonutWithLegend(
                counts: data.hiringEntityCounts,
                centerLabel: 'Total',
                palette: const [
                  Color(0xFF7C3AED),
                  Color(0xFF14B8A6),
                  Color(0xFFEC4899),
                  Color(0xFFF59E0B),
                  Color(0xFF3B82F6),
                ],
              ),
            ),
            _SectionCard(
              title: 'Tenure Distribution',
              child: _TenureBars(buckets: data.tenureBuckets),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Row 4: Attendance + Payroll
        _ResponsiveRow(
          minColWidth: 420,
          children: [
            _SectionCard(
              title: 'Attendance Overview',
              child: _AttendanceBlock(data: data),
            ),
            _SectionCard(
              title: 'Payroll Summary',
              trailing: const _PayrollTimeframeToggle(),
              child: _PayrollBlock(data: data),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Row 5: Employee Movement
        _SectionCard(
          title: 'Employee Movement (This Month)',
          child: _MovementBlock(data: data),
        ),
        const SizedBox(height: 24),
        const Center(
          child: Text(
            'Metrics aligned with HRCI (Human Resource Certification Institute) standards for HR analytics.',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Layout helpers
// ---------------------------------------------------------------------------

class _ResponsiveRow extends StatelessWidget {
  final List<Widget> children;
  final double minColWidth;
  final double spacing;
  const _ResponsiveRow({
    required this.children,
    required this.minColWidth,
    this.spacing = 16,
  });
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, c) {
      final cols = (c.maxWidth / minColWidth).floor().clamp(1, children.length);
      final colWidth = (c.maxWidth - (cols - 1) * spacing) / cols;
      // Wrap preserves the wrap-to-next-line behaviour on narrow screens.
      // We deliberately avoid IntrinsicHeight here — some children contain
      // nested LayoutBuilders (_PayrollBlock uses another _ResponsiveRow for
      // its stat tiles) and LayoutBuilder cannot satisfy intrinsic queries.
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [
          for (final w in children) SizedBox(width: colWidth, child: w),
        ],
      );
    });
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData? icon;
  final Widget child;
  final Widget? trailing;
  const _SectionCard({
    required this.title,
    this.icon,
    required this.child,
    this.trailing,
  });
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: Colors.grey[700]),
                const SizedBox(width: 8),
              ],
              Text(title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
              if (trailing != null) ...[
                const Spacer(),
                trailing!,
              ],
            ]),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String label;
  final String value;
  final String subtitle;
  const _KpiCard({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.subtitle,
  });
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500)),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(value,
                style: const TextStyle(
                    fontSize: 28, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(subtitle,
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Headcount by department — horizontal bars
// ---------------------------------------------------------------------------
class _DeptBars extends StatelessWidget {
  final Map<String, int> counts;
  const _DeptBars({required this.counts});
  @override
  Widget build(BuildContext context) {
    if (counts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: Text('No data', style: TextStyle(color: Colors.grey))),
      );
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final max = entries.first.value;
    final total = entries.fold<int>(0, (s, e) => s + e.value);
    final palette = const [
      Color(0xFF3B82F6),
      Color(0xFF10B981),
      Color(0xFFF59E0B),
      Color(0xFFEF4444),
      Color(0xFF8B5CF6),
      Color(0xFF06B6D4),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < entries.length; i++)
          _DeptBarRow(
            label: entries[i].key,
            value: entries[i].value,
            max: max,
            total: total,
            color: palette[i % palette.length],
          ),
      ],
    );
  }
}

class _DeptBarRow extends StatefulWidget {
  final String label;
  final int value;
  final int max;
  final int total;
  final Color color;
  const _DeptBarRow({
    required this.label,
    required this.value,
    required this.max,
    required this.total,
    required this.color,
  });
  @override
  State<_DeptBarRow> createState() => _DeptBarRowState();
}

class _DeptBarRowState extends State<_DeptBarRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final share = widget.total <= 0
        ? '0%'
        : '${((widget.value * 100.0) / widget.total).toStringAsFixed(widget.value * 100.0 / widget.total >= 10 ? 0 : 1)}%';
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: BrandTooltip.richRows(
        rows: {
          'Department': widget.label,
          'Headcount': widget.value.toString(),
          'Share': share,
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
          decoration: BoxDecoration(
            color: _hover
                ? Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.7)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 110,
                child: Text(
                  widget.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: _hover ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOut,
                    height: _hover ? 16 : 14,
                    // Fill-on-load animation: tween the bar from 0 to its
                    // final share over 450 ms on first build so rows feel
                    // alive (Chart.js-style reveal).
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(
                        begin: 0,
                        end: widget.max == 0 ? 0.0 : widget.value / widget.max,
                      ),
                      duration: const Duration(milliseconds: 450),
                      curve: Curves.easeOutCubic,
                      builder: (context, v, _) => LinearProgressIndicator(
                        value: v,
                        minHeight: _hover ? 16 : 14,
                        backgroundColor: Colors.grey.withValues(alpha: 0.15),
                        valueColor: AlwaysStoppedAnimation(widget.color),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 24,
                child: Text(widget.value.toString(),
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Donut chart with legend (hover-interactive)
// ---------------------------------------------------------------------------
class _DonutWithLegend extends StatefulWidget {
  final Map<String, int> counts;
  final String centerLabel;
  final List<Color> palette;
  const _DonutWithLegend({
    required this.counts,
    required this.centerLabel,
    required this.palette,
  });
  @override
  State<_DonutWithLegend> createState() => _DonutWithLegendState();
}

class _DonutWithLegendState extends State<_DonutWithLegend> {
  int? _hoveredIndex;

  void _setHover(int? i) {
    if (_hoveredIndex == i) return;
    setState(() => _hoveredIndex = i);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.counts.isEmpty || widget.counts.values.every((v) => v == 0)) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: Text('No data', style: TextStyle(color: Colors.grey))),
      );
    }
    final entries = widget.counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<int>(0, (s, e) => s + e.value);
    final sections = <PieChartSectionData>[];
    for (var i = 0; i < entries.length; i++) {
      final hovered = _hoveredIndex == i;
      sections.add(PieChartSectionData(
        value: entries[i].value.toDouble(),
        color: widget.palette[i % widget.palette.length],
        radius: hovered ? 28 : 22,
        showTitle: false,
      ));
    }

    final hovered = _hoveredIndex;
    final centerTopText = hovered == null
        ? total.toString()
        : entries[hovered].value.toString();
    final centerBotText = hovered == null
        ? widget.centerLabel
        : '${_pretty(entries[hovered].key)} · ${_percent(entries[hovered].value, total)}';

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 140,
          height: 140,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(PieChartData(
                sections: sections,
                centerSpaceRadius: 38,
                sectionsSpace: 2,
                startDegreeOffset: -90,
                pieTouchData: PieTouchData(
                  enabled: true,
                  touchCallback: (event, response) {
                    final idx = response?.touchedSection?.touchedSectionIndex;
                    if (!event.isInterestedForInteractions ||
                        idx == null ||
                        idx < 0) {
                      _setHover(null);
                    } else {
                      _setHover(idx);
                    }
                  },
                ),
              )),
              IgnorePointer(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(centerTopText,
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w700)),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 120),
                      child: Text(
                        centerBotText,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11, color: Colors.grey),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 24),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < entries.length; i++)
                MouseRegion(
                  onEnter: (_) => _setHover(i),
                  onExit: (_) => _setHover(null),
                  cursor: SystemMouseCursors.basic,
                  child: BrandTooltip.richRows(
                    rows: {
                      'Category': _pretty(entries[i].key),
                      'Count': entries[i].value.toString(),
                      'Share': _percent(entries[i].value, total),
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeOut,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 4),
                      decoration: BoxDecoration(
                        color: _hoveredIndex == i
                            ? Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                                .withValues(alpha: 0.7)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: widget.palette[i % widget.palette.length],
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(_pretty(entries[i].key),
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: _hoveredIndex == i
                                        ? FontWeight.w600
                                        : FontWeight.normal)),
                          ),
                          Text(entries[i].value.toString(),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  static String _pretty(String raw) {
    // Lower-case ALL_CAPS enum-style strings to look closer to PeopleOS labels.
    if (RegExp(r'^[A-Z_]+$').hasMatch(raw)) {
      return raw
          .split('_')
          .map((p) => p.isEmpty
              ? p
              : '${p[0]}${p.substring(1).toLowerCase()}')
          .join(' ');
    }
    return raw;
  }

  static String _percent(int v, int total) {
    if (total <= 0) return '0%';
    final pct = (v * 100.0) / total;
    return '${pct.toStringAsFixed(pct >= 10 ? 0 : 1)}%';
  }
}

// ---------------------------------------------------------------------------
// Tenure bars (vertical)
// ---------------------------------------------------------------------------
class _TenureBars extends StatefulWidget {
  final Map<String, int> buckets;
  const _TenureBars({required this.buckets});
  @override
  State<_TenureBars> createState() => _TenureBarsState();
}

class _TenureBarsState extends State<_TenureBars> {
  static const _order = ['< 1 year', '1-2 years', '2-5 years', '5+ years'];
  static const _colors = [
    Color(0xFF3B82F6),
    Color(0xFF10B981),
    Color(0xFFF59E0B),
    Color(0xFF8B5CF6),
  ];
  int? _hoveredIndex;

  @override
  Widget build(BuildContext context) {
    final values = _order.map((k) => widget.buckets[k] ?? 0).toList();
    final max = values.fold<int>(0, (a, b) => a > b ? a : b);
    final total = values.fold<int>(0, (a, b) => a + b);
    // Always give the Y axis some headroom so a 0-bar still looks like a chart.
    final maxY = max == 0 ? 4.0 : (max * 1.25);

    final hovered = _hoveredIndex;
    final hoverRows = hovered == null
        ? null
        : {
            'Tenure': _order[hovered],
            'Employees': values[hovered].toString(),
            'Share': total <= 0
                ? '0%'
                : '${((values[hovered] * 100.0) / total).toStringAsFixed(values[hovered] * 100.0 / total >= 10 ? 0 : 1)}%',
          };

    // Wrap the BarChart in a single BrandTooltip whose content switches to
    // reflect the currently hovered bar. Cheaper than one tooltip per bar —
    // fl_chart's own touchCallback drives the hover state.
    Widget chart = BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxY,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 20,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= values.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    values[i].toString(),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: _hoveredIndex == i
                          ? FontWeight.w700
                          : FontWeight.w600,
                    ),
                  ),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= _order.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _order[i],
                    style: const TextStyle(
                        fontSize: 11, color: Colors.grey),
                  ),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < values.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: values[i].toDouble(),
                  width: 28,
                  color: _hoveredIndex == i
                      ? (Color.lerp(_colors[i], Colors.white, 0.18) ??
                          _colors[i])
                      : _colors[i],
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(4)),
                ),
              ],
            ),
        ],
        barTouchData: BarTouchData(
          enabled: true,
          // Suppress fl_chart's own tooltip; we use BrandTooltip.
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => Colors.transparent,
            tooltipPadding: EdgeInsets.zero,
            tooltipMargin: 0,
            getTooltipItem: (group, groupIdx, rod, rodIdx) => null,
          ),
          touchCallback: (event, response) {
            final idx = response?.spot?.touchedBarGroupIndex;
            if (!event.isInterestedForInteractions || idx == null || idx < 0) {
              if (_hoveredIndex != null) {
                setState(() => _hoveredIndex = null);
              }
            } else if (_hoveredIndex != idx) {
              setState(() => _hoveredIndex = idx);
            }
          },
        ),
      ),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
    );

    final body = SizedBox(height: 180, child: chart);
    if (hoverRows == null) return body;
    return BrandTooltip.richRows(rows: hoverRows, child: body);
  }
}

// ---------------------------------------------------------------------------
// Attendance block — 3 ring gauges + 2 metric tiles
// ---------------------------------------------------------------------------
class _AttendanceBlock extends StatelessWidget {
  final DashboardData data;
  const _AttendanceBlock({required this.data});
  @override
  Widget build(BuildContext context) {
    final chargeable = data.attendanceTotal -
        data.attendanceRestDay -
        data.attendanceOnLeave;
    final presentPct = chargeable <= 0
        ? 0
        : ((data.attendancePresent / chargeable) * 100).round();
    final leavePct = data.attendanceTotal == 0
        ? 0
        : ((data.attendanceOnLeave / data.attendanceTotal) * 100).round();
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _RingGauge(
              percent: data.attendanceRatePct.round(),
              color: const Color(0xFF10B981),
              label: 'Attendance',
              tooltipRows: {
                'Rate': '${data.attendanceRatePct.toStringAsFixed(1)}%',
                'Present': data.attendancePresent.toString(),
                'Absent': data.attendanceAbsent.toString(),
                'On leave': data.attendanceOnLeave.toString(),
                'Rest days': data.attendanceRestDay.toString(),
              },
            ),
            _RingGauge(
              percent: presentPct,
              color: const Color(0xFF3B82F6),
              label: 'Present',
              tooltipRows: {
                'Present': '$presentPct%',
                'Basis': 'present ÷ chargeable days',
                'Chargeable': chargeable.toString(),
              },
            ),
            _RingGauge(
              percent: leavePct,
              color: const Color(0xFF8B5CF6),
              label: 'Leave Used',
              tooltipRows: {
                'Leave used': '$leavePct%',
                'Basis': 'on-leave days ÷ total days',
                'Total days': data.attendanceTotal.toString(),
              },
            ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _MiniMetric(
                label: 'Avg Late Minutes',
                value: '${data.avgLateMinutes} min',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MiniMetric(
                label: 'Overtime Hours',
                value: '${data.overtimeHours.toStringAsFixed(1)} hrs',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RingGauge extends StatelessWidget {
  final int percent;
  final Color color;
  final String label;
  final Map<String, String> tooltipRows;
  const _RingGauge({
    required this.percent,
    required this.color,
    required this.label,
    required this.tooltipRows,
  });
  @override
  Widget build(BuildContext context) {
    final p = percent.clamp(0, 100);
    return BrandTooltip.richRows(
      rows: tooltipRows,
      child: Column(
        children: [
          SizedBox(
            width: 78,
            height: 78,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: p / 100.0,
                    strokeWidth: 7,
                    backgroundColor: color.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
                Text('$p%',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  final String label;
  final String value;
  const _MiniMetric({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// Segmented toggle in the Payroll Summary card header. Flips the provider
/// between yearly (current calendar year) and monthly (current month) —
/// dashboardDataProvider watches the state so numbers refresh immediately.
class _PayrollTimeframeToggle extends ConsumerWidget {
  const _PayrollTimeframeToggle();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tf = ref.watch(dashboardTimeframeProvider);
    return SegmentedButton<DashboardTimeframe>(
      style: SegmentedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(
          value: DashboardTimeframe.yearly,
          label: Text('Yearly'),
        ),
        ButtonSegment(
          value: DashboardTimeframe.monthly,
          label: Text('Monthly'),
        ),
      ],
      selected: {tf},
      onSelectionChanged: (s) =>
          ref.read(dashboardTimeframeProvider.notifier).state = s.first,
    );
  }
}

// ---------------------------------------------------------------------------
// Payroll block — total + statutory tiles
// ---------------------------------------------------------------------------
class _PayrollBlock extends StatelessWidget {
  final DashboardData data;
  const _PayrollBlock({required this.data});
  @override
  Widget build(BuildContext context) {
    final f = NumberFormat.currency(locale: 'en_PH', symbol: '₱', decimalDigits: 0);
    String fmt(Decimal d) => f.format(d.toDouble());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Total Payroll Cost',
            style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(fmt(data.totalPayrollCost),
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text('Avg Salary: ${fmt(data.avgSalary)}',
            style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 16),
        _ResponsiveRow(
          minColWidth: 140,
          spacing: 12,
          children: [
            _StatTile(
              label: 'SSS',
              value: fmt(data.sssTotal),
              bg: const Color(0xFFE0F2FE),
              fg: const Color(0xFF0369A1),
            ),
            _StatTile(
              label: 'PhilHealth',
              value: fmt(data.philhealthTotal),
              bg: const Color(0xFFD1FADF),
              fg: const Color(0xFF12B76A),
            ),
            _StatTile(
              label: 'Pag-IBIG',
              value: fmt(data.pagibigTotal),
              bg: const Color(0xFFFEF3C7),
              fg: const Color(0xFFB45309),
            ),
            _StatTile(
              label: 'Withholding Tax',
              value: fmt(data.withholdingTaxTotal),
              bg: const Color(0xFFFEE2E2),
              fg: const Color(0xFFB91C1C),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final Color bg;
  final Color fg;
  const _StatTile({
    required this.label,
    required this.value,
    required this.bg,
    required this.fg,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: fg)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700, color: fg)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Employee movement
// ---------------------------------------------------------------------------
class _MovementBlock extends StatelessWidget {
  final DashboardData data;
  const _MovementBlock({required this.data});
  @override
  Widget build(BuildContext context) {
    return _ResponsiveRow(
      minColWidth: 160,
      spacing: 12,
      children: [
        _MovementTile(
          label: 'New Hires',
          value: data.newHiresThisMonth.toString(),
          color: const Color(0xFF12B76A),
          bg: const Color(0xFFD1FADF),
        ),
        _MovementTile(
          label: 'Separations',
          value: data.separationsThisMonth.toString(),
          color: const Color(0xFFEF4444),
          bg: const Color(0xFFFEE2E2),
        ),
        _MovementTile(
          label: 'Voluntary (YTD)',
          value: data.voluntaryYtd.toString(),
          color: const Color(0xFFB45309),
          bg: const Color(0xFFFEF3C7),
        ),
        _MovementTile(
          label: 'Involuntary (YTD)',
          value: data.involuntaryYtd.toString(),
          color: const Color(0xFF7C3AED),
          bg: const Color(0xFFEDE0FF),
        ),
      ],
    );
  }
}

class _MovementTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final Color bg;
  const _MovementTile({
    required this.label,
    required this.value,
    required this.color,
    required this.bg,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 28, fontWeight: FontWeight.w700, color: color)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
