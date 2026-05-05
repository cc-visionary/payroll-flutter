import 'package:flutter_quill/quill_delta.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/pdf/pdf_theme.dart';
import '../pdf/delta_to_pdf.dart';
import 'block.dart';

/// Renders a Quill `Delta` document as PDF widgets. Used by the NTE
/// charge-body field; future templates with free-form rich-text bodies
/// can reuse it directly.
class RichTextBlock extends Block {
  final Delta delta;
  const RichTextBlock(this.delta);

  @override
  pw.Widget toPdf(PdfTheme theme) => deltaToPdf(delta, theme);
}
