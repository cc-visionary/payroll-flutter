import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/models/compensation_change.dart';
import '../../../../data/models/employee.dart';
import '../../../../data/repositories/compensation_change_repository.dart';
import '../../../../data/repositories/employee_repository.dart';
import '../../../../data/repositories/workflow_repository.dart';
import '../../../documents/providers.dart' show allDocumentsProvider;
import '../providers.dart';
import 'compensation_change_dialog.dart';

/// Deletes a single compensation change and everything it spawned — its
/// workflow, notice document, and timeline entry — via the atomic
/// `delete_compensation_change` RPC, then refreshes every affected surface.
///
/// Confirms first, naming exactly what will be destroyed. When an APPLIED role
/// change is removed the employee is moved back to their previous role, so the
/// dialog warns about that. If a RELEASED payroll run already paid at this rate
/// the RPC refuses ([ReleasedPayrollException]); that is surfaced as guidance to
/// cancel the change instead, not treated as a crash.
///
/// Mirrors the messenger/container/try-catch idiom of `runCompensationChange`:
/// the captured [container] (not the widget [ref]) drives all post-await reads
/// and invalidations, and post-await `context` use is guarded by `context.mounted`.
Future<void> runDeleteCompensationChange({
  required WidgetRef ref,
  required BuildContext context,
  required Employee employee,
  required CompensationChange change,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final container = ProviderScope.containerOf(context, listen: false);
  final label = compensationChangeTypeLabel(change.changeType);

  // 1) Confirm — name everything that dies so a delete is never a surprise.
  final body = StringBuffer(
    'This permanently deletes the $label, its workflow, its notice document, '
    'and its timeline entry. This cannot be undone.',
  );
  if (change.status == 'APPLIED' && change.isRoleChange) {
    body.write(
      '\n\n${employee.fullName} will be moved back to their previous role.',
    );
  }
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Delete $label?'),
      content: Text(body.toString()),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(dialogContext).colorScheme.error,
            foregroundColor: Theme.of(dialogContext).colorScheme.onError,
          ),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;

  // 2) Atomic delete. The released-payroll refusal is guidance, not a failure —
  //    catch it first, before the generic handler.
  try {
    await container
        .read(compensationChangeRepositoryProvider)
        .deleteChange(change.id);
  } on ReleasedPayrollException catch (e) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Cannot delete: released payroll (${e.runPeriod ?? "a released run"}) '
          'already paid at this rate. Cancel the change instead.',
        ),
      ),
    );
    return;
  } on DeleteForbiddenException {
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          'You do not have permission to delete this compensation change.',
        ),
      ),
    );
    return;
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    return;
  }

  // 3) Refresh every surface that reflected the now-deleted change. The
  //    workflow lookup is keyed by workflow id, so only invalidate it when one
  //    was ever linked.
  container.invalidate(compensationChangesByEmployeeProvider(employee.id));
  container.invalidate(pendingCompensationChangesProvider(employee.id));
  container.invalidate(employeeByIdProvider(employee.id));
  container.invalidate(employeeListProvider);
  container.invalidate(timelineProvider(employee.id));
  container.invalidate(employeeDocumentsProvider(employee.id));
  container.invalidate(allDocumentsProvider);
  container.invalidate(workflowListProvider);
  if (change.workflowId != null) {
    container.invalidate(
      compensationChangeByWorkflowProvider(change.workflowId!),
    );
  }

  // 4) Confirm success.
  if (context.mounted) {
    messenger.showSnackBar(SnackBar(content: Text('$label deleted.')));
  }
}
