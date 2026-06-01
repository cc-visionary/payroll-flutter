import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/workflow_instance.dart';
import '../models/workflow_step.dart';

/// Filter parameters for the workflows list. Mirrors ApplicantListQuery shape.
class WorkflowListQuery {
  final List<String>? statuses;   // null = all; default in UI = exclude CANCELLED
  final List<String>? types;       // null = all workflow_types
  final String? employeeId;
  const WorkflowListQuery({this.statuses, this.types, this.employeeId});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkflowListQuery &&
          _eq(statuses, other.statuses) &&
          _eq(types, other.types) &&
          employeeId == other.employeeId;

  @override
  int get hashCode => Object.hash(
        Object.hashAll(statuses ?? const []),
        Object.hashAll(types ?? const []),
        employeeId,
      );

  static bool _eq(List<String>? a, List<String>? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class WorkflowRepository {
  final SupabaseClient _client;
  WorkflowRepository(this._client);

  Future<List<WorkflowInstance>> list(WorkflowListQuery q) async {
    var builder = _client.from('workflow_instances').select('*');
    if (q.statuses != null && q.statuses!.isNotEmpty) {
      builder = builder.inFilter('status', q.statuses!);
    }
    if (q.types != null && q.types!.isNotEmpty) {
      builder = builder.inFilter('workflow_type', q.types!);
    }
    if (q.employeeId != null) {
      builder = builder.eq('employee_id', q.employeeId!);
    }
    final rows = await builder.order('created_at', ascending: false);
    return (rows as List)
        .map((r) => WorkflowInstanceFromRow.fromRow(r as Map<String, dynamic>))
        .toList();
  }

  Future<WorkflowInstance?> byId(String id) async {
    final row = await _client.from('workflow_instances').select('*').eq('id', id).maybeSingle();
    if (row == null) return null;
    return WorkflowInstanceFromRow.fromRow(row);
  }

  Future<List<WorkflowStep>> stepsForInstance(String workflowInstanceId) async {
    final rows = await _client
        .from('workflow_steps')
        .select('*')
        .eq('workflow_instance_id', workflowInstanceId)
        .order('step_index', ascending: true);
    return (rows as List)
        .map((r) => WorkflowStepFromRow.fromRow(r as Map<String, dynamic>))
        .toList();
  }
}

final workflowRepositoryProvider =
    Provider<WorkflowRepository>((ref) => WorkflowRepository(Supabase.instance.client));

final workflowListProvider =
    FutureProvider.family<List<WorkflowInstance>, WorkflowListQuery>((ref, q) =>
        ref.read(workflowRepositoryProvider).list(q));

final workflowByIdProvider =
    FutureProvider.family<WorkflowInstance?, String>((ref, id) =>
        ref.read(workflowRepositoryProvider).byId(id));

final workflowStepsProvider =
    FutureProvider.family<List<WorkflowStep>, String>((ref, workflowInstanceId) =>
        ref.read(workflowRepositoryProvider).stepsForInstance(workflowInstanceId));
