import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../data/models/employee.dart';
import '../../../auth/profile_provider.dart';
import '../../../documents/providers.dart';
import '../../../documents/templates/document_template.dart';
import '../../../documents/templates/template_picker_field.dart';
import '../../../documents/templates/template_registry.dart';
import '../providers.dart';
import '../widgets/info_card.dart';
import 'document_status.dart';

/// Storage bucket holding frozen, generated employee PDFs. Object path is
/// `{employee_id}/{document_id}.pdf`, recorded in each row's `file_path`.
const String _kDocumentsBucket = 'employee-documents';

/// Signed-URL validity window. Long enough to open + download once; short
/// enough that a shared/leaked link expires quickly.
const int _kSignedUrlExpirySeconds = 300;

class DocumentsTab extends ConsumerStatefulWidget {
  final Employee employee;
  const DocumentsTab({super.key, required this.employee});

  @override
  ConsumerState<DocumentsTab> createState() => _DocumentsTabState();
}

class _DocumentsTabState extends ConsumerState<DocumentsTab> {
  // Holds the selected template id (from kTemplates), or null.
  String? _selectedTemplateId;

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider).asData?.value;
    final canManage = profile?.canManageEmployees ?? false;
    final async = ref.watch(employeeDocumentsProvider(widget.employee.id));

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      children: [
        if (canManage)
          _Card(
            title: 'Generate Document',
            child: Row(
              children: [
                Expanded(
                  child: TemplatePickerField(
                    selectedId: _selectedTemplateId,
                    hintText: 'Select document type...',
                    onSelected: (id) =>
                        setState(() => _selectedTemplateId = id),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _selectedTemplateId == null
                      ? null
                      : () async {
                          final id = _selectedTemplateId!;
                          final tpl = findTemplateById(id);
                          if (tpl != null &&
                              widget.employee.hiringEntityId != null) {
                            final hiringEntity = await ref
                                .read(
                                  hiringEntityByIdProvider(
                                    widget.employee.hiringEntityId!,
                                  ).future,
                                )
                                .catchError((_) => null);
                            final ctx = AutofillContext(
                              employee: widget.employee,
                              company: hiringEntity,
                              ref: ref,
                            );
                            final gates = tpl.gates(ctx);
                            if (gates.isNotEmpty) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(gates.first.reason)),
                                );
                              }
                              return;
                            }
                          }
                          if (context.mounted) {
                            context.go(
                              '/documents/generate/$id?employeeId=${widget.employee.id}',
                            );
                          }
                        },
                  child: const Text('Generate'),
                ),
              ],
            ),
          ),
        if (canManage) const SizedBox(height: 16),
        _Card(
          title: 'Documents',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              async.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text(
                  'Error: $e',
                  style: const TextStyle(color: Colors.red),
                ),
                data: (rows) => rows.isEmpty
                    ? Text(
                        'No documents on file',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final r in rows)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: DocRow(row: r),
                            ),
                        ],
                      ),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () =>
                      context.go('/documents?employeeId=${widget.employee.id}'),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('View in Documents hub'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  final String title;
  final Widget child;
  const _Card({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
          Divider(height: 1, color: Theme.of(context).dividerColor),
          Padding(padding: const EdgeInsets.all(16), child: child),
        ],
      ),
    );
  }
}

/// A single row in the "Documents on file" list: title + meta, a status chip,
/// and (when a stored PDF exists) a View/Download action that opens the file
/// via a short-lived Storage signed URL. Public so it can be widget-tested in
/// isolation without standing up the full tab (Riverpod + Supabase).
class DocRow extends StatefulWidget {
  final Map<String, dynamic> row;
  const DocRow({super.key, required this.row});

  @override
  State<DocRow> createState() => _DocRowState();
}

class _DocRowState extends State<DocRow> {
  bool _opening = false;

  Map<String, dynamic> get row => widget.row;

  Future<void> _openDocument() async {
    final filePath = (row['file_path'] as String?)?.trim();
    if (filePath == null || filePath.isEmpty) return;

    setState(() => _opening = true);
    try {
      final signedUrl = await Supabase.instance.client.storage
          .from(_kDocumentsBucket)
          .createSignedUrl(filePath, _kSignedUrlExpirySeconds);
      final launched = await launchUrl(
        Uri.parse(signedUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't open the document.")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to open document: $e')));
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title =
        (row['title'] as String?) ??
        (row['file_name'] as String? ?? 'Document');
    final type = (row['document_type'] as String?) ?? '';
    final status = (row['status'] as String?) ?? 'ISSUED';
    final created = row['created_at'] as String?;
    final hasFile = documentHasFile(row);
    final id = (row['id'] as String?)?.trim();
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: (id == null || id.isEmpty)
            ? null
            : () => context.go('/documents/view/$id'),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(Icons.description_outlined, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        type,
                        if (created != null)
                          'Added ${created.substring(0, 10)}',
                      ].where((s) => s.isNotEmpty).join(' • '),
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              StatusChip(
                label: documentStatusLabel(status),
                tone: documentStatusTone(status),
              ),
              if (hasFile) ...[
                const SizedBox(width: 8),
                _opening
                    ? const Padding(
                        padding: EdgeInsets.all(8),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        onPressed: _openDocument,
                        icon: const Icon(Icons.open_in_new, size: 18),
                        tooltip: 'View / download',
                        visualDensity: VisualDensity.compact,
                      ),
              ],
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
