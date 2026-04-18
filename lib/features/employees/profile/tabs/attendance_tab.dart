import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/status_colors.dart';
import '../../../../app/tokens.dart';
import '../../../../data/models/attendance_day.dart';
import '../../../../data/models/calendar_event.dart';
import '../../../../data/models/employee.dart';
import '../../../../data/models/shift_template.dart';
import '../../../../data/repositories/attendance_repository.dart';
import '../../../../data/repositories/holiday_repository.dart';
import '../../../../data/repositories/role_scorecard_repository.dart';
import '../../../../data/repositories/shift_template_repository.dart';
import '../../../../widgets/attendance_timeline_bar.dart';
import '../../../attendance/attendance_row_vm.dart';
import '../../../auth/profile_provider.dart';
import '../providers.dart';
import 'attendance_batch_dialog.dart';
import 'attendance_edit_dialog.dart';

class AttendanceTab extends ConsumerStatefulWidget {
  final Employee employee;

  /// Optional default date range. When both are supplied, the tab opens on
  /// that range instead of the current calendar month — used when embedded
  /// inside a payslip detail so it starts on the pay period's dates.
  final DateTime? initialStart;
  final DateTime? initialEnd;

  /// When true, the range bar hides its Prev / Next / This-month / date-picker
  /// controls — the period is fixed to [initialStart]..[initialEnd]. Used
  /// inside the payslip detail so attendance can't drift off the pay period.
  final bool lockRange;

  /// Compact stats presentation — renders only the primary 5-tile row and
  /// omits the "More stats" disclosure. Used inside the Payslip Detail
  /// where the audience only cares about the period totals.
  final bool compact;

  const AttendanceTab({
    super.key,
    required this.employee,
    this.initialStart,
    this.initialEnd,
    this.lockRange = false,
    this.compact = false,
  });

  @override
  ConsumerState<AttendanceTab> createState() => _AttendanceTabState();
}

class _AttendanceTabState extends ConsumerState<AttendanceTab> {
  late DateTime _start;
  late DateTime _end;
  late _AttendanceViewMode _viewMode;
  static const bool _selectMode = true; // selection is always on; no toggle button
  final _selected = <String>{}; // record ids

  @override
  void initState() {
    super.initState();
    if (widget.initialStart != null && widget.initialEnd != null) {
      final s = widget.initialStart!;
      final e = widget.initialEnd!;
      _start = DateTime(s.year, s.month, s.day);
      _end = DateTime(e.year, e.month, e.day);
    } else {
      final now = DateTime.now();
      _start = DateTime(now.year, now.month, 1);
      _end = DateTime(now.year, now.month + 1, 0);
    }
    // Default to Table everywhere — it's the densest layout and supports
    // batch edit + inline scanning. User can always switch to Calendar or
    // Timeline via the segmented toggle.
    _viewMode = _AttendanceViewMode.table;
  }

  void _shiftRange(int months) {
    setState(() {
      _start = DateTime(_start.year, _start.month + months, 1);
      _end = DateTime(_end.year, _end.month + months + 1, 0);
      _selected.clear();
    });
  }

  void _thisMonth() {
    final now = DateTime.now();
    setState(() {
      _start = DateTime(now.year, now.month, 1);
      _end = DateTime(now.year, now.month + 1, 0);
      _selected.clear();
    });
  }

  Future<void> _pickRange() async {
    final picked = await showDialog<DateTimeRange>(
      context: context,
      builder: (_) => _RangePickerDialog(start: _start, end: _end),
    );
    if (picked == null) return;
    setState(() {
      _start = DateTime(picked.start.year, picked.start.month, picked.start.day);
      _end = DateTime(picked.end.year, picked.end.month, picked.end.day);
      _selected.clear();
    });
  }

  int get _year => _start.year;

  @override
  Widget build(BuildContext context) {
    final attendanceAsync = ref.watch(attendanceListProvider(
      AttendanceQuery(
        start: _start,
        end: _end,
        employeeId: widget.employee.id,
      ),
    ));
    final leaveBalancesAsync = ref.watch(
      leaveBalancesProvider(
        LeaveBalanceQuery(employeeId: widget.employee.id, year: _year),
      ),
    );
    final shiftsAsync = ref.watch(shiftTemplateListProvider);
    // A range can straddle a year boundary (e.g. Dec 30 → Jan 14) — fetch
    // every year the range touches so holidays on either side are honored.
    final holidayYears = <int>{
      for (var y = _start.year; y <= _end.year; y++) y,
    };
    final holidayAsyncs =
        holidayYears.map((y) => ref.watch(_holidayEventsForYearProvider(y))).toList();
    final scorecardsAsync = ref.watch(roleScorecardListProvider);
    final workDaysPerWeek = () {
      final id = widget.employee.roleScorecardId;
      if (id == null) return null;
      final cards = scorecardsAsync.asData?.value ?? const [];
      for (final c in cards) {
        if (c.id == id) return c.workDaysPerWeek;
      }
      return null;
    }();

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      children: [
        _RangeBar(
          start: _start,
          end: _end,
          viewMode: _viewMode,
          selectedCount: _selected.length,
          locked: widget.lockRange,
          onPrev: () => _shiftRange(-1),
          onNext: () => _shiftRange(1),
          onToday: _thisMonth,
          onPickRange: _pickRange,
          onViewModeChanged: (m) => setState(() => _viewMode = m),
          onBatchEdit: () => _openBatchEdit(context),
          onBatchDelete: () => _openBatchDelete(context),
        ),
        const SizedBox(height: 16),
        attendanceAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Error: $e', style: const TextStyle(color: Colors.red)),
          ),
          data: (records) {
            final shifts = <String, ShiftTemplate>{
              for (final s in shiftsAsync.asData?.value ?? const <ShiftTemplate>[]) s.id: s,
            };
            final holidays = <String, CalendarEvent>{
              for (final a in holidayAsyncs)
                for (final e in a.asData?.value ?? const <CalendarEvent>[])
                  _isoDate(e.date): e,
            };
            // Employee's default shift resolved via their role scorecard.
            // Used as a fallback for rows whose DB record has no shift_template_id.
            ShiftTemplate? defaultShift;
            final scId = widget.employee.roleScorecardId;
            if (scId != null) {
              for (final c in scorecardsAsync.asData?.value ?? const []) {
                if (c.id == scId && c.shiftTemplateId != null) {
                  defaultShift = shifts[c.shiftTemplateId];
                  break;
                }
              }
            }
            final rows = _buildRows(
              start: _start,
              end: _end,
              records: records,
              shifts: shifts,
              holidays: holidays,
              defaultShift: defaultShift,
              workDaysPerWeek: workDaysPerWeek,
            );
            final stats = _Stats.from(rows, workDaysPerWeek: workDaysPerWeek);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _StatsGrid(stats: stats, compact: widget.compact),
                const SizedBox(height: LuxiumSpacing.xl),
                if (_viewMode == _AttendanceViewMode.calendar)
                  _CalendarView(
                    rows: rows,
                    selected: _selected,
                    onDayTap: (row) => setState(() {
                      final r = row.record;
                      if (r == null) return;
                      if (_selected.contains(r.id)) {
                        _selected.remove(r.id);
                      } else {
                        _selected.add(r.id);
                      }
                    }),
                  )
                else if (_viewMode == _AttendanceViewMode.timeline)
                  _DayTimelineView(
                    rows: rows,
                    selected: _selected,
                    onRowChecked: (id, v) => setState(() {
                      if (v) {
                        _selected.add(id);
                      } else {
                        _selected.remove(id);
                      }
                    }),
                    onHeaderChecked: (v) => setState(() {
                      _selected.clear();
                      if (v) {
                        _selected.addAll(rows
                            .where((r) => r.record != null)
                            .map((r) => r.record!.id));
                      }
                    }),
                    onRowTap: (row) => _openSingleEdit(context, row),
                  )
                else
                _MonthTable(
                  rows: rows,
                  start: _start,
                  end: _end,
                  selectMode: _selectMode,
                  selected: _selected,
                  onRowChecked: (id, v) => setState(() {
                    if (v) {
                      _selected.add(id);
                    } else {
                      _selected.remove(id);
                    }
                  }),
                  onHeaderChecked: (v) => setState(() {
                    _selected.clear();
                    if (v) {
                      _selected.addAll(rows
                          .where((r) => r.record != null)
                          .map((r) => r.record!.id));
                    }
                  }),
                  onEdit: (row) => _openSingleEdit(context, row),
                  onDelete: (row) => _confirmDelete(context, row),
                ),
                const SizedBox(height: LuxiumSpacing.xl),
                _LeaveBalances(async: leaveBalancesAsync),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _openSingleEdit(BuildContext context, _RowVM row) async {
    final shifts = ref.read(shiftTemplateListProvider).asData?.value ?? const [];
    final changed = await showAttendanceEditDialog(
      context: context,
      ref: ref,
      employeeId: widget.employee.id,
      date: row.date,
      record: row.record,
      currentShift: row.shift,
      shifts: shifts,
    );
    if (changed == true && mounted) {
      ref.invalidate(attendanceListProvider);
    }
  }

  Future<void> _confirmDelete(BuildContext context, _RowVM row) async {
    final r = row.record;
    if (r == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete attendance record?'),
        content: Text(
          'This removes the DB record for ${_isoDate(row.date)}. The row '
          'will fall back to its generated default (rest day, holiday, or no data).',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton.tonal(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(attendanceRepositoryProvider).deleteRecord(r.id);
      ref.invalidate(attendanceListProvider);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  Future<void> _openBatchEdit(BuildContext context) async {
    if (_selected.isEmpty) return;
    final count = _selected.length;
    final shifts = ref.read(shiftTemplateListProvider).asData?.value ?? const [];
    final records = ref.read(attendanceListProvider(
      AttendanceQuery(start: _start, end: _end, employeeId: widget.employee.id),
    )).asData?.value ?? const [];
    final datesByRecordId = <String, DateTime>{
      for (final r in records) r.id: r.attendanceDate,
    };
    final messenger = ScaffoldMessenger.of(context);
    final changed = await showAttendanceBatchEditDialog(
      context: context,
      ref: ref,
      recordIds: _selected.toList(),
      datesByRecordId: datesByRecordId,
      shifts: shifts,
    );
    if (changed == true && mounted) {
      setState(() => _selected.clear());
      ref.invalidate(attendanceListProvider);
      // Positive feedback — currently the dialog only surfaces errors, so a
      // fully-successful batch edit used to leave the user guessing whether
      // anything actually happened. Guard via try/catch: when the tab is in
      // a deeply-nested Navigator (payslip detail → attendance shared tab)
      // the Scaffold that owned the messenger may already be detached.
      try {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Updated $count record${count == 1 ? '' : 's'}.'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      } catch (_) {
        // Scaffold already deactivated — swallow; the state change above
        // is all the user actually needs.
      }
    }
  }

  Future<void> _openBatchDelete(BuildContext context) async {
    if (_selected.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${_selected.length} records?'),
        content: const Text(
          'This removes the selected DB records. Rows will fall back to their '
          'generated defaults.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton.tonal(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    final repo = ref.read(attendanceRepositoryProvider);
    final failures = <String>[];
    for (final id in _selected.toList()) {
      try {
        await repo.deleteRecord(id);
      } catch (e) {
        failures.add(e.toString());
      }
    }
    if (!mounted) return;
    setState(() => _selected.clear());
    ref.invalidate(attendanceListProvider);
    if (failures.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${failures.length} delete(s) failed')),
      );
    }
  }
}

// Row ViewModel — one per calendar day in the selected month.
// Implementation lives in lib/features/attendance/attendance_row_vm.dart so
// the payslip PDF renders the same numbers as this tab. The typedef + thin
// wrappers below keep this file's existing call sites unchanged.
typedef _RowVM = AttendanceRowVm;

List<_RowVM> _buildRows({
  required DateTime start,
  required DateTime end,
  required List<AttendanceDay> records,
  required Map<String, ShiftTemplate> shifts,
  required Map<String, CalendarEvent> holidays,
  ShiftTemplate? defaultShift,
  String? workDaysPerWeek,
}) =>
    buildAttendanceRows(
      start: start,
      end: end,
      records: records,
      shifts: shifts,
      holidays: holidays,
      defaultShift: defaultShift,
      workDaysPerWeek: workDaysPerWeek,
    );

String _isoDate(DateTime d) => isoDate(d);

DateTime _applyTime(DateTime date, String hhmmss) => applyTime(date, hhmmss);

String _fmtClock(DateTime? t) {
  if (t == null) return '—';
  final local = t.toLocal();
  final h = local.hour;
  final m = local.minute.toString().padLeft(2, '0');
  final period = h >= 12 ? 'PM' : 'AM';
  final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
  return '${h12.toString().padLeft(2, '0')}:$m $period';
}

String _fmtShiftTime(String hhmmss) {
  final parts = hhmmss.split(':');
  final h = parts[0].padLeft(2, '0');
  final m = (parts.length > 1 ? parts[1] : '00').padLeft(2, '0');
  return '$h:$m';
}

// ---------------------------------------------------------------------------
// Month bar
// ---------------------------------------------------------------------------

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

class _MonthBar extends StatelessWidget {
  final int year;
  final int month;
  final bool selectMode;
  final int selectedCount;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToday;
  final ValueChanged<int> onMonth;
  final ValueChanged<int> onYear;
  final VoidCallback onToggleSelect;
  final VoidCallback onBatchEdit;
  final VoidCallback onBatchDelete;
  const _MonthBar({
    required this.year,
    required this.month,
    required this.selectMode,
    required this.selectedCount,
    required this.onPrev,
    required this.onNext,
    required this.onToday,
    required this.onMonth,
    required this.onYear,
    required this.onToggleSelect,
    required this.onBatchEdit,
    required this.onBatchDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          OutlinedButton(
            onPressed: onPrev,
            child: const Text('← Prev'),
          ),
          DropdownButton<int>(
            value: month,
            onChanged: (v) => v == null ? null : onMonth(v),
            items: [
              for (int i = 1; i <= 12; i++)
                DropdownMenuItem(value: i, child: Text(_monthNames[i - 1])),
            ],
          ),
          DropdownButton<int>(
            value: year,
            onChanged: (v) => v == null ? null : onYear(v),
            items: [
              for (int y = DateTime.now().year - 5;
                  y <= DateTime.now().year + 1;
                  y++)
                DropdownMenuItem(value: y, child: Text(y.toString())),
            ],
          ),
          OutlinedButton(
            onPressed: onNext,
            child: const Text('Next →'),
          ),
          OutlinedButton(
            onPressed: onToday,
            child: const Text('Today'),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: selectedCount == 0 ? null : onBatchEdit,
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: Text('Edit Selected ($selectedCount)'),
          ),
          FilledButton.icon(
            onPressed: selectedCount == 0 ? null : onBatchDelete,
            icon: const Icon(Icons.delete_outline, size: 16),
            label: Text('Delete Selected ($selectedCount)'),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade400),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stats
// ---------------------------------------------------------------------------

// Implementation lives in lib/features/attendance/attendance_row_vm.dart so
// the payslip PDF page 2 summary matches this tab's stat tiles exactly.
typedef _Stats = AttendanceStats;

/// Primary stats row (always visible) + expandable "More stats" disclosure
/// (secondary counts). In `compact` mode the disclosure is omitted entirely,
/// so payslip embeds stay focused on the period totals.
class _StatsGrid extends StatefulWidget {
  final _Stats stats;
  final bool compact;
  const _StatsGrid({required this.stats, this.compact = false});

  @override
  State<_StatsGrid> createState() => _StatsGridState();
}

class _StatsGridState extends State<_StatsGrid> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.stats;
    return LayoutBuilder(builder: (ctx, c) {
      // Primary tiles: Work Days (ratio) + 4 metrics. Tighter col counts than
      // the old 9-tile grid since the new layout is coarser-grained.
      final cols = c.maxWidth >= 1100
          ? 5
          : c.maxWidth >= 760
              ? 3
              : c.maxWidth >= 480
                  ? 2
                  : 1;
      final gap = LuxiumSpacing.md; // 12px
      final w = (c.maxWidth - gap * (cols - 1)) / cols;

      final primary = <Widget>[
        _RatioStatTile(
          width: w,
          label: 'Work Days',
          numerator: s.present,
          denominator: s.workDays,
          unit: 'days',
          tone: AttendanceStatus.present.tone,
        ),
        _CountStatTile(
          width: w,
          label: 'Absent',
          value: s.absent.toString(),
          unit: 'days',
          tone: AttendanceStatus.absent.tone,
        ),
        _CountStatTile(
          width: w,
          label: 'Late / UT',
          value: fmtMinutes(s.lateUndertimeMinutes),
          unit: s.lateUndertimeMinutes < 0.001 ? null : 'mins',
          tone: StatusTone.warning,
        ),
        _CountStatTile(
          width: w,
          label: 'Overtime',
          value: fmtMinutes(s.otMinutes),
          unit: s.otMinutes < 0.001 ? null : 'mins',
          tone: StatusTone.success,
        ),
        _CountStatTile(
          width: w,
          label: 'On Leave',
          value: s.onLeave.toString(),
          unit: 'days',
          tone: AttendanceStatus.onLeave.tone,
        ),
      ];

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(spacing: gap, runSpacing: gap, children: primary),
          if (!widget.compact) ...[
            const SizedBox(height: LuxiumSpacing.md),
            _MoreStatsDisclosure(
              stats: s,
              expanded: _expanded,
              onToggle: () => setState(() => _expanded = !_expanded),
            ),
          ],
        ],
      );
    });
  }
}

/// Ratio tile: `20 / 22 days` + `Nn%` and a thin progress bar.
class _RatioStatTile extends StatelessWidget {
  final double width;
  final String label;
  final int numerator;
  final int denominator;
  final String unit;
  final StatusTone tone;
  const _RatioStatTile({
    required this.width,
    required this.label,
    required this.numerator,
    required this.denominator,
    required this.unit,
    required this.tone,
  });

  @override
  Widget build(BuildContext context) {
    final s = StatusPalette.of(context, tone);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final pct =
        denominator == 0 ? 0.0 : (numerator / denominator).clamp(0.0, 1.0);
    final pctLabel = denominator == 0 ? '' : '${(pct * 100).round()}%';
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.all(LuxiumSpacing.lg),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(LuxiumRadius.lg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                  color: muted,
                )),
            const SizedBox(height: LuxiumSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '$numerator / $denominator',
                  style: TextStyle(
                    fontFamily: 'GeistMono',
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: s.foreground,
                    height: 1,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  unit,
                  style: TextStyle(
                    fontFamily: 'GeistMono',
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: muted,
                  ),
                ),
                const Spacer(),
                if (pctLabel.isNotEmpty)
                  Text(
                    pctLabel,
                    style: TextStyle(
                      fontFamily: 'GeistMono',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: s.foreground,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: LuxiumSpacing.md),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 4,
                backgroundColor: s.background,
                valueColor: AlwaysStoppedAnimation<Color>(s.foreground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Count / duration tile: large mono value + optional unit + label underneath.
class _CountStatTile extends StatelessWidget {
  final double width;
  final String label;
  final String value;
  final String? unit;
  final StatusTone tone;
  const _CountStatTile({
    required this.width,
    required this.label,
    required this.value,
    required this.unit,
    required this.tone,
  });

  @override
  Widget build(BuildContext context) {
    final s = StatusPalette.of(context, tone);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.all(LuxiumSpacing.lg),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(LuxiumRadius.lg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                  color: muted,
                )),
            const SizedBox(height: LuxiumSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontFamily: 'GeistMono',
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: s.foreground,
                    height: 1,
                  ),
                ),
                if (unit != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    unit!,
                    style: TextStyle(
                      fontFamily: 'GeistMono',
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: muted,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Collapsible "More stats" row exposing Rest Days / Regular Holiday /
/// Special Holiday. Rendered as a compact chip strip (not full tiles) so
/// it doesn't compete visually with the primary row.
class _MoreStatsDisclosure extends StatelessWidget {
  final _Stats stats;
  final bool expanded;
  final VoidCallback onToggle;
  const _MoreStatsDisclosure({
    required this.stats,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(LuxiumRadius.lg),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: LuxiumSpacing.sm, vertical: LuxiumSpacing.xs),
            child: Row(
              children: [
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: muted,
                ),
                const SizedBox(width: 4),
                Text(
                  expanded ? 'Hide more stats' : 'More stats',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: muted,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (expanded) ...[
          const SizedBox(height: LuxiumSpacing.sm),
          Wrap(
            spacing: LuxiumSpacing.sm,
            runSpacing: LuxiumSpacing.sm,
            children: [
              _MiniStatChip(
                label: 'Rest Days',
                value: stats.restDays.toString(),
                tone: AttendanceStatus.restDay.tone,
              ),
              _MiniStatChip(
                label: 'Regular Holiday',
                value: stats.regularHoliday.toString(),
                tone: AttendanceStatus.regularHoliday.tone,
              ),
              _MiniStatChip(
                label: 'Special Holiday',
                value: stats.specialHoliday.toString(),
                tone: AttendanceStatus.specialHoliday.tone,
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _MiniStatChip extends StatelessWidget {
  final String label;
  final String value;
  final StatusTone tone;
  const _MiniStatChip({
    required this.label,
    required this.value,
    required this.tone,
  });

  @override
  Widget build(BuildContext context) {
    final s = StatusPalette.of(context, tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: s.background,
        borderRadius: BorderRadius.circular(LuxiumRadius.lg),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              fontFamily: 'GeistMono',
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: s.foreground,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: s.foreground,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Leave balances (unchanged)
// ---------------------------------------------------------------------------

class _LeaveBalances extends StatelessWidget {
  final AsyncValue<List<Map<String, dynamic>>> async;
  const _LeaveBalances({required this.async});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Text(
              'Leave Balance (${DateTime.now().year})',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
          Divider(height: 1, color: Theme.of(context).dividerColor),
          Padding(
            padding: const EdgeInsets.all(16),
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Error: $e',
                  style: const TextStyle(color: Colors.red)),
              data: (rows) {
                if (rows.isEmpty) {
                  return Text(
                    'No leave balances on file.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  );
                }
                return LayoutBuilder(builder: (ctx, c) {
                  final cols = c.maxWidth >= 900
                      ? 4
                      : c.maxWidth >= 600
                          ? 3
                          : c.maxWidth >= 400
                              ? 2
                              : 1;
                  final spacing = 12.0;
                  final w = (c.maxWidth - spacing * (cols - 1)) / cols;
                  return Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: [
                      for (final row in rows)
                        SizedBox(width: w, child: _LeaveCard(row: row)),
                    ],
                  );
                });
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LeaveCard extends StatelessWidget {
  final Map<String, dynamic> row;
  const _LeaveCard({required this.row});

  @override
  Widget build(BuildContext context) {
    final type = (row['leave_types'] as Map?)?['name'] ??
        (row['leave_types'] as Map?)?['code'] ??
        'Leave';
    final opening = _num(row['opening_balance']);
    final accrued = _num(row['accrued']);
    final used = _num(row['used']);
    final remaining = opening + accrued - used;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            type.toString(),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _fmt(remaining),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  '/ ${_fmt(opening + accrued)} days',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Used: ${_fmt(used)} days',
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  static double _num(Object? v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  static String _fmt(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(1);
  }
}

// ---------------------------------------------------------------------------
// Month table
// ---------------------------------------------------------------------------

class _MonthTable extends StatelessWidget {
  final List<_RowVM> rows;
  final DateTime start;
  final DateTime end;
  final bool selectMode;
  final Set<String> selected;
  final void Function(String id, bool value) onRowChecked;
  final ValueChanged<bool> onHeaderChecked;
  final void Function(_RowVM row) onEdit;
  final void Function(_RowVM row) onDelete;

  const _MonthTable({
    required this.rows,
    required this.start,
    required this.end,
    required this.selectMode,
    required this.selected,
    required this.onRowChecked,
    required this.onHeaderChecked,
    required this.onEdit,
    required this.onDelete,
  });

  static const _shortMonths = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _fmtShort(DateTime d) =>
      '${_shortMonths[d.month - 1]} ${d.day}, ${d.year}';

  String _titleForRange() {
    final sameMonth = start.year == end.year && start.month == end.month;
    if (sameMonth) {
      return 'Attendance for ${_monthNames[start.month - 1]} ${start.year}';
    }
    return 'Attendance for ${_fmtShort(start)} → ${_fmtShort(end)}';
  }

  @override
  Widget build(BuildContext context) {
    final recordRows = rows.where((r) => r.record != null).toList();
    final allChecked = recordRows.isNotEmpty &&
        recordRows.every((r) => selected.contains(r.record!.id));
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Text(
              _titleForRange(),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
          Divider(height: 1, color: Theme.of(context).dividerColor),
          SizedBox(
            // Fits ~16 rows visible (48 heading + 16 × 52 = 880). Keeps two
            // weeks of daily attendance on-screen without forcing the user to
            // scroll inside a tiny window.
            height: 900,
            child: rows.isEmpty
                ? Center(
                    child: Text(
                      'No days in range.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : DataTable2(
                    columnSpacing: 12,
                    horizontalMargin: 12,
                    minWidth: 1200,
                    headingRowHeight: 48,
                    dataRowHeight: 52,
                    columns: [
                      if (selectMode)
                        DataColumn2(
                          size: ColumnSize.S,
                          fixedWidth: 48,
                          label: Checkbox(
                            value: allChecked,
                            tristate: false,
                            onChanged: (v) => onHeaderChecked(v ?? false),
                          ),
                        ),
                      const DataColumn2(label: Text('Date'), size: ColumnSize.S),
                      const DataColumn2(label: Text('Day'), size: ColumnSize.S),
                      const DataColumn2(
                          label: Text('Shift'), size: ColumnSize.S),
                      const DataColumn2(
                          label: Text('Clock In'), size: ColumnSize.S),
                      const DataColumn2(
                          label: Text('Clock Out'), size: ColumnSize.S),
                      const DataColumn2(
                          label: Text('Mins'),
                          size: ColumnSize.S,
                          numeric: true),
                      const DataColumn2(
                          label: Text('Status'), size: ColumnSize.M),
                      const DataColumn2(
                          label: Text('Deduction'),
                          size: ColumnSize.S,
                          numeric: true),
                      const DataColumn2(
                          label: Text('Overtime'),
                          size: ColumnSize.S,
                          numeric: true),
                      const DataColumn2(label: Text(''), size: ColumnSize.S, fixedWidth: 0),
                    ],
                    rows: [
                      for (final row in rows) _buildRow(context, row),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  DataRow2 _buildRow(BuildContext context, _RowVM row) {
    final theme = Theme.of(context);
    final onMuted = theme.colorScheme.onSurfaceVariant;
    final hasRecord = row.record != null;
    final isRestOrHoliday = row.dayType.contains('REST') ||
        row.dayType.contains('HOLIDAY');
    final rowColor = isRestOrHoliday
        ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3)
        : null;

    // Shift display
    String shiftText = '—';
    if (row.shift != null) {
      shiftText =
          '${_fmtShiftTime(row.shift!.startTime)} - ${_fmtShiftTime(row.shift!.endTime)}';
    }

    // Late clock-in check
    bool isLateIn = false;
    final tIn = row.record?.actualTimeIn?.toLocal();
    if (tIn != null && row.shift != null && !row.record!.lateInApproved) {
      final scheduled = _applyTime(row.date, row.shift!.startTime)
          .add(Duration(minutes: row.shift!.graceMinutesLate));
      isLateIn = tIn.isAfter(scheduled);
    }

    // Show the *net* values (late time absorbed by OT first) in the table
    // so what the user sees here matches what hits the payslip.
    final ded = row.netDeductionMinutes;
    final ot = row.netOvertimeMinutes;

    return DataRow2(
      color: rowColor == null ? null : WidgetStateProperty.all(rowColor),
      cells: [
        if (selectMode)
          DataCell(
            hasRecord
                ? Checkbox(
                    value: selected.contains(row.record!.id),
                    onChanged: (v) =>
                        onRowChecked(row.record!.id, v ?? false),
                  )
                : const SizedBox.shrink(),
          ),
        DataCell(Text(
            '${_monthNames[row.date.month - 1].substring(0, 3)} ${row.date.day}')),
        DataCell(Text(_weekdayShort(row.date.weekday),
            style: TextStyle(color: onMuted))),
        DataCell(Text(shiftText,
            style: TextStyle(color: row.shift == null ? onMuted : null))),
        DataCell(Text(
          hasRecord ? _fmtClock(row.record!.actualTimeIn) : '—',
          style: TextStyle(
            color: isLateIn ? Colors.red : (hasRecord ? null : onMuted),
            fontWeight: isLateIn ? FontWeight.w600 : null,
          ),
        )),
        DataCell(Text(
          hasRecord ? _fmtClock(row.record!.actualTimeOut) : '—',
          style: TextStyle(color: hasRecord ? null : onMuted),
        )),
        DataCell(Text(
          row.workedMinutes == null ? '—' : fmtDuration(row.workedMinutes!),
          style: TextStyle(
            color: row.workedMinutes == null ? onMuted : null,
            fontFamily: 'GeistMono',
          ),
        )),
        DataCell(_StatusCell(row: row)),
        DataCell(Text(
          ded == 0 ? '—' : fmtDuration(ded),
          style: TextStyle(
            color: ded == 0
                ? onMuted
                : StatusPalette.of(context, StatusTone.warning).foreground,
            fontWeight: ded == 0 ? null : FontWeight.w600,
            fontFamily: 'GeistMono',
          ),
        )),
        DataCell(Text(
          ot == 0 ? '—' : fmtDuration(ot),
          style: TextStyle(
            color: ot == 0
                ? onMuted
                : StatusPalette.of(context, StatusTone.success).foreground,
            fontWeight: ot == 0 ? null : FontWeight.w600,
            fontFamily: 'GeistMono',
          ),
        )),
        // Per-row Actions column intentionally removed — all edits happen via
        // multi-select + batch dialog. Keep empty cell for grid alignment if
        // the table columns expect a trailing cell.
        const DataCell(SizedBox.shrink()),
      ],
    );
  }
}

class _StatusCell extends StatelessWidget {
  final _RowVM row;
  const _StatusCell({required this.row});
  @override
  Widget build(BuildContext context) {
    final worked = row.record?.actualTimeIn != null;
    final status = classifyAttendance(
      status: row.status,
      dayType: row.dayType,
      worked: worked,
    );
    final palette = status.palette(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: palette.background,
            borderRadius: BorderRadius.circular(LuxiumRadius.lg),
          ),
          child: Text(status.label,
              style: TextStyle(
                  color: palette.foreground,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ),
        if (row.holidayName != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              row.holidayName!,
              style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

String _weekdayShort(int w) =>
    const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][(w - 1) % 7];

// ---------------------------------------------------------------------------
// Holiday events for year — scoped to the employee's company.
// ---------------------------------------------------------------------------
/// Holiday events for a SPECIFIC year — independent of the global
/// `selectedHolidayYearProvider` (which the holiday-settings screen mutates).
/// We must fetch by `(companyId, year)` directly so straddling pay periods
/// (e.g. Dec 30 → Jan 14) get holidays from BOTH the December and January
/// calendars, not just the one currently selected in settings.
final _holidayEventsForYearProvider =
    FutureProvider.family<List<CalendarEvent>, int>((ref, year) async {
  final profile = ref.watch(userProfileProvider).asData?.value;
  if (profile == null) return const [];
  final repo = ref.read(holidayRepositoryProvider);
  final cal = await repo.byYear(profile.companyId, year);
  if (cal == null) return const [];
  return repo.events(cal.id);
});

enum _AttendanceViewMode { table, calendar, timeline }

// ---------------------------------------------------------------------------
// Day-by-day timeline — same renderer as the company-wide attendance page,
// rotated so each row is a date for one employee. Selection checkbox + tap-
// to-edit, and edits auto-refresh the bars via Riverpod provider invalidation.
// ---------------------------------------------------------------------------
class _DayTimelineView extends StatelessWidget {
  final List<_RowVM> rows;
  final Set<String> selected;
  final void Function(String recordId, bool checked) onRowChecked;
  final ValueChanged<bool> onHeaderChecked;
  final void Function(_RowVM row) onRowTap;
  const _DayTimelineView({
    required this.rows,
    required this.selected,
    required this.onRowChecked,
    required this.onHeaderChecked,
    required this.onRowTap,
  });

  @override
  Widget build(BuildContext context) {
    final recordRows = rows.where((r) => r.record != null).toList();
    final allChecked = recordRows.isNotEmpty &&
        recordRows.every((r) => selected.contains(r.record!.id));
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header strip — checkbox + date column + 00:00…24:00 hour ticks.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Row(
              children: [
                Checkbox(
                  value: allChecked,
                  tristate: false,
                  onChanged: (v) => onHeaderChecked(v ?? false),
                ),
                const SizedBox(width: 4),
                const SizedBox(
                  width: 110,
                  child: Text('Date',
                      style: TextStyle(fontSize: 11, color: Colors.grey)),
                ),
                const Expanded(child: AttendanceTimelineHeader()),
              ],
            ),
          ),
          const Divider(height: 1),
          for (final row in rows) ...[
            _DayTimelineRow(
              row: row,
              selected: row.record != null && selected.contains(row.record!.id),
              onChecked: row.record == null
                  ? null
                  : (v) => onRowChecked(row.record!.id, v),
              onTap: () => onRowTap(row),
            ),
            const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

class _DayTimelineRow extends StatelessWidget {
  final _RowVM row;
  final bool selected;
  final ValueChanged<bool>? onChecked;
  final VoidCallback onTap;
  const _DayTimelineRow({
    required this.row,
    required this.selected,
    required this.onChecked,
    required this.onTap,
  });

  static const _months = [
    'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final r = row.record;
    final tIn = r?.actualTimeIn?.toLocal();
    final tOut = r?.actualTimeOut?.toLocal();
    final shift = row.shift;

    int? toMin(DateTime? t) => t == null ? null : t.hour * 60 + t.minute;
    int? schedToMin(String? hhmm) {
      if (hhmm == null) return null;
      final parts = hhmm.split(':');
      final h = int.tryParse(parts[0]) ?? 0;
      final m = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
      return h * 60 + m;
    }

    String? emptyLabel;
    Color? emptyColor;
    if (r == null) {
      emptyLabel = 'No record';
    } else if (r.actualTimeIn == null) {
      final st = row.status.toUpperCase();
      if (st == 'ABSENT') {
        emptyLabel = 'Absent';
        emptyColor = const Color(0xFFEF4444);
      } else if (st.contains('LEAVE')) {
        emptyLabel = 'On leave';
        emptyColor = const Color(0xFFA855F7);
      } else if (row.dayType.contains('REST')) {
        emptyLabel = 'Rest day';
      } else if (row.dayType.contains('HOLIDAY')) {
        emptyLabel = row.holidayName ?? 'Holiday';
      }
    }

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Checkbox(
              value: selected,
              onChanged: onChecked == null ? null : (v) => onChecked!(v ?? false),
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: 110,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_months[row.date.month - 1]} ${row.date.day}',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  Text(
                    _weekdayShort(row.date.weekday),
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
            Expanded(
              child: AttendanceDayTimelineBar(
                actualInMin: toMin(tIn),
                actualOutMin: toMin(tOut),
                scheduledInMin: schedToMin(shift?.startTime),
                scheduledOutMin: schedToMin(shift?.endTime),
                earlyInApproved: r?.earlyInApproved ?? false,
                lateOutApproved: r?.lateOutApproved ?? false,
                graceMinutesLate: shift?.graceMinutesLate ?? 0,
                graceMinutesEarlyOut: shift?.graceMinutesEarlyOut ?? 0,
                emptyLabel: emptyLabel,
                emptyLabelColor: emptyColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _fmtShort(DateTime d) {
  const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  return '${m[d.month - 1]} ${d.day}, ${d.year}';
}

// ---------------------------------------------------------------------------
// Range picker bar — replaces single-month nav. Offers prev/next month,
// custom range picker, view-mode toggle (Table/Calendar), and batch buttons.
// ---------------------------------------------------------------------------
class _RangeBar extends StatelessWidget {
  final DateTime start;
  final DateTime end;
  final _AttendanceViewMode viewMode;
  final int selectedCount;
  final bool locked;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToday;
  final VoidCallback onPickRange;
  final ValueChanged<_AttendanceViewMode> onViewModeChanged;
  final VoidCallback onBatchEdit;
  final VoidCallback onBatchDelete;
  const _RangeBar({
    required this.start,
    required this.end,
    required this.viewMode,
    required this.selectedCount,
    required this.onPrev,
    required this.onNext,
    required this.onToday,
    required this.onPickRange,
    required this.onViewModeChanged,
    required this.onBatchEdit,
    required this.onBatchDelete,
    this.locked = false,
  });
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuxiumSpacing.lg),
      child: Wrap(
        spacing: LuxiumSpacing.lg,
        runSpacing: LuxiumSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // Group 1: date-range control (◀ + pill + ▶ + "This month")
          if (locked)
            _DateRangePill(
              label: '${_fmtShort(start)} → ${_fmtShort(end)}',
              onTap: null,
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Previous range',
                  onPressed: onPrev,
                  icon: const Icon(Icons.chevron_left),
                  visualDensity: VisualDensity.compact,
                ),
                _DateRangePill(
                  label: '${_fmtShort(start)} → ${_fmtShort(end)}',
                  onTap: onPickRange,
                ),
                IconButton(
                  tooltip: 'Next range',
                  onPressed: onNext,
                  icon: const Icon(Icons.chevron_right),
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: LuxiumSpacing.sm),
                TextButton(
                  onPressed: onToday,
                  child: Text(
                    'This month',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          // Group 2: view mode toggle
          SegmentedButton<_AttendanceViewMode>(
            segments: const [
              ButtonSegment(
                  value: _AttendanceViewMode.table,
                  label: Text('Table'),
                  icon: Icon(Icons.table_rows, size: 16)),
              ButtonSegment(
                  value: _AttendanceViewMode.calendar,
                  label: Text('Calendar'),
                  icon: Icon(Icons.calendar_month, size: 16)),
              ButtonSegment(
                  value: _AttendanceViewMode.timeline,
                  label: Text('Timeline'),
                  icon: Icon(Icons.timeline, size: 16)),
            ],
            selected: {viewMode},
            onSelectionChanged: (s) => onViewModeChanged(s.first),
          ),
          // Group 3: batch buttons
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton.tonalIcon(
                onPressed: selectedCount == 0 ? null : onBatchEdit,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: Text('Edit ($selectedCount)'),
              ),
              const SizedBox(width: LuxiumSpacing.sm),
              TextButton.icon(
                onPressed: selectedCount == 0 ? null : onBatchDelete,
                icon: const Icon(Icons.delete_outline, size: 16),
                label: Text('Delete ($selectedCount)'),
                style: TextButton.styleFrom(foregroundColor: scheme.error),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Single date-range pill. Read-only when [onTap] is null (payslip embed).
class _DateRangePill extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const _DateRangePill({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final content = Container(
      padding: const EdgeInsets.symmetric(
          horizontal: LuxiumSpacing.md, vertical: LuxiumSpacing.sm),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(LuxiumRadius.lg),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.date_range, size: 14, color: scheme.onSurfaceVariant),
          const SizedBox(width: LuxiumSpacing.sm),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'GeistMono',
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: LuxiumSpacing.sm),
            Icon(Icons.keyboard_arrow_down,
                size: 16, color: scheme.onSurfaceVariant),
          ],
        ],
      ),
    );
    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(LuxiumRadius.lg),
      child: content,
    );
  }
}

// ---------------------------------------------------------------------------
// Range picker dialog — From / To fields with Quick ranges (This month,
// Last 3 months, YTD, etc.). Lets users pick any start/end independently.
// ---------------------------------------------------------------------------
class _RangePickerDialog extends StatefulWidget {
  final DateTime start;
  final DateTime end;
  const _RangePickerDialog({required this.start, required this.end});
  @override
  State<_RangePickerDialog> createState() => _RangePickerDialogState();
}

class _RangePickerDialogState extends State<_RangePickerDialog> {
  late DateTime _s = widget.start;
  late DateTime _e = widget.end;

  Future<void> _pickStart() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _s,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'From',
    );
    if (d != null) setState(() { _s = d; if (_e.isBefore(_s)) _e = _s; });
  }

  Future<void> _pickEnd() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _e.isBefore(_s) ? _s : _e,
      firstDate: _s,
      lastDate: DateTime(2100),
      helpText: 'To',
    );
    if (d != null) setState(() => _e = d);
  }

  @override
  Widget build(BuildContext context) {
    final days = _e.difference(_s).inDays + 1;
    final now = DateTime.now();
    return AlertDialog(
      title: const Text('Attendance range'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(child: OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today, size: 16),
                label: Text('From: ${_fmtShort(_s)}'),
                onPressed: _pickStart,
              )),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today, size: 16),
                label: Text('To: ${_fmtShort(_e)}'),
                onPressed: _pickEnd,
              )),
            ]),
            const SizedBox(height: 10),
            Text('$days day${days == 1 ? '' : 's'} selected',
                style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 14),
            const Text('Quick ranges', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ActionChip(label: const Text('This month'), onPressed: () => setState(() {
                _s = DateTime(now.year, now.month, 1);
                _e = DateTime(now.year, now.month + 1, 0);
              })),
              ActionChip(label: const Text('Last month'), onPressed: () => setState(() {
                _s = DateTime(now.year, now.month - 1, 1);
                _e = DateTime(now.year, now.month, 0);
              })),
              ActionChip(label: const Text('Last 3 months'), onPressed: () => setState(() {
                _s = DateTime(now.year, now.month - 2, 1);
                _e = DateTime(now.year, now.month + 1, 0);
              })),
              ActionChip(label: const Text('Last 6 months'), onPressed: () => setState(() {
                _s = DateTime(now.year, now.month - 5, 1);
                _e = DateTime(now.year, now.month + 1, 0);
              })),
              ActionChip(label: const Text('Year to date'), onPressed: () => setState(() {
                _s = DateTime(now.year, 1, 1);
                _e = DateTime(now.year, now.month + 1, 0);
              })),
            ]),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(context, DateTimeRange(start: _s, end: _e)),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Calendar view — one mini-month per month in the range. Each day is a
// colored cell (status pill) that's tap-selectable for batch editing.
// ---------------------------------------------------------------------------
class _CalendarView extends StatelessWidget {
  final List<_RowVM> rows;
  final Set<String> selected;
  final void Function(_RowVM row) onDayTap;
  const _CalendarView({
    required this.rows,
    required this.selected,
    required this.onDayTap,
  });

  @override
  Widget build(BuildContext context) {
    // Group rows by (year, month)
    final byMonth = <String, List<_RowVM>>{};
    for (final r in rows) {
      final k = '${r.date.year}-${r.date.month}';
      byMonth.putIfAbsent(k, () => []).add(r);
    }
    final keys = byMonth.keys.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final k in keys)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _MonthCalendar(
              rows: byMonth[k]!,
              selected: selected,
              onDayTap: onDayTap,
            ),
          ),
      ],
    );
  }
}

class _MonthCalendar extends StatelessWidget {
  final List<_RowVM> rows;
  final Set<String> selected;
  final void Function(_RowVM row) onDayTap;
  const _MonthCalendar({
    required this.rows,
    required this.selected,
    required this.onDayTap,
  });

  @override
  Widget build(BuildContext context) {
    final first = rows.first.date;
    final monthStart = DateTime(first.year, first.month, 1);
    final monthEnd = DateTime(first.year, first.month + 1, 0);
    // Grid starts on Sunday of the week containing day 1
    final leadingBlanks = monthStart.weekday % 7; // Sun=0
    const monthNames = ['January','February','March','April','May','June','July','August','September','October','November','December'];
    final byDay = <int, _RowVM>{for (final r in rows) r.date.day: r};
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${monthNames[monthStart.month - 1]} ${monthStart.year}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            // Weekday header
            Row(children: const [
              _WeekdayLabel('Sun'), _WeekdayLabel('Mon'), _WeekdayLabel('Tue'),
              _WeekdayLabel('Wed'), _WeekdayLabel('Thu'), _WeekdayLabel('Fri'),
              _WeekdayLabel('Sat'),
            ]),
            const SizedBox(height: 4),
            LayoutBuilder(builder: (ctx, c) {
              final cellW = c.maxWidth / 7;
              final totalCells = leadingBlanks + monthEnd.day;
              final rowsNum = (totalCells / 7).ceil();
              return Column(
                children: [
                  for (int weekIdx = 0; weekIdx < rowsNum; weekIdx++)
                    Row(
                      children: [
                        for (int d = 0; d < 7; d++) _cell(
                          leadingBlanks: leadingBlanks,
                          dayIdx: weekIdx * 7 + d,
                          monthEnd: monthEnd.day,
                          cellW: cellW,
                          byDay: byDay,
                        ),
                      ],
                    ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _cell({
    required int leadingBlanks,
    required int dayIdx,
    required int monthEnd,
    required double cellW,
    required Map<int, _RowVM> byDay,
  }) {
    final dayNum = dayIdx - leadingBlanks + 1;
    if (dayNum < 1 || dayNum > monthEnd) {
      return SizedBox(width: cellW, height: 92);
    }
    final row = byDay[dayNum];
    return SizedBox(
      width: cellW,
      height: 92,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: row == null ? const SizedBox() : _DayCell(row: row, selected: row.record != null && selected.contains(row.record!.id), onTap: onDayTap),
      ),
    );
  }
}

class _WeekdayLabel extends StatelessWidget {
  final String label;
  const _WeekdayLabel(this.label);
  @override
  Widget build(BuildContext context) => Expanded(
        child: Center(
          child: Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600)),
        ),
      );
}

/// Reads the canonical attendance palette from [AttendanceStatus] so calendar
/// cells and table pills stay in lockstep. Falls back to neutral for unknown
/// statuses without minting a one-off palette.
({String label, Color bg, Color fg}) _calendarPillColors(
    BuildContext context, _RowVM row) {
  final worked = row.record?.actualTimeIn != null;
  final s = classifyAttendance(
    status: row.status,
    dayType: row.dayType,
    worked: worked,
  );
  final palette = s.palette(context);
  return (label: s.label, bg: palette.background, fg: palette.foreground);
}

class _DayCell extends StatelessWidget {
  final _RowVM row;
  final bool selected;
  final void Function(_RowVM row) onTap;
  const _DayCell({required this.row, required this.selected, required this.onTap});

  String _hhmm(DateTime t) {
    final local = t.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final pill = _calendarPillColors(context, row);
    final label = pill.label;
    final bg = pill.bg;
    final fg = pill.fg;
    final tIn = row.record?.actualTimeIn;
    final tOut = row.record?.actualTimeOut;
    final ot = row.netOvertimeMinutes;
    final ded = row.netDeductionMinutes;

    return InkWell(
      onTap: () => onTap(row),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(
            color: selected ? Theme.of(context).colorScheme.primary : Colors.black.withValues(alpha: 0.04),
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        padding: const EdgeInsets.all(4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Day number + compact status badge
            Row(
              children: [
                Text('${row.date.day}',
                    style: TextStyle(fontSize: 12, color: fg, fontWeight: FontWeight.w700)),
                const Spacer(),
                Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 9, color: fg, fontWeight: FontWeight.w600)),
              ],
            ),
            // Subtitle: holiday name (e.g. "Maundy Thursday") when it's a holiday
            if ((row.holidayName ?? '').isNotEmpty) ...[
              const SizedBox(height: 1),
              Text(row.holidayName!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 9, color: fg.withValues(alpha: 0.85))),
            ],
            const Spacer(),
            // Clock in / out row (only when present)
            if (tIn != null || tOut != null)
              Text(
                '${tIn == null ? "—" : _hhmm(tIn)} → ${tOut == null ? "—" : _hhmm(tOut)}',
                style: TextStyle(fontSize: 10, color: fg, fontWeight: FontWeight.w500),
              ),
            // OT + deduction chips
            if (ot > 0 || ded > 0) ...[
              const SizedBox(height: 2),
              Row(
                children: [
                  if (ot > 0)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Text('OT ${fmtDuration(ot)}',
                          style: TextStyle(
                            fontSize: 9,
                            fontFamily: 'GeistMono',
                            color: StatusPalette.of(context, StatusTone.success)
                                .foreground,
                            fontWeight: FontWeight.w700,
                          )),
                    ),
                  if (ded > 0)
                    Text('−${fmtDuration(ded)}',
                        style: TextStyle(
                          fontSize: 9,
                          fontFamily: 'GeistMono',
                          color: StatusPalette.of(context, StatusTone.warning)
                              .foreground,
                          fontWeight: FontWeight.w700,
                        )),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
