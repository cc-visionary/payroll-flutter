import 'package:flutter_test/flutter_test.dart';

import 'package:payroll_flutter/features/documents/templates/nod_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/nod_template.dart';

void main() {
  group('NodInputs.fromJson', () {
    final full = NodInputs(
      employeeId: 'EMP-1',
      employeeFullName: 'Jane Doe',
      employeePosition: 'Analyst',
      employeeGender: 'female',
      companyId: 'CO-1',
      companyName: 'Acme Corp',
      companyAddress: '2 Side St, Manila',
      hrManagerName: 'Brixter',
      linkedNteDocumentId: 'NTE-99',
      nteDate: DateTime.utc(2026, 1, 2, 3, 4, 5),
      charges: 'Tardiness',
      employeeResponseSummary: 'Acknowledged the lapse.',
      findings: 'Pattern of late arrivals confirmed.',
      decision: NodDecision.suspension,
      suspensionDays: 3,
      effectiveDate: DateTime.utc(2026, 2, 1),
      issueDate: DateTime.utc(2026, 1, 20),
    );

    final empty = NodInputs(
      employeeId: 'EMP-2',
      employeeFullName: 'John Roe',
      companyId: 'CO-2',
      companyName: 'Beta Inc',
      // nullable fields left null, optionals left default
      linkedNteDocumentId: null,
      nteDate: null,
      decision: NodDecision.noAction,
      effectiveDate: DateTime.utc(2026, 3, 5),
      issueDate: DateTime.utc(2026, 3, 1),
    );

    test('round-trips toJson (full sample)', () {
      expect(NodInputs.fromJson(full.toJson()).toJson(), full.toJson());
    });

    test('round-trips toJson (null/empty sample)', () {
      expect(NodInputs.fromJson(empty.toJson()).toJson(), empty.toJson());
    });

    test('rebuilds blocks', () {
      expect(
        const NodTemplate().build(NodInputs.fromJson(full.toJson())),
        isNotEmpty,
      );
    });
  });
}
