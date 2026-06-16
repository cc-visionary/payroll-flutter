import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/documents/templates/nte_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/nte_template.dart';

void main() {
  // Sample with every field populated, nullable fields non-null, and the
  // nested charges list carrying >1 element each with a non-trivial Delta body.
  final fullSample = NteInputs(
    employeeId: 'EMP-001',
    employeeFullName: 'Juan Dela Cruz',
    employeeFirstName: 'Juan',
    employeeLastName: 'Dela Cruz',
    employeeHonorific: 'Mr.',
    employeePosition: 'Software Engineer',
    employeeDepartment: 'Engineering',
    companyId: 'CO-100',
    companyName: 'Luxium HQ',
    companyAddress: '123 Makati Ave, Makati City',
    hrManagerName: 'Maria Santos',
    dateIssued: DateTime.parse('2025-01-05T09:00:00.000'),
    responseDeadline: DateTime.parse('2025-01-10T17:00:00.000'),
    subjectSubtopic: 'Attendance Infraction',
    charges: [
      NteCharge(
        title: 'Repeated Tardiness',
        body: Delta()
          ..insert('You arrived late on multiple occasions.\n')
          ..insert('Specifically on Jan 2 and Jan 3.\n'),
      ),
      NteCharge(
        title: 'Unauthorized Absence',
        body: Delta()..insert('You were absent without notice.\n'),
      ),
    ],
    applicableViolations: const [
      'Code of Conduct §2.1',
      'Attendance Policy §4.3',
    ],
  );

  // Sample exercising defaults / nulls / empty collections.
  final minimalSample = NteInputs(
    employeeId: 'EMP-002',
    employeeFullName: 'Anna Reyes',
    employeeFirstName: 'Anna',
    employeeLastName: 'Reyes',
    employeePosition: 'Brand Handler',
    employeeDepartment: 'Marketing',
    companyId: 'CO-200',
    companyName: 'GameCove',
    dateIssued: DateTime.parse('2025-03-10T08:00:00.000'),
    responseDeadline: DateTime.parse('2025-03-15T17:00:00.000'),
    subjectSubtopic: '',
    charges: const [],
    applicableViolations: const [],
    // employeeHonorific => default ''
    // companyAddress, hrManagerName => null
  );

  test('round-trips toJson (all fields populated)', () {
    expect(
      NteInputs.fromJson(fullSample.toJson()).toJson(),
      fullSample.toJson(),
    );
  });

  test('round-trips toJson (nullable/empty fields)', () {
    expect(
      NteInputs.fromJson(minimalSample.toJson()).toJson(),
      minimalSample.toJson(),
    );
  });

  test('rebuilds blocks', () {
    expect(
      const NteTemplate().build(NteInputs.fromJson(fullSample.toJson())),
      isNotEmpty,
    );
    expect(
      const NteTemplate().build(NteInputs.fromJson(minimalSample.toJson())),
      isNotEmpty,
    );
  });
}
