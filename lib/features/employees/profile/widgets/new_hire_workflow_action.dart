import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../data/models/employee.dart';
import '../../../../data/repositories/workflow_repository.dart';
import '../../../auth/profile_provider.dart';
import '../../../documents/providers.dart';
import '../../../workflows/seeders.dart';
import '../providers.dart';

/// Inserts the DRAFT hire documents (required contract + NDA, plus any
/// [optionalDocumentTypes]) and a HIRING workflow linked to them. Returns the
/// workflow id.
///
/// Shared by the profile's "Start Workflow → New Hire Onboarding" and by
/// applicant conversion, so both produce the same workflow.
Future<String> createNewHireWorkflow({
  required WorkflowRepository workflows,
  required String companyId,
  required String employeeId,
  required String employeeFullName,
  String? applicantId,
  List<String> optionalDocumentTypes = const [],
  List<String> optionalTasks = const [],
  required String actorId,
}) async {
  final client = Supabase.instance.client;
  final docTypes = [...kRequiredHireDocumentTypes, ...optionalDocumentTypes];
  final inserted = await client
      .from('employee_documents')
      .insert([
        for (final type in docTypes)
          {
            'employee_id': employeeId,
            'document_type': type,
            'title': hireDocTitle(type),
            'file_name': '$employeeFullName — ${hireDocTitle(type)}.pdf',
            'status': 'DRAFT',
            'uploaded_by_id': actorId,
          },
      ])
      .select('id, document_type');
  final docIdByType = <String, String>{
    for (final d in (inserted as List).cast<Map<String, dynamic>>())
      d['document_type'] as String: d['id'] as String,
  };
  final seed = seedHiringWorkflow(
    companyId: companyId,
    employeeId: employeeId,
    employeeFullName: employeeFullName,
    applicantId: applicantId,
    docIdByType: docIdByType,
    optionalDocumentTypes: optionalDocumentTypes,
    optionalTasks: optionalTasks,
    initiatedById: actorId,
  );
  return workflows.insertWithSteps(instance: seed.instance, steps: seed.steps);
}

/// "Start Workflow → New Hire Onboarding": pick the optional items, create the
/// workflow, then open it so HR can generate the contract straight away.
Future<void> runNewHireWorkflow({
  required WidgetRef ref,
  required BuildContext context,
  required Employee employee,
}) async {
  final picked = await showDialog<_NewHireSelection>(
    context: context,
    builder: (_) => const _NewHireDialog(),
  );
  if (picked == null || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  final container = ProviderScope.containerOf(context, listen: false);
  final actorId = ref.read(userProfileProvider).asData?.value?.userId;
  if (actorId == null) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Could not resolve your user — please sign in again.'),
      ),
    );
    return;
  }

  try {
    final workflowId = await createNewHireWorkflow(
      workflows: container.read(workflowRepositoryProvider),
      companyId: employee.companyId,
      employeeId: employee.id,
      employeeFullName: employee.fullName,
      optionalDocumentTypes: picked.documentTypes,
      optionalTasks: picked.tasks,
      actorId: actorId,
    );
    container.invalidate(employeeDocumentsProvider(employee.id));
    container.invalidate(allDocumentsProvider);
    container.invalidate(workflowListProvider);
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text('Onboarding workflow started for ${employee.fullName}.'),
      ),
    );
    context.go('/workflows/$workflowId');
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('Could not start the onboarding workflow: $e')),
    );
  }
}

class _NewHireSelection {
  final List<String> documentTypes;
  final List<String> tasks;
  const _NewHireSelection(this.documentTypes, this.tasks);
}

class _NewHireDialog extends StatefulWidget {
  const _NewHireDialog();

  @override
  State<_NewHireDialog> createState() => _NewHireDialogState();
}

class _NewHireDialogState extends State<_NewHireDialog> {
  // Everything optional starts ticked: HR unticks what this hire doesn't
  // need, and anything left in can still be skipped from the workflow.
  final Set<String> _docs = {...kOptionalHireDocumentTypes};
  final Set<String> _tasks = {...kOnboardingTasks};

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Text(
        text,
        style: t.textTheme.labelMedium?.copyWith(
          color: t.colorScheme.onSurfaceVariant,
          letterSpacing: 0.8,
        ),
      ),
    );
    return AlertDialog(
      title: const Text('New Hire Onboarding'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              heading('REQUIRED'),
              for (final type in kRequiredHireDocumentTypes)
                CheckboxListTile(
                  value: true,
                  onChanged: null,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(hireDocTitle(type)),
                ),
              heading('OPTIONAL DOCUMENTS'),
              for (final type in kOptionalHireDocumentTypes)
                CheckboxListTile(
                  value: _docs.contains(type),
                  onChanged: (v) => setState(
                    () => v == true ? _docs.add(type) : _docs.remove(type),
                  ),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(hireDocTitle(type)),
                ),
              heading('OPTIONAL CHECKLIST'),
              for (final task in kOnboardingTasks)
                CheckboxListTile(
                  value: _tasks.contains(task),
                  onChanged: (v) => setState(
                    () => v == true ? _tasks.add(task) : _tasks.remove(task),
                  ),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(task),
                ),
              const SizedBox(height: 8),
              Text(
                'Optional steps can still be skipped later from the workflow.',
                style: t.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          // Keep the catalogue order, not the tick order.
          onPressed: () => Navigator.of(context).pop(
            _NewHireSelection(
              [
                for (final d in kOptionalHireDocumentTypes)
                  if (_docs.contains(d)) d,
              ],
              [
                for (final task in kOnboardingTasks)
                  if (_tasks.contains(task)) task,
              ],
            ),
          ),
          child: const Text('Start workflow'),
        ),
      ],
    );
  }
}
