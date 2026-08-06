import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart' hide Block;

import '../../../core/pdf/pdf_preview_scaffold.dart';
import '../../../core/pdf/pdf_theme.dart';
import '../brand_logo.dart';
import '../pdf/pdf_builder.dart';
import '../providers.dart';
import 'saved_document_renderer.dart';

/// Views a previously-generated document by re-rendering its PDF on the fly from
/// the persisted `generation_options` (no PDF is ever stored). Reached via
/// `/documents/view/:id` from the documents hub and the employee Documents tab.
class DocumentViewScreen extends ConsumerWidget {
  final String documentId;

  /// Injected in tests; production resolves the themed defaults.
  final PdfTheme? pdfThemeOverride;

  const DocumentViewScreen({
    super.key,
    required this.documentId,
    this.pdfThemeOverride,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(documentByIdProvider(documentId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Document'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back to documents',
          onPressed: () => context.go('/documents'),
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _message(context, "Couldn't load the document.\n$e"),
        data: (row) {
          if (row == null) {
            return _message(context, 'Document not found.');
          }
          final options =
              (row['generation_options'] as Map?)?.cast<String, dynamic>() ??
              const <String, dynamic>{};
          if (!canRenderSavedDocument(options)) {
            final type = (row['document_type'] as String?) ?? 'this';
            return _message(
              context,
              'A preview from saved settings isn\'t available for '
              '$type documents yet.',
            );
          }
          final rawName = (row['file_name'] as String?)?.trim();
          final filename = (rawName == null || rawName.isEmpty)
              ? 'document.pdf'
              : rawName;
          return PdfPreviewScaffold(
            filename: filename,
            buildPdf: (format) async {
              final theme = pdfThemeOverride ?? await PdfTheme.defaults();
              final companyId = options['companyId'] as String?;
              final entity = (companyId == null || companyId.isEmpty)
                  ? null
                  : await ref.read(hiringEntityByIdProvider(companyId).future);
              final logo = await loadCompanyLogoBytes(entity);
              final blocks = blocksForSavedDocument(options, logoBytes: logo);
              return buildDocumentPdf(blocks: blocks, theme: theme);
            },
          );
        },
      ),
    );
  }

  Widget _message(BuildContext context, String text) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ),
  );
}
