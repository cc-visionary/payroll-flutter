import 'package:pdf/widgets.dart' as pw;
import '../../../core/pdf/pdf_theme.dart';
import 'block.dart';

/// Bold "N. Title" heading. Used by NTE charges and any future template
/// that has numbered sections.
class SectionHeadingBlock extends Block {
  final int number;
  final String title;
  const SectionHeadingBlock({required this.number, required this.title});

  String get formatted => '$number. $title';

  @override
  pw.Widget toPdf(PdfTheme theme) => pw.Text(
        formatted,
        style: pw.TextStyle(
          fontSize: theme.headingSize,
          fontWeight: pw.FontWeight.bold,
          color: theme.textColor,
        ),
      );
}
