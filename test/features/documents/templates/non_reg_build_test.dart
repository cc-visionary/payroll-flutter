import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/documents/blocks/heading_block.dart';
import 'package:payroll_flutter/features/documents/blocks/labelled_bullet_list_block.dart';
import 'package:payroll_flutter/features/documents/blocks/letter_meta_block.dart';
import 'package:payroll_flutter/features/documents/blocks/page_break_block.dart';
import 'package:payroll_flutter/features/documents/blocks/section_heading_block.dart';
import 'package:payroll_flutter/features/documents/blocks/signature_block.dart';
import 'package:payroll_flutter/features/documents/templates/non_reg_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/non_reg_template.dart';

void main() {
  NonRegInputs seed({
    List<FindingSection> findings = const [],
    String noteOnScope = '',
    String witnessName = '',
  }) =>
      NonRegInputs(
        employeeId: 'e1',
        employeeFullName: 'Jamaica Vidal',
        employeeLastName: 'Vidal',
        employeePosition: 'HR Assistant',
        companyId: 'c1',
        companyName: 'LUXIUM TRADING CO.',
        hrManagerName: 'Brixter Del Mundo',
        dateIssued: DateTime(2025, 12, 3),
        probationaryStart: DateTime(2025, 6, 9),
        probationaryEnd: DateTime(2025, 12, 6),
        effectiveEndDate: DateTime(2025, 12, 5),
        salutationName: 'Ms. Vidal',
        noteOnScope: noteOnScope,
        findings: findings,
        witnessName: witnessName,
      );

  test('build starts with LetterMetaBlock', () {
    const t = NonRegTemplate();
    final blocks = t.build(seed(findings: const [
      FindingSection(title: 'T', standard: 's', finding: 'f'),
    ]));
    expect(blocks.first, isA<LetterMetaBlock>());
  });

  test('build contains SUBJECT heading after meta', () {
    const t = NonRegTemplate();
    final blocks = t.build(seed(findings: const [
      FindingSection(title: 'T', standard: 's', finding: 'f'),
    ]));
    final heading = blocks
        .whereType<HeadingBlock>()
        .firstWhere((h) => h.text.startsWith('SUBJECT'));
    expect(heading.text, 'SUBJECT: NOTICE OF NON-REGULARIZATION');
  });

  test('each finding produces SectionHeadingBlock + LabelledBulletListBlock',
      () {
    const t = NonRegTemplate();
    final blocks = t.build(seed(findings: const [
      FindingSection(title: 'A', standard: 's1', finding: 'f1'),
      FindingSection(title: 'B', standard: 's2', finding: 'f2'),
    ]));
    final headings = blocks.whereType<SectionHeadingBlock>().toList();
    final lists = blocks.whereType<LabelledBulletListBlock>().toList();
    expect(headings.length, 2);
    expect(lists.length, 2);
    expect(headings[0].number, 1);
    expect(headings[1].number, 2);
    expect(headings[0].title, 'A');
  });

  test('DECISION heading present after findings', () {
    const t = NonRegTemplate();
    final blocks = t.build(seed(findings: const [
      FindingSection(title: 'T', standard: 's', finding: 'f'),
    ]));
    expect(
      blocks.whereType<HeadingBlock>().any((h) => h.text == 'DECISION'),
      true,
    );
  });

  test('PageBreakBlock separates main body from acknowledgment', () {
    const t = NonRegTemplate();
    final blocks = t.build(seed(findings: const [
      FindingSection(title: 'T', standard: 's', finding: 'f'),
    ]));
    expect(blocks.whereType<PageBreakBlock>().length, 1);
  });

  test('ACKNOWLEDGMENT OF RECEIPT heading + 2 signature lines on page 2',
      () {
    const t = NonRegTemplate();
    final blocks = t.build(seed(findings: const [
      FindingSection(title: 'T', standard: 's', finding: 'f'),
    ]));
    final pbIndex = blocks.indexWhere((b) => b is PageBreakBlock);
    final afterBreak = blocks.sublist(pbIndex + 1);
    expect(
      afterBreak.whereType<HeadingBlock>().any(
            (h) => h.text == 'ACKNOWLEDGMENT OF RECEIPT',
          ),
      true,
    );
    // HR signature is BEFORE the break; employee + witness signatures
    // are AFTER.
    expect(afterBreak.whereType<SignatureBlock>().length, 2);
  });

  test('noteOnScope conditionally inserted', () {
    const t = NonRegTemplate();
    final without = t.build(seed(findings: const [
      FindingSection(title: 'T', standard: 's', finding: 'f'),
    ]));
    final with_ = t.build(seed(
      findings: const [FindingSection(title: 'T', standard: 's', finding: 'f')],
      noteOnScope: 'Reassigned to LCT bazaar.',
    ));
    // Adding a non-empty noteOnScope inserts ONE extra block.
    expect(with_.length, without.length + 1);
  });

  test('sub-findings render as nested children in LabelledBulletListBlock',
      () {
    const t = NonRegTemplate();
    final blocks = t.build(seed(findings: const [
      FindingSection(
        title: 'T',
        standard: 's',
        finding: 'f',
        subFindings: [
          SubFinding(title: 'A', body: 'a'),
          SubFinding(title: 'B', body: 'b'),
        ],
      ),
    ]));
    final list = blocks.whereType<LabelledBulletListBlock>().first;
    // Two top-level items: Standard, Finding. Finding has 2 children.
    expect(list.items.length, 2);
    expect(list.items[1].children.length, 2);
    expect(list.items[1].children[0].leadBold, 'A');
  });
}
