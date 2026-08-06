// lib/features/documents/pdf/pdf_builder.dart
import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;

import '../../../core/pdf/page_footer.dart';
import '../../../core/pdf/pdf_theme.dart';
import '../blocks/block.dart';
import '../blocks/page_break_block.dart';

/// Render a list of [Block]s to PDF bytes using the shared [PdfTheme].
///
/// Always uses `pw.MultiPage` (never `pw.Page`) so even single-page
/// documents render with a "Page 1 of 1" footer. A [PageBreakBlock]
/// becomes a `pw.NewPage` widget; all other blocks become their `toPdf`
/// output in document order.
Future<Uint8List> buildDocumentPdf({
  required List<Block> blocks,
  required PdfTheme theme,
}) async {
  final doc = pw.Document(theme: theme.fontTheme);

  doc.addPage(
    pw.MultiPage(
      pageFormat: theme.pageFormat,
      margin: theme.pageMargin,
      theme: theme.fontTheme,
      footer: theme.showPageNumbers
          ? (ctx) => buildStandardPageFooter(
              theme,
              pageNumber: ctx.pageNumber,
              pagesCount: ctx.pagesCount,
            )
          : null,
      build: (ctx) => [
        for (final block in blocks)
          if (block is PageBreakBlock) pw.NewPage() else block.toPdf(theme),
      ],
    ),
  );

  return doc.save();
}

/// Render multiple per-employee block-lists into a single PDF, with each
/// employee getting their own `pw.MultiPage` section. This makes pagination
/// (`Page X of Y`) reset per employee — Mark's doc reads "Page 1 of 1" and
/// Brixter's reads "Page 1 of 1" even though they share one PDF file —
/// instead of running continuously across the whole batch.
Future<Uint8List> buildMultiEmployeePdf({
  required List<List<Block>> employees,
  required PdfTheme theme,
}) async {
  final doc = pw.Document(theme: theme.fontTheme);
  for (final blocks in employees) {
    doc.addPage(
      pw.MultiPage(
        pageFormat: theme.pageFormat,
        margin: theme.pageMargin,
        theme: theme.fontTheme,
        footer: theme.showPageNumbers
            ? (ctx) => buildStandardPageFooter(
                theme,
                pageNumber: ctx.pageNumber,
                pagesCount: ctx.pagesCount,
              )
            : null,
        build: (ctx) => [
          for (final block in blocks)
            if (block is PageBreakBlock) pw.NewPage() else block.toPdf(theme),
        ],
      ),
    );
  }
  return doc.save();
}
