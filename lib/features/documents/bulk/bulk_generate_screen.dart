import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/status_colors.dart' as status;
import '../../../core/pdf/pdf_theme.dart';
import '../../../data/models/employee.dart';
import '../../../data/repositories/audit_repository.dart';
import '../../../data/repositories/employee_repository.dart';
import '../../auth/profile_provider.dart';
import '../templates/document_template.dart';
import '../templates/liability_waiver_template.dart';
import '../templates/template_picker_field.dart';
import '../templates/template_registry.dart';
import 'bulk_generate.dart';

/// Bulk-generate screen: pick one template + many employees, generate a
/// combined PDF and a ZIP of per-employee PDFs. Route `/documents/bulk`.
class BulkGenerateScreen extends ConsumerStatefulWidget {
  const BulkGenerateScreen({super.key});

  @override
  ConsumerState<BulkGenerateScreen> createState() => _BulkGenerateScreenState();
}

class _BulkGenerateScreenState extends ConsumerState<BulkGenerateScreen> {
  late DocumentTemplate _template;
  final Set<String> _selected = <String>{};
  String _query = '';

  // Shared fields (Liability Waiver only).
  DateTime? _outingDate;
  final TextEditingController _outingLocation = TextEditingController();

  bool _generating = false;
  BulkGenerateResult? _result;

  List<DocumentTemplate> get _bulkTemplates =>
      kTemplates.where((t) => t.supportsBulk).toList();

  @override
  void initState() {
    super.initState();
    _template = _bulkTemplates.first;
  }

  @override
  void dispose() {
    _outingLocation.dispose();
    super.dispose();
  }

  bool get _isWaiver => _template is LiabilityWaiverTemplate;

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider).asData?.value;
    final canManage = profile?.canManageEmployees ?? false;

    final scaffold = Scaffold(
      appBar: AppBar(
        title: const Text('Bulk Generate'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back to documents',
          onPressed: () => context.go('/documents'),
        ),
      ),
      body: canManage
          ? _body(context)
          : const Center(
              child: Text('You do not have permission to view documents.'),
            ),
    );
    return scaffold;
  }

  Widget _body(BuildContext context) {
    // Include archived — COE typically targets separated staff; the gate
    // skips ineligible employees at generate time.
    final async = ref.watch(
      employeeListProvider(const EmployeeListQuery(includeArchived: true)),
    );

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Bulk Generate',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          'Pick one template and many employees. Each document autofills from '
          'employee + company data. Employees whose data fails validation '
          '(or whose template gate blocks them) are skipped and reported.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),

        // 1. Template
        _sectionLabel(context, 'Template'),
        const SizedBox(height: 8),
        _templatePicker(context),
        const SizedBox(height: 24),

        // 2. Shared fields (Liability Waiver only)
        if (_isWaiver) ...[
          _sectionLabel(context, 'Shared fields'),
          const SizedBox(height: 8),
          _sharedFields(context),
          const SizedBox(height: 24),
        ],

        // 3. Employees
        _sectionLabel(context, 'Employees'),
        const SizedBox(height: 8),
        async.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text('Error: $e',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
          data: (employees) => _employeePicker(context, employees),
        ),
        const SizedBox(height: 24),

        // 4. Generate
        Row(
          children: [
            FilledButton.icon(
              onPressed: (_selected.isEmpty || _generating)
                  ? null
                  : () => _generate(),
              icon: _generating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.bolt),
              label: Text(
                _generating
                    ? 'Generating…'
                    : 'Generate (${_selected.length})',
              ),
            ),
            if (_result != null) ...[
              const SizedBox(width: 12),
              TextButton(
                onPressed: _generating ? null : _reset,
                child: const Text('New batch'),
              ),
            ],
          ],
        ),

        // Results
        if (_result != null) ...[
          const SizedBox(height: 24),
          const Divider(height: 1),
          const SizedBox(height: 24),
          _results(context, _result!),
        ],
      ],
    );
  }

  Widget _sectionLabel(BuildContext context, String text) => Text(
        text,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      );

  Widget _templatePicker(BuildContext context) {
    return TemplatePickerField(
      selectedId: _template.id,
      enabled: !_generating,
      filter: (t) => t.supportsBulk,
      onSelected: (id) {
        final next = findTemplateById(id);
        if (next != null) setState(() => _template = next);
      },
    );
  }

  Widget _sharedFields(BuildContext context) {
    final dateLabel = _outingDate == null
        ? 'Pick a date'
        : _outingDate!.toIso8601String().substring(0, 10);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.event, size: 18),
              label: Text('Outing date: $dateLabel'),
              onPressed: () async {
                final now = DateTime.now();
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _outingDate ?? now,
                  firstDate: DateTime(now.year - 1),
                  lastDate: DateTime(now.year + 2),
                );
                if (picked != null) setState(() => _outingDate = picked);
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _outingLocation,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
            labelText: 'Outing location',
            hintText: 'e.g. Tagaytay Highlands',
          ),
        ),
      ],
    );
  }

  Widget _employeePicker(BuildContext context, List<Employee> employees) {
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? employees
        : employees
            .where((e) =>
                e.fullName.toLowerCase().contains(q) ||
                e.employeeNumber.toLowerCase().contains(q))
            .toList();
    final filteredIds = filtered.map((e) => e.id).toSet();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
            prefixIcon: Icon(Icons.search, size: 20),
            hintText: 'Search by name or employee number…',
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              '${_selected.length} selected',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => setState(() => _selected.addAll(filteredIds)),
              child: const Text('Select all (filtered)'),
            ),
            TextButton(
              onPressed: _selected.isEmpty
                  ? null
                  : () => setState(() => _selected.clear()),
              child: const Text('Clear'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(6),
          ),
          child: SizedBox(
            height: 320,
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      'No employees match your search',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, i) {
                      final e = filtered[i];
                      final subtitleParts = [
                        if ((e.jobTitle ?? '').isNotEmpty) e.jobTitle!,
                        if (e.employeeNumber.isNotEmpty) e.employeeNumber,
                      ];
                      return CheckboxListTile(
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _selected.contains(e.id),
                        title: Text(e.fullName),
                        subtitle: subtitleParts.isEmpty
                            ? null
                            : Text(subtitleParts.join(' • ')),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _selected.add(e.id);
                          } else {
                            _selected.remove(e.id);
                          }
                        }),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Future<void> _generate() async {
    setState(() {
      _generating = true;
      _result = null;
    });
    try {
      final theme = await PdfTheme.defaults();
      final shared = _isWaiver
          ? <String, Object?>{
              'outingDate': _outingDate,
              'outingLocation': _outingLocation.text.trim(),
            }
          : const <String, Object?>{};
      final result = await bulkGenerate(
        template: _template,
        employeeIds: _selected.toList(),
        ref: ref,
        theme: theme,
        shared: shared,
      );
      if (!mounted) return;

      // Audit: one row for the whole bulk run.
      ref.read(auditRepositoryProvider).logExport(
        description:
            'Bulk ${_template.name} generated: ${result.generatedCount} '
            'document(s), ${result.skipped.length} skipped',
        entityType: 'document_template_bulk',
        metadata: {
          'template_id': _template.id,
          'generated_count': result.generatedCount,
          'skipped_count': result.skipped.length,
          'selected_count': _selected.length,
        },
      );

      setState(() {
        _result = result;
        _generating = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _generating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Bulk generate failed: $e')),
      );
    }
  }

  void _reset() {
    setState(() {
      _result = null;
      _selected.clear();
    });
  }

  Widget _results(BuildContext context, BulkGenerateResult result) {
    final hasFiles = result.generatedCount > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionLabel(context, 'Results'),
        const SizedBox(height: 8),
        Text(
          '${result.generatedCount} generated'
          '${result.skipped.isNotEmpty ? ' • ${result.skipped.length} skipped' : ''}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        if (result.skipped.isNotEmpty) ...[
          const SizedBox(height: 12),
          _skippedPanel(context, result.skipped),
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: hasFiles ? () => _downloadZip(result) : null,
              icon: const Icon(Icons.folder_zip_outlined),
              label: const Text('Download ZIP'),
            ),
            OutlinedButton.icon(
              onPressed: hasFiles ? () => _downloadCombined(result) : null,
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Download Combined PDF'),
            ),
            OutlinedButton.icon(
              onPressed: hasFiles ? () => _printCombined(result) : null,
              icon: const Icon(Icons.print_outlined),
              label: const Text('Print Combined'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _skippedPanel(BuildContext context, List<BulkSkip> skipped) {
    final palette = status.StatusPalette.of(context, status.StatusTone.warning);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Skipped (${skipped.length})',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: palette.foreground,
            ),
          ),
          const SizedBox(height: 6),
          for (final s in skipped)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                '${s.employeeName}: ${s.reason}',
                style: TextStyle(fontSize: 12, color: palette.foreground),
              ),
            ),
        ],
      ),
    );
  }

  String _prefix() {
    final first = _result?.files.isNotEmpty == true
        ? _result!.files.first.filename
        : null;
    if (first != null) {
      final us = first.indexOf('_');
      if (us > 0) return first.substring(0, us);
    }
    return _template.id;
  }

  String _ymd() {
    final d = DateTime.now();
    return '${d.year.toString().padLeft(4, '0')}'
        '${d.month.toString().padLeft(2, '0')}'
        '${d.day.toString().padLeft(2, '0')}';
  }

  bool get _useMobileShareSheet {
    if (kIsWeb) return false;
    try {
      return Platform.isIOS || Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }

  Future<void> _downloadZip(BulkGenerateResult result) async {
    final archive = Archive();
    final used = <String>{};
    for (final f in result.files) {
      final name = _uniqueName(f.filename, used);
      archive.addFile(ArchiveFile(name, f.bytes.length, f.bytes));
    }
    final encoded = ZipEncoder().encode(archive);
    if (encoded == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to build ZIP archive.')),
      );
      return;
    }
    final zipBytes = Uint8List.fromList(encoded);
    final zipName = '${_prefix()}_bulk_${_ymd()}.zip';

    try {
      if (_useMobileShareSheet) {
        final dir = await getTemporaryDirectory();
        final path = '${dir.path}${Platform.pathSeparator}$zipName';
        await File(path).writeAsBytes(zipBytes);
        await Share.shareXFiles(
          [XFile(path, mimeType: 'application/zip')],
          subject: zipName,
        );
        return;
      }
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save bulk documents ZIP',
        fileName: zipName,
        type: FileType.custom,
        allowedExtensions: const ['zip'],
      );
      if (savePath == null) return;
      final target =
          savePath.toLowerCase().endsWith('.zip') ? savePath : '$savePath.zip';
      await File(target).writeAsBytes(zipBytes);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved $zipName')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save ZIP: $e')),
      );
    }
  }

  Future<void> _downloadCombined(BulkGenerateResult result) async {
    final name = '${_prefix()}_bulk_${_ymd()}.pdf';
    try {
      await Printing.sharePdf(bytes: result.combinedPdf, filename: name);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to share combined PDF: $e')),
      );
    }
  }

  Future<void> _printCombined(BulkGenerateResult result) async {
    await Printing.layoutPdf(onLayout: (_) async => result.combinedPdf);
  }

  /// Disambiguate ZIP entry names if two files collide (e.g. duplicate
  /// employee numbers). Appends ` (2)`, ` (3)`, … before the extension.
  String _uniqueName(String desired, Set<String> used) {
    if (used.add(desired)) return desired;
    final dot = desired.lastIndexOf('.');
    final stem = dot >= 0 ? desired.substring(0, dot) : desired;
    final ext = dot >= 0 ? desired.substring(dot) : '';
    for (var i = 2;; i++) {
      final candidate = '$stem ($i)$ext';
      if (used.add(candidate)) return candidate;
    }
  }
}
