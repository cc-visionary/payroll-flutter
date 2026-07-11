import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/workflow_instance.dart';
import '../models/workflow_step.dart';
import 'compensation_change_repository.dart'
    show DeleteForbiddenException, deleteForbiddenFrom;

/// Pure input shape for a new workflow_instance. Used by the seeders in
/// `lib/features/workflows/seeders.dart` so kickoff handlers don't have to
/// know SQL column names.
class WorkflowInstanceInput {
  final String companyId;
  final String employeeId;
  final String workflowType;
  final String title;
  final Map<String, dynamic> context;
  final String initiatedById;
  const WorkflowInstanceInput({
    required this.companyId,
    required this.employeeId,
    required this.workflowType,
    required this.title,
    this.context = const {},
    required this.initiatedById,
  });
}

class WorkflowStepInput {
  final int stepIndex;
  final String stepType;
  final String name;
  final String? description;
  final Map<String, dynamic>? inputData;
  final String? generatedDocumentId;
  const WorkflowStepInput({
    required this.stepIndex,
    required this.stepType,
    required this.name,
    this.description,
    this.inputData,
    this.generatedDocumentId,
  });
}

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

  /// Insert one workflow_instance + N workflow_steps. Two sequential calls —
  /// Supabase Dart client doesn't expose multi-statement transactions, so this
  /// is best-effort atomic. If steps insert fails, the orphan instance is left
  /// in IN_PROGRESS (with no steps) and surfaces in the UI for manual cancel.
  /// Acceptable for MVP given low-concurrency single-handler usage.
  Future<String> insertWithSteps({
    required WorkflowInstanceInput instance,
    required List<WorkflowStepInput> steps,
  }) async {
    final instanceRow = await _client
        .from('workflow_instances')
        .insert({
          'company_id': instance.companyId,
          'employee_id': instance.employeeId,
          'workflow_type': instance.workflowType,
          'status': 'IN_PROGRESS',  // not DRAFT — DRAFT means "not yet kicked off"
          'title': instance.title,
          'context': instance.context,
          'initiated_by_id': instance.initiatedById,
        })
        .select('id')
        .single();
    final instanceId = instanceRow['id'] as String;

    if (steps.isNotEmpty) {
      final stepPayload = [
        for (final s in steps)
          {
            'workflow_instance_id': instanceId,
            'step_index': s.stepIndex,
            'step_type': s.stepType,
            'name': s.name,
            'description': s.description,
            'input_data': s.inputData,
            'generated_document_id': s.generatedDocumentId,
          },
      ];
      await _client.from('workflow_steps').insert(stepPayload);
    }
    return instanceId;
  }

  Future<void> markStepInProgress(String stepId) async {
    await _client
        .from('workflow_steps')
        .update({'status': 'IN_PROGRESS'})
        .eq('id', stepId);
  }

  Future<void> markStepCompleted({
    required String stepId,
    required String completedById,
    String? remarks,
    Map<String, dynamic>? outputData,
    String? generatedDocumentId,
  }) async {
    final payload = <String, dynamic>{
      'status': 'COMPLETED',
      'completed_by_id': completedById,
      'completed_at': DateTime.now().toIso8601String(),
      if (remarks != null) ...{'remarks': remarks},
      if (outputData != null) ...{'output_data': outputData},
      if (generatedDocumentId != null) ...{'generated_document_id': generatedDocumentId},
    };
    await _client.from('workflow_steps').update(payload).eq('id', stepId);
  }

  Future<void> markStepSkipped({
    required String stepId,
    required String completedById,
    String? remarks,
  }) async {
    await _client.from('workflow_steps').update({
      'status': 'SKIPPED',
      'completed_by_id': completedById,
      'completed_at': DateTime.now().toIso8601String(),
      if (remarks != null) ...{'remarks': remarks},
    }).eq('id', stepId);
  }

  Future<void> markStepRejected({
    required String stepId,
    required String completedById,
    required String remarks,
  }) async {
    await _client.from('workflow_steps').update({
      'status': 'REJECTED',
      'completed_by_id': completedById,
      'completed_at': DateTime.now().toIso8601String(),
      'remarks': remarks,
    }).eq('id', stepId);
  }

  /// If every step on the instance is COMPLETED or SKIPPED, flip the instance
  /// status to COMPLETED + stamp completed_at. Called after every step status
  /// change. No-op if any step is still PENDING/IN_PROGRESS, or if the instance
  /// is already COMPLETED/CANCELLED.
  Future<void> maybeCompleteInstance(String instanceId) async {
    final stepRows = await _client
        .from('workflow_steps')
        .select('status')
        .eq('workflow_instance_id', instanceId);
    final statuses = [
      for (final r in (stepRows as List))
        (r as Map<String, dynamic>)['status'] as String,
    ];
    if (statuses.isEmpty) return;
    final allDone = statuses.every((s) => s == 'COMPLETED' || s == 'SKIPPED');
    if (!allDone) return;
    await _client.from('workflow_instances').update({
      'status': 'COMPLETED',
      'completed_at': DateTime.now().toIso8601String(),
    })
    .eq('id', instanceId)
    .inFilter('status', ['DRAFT', 'IN_PROGRESS']);  // idempotent — don't re-complete
  }

  Future<void> cancelInstance({
    required String instanceId,
    required String cancelReason,
  }) async {
    // Note: `workflow_instances` schema has no cancelled_by_id column.
    // If/when audit-trail granularity is needed, add the column via
    // migration + a setByUserId param here (mirroring the step lifecycle).
    await _client.from('workflow_instances').update({
      'status': 'CANCELLED',
      'cancelled_at': DateTime.now().toIso8601String(),
      'cancel_reason': cancelReason,
    })
    .eq('id', instanceId)
    .inFilter('status', ['DRAFT', 'IN_PROGRESS']);  // idempotent
  }

  /// Hard-deletes a CANCELLED, standalone (non-compensation) workflow together
  /// with its steps (FK cascade), via the `delete_workflow` RPC. Comp-linked
  /// workflows must be removed through `CompensationChangeRepository.deleteChange`
  /// instead — the RPC refuses them (`WORKFLOW_HAS_COMPENSATION_CHANGE`) so the
  /// change, notice document, and timeline event are cleaned up together.
  ///
  /// Throws [DeleteForbiddenException] when RLS permitted the read but not the
  /// delete — nothing is deleted in that case.
  Future<void> deleteWorkflow(String instanceId) async {
    try {
      await _client.rpc('delete_workflow', params: {'p_instance_id': instanceId});
    } catch (e) {
      final forbidden = deleteForbiddenFrom(e);
      if (forbidden != null) throw forbidden;
      rethrow;
    }
  }

  /// Undo a mistaken completion: revert the most-recently-finished step back to
  /// PENDING and flip the instance from COMPLETED back to IN_PROGRESS. Client-side
  /// (no cascade/integrity to protect), mirroring [cancelInstance]. Guarded up
  /// front on the instance still being COMPLETED, so the whole operation —
  /// step revert included — is idempotent: a repeat call is a no-op rather than
  /// walking back a second finished step. Does not touch any linked
  /// compensation change or generated document.
  Future<void> reopenInstance(String instanceId) async {
    // Reopening is only meaningful for a COMPLETED instance. Check first: the
    // step revert below is NOT status-guarded, so without this a second call
    // would walk back a second finished step.
    final inst = await _client
        .from('workflow_instances')
        .select('status')
        .eq('id', instanceId)
        .maybeSingle();
    if (inst == null || inst['status'] != 'COMPLETED') return;

    final stepRows = await _client
        .from('workflow_steps')
        .select('id')
        .eq('workflow_instance_id', instanceId)
        .inFilter('status', ['COMPLETED', 'SKIPPED'])
        .order('completed_at', ascending: false)
        .order('step_index', ascending: false)
        .limit(1);
    final rows = stepRows as List;
    if (rows.isNotEmpty) {
      final stepId = (rows.first as Map<String, dynamic>)['id'] as String;
      await _client.from('workflow_steps').update({
        'status': 'PENDING',
        'completed_by_id': null,
        'completed_at': null,
        'remarks': null,
      }).eq('id', stepId);
    }
    await _client
        .from('workflow_instances')
        .update({'status': 'IN_PROGRESS', 'completed_at': null})
        .eq('id', instanceId)
        .eq('status', 'COMPLETED');
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
