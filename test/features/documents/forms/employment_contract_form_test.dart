import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/employee.dart';
import 'package:payroll_flutter/data/models/hiring_entity.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';
import 'package:payroll_flutter/data/repositories/employee_repository.dart';
import 'package:payroll_flutter/data/repositories/hiring_entity_repository.dart';
import 'package:payroll_flutter/data/repositories/role_scorecard_repository.dart';
import 'package:payroll_flutter/features/documents/forms/employment_contract_form.dart';
import 'package:payroll_flutter/features/documents/templates/employment_contract_inputs.dart';

EmploymentContractInputs _inputs() => EmploymentContractInputs(
      applicantId: 'app-00000001',
      employeeFullName: 'Jane Doe',
      employeeAddress: '1 Mabini St, Makati',
      companyId: '',
      companyName: '',
      companyAddress: '',
      representativeName: '',
      representativeRole: '',
      place: 'Makati',
      dateEntered: DateTime(2026, 6, 15),
      industry: 'Retail',
      position: 'Associate',
      monthlySalary: '695',
      salaryPeriod: 'day',
      workHoursPerDay: 8,
      workDaysPerWeek: 'Monday to Saturday',
      nonCompeteMonths: 24,
      employerSignatoryName: 'Brixter',
      employerSignatoryRole: 'HR Manager',
    );

Future<void> _pump(WidgetTester tester) async {
  // Tall viewport so the toggle and the fields below it are laid out at the
  // same time — the recycling bug only manifests among simultaneously-built
  // ListView children.
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        employeeListProvider(const EmployeeListQuery())
            .overrideWith((ref) => const <Employee>[]),
        hiringEntityListProvider.overrideWith((ref) => const <HiringEntity>[]),
        roleScorecardListProvider
            .overrideWith((ref) => const <RoleScorecard>[]),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: EmploymentContractForm(
            initial: _inputs(),
            employeeLocked: false,
            onChanged: (_) {},
            onEmployeeChanged: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'enabling graduated training wage shows the new fields\' own defaults, '
      'not values recycled from the fields below', (tester) async {
    await _pump(tester);

    // Toggle the graduated training wage on. This inserts two new TextFormFields
    // above "Work Hours per Day" / "Work Days per Week". Without stable keys,
    // Flutter recycles the existing fields' State (and their controllers) into
    // the new positions, leaking "8" and "Monday to Saturday" into the training
    // fields and shifting "24" up into Work Hours per Day.
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    // The training fields must display THEIR OWN seeded defaults.
    expect(find.text('350'), findsOneWidget,
        reason: 'Training daily rate must show its default 350, not "8"');
    expect(find.text('7'), findsOneWidget,
        reason: 'Training period must show its default 7, not "Monday to Saturday"');

    // And the field below must keep its real value (not the non-compete 24).
    expect(find.widgetWithText(TextFormField, '8'), findsOneWidget,
        reason: 'Work Hours per Day must still read 8, not 24');
  });
}
