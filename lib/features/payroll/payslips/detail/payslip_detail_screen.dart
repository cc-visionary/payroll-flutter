import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/breakpoints.dart';
import '../../../../core/money.dart';
import '../../../../data/repositories/employee_repository.dart';
import '../../../employees/profile/tabs/attendance_tab.dart' as emp;
import 'providers.dart';
import 'tabs/adjustments_tab.dart';
import 'tabs/breakdown_tab.dart';

/// Full payslip detail, matching the payrollos 3-tab layout
/// (Calculation Breakdown / Daily Attendance / Commissions & Adjustments).
class PayslipDetailScreen extends ConsumerWidget {
  final String runId;
  final String payslipId;
  const PayslipDetailScreen({
    super.key,
    required this.runId,
    required this.payslipId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(payslipDetailProvider(payslipId));
    return Scaffold(
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Error: $e', style: const TextStyle(color: Colors.red)),
          ),
        ),
        data: (payslip) {
          if (payslip == null) {
            return const Center(child: Text('Payslip not found.'));
          }
          final employee = payslip['employees'] as Map<String, dynamic>?;
          final run = payslip['payroll_runs'] as Map<String, dynamic>?;
          // Period fields live directly on payroll_runs after the
          // pay_periods drop; treat `run` as the period for downstream
          // helpers that still read `period['pay_date']` etc.
          final period = run;
          final runStatus = run?['status'] as String? ?? 'DRAFT';
          final canEdit = runStatus == 'DRAFT' || runStatus == 'REVIEW';

          // Fall back to the payslip's `created_at` when the run row is
          // missing period_start/end — can happen if migration
          // 20260418000001 hasn't been applied yet.
          DateTime parseOrCreated(Object? v) =>
              v == null ? DateTime.parse(payslip['created_at'] as String) : DateTime.parse(v as String);
          final from = parseOrCreated(period?['period_start']);
          final to = parseOrCreated(period?['period_end']);
          final attendanceCount =
              (to.difference(from).inDays + 1).clamp(0, 60);
          final adjustmentsCount =
              // We don't want to block first render on this provider — but we
              // can surface the count after it loads via a separate watch in
              // the tab label below.
              0;
          final hPad = isMobile(context) ? 16.0 : 24.0;
          return DefaultTabController(
            length: 3,
            child: NestedScrollView(
              headerSliverBuilder: (context, _) => [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(hPad, 16, hPad, 0),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Header(
                          runId: runId,
                          payslipId: payslipId,
                          employee: employee,
                          period: period,
                          runStatus: runStatus,
                        ),
                        const SizedBox(height: 16),
                        _SummaryCards(payslip: payslip, period: period),
                        const SizedBox(height: 16),
                        _RateBox(payslip: payslip, period: period),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _TabBarHeaderDelegate(
                    child: Container(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      padding: EdgeInsets.symmetric(horizontal: hPad),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          _TabBar(
                            attendanceCount: attendanceCount,
                            runId: runId,
                            employeeId: employee['id'] as String,
                            adjustmentsCountPlaceholder: adjustmentsCount,
                          ),
                          const Divider(height: 1),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              body: Padding(
                padding: EdgeInsets.symmetric(horizontal: hPad),
                child: TabBarView(
                  children: [
                    BreakdownTab(
                      payslip: payslip,
                      runId: runId,
                      runStatus: runStatus,
                    ),
                    _SharedAttendanceTab(
                      employeeId: employee!['id'] as String,
                      from: from,
                      to: to,
                    ),
                    AdjustmentsTab(
                      runId: run!['id'] as String,
                      employeeId: employee['id'] as String,
                      canEdit: canEdit,
                    ),
                  ],
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

class _Header extends StatelessWidget {
  final String runId;
  final String payslipId;
  final Map<String, dynamic>? employee;
  final Map<String, dynamic>? period;
  final String runStatus;
  const _Header({
    required this.runId,
    required this.payslipId,
    required this.employee,
    required this.period,
    required this.runStatus,
  });

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final fullName = [
      employee?['first_name'],
      employee?['middle_name'],
      employee?['last_name'],
    ].where((s) => s != null && (s as String).isNotEmpty).join(' ');
    final last = employee?['last_name'] as String? ?? '';
    final first = employee?['first_name'] as String? ?? '';
    final lastFirst = last.isEmpty ? fullName : '$last, $first';
    final number = employee?['employee_number'] as String? ?? '—';
    final role =
        (employee?['role_scorecards'] as Map?)?['job_title'] as String? ??
            employee?['job_title'] as String? ??
            '—';
    final dept =
        (employee?['departments'] as Map?)?['name'] as String? ?? '—';
    final code = period?['code'] as String? ?? '';

    final mobile = isMobile(context);
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            InkWell(
              onTap: () => context.go('/payroll'),
              child: Text(
                'Payroll Runs',
                style: TextStyle(fontSize: 13, color: muted),
              ),
            ),
            Text('  /  ', style: TextStyle(color: muted)),
            InkWell(
              onTap: () => context.go('/payroll/$runId'),
              child: Text(
                code.isEmpty ? 'Run' : code,
                style: TextStyle(fontSize: 13, color: muted),
              ),
            ),
            Text('  /  ', style: TextStyle(color: muted)),
            Text(
              lastFirst.isEmpty ? 'Payslip' : lastFirst,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          lastFirst,
          style: TextStyle(
            fontSize: mobile ? 18 : 22,
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '$number · $role · $dept',
          style: TextStyle(fontSize: 13, color: muted),
        ),
      ],
    );
    final pdfBtn = OutlinedButton.icon(
      onPressed: () => context.push('/payslips/$payslipId'),
      icon: const Icon(Icons.picture_as_pdf, size: 16),
      label: const Text('PDF'),
    );
    if (mobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          titleBlock,
          const SizedBox(height: 12),
          Align(alignment: Alignment.centerLeft, child: pdfBtn),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: titleBlock),
        pdfBtn,
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _SummaryCards extends StatelessWidget {
  final Map<String, dynamic> payslip;
  final Map<String, dynamic>? period;
  const _SummaryCards({required this.payslip, required this.period});

  @override
  Widget build(BuildContext context) {
    Decimal d(Object? v) => Decimal.parse((v ?? '0').toString());
    final gross = d(payslip['gross_pay']);
    final deductions = d(payslip['total_deductions']);
    final net = d(payslip['net_pay']);
    final start = period?['period_start'];
    final end = period?['period_end'];
    final pay = period?['pay_date'];
    final cards = <Widget>[
      _SummaryCard(label: 'Gross Pay', value: Money.fmtPhp(gross)),
      _SummaryCard(
        label: 'Deductions',
        value: '-${Money.fmtPhp(deductions)}',
        color: const Color(0xFFDC2626),
      ),
      _SummaryCard(
        label: 'Net Pay',
        value: Money.fmtPhp(net),
        color: const Color(0xFF16A34A),
      ),
      _SummaryCard(
        label: 'Pay Period',
        value: (start != null && end != null)
            ? '${_fmtDate(DateTime.parse(start as String))} - ${_fmtDate(DateTime.parse(end as String))}'
            : '—',
        subtitle: pay == null ? null : 'Pay Date: ${_fmtDate(DateTime.parse(pay as String))}',
      ),
    ];
    return LayoutBuilder(builder: (ctx, c) {
      final cols = c.maxWidth >= 1100 ? 4 : c.maxWidth >= 700 ? 2 : 1;
      const spacing = 12.0;
      final w = (c.maxWidth - spacing * (cols - 1)) / cols;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [for (final cd in cards) SizedBox(width: w, child: cd)],
      );
    });
  }

  static String _fmtDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final String? subtitle;
  final Color? color;
  const _SummaryCard({
    required this.label,
    required this.value,
    this.subtitle,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _RateBox extends StatelessWidget {
  final Map<String, dynamic> payslip;
  final Map<String, dynamic>? period;
  const _RateBox({required this.payslip, required this.period});

  @override
  Widget build(BuildContext context) {
    final snap = payslip['pay_profile_snapshot'] as Map<String, dynamic>?;
    final wageType = snap?['wageType'] as String? ??
        snap?['wage_type'] as String? ??
        'DAILY';
    final baseRate = _dec(snap?['baseRate'] ?? snap?['base_rate']);
    final derived = snap?['derivedRates'] as Map<String, dynamic>?;

    // Work-hours/days config — prefer the scorecard snapshot, else PH defaults.
    final hoursPerDay = _decOr(
      snap?['workHoursPerDay'] ?? snap?['work_hours_per_day'],
      Decimal.fromInt(8),
    );
    // Days-per-month divisor: scorecard snapshot is days_per_week (e.g. 5 or 6).
    // Convert to per-month factor: 5-day week → 22, 6-day → 26, etc. Fall back
    // to 26 (PH semi-monthly convention for daily workers).
    final daysPerWeek = _decOr(
      snap?['workDaysPerWeek'] ?? snap?['work_days_per_week'],
      Decimal.zero,
    );
    final daysPerMonth = daysPerWeek == Decimal.zero
        ? Decimal.fromInt(26)
        : (daysPerWeek * Decimal.fromInt(52) / Decimal.fromInt(12))
            .toDecimal(scaleOnInfinitePrecision: 4);

    // Compute canonical daily/hourly/minute from baseRate+wageType, then
    // prefer snapshot-provided values when present (non-zero). Old snapshots
    // only carry baseRate; new ones may eventually carry derivedRates too.
    final ratesFromBase = _deriveRates(
      base: baseRate,
      wageType: wageType,
      hoursPerDay: hoursPerDay,
      daysPerMonth: daysPerMonth,
    );
    Decimal preferNonZero(Decimal snapshot, Decimal fallback) =>
        snapshot == Decimal.zero ? fallback : snapshot;
    final daily = preferNonZero(
      _dec(derived?['dailyRate'] ?? snap?['dailyRate']),
      ratesFromBase.daily,
    );
    final hourly = preferNonZero(
      _dec(derived?['hourlyRate'] ?? snap?['hourlyRate']),
      ratesFromBase.hourly,
    );
    final minute = preferNonZero(
      _dec(derived?['minuteRate'] ?? snap?['minuteRate']),
      ratesFromBase.minute,
    );

    final freq = (period?['pay_frequency'] as String?) ??
        snap?['payFrequency'] as String? ??
        '';

    final perLabel = wageType == 'HOURLY'
        ? 'hour'
        : wageType == 'MONTHLY'
            ? 'month'
            : 'day';

    // Directional hint: show the *opposite* time unit so the user can sanity-
    // check the conversion factor at a glance.
    final daysPerMonthInt =
        daysPerMonth.toDouble().round(); // for the hint label
    String? hintText;
    if (wageType == 'DAILY') {
      final monthly = daily * Decimal.fromInt(daysPerMonthInt);
      hintText =
          '(Monthly: ${Money.fmtPhp(monthly)} = daily × $daysPerMonthInt)';
    } else if (wageType == 'HOURLY') {
      hintText =
          '(Daily: ${Money.fmtPhp(daily)} = hourly × ${hoursPerDay.toDouble().round()})';
    } else if (wageType == 'MONTHLY') {
      hintText =
          '(Daily: ${Money.fmtPhp(daily)} = monthly / $daysPerMonthInt)';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        border: Border.all(color: const Color(0xFFBFDBFE)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _kv(context, 'Rate:', '${Money.fmtPhp(baseRate)}/$perLabel',
                  emphasis: true),
              if (hintText != null) _kv(context, '', hintText, muted: true),
              _kv(context, 'Pay Frequency:',
                  freq.toLowerCase().replaceAll('_', '-')),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 24,
            runSpacing: 4,
            children: [
              _kv(context, 'Daily:', Money.fmtPhp(daily)),
              _kv(context, 'Hourly:', Money.fmtPhp(hourly)),
              // Minute rate is typically < ₱2 — render to 4 decimals so the
              // tail of the conversion isn't rounded to ₱0.00 or ₱1.00.
              _kv(context, 'Minute:', _fmtPhpFine(minute, 4)),
            ],
          ),
        ],
      ),
    );
  }

  /// Standard PH conversions between wage-type base rates.
  static ({Decimal daily, Decimal hourly, Decimal minute}) _deriveRates({
    required Decimal base,
    required String wageType,
    required Decimal hoursPerDay,
    required Decimal daysPerMonth,
  }) {
    final sixty = Decimal.fromInt(60);
    final hpd = hoursPerDay == Decimal.zero ? Decimal.fromInt(8) : hoursPerDay;
    final dpm = daysPerMonth == Decimal.zero
        ? Decimal.fromInt(26)
        : daysPerMonth;

    Decimal div(Decimal a, Decimal b) =>
        (a / b).toDecimal(scaleOnInfinitePrecision: 4);

    switch (wageType) {
      case 'HOURLY':
        return (
          daily: base * hpd,
          hourly: base,
          minute: div(base, sixty),
        );
      case 'MONTHLY':
        final d = div(base, dpm);
        final h = div(d, hpd);
        return (daily: d, hourly: h, minute: div(h, sixty));
      case 'DAILY':
      default:
        final h = div(base, hpd);
        return (daily: base, hourly: h, minute: div(h, sixty));
    }
  }

  static String _fmtPhpFine(Decimal v, int digits) {
    return '₱${v.toDouble().toStringAsFixed(digits)}';
  }

  static Decimal _decOr(Object? v, Decimal fallback) {
    if (v == null) return fallback;
    final parsed = Decimal.tryParse(v.toString());
    return parsed ?? fallback;
  }

  Widget _kv(BuildContext ctx, String k, String v,
      {bool emphasis = false, bool muted = false}) {
    return RichText(
      text: TextSpan(
        style: TextStyle(
          fontSize: 13,
          color: muted ? const Color(0xFF6B7280) : const Color(0xFF1D4ED8),
        ),
        children: [
          if (k.isNotEmpty)
            TextSpan(
              text: '$k ',
              style: TextStyle(
                fontWeight: emphasis ? FontWeight.w700 : FontWeight.w600,
                color: emphasis ? const Color(0xFF1E40AF) : null,
              ),
            ),
          TextSpan(
            text: v,
            style: TextStyle(
              fontWeight: emphasis ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  static Decimal _dec(Object? v) {
    if (v == null) return Decimal.zero;
    return Decimal.parse(v.toString());
  }
}

// ---------------------------------------------------------------------------

/// Pins the TabBar + divider below the scrollable header in the
/// NestedScrollView. Height is fixed to the TabBar's material default (48px)
/// plus the 1-px divider.
class _TabBarHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  _TabBarHeaderDelegate({required this.child});

  static const double _height = 49; // 48 tab bar + 1 divider

  @override
  double get minExtent => _height;
  @override
  double get maxExtent => _height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return SizedBox(height: _height, child: child);
  }

  @override
  bool shouldRebuild(covariant _TabBarHeaderDelegate oldDelegate) =>
      oldDelegate.child != child;
}

class _TabBar extends ConsumerWidget {
  final int attendanceCount;
  final String runId;
  final String employeeId;
  final int adjustmentsCountPlaceholder;
  const _TabBar({
    required this.attendanceCount,
    required this.runId,
    required this.employeeId,
    required this.adjustmentsCountPlaceholder,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adjCount = ref
            .watch(
              manualAdjustmentsProvider(
                ManualAdjustmentsKey(runId: runId, employeeId: employeeId),
              ),
            )
            .asData
            ?.value
            .length ??
        adjustmentsCountPlaceholder;
    return TabBar(
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      indicatorSize: TabBarIndicatorSize.label,
      labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      unselectedLabelStyle: const TextStyle(fontSize: 14),
      tabs: [
        const Tab(text: 'Calculation Breakdown'),
        Tab(text: 'Daily Attendance ($attendanceCount)'),
        Tab(text: 'Commissions & Adjustments ($adjCount)'),
      ],
    );
  }
}

/// Thin wrapper that loads the full `Employee` by id and hands it to the
/// shared `AttendanceTab` from `features/employees/profile/tabs/attendance_tab.dart`
/// so the payslip-detail view gets the exact same feature set (stats tiles,
/// calendar/table toggle, leave balance, edit/delete, range picker) as the
/// employee-profile attendance tab. Default date range is the pay period.
class _SharedAttendanceTab extends ConsumerWidget {
  final String employeeId;
  final DateTime from;
  final DateTime to;
  const _SharedAttendanceTab({
    required this.employeeId,
    required this.from,
    required this.to,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(employeeByIdProvider(employeeId));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Error: $e', style: const TextStyle(color: Colors.red)),
        ),
      ),
      data: (employee) {
        if (employee == null) {
          return const Center(child: Text('Employee not found.'));
        }
        return emp.AttendanceTab(
          employee: employee,
          initialStart: from,
          initialEnd: to,
          lockRange: true,
          compact: true,
        );
      },
    );
  }
}
