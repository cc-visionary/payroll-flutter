import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/employees/employee_form_screen.dart';

void main() {
  test('derive uses scorecard entity; manual uses explicit pick', () {
    expect(
      resolveBrandAllocation(
        deriveFromScorecard: true,
        scorecardHiringEntityId: 'sc-entity',
        manualHiringEntityId: 'manual-entity',
      ),
      'sc-entity',
    );
    expect(
      resolveBrandAllocation(
        deriveFromScorecard: false,
        scorecardHiringEntityId: 'sc-entity',
        manualHiringEntityId: 'manual-entity',
      ),
      'manual-entity',
    );
  });

  test('derive with no scorecard entity resolves null (form blocks save)', () {
    expect(
      resolveBrandAllocation(
        deriveFromScorecard: true,
        scorecardHiringEntityId: null,
        manualHiringEntityId: 'manual-entity',
      ),
      isNull,
    );
  });
}
