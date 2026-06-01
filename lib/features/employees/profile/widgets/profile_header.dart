import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/breakpoints.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../data/models/employee.dart';
import '../../../../data/repositories/employee_repository.dart';
import '../../../../data/repositories/role_scorecard_repository.dart';
import '../../../../data/repositories/workflow_repository.dart';
import '../../../auth/profile_provider.dart';
import '../../../workflows/seeders.dart';
import '../providers.dart';
import 'info_card.dart';

/// Back link + name/title block + action buttons + four info cards.
/// Pure layout — all data comes in via props so this works in tests too.
class ProfileHeader extends ConsumerWidget {
  final Employee employee;
  const ProfileHeader({super.key, required this.employee});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider).asData?.value;
    final canManage = profile?.canManageEmployees ?? false;
    final isAdmin = profile?.isAdmin ?? false;

    // Role scorecard is the source of truth for job title + department when
    // an employee is linked to one. Fall back to the employee's own fields
    // for legacy rows that don't have a role linked yet.
    final cardsAsync = ref.watch(roleScorecardListProvider);
    final linkedCard = cardsAsync.asData?.value
        .where((c) => c.id == employee.roleScorecardId)
        .cast<dynamic>()
        .firstOrNull;
    final roleDerivedDeptId = linkedCard?.departmentId as String?;
    final roleDerivedJobTitle = linkedCard?.jobTitle as String?;
    final effectiveDeptId = roleDerivedDeptId ?? employee.departmentId;

    final deptAsync = effectiveDeptId == null
        ? const AsyncValue<String?>.data(null)
        : ref.watch(departmentNameProvider(effectiveDeptId));
    final entityAsync = employee.hiringEntityId == null
        ? const AsyncValue<String?>.data(null)
        : ref.watch(hiringEntityNameProvider(employee.hiringEntityId!));
    final managerAsync = employee.reportsToId == null
        ? const AsyncValue<String?>.data(null)
        : ref.watch(managerNameProvider(employee.reportsToId!));

    final deptName = deptAsync.asData?.value;
    final entityName = entityAsync.asData?.value;
    final managerName = managerAsync.asData?.value;
    final effectiveJobTitle = roleDerivedJobTitle ?? employee.jobTitle;
    final archived = employee.deletedAt != null;
    final statusLabel = archived
        ? 'ARCHIVED'
        : employee.employmentStatus.toUpperCase();
    final typeLabel = employee.employmentType.replaceAll('_', ' ');
    final mobile = isMobile(context);

    final nameBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          employee.fullName,
          style: TextStyle(
            fontSize: mobile ? 20 : 24,
            fontWeight: FontWeight.w700,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            Text(
              employee.employeeNumber,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: Color(0xFF6B7280),
              ),
            ),
            const Text('│',
                style: TextStyle(color: Color(0xFF9CA3AF))),
            StatusChip(
              label: typeLabel,
              tone: toneForStatus(typeLabel),
            ),
            StatusChip(
              label: statusLabel,
              tone: archived
                  ? ChipTone.danger
                  : toneForStatus(statusLabel),
            ),
            if (employee.larkUserId != null) ...[
              const Text('│',
                  style: TextStyle(color: Color(0xFF9CA3AF))),
              Text(
                'Lark: ${employee.larkUserId}',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: Color(0xFF6B7280),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Text(
          _buildSubtitle(effectiveJobTitle, deptName),
          style: const TextStyle(
            fontSize: 14,
            color: Color(0xFF374151),
          ),
        ),
        if (entityName != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'Hired under: $entityName',
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF6B7280),
              ),
            ),
          ),
      ],
    );

    final actionButtons = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (canManage)
          OutlinedButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content:
                        Text('Workflow launcher — coming soon.')),
              );
            },
            child: const Text('Start Workflow'),
          ),
        if (canManage)
          OutlinedButton(
            onPressed: () =>
                context.push('/employees/${employee.id}/edit'),
            child: const Text('Edit Employee'),
          ),
        if (isAdmin && employee.employmentStatus == 'ACTIVE')
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
            ),
            onPressed: () => _confirmSeparate(context, ref),
            child: const Text('Separate Employee'),
          ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Back link
        InkWell(
          onTap: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/employees');
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('← ', style: TextStyle(color: Color(0xFF2563EB))),
                Text(
                  'Back to Employees',
                  style: TextStyle(
                    color: const Color(0xFF2563EB),
                    decoration: TextDecoration.underline,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Name + action buttons row — stacked on mobile.
        if (mobile)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              nameBlock,
              const SizedBox(height: 12),
              actionButtons,
            ],
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: nameBlock),
              const SizedBox(width: 16),
              actionButtons,
            ],
          ),
        const SizedBox(height: 20),
        // Info cards row
        LayoutBuilder(builder: (ctx, c) {
          // Four cards: wrap when narrow.
          final cardWidth = c.maxWidth >= 920
              ? (c.maxWidth - 3 * 12) / 4
              : c.maxWidth >= 600
                  ? (c.maxWidth - 12) / 2
                  : c.maxWidth;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: cardWidth,
                child: InfoCard(
                  label: 'Hire Date',
                  value: _fmtDate(employee.hireDate),
                ),
              ),
              SizedBox(
                width: cardWidth,
                child: InfoCard(
                  label: 'Regularization Date',
                  value: employee.regularizationDate == null
                      ? '—'
                      : _fmtDate(employee.regularizationDate!),
                ),
              ),
              SizedBox(
                width: cardWidth,
                child: InfoCard(
                  label: 'OT Eligible',
                  value: employee.isOtEligible ? 'Yes' : 'No',
                ),
              ),
              SizedBox(
                width: cardWidth,
                child: InfoCard(
                  label: 'Reports To',
                  value: managerName ?? '—',
                ),
              ),
            ],
          );
        }),
      ],
    );
  }

  String _buildSubtitle(String? jobTitle, String? deptName) {
    final parts = <String>[];
    if (jobTitle != null && jobTitle.isNotEmpty) parts.add(jobTitle);
    if (deptName != null && deptName.isNotEmpty) parts.add(deptName);
    return parts.join(' • ');
  }

  String _fmtDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  Future<void> _confirmSeparate(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final actorId = ref.read(userProfileProvider).asData?.value?.userId;
    final _SeparationResult? result;
    try {
      result = await showDialog<_SeparationResult>(
        context: context,
        builder: (c) => _SeparationDialog(employeeName: employee.fullName),
      );
    } catch (e, st) {
      messenger.showSnackBar(SnackBar(content: Text('Dialog error: $e')));
      // ignore: avoid_print
      print('Separate dialog failed: $e\n$st');
      return;
    }
    if (result == null || !context.mounted) return;

    try {
    final client = Supabase.instance.client;

    // 1) Update employment status + separation date on the employee row.
    //    When the user opts to archive on separation, also stamp deleted_at
    //    so the employee disappears from active lists and payroll runs.
    await client.from('employees').update({
      'employment_status': result.status,
      'separation_date': result.date.toIso8601String().substring(0, 10),
      if (result.archive) 'deleted_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', employee.id);

    // 2) Append SEPARATION_CONFIRMED to the timeline. Capture the new event
    //    id so generated documents can link back to it for audit.
    final eventRow = await client
        .from('employment_events')
        .insert({
          'employee_id': employee.id,
          'event_type': 'SEPARATION_CONFIRMED',
          'event_date': result.date.toIso8601String().substring(0, 10),
          'status': 'APPROVED',
          'payload': {'reason': result.status},
          if (result.reason.isNotEmpty) 'remarks': result.reason,
          if (actorId != null) 'requested_by_id': actorId,
          if (actorId != null) 'approved_by_id': actorId,
          if (actorId != null)
            'approved_at': DateTime.now().toUtc().toIso8601String(),
        })
        .select('id')
        .single();
    final eventId = eventRow['id'] as String;

    // 3) Queue document placeholders (DRAFT) + insert a SEPARATION workflow
    //    so HR has a single "what's in-flight" inbox. The workflow_steps link
    //    to the placeholder rows via input_data + generated_document_id; the
    //    actual PDF rendering happens via "Generate now" on /workflows/:id.
    if (result.documents.isNotEmpty) {
      final docs = [
        for (final type in result.documents)
          {
            'employee_id': employee.id,
            'document_type': type,
            'title': _docTitleFor(type),
            'file_name': '${employee.fullName} — ${_docTitleFor(type)}.pdf',
            'status': 'DRAFT',
            'generated_from_event_id': eventId,
            if (actorId != null) 'uploaded_by_id': actorId,
          },
      ];
      // Insert with .select() so we get the new ids back to link the workflow steps.
      final insertedDocs = await client
          .from('employee_documents')
          .insert(docs)
          .select('id, document_type');
      final docIdByType = <String, String>{
        for (final d in (insertedDocs as List))
          (d as Map<String, dynamic>)['document_type'] as String:
              d['id'] as String,
      };
      if (actorId != null) {
        final seed = seedSeparationWorkflow(
          companyId: employee.companyId,
          employeeId: employee.id,
          employeeFullName: employee.fullName,
          documentTypes: result.documents,
          eventId: eventId,
          docIdByType: docIdByType,
          initiatedById: actorId,
        );
        await container
            .read(workflowRepositoryProvider)
            .insertWithSteps(instance: seed.instance, steps: seed.steps);
        container.invalidate(workflowListProvider);
      }
    }

    container.invalidate(employeeByIdProvider(employee.id));
    container.invalidate(employeeListProvider);
    container.invalidate(timelineProvider(employee.id));
    container.invalidate(employeeDocumentsProvider(employee.id));

    if (context.mounted) {
      final docCount = result.documents.length;
      final tail = [
        if (docCount > 0) '$docCount document${docCount == 1 ? '' : 's'} queued',
        if (result.archive) 'archived',
      ].join(' · ');
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${employee.fullName} separated as ${result.status}'
            '${tail.isEmpty ? '.' : ' · $tail.'}',
          ),
        ),
      );
    }
    } catch (e, st) {
      messenger.showSnackBar(SnackBar(content: Text('Separate failed: $e')));
      // ignore: avoid_print
      print('Separate write failed: $e\n$st');
    }
  }
}

String _docTitleFor(String type) {
  switch (type) {
    case 'CERTIFICATE_OF_EMPLOYMENT':
      return 'Certificate of Employment';
    case 'QUITCLAIM':
      return 'Quitclaim and Release';
    case 'POST_EMPLOYMENT_CONFIDENTIALITY':
      return 'Post-Employment Confidentiality Agreement';
    case 'SEPARATION_LETTER':
      return 'Separation Letter';
    case 'CLEARANCE_FORM':
      return 'Clearance Form';
    default:
      return type.replaceAll('_', ' ');
  }
}

class _SeparationResult {
  final String status;
  final DateTime date;
  final String reason;
  final List<String> documents;
  final bool archive;
  const _SeparationResult({
    required this.status,
    required this.date,
    required this.reason,
    required this.documents,
    required this.archive,
  });
}

class _SeparationDialog extends StatefulWidget {
  final String employeeName;
  const _SeparationDialog({required this.employeeName});

  @override
  State<_SeparationDialog> createState() => _SeparationDialogState();
}

class _SeparationDialogState extends State<_SeparationDialog> {
  String _status = 'RESIGNED';
  DateTime _date = DateTime.now();
  final _reason = TextEditingController();

  static const _docOptions = <_DocOption>[
    _DocOption('CERTIFICATE_OF_EMPLOYMENT', 'Certificate of Employment'),
    _DocOption('QUITCLAIM', 'Quitclaim and Release'),
    _DocOption(
        'POST_EMPLOYMENT_CONFIDENTIALITY', 'Post-Employment Confidentiality'),
    _DocOption('SEPARATION_LETTER', 'Separation Letter'),
    _DocOption('CLEARANCE_FORM', 'Clearance Form'),
  ];
  final _selected = <String>{'CERTIFICATE_OF_EMPLOYMENT'};
  bool _archive = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(1990),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = _date.toIso8601String().substring(0, 10);
    return AlertDialog(
      title: Text('Separate ${widget.employeeName}'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: const InputDecoration(
                  labelText: 'Separation type',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  'RESIGNED',
                  'TERMINATED',
                  'AWOL',
                  'END_OF_CONTRACT',
                  'RETIRED',
                  'DECEASED',
                ]
                    .map((s) => DropdownMenuItem(
                        value: s, child: Text(s.replaceAll('_', ' '))))
                    .toList(),
                onChanged: (v) => setState(() => _status = v!),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: _pickDate,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Separation date',
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.calendar_today, size: 18),
                  ),
                  child: Text(dateStr),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _reason,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Reason / remarks',
                  hintText: 'e.g. Resigned to pursue another opportunity.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Generate separation documents',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                'Selected docs are queued as DRAFT under the employee\'s '
                'Documents tab.',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              for (final opt in _docOptions)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _selected.contains(opt.code),
                  title: Text(opt.label),
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      _selected.add(opt.code);
                    } else {
                      _selected.remove(opt.code);
                    }
                  }),
                ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                value: _archive,
                title: const Text('Also archive employee'),
                subtitle: const Text(
                  'Hides them from active lists and payroll runs. '
                  'Records are preserved and can be restored later.',
                ),
                onChanged: (v) => setState(() => _archive = v ?? false),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFDC2626),
          ),
          onPressed: () => Navigator.pop(
            context,
            _SeparationResult(
              status: _status,
              date: _date,
              reason: _reason.text.trim(),
              documents: _selected.toList(),
              archive: _archive,
            ),
          ),
          child: const Text('Separate'),
        ),
      ],
    );
  }
}

class _DocOption {
  final String code;
  final String label;
  const _DocOption(this.code, this.label);
}
