// lib/features/documents/blocks/block.dart
import 'package:pdf/widgets.dart' as pw;

import '../../../core/pdf/pdf_theme.dart';

/// A single building unit of a generated document. Each concrete Block
/// has exactly one render path: [toPdf]. The on-screen preview displays
/// the actual PDF bytes (via `printing.PdfPreview`), so there is no
/// separate Flutter widget render — preview and final file are
/// byte-identical.
abstract class Block {
  const Block();
  pw.Widget toPdf(PdfTheme theme);
}
