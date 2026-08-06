import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/pdf/pdf_preview_scaffold.dart';
import '../../core/pdf/pdf_theme.dart';
import '../documents/brand_logo.dart';
import '../documents/pdf/pdf_builder.dart';
import '../documents/providers.dart';
import 'role_card_pdf.dart';

/// Ephemeral, on-the-fly PDF preview of the current role scorecard. Nothing is
/// persisted — the PDF is rebuilt from the live card each time this opens. The
/// role-card edit flow invalidates roleScorecardByIdProvider on save, so a
/// re-opened preview reflects the latest saved card.
class RoleCardPdfScreen extends ConsumerWidget {
  final String cardId;
  const RoleCardPdfScreen({super.key, required this.cardId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardAsync = ref.watch(roleScorecardByIdProvider(cardId));
    return Scaffold(
      appBar: AppBar(title: const Text('Role reference')),
      body: cardAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _message(context, 'Could not load the role card.\n$e'),
        data: (card) {
          if (card == null) {
            return _message(context, 'Role card not found.');
          }
          final slug = card.jobTitle
              .toLowerCase()
              .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
              .replaceAll(RegExp(r'(^-|-$)'), '');
          return PdfPreviewScaffold(
            filename: slug.isEmpty ? 'role-card.pdf' : '$slug-role-card.pdf',
            buildPdf: (format) async {
              final theme = await PdfTheme.defaults();
              final entityId = card.hiringEntityId;
              final entity = (entityId == null || entityId.isEmpty)
                  ? null
                  : await ref.read(hiringEntityByIdProvider(entityId).future);
              final logo = await loadCompanyLogoBytes(entity);
              final address = [
                entity?.addressLine1,
                entity?.addressLine2,
              ].whereType<String>().where((s) => s.isNotEmpty).join(', ');
              return buildDocumentPdf(
                blocks: roleCardBlocks(
                  card,
                  logoBytes: logo,
                  companyName: entity?.name ?? '',
                  companyAddress: address,
                ),
                theme: theme,
              );
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
