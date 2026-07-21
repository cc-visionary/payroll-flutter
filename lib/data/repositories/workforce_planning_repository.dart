import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/workforce_planning.dart';
import '../pagination.dart';

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
    if (task.id.isEmpty) {
      await _client.from('wp_tasks').insert(payload);
    } else {
      await _client.from('wp_tasks').update(payload).eq('id', task.id);
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

  Future<void> reassignTaskOwner(String taskId, String? ownerEmployeeId) async =>
      _client.from('wp_tasks').update({'owner_employee_id': ownerEmployeeId}).eq('id', taskId);

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
