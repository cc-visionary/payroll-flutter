import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;

import '../../../core/pdf/pdf_theme.dart';
import 'block.dart';

/// Renders a pre-loaded brand logo image, left-aligned, at a fixed height.
/// Bytes must be loaded ahead of time (asset loading is async; blocks
/// render synchronously).
class LogoBlock extends Block {
  final Uint8List bytes;
  final double height;
  const LogoBlock(this.bytes, {this.height = 90});

  @override
  pw.Widget toPdf(PdfTheme theme) {
    return pw.Container(
      alignment: pw.Alignment.centerLeft,
      child: pw.Image(
        pw.MemoryImage(bytes),
        height: height,
        fit: pw.BoxFit.contain,
      ),
    );
  }
}
