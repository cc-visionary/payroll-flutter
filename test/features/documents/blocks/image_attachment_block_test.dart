import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/core/pdf/pdf_theme.dart';
import 'package:payroll_flutter/features/documents/blocks/image_attachment_block.dart';

void main() {
  // Minimal 1×1 white RGB PNG — pw.MemoryImage decodes format eagerly so
  // the bytes must be valid image data. [1,2,3,4] from the brief caused
  // RangeError inside im.findDecoderForData before format detection finished.
  final bytes = Uint8List.fromList([
    0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, // PNG signature
    0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52, // IHDR length + type
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, // width=1, height=1
    0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xde, // 8-bit RGB + CRC
    0x00, 0x00, 0x00, 0x0c, 0x49, 0x44, 0x41, 0x54, // IDAT length + type
    0x78, 0x9c, 0x63, 0xf8, 0xff, 0xff, 0x3f, 0x00, // compressed pixel data
    0x05, 0xfe, 0x02, 0xfe, 0x0d, 0xef, 0x46, 0xb8, // end of compressed data
    0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, // IEND length + type
    0xae, 0x42, 0x60, 0x82, //                         IEND CRC
  ]);

  test('stores bytes and caption', () {
    final block = ImageAttachmentBlock(bytes, caption: 'CCTV still');
    expect(block.bytes, bytes);
    expect(block.caption, 'CCTV still');
  });

  test('caption defaults to null', () {
    final block = ImageAttachmentBlock(bytes);
    expect(block.caption, isNull);
  });

  test('toPdf renders without throwing (with and without caption)', () {
    final theme = PdfTheme.testStub();
    expect(() => ImageAttachmentBlock(bytes, caption: 'cap').toPdf(theme),
        returnsNormally);
    expect(() => ImageAttachmentBlock(bytes).toPdf(theme), returnsNormally);
    expect(() => ImageAttachmentBlock(bytes, caption: '   ').toPdf(theme),
        returnsNormally);
  });
}
