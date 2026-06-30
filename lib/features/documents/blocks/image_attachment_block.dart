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
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Center(
          // Explicit width+height with BoxFit.contain letterboxes any image
          // size into the page, so a high-resolution photo can never overflow.
          child: pw.Image(
            pw.MemoryImage(bytes),
            width: maxWidth,
            height: 480,
            fit: pw.BoxFit.contain,
          ),
        ),
        if (hasCaption) pw.SizedBox(height: 6),
        if (hasCaption)
          pw.Text(
            caption!.trim(),
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              fontSize: theme.bodySize - 1,
              color: PdfColors.grey700,
              fontStyle: pw.FontStyle.italic,
            ),
          ),
      ],
    );
  }
}
