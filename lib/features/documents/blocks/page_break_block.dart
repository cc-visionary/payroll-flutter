// lib/features/documents/blocks/page_break_block.dart
import 'package:pdf/widgets.dart' as pw;
import '../../../core/pdf/pdf_theme.dart';
import 'block.dart';

/// Forces a page break in `pw.MultiPage`. The pdf_builder treats this
/// block specially — it never calls toPdf; instead it inserts a
/// `pw.NewPage()` widget. The toPdf below is only called if a Block
/// list contains a PageBreakBlock outside that path.
class PageBreakBlock extends Block {
  const PageBreakBlock();
  @override
  pw.Widget toPdf(PdfTheme theme) => pw.SizedBox.shrink();
}
