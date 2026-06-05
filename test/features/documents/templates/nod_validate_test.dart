import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/documents/templates/nod_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/nod_validate.dart';

NodInputs _base() => NodInputs(
  employeeId: 'e1',
  employeeFullName: 'Bob',
  companyId: 'c1',
  companyName: 'X',
  hrManagerName: 'HR',
  charges: 'Tardiness',
  employeeResponseSummary: 'Bob admits the lateness.',
  findings: 'Substantiated.',
  decision: NodDecision.writtenWarning,
  effectiveDate: DateTime(2026, 6, 6),
  issueDate: DateTime(2026, 6, 5),
);

void main() {
  test('valid baseline passes', () => expect(validateNod(_base()), isEmpty));

  test(
    'charges required',
    () => expect(
      validateNod(_base().copyWith(charges: '')).map((e) => e.field),
      contains('charges'),
    ),
  );

  test(
    'employee response required',
    () => expect(
      validateNod(
        _base().copyWith(employeeResponseSummary: ''),
      ).map((e) => e.field),
      contains('employeeResponseSummary'),
    ),
  );

  test(
    'findings required',
    () => expect(
      validateNod(_base().copyWith(findings: '')).map((e) => e.field),
      contains('findings'),
    ),
  );

  test('suspension requires days > 0', () {
    final i = _base().copyWith(
      decision: NodDecision.suspension,
      suspensionDays: 0,
    );
    expect(validateNod(i).map((e) => e.field), contains('suspensionDays'));
  });

  test('issueDate after effectiveDate rejected', () {
    final i = _base().copyWith(
      issueDate: DateTime(2026, 6, 10),
      effectiveDate: DateTime(2026, 6, 6),
    );
    expect(validateNod(i).map((e) => e.field), contains('effectiveDate'));
  });
}
