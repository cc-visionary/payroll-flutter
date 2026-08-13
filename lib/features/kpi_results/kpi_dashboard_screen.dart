import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/breakpoints.dart';
import '../../app/shell.dart';
import '../../app/status_colors.dart';
import '../../data/models/department.dart';
import '../../data/models/kpi.dart';
import '../../data/models/kpi_result.dart';
import '../../data/repositories/department_repository.dart';
import '../../data/repositories/role_scorecard_repository.dart';
import 'kpi_results_screen.dart'
    show
        kpiResultsForPeriodProvider,
        periodOf,
        startOfPeriod,
        kpiStatusLabel,
        kpiStatusTone,
        fmtKpiValue;

/// OFF_TRACK first, then NO_DATA, then ON_TRACK -- everywhere on this screen.
/// A dashboard sorted alphabetically buries the only rows that need action;
/// this is what makes it a management-rhythm view instead of a spreadsheet
/// dump. See `KpiStatus`'s own doc comment (`data/models/kpi_result.dart`)
/// for why NO_DATA sits strictly between the two judged states, never after
/// ON_TRACK and never rendered like OFF_TRACK.
int _statusPriority(KpiStatus s) => switch (s) {
  KpiStatus.offTrack => 0,
  KpiStatus.noData => 1,
  KpiStatus.onTrack => 2,
};

/// Orders rows by [_statusPriority] alone -- no invented secondary key (e.g.
/// KPI name) that could coincidentally reproduce the same order on its own
/// and mask a broken priority rule. Rows sharing a status keep whatever
/// order they already had; apply with [mergeSort] (a genuinely STABLE sort
/// -- `List.sort`'s algorithm is not guaranteed stable), so "whatever order
/// they already had" is well-defined rather than an implementation detail.
int _byActionability(KpiResult a, KpiResult b) =>
    _statusPriority(a.status).compareTo(_statusPriority(b.status));

/// HR/admin-facing monthly dashboard: company KPIs, then every department's
/// KPIs, each list sorted off-track-first. This is the view the monthly
/// management rhythm runs on -- read one page and know where to look, rather
/// than scan a flat alphabetical table for red. Reachable only by HR/Admin --
/// see the `/kpi-dashboard` redirect guard in `app/router.dart`.
///
/// Read-only. Recomputing a month's results lives on `/kpi-results`; this
/// screen only reads what has already been computed via
/// [kpiResultsForPeriodProvider], the same provider `KpiResultsScreen` uses.
class KpiDashboardScreen extends ConsumerStatefulWidget {
  const KpiDashboardScreen({super.key});

  @override
  ConsumerState<KpiDashboardScreen> createState() =>
      _KpiDashboardScreenState();
}

class _KpiDashboardScreenState extends ConsumerState<KpiDashboardScreen> {
  late String _period = periodOf(DateTime.now());

  DateTime get _periodStart => startOfPeriod(_period);
  String get _monthLabel => DateFormat('MMMM yyyy').format(_periodStart);

  void _shiftMonth(int delta) {
    final d = DateTime(_periodStart.year, _periodStart.month + delta, 1);
    setState(() => _period = periodOf(d));
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(kpiResultsForPeriodProvider(_period));
    final mobile = isMobile(context);

    return Scaffold(
      drawer: mobile ? const AppDrawer() : null,
      appBar: AppBar(title: const Text('KPI Dashboard')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _monthPicker(context),
            const SizedBox(height: 16),
            Expanded(
              child: async.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Text(
                    'Error: $e',
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
                data: (rows) {
                  // An empty month is EMPTY, not a page of red -- nothing has
                  // been computed yet, which is not the same claim as "every
                  // KPI is off track". See KpiStatus's own doc comment.
                  if (rows.isEmpty) {
                    return Center(
                      child: Text(
                        'Nothing computed for $_monthLabel yet. Run '
                        '"Recompute this month" on KPI Results.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    );
                  }
                  return _DashboardBody(rows: rows);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _monthPicker(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Previous month',
          icon: const Icon(Icons.chevron_left),
          onPressed: () => _shiftMonth(-1),
        ),
        SizedBox(
          width: 150,
          child: Text(
            _monthLabel,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        IconButton(
          tooltip: 'Next month',
          icon: const Icon(Icons.chevron_right),
          onPressed: () => _shiftMonth(1),
        ),
      ],
    );
  }
}

/// Splits [rows] into the company section and one section per department,
/// each independently sorted off-track-first. Watches [kpiLibraryAllProvider]
/// once here (not per row) so every row shares one resolved name/unit map.
class _DashboardBody extends ConsumerWidget {
  final List<KpiResult> rows;
  const _DashboardBody({required this.rows});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kpisAsync = ref.watch(kpiLibraryAllProvider);
    final kpiById = <String, Kpi>{
      for (final k in kpisAsync.asData?.value ?? const <Kpi>[]) k.id: k,
    };

    final company = rows.where((r) => r.scope == KpiScope.company).toList();
    mergeSort(company, compare: _byActionability);

    final deptRows = rows
        .where((r) => r.scope == KpiScope.department)
        .toList();
    final byDept = <String, List<KpiResult>>{};
    for (final r in deptRows) {
      byDept.putIfAbsent(r.departmentId ?? '', () => []).add(r);
    }
    for (final list in byDept.values) {
      mergeSort(list, compare: _byActionability);
    }

    return ListView(
      children: [
        const _SectionHeader('Company'),
        if (company.isEmpty)
          _emptySectionText(context, 'No company KPIs this month.')
        else
          for (final r in company) _KpiRow(result: r, kpi: kpiById[r.kpiId]),
        if (byDept.isNotEmpty) ...[
          const SizedBox(height: 24),
          _DepartmentSections(byDept: byDept, kpiById: kpiById),
        ],
      ],
    );
  }

  Widget _emptySectionText(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(
      text,
      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );
}

/// One section per department, ordered by department name (a secondary,
/// non-actionability axis -- the off-track-first rule governs ROWS within a
/// section, not which department's section comes first).
class _DepartmentSections extends ConsumerWidget {
  final Map<String, List<KpiResult>> byDept;
  final Map<String, Kpi> kpiById;
  const _DepartmentSections({required this.byDept, required this.kpiById});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deptsAsync = ref.watch(departmentListProvider);
    final nameById = <String, String>{
      for (final d in deptsAsync.asData?.value ?? const <Department>[])
        d.id: d.name,
    };

    String labelFor(String id) {
      if (id.isEmpty) return 'Unassigned department';
      return nameById[id] ?? id;
    }

    final ids = byDept.keys.toList()
      ..sort((a, b) => labelFor(a).compareTo(labelFor(b)));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final id in ids) ...[
          _SectionHeader(labelFor(id)),
          for (final r in byDept[id]!) _KpiRow(result: r, kpi: kpiById[r.kpiId]),
          const SizedBox(height: 24),
        ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    ),
  );
}

/// One KPI's row: name, value / target, status chip. The chip reuses
/// `kpiStatusLabel`/`kpiStatusTone` from `kpi_results_screen.dart` verbatim
/// -- NO_DATA must render exactly as it does there (neutral tone, distinct
/// text, `BorderSide.none`), not a second vocabulary that happens to look
/// similar.
class _KpiRow extends StatelessWidget {
  final KpiResult result;
  final Kpi? kpi;
  const _KpiRow({required this.result, this.kpi});

  @override
  Widget build(BuildContext context) {
    final name = kpi?.name ?? result.kpiId;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(name)),
          SizedBox(
            width: 160,
            child: Text(
              '${fmtKpiValue(result.value, kpi)} / '
              '${fmtKpiValue(result.targetSnapshot, kpi)}',
              textAlign: TextAlign.end,
            ),
          ),
          const SizedBox(width: 16),
          StatusChip(
            label: kpiStatusLabel(result.status),
            tone: kpiStatusTone(result.status),
            labelKey: const ValueKey('kpi-status-label'),
          ),
        ],
      ),
    );
  }
}
