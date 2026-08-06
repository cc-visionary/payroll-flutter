import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/employee.dart';
import 'package:payroll_flutter/data/repositories/employee_repository.dart';
import 'package:payroll_flutter/features/performance/new_check_in_dialog.dart';

Employee _emp(String id, String first, String last) => Employee(
  id: id,
  companyId: 'c1',
  employeeNumber: id,
  firstName: first,
  lastName: last,
  employmentType: 'REGULAR',
  employmentStatus: 'ACTIVE',
  hireDate: DateTime.utc(2024, 1, 1),
  isRankAndFile: true,
  isOtEligible: true,
  isNdEligible: true,
  isHolidayPayEligible: true,
  taxOnFullEarnings: false,
);

Future<void> _openDialog(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        employeeListProvider(const EmployeeListQuery()).overrideWith(
          (ref) async => [_emp('1', 'Ann', 'Cruz'), _emp('2', 'Ben', 'Diaz')],
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showNewCheckInDialog(context: context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('dialog renders without layout/hit-test errors', (tester) async {
    await _openDialog(tester);
    expect(find.text('New check-in'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hovering a mouse over the dialog does not crash', (
    tester,
  ) async {
    await _openDialog(tester);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    // Sweep the pointer across the dialog surface.
    await gesture.moveTo(tester.getCenter(find.text('New check-in')));
    await tester.pump();
    await gesture.moveTo(tester.getCenter(find.byType(AlertDialog)));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('opening the employee dropdown does not crash', (tester) async {
    await _openDialog(tester);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // Pick the second employee from the opened menu.
    await tester.tap(find.text('Ben Diaz').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
