import 'package:pdf/widgets.dart' as pw;
import '../../../core/pdf/pdf_theme.dart';
import 'block.dart';

/// Letterhead pattern: bold company name on the first line, a single
/// concatenated address line below in regular weight.
class CompanyHeaderBlock extends Block {
  final String name;
  final String? address;
  const CompanyHeaderBlock({required this.name, this.address});

  @override
  pw.Widget toPdf(PdfTheme theme) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          name,
          style: pw.TextStyle(
            fontSize: theme.bodySize + 1,
            fontWeight: pw.FontWeight.bold,
            color: theme.textColor,
          ),
        ),
        if (address != null && address!.isNotEmpty)
          pw.Text(
            address!,
            style: pw.TextStyle(
              fontSize: theme.bodySize,
              color: theme.textColor,
            ),
          ),
      ],
    );
  }
}
