import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/payroll/runs/compute/compute_service.dart';

/// Guards the projection-vs-read contract in [PayrollComputeService.computeRun].
/// The compute reads several flags directly off the employee `row`; a column
/// that is read but not SELECTed silently reads as null/false. This regression
/// test exists because the statutory force-enroll overrides were dropped from
/// the SELECT, which disabled force-enrolment for probationary employees.
void main() {
  group('PayrollComputeService.employeeSelectColumns', () {
    test('includes the statutory force-enroll override columns', () {
      const cols = PayrollComputeService.employeeSelectColumns;
      expect(cols, contains('sss_eligibility_override'));
      expect(cols, contains('philhealth_eligibility_override'));
      expect(cols, contains('pagibig_eligibility_override'));
    });

    test(
      'includes the per-employee flags read when building the engine input',
      () {
        const cols = PayrollComputeService.employeeSelectColumns;
        for (final col in const [
          'regularization_date',
          'employment_type',
          'is_ot_eligible',
          'is_nd_eligible',
          'tax_on_full_earnings',
          'declared_wage_override',
          'declared_wage_type',
        ]) {
          expect(cols, contains(col), reason: '$col must be SELECTed');
        }
      },
    );
  });
}
