import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/employee.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';
import 'package:payroll_flutter/data/repositories/role_scorecard_repository.dart';
import 'package:payroll_flutter/features/workforce_planning/accountability_chart_screen.dart';
import 'package:payroll_flutter/features/workforce_planning/wp_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/supabase_stub.dart';

RoleScorecard _seat(String id, String title, {String? parentId}) =>
    RoleScorecard(
      id: id,
      companyId: 'c',
      jobTitle: title,
      missionStatement: '',
      responsibilities: const [],
      kpis: const [],
      baseSalary: null,
      wageType: 'DAILY',
      workHoursPerDay: 8,
      workDaysPerWeek: 'MON_FRI',
      isActive: true,
      effectiveDate: DateTime(2026, 1, 1),
      parentId: parentId,
    );

Employee _emp(
  String id,
  String first,
  String last,
  String? seatId, {
  String status = 'ACTIVE',
}) => Employee(
  id: id,
  companyId: 'c',
  employeeNumber: id,
  firstName: first,
  lastName: last,
  roleScorecardId: seatId,
  employmentType: 'FULL_TIME',
  employmentStatus: status,
  hireDate: DateTime(2024, 1, 1),
  isRankAndFile: true,
  isOtEligible: false,
  isNdEligible: false,
  isHolidayPayEligible: false,
  sssEligibilityOverride: false,
  philhealthEligibilityOverride: false,
  pagibigEligibilityOverride: false,
  taxOnFullEarnings: false,
);

/// Records calls instead of hitting the network, mirroring
/// `_CapturingRepository` in `kpis_pane_test.dart`.
class _CapturingRepository extends RoleScorecardRepository {
  _CapturingRepository() : super(Supabase.instance.client);
  final calls = <(String, String?)>[];

  @override
  Future<void> updateParent(String seatId, String? parentId) async {
    calls.add((seatId, parentId));
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initSupabaseStub();
  });

  Future<void> pump(
    WidgetTester tester, {
    required List<RoleScorecard> seats,
    List<Employee> employees = const [],
    RoleScorecardRepository? repo,
  }) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          roleScorecardListProvider.overrideWith((ref) async => seats),
          wpActiveEmployeesProvider.overrideWith((ref) async => employees),
          wpTasksProvider.overrideWith((ref) async => const []),
          if (repo != null)
            roleScorecardRepositoryProvider.overrideWithValue(repo),
        ],
        child: const MaterialApp(home: AccountabilityChartScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a seat with two holders renders two boxes', (tester) async {
    await pump(
      tester,
      seats: [_seat('s1', 'Brand Handling')],
      employees: [
        _emp('e1', 'Christian', 'Ong', 's1'),
        _emp('e2', 'Evander', 'Cruz', 's1'),
      ],
    );
    expect(find.text('Christian Ong'), findsOneWidget);
    expect(find.text('Evander Cruz'), findsOneWidget);
  });

  testWidgets('a seat with no holder renders one OPEN SEAT box', (
    tester,
  ) async {
    await pump(tester, seats: [_seat('s1', 'Marketing')], employees: const []);
    expect(find.text('OPEN SEAT'), findsOneWidget);
  });

  testWidgets('a child seat renders beneath its parent', (tester) async {
    await pump(
      tester,
      seats: [
        _seat('root', 'Visionary'),
        _seat('child', 'Sourcing', parentId: 'root'),
      ],
      employees: [
        _emp('e1', 'Clint', 'Yu', 'root'),
        _emp('e2', 'Al', 'Ong', 'child'),
      ],
    );
    expect(find.text('Clint Yu'), findsOneWidget);
    expect(find.text('Al Ong'), findsOneWidget);
    final parentY = tester.getTopLeft(find.text('Clint Yu')).dy;
    final childY = tester.getTopLeft(find.text('Al Ong')).dy;
    expect(
      childY,
      greaterThan(parentY),
      reason: 'the child seat must render below its parent',
    );
  });

  testWidgets('an unparented seat renders as a root, not disappearing', (
    tester,
  ) async {
    await pump(
      tester,
      seats: [_seat('orphan', 'Odd Function', parentId: 'does-not-exist')],
      employees: [_emp('e1', 'Nia', 'Reyes', 'orphan')],
    );
    expect(find.text('Nia Reyes'), findsOneWidget);
  });

  testWidgets('states plainly what the chart is, and what it is not', (
    tester,
  ) async {
    await pump(tester, seats: [_seat('s1', 'Marketing')]);
    expect(
      find.textContaining('functions and who owns them'),
      findsOneWidget,
    );
    expect(find.textContaining('Workforce Planning'), findsOneWidget);
  });

  testWidgets('a legal re-parent drag saves immediately', (tester) async {
    final repo = _CapturingRepository();
    await pump(
      tester,
      seats: [
        _seat('root', 'Visionary'),
        _seat('child', 'Sourcing'), // starts unparented
      ],
      employees: [
        _emp('e1', 'Clint', 'Yu', 'root'),
        _emp('e2', 'Al', 'Ong', 'child'),
      ],
      repo: repo,
    );

    final from = tester.getCenter(find.text('Al Ong'));
    final to = tester.getCenter(find.text('Clint Yu'));
    final g = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 100));
    await g.moveTo(to);
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();

    expect(repo.calls, [('child', 'root')]);
  });

  testWidgets('a drop refused by seatDropError leaves the data untouched', (
    tester,
  ) async {
    final repo = _CapturingRepository();
    await pump(
      tester,
      seats: [
        _seat('root', 'Visionary'),
        _seat('child', 'Sourcing', parentId: 'root'),
      ],
      employees: [
        _emp('e1', 'Clint', 'Yu', 'root'),
        _emp('e2', 'Al', 'Ong', 'child'),
      ],
      repo: repo,
    );

    // Drag the parent onto its own child — a cycle, refused.
    final from = tester.getCenter(find.text('Clint Yu'));
    final to = tester.getCenter(find.text('Al Ong'));
    final g = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 100));
    await g.moveTo(to);
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();

    expect(repo.calls, isEmpty);
    expect(find.textContaining('loop'), findsOneWidget);
  });
}
