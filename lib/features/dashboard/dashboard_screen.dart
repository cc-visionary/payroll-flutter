import 'package:decimal/decimal.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/breakpoints.dart';
import '../../app/shell.dart';
import '../../app/tokens.dart';
import 'dashboard_providers.dart';

/// HR analytics dashboard. Mirrors the PeopleOS reference layout:
/// header → 4 KPI cards → headcount/distribution charts →
/// attendance + payroll → movement → footer.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(dashboardDataProvider);
    final mobile = isMobile(context);
    return Scaffold(
      drawer: mobile ? const AppDrawer() : null,
      appBar: mobile
          ? AppBar(title: const Text('Dashboard'))
          : null,
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
            padding: EdgeInsets.all(mobile ? 16 : 24),
            child: _DashboardBody(data: d),
          ),
        ),
      ),
    );
  }
}

class _DashboardBody extends ConsumerWidget {
  final DashboardData data;
  const _DashboardBody({required this.data});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedYear = ref.watch(dashboardYearProvider);
    final thisYear = DateTime.now().year;
    // Year options: current year + 4 back. Dropdown lets HR audit prior
    // years without touching query params.
    final yearOptions = [
      for (var y = thisYear; y >= thisYear - 4; y--) y,
    ];
    final updatedLabel =
        DateFormat('MMM d, yyyy, h:mm a').format(data.generatedAt);
    final mobile = isMobile(context);
    final headerTitle = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Dashboard',
            style: TextStyle(
                fontSize: mobile ? 22 : 28, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('HR Analytics for $selectedYear',
            style: const TextStyle(color: Colors.grey)),
      ],
    );
    final headerMeta = Column(
      crossAxisAlignment:
          mobile ? CrossAxisAlignment.start : CrossAxisAlignment.end,
      children: [
        // Year picker — drives every yearly aggregation on the page.
        DropdownButton<int>(
          value: selectedYear,
          isDense: true,
          underline: const SizedBox.shrink(),
          items: [
            for (final y in yearOptions)
              DropdownMenuItem(value: y, child: Text('$y')),
          ],
          onChanged: (y) {
            if (y == null) return;
            ref.read(dashboardYearProvider.notifier).state = y;
          },
        ),
        const SizedBox(height: 4),
        Text('Last updated: $updatedLabel',
            style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        if (mobile)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              headerTitle,
              const SizedBox(height: 12),
              headerMeta,
            ],
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: headerTitle),
              headerMeta,
            ],
          ),
        const SizedBox(height: 24),
        // Row 1: KPIs
        Builder(builder: (context) {
          final p = LuxiumColors.of(context);
          final amber = Theme.of(context).brightness == Brightness.light
              ? const Color(0xFFF59E0B)
              : const Color(0xFFFBBF24);
          final tertiary = Theme.of(context).colorScheme.tertiary;
          return _ResponsiveRow(
            minColWidth: 240,
            children: [
              _KpiCard(
                icon: Icons.groups_outlined,
                iconBg: p.ctaTint,
                iconColor: p.cta,
                label: 'Active Employees',
                value: data.activeEmployees.toString(),
                subtitle: '${data.totalEmployees} total',
              ),
              _KpiCard(
                icon: Icons.trending_up,
                iconBg: p.accentGreen.withValues(alpha: 0.14),
                iconColor: p.accentGreen,
                label: 'Avg Tenure',
                value: '${data.avgTenureMonths.toStringAsFixed(1)} mo',
                subtitle: 'across active staff',
              ),
              _KpiCard(
                icon: Icons.work_outline,
                iconBg: tertiary.withValues(alpha: 0.14),
                iconColor: tertiary,
                label: 'Open Positions',
                value: data.openPositions.toString(),
                subtitle:
                    '${data.newApplicantsThisMonth} applicants this month',
              ),
              _KpiCard(
                icon: Icons.access_time,
                iconBg: amber.withValues(alpha: 0.14),
                iconColor: amber,
                label: 'Attendance Rate',
                value: '${data.attendanceRatePct.toStringAsFixed(1)}%',
                subtitle: '${data.overtimeHours.toStringAsFixed(1)} OT hours',
              ),
            ],
          );
        }),
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
              child: _PayrollBlock(data: data),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Row 5: Employee Movement (yearly — year picker in header)
        _SectionCard(
          title: 'Employee Movement ($selectedYear)',
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

/// Responsive grid row. [equalSize] (default true) gives cards in the same
/// row equal width via Expanded; their heights follow the tallest child
/// naturally (no IntrinsicHeight, so children may freely contain
/// LayoutBuilder / fl_chart / nested ResponsiveRow). When [equalSize] is
/// false, falls back to a Wrap — use this for internal tile grids inside
/// a card.
class _ResponsiveRow extends StatelessWidget {
  final List<Widget> children;
  final double minColWidth;
  final double spacing;
  final bool equalSize;
  const _ResponsiveRow({
    required this.children,
    required this.minColWidth,
    this.spacing = 16,
    this.equalSize = true,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, c) {
      final cols =
          (c.maxWidth / minColWidth).floor().clamp(1, children.length);

      if (!equalSize) {
        final colWidth = (c.maxWidth - (cols - 1) * spacing) / cols;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final w in children) SizedBox(width: colWidth, child: w),
          ],
        );
      }

      // Split children into rows of [cols] and render each as a plain Row
      // with Expanded for equal widths. Tallest child sets the row height;
      // shorter cards align to top. We intentionally avoid IntrinsicHeight
      // because children may contain LayoutBuilder-based widgets (fl_chart,
      // nested _ResponsiveRow) that cannot answer intrinsic-size queries.
      final rows = <Widget>[];
      for (var i = 0; i < children.length; i += cols) {
        final end = (i + cols).clamp(0, children.length);
        final slice = children.sublist(i, end);
        rows.add(
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var j = 0; j < cols; j++) ...[
                if (j > 0) SizedBox(width: spacing),
                Expanded(
                  child: j < slice.length ? slice[j] : const SizedBox(),
                ),
              ],
            ],
          ),
        );
        if (end < children.length) {
          rows.add(SizedBox(height: spacing));
        }
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      );
    });
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData? icon;
  final Widget child;
  const _SectionCard({
    required this.title,
    this.icon,
    required this.child,
  });
  @override
  Widget build(BuildContext context) {
    final p = LuxiumColors.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(LuxiumSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: p.subdued),
                const SizedBox(width: LuxiumSpacing.sm),
              ],
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: p.foreground,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
            ]),
            const SizedBox(height: LuxiumSpacing.lg),
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
    final p = LuxiumColors.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(LuxiumSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      color: p.subdued,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(LuxiumSpacing.sm),
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(LuxiumRadius.lg),
                  ),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
              ],
            ),
            const SizedBox(height: LuxiumSpacing.md),
            Text(
              value,
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w700,
                height: 1.1,
                letterSpacing: -0.4,
                fontFamily: 'GeistMono',
                color: p.foreground,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(fontSize: 12, color: p.subdued),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Headcount by department — ranked horizontal bars
// ---------------------------------------------------------------------------
//
// Design: a single-color brand bar with gradient, count + percentage pinned
// on the right. Bars share a common max so the longest bar fills the track.
// Single-color (cta) instead of rainbow reads as more professional and keeps
// the visual weight on ranking, not on hue differentiation.
class _DeptBars extends StatefulWidget {
  final Map<String, int> counts;
  const _DeptBars({required this.counts});

  @override
  State<_DeptBars> createState() => _DeptBarsState();
}

class _DeptBarsState extends State<_DeptBars> {
  int? _hoveredIndex;

  @override
  Widget build(BuildContext context) {
    if (widget.counts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
            child: Text('No data', style: TextStyle(color: Colors.grey))),
      );
    }
    final entries = widget.counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final max = entries.first.value;
    final total = entries.fold<int>(0, (s, e) => s + e.value);
    final p = LuxiumColors.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < entries.length; i++)
          _DeptBarRow(
            label: entries[i].key,
            value: entries[i].value,
            max: max,
            total: total,
            palette: p,
            hovered: _hoveredIndex == i,
            dimmed: _hoveredIndex != null && _hoveredIndex != i,
            onHover: (h) => setState(() => _hoveredIndex = h ? i : null),
          ),
      ],
    );
  }
}

class _DeptBarRow extends StatelessWidget {
  final String label;
  final int value;
  final int max;
  final int total;
  final LuxiumPalette palette;
  final bool hovered;
  final bool dimmed;
  final ValueChanged<bool> onHover;

  const _DeptBarRow({
    required this.label,
    required this.value,
    required this.max,
    required this.total,
    required this.palette,
    required this.hovered,
    required this.dimmed,
    required this.onHover,
  });

  @override
  Widget build(BuildContext context) {
    final share =
        total <= 0 ? 0.0 : (value * 100.0) / total;
    final shareLabel = total <= 0
        ? '0%'
        : '${share.toStringAsFixed(share >= 10 ? 0 : 1)}%';
    final opacity = dimmed ? 0.55 : 1.0;

    return MouseRegion(
      onEnter: (_) => onHover(true),
      onExit: (_) => onHover(false),
      child: Tooltip(
        message: '$label\nHeadcount: $value\nShare: $shareLabel',
        waitDuration: const Duration(milliseconds: 150),
        preferBelow: false,
        textStyle: const TextStyle(fontSize: 12, color: Colors.white),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 160),
          opacity: opacity,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 128,
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight:
                          hovered ? FontWeight.w700 : FontWeight.w500,
                      color: palette.foreground,
                    ),
                  ),
                ),
                const SizedBox(width: LuxiumSpacing.md),
                Expanded(
                  child: _BarTrack(
                    fraction: max == 0 ? 0 : value / max,
                    palette: palette,
                    hovered: hovered,
                  ),
                ),
                const SizedBox(width: LuxiumSpacing.md),
                SizedBox(
                  width: 28,
                  child: Text(
                    value.toString(),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontFamily: 'GeistMono',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: palette.foreground,
                    ),
                  ),
                ),
                const SizedBox(width: LuxiumSpacing.sm),
                SizedBox(
                  width: 40,
                  child: Text(
                    shareLabel,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontFamily: 'GeistMono',
                      fontSize: 11.5,
                      color: palette.subdued,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BarTrack extends StatelessWidget {
  final double fraction;
  final LuxiumPalette palette;
  final bool hovered;
  const _BarTrack({
    required this.fraction,
    required this.palette,
    required this.hovered,
  });

  @override
  Widget build(BuildContext context) {
    final height = hovered ? 22.0 : 20.0;
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: palette.muted,
        borderRadius: BorderRadius.circular(LuxiumRadius.lg),
      ),
      clipBehavior: Clip.antiAlias,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: fraction.clamp(0.0, 1.0)),
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) {
          return Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: v.clamp(0.0, 1.0),
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      palette.cta,
                      hovered
                          ? palette.cta
                          : palette.cta.withValues(alpha: 0.85),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(LuxiumRadius.lg),
                ),
              ),
            ),
          );
        },
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
              ExcludeSemantics(
                child: PieChart(PieChartData(
                  sections: sections,
                  centerSpaceRadius: 38,
                  sectionsSpace: 2,
                  startDegreeOffset: -90,
                  pieTouchData: PieTouchData(
                    enabled: true,
                    touchCallback: (event, response) {
                      final idx =
                          response?.touchedSection?.touchedSectionIndex;
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
              ),
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
                  child: Tooltip(
                    message:
                        '${_pretty(entries[i].key)}\nCount: ${entries[i].value}\nShare: ${_percent(entries[i].value, total)}',
                    waitDuration: const Duration(milliseconds: 150),
                    preferBelow: false,
                    textStyle:
                        const TextStyle(fontSize: 12, color: Colors.white),
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

    // fl_chart's own `touchTooltipData` is the reliable hover surface for
    // bar charts on desktop — the tooltip follows the pointer and doesn't
    // depend on widget mount timing the way our OverlayPortal-based
    // BrandTooltip did. Content mirrors the old richRows payload.
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
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => const Color(0xE6111827),
            tooltipPadding: const EdgeInsets.symmetric(
                horizontal: 10, vertical: 6),
            tooltipMargin: 8,
            getTooltipItem: (group, groupIdx, rod, rodIdx) {
              final i = group.x;
              if (i < 0 || i >= values.length) return null;
              final count = values[i];
              final share = total <= 0
                  ? '0%'
                  : '${((count * 100.0) / total).toStringAsFixed(count * 100.0 / total >= 10 ? 0 : 1)}%';
              return BarTooltipItem(
                '${_order[i]}\n',
                const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
                children: [
                  TextSpan(
                    text: '$count ${count == 1 ? 'employee' : 'employees'} · $share',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              );
            },
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

    return SizedBox(height: 180, child: ExcludeSemantics(child: chart));
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
    final msg = tooltipRows.entries
        .map((e) => '${e.key}: ${e.value}')
        .join('\n');
    return Tooltip(
      message: msg,
      waitDuration: const Duration(milliseconds: 150),
      preferBelow: false,
      textStyle: const TextStyle(fontSize: 12, color: Colors.white),
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
          equalSize: false,
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
      equalSize: false,
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
