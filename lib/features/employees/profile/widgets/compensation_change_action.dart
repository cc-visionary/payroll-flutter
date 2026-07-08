import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../data/models/employee.dart';
import '../../../../data/models/role_scorecard.dart';
import '../../../../data/repositories/compensation_change_repository.dart';
import '../../../../data/repositories/employee_repository.dart';
import '../../../../data/repositories/workflow_repository.dart';
import '../../../auth/profile_provider.dart';
import '../../../workflows/seeders.dart';
import '../providers.dart';
import 'compensation_change_dialog.dart';

/// Performs the full compensation-change chain, mirroring the separation
/// handler in `profile_header.dart:_confirmSeparate`:
///   1) effective-dated `compensation_changes` row (APPLIED now vs SCHEDULED),
///   2) immediate role repoint when effective today and the role actually moves,
///   3) `employment_events` timeline entry (APPROVED),
///   4) DRAFT notice in `employee_documents`,
///   5) single-step workflow, linked back onto the change row,
/// then invalidates every affected provider and shows a snackbar. Best-effort
/// atomic — any failure surfaces via an error snackbar, matching separation.
Future<void> runCompensationChange({
  required WidgetRef ref,
  required BuildContext context,
  required Employee employee,
  required RoleScorecard? currentCard,
  required CompensationChangeRequest req,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final container = ProviderScope.containerOf(context, listen: false);
  final actorId = ref.read(userProfileProvider).asData?.value?.userId;

  // A null actor would produce an unattributable change + workflow; refuse to
  // write rather than seed bad employee/workflow state.
  if (actorId == null) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Could not resolve your user — please sign in again.'),
      ),
    );
    return;
  }

  try {
    final client = Supabase.instance.client;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Effective today (or earlier) applies now; a future date is scheduled and
    // materialized later by CompensationChangeRepository.applyDue().
    final applyImmediately = !req.effectiveDate.isAfter(today);
    final effectiveDateStr = req.effectiveDate.toIso8601String().substring(0, 10);

    // 1) Effective-dated compensation change row (APPLIED now vs SCHEDULED).
    //    Use the captured `container` (not the widget `ref`) for all post-await
    //    reads so they don't depend on the widget's ref surviving disposal.
    final change = await container.read(compensationChangeRepositoryProvider).insert(
          companyId: employee.companyId,
          employeeId: employee.id,
          changeType: req.changeType,
          effectiveDate: req.effectiveDate,
          prevBaseSalary: currentCard?.baseSalary,
          newBaseSalary: req.newSalary,
          prevWageType: currentCard?.wageType,
          newWageType: req.newWageType,
          prevScorecardId: employee.roleScorecardId,
          newScorecardId: req.newScorecardId ?? employee.roleScorecardId,
          reason: req.reason,
          initiatedById: actorId,
          applyImmediately: applyImmediately,
        );

    // 2) When effective now and the role actually moves, repoint the employee's
    //    role scorecard immediately. Future-dated role moves wait for applyDue().
    if (applyImmediately &&
        req.newScorecardId != null &&
        req.newScorecardId != employee.roleScorecardId) {
      await client
          .from('employees')
          .update({'role_scorecard_id': req.newScorecardId})
          .eq('id', employee.id);
    }

    // 3) Append the employment event to the timeline. Capture the id so the
    //    generated notice can link back to it for audit.
    final eventType = switch (req.changeType) {
      'PROMOTION' => 'PROMOTION',
      'DEMOTION' => 'DEMOTION',
      'LATERAL_TRANSFER' => 'DEPARTMENT_TRANSFER',
      _ => 'SALARY_CHANGE',
    };
    final eventRow = await client
        .from('employment_events')
        .insert({
          'employee_id': employee.id,
          'event_type': eventType,
          'event_date': effectiveDateStr,
          'status': 'APPROVED',
          'payload': {
            'change_id': change.id,
            'reason': req.reason,
            'old_salary': currentCard?.baseSalary?.toString(),
            'new_salary': req.newSalary.toString(),
          },
          'requested_by_id': actorId,
          'approved_by_id': actorId,
          'approved_at': DateTime.now().toUtc().toIso8601String(),
        })
        .select('id')
        .single();
    final eventId = eventRow['id'] as String;

    // 4) Queue the notice as a DRAFT under the employee's Documents tab; the PDF
    //    is rendered later via "Generate now" on the workflow.
    final docType = compensationDocumentType(req.changeType);
    final docTitle = compensationDocTitle(req.changeType);
    final docRow = await client
        .from('employee_documents')
        .insert({
          'employee_id': employee.id,
          'document_type': docType,
          'title': docTitle,
          'file_name': '${employee.fullName} — $docTitle.pdf',
          'status': 'DRAFT',
          'generated_from_event_id': eventId,
          'uploaded_by_id': actorId,
        })
        .select('id')
        .single();
    final docId = docRow['id'] as String;

    // 5) Seed the single-step workflow and link it back onto the change row.
    final seed = seedCompensationChangeWorkflow(
      companyId: employee.companyId,
      employeeId: employee.id,
      employeeFullName: employee.fullName,
      changeType: req.changeType,
      employeeDocumentId: docId,
      initiatedById: actorId,
    );
    final wfId = await container
        .read(workflowRepositoryProvider)
        .insertWithSteps(instance: seed.instance, steps: seed.steps);
    await container
        .read(compensationChangeRepositoryProvider)
        .linkWorkflow(id: change.id, workflowId: wfId, documentId: docId);

    // 6) Refresh every surface that reflects the new state.
    container.invalidate(employeeByIdProvider(employee.id));
    container.invalidate(employeeListProvider);
    container.invalidate(timelineProvider(employee.id));
    container.invalidate(employeeDocumentsProvider(employee.id));
    container.invalidate(workflowListProvider);
    container.invalidate(compensationChangesByEmployeeProvider(employee.id));
    container.invalidate(pendingCompensationChangesProvider(employee.id));

    if (context.mounted) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${employee.fullName}: $docTitle queued · effective $effectiveDateStr.',
          ),
        ),
      );
    }
  } catch (e, st) {
    messenger.showSnackBar(
      SnackBar(content: Text('Compensation change failed: $e')),
    );
    // ignore: avoid_print
    print('Compensation change write failed: $e\n$st');
  }
}
