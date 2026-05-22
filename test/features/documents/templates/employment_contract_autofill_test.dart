import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/employee.dart';
import 'package:payroll_flutter/data/models/hiring_entity.dart';
import 'package:payroll_flutter/features/documents/templates/document_template.dart';
import 'package:payroll_flutter/features/documents/templates/employment_contract_template.dart';

void main() {
  test('template metadata', () {
    const t = EmploymentContractTemplate();
    expect(t.id, 'employment_contract');
    expect(t.name, 'Employment Contract');
    expect(t.version, 1);
  });

  test('emptyInputs sensible defaults', () {
    const t = EmploymentContractTemplate();
    final i = t.emptyInputs();
    expect(i.employeeId, isEmpty);
    expect(i.workHoursPerDay, 8);
    expect(i.workDaysPerWeek, 'Monday to Saturday');
    expect(i.nonCompeteMonths, 24);
    expect(i.representativeRole, 'People Manager');
    expect(i.responsibilities, isEmpty);
  });

  test('build returns empty until implemented', () {
    const t = EmploymentContractTemplate();
    expect(t.build(t.emptyInputs()), isEmpty);
  });

  testWidgets('autofill with employee + company copies basic fields',
      (tester) async {
    late WidgetRef capturedRef;
    await tester.pumpWidget(
      ProviderScope(
        child: Consumer(builder: (_, ref, __) {
          capturedRef = ref;
          return const SizedBox();
        }),
      ),
    );
    final emp = _buildEmployee();
    final co = _buildHiringEntity();
    const t = EmploymentContractTemplate();
    // Scorecard / HIRE-event / logo providers throw in the test env (no
    // Supabase); autofill swallows those and falls back to defaults.
    final filled = await t.autofill(
      AutofillContext(employee: emp, company: co, ref: capturedRef),
    );
    expect(filled.employeeId, 'e1');
    expect(filled.employeeFullName, 'Jamaica Vidal');
    expect(filled.companyId, 'c1');
    expect(filled.companyName, 'LUXIUM TRADING CO.');
    // legalSignatoryRole is null on the seeded entity → falls back.
    expect(filled.representativeRole, 'People Manager');
    expect(filled.representativeName, 'Brixter Del Mundo');
    // position from jobTitle.
    expect(filled.position, 'Sales Associate');
    // probation dates derive from hireDate (HIRE event read fails).
    expect(filled.probationStart, DateTime(2020, 1, 1));
    expect(filled.probationEnd, isNotNull);
    expect(filled.probationEnd, DateTime(2020, 7, 1));
    // Defaults preserved when scorecard read fails.
    expect(filled.workHoursPerDay, 8);
    expect(filled.workDaysPerWeek, 'Monday to Saturday');
    expect(filled.nonCompeteMonths, 24);
    expect(filled.industry, 'Retail Industry');
    expect(filled.monthlySalary, isEmpty);
    expect(filled.employerSignatoryName, 'Brixter Del Mundo');
    expect(filled.employerSignatoryRole, 'People Manager');
  });

  testWidgets('autofill returns emptyInputs when employee is null',
      (tester) async {
    late WidgetRef capturedRef;
    await tester.pumpWidget(
      ProviderScope(
        child: Consumer(builder: (_, ref, __) {
          capturedRef = ref;
          return const SizedBox();
        }),
      ),
    );
    const t = EmploymentContractTemplate();
    final filled = await t.autofill(
      AutofillContext(employee: null, company: null, ref: capturedRef),
    );
    expect(filled.employeeId, isEmpty);
    expect(filled.representativeRole, 'People Manager');
  });
}

Employee _buildEmployee() => Employee(
      id: 'e1',
      companyId: 'c1',
      employeeNumber: 'EMP-001',
      firstName: 'Jamaica',
      lastName: 'Vidal',
      jobTitle: 'Sales Associate',
      hiringEntityId: 'c1',
      employmentType: 'PROBATIONARY',
      employmentStatus: 'ACTIVE',
      hireDate: DateTime(2020, 1, 1),
      isRankAndFile: true,
      isOtEligible: true,
      isNdEligible: true,
      isHolidayPayEligible: true,
      taxOnFullEarnings: false,
      addressLine1: '123 Mabini St',
      city: 'Makati',
      province: 'Metro Manila',
      zipCode: '1200',
    );

HiringEntity _buildHiringEntity() => const HiringEntity(
      id: 'c1',
      companyId: 'c1',
      code: 'LUX',
      name: 'LUXIUM TRADING CO.',
      hrManagerName: 'Brixter Del Mundo',
      city: 'Makati',
      province: 'Metro Manila',
    );
