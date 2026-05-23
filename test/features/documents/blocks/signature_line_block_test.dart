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

  test('renders header + showDate without throwing', () {
    final theme = PdfTheme.testStub();
    const b = SignatureLineBlock(
      [
        SignatoryLine(header: 'X', name: 'A', role: 'CEO'),
        SignatoryLine(header: 'Y', name: 'B', role: 'Recipient'),
      ],
      row: true,
      showDate: true,
    );
    expect(b.showDate, true);
    expect(b.signatories.first.header, 'X');
    expect(() => b.toPdf(theme), returnsNormally);
  });
}
