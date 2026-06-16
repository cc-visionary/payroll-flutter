import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/profile_provider.dart';
import '../employees/profile/widgets/info_card.dart';
import 'providers.dart';
import 'templates/template_picker_field.dart';

class DocumentsScreen extends ConsumerStatefulWidget {
  /// Optional pre-filter — when set, the registry is scoped to a single
  /// employee and a clearable filter chip is shown.
  final String? employeeId;
  const DocumentsScreen({super.key, this.employeeId});

  @override
  ConsumerState<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends ConsumerState<DocumentsScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider).asData?.value;
    final canManage = profile?.canManageEmployees ?? false;
    if (!canManage) {
      return const Center(
        child: Text('You do not have permission to view documents.'),
      );
    }

    final async = ref.watch(allDocumentsProvider);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Generate a Document',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.layers_outlined, size: 18),
              label: const Text('Bulk Generate'),
              onPressed: () => context.go('/documents/bulk'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Pick a template to start. Inputs autofill from employee + payroll data; '
          'the preview shows exactly what gets generated.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Template',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        TemplatePickerField(
          selectedId: null,
          hintText: 'Select a document template…',
          onSelected: (id) => context.go('/documents/generate/$id'),
        ),
        const SizedBox(height: 40),
        Text(
          'Documents on File',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          'Every recorded document across the company. Search by employee or title.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        async.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'Error: $e',
              style: const TextStyle(color: Colors.red),
            ),
          ),
          data: (entries) => _registry(context, entries),
        ),
      ],
    );
  }

  Widget _registry(BuildContext context, List<DocumentRegistryEntry> entries) {
    // Resolve the pre-filter employee name (from the data set itself).
    String? filterName;
    if (widget.employeeId != null) {
      for (final e in entries) {
        if (e.employeeId == widget.employeeId) {
          filterName = e.employeeName;
          break;
        }
      }
      filterName ??= 'this employee';
    }

    var filtered = entries;
    if (widget.employeeId != null) {
      filtered = filtered
          .where((e) => e.employeeId == widget.employeeId)
          .toList();
    }
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      filtered = filtered
          .where((e) =>
              e.employeeName.toLowerCase().contains(q) ||
              e.title.toLowerCase().contains(q))
          .toList();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 20),
                  hintText: 'Search by employee or document title…',
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
          ],
        ),
        if (widget.employeeId != null) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: InputChip(
              label: Text('Filtered: $filterName'),
              onDeleted: () => context.go('/documents'),
            ),
          ),
        ],
        const SizedBox(height: 16),
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              q.isNotEmpty
                  ? 'No documents match your search'
                  : 'No documents on file',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          for (final entry in filtered)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _RegistryRow(entry: entry),
            ),
      ],
    );
  }
}

class _RegistryRow extends StatelessWidget {
  final DocumentRegistryEntry entry;
  const _RegistryRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final created = entry.createdAt;
    final meta = [
      if (entry.documentType.isNotEmpty) entry.documentType,
      if (entry.employeeName.isNotEmpty) entry.employeeName,
      if (created != null)
        'Added ${created.toIso8601String().substring(0, 10)}',
    ].join(' • ');

    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => context.go('/documents/view/${entry.id}'),
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
                      entry.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              StatusChip(
                label: entry.status,
                tone: toneForStatus(entry.status),
              ),
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

