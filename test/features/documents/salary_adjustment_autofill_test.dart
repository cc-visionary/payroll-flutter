import 'package:decimal/decimal.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/compensation_change.dart';
import 'package:payroll_flutter/data/models/employee.dart';
import 'package:payroll_flutter/data/repositories/compensation_change_repository.dart';
import 'package:payroll_flutter/features/documents/templates/document_template.dart';
import 'package:payroll_flutter/features/documents/templates/salary_adjustment_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/salary_adjustment_template.dart';

/// Regression: the salary-adjustment autofill must render the LINKED change
/// (threaded via [AutofillContext.compensationChangeId]) rather than always
/// defaulting to the newest non-cancelled change. Generating an OLDER change's
/// notice used to render the newest one's salary/mode.
void main() {
  // Two changes for the same employee. C1 is the OLDER salary-adjustment
  // (SALARY_INCREASE → salaryAdjustment mode); C2 is the NEWER promotion
  // (PROMOTION mode) with a higher salary. `createdAt` orders them.
  final c1 = CompensationChange(
    id: 'C1',
    companyId: 'co1',
    employeeId: 'e1',
    changeType: 'SALARY_INCREASE',
    status: 'SCHEDULED',
    effectiveDate: DateTime(2026, 2, 1),
    prevBaseSalary: Decimal.parse('25000'),
    newBaseSalary: Decimal.parse('30000'),
    newWageType: 'MONTHLY',
    reason: 'Merit increase',
    initiatedById: 'admin',
    createdAt: DateTime(2026, 1, 1),
  );
  final c2 = CompensationChange(
    id: 'C2',
    companyId: 'co1',
    employeeId: 'e1',
    changeType: 'PROMOTION',
    status: 'SCHEDULED',
    effectiveDate: DateTime(2026, 3, 1),
    prevBaseSalary: Decimal.parse('40000'),
    newBaseSalary: Decimal.parse('50000'),
    newWageType: 'MONTHLY',
    reason: 'Promotion to Lead',
    initiatedById: 'admin',
    createdAt: DateTime(2026, 2, 1),
  );

  /// Pumps a ProviderScope overriding the employee's compensation-change list,
  /// captures a ref, and runs the salary-adjustment autofill for [changeId].
  /// `roleScorecardId` is null so the scorecard lookups are skipped — the
  /// change snapshots are the sole source of salary/mode.
  Future<SalaryAdjustmentInputs> runAutofill(
    WidgetTester tester,
    String? changeId,
  ) async {
    late WidgetRef capturedRef;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          compensationChangesByEmployeeProvider(
            'e1',
          ).overrideWith((ref) async => [c1, c2]),
        ],
        child: Consumer(
          builder: (_, ref, _) {
            capturedRef = ref;
            return const SizedBox();
          },
        ),
      ),
    );
    const t = SalaryAdjustmentTemplate();
    return t.autofill(
      AutofillContext(
        employee: _buildEmployee(),
        ref: capturedRef,
        compensationChangeId: changeId,
      ),
    );
  }

  testWidgets('linked change id selects THAT change, not the newest', (
    tester,
  ) async {
    final filled = await runAutofill(tester, 'C1');
    expect(filled.type, SalaryAdjustmentType.salaryAdjustment);
    expect(filled.newSalary, Decimal.parse('30000'));
    expect(filled.oldSalary, Decimal.parse('25000'));
  });

  testWidgets('no linked change id falls back to the newest change', (
    tester,
  ) async {
    final filled = await runAutofill(tester, null);
    expect(filled.type, SalaryAdjustmentType.promotion);
    expect(filled.newSalary, Decimal.parse('50000'));
    expect(filled.oldSalary, Decimal.parse('40000'));
  });

  testWidgets('unknown linked change id falls back to the newest change', (
    tester,
  ) async {
    final filled = await runAutofill(tester, 'does-not-exist');
    expect(filled.type, SalaryAdjustmentType.promotion);
    expect(filled.newSalary, Decimal.parse('50000'));
  });
}

Employee _buildEmployee() => Employee(
  id: 'e1',
  companyId: 'co1',
  employeeNumber: 'EMP-001',
  firstName: 'Jamaica',
  lastName: 'Vidal',
  hiringEntityId: null,
  employmentType: 'REGULAR',
  employmentStatus: 'ACTIVE',
  hireDate: DateTime(2020, 1, 1),
  isRankAndFile: true,
  isOtEligible: true,
  isNdEligible: true,
  isHolidayPayEligible: true,
  taxOnFullEarnings: false,
);
