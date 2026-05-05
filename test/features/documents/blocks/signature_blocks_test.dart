import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/core/pdf/pdf_theme.dart';
import 'package:payroll_flutter/features/documents/blocks/signature_block.dart';
import 'package:payroll_flutter/features/documents/blocks/multi_signature_block.dart';
import 'package:payroll_flutter/features/documents/blocks/receipt_block.dart';
import 'package:payroll_flutter/features/documents/blocks/refusal_clause_block.dart';

void main() {
  test('SignatureBlock stores fields', () {
    final b = SignatureBlock(
      name: 'Donald',
      role: 'CTO — Luxium',
      date: DateTime(2026, 5, 5),
    );
    expect(b.name, 'Donald');
  });

  test('MultiSignatureBlock holds multiple signatories', () {
    final b = MultiSignatureBlock([
      SignatoryParty(name: 'Donald', role: 'Employee', date: DateTime(2026, 5, 5)),
      SignatoryParty(name: 'Clinton', role: 'CEO', date: DateTime(2026, 5, 5)),
    ]);
    expect(b.signatories.length, 2);
  });

  test('ReceiptBlock holds field list', () {
    const b = ReceiptBlock([
      ReceiptField(label: 'Received by', caption: '(Name & Signature)'),
      ReceiptField(label: 'Date & Time Received'),
    ]);
    expect(b.fields.length, 2);
  });

  test('RefusalClauseBlock stores text', () {
    const b = RefusalClauseBlock(
      'If the employee refuses to sign, the server shall note...',
    );
    expect(b.text.startsWith('If the employee'), true);
  });

  test('all blocks render without throwing', () async {
    final theme = await PdfTheme.defaults();
    expect(
      () => SignatureBlock(name: 'X', role: 'Y', date: DateTime(2026, 1, 1)).toPdf(theme),
      returnsNormally,
    );
    expect(
      () => MultiSignatureBlock([
        SignatoryParty(name: 'A', role: 'B', date: DateTime(2026, 1, 1)),
      ]).toPdf(theme),
      returnsNormally,
    );
    expect(
      () => const ReceiptBlock([ReceiptField(label: 'X')]).toPdf(theme),
      returnsNormally,
    );
    expect(
      () => const RefusalClauseBlock('test').toPdf(theme),
      returnsNormally,
    );
  });
}
