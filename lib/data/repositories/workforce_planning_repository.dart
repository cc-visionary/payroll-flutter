import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/workforce_planning.dart';

class WorkforcePlanningRepository {
  final SupabaseClient _client;
  WorkforcePlanningRepository(this._client);

  Future<List<WpNode>> nodes() async {
    final rows = await _client.from('wp_value_chain_nodes').select().order('sort_order');
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

  Future<List<WpTask>> tasks() async {
    final rows = await _client.from('wp_tasks').select().order('name');
    return rows.cast<Map<String, dynamic>>().map(WpTask.fromRow).toList();
  }

  Future<List<WpPersonLoad>> personLoads() async {
    final rows = await _client.from('wp_person_load').select();
    return rows.cast<Map<String, dynamic>>().map(WpPersonLoad.fromRow).toList();
  }

  Future<List<WpTaskComputed>> taskComputedForOwner(String employeeId) async {
    final rows = await _client
        .from('wp_task_computed').select().eq('owner_employee_id', employeeId);
    return rows.cast<Map<String, dynamic>>().map(WpTaskComputed.fromRow).toList();
  }

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
