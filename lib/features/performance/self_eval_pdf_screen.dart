import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/pdf/pdf_filename.dart';
import '../../core/pdf/pdf_preview_scaffold.dart';
import '../../core/pdf/pdf_theme.dart';
import '../../data/repositories/lark_self_eval_repository.dart';
import '../documents/pdf/pdf_builder.dart';
import 'self_eval_pdf.dart';

/// Ephemeral, on-the-fly PDF preview of a single self-evaluation response.
/// Nothing is persisted — the PDF is rebuilt from the live row each time this
/// opens. Reachable via `/self-evals/:id/pdf`, whose `/pdf` suffix keeps it
/// outside the HR management-UI redirect; the repository read is still governed
/// by RLS on `lark_self_eval_responses`.
class SelfEvalPdfScreen extends ConsumerWidget {
  final String id;
  const SelfEvalPdfScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(selfEvalDetailByIdProvider(id));
    return Scaffold(
      appBar: AppBar(title: const Text('Self-evaluation')),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            _message(context, 'Could not load the self-evaluation.\n$e'),
        data: (detail) {
          if (detail == null) {
            return _message(context, 'Self-evaluation not found.');
          }
          return PdfPreviewScaffold(
            filename: filenameForSelfEval(
              employeeName: detail.fullName,
              reviewTypeLabel: reviewTypeLabel(detail.response.reviewType),
              submittedAt: detail.response.submittedAt,
            ),
            buildPdf: (format) async {
              final theme = await PdfTheme.defaults();
              return buildDocumentPdf(
                blocks: selfEvalBlocks(detail),
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
