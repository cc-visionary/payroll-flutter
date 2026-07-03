import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/pdf/pdf_theme.dart';
import 'block.dart';

/// Renders an optional, user-supplied image attachment (e.g. photo evidence)
/// for a memo, letterboxed to fit the page content area, with an optional
/// caption beneath it.
///
/// The bytes are NEVER persisted — like the brand logo, this is a
/// generation-time-only binary carried on the template inputs. See the
/// memo-image-attachment design doc.
class ImageAttachmentBlock extends Block {
  final Uint8List bytes;

  /// Optional caption shown under the image. Null or whitespace renders no
  /// caption.
  final String? caption;

  const ImageAttachmentBlock(this.bytes, {this.caption});

  @override
  pw.Widget toPdf(PdfTheme theme) {
    final maxWidth =
        theme.pageFormat.width - theme.pageMargin.left - theme.pageMargin.right;
    final hasCaption = caption != null && caption!.trim().isNotEmpty;
    // A 0.5pt hairline border + 8pt inner padding frame the image as a formal
    // exhibit. Subtract the frame from the image width so the bordered box
    // never exceeds the page content width.
    const framePadding = 8.0;
    const frameBorder = 0.5;
    final imageWidth = maxWidth - 2 * (framePadding + frameBorder);
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Container(
          padding: const pw.EdgeInsets.all(framePadding),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey400, width: frameBorder),
          ),
          child: pw.Center(
            // Explicit width+height with BoxFit.contain letterboxes any image
            // size into the frame, so a high-resolution photo can never overflow.
            child: pw.Image(
              pw.MemoryImage(bytes),
              width: imageWidth,
              height: 480,
              fit: pw.BoxFit.contain,
            ),
          ),
        ),
        if (hasCaption) pw.SizedBox(height: 8),
        if (hasCaption)
          pw.Text(
            caption!.trim(),
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              fontSize: theme.bodySize - 1,
              color: PdfColors.grey800,
            ),
          ),
      ],
    );
  }
}
