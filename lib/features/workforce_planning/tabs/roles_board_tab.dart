import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/employee.dart';
import '../../../data/models/role_scorecard.dart';
import '../../../data/models/workforce_planning.dart';
import '../../../data/repositories/role_scorecard_repository.dart';
import '../../../data/repositories/workforce_planning_repository.dart';
import '../board/board_sections.dart';
import '../board/role_load_card.dart';
import '../role/new_role_dialog.dart';
import '../role_load.dart';
import '../wp_providers.dart';
import 'needs_attention_strip.dart';
import 'task_form_dialog.dart';

/// The Workforce Planning front door: every role with its people and its
/// work. Drag a task onto another role to plan a move; nothing is written
/// until Apply.
class RolesBoardTab extends ConsumerStatefulWidget {
  const RolesBoardTab({super.key});

  @override
  ConsumerState<RolesBoardTab> createState() => _RolesBoardTabState();
}

class _RolesBoardTabState extends ConsumerState<RolesBoardTab> {
  final RoleMoves _moves = {};
  ({String taskId, String roleId})? _hover;
  bool _applying = false;

  void _invalidate() {
    ref.invalidate(wpTasksProvider);
    ref.invalidate(wpAllTaskComputedProvider);
    ref.invalidate(wpPersonLoadsProvider);
    ref.invalidate(roleScorecardListProvider);
  }

  /// Records a move, or removes it when the task lands back on its own role.
  void _drop(WpTask task, String roleId) => setState(() {
    _hover = null;
    if (task.roleScorecardId == roleId) {
      _moves.remove(task.id);
    } else {
      _moves[task.id] = roleId;
    }
  });

  Future<void> _apply() async {
    setState(() => _applying = true);
    try {
      final failed = await ref.read(workforcePlanningRepositoryProvider).moveTasksToRoles({..._moves});
      if (!mounted) return;
      setState(() {
        _moves.removeWhere((id, _) => !failed.contains(id));
      });
      _invalidate();
      if (failed.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${failed.length} move(s) could not be saved and are still drafts.')),
        );
      }
    } catch (e) {
      // All drafts are kept as-is — nothing was confirmed saved.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not apply moves: $e')),
      );
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  Future<void> _openTask({WpTask? existing, String? roleId, required _BoardData d}) async {
    final saved = await showDialog<WpTask>(
      context: context,
      builder: (_) => TaskFormDialog(
        existing: existing,
        companyId: d.companyId,
        cards: d.roles,
        nodes: d.nodes,
        drivers: d.drivers,
        rates: d.rates,
        initialRoleId: roleId,
        duplicateCheckPool: d.tasks,
        holderCountByRole: {for (final r in d.current) r.role.id: r.holders.length},
      ),
    );
    if (saved == null) return;
    await ref.read(workforcePlanningRepositoryProvider).saveTask(saved);
    _invalidate();
  }

  Future<void> _addHolder(RoleScorecard role, List<Employee> employees) async {
    final picked = await showDialog<Employee>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Who should hold ${role.jobTitle}?'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              'Changing someone\'s role can change their pay, so it is done from '
              'their profile with Compensation & role change.',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
          ),
          for (final e in employees.where((e) => e.roleScorecardId != role.id))
            SimpleDialogOption(onPressed: () => Navigator.pop(ctx, e), child: Text(e.fullName)),
        ],
      ),
    );
    if (picked != null && mounted) context.push('/employees/${picked.id}');
  }

  @override
  Widget build(BuildContext context) {
    final async = _BoardData.watch(ref);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (d) => _board(context, d),
    );
  }

  Widget _board(BuildContext context, _BoardData d) {
    // Order and task rows follow the committed drafts only; the hover changes
    // numbers, never layout, so nothing moves under the pointer mid-drag.
    final withDrafts = d.loads(_moves);
    final preview = {..._moves, if (_hover != null) _hover!.taskId: _hover!.roleId};
    final plannedById = {for (final r in d.loads(preview)) r.role.id: r};
    final currentById = {for (final r in d.current) r.role.id: r};
    final rolesById = {for (final r in d.roles) r.id: r};
    final tasksById = {for (final t in d.tasks) t.id: t};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const NeedsAttentionStrip(),
        if (_moves.isNotEmpty) _planBar(context),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Creating a role lives on the board (it replaced the old Roles
              // tab). No extra permission check: the hub is already
              // HR/Admin-only via the /workforce-planning route guard.
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: () async {
                    final id = await showNewRoleDialog(context, ref);
                    if (id != null && context.mounted) {
                      context.push('/workforce-planning/roles/$id');
                    }
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('New role'),
                ),
              ),
              const SizedBox(height: 12),
              PeopleLoadStrip(loads: plannedById.values.toList(), employees: d.employees),
              const SizedBox(height: 16),
              NoRoleSection(
                tasks: noRoleTasks(d.tasks, moves: _moves),
                hoursById: d.hoursById,
                onOpenTask: (t) => _openTask(existing: t, d: d),
              ),
              FlaggedSection(
                tasks: flaggedTasks(d.tasks),
                rolesById: rolesById,
                onLooksRight: (t) async {
                  await ref.read(workforcePlanningRepositoryProvider).clearReviewNote(t.id);
                  _invalidate();
                },
                onOpenTask: (t) => _openTask(existing: t, d: d),
              ),
              for (final p in withDrafts)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: RoleLoadCard(
                    current: currentById[p.role.id]!,
                    planned: plannedById[p.role.id]!,
                    tasks: p.tasks,
                    checkedBy: checkedByTitles(role: p.role, employees: d.employees, rolesById: rolesById),
                    highlighted: _hover?.roleId == p.role.id,
                    taskHoursById: d.hoursById,
                    onHoverTask: (taskId) => setState(() {
                      _hover = taskId == null ? null : (taskId: taskId, roleId: p.role.id);
                    }),
                    onDropTask: (taskId) {
                      final t = tasksById[taskId];
                      if (t != null) _drop(t, p.role.id);
                    },
                    onAddTask: () => _openTask(roleId: p.role.id, d: d),
                    onAddHolder: () => _addHolder(p.role, d.employees),
                    onOpenRole: () => context.push('/workforce-planning/roles/${p.role.id}'),
                    onOpenTask: (t) => _openTask(existing: t, d: d),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _planBar(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(children: [
        Expanded(child: Text('${_moves.length} unsaved ${_moves.length == 1 ? 'move' : 'moves'}')),
        TextButton(
          onPressed: _applying ? null : () => setState(() { _moves.clear(); _hover = null; }),
          child: const Text('Reset'),
        ),
        const SizedBox(width: 8),
        FilledButton(onPressed: _applying ? null : _apply, child: Text('Apply ${_moves.length}')),
      ]),
    ),
  );
}

/// Everything the board reads, loaded together.
class _BoardData {
  final String companyId;
  final List<RoleScorecard> roles;
  final List<Employee> employees;
  final List<WpTask> tasks;
  final List<WpNode> nodes;
  final List<WpDriver> drivers;
  final List<WpRate> rates;
  final Map<String, double> hoursById;
  final Map<String, double> capacityById;
  final double defaultCapacity;
  late final List<RoleLoad> current = loads(const {});

  _BoardData({
    required this.companyId, required this.roles, required this.employees,
    required this.tasks, required this.nodes, required this.drivers, required this.rates,
    required this.hoursById, required this.capacityById, required this.defaultCapacity,
  });

  List<RoleLoad> loads(RoleMoves moves) => buildRoleLoads(
    roles: roles, employees: employees, tasks: tasks, hoursByTaskId: hoursById,
    capacityByEmployee: capacityById, defaultCapacity: defaultCapacity, moves: moves,
  );

  static AsyncValue<_BoardData> watch(WidgetRef ref) {
    final roles = ref.watch(roleScorecardListProvider);
    final emps = ref.watch(wpActiveEmployeesProvider);
    final tasks = ref.watch(wpTasksProvider);
    final computed = ref.watch(wpAllTaskComputedProvider);
    final loads = ref.watch(wpPersonLoadsProvider);
    final config = ref.watch(wpConfigProvider);
    final nodes = ref.watch(wpNodesProvider);
    final drivers = ref.watch(wpDriversProvider);
    final rates = ref.watch(wpRatesProvider);
    final multiplier = ref.watch(wpGrowthMultiplierProvider);
    for (final a in [roles, emps, tasks, computed, loads, config]) {
      if (a.hasError) return AsyncValue.error(a.error!, a.stackTrace ?? StackTrace.empty);
      if (!a.hasValue) return const AsyncValue.loading();
    }
    final active = roles.requireValue.where((r) => r.isActive).toList();
    final e = emps.requireValue;
    return AsyncValue.data(_BoardData(
      companyId: e.isNotEmpty ? e.first.companyId : (active.isNotEmpty ? active.first.companyId : ''),
      roles: active,
      employees: e,
      tasks: tasks.requireValue,
      nodes: nodes.asData?.value ?? const [],
      drivers: drivers.asData?.value ?? const [],
      rates: rates.asData?.value ?? const [],
      hoursById: {for (final c in computed.requireValue) c.taskId: taskHours(c, multiplier)},
      capacityById: {for (final l in loads.requireValue) l.employeeId: l.capacityHours},
      defaultCapacity: config.requireValue?.defaultCapacityHours ?? 160,
    ));
  }
}
