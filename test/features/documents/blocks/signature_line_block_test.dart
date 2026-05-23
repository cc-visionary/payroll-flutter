import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/core/pdf/pdf_theme.dart';
import 'package:payroll_flutter/features/documents/blocks/signature_line_block.dart';

void main() {
  test('stores signatories + flags', () {
    const b = SignatureLineBlock(
      [SignatoryLine(name: 'A', role: 'CEO'), SignatoryLine()],
      row: true,
    );
    expect(b.signatories.length, 2);
    expect(b.row, true);
  });

  test('renders stacked and row without throwing', () {
    final theme = PdfTheme.testStub();
    expect(() => const SignatureLineBlock([SignatoryLine(name: 'X', role: 'Y')]).toPdf(theme), returnsNormally);
    expect(() => const SignatureLineBlock([SignatoryLine(), SignatoryLine()], row: true).toPdf(theme), returnsNormally);
  });
}
