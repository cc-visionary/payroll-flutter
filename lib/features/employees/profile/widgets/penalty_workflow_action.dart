import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../data/models/employee.dart';
import '../../../../data/repositories/workflow_repository.dart';
import '../../../auth/profile_provider.dart';
import '../../../documents/providers.dart';
import '../../../workflows/generate_url.dart';
import '../../../workflows/seeders.dart';
import '../providers.dart';
import '../tabs/add_penalty_dialog.dart';

/// Records a penalty as a tracked workflow rather than a bare row, mirroring
/// the compensation-change chain in `compensation_change_action.dart`:
///   1) the penalty + its installments (written by the dialog),
///   2) a DRAFT Penalty Repayment Agreement in `employee_documents`,
///   3) a REPAYMENT_AGREEMENT workflow linked to both,
/// then navigates straight to the generate screen with the penalty pre-filled
/// so the agreement comes out of the same click that recorded the penalty.
///
/// Best-effort atomic, matching separation and compensation change: the penalty
/// survives a later failure and the error surfaces in a snackbar. The penalty is
/// the record of truth for payroll; the agreement is paperwork that can be
/// regenerated from the workflow at any time.
Future<void> runPenaltyWorkflow({
  required WidgetRef ref,
  required BuildContext context,
  required Employee employee,
}) async {
  final penaltyId = await showAddPenaltyDialog(
    context: context,
    employeeId: employee.id,
  );
  if (penaltyId == null || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  final container = ProviderScope.containerOf(context, listen: false);
  final actorId = ref.read(userProfileProvider).asData?.value?.userId;
  if (actorId == null) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          'Penalty recorded, but your user could not be resolved — open the '
          'employee\'s Documents tab to generate the agreement.',
        ),
      ),
    );
    return;
  }

  try {
    final client = Supabase.instance.client;
    const docTitle = 'Penalty Repayment Agreement';

    // Queue the agreement as a DRAFT; the generate screen flips it to ISSUED
    // when the PDF is produced (passing documentId updates in place rather
    // than inserting a second, unlinked document).
    final docRow = await client
        .from('employee_documents')
        .insert({
          'employee_id': employee.id,
          'document_type': 'PENALTY_AGREEMENT',
          'title': docTitle,
          'file_name': '${employee.fullName} — $docTitle.pdf',
          'status': 'DRAFT',
          'uploaded_by_id': actorId,
        })
        .select('id')
        .single();
    final docId = docRow['id'] as String;

    final seed = seedPenaltyWorkflow(
      companyId: employee.companyId,
      employeeId: employee.id,
      employeeFullName: employee.fullName,
      penaltyId: penaltyId,
      employeeDocumentId: docId,
      initiatedById: actorId,
    );
    await container
        .read(workflowRepositoryProvider)
        .insertWithSteps(instance: seed.instance, steps: seed.steps);

    container.invalidate(financialsByEmployeeProvider);
    container.invalidate(employeeDocumentsProvider(employee.id));
    container.invalidate(allDocumentsProvider);
    container.invalidate(workflowListProvider);

    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Penalty recorded for ${employee.fullName}. '
          'Review and generate the repayment agreement.',
        ),
      ),
    );
    context.go(
      buildGenerateDocumentUrl(
        templateId: 'penalty_agreement',
        employeeId: employee.id,
        penaltyId: penaltyId,
        documentId: docId,
      ),
    );
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Penalty recorded, but the agreement workflow failed: $e',
        ),
      ),
    );
  }
}
