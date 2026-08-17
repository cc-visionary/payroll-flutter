import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/breakpoints.dart';
import '../../app/shell.dart';
import '../../app/status_colors.dart';
import '../../data/models/kpi.dart';
import '../../data/models/kpi_input.dart';
import '../../data/models/kpi_result.dart';
import '../../data/models/kpi_source_config.dart' show KpiSourceBinding;
import '../../data/repositories/attendance_repository.dart';
import '../../data/repositories/employee_repository.dart';
import '../../data/repositories/kpi_result_repository.dart';
import '../../data/repositories/kpi_source_config_repository.dart';
import '../../data/repositories/review_cycle_repository.dart';
import '../../data/repositories/role_scorecard_repository.dart';
import '../../widgets/responsive_table.dart';
import '../../widgets/pending_migration_notice.dart';
import 'automatic_sources.dart';
import 'compute_kpi_results.dart';
import 'configured_source.dart';

/// Every `kpi_results` row for one period, across every scope in one call --
/// a recompute (Task 7's `computeResults`) writes company/department/personal
/// rows together, and this is the one read the screen needs regardless of
/// which scope the user is currently looking at. Scope narrowing happens
/// client-side, in [_KpiResultsScreenState._scope].
final kpiResultsForPeriodProvider =
    FutureProvider.family<List<KpiResult>, String>((ref, period) {
      return ref.watch(kpiResultRepositoryProvider).listByPeriod(period);
    });

String _twoDigit(int n) => n.toString().padLeft(2, '0');

/// Public so `kpi_dashboard_screen.dart` shares the exact same period
/// arithmetic rather than a second, potentially drifting copy.
String periodOf(DateTime d) => '${d.year}-${_twoDigit(d.month)}';

DateTime startOfPeriod(String period) {
  final parts = period.split('-');
  return DateTime(int.parse(parts[0]), int.parse(parts[1]), 1);
}

/// The four things a manager can narrow this screen to. `all` shows every
/// scope's rows together -- the default, since a fresh recompute writes all
/// of them and hiding two thirds of the output by default would bury exactly
/// what changed.
enum _ScopeFilter { all, personal, department, company }

KpiScope? _kpiScopeFor(_ScopeFilter f) => switch (f) {
  _ScopeFilter.all => null,
  _ScopeFilter.personal => KpiScope.personal,
  _ScopeFilter.department => KpiScope.department,
  _ScopeFilter.company => KpiScope.company,
};

/// HR/admin-facing monthly results screen: month picker, scope switch, one
/// row per KPI result, and a "Recompute this month" action that runs Task 7's
/// `computeResults` and upserts the output. Reachable only by
/// `UserProfile.isPerformanceAdmin` -- SUPER_ADMIN/ADMIN/HR/HR_ADMIN, not the
/// broader `isHrOrAdmin` (which also admits PAYROLL_ADMIN) most other
/// HR-gated routes use -- see the `/kpi-results` redirect guard in
/// `app/router.dart` and `kPerformanceAdminRoleCodes`'s doc comment
/// (`features/auth/profile_provider.dart`) for why this route is narrower.
///
/// `NO_DATA` must never render the same as `OFF_TRACK`: see the status chip
/// in `_ResultsTable` and the doc comment on `KpiStatus` itself
/// (`data/models/kpi_result.dart`) for why that distinction is the whole
/// point of this table.
class KpiResultsScreen extends ConsumerStatefulWidget {
  const KpiResultsScreen({super.key});

  @override
  ConsumerState<KpiResultsScreen> createState() => _KpiResultsScreenState();
}

class _KpiResultsScreenState extends ConsumerState<KpiResultsScreen> {
  late String _period = periodOf(DateTime.now());
  _ScopeFilter _scope = _ScopeFilter.all;
  bool _recomputing = false;

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
      appBar: AppBar(
        title: const Text('KPI Results'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(
              onPressed: _recomputing ? null : () => _recompute(context),
              icon: _recomputing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              label: const Text('Recompute this month'),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 24,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [_monthPicker(context), _scopeSwitch(context)],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: async.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => PendingMigrationNotice(
                  error: e,
                  feature: 'KPI results',
                ),
                data: (rows) {
                  final wantScope = _kpiScopeFor(_scope);
                  final shown = wantScope == null
                      ? rows
                      : rows.where((r) => r.scope == wantScope).toList();
                  if (shown.isEmpty) {
                    return Center(
                      child: Text(
                        'No results for $_monthLabel'
                        '${wantScope == null ? '' : ' at this scope'}. '
                        'Try "Recompute this month".',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    );
                  }
                  return _ResultsTable(rows: shown);
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

  Widget _scopeSwitch(BuildContext context) {
    return SegmentedButton<_ScopeFilter>(
      segments: const [
        ButtonSegment(value: _ScopeFilter.all, label: Text('All')),
        ButtonSegment(value: _ScopeFilter.personal, label: Text('Personal')),
        ButtonSegment(
          value: _ScopeFilter.department,
          label: Text('Department'),
        ),
        ButtonSegment(value: _ScopeFilter.company, label: Text('Company')),
      ],
      selected: {_scope},
      onSelectionChanged: (selected) =>
          setState(() => _scope = selected.first),
    );
  }

  /// Runs Task 7's `computeResults` for [_period] and upserts the output via
  /// `KpiResultRepository.upsertAll`. Gathers every input `computeResults`
  /// needs itself, since nothing upstream of this screen assembles them:
  /// active KPIs, active+separated employees (population filtering is
  /// `populationFor`'s job, not this method's), role cards, the KPI-to-role
  /// link map, this period's exceptions and readings, and the automatic
  /// source registry.
  Future<void> _recompute(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _recomputing = true);
    try {
      final kpis = await ref.read(kpiLibraryProvider.future);
      final employees = await ref.read(
        employeeListProvider(const EmployeeListQuery()).future,
      );
      final roles = await ref.read(roleScorecardListProvider.future);
      final roleKpiLinks = await ref.read(kpiRoleIdsByKpiProvider.future);

      final resultRepo = ref.read(kpiResultRepositoryProvider);
      final readings = await resultRepo.readingsFor(_period);
      // exceptionsFor is keyed by one kpiId at a time (KpiResultRepository
      // has no "every exception in this period, any KPI" read) --
      // computeResults filters by kpi.id internally, so the merge below just
      // needs every exception a KPI in this recompute could possibly own.
      final exceptions = <KpiException>[
        for (final kpi in kpis)
          ...await resultRepo.exceptionsFor(kpi.id, _period),
      ];

      final attendanceRepo = ref.read(attendanceRepositoryProvider);
      final reviewRepo = ref.read(reviewCycleRepositoryProvider);

      // Task 7 Part D: every ACTIVE `kpi_source_bindings` row becomes one
      // `ConfiguredSource` in the registry, alongside the two code sources.
      // `20260815000002_kpi_source_config.sql` is, as of writing, UNAPPLIED
      // on the live database -- `listBindings()` raises PGRST205 there --
      // so this load is wrapped and degrades to "no configured sources"
      // rather than aborting the whole recompute: code-source and manual
      // KPIs must still compute even when the source-config tables do not
      // exist yet. `kpiResultsForPeriodProvider`'s own `PendingMigrationNotice`
      // (this screen's `error` branch) already tells the user the read side
      // is unavailable; this catch is what keeps WRITING (Recompute) from
      // failing in sympathy with a table Recompute does not even need for
      // every KPI, only for the ones an admin has actually bound.
      final sourceConfigRepo = ref.read(kpiSourceConfigRepositoryProvider);
      List<KpiSourceBinding> activeBindings;
      try {
        // `listBindings()` does NOT filter `is_active` (its own doc comment)
        // -- it returns every binding ever created, retired or not. Only
        // ACTIVE ones belong in the registry: an inactive binding is a
        // deliberately retired configuration, and wiring it in anyway would
        // resurrect a source an admin turned off, silently overriding
        // whatever the KPI is supposed to read now (nothing, or a
        // replacement binding). This filter is the ONLY thing enforcing
        // that -- the repository does not, and `kpi_source_bindings_kpi_active`
        // (the partial unique index) only ever constrains ACTIVE rows
        // against each other, not against inactive history.
        activeBindings = (await sourceConfigRepo.listBindings())
            .where((b) => b.isActive)
            .toList();
      } catch (_) {
        activeBindings = const [];
      }

      final configuredSources = [
        for (final binding in activeBindings)
          ConfiguredSource(
            binding: binding,
            subjectMapReader: sourceConfigRepo.subjectMapFor,
            fetcher: sourceConfigRepo.fetchSourceRows,
            employees: employees,
            roles: roles,
          ),
      ];

      final registry = buildSourceRegistry(
        attendanceRangeReader: attendanceRepo.listByRange,
        // `allReviews()` is safe to wire from ANY caller, HR-gated route or
        // not: it now checks the caller's actual DB role
        // (`callerSeesAllReviews`, review_cycle_repository.dart) and returns
        // `null` instead of RLS's own silently narrowed self/direct-report
        // subset when that role does not grant full-company visibility.
        // `ReviewsCompletedOnTimeSource` reads `null` as NO_DATA, never as a
        // plausible partial count. This screen's own `/kpi-results` route
        // guard (app/router.dart) is a client-side navigation gate and was
        // never the thing making this call safe.
        employeeReviewsReader: reviewRepo.allReviews,
        configured: configuredSources,
      );

      final results = await computeResults(
        period: _period,
        kpis: kpis,
        employees: employees,
        roles: roles,
        registry: registry,
        exceptions: exceptions,
        readings: readings,
        roleKpiLinks: roleKpiLinks,
      );
      await resultRepo.upsertAll(results);
      ref.invalidate(kpiResultsForPeriodProvider(_period));
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Recomputed ${results.length} result(s) for $_monthLabel.',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not recompute: $e')),
      );
    } finally {
      if (mounted) setState(() => _recomputing = false);
    }
  }
}

String _scopeLabel(KpiScope s) => switch (s) {
  KpiScope.personal => 'Personal',
  KpiScope.department => 'Department',
  KpiScope.company => 'Company',
};

/// `NO_DATA` must never look like `OFF_TRACK` -- see the class doc comment on
/// `KpiStatus`. Distinct label AND distinct tint (neutral, not danger);
/// StatusChip already renders tinted background + darker text, no colored
/// border, per PRODUCT.md.
///
/// Public so `kpi_dashboard_screen.dart` renders the exact same chip
/// vocabulary rather than a second, subtly different one -- that distinction
/// is the reason `KpiStatus.noData` exists at all.
String kpiStatusLabel(KpiStatus s) => switch (s) {
  KpiStatus.onTrack => 'On track',
  KpiStatus.offTrack => 'Off track',
  KpiStatus.noData => 'No data',
};

StatusTone kpiStatusTone(KpiStatus s) => switch (s) {
  KpiStatus.onTrack => StatusTone.success,
  KpiStatus.offTrack => StatusTone.danger,
  KpiStatus.noData => StatusTone.neutral,
};

/// A null value/target renders as an em dash, never as `0` or `0%` -- a
/// `NO_DATA` row's null numerator must not turn into an invented number just
/// because this table wants something to print. A REAL zero (e.g. a
/// MANUAL_EXCEPTION KPI whose confirmed count summed to zero) still prints
/// `0`; only the null case is special-cased.
String _fmtNum(num? v) {
  if (v == null) return '—';
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toString();
}

/// Public for the same reason as [kpiStatusLabel] -- shared, not reinvented.
String fmtKpiValue(num? v, Kpi? kpi) {
  final base = _fmtNum(v);
  if (v == null) return base;
  final unit = kpi?.unit?.trim();
  if (unit == null || unit.isEmpty) return base;
  return unit == '%' ? '$base%' : '$base $unit';
}

/// "Where the number came from" -- the KPI's own `data_method` plus, when a
/// registry-backed source could not answer this period, that it could not.
/// Falls back to the result row's own `sourceCompleteness` when the KPI
/// definition is not (yet) loaded, so the column is never blank while the
/// KPI library is still resolving.
String _sourceLabel(KpiResult r, Kpi? kpi) {
  final missing = r.sourceCompleteness == SourceCompleteness.missingSource;
  final method = switch (kpi?.dataMethod) {
    'AUTOMATIC' =>
      'Automatic'
          '${(kpi?.numeratorSource?.trim().isNotEmpty ?? false) ? ' · ${kpi!.numeratorSource}' : ''}',
    'HYBRID' =>
      'Hybrid'
          '${(kpi?.numeratorSource?.trim().isNotEmpty ?? false) ? ' · ${kpi!.numeratorSource}' : ''}',
    'MANUAL_EXCEPTION' => 'Manual (exception)',
    'MANUAL_PERIODIC' => 'Manual (periodic)',
    _ => null,
  };
  if (method == null) return missing ? 'Missing source' : 'Complete';
  return missing ? '$method — missing' : method;
}

class _ResultsTable extends ConsumerWidget {
  final List<KpiResult> rows;
  const _ResultsTable({required this.rows});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kpisAsync = ref.watch(kpiLibraryAllProvider);
    final kpiById = <String, Kpi>{
      for (final k in kpisAsync.asData?.value ?? const <Kpi>[]) k.id: k,
    };

    String nameOf(KpiResult r) => kpiById[r.kpiId]?.name ?? r.kpiId;
    final sorted = [...rows]..sort((a, b) {
      final byName = nameOf(a).compareTo(nameOf(b));
      if (byName != 0) return byName;
      return a.scope.index.compareTo(b.scope.index);
    });

    return SingleChildScrollView(
      child: ResponsiveTable(
        fullWidth: true,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('KPI')),
            DataColumn(label: Text('Scope')),
            DataColumn(label: Text('Value')),
            DataColumn(label: Text('Target')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Source')),
          ],
          rows: [
            for (final r in sorted)
              DataRow(
                key: ValueKey(
                  r.id ??
                      '${r.kpiId}|${r.scope}|${r.employeeId}|${r.departmentId}',
                ),
                cells: [
                  DataCell(Text(nameOf(r))),
                  DataCell(Text(_scopeLabel(r.scope))),
                  DataCell(Text(fmtKpiValue(r.value, kpiById[r.kpiId]))),
                  DataCell(
                    Text(fmtKpiValue(r.targetSnapshot, kpiById[r.kpiId])),
                  ),
                  DataCell(
                    StatusChip(
                      label: kpiStatusLabel(r.status),
                      tone: kpiStatusTone(r.status),
                    ),
                  ),
                  DataCell(Text(_sourceLabel(r, kpiById[r.kpiId]))),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
