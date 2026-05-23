import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/documents/blocks/bullet_list_block.dart';
import 'package:payroll_flutter/features/documents/blocks/lettered_list_block.dart';
import 'package:payroll_flutter/features/documents/blocks/section_heading_block.dart';
import 'package:payroll_flutter/features/documents/blocks/signature_line_block.dart';
import 'package:payroll_flutter/features/documents/blocks/title_block.dart';
import 'package:payroll_flutter/features/documents/templates/nda_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/nda_template.dart';

void main() {
  NdaInputs seed() => NdaInputs(
        employeeId: 'e1',
        employeeFullName: 'Jamaica Vidal',
        employeePosition: 'HR Assistant',
        employeeHomeAddress: '8 Tendido St, Quezon City',
        companyId: 'c1',
        companyName: 'Luxium Trading Co.',
        companyAddress: '908 Alvarado St, Manila',
        effectiveDate: DateTime(2025, 6, 9),
        authorizedSignatoryName: 'Brixter Del Mundo',
        authorizedSignatoryRole: 'Authorized Signatory',
      );

  test('first block is the centered title', () {
    final blocks = const NdaTemplate().build(seed());
    expect(blocks.first, isA<TitleBlock>());
    final title = blocks.first as TitleBlock;
    expect(title.text, 'Confidentiality & Non-Disclosure Agreement');
    expect(title.centered, true);
  });

  test('16 section headings numbered 1..16 in order', () {
    final blocks = const NdaTemplate().build(seed());
    final headings = blocks.whereType<SectionHeadingBlock>().toList();
    expect(headings.length, 16);
    expect(headings.map((h) => h.number).toList(),
        List<int>.generate(16, (n) => n + 1));
  });

  test('a lettered list is present (§4)', () {
    final blocks = const NdaTemplate().build(seed());
    expect(blocks.whereType<LetteredListBlock>(), isNotEmpty);
  });

  test('bullet lists are present (§3, §11, §16)', () {
    final blocks = const NdaTemplate().build(seed());
    expect(blocks.whereType<BulletListBlock>().length, greaterThanOrEqualTo(3));
  });

  test('a signature line block is present', () {
    final blocks = const NdaTemplate().build(seed());
    expect(blocks.whereType<SignatureLineBlock>(), isNotEmpty);
  });
}
