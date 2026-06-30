import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/payroll/runs/detail/providers.dart';
import 'package:payroll_flutter/features/payroll/runs/detail/tabs/warnings_tab.dart';
import 'package:payroll_flutter/features/payroll/runs/detail/warnings.dart';

Widget _host(List<RunWarning> warnings) => ProviderScope(
      overrides: [
        runWarningsProvider('R1').overrideWith((ref) async => warnings),
      ],
      child: const MaterialApp(
        home: Scaffold(body: PayrollWarningsTab(runId: 'R1')),
      ),
    );

void main() {
  testWidgets('empty state shows the all-clear message', (tester) async {
    await tester.pumpWidget(_host(const []));
    await tester.pumpAndSettle();
    expect(find.text('No attendance warnings for this period.'), findsOneWidget);
  });

  testWidgets('populated state renders a warning row', (tester) async {
    await tester.pumpWidget(_host([
      RunWarning(
        employeeId: 'E1',
        employeeLabel: 'EMP-001 · Jane Doe',
        date: DateTime(2026, 6, 15),
        type: WarningType.missingClockOut,
        message: 'Clocked in at 9:02 AM but never clocked out.',
      ),
    ]));
    await tester.pumpAndSettle();
    expect(find.text('EMP-001 · Jane Doe'), findsOneWidget);
    expect(find.textContaining('never clocked out'), findsOneWidget);
    expect(find.text('1 warning'), findsOneWidget);
  });
}
