import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/documents/blocks/block.dart';
import 'package:payroll_flutter/features/documents/blocks/company_header_block.dart';
import 'package:payroll_flutter/features/documents/blocks/emphasis_paragraph_block.dart';
import 'package:payroll_flutter/features/documents/blocks/letterhead_block.dart';
import 'package:payroll_flutter/features/documents/blocks/paragraph_block.dart';
import 'package:payroll_flutter/features/documents/blocks/signature_block.dart';
import 'package:payroll_flutter/features/documents/blocks/title_block.dart';
import 'package:payroll_flutter/features/documents/templates/coe_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/coe_template.dart';

void main() {
  CoeInputs filled({Uint8List? logo}) => CoeInputs(
        employeeId: 'e1',
        employeeFullName: 'Donald Xu',
        employeeLastName: 'Xu',
        employeeHonorific: 'Mr.',
        companyId: 'c1',
        companyName: 'Luxium',
        companyAddress: 'Manila',
        hrManagerName: 'Brixter',
        position: 'CTO',
        place: 'Makati City',
        dateStart: DateTime(2024, 1, 1),
        dateEnd: DateTime(2026, 4, 30),
        dateIssued: DateTime(2025, 6, 9),
        logoBytes: logo,
      );

  test('first block is a LetterheadBlock when no logo (companyName non-empty)',
      () {
    const t = CoeTemplate();
    final blocks = t.build(filled());
    expect(blocks.first, isA<LetterheadBlock>());
    final title = blocks.whereType<TitleBlock>().first;
    expect(title.text, 'CERTIFICATE OF EMPLOYMENT');
    expect(title.centered, true);
  });

  test('first block is a LetterheadBlock with logoBytes when logo set', () {
    const t = CoeTemplate();
    final blocks =
        t.build(filled(logo: Uint8List.fromList(const [137, 80, 78, 71])));
    expect(blocks.first, isA<LetterheadBlock>());
    expect((blocks.first as LetterheadBlock).logoBytes, isNotNull);
  });

  test('build prepends LetterheadBlock with companyName + logo', () {
    const t = CoeTemplate();
    final blocks =
        t.build(filled(logo: Uint8List.fromList(const [137, 80, 78, 71])));
    final heads = blocks.whereType<LetterheadBlock>().toList();
    expect(heads, isNotEmpty);
    expect(heads.first.companyName, 'Luxium');
    expect(heads.first.logoBytes, isNotNull);
  });

  test('contains a bold centered "To Whom It May Concern:" emphasis', () {
    const t = CoeTemplate();
    final blocks = t.build(filled());
    final concern = blocks.whereType<EmphasisParagraphBlock>().firstWhere(
        (b) => b.spans.any((s) => s.text.contains('To Whom It May Concern')));
    expect(concern.spans.first.bold, true);
  });

  test('certify paragraph uppercases company and position', () {
    const t = CoeTemplate();
    final blocks = t.build(filled());
    final certify = blocks
        .whereType<ParagraphBlock>()
        .firstWhere((b) => b.text.startsWith('This is to certify'));
    expect(certify.text.contains('LUXIUM'), true);
    expect(certify.text.contains('CTO'), true);
  });

  test('issued paragraph uses ordinal day + place', () {
    const t = CoeTemplate();
    final blocks = t.build(filled());
    final issued = blocks
        .whereType<ParagraphBlock>()
        .firstWhere((b) => b.text.startsWith('Given this'));
    expect(issued.text.contains('9th day of June 2025'), true);
    expect(issued.text.contains('Makati City'), true);
  });

  test('ends with bold "HR MANAGER" emphasis after HR manager name', () {
    const t = CoeTemplate();
    final blocks = t.build(filled());
    expect(blocks.last, isA<EmphasisParagraphBlock>());
    final last = blocks.last as EmphasisParagraphBlock;
    expect(last.spans.first.text, 'HR MANAGER');
    expect(last.spans.first.bold, true);
  });

  test('no CompanyHeaderBlock or SignatureBlock', () {
    const t = CoeTemplate();
    final blocks = t.build(filled());
    expect(blocks.whereType<CompanyHeaderBlock>(), isEmpty);
    expect(blocks.whereType<SignatureBlock>(), isEmpty);
  });
}
