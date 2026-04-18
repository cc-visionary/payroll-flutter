import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/models/employee.dart';
import '../../../auth/profile_provider.dart';
import '../providers.dart';
import '../widgets/info_card.dart';

class DocumentsTab extends ConsumerStatefulWidget {
  final Employee employee;
  const DocumentsTab({super.key, required this.employee});

  @override
  ConsumerState<DocumentsTab> createState() => _DocumentsTabState();
}

class _DocumentsTabState extends ConsumerState<DocumentsTab> {
  String? _selectedType;

  static const _docTypes = [
    'Offer Letter',
    'Employment Contract',
    'Certificate of Employment',
    'Payslip Bundle',
    'BIR 2316',
    'Separation Letter',
  ];

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
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedType,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Select document type...',
                      isDense: true,
                    ),
                    items: [
                      for (final type in _docTypes)
                        DropdownMenuItem(value: type, child: Text(type)),
                    ],
                    onChanged: (v) => setState(() => _selectedType = v),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _selectedType == null
                      ? null
                      : () => ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Generate "$_selectedType" — coming soon.',
                              ),
                            ),
                          ),
                  child: const Text('Generate'),
                ),
              ],
            ),
          ),
        if (canManage) const SizedBox(height: 16),
        _Card(
          title: 'Documents',
          child: async.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Error: $e',
                style: const TextStyle(color: Colors.red)),
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
                          child: _DocRow(row: r),
                        ),
                    ],
                  ),
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
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Divider(height: 1, color: Theme.of(context).dividerColor),
          Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _DocRow extends StatelessWidget {
  final Map<String, dynamic> row;
  const _DocRow({required this.row});

  @override
  Widget build(BuildContext context) {
    final title = (row['title'] as String?) ?? (row['file_name'] as String? ?? 'Document');
    final type = (row['document_type'] as String?) ?? '';
    final status = (row['status'] as String?) ?? 'ISSUED';
    final created = row['created_at'] as String?;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
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
                  [type, if (created != null) 'Added ${created.substring(0, 10)}']
                      .where((s) => s.isNotEmpty)
                      .join(' • '),
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          StatusChip(label: status, tone: toneForStatus(status)),
        ],
      ),
    );
  }
}
