import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

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
/// Only reachable through [runNewHireWorkflow], whose dialog will not start
/// until HR confirms the Lark onboarding checklist was sent.
Future<String> createNewHireWorkflow({
  required WorkflowRepository workflows,
  required String companyId,
  required String employeeId,
  required String employeeFullName,
  String? applicantId,
  List<String> optionalDocumentTypes = const [],
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
    initiatedById: actorId,
  );
  return workflows.insertWithSteps(instance: seed.instance, steps: seed.steps);
}

/// "Start Workflow → New Hire Onboarding": HR sends the Lark onboarding
/// checklist first, picks any optional documents, then the workflow is created
/// and opened so HR can generate the contract straight away.
Future<void> runNewHireWorkflow({
  required WidgetRef ref,
  required BuildContext context,
  required Employee employee,
}) async {
  final picked = await showNewHireDialog(context);
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
      optionalDocumentTypes: picked,
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

/// The New Hire Onboarding dialog. Returns the optional document types HR
/// picked, or null when cancelled. Exposed for widget tests of the gate.
@visibleForTesting
Future<List<String>?> showNewHireDialog(BuildContext context) =>
    showDialog<List<String>>(
      context: context,
      builder: (_) => const _NewHireDialog(),
    );

class _NewHireDialog extends StatefulWidget {
  const _NewHireDialog();

  @override
  State<_NewHireDialog> createState() => _NewHireDialogState();
}

class _NewHireDialogState extends State<_NewHireDialog> {
  // Optional documents start unticked: HR opts in per hire.
  final Set<String> _docs = {};

  /// The gate: the workflow cannot start until HR confirms the new hire's
  /// onboarding checklist was made from the Lark template and sent to them.
  bool _checklistSent = false;

  Future<void> _openTemplate() async {
    final ok = await launchUrl(
      Uri.parse(kLarkOnboardingChecklistTemplateUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the Lark template.')),
      );
    }
  }

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
              heading('BEFORE YOU START'),
              Text(
                'Make the new hire\'s onboarding checklist from the Lark '
                'template and send it to them in Lark chat.',
                style: t.textTheme.bodyMedium,
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _openTemplate,
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Open checklist template in Lark'),
                ),
              ),
              CheckboxListTile(
                value: _checklistSent,
                onChanged: (v) => setState(() => _checklistSent = v ?? false),
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'I made the checklist and sent it to the new hire',
                ),
              ),
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
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        Tooltip(
          message: _checklistSent
              ? ''
              : 'Send the onboarding checklist first',
          child: FilledButton(
            // Keep the catalogue order, not the tick order.
            onPressed: _checklistSent
                ? () => Navigator.of(context).pop([
                    for (final d in kOptionalHireDocumentTypes)
                      if (_docs.contains(d)) d,
                  ])
                : null,
            child: const Text('Start workflow'),
          ),
        ),
      ],
    );
  }
}
