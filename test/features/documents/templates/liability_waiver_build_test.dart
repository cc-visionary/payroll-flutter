import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/documents/blocks/emphasis_paragraph_block.dart';
import 'package:payroll_flutter/features/documents/blocks/heading_block.dart';
import 'package:payroll_flutter/features/documents/blocks/lettered_list_block.dart';
import 'package:payroll_flutter/features/documents/blocks/signature_line_block.dart';
import 'package:payroll_flutter/features/documents/templates/liability_waiver_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/liability_waiver_template.dart';

void main() {
  LiabilityWaiverInputs seed() => LiabilityWaiverInputs(
        employeeId: 'emp-1',
        employeeFullName: 'Donald Xu',
        employeeAddress: '123 Mabini St, Binondo, Manila',
        companyId: 'co-1',
        companyName: 'LUXIUM TRADING CO.',
        dateOfEmployment: DateTime(2024, 1, 15),
        outingDate: DateTime(2026, 6, 20),
        outingLocation: 'Tagaytay City, Cavite',
        dateSigned: DateTime(2026, 5, 23),
        signingPlace: 'Manila City',
      );

  const t = LiabilityWaiverTemplate();

  test('first block is the title HeadingBlock', () {
    final blocks = t.build(seed());
    expect(blocks.first, isA<HeadingBlock>());
    expect((blocks.first as HeadingBlock).text, 'Travel Release and Waiver');
  });

  test('two LetteredListBlocks: §2 (5 items) and §3 (3 items)', () {
    final blocks = t.build(seed());
    final lettered = blocks.whereType<LetteredListBlock>().toList();
    expect(lettered.length, 2);
    expect(lettered[0].items.length, 5);
    expect(lettered[1].items.length, 3);
  });

  test('a single SignatureLineBlock with the hand-sign caption', () {
    final blocks = t.build(seed());
    final sigs = blocks.whereType<SignatureLineBlock>().toList();
    expect(sigs.length, 1);
    expect(sigs.first.signatories.length, 1);
    expect(sigs.first.signatories.first.name, isNull);
    expect(sigs.first.signatories.first.role,
        'Signature over Printed Name / Date');
  });

  test('intro + numbered EmphasisParagraphBlocks present with bold values',
      () {
    final blocks = t.build(seed());
    final emphasis = blocks.whereType<EmphasisParagraphBlock>().toList();
    final allTexts = emphasis.expand((b) => b.spans).map((s) => s.text);

    // Intro lead.
    expect(allTexts, contains('I, '));
    // Bold inline values.
    final boldTexts = emphasis
        .expand((b) => b.spans)
        .where((s) => s.bold)
        .map((s) => s.text)
        .toList();
    expect(boldTexts, contains('Donald Xu'));
    expect(boldTexts, contains('LUXIUM TRADING CO.'));
    expect(boldTexts, contains('Company Outing'));
    expect(boldTexts, contains('Tagaytay City, Cavite'));
    expect(boldTexts, contains('Manila City'));

    // Numbered item leads.
    expect(allTexts, contains('1.   I am an employee of '));
    expect(
        allTexts,
        contains('2.   In connection with the outing (hereafter referred to '
            'as the "Trip"), I acknowledge and affirm the following:'));
    expect(allTexts, contains('3.   I affirm that:'));
    expect(allTexts, contains('4.   '));
    expect(boldTexts, contains('Medical and Emergency Consent'));

    // Witness clause with ordinal date (23rd) + place.
    final witness = emphasis.any((b) =>
        b.spans.any((s) => s.text.contains('IN WITNESS WHEREOF') &&
            s.text.contains('23rd day of May 2026')));
    expect(witness, true);
  });
}
