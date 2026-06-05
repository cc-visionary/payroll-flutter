import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/documents/blocks/paragraph_block.dart';
import 'package:payroll_flutter/features/documents/templates/resignation_acceptance_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/resignation_acceptance_template.dart';

ResignationAcceptanceInputs _i({bool clearance = true, bool finalPay = true}) =>
    ResignationAcceptanceInputs(
      employeeId: 'e1',
      employeeFullName: 'B',
      employeePosition: 'Dev',
      companyId: 'c1',
      companyName: 'Luxium',
      hrManagerName: 'HR',
      resignationDate: DateTime(2026, 6, 1),
      lastDayOfWork: DateTime(2026, 7, 1),
      issueDate: DateTime(2026, 6, 5),
      includeClearanceMention: clearance,
      includeFinalPayMention: finalPay,
    );

void main() {
  test('id + name + supportsBulk', () {
    const t = ResignationAcceptanceTemplate();
    expect(t.id, 'resignation_acceptance');
    expect(t.supportsBulk, isTrue);
  });

  test('clearance toggle off → no clearance line', () {
    const t = ResignationAcceptanceTemplate();
    final body = t
        .build(_i(clearance: false))
        .whereType<ParagraphBlock>()
        .map((p) => p.text)
        .join(' ');
    expect(body.toLowerCase(), isNot(contains('clearance')));
  });

  test('finalPay toggle off → no DOLE LA 06-20 line', () {
    const t = ResignationAcceptanceTemplate();
    final body = t
        .build(_i(finalPay: false))
        .whereType<ParagraphBlock>()
        .map((p) => p.text)
        .join(' ');
    expect(body, isNot(contains('06-20')));
  });

  test('both on → both lines present', () {
    const t = ResignationAcceptanceTemplate();
    final body = t
        .build(_i())
        .whereType<ParagraphBlock>()
        .map((p) => p.text)
        .join(' ');
    expect(body.toLowerCase(), contains('clearance'));
    expect(body, contains('06-20'));
  });
}
