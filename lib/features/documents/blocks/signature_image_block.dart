import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;

import '../../../core/pdf/pdf_theme.dart';
import 'block.dart';

/// A standalone signature image (transparent PNG) for templates that print
/// the signatory as a plain name paragraph instead of a line block (COE).
class SignatureImageBlock extends Block {
  final Uint8List bytes;
  final double height;
  final bool centered;
  const SignatureImageBlock(
    this.bytes, {
    this.height = 40,
    this.centered = true,
  });

  @override
  pw.Widget toPdf(PdfTheme theme) {
    final img = pw.Image(
      pw.MemoryImage(bytes),
      height: height,
      fit: pw.BoxFit.contain,
    );
    return centered ? pw.Center(child: img) : img;
  }
}
