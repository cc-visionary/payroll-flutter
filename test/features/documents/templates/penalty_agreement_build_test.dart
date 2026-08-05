import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:payroll_flutter/core/pdf/pdf_theme.dart';
import 'package:payroll_flutter/features/documents/blocks/block.dart';
import 'package:payroll_flutter/features/documents/blocks/heading_block.dart';
import 'package:payroll_flutter/features/documents/blocks/letter_meta_block.dart';
import 'package:payroll_flutter/features/documents/blocks/letterhead_block.dart';
import 'package:payroll_flutter/features/documents/blocks/multi_signature_block.dart';
import 'package:payroll_flutter/features/documents/blocks/table_block.dart';
import 'package:payroll_flutter/features/documents/templates/penalty_agreement_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/penalty_agreement_template.dart';

/// 1x1 fully-transparent PNG.
const _png1x1B64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

PenaltyAgreementInputs _seed() => PenaltyAgreementInputs(
  employeeId: 'e1',
  employeeFullName: 'Jamaica Vidal',
  employeePosition: 'HR Assistant',
  companyId: 'c1',
  companyName: 'Luxium Trading Co.',
  companyAddress: '908 Alvarado St, Manila',
  hrManagerName: 'Brixter Del Mundo',
  penaltyId: 'p1',
  description: 'Damaged a company handheld while on delivery',
  totalAmount: Decimal.parse('3000.00'),
  effectiveDate: DateTime(2026, 8, 1),
  installments: [
    PenaltyInstallmentLine(
      number: 1,
      amount: Decimal.parse('1000.00'),
      isDeducted: true,
    ),
    PenaltyInstallmentLine(number: 2, amount: Decimal.parse('1000.00')),
    PenaltyInstallmentLine(number: 3, amount: Decimal.parse('1000.00')),
  ],
);

Future<List<int>> _render(List<Block> blocks) async {
  final theme = PdfTheme.testStub();
  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(build: (_) => [for (final b in blocks) b.toPdf(theme)]),
  );
  return doc.save();
}

void main() {
  group('PenaltyAgreementTemplate.build', () {
    test('lays out letterhead → meta → schedule → signatures', () {
      final blocks = const PenaltyAgreementTemplate().build(_seed());
      expect(blocks.first, isA<LetterheadBlock>());
      expect(blocks.whereType<LetterMetaBlock>().single.subject,
          'Penalty Repayment Agreement');
      expect(
        blocks.whereType<HeadingBlock>().single.text,
        'Repayment Schedule',
      );
      expect(blocks.whereType<MultiSignatureBlock>(), isNotEmpty);
    });

    test('the table renders one row per installment with its status', () {
      final table = const PenaltyAgreementTemplate()
          .build(_seed())
          .whereType<TableBlock>()
          .single;
      expect(table.headers, ['Installment', 'Amount', 'Status']);
      expect(table.rows.length, 3);
      expect(table.rows[0][0], '1');
      expect(table.rows[0][2], 'Deducted');
      expect(table.rows[1][2], 'Scheduled');
      expect(table.rows[2][1], contains('1,000.00'));
    });

    test('builds and renders with BOTH signatures', () async {
      final i = _seed().copyWith(
        companySignaturePngB64: _png1x1B64,
        employeeSignaturePngB64: _png1x1B64,
      );
      final blocks = const PenaltyAgreementTemplate().build(i);
      final parties = blocks.whereType<MultiSignatureBlock>().single.signatories;
      expect(parties.length, 2);
      expect(parties[0].role, 'HR Manager');
      expect(parties[0].signatureImage, isNotNull);
      expect(parties[1].role, 'Employee (Conforme)');
      expect(parties[1].signatureImage, isNotNull);
      expect((await _render(blocks)).length, greaterThan(500));
    });

    test('builds with only HR signed — employee gets a blank wet-sign line',
        () async {
      final i = _seed().copyWith(companySignaturePngB64: _png1x1B64);
      final blocks = const PenaltyAgreementTemplate().build(i);
      final parties = blocks.whereType<MultiSignatureBlock>().single.signatories;
      expect(parties[0].signatureImage, isNotNull);
      expect(parties[1].signatureImage, isNull);
      expect(parties[1].name, 'Jamaica Vidal');
      expect((await _render(blocks)).length, greaterThan(500));
    });

    test('builds with NEITHER signature', () async {
      final blocks = const PenaltyAgreementTemplate().build(_seed());
      final parties = blocks.whereType<MultiSignatureBlock>().single.signatories;
      expect(parties[0].signatureImage, isNull);
      expect(parties[1].signatureImage, isNull);
      expect((await _render(blocks)).length, greaterThan(500));
    });

    test('a corrupt base64 signature degrades to a blank line, not a crash',
        () {
      final i = _seed().copyWith(employeeSignaturePngB64: '!!!not-base64!!!');
      final parties = const PenaltyAgreementTemplate()
          .build(i)
          .whereType<MultiSignatureBlock>()
          .single
          .signatories;
      expect(parties[1].signatureImage, isNull);
      // Sanity: the constant used elsewhere in this file IS decodable.
      expect(base64Decode(_png1x1B64), isNotEmpty);
    });

    test('emptyInputs still produce renderable blocks', () {
      final blocks =
          const PenaltyAgreementTemplate().build(
            const PenaltyAgreementTemplate().emptyInputs(),
          );
      expect(blocks, isNotEmpty);
      expect(blocks.whereType<TableBlock>().single.rows, isEmpty);
    });

    test('remarks render only when present', () {
      final without = const PenaltyAgreementTemplate().build(_seed());
      final with_ = const PenaltyAgreementTemplate()
          .build(_seed().copyWith(remarks: 'Starts on the Aug 15 cutoff.'));
      expect(with_.length, without.length + 2);
    });
  });
}
