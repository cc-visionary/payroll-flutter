import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/status_colors.dart';
import '../../data/models/compensation_change.dart';
import '../../data/models/workflow_instance.dart';
import '../../data/models/workflow_step.dart';
import '../../data/repositories/adjuncts_repository.dart'
    show AdjunctDeleteException;
import '../../data/repositories/compensation_change_repository.dart';
import '../../data/repositories/employee_repository.dart';
import '../../data/repositories/workflow_repository.dart';
import '../auth/profile_provider.dart';
import '../documents/providers.dart' show allDocumentsProvider;
import '../employees/profile/providers.dart'
    show employeeDocumentsProvider, financialsByEmployeeProvider, timelineProvider;
import 'generate_url.dart';
import 'remarks_dialog.dart';

class WorkflowDetailScreen extends ConsumerWidget {
  final String instanceId;
  const WorkflowDetailScreen({super.key, required this.instanceId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider).asData?.value;
    if (!(profile?.isHrOrAdmin ?? false)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Workflow')),
        body: const Center(child: Text('You do not have permission.')),
      );
    }
    final async = ref.watch(workflowByIdProvider(instanceId));
    return async.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Workflow')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('Workflow')),
        body: Center(
          child: Text('Error: $e', style: const TextStyle(color: Colors.red)),
        ),
      ),
      data: (w) {
        if (w == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Workflow')),
            body: const Center(child: Text('Workflow not found.')),
          );
        }
        return _Body(w: w);
      },
    );
  }
}

class _Body extends ConsumerWidget {
  final WorkflowInstance w;
  const _Body({required this.w});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final employee =
        ref.watch(employeeByIdProvider(w.employeeId)).asData?.value;
    final stepsAsync = ref.watch(workflowStepsProvider(w.id));
    return Scaffold(
      appBar: AppBar(
        title: Text(w.title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/workflows'),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (w.status == 'COMPLETED') ...[
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(children: [
                  const Icon(Icons.check_circle_outline, color: Colors.green, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Workflow completed ${w.completedAt?.toIso8601String().substring(0, 10) ?? ''}',
                    style: const TextStyle(color: Colors.green),
                  ),
                ]),
              ),
            ],
            if (w.status == 'CANCELLED') ...[
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(children: [
                  Icon(Icons.cancel_outlined, color: Theme.of(context).colorScheme.error, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Cancelled${w.cancelReason != null ? ' — ${w.cancelReason}' : ''}',
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                ]),
              ),
            ],
            Row(children: [
              Chip(label: Text(w.workflowType)),
              const SizedBox(width: 8),
              Chip(label: Text(w.status)),
              const SizedBox(width: 12),
              if (employee != null)
                Text(employee.fullName, style: const TextStyle(fontSize: 16)),
            ]),
            const SizedBox(height: 16),
            Text(
              'Created ${w.createdAt.toIso8601String().substring(0, 10)}'
              '${w.completedAt != null ? '  ·  Completed ${w.completedAt!.toIso8601String().substring(0, 10)}' : ''}'
              '${w.cancelledAt != null ? '  ·  Cancelled ${w.cancelledAt!.toIso8601String().substring(0, 10)}' : ''}',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            stepsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Error loading steps: $e',
                  style: const TextStyle(color: Colors.red)),
              data: (steps) =>
                  _StepsTimeline(workflow: w, steps: steps),
            ),
            if (w.workflowType == 'SALARY_CHANGE' || w.workflowType == 'ROLE_CHANGE') ...[
              const SizedBox(height: 24),
              _CompensationChangeSection(workflow: w),
            ],
            if (w.status == 'IN_PROGRESS' || w.status == 'DRAFT') ...[
              const SizedBox(height: 32),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: () => _cancelWorkflow(context, ref),
                  icon: Icon(Icons.cancel_outlined, color: Theme.of(context).colorScheme.error, size: 18),
                  label: Text('Cancel workflow', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              ),
            ],
            if (w.status == 'CANCELLED') ...[
              const SizedBox(height: 32),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: () => _deleteWorkflow(context, ref),
                  icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error, size: 18),
                  label: Text('Delete workflow', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              ),
            ],
            if (w.status == 'COMPLETED') ...[
              const SizedBox(height: 32),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: () => _reopenWorkflow(context, ref),
                  icon: const Icon(Icons.undo, size: 18),
                  label: const Text('Undo completion'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _cancelWorkflow(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final reason = await showRemarksDialog(context, 'Cancel this workflow?', 'Cancellation reason (required)', requireNonEmpty: true);
    if (reason == null) return;
    // Without this the write's failure went nowhere — an RLS refusal or a
    // dropped connection looked identical to success, since the only feedback
    // was the status chip quietly not changing.
    try {
      await ref.read(workflowRepositoryProvider).cancelInstance(
            instanceId: w.id,
            cancelReason: reason.trim(),
          );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Cancel failed: $e')));
      return;
    }
    ref.invalidate(workflowByIdProvider(w.id));
    ref.invalidate(workflowListProvider);
    messenger.showSnackBar(const SnackBar(
      content: Text('Workflow cancelled. You can now delete it.'),
    ));
  }

  Future<void> _deleteWorkflow(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    // Route comp-linked workflows through the compensation-change delete so the
    // change + notice + timeline entry go with the workflow (symmetry with the
    // profile-side delete). Standalone workflows use the workflow RPC.
    final change =
        await ref.read(compensationChangeByWorkflowProvider(w.id).future);
    if (!context.mounted) return;

    final isPenalty = w.workflowType == 'REPAYMENT_AGREEMENT';
    final body = change != null
        ? 'This permanently deletes the workflow, its steps, and the linked '
            'compensation change — including its notice document and timeline '
            'entry. This cannot be undone.'
        : isPenalty
            ? 'This permanently deletes the workflow, its steps, the repayment '
                'agreement it generated, and the penalty itself with its '
                'installment schedule. This cannot be undone.\n\n'
                'Blocked if any installment has already been deducted or is '
                'sitting on a payroll run.'
            : 'This permanently deletes the workflow and its steps. This cannot '
                'be undone.';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('Delete this workflow?'),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dctx).colorScheme.error,
              foregroundColor: Theme.of(dctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      if (change != null) {
        await ref
            .read(compensationChangeRepositoryProvider)
            .deleteChange(change.id);
      } else if (isPenalty) {
        // Takes the agreement and the penalty with it, the same way the
        // comp-linked path takes the change, its notice, and its event.
        await ref.read(workflowRepositoryProvider).deletePenaltyWorkflow(w.id);
      } else {
        await ref.read(workflowRepositoryProvider).deleteWorkflow(w.id);
      }
    } on AdjunctDeleteException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      return;
    } on ReleasedPayrollException catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(
          'Cannot delete: released payroll (${e.runPeriod ?? "a released run"}) '
          'already paid at this rate. Cancel the change instead.',
        ),
      ));
      return;
    } on DeleteForbiddenException {
      messenger.showSnackBar(const SnackBar(
        content: Text('You do not have permission to delete this workflow.'),
      ));
      return;
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      return;
    }

    ref.invalidate(workflowListProvider);
    if (isPenalty) {
      // The agreement and the penalty went with it — refresh the Documents
      // list and the employee's Financials tab so neither shows a ghost.
      ref.invalidate(employeeDocumentsProvider(w.employeeId));
      ref.invalidate(allDocumentsProvider);
      ref.invalidate(financialsByEmployeeProvider);
    }
    if (change != null) {
      // Comp-linked delete also removed the change's notice document and
      // timeline entry (delete_compensation_change RPC) — refresh every
      // surface that reflected it, mirroring runDeleteCompensationChange.
      ref.invalidate(compensationChangeByWorkflowProvider(w.id));
      ref.invalidate(compensationChangesByEmployeeProvider(w.employeeId));
      ref.invalidate(pendingCompensationChangesProvider(w.employeeId));
      ref.invalidate(employeeByIdProvider(w.employeeId));
      ref.invalidate(employeeListProvider);
      ref.invalidate(timelineProvider(w.employeeId));
      ref.invalidate(employeeDocumentsProvider(w.employeeId));
      ref.invalidate(allDocumentsProvider);
    }
    messenger.showSnackBar(const SnackBar(content: Text('Workflow deleted.')));
    if (context.mounted) context.go('/workflows');
  }

  Future<void> _reopenWorkflow(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('Reopen this workflow?'),
        content: const Text(
          'It returns to in-progress and reopens the last completed step so you '
          'can redo it. This does not un-apply any compensation change or '
          'un-issue a generated document.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('Reopen'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(workflowRepositoryProvider).reopenInstance(w.id);
    ref.invalidate(workflowStepsProvider(w.id));
    ref.invalidate(workflowByIdProvider(w.id));
    ref.invalidate(workflowListProvider);
    messenger.showSnackBar(const SnackBar(content: Text('Workflow reopened.')));
  }
}

/// Apply-now / cancel actions for the `compensation_changes` row linked to a
/// SALARY_CHANGE / ROLE_CHANGE workflow. Renders nothing if the workflow has
/// no linked change yet (e.g. still generating).
class _CompensationChangeSection extends ConsumerWidget {
  final WorkflowInstance workflow;
  const _CompensationChangeSection({required this.workflow});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(compensationChangeByWorkflowProvider(workflow.id));
    return async.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => const SizedBox.shrink(),
      data: (change) {
        if (change == null) return const SizedBox.shrink();
        final dateLabel = change.effectiveDate.toIso8601String().substring(0, 10);
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final effectiveDay = DateTime(
          change.effectiveDate.year,
          change.effectiveDate.month,
          change.effectiveDate.day,
        );
        final isDue = !effectiveDay.isAfter(today);

        Widget content;
        if (change.status == 'SCHEDULED' && isDue) {
          content = Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton(
                onPressed: () => _applyNow(context, ref, change),
                child: const Text('Apply now'),
              ),
              TextButton(
                onPressed: () => _cancelChange(context, ref, change),
                child: const Text('Cancel change'),
              ),
            ],
          );
        } else if (change.status == 'SCHEDULED') {
          content = Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StatusChip(label: 'Scheduled for $dateLabel', tone: StatusTone.warning),
              TextButton(
                onPressed: () => _cancelChange(context, ref, change),
                child: const Text('Cancel change'),
              ),
            ],
          );
        } else if (change.status == 'APPLIED') {
          final appliedLabel = change.appliedAt?.toIso8601String().substring(0, 10) ?? dateLabel;
          content = StatusChip(label: 'Applied $appliedLabel', tone: StatusTone.success);
        } else {
          content = const StatusChip(label: 'Cancelled', tone: StatusTone.danger);
        }

        return Padding(padding: const EdgeInsets.only(bottom: 8), child: content);
      },
    );
  }

  Future<void> _applyNow(
    BuildContext context,
    WidgetRef ref,
    CompensationChange change,
  ) async {
    // Scope to THIS change only — never company-wide applyDue, which would
    // also materialize any other due change for the company.
    await ref.read(compensationChangeRepositoryProvider).applyChange(change.id);
    ref.invalidate(workflowByIdProvider(workflow.id));
    ref.invalidate(employeeByIdProvider(workflow.employeeId));
    ref.invalidate(pendingCompensationChangesProvider(workflow.employeeId));
    ref.invalidate(compensationChangeByWorkflowProvider(workflow.id));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Change applied.')),
    );
  }

  Future<void> _cancelChange(
    BuildContext context,
    WidgetRef ref,
    CompensationChange change,
  ) async {
    final confirmed = await _confirmDialog(
      context,
      'Cancel this compensation change?',
      'This cancels the pending change and the linked workflow. This cannot be undone.',
    );
    if (!confirmed) return;
    await ref.read(compensationChangeRepositoryProvider).cancel(change.id);
    await ref.read(workflowRepositoryProvider).cancelInstance(
          instanceId: workflow.id,
          cancelReason: 'Compensation change cancelled',
        );
    ref.invalidate(workflowByIdProvider(workflow.id));
    ref.invalidate(employeeByIdProvider(workflow.employeeId));
    ref.invalidate(pendingCompensationChangesProvider(workflow.employeeId));
    ref.invalidate(compensationChangeByWorkflowProvider(workflow.id));
    ref.invalidate(workflowListProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Change cancelled.')),
    );
  }
}

Future<bool> _confirmDialog(BuildContext context, String title, String body) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Back'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Confirm'),
        ),
      ],
    ),
  );
  return result ?? false;
}

class _StepsTimeline extends StatelessWidget {
  final WorkflowInstance workflow;
  final List<WorkflowStep> steps;
  const _StepsTimeline({required this.workflow, required this.steps});

  @override
  Widget build(BuildContext context) {
    if (steps.isEmpty) {
      return const Text('No steps in this workflow.');
    }
    final done = steps
        .where((s) => s.status == 'COMPLETED' || s.status == 'SKIPPED')
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$done / ${steps.length} steps complete',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        for (final s in steps)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 14,
                    child: Text('${s.stepIndex + 1}',
                        style: const TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.name,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        if (s.description != null) ...[
                          const SizedBox(height: 4),
                          Text(s.description!,
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              )),
                        ],
                        const SizedBox(height: 8),
                        Row(children: [
                          Chip(label: Text(s.status)),
                          const SizedBox(width: 8),
                          Text(s.stepType,
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              )),
                        ]),
                        if (s.completedAt != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Completed ${s.completedAt!.toIso8601String().substring(0, 16)}',
                            style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant),
                          ),
                        ],
                        if (s.remarks != null) ...[
                          const SizedBox(height: 4),
                          Text(s.remarks!,
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              )),
                        ],
                        _StepActions(workflow: workflow, step: s),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _StepActions extends ConsumerWidget {
  final WorkflowInstance workflow;
  final WorkflowStep step;
  const _StepActions({required this.workflow, required this.step});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOpen = step.status == 'PENDING' || step.status == 'IN_PROGRESS';
    final isTerminal = workflow.status == 'COMPLETED' || workflow.status == 'CANCELLED';
    if (!isOpen || isTerminal) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(spacing: 8, children: [
        if (step.stepType == 'DOCUMENT_GENERATION') ...[
          FilledButton.icon(
            onPressed: () => _generateNow(context, ref),
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
            label: const Text('Generate now'),
          ),
          // "Generate now" navigates away to the generate screen and never
          // returns, so without this a DOCUMENT_GENERATION step could only
          // ever be skipped — it had no path to COMPLETED at all.
          FilledButton.tonal(
            onPressed: () => _markComplete(context, ref),
            child: const Text('Mark complete'),
          ),
        ],
        if (step.stepType != 'DOCUMENT_GENERATION' && step.stepType != 'APPROVAL')
          FilledButton.tonal(
            onPressed: () => _markComplete(context, ref),
            child: const Text('Mark complete'),
          ),
        if (step.stepType == 'APPROVAL') ...[
          FilledButton.tonal(
            onPressed: () => _approve(context, ref),
            child: const Text('Approve'),
          ),
          OutlinedButton(
            onPressed: () => _reject(context, ref),
            child: const Text('Reject'),
          ),
        ],
        TextButton(
          onPressed: () => _skip(context, ref),
          child: const Text('Skip'),
        ),
      ]),
    );
  }

  Future<void> _generateNow(BuildContext context, WidgetRef ref) async {
    final templateId = step.inputData?['template_id'] as String?;
    if (templateId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Step has no template_id; cannot generate.')),
      );
      return;
    }
    await ref.read(workflowRepositoryProvider).markStepInProgress(step.id);
    ref.invalidate(workflowStepsProvider(workflow.id));

    // For compensation/role-change workflows, thread the linked change id so
    // the salary-adjustment notice renders THIS change (not the newest). Other
    // document workflows (separation, etc.) pass no changeId.
    String? changeId;
    if (workflow.workflowType == 'SALARY_CHANGE' ||
        workflow.workflowType == 'ROLE_CHANGE') {
      final change =
          await ref.read(compensationChangeByWorkflowProvider(workflow.id).future);
      changeId = change?.id;
    }
    // Same idea for a repayment agreement: render THIS penalty's schedule, not
    // whichever penalty happens to be the employee's newest active one.
    final penaltyId = step.inputData?['penalty_id'] as String?;
    if (!context.mounted) return;
    final url = buildGenerateDocumentUrl(
      templateId: templateId,
      employeeId: workflow.employeeId,
      changeId: changeId,
      penaltyId: penaltyId,
      documentId: step.generatedDocumentId,
    );
    context.go(url);
  }

  Future<void> _markComplete(BuildContext context, WidgetRef ref) async {
    final remarks = await showRemarksDialog(context, 'Mark step complete?', 'Remarks (optional)');
    if (remarks == null) return;
    final profile = ref.read(userProfileProvider).asData!.value!;
    await ref.read(workflowRepositoryProvider).markStepCompleted(
          stepId: step.id,
          completedById: profile.userId,
          remarks: remarks.trim().isEmpty ? null : remarks.trim(),
          generatedDocumentId: step.stepType == 'DOCUMENT_GENERATION' ? step.generatedDocumentId : null,
        );
    await ref.read(workflowRepositoryProvider).maybeCompleteInstance(workflow.id);
    ref.invalidate(workflowStepsProvider(workflow.id));
    ref.invalidate(workflowByIdProvider(workflow.id));
    ref.invalidate(workflowListProvider);
  }

  Future<void> _approve(BuildContext context, WidgetRef ref) async {
    final remarks = await showRemarksDialog(context, 'Approve this step?', 'Approval remarks (optional)');
    if (remarks == null) return;
    final profile = ref.read(userProfileProvider).asData!.value!;
    await ref.read(workflowRepositoryProvider).markStepCompleted(
          stepId: step.id,
          completedById: profile.userId,
          remarks: remarks.trim().isEmpty ? null : remarks.trim(),
        );
    await ref.read(workflowRepositoryProvider).maybeCompleteInstance(workflow.id);
    ref.invalidate(workflowStepsProvider(workflow.id));
    ref.invalidate(workflowByIdProvider(workflow.id));
    ref.invalidate(workflowListProvider);
  }

  Future<void> _reject(BuildContext context, WidgetRef ref) async {
    final remarks = await showRemarksDialog(context, 'Reject this step?', 'Rejection reason (required)', requireNonEmpty: true);
    if (remarks == null) return;
    final profile = ref.read(userProfileProvider).asData!.value!;
    await ref.read(workflowRepositoryProvider).markStepRejected(
          stepId: step.id,
          completedById: profile.userId,
          remarks: remarks.trim(),
        );
    ref.invalidate(workflowStepsProvider(workflow.id));
    ref.invalidate(workflowByIdProvider(workflow.id));
    ref.invalidate(workflowListProvider);
  }

  Future<void> _skip(BuildContext context, WidgetRef ref) async {
    final remarks = await showRemarksDialog(context, 'Skip this step?', 'Skip reason (optional)');
    if (remarks == null) return;
    final profile = ref.read(userProfileProvider).asData!.value!;
    await ref.read(workflowRepositoryProvider).markStepSkipped(
          stepId: step.id,
          completedById: profile.userId,
          remarks: remarks.trim().isEmpty ? null : remarks.trim(),
        );
    await ref.read(workflowRepositoryProvider).maybeCompleteInstance(workflow.id);
    ref.invalidate(workflowStepsProvider(workflow.id));
    ref.invalidate(workflowByIdProvider(workflow.id));
    ref.invalidate(workflowListProvider);
  }
}
