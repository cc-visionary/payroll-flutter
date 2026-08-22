import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/payroll_run.dart';
import 'package:payroll_flutter/features/auth/profile_provider.dart';
import 'package:payroll_flutter/features/payroll/runs/detail/providers.dart';
import 'package:payroll_flutter/features/payroll/runs/detail/tabs/payslips_tab.dart';

import '../../support/supabase_stub.dart';

/// Who may edit a run's roster, and when. The controls are also refused
/// server-side by PayrollRosterService — this pins the UI half so a RELEASED
/// run never offers a Remove the service would reject.
void main() {
  setUpAll(initSupabaseStub);

  PayrollRun run(String status) => PayrollRun.fromRow({
    'id': 'run-1',
    'company_id': 'co-1',
    'status': status,
    'period_start': '2026-08-01',
    'period_end': '2026-08-15',
    'pay_date': '2026-08-20',
    'created_at': '2026-08-01T00:00:00Z',
  });

  UserProfile profile(AppRole role) => UserProfile(
    userId: 'u-1',
    email: 'someone@example.com',
    companyId: 'co-1',
    employeeId: null,
    appRole: role,
    mustChangePassword: false,
  );

  final payslips = [
    {
      'id': 'ps-1',
      'employee_id': 'emp-1',
      'gross_pay': '0',
      'total_deductions': '250',
      'net_pay': '-250',
      'employees': {
        'id': 'emp-1',
        'employee_number': 'CHRIS',
        'first_name': 'Christopher',
        'last_name': 'Lim',
      },
    },
  ];

  Future<void> pump(
    WidgetTester tester, {
    required String status,
    required AppRole role,
    Size surface = const Size(1600, 1400),
  }) async {
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          payslipListForRunProvider(
            'run-1',
          ).overrideWith((ref) async => payslips),
          userProfileProvider.overrideWith((ref) async => profile(role)),
        ],
        child: MaterialApp(
          home: Scaffold(body: PayrollPayslipsTab(run: run(status))),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a REVIEW run offers Add Employee and a per-row menu', (
    tester,
  ) async {
    await pump(tester, status: 'REVIEW', role: AppRole.HR_ADMIN);
    expect(find.text('Add Employee'), findsOneWidget);
    expect(find.byIcon(Icons.more_vert), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('Remove from run'), findsOneWidget);
  });

  testWidgets('a DRAFT run offers them too', (tester) async {
    await pump(tester, status: 'DRAFT', role: AppRole.HR_ADMIN);
    expect(find.text('Add Employee'), findsOneWidget);
    expect(find.byIcon(Icons.more_vert), findsOneWidget);
  });

  testWidgets('a RELEASED run offers neither', (tester) async {
    // Released payroll is final; the roster must not be editable at all.
    await pump(tester, status: 'RELEASED', role: AppRole.HR_ADMIN);
    expect(find.text('Add Employee'), findsNothing);
    expect(find.byIcon(Icons.more_vert), findsNothing);
  });

  testWidgets('a CANCELLED run offers neither', (tester) async {
    await pump(tester, status: 'CANCELLED', role: AppRole.HR_ADMIN);
    expect(find.text('Add Employee'), findsNothing);
    expect(find.byIcon(Icons.more_vert), findsNothing);
  });

  testWidgets('the actions column still fits on a narrow window', (
    tester,
  ) async {
    // The row gained a second control; a RenderFlex overflow here would fail
    // the test, which is the point.
    await pump(
      tester,
      status: 'REVIEW',
      role: AppRole.HR_ADMIN,
      surface: const Size(800, 1200),
    );
    expect(find.byIcon(Icons.more_vert), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('BASELINE: no-menu row at the same narrow window', (
    tester,
  ) async {
    await pump(
      tester,
      status: 'REVIEW',
      role: AppRole.EMPLOYEE,
      surface: const Size(800, 1200),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a user who cannot run payroll offers neither', (tester) async {
    await pump(tester, status: 'REVIEW', role: AppRole.EMPLOYEE);
    expect(find.text('Add Employee'), findsNothing);
    expect(find.byIcon(Icons.more_vert), findsNothing);
  });
}
