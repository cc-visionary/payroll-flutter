import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/breakpoints.dart';
import '../../app/shell.dart';
import '../../data/models/attendance_day.dart';
import '../../data/models/employee.dart';
import '../../data/repositories/attendance_repository.dart';
import '../../data/repositories/company_settings_repository.dart';
import '../../data/repositories/employee_repository.dart';
import '../../data/repositories/role_scorecard_repository.dart';
import '../auth/profile_provider.dart';
import '../../widgets/syncing_dialog.dart';
import '../../data/repositories/shift_template_repository.dart';
import '../../data/models/shift_template.dart';
import 'import/attendance_import_dialog.dart';

/// Daily Attendance — single-date view with stats, search, and 3 sub-views:
/// Cards, Table, Timeline. Clicking an employee opens a per-person detail
/// page for that same date.
class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key});
  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

enum _ViewMode { cards, table, timeline }

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> {
  late DateTime _date;
  _ViewMode _mode = _ViewMode.cards;
  String _search = '';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _date = DateTime(now.year, now.month, now.day);
  }

  void _setDate(DateTime d) => setState(() => _date = DateTime(d.year, d.month, d.day));

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) _setDate(picked);
  }

  Future<DateTimeRange?> _pickRange(
    BuildContext context,
    DateTime initStart,
    DateTime initEnd,
    DateTime lastDate,
  ) async {
    return showDialog<DateTimeRange>(
      context: context,
      builder: (_) => _RangePickerDialog(
        initialStart: initStart,
        initialEnd: initEnd,
        firstDate: DateTime(2020),
        lastDate: lastDate,
      ),
    );
  }

  Future<void> _syncFromLark(BuildContext context, String? companyId) async {
    if (companyId == null || companyId.isEmpty) return;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monthStart = DateTime(_date.year, _date.month, 1);
    final rawMonthEnd = DateTime(_date.year, _date.month + 1, 0);
    final monthEnd = rawMonthEnd.isAfter(today) ? today : rawMonthEnd;
    final initStart = monthStart.isAfter(today) ? today : monthStart;
    final picked = await _pickRange(context, initStart, monthEnd, today);
    if (picked == null) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final fromIso = picked.start.toIso8601String().substring(0, 10);
      final toIso = picked.end.toIso8601String().substring(0, 10);
      final res = await runWithSyncingDialog(
        context,
        'Attendance ($fromIso → $toIso)',
        () => Supabase.instance.client.functions.invoke(
          'sync-lark-attendance',
          body: {'company_id': companyId, 'from': fromIso, 'to': toIso},
        ),
      );
      final data = (res.data as Map?) ?? {};
      messenger.showSnackBar(SnackBar(
        content: Text(data['ok'] == true
            ? 'Sync done — created ${data['created']}, updated ${data['updated']}, skipped ${data['skipped']}'
            : 'Sync error: ${data['error'] ?? 'unknown'}'),
      ));
      ref.invalidate(attendanceListProvider);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Sync failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider).asData?.value;
    final employeeFilter =
        (profile != null && !profile.isHrOrAdmin) ? profile.employeeId : null;

    final attendanceAsync = ref.watch(attendanceListProvider(
      AttendanceQuery(start: _date, end: _date, employeeId: employeeFilter),
    ));
    // Only HR/Admin see all employees; a plain EMPLOYEE only sees themselves
    // (their attendance record, if any). Skip the bulk employees fetch in that
    // case so RLS doesn't return an empty list and nuke the view.
    final canSeeAll = profile?.isHrOrAdmin ?? false;
    final employeesAsync = canSeeAll
        ? ref.watch(employeeListProvider(const EmployeeListQuery()))
        : const AsyncValue<List<Employee>>.data(<Employee>[]);
    final cardsAsync = ref.watch(roleScorecardListProvider);
    final shiftsAsync = ref.watch(shiftTemplateListProvider);
    final roleTitleById = <String, String>{
      for (final c in cardsAsync.asData?.value ?? const []) c.id: c.jobTitle,
    };
    final workDaysById = <String, String>{
      for (final c in cardsAsync.asData?.value ?? const []) c.id: c.workDaysPerWeek,
    };
    final shiftById = <String, ShiftTemplate>{
      for (final s in shiftsAsync.asData?.value ?? const <ShiftTemplate>[]) s.id: s,
    };
    final shiftByScorecard = <String, ShiftTemplate>{
      for (final c in cardsAsync.asData?.value ?? const [])
        if (c.id.isNotEmpty && c.shiftTemplateId != null && shiftById[c.shiftTemplateId!] != null)
          c.id: shiftById[c.shiftTemplateId!]!,
    };

    final canSync = profile?.isHrOrAdmin ?? false;
    final flags = ref.watch(attendanceSourceFlagsProvider).asData?.value ??
        const AttendanceSourceFlags(manualCsvEnabled: true, larkEnabled: true);
    final showCsvImport = canSync && flags.manualCsvEnabled;
    final showLarkSync = canSync && flags.larkEnabled;
    return Scaffold(
      drawer: isMobile(context) ? const AppDrawer() : null,
      appBar: AppBar(
        title: const Text('Attendance'),
        actions: [
          if (showCsvImport)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: OutlinedButton.icon(
                onPressed: () => showAttendanceImportDialog(context),
                icon: const Icon(Icons.upload_file_outlined, size: 18),
                label: const Text('Import CSV'),
              ),
            ),
          if (showLarkSync)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.tonalIcon(
                onPressed: () => _syncFromLark(context, profile?.companyId),
                icon: const Icon(Icons.cloud_sync_outlined, size: 18),
                label: const Text('Sync from Lark'),
              ),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DateBar(
              date: _date,
              onPrev: () => _setDate(_date.subtract(const Duration(days: 1))),
              onNext: () => _setDate(_date.add(const Duration(days: 1))),
              onToday: () => _setDate(DateTime.now()),
              onPick: _pickDate,
              mode: _mode,
              onModeChanged: (m) => setState(() => _mode = m),
              onRefresh: () => ref.invalidate(attendanceListProvider),
            ),
            const SizedBox(height: 16),
            _buildBody(attendanceAsync, employeesAsync, roleTitleById, workDaysById, shiftById, shiftByScorecard, canSeeAll),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
    AsyncValue<List<AttendanceDay>> attendanceAsync,
    AsyncValue<List<Employee>> employeesAsync,
    Map<String, String> roleTitleById,
    Map<String, String> workDaysById,
    Map<String, ShiftTemplate> shiftById,
    Map<String, ShiftTemplate> shiftByScorecard,
    bool canSeeAll,
  ) {
    // Surface loading / error states uniformly
    if (attendanceAsync.isLoading || employeesAsync.isLoading) {
      return const Expanded(child: Center(child: CircularProgressIndicator()));
    }
    if (attendanceAsync.hasError) {
      return Expanded(
        child: Center(
          child: Text('Error: ${attendanceAsync.error}',
              style: const TextStyle(color: Colors.red)),
        ),
      );
    }

    final attendanceRecords = attendanceAsync.value ?? const [];
    final employees = employeesAsync.value ?? const [];

    // Build the merged row list — every employee gets a row, whether or not
    // they have an attendance record for this date. Non-admins only see their
    // own attendance row (their employee entry won't be in `employees`).
    final recordByEmpId = <String, AttendanceDay>{
      for (final r in attendanceRecords) r.employeeId: r,
    };

    final activeEmployees = canSeeAll
        ? employees
            .where((e) =>
                e.deletedAt == null && e.employmentStatus == 'ACTIVE')
            .toList()
        : <Employee>[];

    TimeOfDay? toTod(String? hhmmss) {
      if (hhmmss == null || hhmmss.isEmpty) return null;
      final parts = hhmmss.split(':');
      if (parts.length < 2) return null;
      final h = int.tryParse(parts[0]); final m = int.tryParse(parts[1]);
      if (h == null || m == null) return null;
      return TimeOfDay(hour: h, minute: m);
    }

    // Resolve shift for a row: prefer the per-day stored shift (from the Lark
    // sync) if present, falling back to the scorecard's default shift.
    ShiftTemplate? shiftFor(Employee? e, AttendanceDay? rec) {
      final perDay = rec?.shiftTemplateId;
      if (perDay != null && shiftById[perDay] != null) return shiftById[perDay];
      if (e?.roleScorecardId != null) return shiftByScorecard[e!.roleScorecardId];
      return null;
    }

    final rows = <_Row>[];
    for (final e in activeEmployees) {
      final rec = recordByEmpId[e.id];
      final shift = shiftFor(e, rec);
      rows.add(_Row(
        employee: e,
        record: rec,
        roleTitle: e.roleScorecardId != null ? roleTitleById[e.roleScorecardId] : null,
        workDaysPerWeek: e.roleScorecardId != null ? workDaysById[e.roleScorecardId] : null,
        date: _date,
        scheduledIn: toTod(shift?.startTime),
        scheduledOut: toTod(shift?.endTime),
        graceMinutesLate: shift?.graceMinutesLate ?? 0,
        graceMinutesEarlyOut: shift?.graceMinutesEarlyOut ?? 0,
      ));
      recordByEmpId.remove(e.id);
    }
    // Any leftover records (employee not in our active list — e.g. the current
    // user when they're not HR/Admin) still get rendered.
    for (final leftover in recordByEmpId.values) {
      final shift = shiftFor(null, leftover);
      rows.add(_Row(
        employee: null,
        record: leftover,
        roleTitle: null,
        date: _date,
        scheduledIn: toTod(shift?.startTime),
        scheduledOut: toTod(shift?.endTime),
        graceMinutesLate: shift?.graceMinutesLate ?? 0,
        graceMinutesEarlyOut: shift?.graceMinutesEarlyOut ?? 0,
      ));
    }

    rows.sort((a, b) {
      final an = a.employeeNumber ?? '';
      final bn = b.employeeNumber ?? '';
      if (an.isEmpty && bn.isEmpty) return 0;
      if (an.isEmpty) return 1;
      if (bn.isEmpty) return -1;
      return an.compareTo(bn);
    });

    final stats = _Stats.from(rows);

    // Search filter
    final q = _search.trim().toLowerCase();
    final filtered = q.isEmpty
        ? rows
        : rows.where((r) {
            return r.displayName.toLowerCase().contains(q) ||
                (r.employeeNumber ?? '').toLowerCase().contains(q) ||
                (r.roleTitle ?? '').toLowerCase().contains(q);
          }).toList();

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StatsBar(stats: stats),
          const SizedBox(height: 12),
          TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search by name, employee #, or role…',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _search = v),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Card(
              child: filtered.isEmpty
                  ? const Center(child: Text('No employees match.'))
                  : switch (_mode) {
                      _ViewMode.cards => _CardsView(rows: filtered, date: _date),
                      _ViewMode.table => _TableView(rows: filtered, date: _date),
                      _ViewMode.timeline =>
                        _TimelineView(rows: filtered, date: _date),
                    },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Row = one employee + (maybe) their attendance record for the selected date.
// ---------------------------------------------------------------------------
class _Row {
  final Employee? employee;
  final AttendanceDay? record;
  final String? roleTitle;
  final String? workDaysPerWeek;
  final DateTime date;
  // Scheduled shift (parsed HH:mm from shift_templates)
  final TimeOfDay? scheduledIn;
  final TimeOfDay? scheduledOut;
  final int graceMinutesLate;
  final int graceMinutesEarlyOut;
  const _Row({
    required this.employee,
    required this.record,
    required this.roleTitle,
    this.workDaysPerWeek,
    required this.date,
    this.scheduledIn,
    this.scheduledOut,
    this.graceMinutesLate = 0,
    this.graceMinutesEarlyOut = 0,
  });

  String get employeeId => employee?.id ?? record?.employeeId ?? '';
  String? get employeeNumber =>
      employee?.employeeNumber ?? record?.employeeNumber;
  String get displayName {
    if (employee != null) return employee!.fullName;
    final name = [record?.employeeFirstName, record?.employeeLastName]
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .join(' ');
    return name.isNotEmpty ? name : (record?.employeeId ?? '—');
  }

  String get initials {
    final parts = displayName.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '—';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  _Status get status {
    if (record == null) {
      // No attendance row: decide if it's a rest day (not scheduled) vs absent
      if (_isRestDay(date, workDaysPerWeek)) return _Status.restDay;
      return _Status.noData;
    }
    final s = (record!.attendanceStatus).toUpperCase();
    final d = (record!.dayType).toUpperCase();
    if (s.contains('LEAVE') || d.contains('LEAVE')) return _Status.onLeave;
    if (d == 'REST_DAY') return _Status.restDay;
    if (record!.actualTimeIn != null) return _Status.present;
    if (s == 'ABSENT') {
      // Even when sync marked ABSENT, treat as REST_DAY if it's not a workday
      if (_isRestDay(date, workDaysPerWeek)) return _Status.restDay;
      return _Status.absent;
    }
    return _Status.noData;
  }
}

enum _Status { present, absent, onLeave, restDay, noData }

extension on _Status {
  String get label => switch (this) {
        _Status.present => 'Present',
        _Status.absent => 'Absent',
        _Status.onLeave => 'On Leave',
        _Status.restDay => 'Rest Day',
        _Status.noData => 'No Data',
      };
  Color get color => switch (this) {
        _Status.present => const Color(0xFF22C55E),
        _Status.absent => const Color(0xFFEF4444),
        _Status.onLeave => const Color(0xFFA855F7),
        _Status.restDay => const Color(0xFF64748B),
        _Status.noData => const Color(0xFF9CA3AF),
      };
}

/// Parse free-form workDaysPerWeek like "Monday to Saturday" and decide if
/// the given date is OUTSIDE that schedule (= rest day).
bool _isRestDay(DateTime date, String? workDaysPerWeek) {
  const names = <String, int>{
    'sunday': DateTime.sunday,
    'sun': DateTime.sunday,
    'monday': DateTime.monday,
    'mon': DateTime.monday,
    'tuesday': DateTime.tuesday,
    'tue': DateTime.tuesday,
    'tues': DateTime.tuesday,
    'wednesday': DateTime.wednesday,
    'wed': DateTime.wednesday,
    'thursday': DateTime.thursday,
    'thu': DateTime.thursday,
    'thur': DateTime.thursday,
    'thurs': DateTime.thursday,
    'friday': DateTime.friday,
    'fri': DateTime.friday,
    'saturday': DateTime.saturday,
    'sat': DateTime.saturday,
  };
  final dow = date.weekday; // 1=Mon .. 7=Sun
  // Fallback: no info → treat Sunday as rest (standard PH default)
  if (workDaysPerWeek == null || workDaysPerWeek.trim().isEmpty) {
    return dow == DateTime.sunday;
  }
  final s = workDaysPerWeek.toLowerCase();
  final toMatch = RegExp(r'([a-z]+)\s*(?:to|-|–|—|until)\s*([a-z]+)').firstMatch(s);
  if (toMatch != null) {
    final a = names[toMatch.group(1)!];
    final b = names[toMatch.group(2)!];
    if (a != null && b != null) {
      // Inclusive range, wrapping if needed (e.g. Saturday to Thursday)
      if (a <= b) return !(dow >= a && dow <= b);
      return !(dow >= a || dow <= b);
    }
  }
  // Comma/space-separated list: "Monday, Tuesday, Wednesday"
  final tokens = s.split(RegExp(r'[,/;\s]+')).where((t) => t.isNotEmpty).toList();
  final working = tokens.map((t) => names[t]).whereType<int>().toSet();
  if (working.isNotEmpty) return !working.contains(dow);
  // Unparseable → default to Sunday rest
  return dow == DateTime.sunday;
}

// ---------------------------------------------------------------------------
// Stats
// ---------------------------------------------------------------------------
class _Stats {
  final int total;
  final int present;
  final int absent;
  final int onLeave;
  final int restDay;
  final int noData;
  const _Stats({
    required this.total,
    required this.present,
    required this.absent,
    required this.onLeave,
    required this.restDay,
    required this.noData,
  });

  factory _Stats.from(List<_Row> rows) {
    int p = 0, a = 0, l = 0, r = 0, n = 0;
    for (final row in rows) {
      switch (row.status) {
        case _Status.present: p++; break;
        case _Status.absent:  a++; break;
        case _Status.onLeave: l++; break;
        case _Status.restDay: r++; break;
        case _Status.noData:  n++; break;
      }
    }
    return _Stats(total: rows.length, present: p, absent: a, onLeave: l, restDay: r, noData: n);
  }
}

class _StatsBar extends StatelessWidget {
  final _Stats stats;
  const _StatsBar({required this.stats});
  @override
  Widget build(BuildContext context) {
    final pct = stats.total == 0
        ? null
        : '${((stats.present / stats.total) * 100).round()}%';
    final cards = <Widget>[
      _StatCard(label: 'Total', value: stats.total.toString()),
      _StatCard(
        label: 'Present',
        value: stats.present.toString(),
        color: _Status.present.color,
        subtitle: pct,
      ),
      _StatCard(
        label: 'Absent',
        value: stats.absent.toString(),
        color: _Status.absent.color,
      ),
      _StatCard(
        label: 'On Leave',
        value: stats.onLeave.toString(),
        color: _Status.onLeave.color,
      ),
      _StatCard(
        label: 'Rest Day',
        value: stats.restDay.toString(),
        color: _Status.restDay.color,
      ),
      _StatCard(
        label: 'No Data',
        value: stats.noData.toString(),
        color: _Status.noData.color,
      ),
    ];

    if (isMobile(context)) {
      return LayoutBuilder(builder: (ctx, c) {
        const gap = 8.0;
        final cols = (c.maxWidth / 140).floor().clamp(2, 3);
        final itemWidth = (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final card in cards) SizedBox(width: itemWidth, child: card),
          ],
        );
      });
    }

    return Row(
      children: [
        for (int i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: cards[i]),
        ],
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  final String? subtitle;
  const _StatCard({
    required this.label,
    required this.value,
    this.color,
    this.subtitle,
  });
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 12)),
            if (subtitle != null)
              Text(subtitle!,
                  style: TextStyle(fontSize: 11, color: color ?? Colors.grey)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Date bar + mode toggle
// ---------------------------------------------------------------------------
class _DateBar extends StatelessWidget {
  final DateTime date;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToday;
  final VoidCallback onPick;
  final VoidCallback onRefresh;
  final _ViewMode mode;
  final ValueChanged<_ViewMode> onModeChanged;
  const _DateBar({
    required this.date,
    required this.onPrev,
    required this.onNext,
    required this.onToday,
    required this.onPick,
    required this.onRefresh,
    required this.mode,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final weekday = _weekdayName(date.weekday);
    final long = '$weekday, ${_monthName(date.month)} ${date.day}, ${date.year}';
    // Switch to the stacked layout below tablet width — the single-row
    // variant squeezes the long date + segmented button together even on
    // iPad-class screens, so the threshold is higher than the app's global
    // mobile breakpoint.
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 1000;
        return _buildLayout(context, compact: compact, long: long);
      },
    );
  }

  Widget _buildLayout(
    BuildContext context, {
    required bool compact,
    required String long,
  }) {
    final prevBtn =
        IconButton(onPressed: onPrev, icon: const Icon(Icons.chevron_left));
    final pickBtn = OutlinedButton.icon(
      onPressed: onPick,
      icon: const Icon(Icons.calendar_today, size: 16),
      label: Text(date.toIso8601String().substring(0, 10)),
    );
    final nextBtn =
        IconButton(onPressed: onNext, icon: const Icon(Icons.chevron_right));
    final todayBtn =
        OutlinedButton(onPressed: onToday, child: const Text('Today'));
    final refreshBtn = IconButton(
      tooltip: 'Refresh',
      onPressed: onRefresh,
      icon: const Icon(Icons.refresh),
    );
    final segmented = SegmentedButton<_ViewMode>(
      segments: const [
        ButtonSegment(value: _ViewMode.cards, label: Text('Cards')),
        ButtonSegment(value: _ViewMode.table, label: Text('Table')),
        ButtonSegment(value: _ViewMode.timeline, label: Text('Timeline')),
      ],
      selected: {mode},
      onSelectionChanged: (s) => onModeChanged(s.first),
    );

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              prevBtn,
              Expanded(child: pickBtn),
              nextBtn,
              refreshBtn,
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    long,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 8),
                todayBtn,
              ],
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: segmented,
          ),
        ],
      );
    }

    return Row(
      children: [
        prevBtn,
        pickBtn,
        nextBtn,
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            long,
            style: const TextStyle(fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
            softWrap: false,
          ),
        ),
        const SizedBox(width: 8),
        todayBtn,
        const Spacer(),
        segmented,
        const SizedBox(width: 8),
        refreshBtn,
      ],
    );
  }
}

String _weekdayName(int w) => const [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ][(w - 1) % 7];

String _monthName(int m) => const [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ][(m - 1) % 12];

String formatClock(DateTime? t) {
  if (t == null) return '—';
  final local = t.toLocal();
  final h = local.hour;
  final m = local.minute.toString().padLeft(2, '0');
  final period = h >= 12 ? 'PM' : 'AM';
  final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
  return '${h12.toString().padLeft(2, '0')}:$m $period';
}

// ---------------------------------------------------------------------------
// Cards view
// ---------------------------------------------------------------------------
class _CardsView extends StatelessWidget {
  final List<_Row> rows;
  final DateTime date;
  const _CardsView({required this.rows, required this.date});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, c) {
      final cols = (c.maxWidth / 280).floor().clamp(1, 6);
      return GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 2.2,
        ),
        itemCount: rows.length,
        itemBuilder: (_, i) => _EmployeeCard(row: rows[i], date: date),
      );
    });
  }
}

class _EmployeeCard extends StatelessWidget {
  final _Row row;
  final DateTime date;
  const _EmployeeCard({required this.row, required this.date});

  @override
  Widget build(BuildContext context) {
    final status = row.status;
    final bg = status.color.withValues(alpha: 0.08);
    final border = status.color.withValues(alpha: 0.35);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => context.push(
        '/attendance/${row.employeeId}/${date.toIso8601String().substring(0, 10)}',
      ),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: status.color.withValues(alpha: 0.25),
                  child: Text(
                    row.initials,
                    style: TextStyle(
                      color: status.color,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        [row.employeeNumber, row.roleTitle]
                            .whereType<String>()
                            .where((s) => s.isNotEmpty)
                            .join(' • '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Spacer(),
            if (row.record == null)
              Text(
                status.label,
                style: TextStyle(
                  color: status.color,
                  fontWeight: FontWeight.w600,
                ),
              )
            else
              Row(
                children: [
                  _InOutBlock(label: 'IN', time: row.record!.actualTimeIn, color: status.color),
                  const Expanded(
                    child: Icon(Icons.arrow_right_alt, color: Colors.grey, size: 18),
                  ),
                  _InOutBlock(label: 'OUT', time: row.record!.actualTimeOut, color: status.color),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _InOutBlock extends StatelessWidget {
  final String label;
  final DateTime? time;
  final Color color;
  const _InOutBlock({required this.label, required this.time, required this.color});
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        Text(
          formatClock(time),
          style: TextStyle(fontWeight: FontWeight.w700, color: color),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Table view
// ---------------------------------------------------------------------------
class _TableView extends StatelessWidget {
  final List<_Row> rows;
  final DateTime date;
  const _TableView({required this.rows, required this.date});

  @override
  Widget build(BuildContext context) {
    return DataTable2(
      columnSpacing: 16,
      horizontalMargin: 16,
      minWidth: 900,
      columns: const [
        DataColumn2(label: Text('Employee'), size: ColumnSize.L),
        DataColumn2(label: Text('Role'), size: ColumnSize.M),
        DataColumn2(label: Text('Clock In'), size: ColumnSize.S),
        DataColumn2(label: Text('Clock Out'), size: ColumnSize.S),
        DataColumn2(label: Text('Status'), size: ColumnSize.S),
      ],
      rows: rows.map((r) {
        final status = r.status;
        return DataRow2(
          onTap: () => context.push(
            '/attendance/${r.employeeId}/${date.toIso8601String().substring(0, 10)}',
          ),
          cells: [
            DataCell(Row(children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: status.color.withValues(alpha: 0.2),
                child: Text(r.initials,
                    style: TextStyle(
                        color: status.color,
                        fontSize: 10,
                        fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(r.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w500)),
                    Text(r.employeeNumber ?? '—',
                        style:
                            const TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ),
            ])),
            DataCell(Text(r.roleTitle ?? '—')),
            DataCell(Text(formatClock(r.record?.actualTimeIn))),
            DataCell(Text(formatClock(r.record?.actualTimeOut))),
            DataCell(_StatusPill(status: status)),
          ],
        );
      }).toList(),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final _Status status;
  const _StatusPill({required this.status});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: status.color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Timeline view: 06:00 → 18:00 per employee
// ---------------------------------------------------------------------------
class _TimelineView extends StatelessWidget {
  final List<_Row> rows;
  final DateTime date;
  const _TimelineView({required this.rows, required this.date});

  static const int _startHour = 0;
  static const int _endHour = 24;
  static const int _labelStepHours = 2;

  static double nameColWidth(BuildContext context) =>
      isMobile(context) ? 120 : 200;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Hour header
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(
            children: [
              SizedBox(width: nameColWidth(context)),
              Expanded(
                child: LayoutBuilder(builder: (ctx, c) {
                  final hours = _endHour - _startHour;
                  final step = _labelStepHours;
                  final labelCount = (hours ~/ step) + 1;
                  const labelWidth = 36.0;
                  return SizedBox(
                    height: 20,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: List.generate(labelCount, (i) {
                        final hour = _startHour + i * step;
                        final x = ((i * step) / hours) * c.maxWidth;
                        // Last label anchors to the right edge so "24:00" stays
                        // inside the timeline bounds. Others center on their tick.
                        final isLast = i == labelCount - 1;
                        return Positioned(
                          left: isLast
                              ? (c.maxWidth - labelWidth).clamp(0.0, c.maxWidth)
                              : (x - labelWidth / 2).clamp(0.0, c.maxWidth - labelWidth),
                          width: labelWidth,
                          child: Text(
                            '${hour.toString().padLeft(2, '0')}:00',
                            textAlign: isLast ? TextAlign.right : TextAlign.left,
                            style: const TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        );
                      }),
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) =>
                _TimelineRow(row: rows[i], date: date),
          ),
        ),
      ],
    );
  }
}

class _TimelineRow extends StatelessWidget {
  final _Row row;
  final DateTime date;
  const _TimelineRow({required this.row, required this.date});

  @override
  Widget build(BuildContext context) {
    final status = row.status;
    return InkWell(
      onTap: () => context.push(
        '/attendance/${row.employeeId}/${date.toIso8601String().substring(0, 10)}',
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: _TimelineView.nameColWidth(context),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: status.color.withValues(alpha: 0.2),
                    child: Text(row.initials,
                        style: TextStyle(
                            color: status.color,
                            fontSize: 10,
                            fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(row.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                const TextStyle(fontWeight: FontWeight.w500)),
                        Text(row.roleTitle ?? (row.employeeNumber ?? '—'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SizedBox(
                height: 24,
                child: LayoutBuilder(builder: (ctx, c) {
                  return Stack(
                    children: [
                      // Track
                      Positioned.fill(
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.grey.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      // Bar or label
                      ..._buildBar(c.maxWidth, status),
                    ],
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildBar(double width, _Status status) {
    if (row.record == null) {
      return [
        Center(
          child: Text(
            status.label,
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ),
      ];
    }
    final tIn = row.record!.actualTimeIn?.toLocal();
    final tOut = row.record!.actualTimeOut?.toLocal();
    if (tIn == null) {
      return [
        Center(
          child: Text(
            status.label,
            style: TextStyle(fontSize: 11, color: status.color),
          ),
        ),
      ];
    }
    const red = Color(0xFFEF4444);
    const yellow = Color(0xFFF59E0B);
    const green = Color(0xFF22C55E);
    const totalMin = (_TimelineView._endHour - _TimelineView._startHour) * 60;

    final rec = row.record!;
    final sched = row.scheduledIn;
    final schedOut = row.scheduledOut;
    final actualIn = tIn.hour * 60 + tIn.minute;
    final actualOut = tOut == null ? null : tOut.hour * 60 + tOut.minute;
    final schedIn = sched == null ? null : sched.hour * 60 + sched.minute;
    final schedOutM = schedOut == null ? null : schedOut.hour * 60 + schedOut.minute;

    // Build segment list: (startMin, endMin, color, tooltip)
    final segments = <(int, int, Color, String)>[];
    String tip(int s, int e, String desc) => '${_fmtTime(s)} → ${_fmtTime(e)}  •  $desc';

    // Fallback: no shift info → just render one green bar from in→out (15m if no out)
    if (schedIn == null || schedOutM == null) {
      final end = actualOut ?? actualIn + 15;
      segments.add((actualIn, end, green, tip(actualIn, end, 'Worked')));
    } else {
      // 1. Early-in OT segment: [actualIn, schedIn]
      // Only render when approved — unapproved early clock-ins don't count as
      // paid work, so visually the bar starts at the scheduled time.
      if (actualIn < schedIn && rec.earlyInApproved) {
        final mins = schedIn - actualIn;
        final desc = 'Early in ($mins min, approved)';
        segments.add((actualIn, schedIn, green, tip(actualIn, schedIn, desc)));
      }
      // 2. Late-in "missed" segment: [schedIn, actualIn] — always red (undertime,
      // counted against the employee regardless of approval)
      if (actualIn > schedIn + row.graceMinutesLate) {
        final endClamped = actualIn.clamp(schedIn, schedOutM);
        final desc = 'Late in (${actualIn - schedIn} min, undertime)';
        segments.add((schedIn, endClamped, red, tip(schedIn, endClamped, desc)));
      }
      // 3. Normal working segment
      final normStart = actualIn > schedIn ? actualIn : schedIn;
      final normEnd = actualOut == null
          ? schedOutM
          : (actualOut < schedOutM ? actualOut : schedOutM);
      if (normEnd > normStart) {
        segments.add((normStart, normEnd, green, tip(normStart, normEnd, 'Worked')));
      }
      // 4. Early-out segment: [actualOut, schedOutM] — always yellow
      // (undertime, counted against the employee)
      if (actualOut != null && actualOut < schedOutM - row.graceMinutesEarlyOut) {
        final mins = schedOutM - actualOut;
        final desc = 'Early out ($mins min, undertime)';
        segments.add((actualOut, schedOutM, yellow, tip(actualOut, schedOutM, desc)));
      }
      // 5. Late-out / OT segment: [schedOutM, actualOut]
      // Only render when approved — unapproved late clock-outs don't count as
      // paid work, so visually the bar stops at the scheduled end.
      if (actualOut != null && actualOut > schedOutM && rec.lateOutApproved) {
        final mins = actualOut - schedOutM;
        final desc = 'Late out / OT ($mins min, approved)';
        segments.add((schedOutM, actualOut, green, tip(schedOutM, actualOut, desc)));
      }
    }

    // Scheduled start/end ghost markers — thin dashed vertical lines on the
    // track (behind the bars) so users can see "shift was supposed to be here"
    // at a glance without visual noise. Hover tooltip shows the exact time.
    final ghosts = <Widget>[];
    if (schedIn != null) {
      ghosts.add(_ScheduledTick(
        leftPct: schedIn / totalMin,
        trackWidth: width,
        tooltip: 'Scheduled start ${_fmtTime(schedIn)}',
      ));
    }
    if (schedOutM != null) {
      ghosts.add(_ScheduledTick(
        leftPct: schedOutM / totalMin,
        trackWidth: width,
        tooltip: 'Scheduled end ${_fmtTime(schedOutM)}',
      ));
    }

    return [
      ...ghosts,
      for (final seg in segments)
        Positioned(
          left: (seg.$1 / totalMin) * width,
          top: 6,
          bottom: 6,
          width: (((seg.$2 - seg.$1) / totalMin) * width).clamp(2.0, width),
          child: Tooltip(
            message: seg.$4,
            child: Container(
              decoration: BoxDecoration(
                color: seg.$3.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
    ];
  }
}

String _fmtTime(int totalMin) {
  final h = (totalMin ~/ 60) % 24;
  final m = totalMin % 60;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}

/// Thin vertical tick mark showing a scheduled boundary (shift start or end)
/// on the timeline track. Subtle dashed gray line with a tooltip on hover.
class _ScheduledTick extends StatelessWidget {
  final double leftPct; // 0.0 to 1.0 of track width
  final double trackWidth;
  final String tooltip;
  const _ScheduledTick({
    required this.leftPct,
    required this.trackWidth,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    // Wider hit area (8px) so the tooltip triggers reliably over a 1px line
    const hitWidth = 8.0;
    final x = leftPct * trackWidth;
    return Positioned(
      left: x - hitWidth / 2,
      top: 0,
      bottom: 0,
      width: hitWidth,
      child: Tooltip(
        message: tooltip,
        child: CustomPaint(
          painter: _DashedLinePainter(color: Colors.grey.withValues(alpha: 0.7)),
        ),
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  final Color color;
  _DashedLinePainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const dashH = 3.0;
    const gap = 3.0;
    // Draw a vertical dashed line centered in the widget's width so the
    // 1px line sits in the middle of the (wider) hit area used for tooltip.
    final x = size.width / 2;
    double y = 0;
    while (y < size.height) {
      canvas.drawLine(Offset(x, y), Offset(x, y + dashH), paint);
      y += dashH + gap;
    }
  }
  @override
  bool shouldRepaint(covariant _DashedLinePainter old) => old.color != color;
}

// ---------------------------------------------------------------------------
// Two-field date range picker — picks From and To independently via separate
// showDatePicker dialogs. Avoids the built-in showDateRangePicker's UX
// footguns (can't go to prior months when initialDateRange spans current
// month; requires scrolling that isn't obvious on desktop).
// ---------------------------------------------------------------------------
class _RangePickerDialog extends StatefulWidget {
  final DateTime initialStart;
  final DateTime initialEnd;
  final DateTime firstDate;
  final DateTime lastDate;
  const _RangePickerDialog({
    required this.initialStart,
    required this.initialEnd,
    required this.firstDate,
    required this.lastDate,
  });
  @override
  State<_RangePickerDialog> createState() => _RangePickerDialogState();
}

class _RangePickerDialogState extends State<_RangePickerDialog> {
  late DateTime _start = widget.initialStart;
  late DateTime _end = widget.initialEnd;

  Future<void> _pickStart() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: widget.firstDate,
      lastDate: widget.lastDate,
      helpText: 'From',
    );
    if (d != null) {
      setState(() {
        _start = d;
        if (_start.isAfter(_end)) _end = _start;
      });
    }
  }

  Future<void> _pickEnd() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _end.isBefore(_start) ? _start : _end,
      firstDate: _start,
      lastDate: widget.lastDate,
      helpText: 'To',
    );
    if (d != null) setState(() => _end = d);
  }

  void _quickRange(int monthsBack) {
    final today = widget.lastDate;
    final fromMonth = DateTime(today.year, today.month - monthsBack, 1);
    final toMonth = DateTime(today.year, today.month - monthsBack + 1, 0);
    final clampedEnd = toMonth.isAfter(today) ? today : toMonth;
    setState(() {
      _start = fromMonth.isBefore(widget.firstDate) ? widget.firstDate : fromMonth;
      _end = clampedEnd;
    });
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final days = _end.difference(_start).inDays + 1;
    return AlertDialog(
      title: const Text('Sync range from Lark'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text('From: ${_fmt(_start)}'),
                  onPressed: _pickStart,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text('To: ${_fmt(_end)}'),
                  onPressed: _pickEnd,
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Text('$days day${days == 1 ? '' : 's'} selected',
                style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 16),
            const Text('Quick ranges', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _quickChip('This month', () => _quickRange(0)),
              _quickChip('Last month', () => _quickRange(1)),
              _quickChip('Last 2 months', () {
                final today = widget.lastDate;
                setState(() {
                  _start = DateTime(today.year, today.month - 2, 1);
                  _end = today;
                });
              }),
              _quickChip('Last 7 days', () {
                final today = widget.lastDate;
                setState(() {
                  _start = today.subtract(const Duration(days: 6));
                  _end = today;
                });
              }),
              _quickChip('Year to date', () {
                final today = widget.lastDate;
                setState(() {
                  _start = DateTime(today.year, 1, 1);
                  _end = today;
                });
              }),
            ]),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(context, DateTimeRange(start: _start, end: _end)),
          child: const Text('Sync'),
        ),
      ],
    );
  }

  Widget _quickChip(String label, VoidCallback onTap) => ActionChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        onPressed: onTap,
      );
}
