import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:payroll_flutter/core/pdf/pdf_theme.dart';
import 'package:payroll_flutter/features/documents/blocks/spacer_block.dart';

void main() {
  test('SpacerBlock toPdf returns SizedBox with the requested height', () async {
    final theme = await PdfTheme.defaults();
    final block = const SpacerBlock(24);
    final widget = block.toPdf(theme);
    expect(widget, isA<pw.SizedBox>());
    final sized = widget as pw.SizedBox;
    expect(sized.height, 24);
  });
}
