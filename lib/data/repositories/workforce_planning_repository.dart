import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/workforce_planning.dart';
import '../pagination.dart';

/// The PRIMARY assignment insert payload for a task's current owner/card, or
/// null when the task is unassigned. Owner wins over card — matching the step-4
/// backfill. Pure so the branching is unit-tested; the DB glue lives in
/// [WorkforcePlanningRepository._syncPrimaryFromTask].
Map<String, dynamic>? primaryAssignmentPayload({
  required String companyId,
  required String taskId,
  String? ownerEmployeeId,
  String? roleScorecardId,
}) {
  if (ownerEmployeeId != null) {
    return {
      'company_id': companyId, 'task_id': taskId, 'employee_id': ownerEmployeeId,
      'assignment_role': 'PRIMARY', 'allocation_pct': 100,
    };
  }
  if (roleScorecardId != null) {
    return {
      'company_id': companyId, 'task_id': taskId, 'role_scorecard_id': roleScorecardId,
      'assignment_role': 'PRIMARY', 'allocation_pct': 100,
    };
  }
  return null;
}

class WorkforcePlanningRepository {
  final SupabaseClient _client;
  WorkforcePlanningRepository(this._client);

  Future<List<WpNode>> nodes() async {
    final rows = await _client.from('wp_value_chain_nodes').select().order('sort_order').order('code');
    return rows.cast<Map<String, dynamic>>().map(WpNode.fromRow).toList();
  }

  Future<List<WpDriver>> drivers() async {
    final rows = await _client.from('wp_drivers').select().order('sort_order').order('name');
    return rows.cast<Map<String, dynamic>>().map(WpDriver.fromRow).toList();
  }

  Future<List<WpRate>> rates() async {
    final rows = await _client.from('wp_rates').select().order('name');
    return rows.cast<Map<String, dynamic>>().map(WpRate.fromRow).toList();
  }

  Future<WpConfig?> config() async {
    final row = await _client.from('wp_config').select().maybeSingle();
    return row == null ? null : WpConfig.fromRow(row);
  }

  /// Paged: PostgREST caps a response at `max_rows` (1000). `wp_tasks` is
  /// already at 282 and grows with every responsibility added, so an
  /// unpaged select would eventually return a silent truncated slice — and a
  /// missing task reads as "this work does not exist" rather than as an error.
  Future<List<WpTask>> tasks() => fetchAllPages((from, to) async {
        final rows =
            await _client.from('wp_tasks').select().order('name').range(from, to);
        return rows.cast<Map<String, dynamic>>().map(WpTask.fromRow).toList();
      });

  /// Paged for the same reason as [tasks] — grows with every assignment.
  Future<List<WpTaskAssignment>> taskAssignments() => fetchAllPages((from, to) async {
        final rows = await _client
            .from('wp_task_assignments')
            .select()
            .order('task_id')
            .range(from, to);
        return rows.cast<Map<String, dynamic>>().map(WpTaskAssignment.fromRow).toList();
      });

  /// Inserts a new assignment or updates an existing one's role/percentage.
  /// A TARGET change is a delete + insert, not an update — the partial unique
  /// indexes are on (task_id, target), so mutating the target in place could
  /// collide with a sibling row.
  Future<void> upsertAssignment(WpTaskAssignment a) async {
    if (a.id.isEmpty) {
      await _client.from('wp_task_assignments').insert(a.toUpsert(a.companyId));
    } else {
      await _client.from('wp_task_assignments').update({
        'assignment_role': a.assignmentRole,
        'allocation_pct': a.allocationPct,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', a.id);
    }
  }

  Future<void> deleteAssignment(String id) async =>
      _client.from('wp_task_assignments').delete().eq('id', id);

  /// Bulk percentage write (the panel's simplifiers). One statement per row —
  /// PostgREST has no multi-row-different-values update.
  Future<void> setAllocations(Map<String, double> pctById) async {
    for (final e in pctById.entries) {
      await _client.from('wp_task_assignments').update({
        'allocation_pct': e.value,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', e.key);
    }
  }

  Future<List<WpPersonLoad>> personLoads() => fetchAllPages((from, to) async {
        final rows = await _client
            .from('wp_person_load')
            .select()
            .order('employee_id')
            .range(from, to);
        return rows.cast<Map<String, dynamic>>().map(WpPersonLoad.fromRow).toList();
      });

  Future<List<WpTaskComputed>> taskComputedForOwner(String employeeId) async {
    final rows = await _client
        .from('wp_task_computed').select().eq('owner_employee_id', employeeId);
    return rows.cast<Map<String, dynamic>>().map(WpTaskComputed.fromRow).toList();
  }

  /// Every computed task row. Needed because a person's task list now includes
  /// DERIVED tasks (unowned rows on their role card), which
  /// `taskComputedForOwner` cannot return — it filters on `owner_employee_id`
  /// server-side.
  /// Paged for the same reason as [tasks] — this view has one row per task, so
  /// it crosses `max_rows` at exactly the same point, and a truncated slice
  /// here silently under-reports everyone's hours.
  Future<List<WpTaskComputed>> allTaskComputed() => fetchAllPages((from, to) async {
        final rows = await _client
            .from('wp_task_computed')
            .select()
            .order('task_id')
            .range(from, to);
        return rows.cast<Map<String, dynamic>>().map(WpTaskComputed.fromRow).toList();
      });

  Future<void> saveTask(WpTask task) async {
    final payload = task.toUpsert(task.companyId);
    String id;
    if (task.id.isEmpty) {
      final row = await _client.from('wp_tasks').insert(payload).select('id').single();
      id = row['id'] as String;
    } else {
      await _client.from('wp_tasks').update(payload).eq('id', task.id);
      id = task.id;
    }
    await _syncPrimaryFromTask(id);
  }

  /// Keeps a task's PRIMARY assignment in lockstep with its owner/card while the
  /// current forms still write owner_employee_id / role_scorecard_id directly.
  /// wp_person_load reads assignments now, so without this a reassignment would
  /// leave a stale PRIMARY and the load view would disagree with the rest of the
  /// UI. Step 5 moves writes onto assignments directly and retires this sync.
  Future<void> _syncPrimaryFromTask(String taskId) async {
    final t = await _client.from('wp_tasks')
        .select('company_id, owner_employee_id, role_scorecard_id')
        .eq('id', taskId).maybeSingle();
    if (t == null) return;
    final payload = primaryAssignmentPayload(
      companyId: t['company_id'] as String,
      taskId: taskId,
      ownerEmployeeId: t['owner_employee_id'] as String?,
      roleScorecardId: t['role_scorecard_id'] as String?,
    );
    // Keep a manually-set percentage when the PRIMARY still points at the same
    // target — otherwise editing an unrelated field would silently reset a
    // deliberate 60/40 split back to 100.
    final existing = await _client.from('wp_task_assignments')
        .select('employee_id, role_scorecard_id, allocation_pct')
        .eq('task_id', taskId).eq('assignment_role', 'PRIMARY').maybeSingle();
    if (existing != null && payload != null &&
        existing['employee_id'] == payload['employee_id'] &&
        existing['role_scorecard_id'] == payload['role_scorecard_id']) {
      return; // same target — leave the row (and its pct) untouched
    }
    await _client.from('wp_task_assignments').delete()
        .eq('task_id', taskId).eq('assignment_role', 'PRIMARY');
    if (payload != null) {
      await _client.from('wp_task_assignments').insert(payload);
    }
  }

  Future<void> deleteTask(String id) async =>
      _client.from('wp_tasks').delete().eq('id', id);

  /// Writes only the costing columns for a batch of tasks (the Tasks tab's bulk
  /// grid). Deliberately NOT a full `toUpsert` — that would round-trip every
  /// other column and let a stale in-memory row clobber a concurrent edit to,
  /// say, the owner or the responsibility area.
  ///
  /// Applied one row at a time and reported per row: PostgREST has no
  /// multi-row-different-values update, and a partial failure must leave the
  /// successful rows saved rather than silently rolling the batch back.
  /// Returns the ids that failed, so the caller can keep them dirty.
  Future<List<String>> updateTaskCosts(Map<String, Map<String, dynamic>> byId) async {
    final failed = <String>[];
    for (final entry in byId.entries) {
      try {
        await _client.from('wp_tasks').update(entry.value).eq('id', entry.key);
      } catch (_) {
        failed.add(entry.key);
      }
    }
    return failed;
  }

  /// Marks a responsibility as a behavioural expectation (or back to costable).
  ///
  /// Clears the costing columns in the SAME statement when setting the flag:
  /// the DB constraint forbids an expectation that carries hours, and doing it
  /// in two writes would leave a window where the row violates the rule.
  Future<void> setTaskExpectation(String taskId, bool isExpectation) async {
    await _client.from('wp_tasks').update({
      'is_expectation': isExpectation,
      // Keep the invariant: an expectation is non-essential; a task made
      // costable again returns to the essential default. Setting is_essential in
      // the SAME statement avoids a window where the row violates the CHECK.
      'is_essential': !isExpectation,
      if (isExpectation) ...{
        'times_manual': null,
        'driver_id': null,
        'minutes_manual': null,
        'rate_id': null,
        'hours_per_month': null,
      },
    }).eq('id', taskId);
  }

  /// Archives (or restores) an accountability. ARCHIVED work leaves load and
  /// the derived lists (wp_task_computed filters on status) but is retained and
  /// can be restored — the correct tool for "no longer needed", vs a hard
  /// delete of a row that carries history.
  Future<void> setTaskArchived(String taskId, bool archived) async {
    await _client.from('wp_tasks')
        .update({'status': archived ? 'ARCHIVED' : 'ACTIVE'})
        .eq('id', taskId);
  }

  Future<void> reassignTaskOwner(String taskId, String? ownerEmployeeId) async {
    await _client.from('wp_tasks').update({'owner_employee_id': ownerEmployeeId}).eq('id', taskId);
    await _syncPrimaryFromTask(taskId);
  }

  /// Sets (or clears) an accountability's home card. Assigning an orphan to a
  /// staffed card gives it a derived owner via that card's holders, which is
  /// how work leaves the unassigned set pre-`wp_task_assignments`. At step 4
  /// this becomes a PRIMARY assignment insert with no caller change.
  Future<void> setTaskCard(String taskId, String? roleScorecardId) async {
    await _client.from('wp_tasks')
        .update({'role_scorecard_id': roleScorecardId})
        .eq('id', taskId);
    await _syncPrimaryFromTask(taskId);
  }

  Future<void> saveDriver(WpDriver driver) async {
    final payload = driver.toUpsert(driver.companyId);
    if (driver.id.isEmpty) {
      await _client.from('wp_drivers').insert(payload);
    } else {
      await _client.from('wp_drivers').update(payload).eq('id', driver.id);
    }
  }

  Future<void> saveRate(WpRate rate) async {
    final payload = rate.toUpsert(rate.companyId);
    if (rate.id.isEmpty) {
      await _client.from('wp_rates').insert(payload);
    } else {
      await _client.from('wp_rates').update(payload).eq('id', rate.id);
    }
  }

  Future<void> setGrowthMultiplier(String companyId, double m) async =>
      _client.from('wp_config').upsert({
        'company_id': companyId, 'growth_multiplier': m, 'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'company_id');

  Future<void> setCapacityOverride(String employeeId, double? hours) async {
    if (hours == null) {
      await _client.from('wp_capacity_overrides').delete().eq('employee_id', employeeId);
    } else {
      await _client.from('wp_capacity_overrides').upsert({
        'employee_id': employeeId, 'capacity_hours': hours,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'employee_id');
    }
  }
}

final workforcePlanningRepositoryProvider = Provider<WorkforcePlanningRepository>(
    (ref) => WorkforcePlanningRepository(Supabase.instance.client));
