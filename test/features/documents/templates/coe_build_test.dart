import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/documents/blocks/title_block.dart';
import 'package:payroll_flutter/features/documents/blocks/signature_block.dart';
import 'package:payroll_flutter/features/documents/templates/coe_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/coe_template.dart';

void main() {
  CoeInputs filled() => CoeInputs(
        employeeId: 'e1',
        employeeFullName: 'Donald Xu',
        companyId: 'c1',
        companyName: 'LUXIUM',
        companyAddress: 'Manila',
        hrManagerName: 'Brixter',
        position: 'CTO',
        dateStart: DateTime(2024, 1, 1),
        dateEnd: DateTime(2026, 4, 30),
      );

  test('build returns block list with TITLE = COE', () {
    const t = CoeTemplate();
    final blocks = t.build(filled());
    expect(blocks.whereType<TitleBlock>().first.text,
        'CERTIFICATE OF EMPLOYMENT');
  });

  test('build ends with a SignatureBlock for HR manager', () {
    const t = CoeTemplate();
    final blocks = t.build(filled());
    expect(blocks.last, isA<SignatureBlock>());
  });
}
