import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/employee.dart';
import 'package:payroll_flutter/data/models/hiring_entity.dart';
import 'package:payroll_flutter/features/documents/templates/document_template.dart';
import 'package:payroll_flutter/features/documents/templates/non_reg_template.dart';

void main() {
  test('template metadata', () {
    const t = NonRegTemplate();
    expect(t.id, 'non_reg');
    expect(t.name, 'Notice of Non-Regularization');
    expect(t.version, 1);
  });

  test('emptyInputs has empty findings and today as dateIssued', () {
    const t = NonRegTemplate();
    final i = t.emptyInputs();
    expect(i.findings, isEmpty);
    expect(i.employeeId, isEmpty);
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
    const t = NonRegTemplate();
    final filled = await t.autofill(
      AutofillContext(employee: emp, company: co, ref: capturedRef),
    );
    expect(filled.employeeId, 'e1');
    expect(filled.employeeFullName, 'Jamaica Vidal');
    expect(filled.employeeLastName, 'Vidal');
    expect(filled.companyId, 'c1');
    expect(filled.companyName, 'LUXIUM TRADING CO.');
    expect(filled.hrManagerName, 'Brixter Del Mundo');
    expect(filled.salutationName, 'Vidal');
  });
}

Employee _buildEmployee() => Employee(
      id: 'e1',
      companyId: 'c1',
      employeeNumber: 'EMP-001',
      firstName: 'Jamaica',
      lastName: 'Vidal',
      hiringEntityId: 'c1',
      employmentType: 'PROBATIONARY',
      employmentStatus: 'ACTIVE',
      hireDate: DateTime(2020, 1, 1),
      isRankAndFile: true,
      isOtEligible: true,
      isNdEligible: true,
      isHolidayPayEligible: true,
      taxOnFullEarnings: false,
    );

HiringEntity _buildHiringEntity() => const HiringEntity(
      id: 'c1',
      companyId: 'c1',
      code: 'LUX',
      name: 'LUXIUM TRADING CO.',
      hrManagerName: 'Brixter Del Mundo',
    );
