import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/core/pdf/pdf_theme.dart';
import 'package:payroll_flutter/features/documents/blocks/signature_block.dart';
import 'package:payroll_flutter/features/documents/blocks/multi_signature_block.dart';
import 'package:payroll_flutter/features/documents/blocks/receipt_block.dart';
import 'package:payroll_flutter/features/documents/blocks/refusal_clause_block.dart';

final _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);

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
      SignatoryParty(
        name: 'Donald',
        role: 'Employee',
        date: DateTime(2026, 5, 5),
      ),
      SignatoryParty(name: 'Clinton', role: 'CEO', date: DateTime(2026, 5, 5)),
    ]);
    expect(b.signatories.length, 2);
  });

  test(
    'MultiSignatureBlock accepts null date and renders without throwing',
    () {
      final theme = PdfTheme.testStub();
      const party = SignatoryParty(name: 'X', role: 'Y', date: null);
      expect(party.date, isNull);
      expect(
        () => const MultiSignatureBlock([party]).toPdf(theme),
        returnsNormally,
      );
    },
  );

  test('MultiSignatureBlock renders a mixed signed/unsigned pair', () {
    // A one-sided signature used to shift that party's sign line 40pt down
    // relative to the unsigned one; the strip is now reserved for every party.
    final theme = PdfTheme.testStub();
    final signed = MultiSignatureBlock([
      SignatoryParty(
        name: 'Brixter',
        role: 'HR Manager',
        signatureImage: _onePixelPng,
      ),
      const SignatoryParty(name: 'Christopher', role: 'Employee (Conforme)'),
    ]);
    expect(() => signed.toPdf(theme), returnsNormally);
    expect(signed.signatories.first.signatureImage, isNotNull);
    expect(signed.signatories.last.signatureImage, isNull);
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

  test('all blocks render without throwing', () {
    final theme = PdfTheme.testStub();
    expect(
      () => SignatureBlock(
        name: 'X',
        role: 'Y',
        date: DateTime(2026, 1, 1),
      ).toPdf(theme),
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

  test('SignatureBlock accepts null date', () {
    const b = SignatureBlock(name: 'Donald', role: 'Employee', date: null);
    expect(b.date, isNull);
    expect(b.name, 'Donald');
  });

  test('SignatureBlock renders with null date without throwing', () {
    final theme = PdfTheme.testStub();
    expect(
      () => const SignatureBlock(name: 'X', role: '', date: null).toPdf(theme),
      returnsNormally,
    );
  });
}
