import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/breakpoints.dart';
import '../../../app/theme.dart';
import '../../../data/models/department.dart';
import '../../../data/models/employee.dart';
import '../../../data/models/kpi.dart';
import '../../../data/models/kpi_result.dart' show KpiScope;
import '../../../data/models/kpi_source_config.dart';
import '../../../data/repositories/department_repository.dart';
import '../../../data/repositories/employee_repository.dart';
import '../../../data/repositories/kpi_source_config_repository.dart';
import '../../../data/repositories/role_scorecard_repository.dart'
    show kpiLibraryProvider, roleScorecardListProvider;
import '../../../widgets/pending_migration_notice.dart';
import '../../../widgets/responsive_table.dart';
import '../../auth/profile_provider.dart';
import '../../kpi_results/configured_source.dart';
import '../../kpi_results/kpi_results_screen.dart' show periodOf, startOfPeriod;
import '../../kpi_results/sql_identifier.dart';

/// Said inline, at the point of typing, whenever `object_name` or one of the
/// four `*_column` fields fails [isValidSqlIdentifier]. This exact string is
/// public so `kpi_sources_settings_screen_test.dart` can assert on it
/// directly rather than re-deriving it -- see that test's "an invalid
/// identifier blocks save and says why".
const kInvalidSourceIdentifierMessage =
    'Letters, digits and underscores only; must start with a letter or '
    'underscore.';

/// Shown by [_KpiSourcesSettingsScreenState._openBindingDialog] when
/// [KpiSourceConfigRepository.upsertBinding] succeeds but the follow-up
/// [KpiSourceConfigRepository.setKpiNumeratorSource] write fails. The two
/// writes are sequential and non-transactional; by this point the binding
/// row itself DID change, so a plain "Could not save" would be a lie. This
/// is deliberately not turned into a transaction or given a rollback --
/// see this file's fix-wave note -- because the failure mode is the same
/// either way: `computeResults` only ever resolves a KPI's source via
/// `kpis.numerator_source`, so an unlinked KPI already reads NO_DATA, and
/// a rollback would not make that any less true. The fix owed here is an
/// honest message, not a different data outcome.
const kBindingSavedButLinkFailedMessage =
    'Binding saved, but linking it to this KPI failed';

/// Same shape as [kBindingSavedButLinkFailedMessage], for
/// [_KpiSourcesSettingsScreenState._confirmUnbind]:
/// [KpiSourceConfigRepository.deleteBinding] succeeds but the follow-up
/// [KpiSourceConfigRepository.setKpiNumeratorSource] clear fails, leaving
/// `kpis.numerator_source` pointing at a `cfg:<kpiId>` key the deleted
/// binding no longer answers to.
const kBindingRemovedButUnlinkFailedMessage =
    'Binding removed, but clearing this KPI\'s link to it failed';

/// Settings ▸ KPI Sources -- where a KPI is pointed at a table in an
/// external database and computes with no code change.
///
/// Three sections, top to bottom: **connections** (a named external
/// database), **bindings** (which table/columns answer one KPI, one per row
/// in the library), and the **subject map** for whichever connection is
/// currently selected (a source's own key -- a staff id, an email --
/// resolved to this app's employee or department).
///
/// Saving or clearing a binding also writes `kpis.numerator_source` via
/// [KpiSourceConfigRepository.setKpiNumeratorSource] -- see that method's
/// doc comment for why this is the ONE place this screen touches the `kpis`
/// table, and why it is never routed through
/// `RoleScorecardRepository.saveLibraryKpi(..., writeDefinition: true)`.
/// Without it, `computeResults` (`compute_kpi_results.dart:332,367`) would
/// never find the [ConfiguredSource] this binding is meant to activate --
/// an admin would configure a binding, this screen would report success,
/// and the KPI would silently read NO_DATA forever.
///
/// These three tables ship in `20260815000002_kpi_source_config.sql`,
/// unapplied at the time this screen was written -- every read below fails
/// PGRST205 until an administrator runs the pending migration. Each section
/// renders [PendingMigrationNotice] for that case instead of a raw
/// Postgrest error, the same pattern `KpiDashboardScreen` already uses.
class KpiSourcesSettingsScreen extends ConsumerStatefulWidget {
  const KpiSourcesSettingsScreen({super.key});

  @override
  ConsumerState<KpiSourcesSettingsScreen> createState() =>
      _KpiSourcesSettingsScreenState();
}

class _KpiSourcesSettingsScreenState
    extends ConsumerState<KpiSourcesSettingsScreen> {
  String? _subjectMapConnectionId;

  String get _companyId =>
      ref.read(userProfileProvider).asData?.value?.companyId ?? '';

  @override
  Widget build(BuildContext context) {
    final mobile = isMobile(context);
    return SingleChildScrollView(
      padding: EdgeInsets.all(mobile ? 16 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('KPI Sources', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          const Text(
            'Point a KPI at a table in an external database so it computes '
            'automatically -- no code change, no developer.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),
          _connectionsSection(context),
          const SizedBox(height: 24),
          _bindingsSection(context),
          const SizedBox(height: 24),
          _subjectMapSection(context),
        ],
      ),
    );
  }

  // ===========================================================================
  // Connections
  // ===========================================================================

  Widget _connectionsSection(BuildContext context) {
    final async = ref.watch(kpiConnectionsProvider);
    return _Section(
      title: 'Connections',
      subtitle: 'External databases a KPI can read from.',
      action: FilledButton.icon(
        key: const Key('addConnectionButton'),
        onPressed: () => _openConnectionDialog(context),
        icon: const Icon(Icons.add, size: 18),
        label: const Text('Add connection'),
      ),
      child: async.when(
        loading: () => const _SectionLoading(),
        error: (e, _) =>
            PendingMigrationNotice(error: e, feature: 'KPI source connections'),
        data: (conns) => conns.isEmpty
            ? const Text('No connections yet.', style: TextStyle(color: Colors.grey))
            : _connectionsTable(context, conns),
      ),
    );
  }

  Widget _connectionsTable(BuildContext context, List<KpiConnection> conns) {
    return ResponsiveTable(
      fullWidth: true,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Name')),
          DataColumn(label: Text('Kind')),
          DataColumn(label: Text('Host')),
          DataColumn(label: Text('Database')),
          DataColumn(label: Text('User')),
          DataColumn(label: Text('Active')),
          DataColumn(label: Text('')),
        ],
        rows: [
          for (final c in conns)
            DataRow(
              key: ValueKey('connection-${c.id}'),
              cells: [
                DataCell(Text(c.name)),
                DataCell(Text(c.kind)),
                DataCell(Text('${c.host}:${c.port}', style: AppTheme.mono(context))),
                DataCell(Text(c.database)),
                DataCell(Text(c.dbUser)),
                DataCell(
                  Icon(
                    c.isActive ? Icons.check_circle : Icons.remove_circle_outline,
                    size: 18,
                    color: c.isActive
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                DataCell(
                  IconButton(
                    key: Key('editConnection-${c.id}'),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    tooltip: 'Edit connection',
                    onPressed: () => _openConnectionDialog(context, existing: c),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _openConnectionDialog(
    BuildContext context, {
    KpiConnection? existing,
  }) async {
    final companyId = _companyId.isNotEmpty ? _companyId : (existing?.companyId ?? '');
    final messenger = ScaffoldMessenger.of(context);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _ConnectionFormDialog(
        existing: existing,
        companyId: companyId,
        onSave: (connection) async {
          try {
            await ref
                .read(kpiSourceConfigRepositoryProvider)
                .upsertConnection(connection);
            ref.invalidate(kpiConnectionsProvider);
            if (dialogContext.mounted) Navigator.pop(dialogContext);
          } catch (e) {
            messenger.showSnackBar(
              SnackBar(content: Text('Could not save the connection: $e')),
            );
          }
        },
      ),
    );
  }

  // ===========================================================================
  // Bindings
  // ===========================================================================

  Widget _bindingsSection(BuildContext context) {
    final kpisAsync = ref.watch(kpiLibraryProvider);
    final bindingsAsync = ref.watch(kpiSourceBindingsProvider);
    final connectionsAsync = ref.watch(kpiConnectionsProvider);

    final error = kpisAsync.error ?? bindingsAsync.error ?? connectionsAsync.error;
    Widget body;
    if (error != null) {
      body = PendingMigrationNotice(error: error, feature: 'KPI bindings');
    } else if (!kpisAsync.hasValue ||
        !bindingsAsync.hasValue ||
        !connectionsAsync.hasValue) {
      body = const _SectionLoading();
    } else {
      body = _bindingsTable(
        context,
        kpisAsync.value!,
        bindingsAsync.value!,
        connectionsAsync.value!,
      );
    }

    return _Section(
      title: 'Bindings',
      subtitle: 'Which table and columns answer each KPI, one per row in the '
          'library.',
      child: body,
    );
  }

  KpiSourceBinding? _activeBindingFor(String kpiId, List<KpiSourceBinding> all) {
    for (final b in all) {
      if (b.kpiId == kpiId && b.isActive) return b;
    }
    return null;
  }

  Widget _bindingsTable(
    BuildContext context,
    List<Kpi> kpis,
    List<KpiSourceBinding> bindings,
    List<KpiConnection> connections,
  ) {
    if (kpis.isEmpty) {
      return const Text(
        'No KPIs in the library yet.',
        style: TextStyle(color: Colors.grey),
      );
    }
    final connectionsById = {for (final c in connections) c.id: c};

    return ResponsiveTable(
      fullWidth: true,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('KPI')),
          DataColumn(label: Text('Source')),
          DataColumn(label: Text('')),
        ],
        rows: [
          for (final kpi in kpis)
            DataRow(
              key: ValueKey('binding-row-${kpi.id}'),
              cells: [
                DataCell(Text(kpi.name)),
                DataCell(
                  _bindingCell(
                    context,
                    _activeBindingFor(kpi.id, bindings),
                    connectionsById,
                  ),
                ),
                DataCell(
                  _bindingActions(
                    context,
                    kpi,
                    _activeBindingFor(kpi.id, bindings),
                    connections,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _bindingCell(
    BuildContext context,
    KpiSourceBinding? binding,
    Map<String?, KpiConnection> connectionsById,
  ) {
    if (binding == null) {
      return const Text('Not bound', style: TextStyle(color: Colors.grey));
    }
    final conn = connectionsById[binding.connectionId];
    return Text(
      '${conn?.name ?? binding.connectionId} · ${binding.objectName}',
      style: AppTheme.mono(context, fontSize: 12),
    );
  }

  Widget _bindingActions(
    BuildContext context,
    Kpi kpi,
    KpiSourceBinding? existing,
    List<KpiConnection> connections,
  ) {
    if (connections.isEmpty) {
      return const Text(
        'Add a connection first',
        style: TextStyle(color: Colors.grey, fontSize: 12),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          key: Key('bind-${kpi.id}'),
          onPressed: () => _openBindingDialog(
            context,
            kpi: kpi,
            existing: existing,
            connections: connections,
          ),
          child: Text(existing == null ? 'Bind' : 'Edit'),
        ),
        if (existing != null)
          IconButton(
            key: Key('unbind-${kpi.id}'),
            icon: const Icon(Icons.link_off, size: 18),
            tooltip: 'Unbind',
            onPressed: () => _confirmUnbind(context, kpi: kpi, binding: existing),
          ),
        // Only EMPLOYEE/DEPARTMENT bindings have a subject to map at all --
        // a NONE-kind binding produces a single company figure with no
        // identity behind it, so "unmapped keys" is meaningless for it. See
        // ConfiguredSource.readDetailed: it never populates
        // unresolvedSubjectKeys for SubjectKind.none.
        if (existing != null && existing.subjectKind != SubjectKind.none)
          IconButton(
            key: Key('checkUnmapped-${kpi.id}'),
            icon: const Icon(Icons.search, size: 18),
            tooltip: 'Check for unmapped keys',
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => _UnmappedKeysDialog(
                kpi: kpi,
                binding: existing,
                companyId: _companyId,
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _openBindingDialog(
    BuildContext context, {
    required Kpi kpi,
    required KpiSourceBinding? existing,
    required List<KpiConnection> connections,
  }) async {
    final companyId = _companyId.isNotEmpty ? _companyId : (existing?.companyId ?? '');
    final messenger = ScaffoldMessenger.of(context);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _BindingFormDialog(
        kpi: kpi,
        existing: existing,
        connections: connections,
        companyId: companyId,
        onSave: (binding) async {
          final repo = ref.read(kpiSourceConfigRepositoryProvider);
          // Two sequential, non-transactional writes. `bindingSaved` tracks
          // which one failed so the catch below can say so honestly --
          // see kBindingSavedButLinkFailedMessage's doc comment for why
          // this is not instead turned into a transaction/rollback.
          var bindingSaved = false;
          try {
            await repo.upsertBinding(binding);
            bindingSaved = true;
            // Task 8's non-negotiable: the KPI's own numerator_source must
            // track the binding's active state, or computeResults never
            // finds this source at all. See setKpiNumeratorSource's doc
            // comment.
            await repo.setKpiNumeratorSource(
              kpi.id,
              binding.isActive ? 'cfg:${kpi.id}' : null,
            );
            ref.invalidate(kpiSourceBindingsProvider);
            if (dialogContext.mounted) Navigator.pop(dialogContext);
          } catch (e) {
            if (bindingSaved) {
              // The binding row did change -- refresh the list to reflect
              // it even though the KPI link failed.
              ref.invalidate(kpiSourceBindingsProvider);
            }
            final message = bindingSaved
                ? '$kBindingSavedButLinkFailedMessage: $e. This KPI will '
                    'read as having no data until it is saved again.'
                : 'Could not save the binding: $e';
            messenger.showSnackBar(SnackBar(content: Text(message)));
          }
        },
      ),
    );
  }

  Future<void> _confirmUnbind(
    BuildContext context, {
    required Kpi kpi,
    required KpiSourceBinding binding,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Unbind ${kpi.name}?'),
        content: const Text(
          'This KPI stops computing from this source. Past results are kept '
          '-- new periods read NO_DATA until it is bound again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Unbind'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final repo = ref.read(kpiSourceConfigRepositoryProvider);
    // Same two-non-transactional-writes shape as _openBindingDialog's
    // onSave above -- see kBindingRemovedButUnlinkFailedMessage's doc
    // comment.
    var bindingDeleted = false;
    try {
      await repo.deleteBinding(binding.id!);
      bindingDeleted = true;
      // Clears the KPI's numerator_source too -- an unbound KPI must not
      // keep pointing at a registry key nothing answers to any more. See
      // setKpiNumeratorSource's doc comment.
      await repo.setKpiNumeratorSource(kpi.id, null);
      ref.invalidate(kpiSourceBindingsProvider);
    } catch (e) {
      if (bindingDeleted) {
        ref.invalidate(kpiSourceBindingsProvider);
      }
      final message = bindingDeleted
          ? '$kBindingRemovedButUnlinkFailedMessage: $e. This KPI will '
              'read as having no data until it is bound again.'
          : 'Could not unbind: $e';
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  // ===========================================================================
  // Subject map
  // ===========================================================================

  Widget _subjectMapSection(BuildContext context) {
    final connectionsAsync = ref.watch(kpiConnectionsProvider);
    return _Section(
      title: 'Subject Map',
      subtitle: 'How one source\'s own key -- a staff id, an email -- resolves '
          'to an employee or department here.',
      child: connectionsAsync.when(
        loading: () => const _SectionLoading(),
        error: (e, _) =>
            PendingMigrationNotice(error: e, feature: 'KPI subject mapping'),
        data: (connections) => _subjectMapBody(context, connections),
      ),
    );
  }

  Widget _subjectMapBody(BuildContext context, List<KpiConnection> connections) {
    if (connections.isEmpty) {
      return const Text(
        'Add a connection first.',
        style: TextStyle(color: Colors.grey),
      );
    }
    _subjectMapConnectionId ??= connections.first.id;
    final selected = connections.firstWhere(
      (c) => c.id == _subjectMapConnectionId,
      orElse: () => connections.first,
    );
    final connectionId = selected.id!;

    final employees =
        ref.watch(employeeListProvider(const EmployeeListQuery())).asData?.value ??
            const <Employee>[];
    final departments =
        ref.watch(departmentListProvider).asData?.value ?? const <Department>[];

    final mapAsync = ref.watch(kpiSubjectMapProvider(connectionId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                key: const Key('subjectMapConnection'),
                initialValue: connectionId,
                decoration: const InputDecoration(labelText: 'Connection'),
                items: [
                  for (final c in connections)
                    DropdownMenuItem(value: c.id, child: Text(c.name)),
                ],
                onChanged: (v) => setState(() => _subjectMapConnectionId = v),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              key: const Key('addSubjectMappingButton'),
              onPressed: () => _openSubjectMapDialog(
                context,
                connectionId: connectionId,
                employees: employees,
                departments: departments,
              ),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add mapping'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        mapAsync.when(
          loading: () => const _SectionLoading(),
          error: (e, _) =>
              PendingMigrationNotice(error: e, feature: 'KPI subject mapping'),
          data: (rows) => rows.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    'No mappings yet for this connection.',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : _subjectMapTable(context, rows, employees, departments),
        ),
      ],
    );
  }

  Widget _subjectMapTable(
    BuildContext context,
    List<KpiSubjectMap> rows,
    List<Employee> employees,
    List<Department> departments,
  ) {
    final employeeNameById = {for (final e in employees) e.id: e.fullName};
    final departmentNameById = {for (final d in departments) d.id: d.name};

    String targetLabel(KpiSubjectMap m) {
      if (m.employeeId != null) {
        return 'Employee: ${employeeNameById[m.employeeId] ?? m.employeeId}';
      }
      return 'Department: ${departmentNameById[m.departmentId] ?? m.departmentId}';
    }

    return ResponsiveTable(
      fullWidth: true,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('External key')),
          DataColumn(label: Text('Maps to')),
          DataColumn(label: Text('')),
        ],
        rows: [
          for (final m in rows)
            DataRow(
              key: ValueKey('subject-map-${m.id}'),
              cells: [
                DataCell(Text(m.externalKey, style: AppTheme.mono(context, fontSize: 12))),
                DataCell(Text(targetLabel(m))),
                DataCell(
                  IconButton(
                    key: Key('deleteSubjectMap-${m.id}'),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    tooltip: 'Remove mapping',
                    onPressed: () => _deleteSubjectMap(context, m),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _openSubjectMapDialog(
    BuildContext context, {
    required String connectionId,
    required List<Employee> employees,
    required List<Department> departments,
  }) async {
    final companyId = _companyId;
    final messenger = ScaffoldMessenger.of(context);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _SubjectMapFormDialog(
        connectionId: connectionId,
        companyId: companyId,
        employees: employees,
        departments: departments,
        onSave: (mapping) async {
          try {
            await ref
                .read(kpiSourceConfigRepositoryProvider)
                .upsertSubjectMapping(mapping);
            ref.invalidate(kpiSubjectMapProvider(connectionId));
            if (dialogContext.mounted) Navigator.pop(dialogContext);
          } catch (e) {
            messenger.showSnackBar(
              SnackBar(content: Text('Could not save the mapping: $e')),
            );
          }
        },
      ),
    );
  }

  Future<void> _deleteSubjectMap(BuildContext context, KpiSubjectMap m) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(kpiSourceConfigRepositoryProvider)
          .deleteSubjectMapping(m.id!);
      ref.invalidate(kpiSubjectMapProvider(m.connectionId));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not remove mapping: $e')));
    }
  }
}

// ===========================================================================
// Shared section chrome
// ===========================================================================

class _Section extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? action;
  final Widget child;

  const _Section({
    required this.title,
    required this.subtitle,
    this.action,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // A Card, not a plain decorated Container: PendingMigrationNotice's
    // ExpansionTile (rendered as `child` on the pending-migration path)
    // paints its ListTile's background and ink splashes on the nearest
    // Material ancestor. A Container's BoxDecoration has no Material of its
    // own, so an opaque background painted between the ListTile and the
    // Scaffold's own Material hides those effects -- Flutter flags this as
    // an error at build time. Card wraps its child in a Material for free,
    // so this keeps the section's 6px-radius bordered look (Luxium's radius
    // rule) while giving every descendant a proper ink surface.
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                ?action,
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _SectionLoading extends StatelessWidget {
  const _SectionLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

// ===========================================================================
// Connection form
// ===========================================================================

class _ConnectionFormDialog extends StatefulWidget {
  final KpiConnection? existing;
  final String companyId;
  final Future<void> Function(KpiConnection) onSave;

  const _ConnectionFormDialog({
    required this.existing,
    required this.companyId,
    required this.onSave,
  });

  @override
  State<_ConnectionFormDialog> createState() => _ConnectionFormDialogState();
}

class _ConnectionFormDialogState extends State<_ConnectionFormDialog> {
  late final TextEditingController _name;
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _database;
  late final TextEditingController _dbSchema;
  late final TextEditingController _dbUser;
  late final TextEditingController _credentialRef;
  String _kind = 'POSTGRES';
  String _credentialKind = 'ENV';
  bool _isActive = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _host = TextEditingController(text: e?.host ?? '');
    _port = TextEditingController(text: (e?.port ?? 5432).toString());
    _database = TextEditingController(text: e?.database ?? '');
    _dbSchema = TextEditingController(text: e?.dbSchema ?? 'public');
    _dbUser = TextEditingController(text: e?.dbUser ?? '');
    _credentialRef = TextEditingController(text: e?.credentialRef ?? '');
    _kind = e?.kind ?? 'POSTGRES';
    _credentialKind = e?.credentialKind ?? 'ENV';
    _isActive = e?.isActive ?? true;
    for (final c in [_name, _host, _port, _database, _dbSchema, _dbUser, _credentialRef]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _port.dispose();
    _database.dispose();
    _dbSchema.dispose();
    _dbUser.dispose();
    _credentialRef.dispose();
    super.dispose();
  }

  bool get _canSave =>
      !_saving &&
      _name.text.trim().isNotEmpty &&
      _host.text.trim().isNotEmpty &&
      int.tryParse(_port.text.trim()) != null &&
      _database.text.trim().isNotEmpty &&
      _dbSchema.text.trim().isNotEmpty &&
      _dbUser.text.trim().isNotEmpty &&
      _credentialRef.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add connection' : 'Edit connection'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const Key('connectionName'),
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                isExpanded: true,
                key: const Key('connectionKind'),
                initialValue: _kind,
                decoration: const InputDecoration(labelText: 'Kind'),
                items: const [
                  DropdownMenuItem(value: 'POSTGRES', child: Text('Postgres')),
                  DropdownMenuItem(value: 'SUPABASE', child: Text('Supabase')),
                ],
                onChanged: (v) => setState(() => _kind = v ?? 'POSTGRES'),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('connectionHost'),
                controller: _host,
                decoration: const InputDecoration(labelText: 'Host'),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('connectionPort'),
                controller: _port,
                decoration: const InputDecoration(labelText: 'Port'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('connectionDatabase'),
                controller: _database,
                decoration: const InputDecoration(labelText: 'Database'),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('connectionSchema'),
                controller: _dbSchema,
                decoration: const InputDecoration(labelText: 'Schema'),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('connectionDbUser'),
                controller: _dbUser,
                decoration: const InputDecoration(labelText: 'Database user'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                isExpanded: true,
                key: const Key('connectionCredentialKind'),
                initialValue: _credentialKind,
                decoration: const InputDecoration(labelText: 'Credential source'),
                items: const [
                  DropdownMenuItem(value: 'ENV', child: Text('Function secret (ENV)')),
                  DropdownMenuItem(value: 'VAULT', child: Text('Supabase Vault')),
                ],
                onChanged: (v) => setState(() => _credentialKind = v ?? 'ENV'),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('connectionCredentialRef'),
                controller: _credentialRef,
                decoration: const InputDecoration(
                  labelText: 'Secret name (password only, never typed here)',
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                key: const Key('connectionActiveSwitch'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Active'),
                value: _isActive,
                onChanged: (v) => setState(() => _isActive = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('connectionSaveButton'),
          onPressed: _canSave ? _save : null,
          child: const Text('Save'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final connection = KpiConnection(
      id: widget.existing?.id,
      companyId: widget.companyId,
      name: _name.text.trim(),
      kind: _kind,
      host: _host.text.trim(),
      port: int.parse(_port.text.trim()),
      database: _database.text.trim(),
      dbSchema: _dbSchema.text.trim(),
      dbUser: _dbUser.text.trim(),
      credentialKind: _credentialKind,
      credentialRef: _credentialRef.text.trim(),
      isActive: _isActive,
    );
    await widget.onSave(connection);
    if (mounted) setState(() => _saving = false);
  }
}

// ===========================================================================
// Binding form
// ===========================================================================

class _BindingFormDialog extends StatefulWidget {
  final Kpi kpi;
  final KpiSourceBinding? existing;
  final List<KpiConnection> connections;
  final String companyId;
  final Future<void> Function(KpiSourceBinding) onSave;

  const _BindingFormDialog({
    required this.kpi,
    required this.existing,
    required this.connections,
    required this.companyId,
    required this.onSave,
  });

  @override
  State<_BindingFormDialog> createState() => _BindingFormDialogState();
}

class _BindingFormDialogState extends State<_BindingFormDialog> {
  String? _connectionId;
  late final TextEditingController _objectName;
  late final TextEditingController _periodColumn;
  late final TextEditingController _subjectColumn;
  late final TextEditingController _numeratorColumn;
  late final TextEditingController _denominatorColumn;
  SubjectKind _subjectKind = SubjectKind.employee;
  bool _isActive = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _connectionId = e?.connectionId ??
        (widget.connections.isNotEmpty ? widget.connections.first.id : null);
    _objectName = TextEditingController(text: e?.objectName ?? '');
    _periodColumn = TextEditingController(text: e?.periodColumn ?? '');
    _subjectColumn = TextEditingController(text: e?.subjectColumn ?? '');
    _numeratorColumn = TextEditingController(text: e?.numeratorColumn ?? '');
    _denominatorColumn = TextEditingController(text: e?.denominatorColumn ?? '');
    _subjectKind = e?.subjectKind ?? SubjectKind.employee;
    _isActive = e?.isActive ?? true;
    for (final c in [
      _objectName,
      _periodColumn,
      _subjectColumn,
      _numeratorColumn,
      _denominatorColumn,
    ]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _objectName.dispose();
    _periodColumn.dispose();
    _subjectColumn.dispose();
    _numeratorColumn.dispose();
    _denominatorColumn.dispose();
    super.dispose();
  }

  /// Refuses inline, at the point of typing -- the DB-side CHECK
  /// (`kpi_source_bindings_*_valid`, `20260815000002_kpi_source_config.sql`)
  /// and the edge function's `quoteIdentifier`
  /// (`supabase/functions/_shared/source_query.ts`) are the two things that
  /// actually enforce this shape; this is the courtesy that catches a
  /// mistake here instead of at month-end compute time. An EMPTY field is
  /// deliberately not an error here -- see [_canSave], which requires
  /// non-empty for the four REQUIRED columns but treats an empty
  /// denominator as legal (a COUNT KPI has none), so this function must not
  /// flag "empty" as "invalid" for either case.
  String? _identifierError(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return null;
    return isValidSqlIdentifier(v) ? null : kInvalidSourceIdentifierMessage;
  }

  bool get _canSave =>
      !_saving &&
      _connectionId != null &&
      _objectName.text.trim().isNotEmpty &&
      _identifierError(_objectName.text) == null &&
      _periodColumn.text.trim().isNotEmpty &&
      _identifierError(_periodColumn.text) == null &&
      _subjectColumn.text.trim().isNotEmpty &&
      _identifierError(_subjectColumn.text) == null &&
      _numeratorColumn.text.trim().isNotEmpty &&
      _identifierError(_numeratorColumn.text) == null &&
      // Denominator is the one optional column -- an empty value here is
      // valid (saves as null, see _save below); only a NON-empty invalid
      // value blocks saving.
      _identifierError(_denominatorColumn.text) == null;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.existing == null
            ? 'Bind ${widget.kpi.name}'
            : 'Edit binding — ${widget.kpi.name}',
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                isExpanded: true,
                key: const Key('bindingConnection'),
                initialValue: _connectionId,
                decoration: const InputDecoration(labelText: 'Connection'),
                items: [
                  for (final c in widget.connections)
                    DropdownMenuItem(value: c.id, child: Text(c.name)),
                ],
                onChanged: (v) => setState(() => _connectionId = v),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('bindingObjectName'),
                controller: _objectName,
                decoration: InputDecoration(
                  labelText: 'Table / view name',
                  errorText: _identifierError(_objectName.text),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('bindingPeriodColumn'),
                controller: _periodColumn,
                decoration: InputDecoration(
                  labelText: 'Period column',
                  errorText: _identifierError(_periodColumn.text),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('bindingSubjectColumn'),
                controller: _subjectColumn,
                decoration: InputDecoration(
                  labelText: 'Subject column',
                  errorText: _identifierError(_subjectColumn.text),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('bindingNumeratorColumn'),
                controller: _numeratorColumn,
                decoration: InputDecoration(
                  labelText: 'Numerator column',
                  errorText: _identifierError(_numeratorColumn.text),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('bindingDenominatorColumn'),
                controller: _denominatorColumn,
                decoration: InputDecoration(
                  labelText: 'Denominator column (optional -- blank for a COUNT '
                      'KPI)',
                  errorText: _identifierError(_denominatorColumn.text),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<SubjectKind>(
                isExpanded: true,
                key: const Key('bindingSubjectKind'),
                initialValue: _subjectKind,
                decoration: const InputDecoration(labelText: 'Subject kind'),
                items: const [
                  DropdownMenuItem(
                    value: SubjectKind.employee,
                    child: Text('Employee'),
                  ),
                  DropdownMenuItem(
                    value: SubjectKind.department,
                    child: Text('Department'),
                  ),
                  DropdownMenuItem(
                    value: SubjectKind.none,
                    child: Text('None (single company figure)'),
                  ),
                ],
                onChanged: (v) =>
                    setState(() => _subjectKind = v ?? SubjectKind.employee),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                key: const Key('bindingActiveSwitch'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Active'),
                value: _isActive,
                onChanged: (v) => setState(() => _isActive = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('bindingSaveButton'),
          onPressed: _canSave ? _save : null,
          child: const Text('Save'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final denom = _denominatorColumn.text.trim();
    final binding = KpiSourceBinding(
      id: widget.existing?.id,
      companyId: widget.companyId,
      kpiId: widget.kpi.id,
      connectionId: _connectionId!,
      objectName: _objectName.text.trim(),
      periodColumn: _periodColumn.text.trim(),
      subjectColumn: _subjectColumn.text.trim(),
      numeratorColumn: _numeratorColumn.text.trim(),
      // A COUNT KPI has no denominator column -- must round-trip as null,
      // never '', which is exactly what a blank text field would otherwise
      // become. See KpiSourceBinding's own doc comment.
      denominatorColumn: denom.isEmpty ? null : denom,
      subjectKind: _subjectKind,
      isActive: _isActive,
    );
    await widget.onSave(binding);
    if (mounted) setState(() => _saving = false);
  }
}

// ===========================================================================
// Subject map form
// ===========================================================================

enum _MapTargetKind { employee, department }

class _SubjectMapFormDialog extends StatefulWidget {
  final String connectionId;
  final String companyId;
  final List<Employee> employees;
  final List<Department> departments;
  final Future<void> Function(KpiSubjectMap) onSave;

  /// Pre-fills and locks the external key -- set when this dialog is
  /// opened FROM the unmapped-keys list (Task 9): the key is already known
  /// (it is exactly what the source returned), so re-typing it would only
  /// risk a mismatch between what was flagged and what gets mapped.
  final String? fixedExternalKey;

  /// Locks the target kind and hides [_MapTargetKind]'s picker entirely --
  /// set the same way, from the unmapped-keys list, whose binding's
  /// `subject_kind` already says which one is possible: EMPLOYEE maps to
  /// an employee, DEPARTMENT to a department, never a choice between both.
  /// `null` (the standalone "Add mapping" button) keeps the original
  /// either-or picker.
  final _MapTargetKind? fixedKind;

  const _SubjectMapFormDialog({
    required this.connectionId,
    required this.companyId,
    required this.employees,
    required this.departments,
    required this.onSave,
    this.fixedExternalKey,
    this.fixedKind,
  });

  @override
  State<_SubjectMapFormDialog> createState() => _SubjectMapFormDialogState();
}

class _SubjectMapFormDialogState extends State<_SubjectMapFormDialog> {
  late final _externalKey = TextEditingController(text: widget.fixedExternalKey ?? '');
  late _MapTargetKind _kind = widget.fixedKind ?? _MapTargetKind.employee;
  String? _targetId;
  bool _saving = false;

  @override
  void dispose() {
    _externalKey.dispose();
    super.dispose();
  }

  bool get _canSave =>
      !_saving && _externalKey.text.trim().isNotEmpty && _targetId != null;

  @override
  Widget build(BuildContext context) {
    final targets = _kind == _MapTargetKind.employee
        ? [for (final e in widget.employees) (id: e.id, label: e.fullName)]
        : [for (final d in widget.departments) (id: d.id, label: d.name)];

    return AlertDialog(
      title: const Text('Add subject mapping'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key('subjectMapExternalKey'),
              controller: _externalKey,
              readOnly: widget.fixedExternalKey != null,
              decoration: const InputDecoration(
                labelText: 'External key (the source\'s own id)',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            if (widget.fixedKind == null)
              SegmentedButton<_MapTargetKind>(
                key: const Key('subjectMapKind'),
                segments: const [
                  ButtonSegment(value: _MapTargetKind.employee, label: Text('Employee')),
                  ButtonSegment(
                    value: _MapTargetKind.department,
                    label: Text('Department'),
                  ),
                ],
                selected: {_kind},
                onSelectionChanged: (s) => setState(() {
                  _kind = s.first;
                  _targetId = null;
                }),
              ),
            if (widget.fixedKind == null) const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              isExpanded: true,
              key: const Key('subjectMapTarget'),
              initialValue: _targetId,
              decoration: const InputDecoration(labelText: 'Maps to'),
              items: [
                for (final t in targets)
                  DropdownMenuItem(value: t.id, child: Text(t.label)),
              ],
              onChanged: (v) => setState(() => _targetId = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('subjectMapSaveButton'),
          onPressed: _canSave ? _save : null,
          child: const Text('Save'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final mapping = KpiSubjectMap(
      companyId: widget.companyId,
      connectionId: widget.connectionId,
      externalKey: _externalKey.text.trim(),
      employeeId: _kind == _MapTargetKind.employee ? _targetId : null,
      departmentId: _kind == _MapTargetKind.department ? _targetId : null,
    );
    await widget.onSave(mapping);
    if (mounted) setState(() => _saving = false);
  }
}

// ===========================================================================
// Unmapped keys (Task 9) -- an on-demand, point-in-time probe
// ===========================================================================

/// "Keys this connection returned that map to nobody," for one binding, one
/// period at a time -- the spec's "Done when" requirement that an unmapped
/// subject be visible somewhere an admin can fix it. Without this, the
/// failure mode is a company figure that is right sitting beside a
/// department figure that is quietly short, and nothing on screen says so.
///
/// **On-demand, not stored.** There is no table for this -- the one
/// migration this plan ships (`20260815000002_kpi_source_config.sql`) has
/// no room for one, and adding a second was ruled out. So this dialog does
/// a LIVE read every time it opens (and every time the period changes):
/// [ConfiguredSource.readDetailed], the exact function `computeResults`
/// itself would use for this binding. Reusing it, rather than re-deriving
/// "unmapped" here, is deliberate -- see that class's own doc comment for
/// why a second definition would be worse than no screen at all: it could
/// say "all mapped" while the real recompute still undercounts.
///
/// **Point-in-time, said plainly.** The header text below names the exact
/// period checked -- an admin who maps everything today and assumes it
/// stays clean is the same silent-undercount failure, one level up. Mapping
/// a key here fixes future recomputes of THIS period and any other period
/// sharing the same external key; it does not retroactively repair a
/// period already computed, and a new period can surface a brand new
/// unmapped key of its own.
///
/// **Blank keys are a different problem.** Task 5's `toFetchRow` maps a SQL
/// NULL `subject_key` to `''`, and `kpi_subject_map_external_key_not_blank`
/// (`20260815000002_kpi_source_config.sql:174`) forbids a blank
/// `external_key` -- so a blank key can never be mapped, only fixed
/// upstream in the source. It is counted and named separately below, with
/// no "Map" control, rather than offered a button that could only fail at
/// the database.
class _UnmappedKeysDialog extends ConsumerStatefulWidget {
  final Kpi kpi;
  final KpiSourceBinding binding;
  final String companyId;

  const _UnmappedKeysDialog({
    required this.kpi,
    required this.binding,
    required this.companyId,
  });

  @override
  ConsumerState<_UnmappedKeysDialog> createState() => _UnmappedKeysDialogState();
}

class _UnmappedKeysDialogState extends ConsumerState<_UnmappedKeysDialog> {
  late String _period = periodOf(DateTime.now());
  bool _loading = true;
  Object? _error;
  ConfiguredSourceResult? _result;
  List<Employee> _employees = const [];
  List<Department> _departments = const [];

  DateTime get _periodStart => startOfPeriod(_period);
  String get _monthLabel => DateFormat('MMMM yyyy').format(_periodStart);

  @override
  void initState() {
    super.initState();
    _check();
  }

  void _shiftMonth(int delta) {
    final d = DateTime(_periodStart.year, _periodStart.month + delta, 1);
    setState(() => _period = periodOf(d));
    _check();
  }

  /// The live probe. Every failure -- including the two config tables not
  /// existing yet -- is caught here and rendered as [PendingMigrationNotice]
  /// or a plain error, the same as every other section of this screen;
  /// [ConfiguredSource.readDetailed] itself only swallows the FETCH half of
  /// a read (a network blip, a non-2xx), not a `subjectMapFor` call that
  /// throws PGRST205 against an unapplied migration, so this catch has to
  /// cover that too.
  Future<void> _check() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(kpiSourceConfigRepositoryProvider);
      final employees = await ref.read(
        employeeListProvider(const EmployeeListQuery()).future,
      );
      final departments = await ref.read(departmentListProvider.future);
      final roles = await ref.read(roleScorecardListProvider.future);
      final source = ConfiguredSource(
        binding: widget.binding,
        subjectMapReader: repo.subjectMapFor,
        fetcher: repo.fetchSourceRows,
        employees: employees,
        roles: roles,
      );
      // Company scope: unresolvedSubjectKeys is computed over EVERY row for
      // the period regardless of scope (see ConfiguredSourceResult's own
      // doc comment), so which scope is requested here has no bearing on
      // which keys come back -- company is picked only because it needs no
      // employeeIds population to ask for.
      final result = await source.readDetailed(
        scope: KpiScope.company,
        period: _period,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _employees = employees;
        _departments = departments;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _mapKey(String key) async {
    final messenger = ScaffoldMessenger.of(context);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _SubjectMapFormDialog(
        connectionId: widget.binding.connectionId,
        companyId: widget.companyId,
        employees: _employees,
        departments: _departments,
        fixedExternalKey: key,
        fixedKind: widget.binding.subjectKind == SubjectKind.employee
            ? _MapTargetKind.employee
            : _MapTargetKind.department,
        onSave: (mapping) async {
          try {
            await ref
                .read(kpiSourceConfigRepositoryProvider)
                .upsertSubjectMapping(mapping);
            ref.invalidate(kpiSubjectMapProvider(widget.binding.connectionId));
            if (dialogContext.mounted) Navigator.pop(dialogContext);
          } catch (e) {
            messenger.showSnackBar(
              SnackBar(content: Text('Could not save the mapping: $e')),
            );
          }
        },
      ),
    );
    // Disappearance must be a consequence of the write just made, not a
    // second, differently-stubbed read -- re-running the SAME probe is what
    // proves that: the fetch answers identically, only the subject map
    // (just written) can change what comes back unresolved.
    await _check();
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_error != null) {
      body = PendingMigrationNotice(error: _error!, feature: 'KPI subject mapping');
    } else if (_loading) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    } else {
      final unresolved = _result?.unresolvedSubjectKeys ?? const <String>[];
      final blankCount = unresolved.where((k) => k.isEmpty).length;
      final realKeys = unresolved.where((k) => k.isNotEmpty).toList();
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'For $_monthLabel only. This is a live check for this one period '
            '-- mapping a key here does not retroactively fix past periods, '
            'and a new period can surface a key of its own.',
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          if (blankCount > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '$blankCount row(s) returned a blank subject key -- the '
                'source\'s own ${widget.binding.subjectColumn} column is '
                'empty for those rows. Fix this in the source system; '
                'there is nothing to map here.',
                style: const TextStyle(color: Colors.orange),
              ),
            ),
          if (realKeys.isEmpty && blankCount == 0)
            const Text('No unmapped keys for this period.', style: TextStyle(color: Colors.grey)),
          for (final key in realKeys)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(key, style: AppTheme.mono(context, fontSize: 12)),
                  ),
                  TextButton(
                    key: Key('mapUnresolved-$key'),
                    onPressed: () => _mapKey(key),
                    child: const Text('Map'),
                  ),
                ],
              ),
            ),
        ],
      );
    }

    return AlertDialog(
      title: Text('Unmapped keys -- ${widget.kpi.name}'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  key: const Key('unmappedKeysPrevMonth'),
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => _shiftMonth(-1),
                ),
                Text(_monthLabel, style: Theme.of(context).textTheme.titleSmall),
                IconButton(
                  key: const Key('unmappedKeysNextMonth'),
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => _shiftMonth(1),
                ),
              ],
            ),
            const SizedBox(height: 8),
            body,
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
