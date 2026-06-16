import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/documents/templates/non_reg_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/non_reg_template.dart';

void main() {
  // Fully-populated sample: every field set, nested lists non-empty,
  // nullable fields all non-null, dates set.
  final fullSample = NonRegInputs(
    employeeId: 'EMP-001',
    employeeFullName: 'Juan Dela Cruz',
    employeeLastName: 'Dela Cruz',
    employeePosition: 'Sales Associate',
    companyId: 'CO-09',
    companyName: 'OgKilz',
    companyAddress: '123 Badminton St · Quezon City, Metro Manila, 1100',
    hrManagerName: 'Brixter Reyes',
    dateIssued: DateTime(2026, 6, 16, 9, 30, 15),
    probationaryStart: DateTime(2025, 12, 1),
    probationaryEnd: DateTime(2026, 6, 1, 23, 59, 59),
    effectiveEndDate: DateTime(2026, 6, 1),
    salutationName: 'Mr. Dela Cruz',
    noteOnScope: 'Evaluation limited to the probationary KPIs in Annex B.',
    findings: const [
      FindingSection(
        title: 'Sales Targets',
        standard: 'Meet 80% of monthly quota.',
        finding: 'Achieved 52% across the period.',
        subFindings: [
          SubFinding(title: 'Q1', body: 'Missed quota by 40%.'),
          SubFinding(title: 'Q2', body: 'Missed quota by 28%.'),
        ],
      ),
      FindingSection(
        title: 'Attendance',
        standard: 'No more than 2 unexcused absences.',
        finding: '5 unexcused absences recorded.',
      ),
    ],
    witnessName: 'Maria Santos',
  );

  // Nullable/empty sample: nullable fields null, optional strings empty,
  // findings empty, only required non-null fields populated.
  final emptySample = NonRegInputs(
    employeeId: 'EMP-002',
    employeeFullName: 'Pedro Penduko',
    employeeLastName: 'Penduko',
    employeePosition: '',
    companyId: 'CO-02',
    companyName: 'HAVIT',
    companyAddress: null,
    hrManagerName: null,
    dateIssued: DateTime(2026, 1, 5),
    probationaryStart: null,
    probationaryEnd: null,
    effectiveEndDate: null,
    salutationName: 'Pedro',
    noteOnScope: '',
    findings: const [],
    witnessName: '',
  );

  test('round-trips toJson', () {
    expect(
      NonRegInputs.fromJson(fullSample.toJson()).toJson(),
      fullSample.toJson(),
    );
  });

  test('round-trips toJson with nullable/empty fields', () {
    expect(
      NonRegInputs.fromJson(emptySample.toJson()).toJson(),
      emptySample.toJson(),
    );
  });

  test('rebuilds blocks', () {
    expect(
      const NonRegTemplate().build(NonRegInputs.fromJson(fullSample.toJson())),
      isNotEmpty,
    );
  });
}
