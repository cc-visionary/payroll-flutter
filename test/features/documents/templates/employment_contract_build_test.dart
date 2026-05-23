import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/documents/blocks/emphasis_paragraph_block.dart';
import 'package:payroll_flutter/features/documents/blocks/heading_block.dart';
import 'package:payroll_flutter/features/documents/blocks/lettered_list_block.dart';
import 'package:payroll_flutter/features/documents/blocks/multi_signature_block.dart';
import 'package:payroll_flutter/features/documents/blocks/page_break_block.dart';
import 'package:payroll_flutter/features/documents/blocks/signature_line_block.dart';
import 'package:payroll_flutter/features/documents/blocks/section_heading_block.dart';
import 'package:payroll_flutter/features/documents/blocks/title_block.dart';
import 'package:payroll_flutter/features/documents/templates/employment_contract_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/employment_contract_template.dart';

void main() {
  // Section titles in canonical §1..§17 order — mirror of the template's
  // private `_sectionTitles`.
  const sectionTitles = <String>[
    'PROBATIONARY EMPLOYMENT',
    'JOB TITLE AND DESCRIPTION',
    'PERIOD OF PROBATIONARY EMPLOYMENT',
    'PROBATIONARY EVALUATION',
    'COMPENSATION',
    'WORK HOURS',
    'ASSIGNMENT OF TASKS',
    'MEDICAL/DRUG TESTS',
    'COMPANY RULES AND REGULATIONS',
    'DEDUCTIONS FOR COMPANY-INCURRED COSTS',
    'DISCIPLINARY MEASURES',
    'NON-COMPETE AGREEMENT',
    'TERMINATION OF EMPLOYMENT',
    'FINAL PAY',
    'CONFIDENTIALITY',
    'SEPARABILITY CLAUSE',
    'ENTIRE AGREEMENT',
  ];

  EmploymentContractInputs seed({Uint8List? logoBytes}) =>
      EmploymentContractInputs(
        employeeId: 'e1',
        employeeFullName: 'Jamaica Vidal',
        employeeAddress: '123 Mabini St, Binondo, Manila',
        companyId: 'c1',
        companyName: 'LUXIUM TRADING CO.',
        companyAddress: '456 Quintin Paredes, Binondo, Manila',
        representativeName: 'Brixter Del Mundo',
        representativeRole: 'People Manager',
        place: 'Binondo, Metro Manila, Philippines',
        dateEntered: DateTime(2025, 12, 3),
        industry: 'Retail Industry',
        position: 'HR Assistant',
        probationStart: DateTime(2025, 6, 9),
        probationEnd: DateTime(2025, 12, 6),
        monthlySalary: '17,000',
        workHoursPerDay: 8,
        workDaysPerWeek: 'Monday to Saturday',
        nonCompeteMonths: 24,
        employerSignatoryName: 'Brixter Del Mundo',
        employerSignatoryRole: 'People Manager',
        witness1Name: 'Christopher Lim',
        witness1Role: 'COO',
        witness2Name: 'Clinton Xu',
        witness2Role: 'CEO',
        missionStatement: 'Support HR operations end to end.',
        responsibilities: const [
          ContractResponsibility(
            area: 'Recruitment',
            tasks: ['Post job openings', 'Screen applicants'],
          ),
          ContractResponsibility(
            area: 'Records',
            tasks: ['Maintain 201 files'],
          ),
        ],
        kpis: const [
          ContractKpi(metric: 'Time to fill', frequency: 'Monthly'),
        ],
        logoBytes: logoBytes,
      );

  const t = EmploymentContractTemplate();

  test('first block is the centered TitleBlock', () {
    final blocks = t.build(seed());
    expect(blocks.first, isA<TitleBlock>());
    expect((blocks.first as TitleBlock).text, 'EMPLOYMENT CONTRACT');
  });

  test('EC ignores logoBytes — first block is still the TitleBlock', () {
    final blocks = t.build(seed(logoBytes: Uint8List.fromList([1, 2, 3])));
    expect(blocks.first, isA<TitleBlock>());
    expect((blocks.first as TitleBlock).text, 'EMPLOYMENT CONTRACT');
  });

  test('exactly 17 SectionHeadingBlocks, numbered 1..17 in order with '
      'matching titles', () {
    final blocks = t.build(seed());
    final sections = blocks.whereType<SectionHeadingBlock>().toList();
    expect(sections.length, 17);
    for (var n = 0; n < 17; n++) {
      expect(sections[n].number, n + 1);
      expect(sections[n].title, sectionTitles[n]);
    }
  });

  test('exactly two PageBreakBlocks (Annex A + Annex B)', () {
    final blocks = t.build(seed());
    expect(blocks.whereType<PageBreakBlock>().length, 2);
  });

  test('Annex B TitleBlock appears after the second PageBreakBlock', () {
    final blocks = t.build(seed());
    final breaks = <int>[];
    for (var idx = 0; idx < blocks.length; idx++) {
      if (blocks[idx] is PageBreakBlock) breaks.add(idx);
    }
    expect(breaks.length, 2);
    final after = blocks.sublist(breaks[1] + 1);
    final titles = after.whereType<TitleBlock>().toList();
    expect(titles, isNotEmpty);
    expect(titles.first.text, startsWith('Annex B'));
  });

  test('a LetteredListBlock is present (§13 termination grounds)', () {
    final blocks = t.build(seed());
    final lettered = blocks.whereType<LetteredListBlock>().toList();
    expect(lettered.length, 1);
    expect(lettered.first.items.length, 6);
  });

  test('Annex A TitleBlock appears after the PageBreakBlock', () {
    final blocks = t.build(seed());
    final breakIdx = blocks.indexWhere((b) => b is PageBreakBlock);
    expect(breakIdx, greaterThanOrEqualTo(0));
    final after = blocks.sublist(breakIdx + 1);
    final annex = after.whereType<TitleBlock>().toList();
    expect(annex, isNotEmpty);
    expect(annex.first.text, startsWith('Annex A'));
  });

  test('responsibilities produce numbered area labels', () {
    final blocks = t.build(seed());
    final emphasisTexts = blocks
        .whereType<EmphasisParagraphBlock>()
        .expand((b) => b.spans)
        .map((s) => s.text)
        .toList();
    // Area labels are now numbered inside EmphasisParagraphBlock spans.
    expect(emphasisTexts, contains('1. Recruitment'));
    expect(emphasisTexts, contains('2. Records'));
  });

  test('Annex A has Training and Development, Work Hours, and Performance '
      'Evaluation headings', () {
    final blocks = t.build(seed());
    final headings =
        blocks.whereType<HeadingBlock>().map((b) => b.text).toList();
    expect(headings, contains('Duties and Responsibilities'));
    expect(headings, contains('Training and Development'));
    expect(headings, contains('Work Hours'));
    expect(headings, contains('Performance Evaluation'));
  });

  test('Annex A Performance Evaluation includes an Evaluation Timeline', () {
    final blocks = t.build(seed());
    final emphasisTexts = blocks
        .whereType<EmphasisParagraphBlock>()
        .expand((b) => b.spans)
        .map((s) => s.text)
        .toList();
    expect(emphasisTexts, contains('Evaluation Timeline'));
    expect(emphasisTexts, contains('Key Performance Indicators (KPIs)'));
  });

  test('two SignatureLineBlocks (stacked parties + row of witnesses), '
      'no MultiSignatureBlocks', () {
    final blocks = t.build(seed());
    expect(blocks.whereType<MultiSignatureBlock>(), isEmpty);
    final sigs = blocks.whereType<SignatureLineBlock>().toList();
    expect(sigs.length, 2);
    // Employer + employee, stacked.
    expect(sigs[0].signatories.length, 2);
    expect(sigs[0].row, false);
    // Two witnesses, side by side.
    expect(sigs[1].signatories.length, 2);
    expect(sigs[1].row, true);
  });
}
