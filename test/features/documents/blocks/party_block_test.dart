import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/core/pdf/pdf_theme.dart';
import 'package:payroll_flutter/features/documents/blocks/emphasis_paragraph_block.dart';
import 'package:payroll_flutter/features/documents/blocks/party_block.dart';

void main() {
  test('PartyBlock stores spans + indent and renders', () {
    final theme = PdfTheme.testStub();
    const block = PartyBlock(spans: [
      EmphasisSpan('Luxium Trading Co.', bold: true),
      EmphasisSpan(', with address at '),
      EmphasisSpan('908 Alvarado St', italic: true),
    ]);
    expect(block.spans.length, 3);
    expect(block.leftIndent, 110);
    expect(() => block.toPdf(theme), returnsNormally);
  });
}
