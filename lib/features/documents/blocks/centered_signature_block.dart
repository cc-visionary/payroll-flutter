import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../core/pdf/pdf_theme.dart';
import 'block.dart';

/// A centered empty signature line with a caption below (e.g. the
/// notarized-quitclaim "Name and signature of Employee").
class CenteredSignatureBlock extends Block {
  final String caption;
  final double lineWidth;
  const CenteredSignatureBlock(this.caption, {this.lineWidth = 320});

  @override
  pw.Widget toPdf(PdfTheme theme) {
    return pw.Center(
      child: pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Container(
            width: lineWidth,
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(color: PdfColors.black, width: 0.7),
              ),
            ),
            child: pw.SizedBox(height: 28),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            caption,
            style: pw.TextStyle(
              fontSize: theme.bodySize,
              color: theme.textColor,
            ),
          ),
        ],
      ),
    );
  }
}
