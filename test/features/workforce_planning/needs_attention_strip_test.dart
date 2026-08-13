import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/employee.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/features/workforce_planning/tabs/needs_attention_strip.dart';
import 'package:payroll_flutter/features/workforce_planning/wp_providers.dart';
import 'package:payroll_flutter/data/repositories/role_scorecard_repository.dart';

const _over = WpPersonLoad(
  employeeId: 'a',
  companyId: 'c',
  hoursFixed: 200,
  capacityHours: 160,
);

Widget _host({required bool withSignal}) => ProviderScope(
  overrides: [
    wpPersonLoadsProvider.overrideWith(
      (ref) async => withSignal ? const [_over] : const [],
    ),
    wpTasksProvider.overrideWith((ref) async => const []),
    wpActiveEmployeesProvider.overrideWith((ref) async => const []),
    roleScorecardListProvider.overrideWith((ref) async => const []),
    kpiLibraryProvider.overrideWith((ref) async => const []),
    kpiAssignedEmployeesProvider.overrideWith((ref) async => const {}),
  ],
  child: const MaterialApp(
    home: Scaffold(
      body: DefaultTabController(length: 5, child: NeedsAttentionStrip()),
    ),
  ),
);

void main() {
  testWidgets('renders nothing when there are no gaps', (tester) async {
    await tester.pumpWidget(_host(withSignal: false));
    await tester.pumpAndSettle();
    expect(find.textContaining('over capacity'), findsNothing);
    expect(find.text('Needs attention'), findsNothing);
  });

  testWidgets('surfaces an over-capacity gap under People', (tester) async {
    await tester.pumpWidget(_host(withSignal: true));
    await tester.pumpAndSettle();
    expect(find.text('Needs attention'), findsOneWidget);
    expect(find.textContaining('over capacity'), findsOneWidget);
  });

  testWidgets('tapping a chip deep-links to the right hub tab', (tester) async {
    late TabController controller;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          wpPersonLoadsProvider.overrideWith((ref) async => const []),
          wpTasksProvider.overrideWith(
            (ref) async => const [
              WpTask(id: 't', companyId: 'c', name: 'Orphan'),
            ],
          ),
          wpActiveEmployeesProvider.overrideWith((ref) async => const []),
          roleScorecardListProvider.overrideWith((ref) async => const []),
          kpiLibraryProvider.overrideWith((ref) async => const []),
          kpiAssignedEmployeesProvider.overrideWith((ref) async => const {}),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: DefaultTabController(
              length: 5,
              child: Builder(
                builder: (ctx) {
                  controller = DefaultTabController.of(ctx);
                  return const NeedsAttentionStrip();
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.index, 0);
    await tester.tap(find.text('1 responsibility unassigned'));
    await tester.pumpAndSettle();
    expect(
      controller.index,
      4,
      reason: 'unassigned chip must switch to the Unassigned tab',
    );
  });

  // Pure inheritance: a person's KPIs are their role's KPIs, so the gap that
  // used to be a PERSON'S ("N people have no KPI set", requiring the
  // person's stored subset to be read separately from the role) is now the
  // ROLE'S — read straight off `card.kpis`, the same embed the "N roles with
  // no department" signal below already reads.
  final noKpiCard = RoleScorecard(
    id: 'card-1',
    companyId: 'c',
    jobTitle: 'Card',
    missionStatement: '',
    responsibilities: const [],
    kpis: const [],
    wageType: 'MONTHLY',
    workHoursPerDay: 8,
    workDaysPerWeek: 'MON_FRI',
    isActive: true,
    effectiveDate: DateTime(2026),
  );
  final withKpiCard = RoleScorecard(
    id: 'card-2',
    companyId: 'c',
    jobTitle: 'Card With KPI',
    missionStatement: '',
    responsibilities: const [],
    kpis: const [
      KpiItem(name: 'Return Rate', measurement: '%', target: '', frequency: 'Weekly'),
    ],
    wageType: 'MONTHLY',
    workHoursPerDay: 8,
    workDaysPerWeek: 'MON_FRI',
    isActive: true,
    effectiveDate: DateTime(2026),
  );

  testWidgets(
    'no-KPI chip is absent when the role has a KPI',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            wpPersonLoadsProvider.overrideWith((ref) async => const []),
            wpTasksProvider.overrideWith((ref) async => const []),
            wpActiveEmployeesProvider.overrideWith((ref) async => const []),
            roleScorecardListProvider.overrideWith(
              (ref) async => [withKpiCard],
            ),
            kpiLibraryProvider.overrideWith((ref) async => const []),
            kpiAssignedEmployeesProvider.overrideWith((ref) async => const {}),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: DefaultTabController(length: 5, child: NeedsAttentionStrip()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('with no KPI'), findsNothing);
    },
  );

  testWidgets(
    'flags a role with no KPI, and deep-links to Roles — counted per role, '
    'not per holder',
    (tester) async {
      final holder = Employee(
        id: 'e1',
        companyId: 'c',
        employeeNumber: 'e1',
        firstName: 'One',
        lastName: 'X',
        roleScorecardId: 'card-1',
        employmentType: 'FULL_TIME',
        employmentStatus: 'ACTIVE',
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
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            wpPersonLoadsProvider.overrideWith((ref) async => const []),
            wpTasksProvider.overrideWith((ref) async => const []),
            wpActiveEmployeesProvider.overrideWith((ref) async => [holder]),
            roleScorecardListProvider.overrideWith(
              (ref) async => [noKpiCard],
            ),
            kpiLibraryProvider.overrideWith((ref) async => const []),
            kpiAssignedEmployeesProvider.overrideWith((ref) async => const {}),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: DefaultTabController(length: 5, child: NeedsAttentionStrip()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1 role with no KPI'), findsOneWidget);

      final controller = DefaultTabController.of(
        tester.element(find.text('1 role with no KPI')),
      );
      expect(controller.index, 0);
      await tester.tap(find.text('1 role with no KPI'));
      await tester.pumpAndSettle();
      expect(
        controller.index,
        1,
        reason: 'a roles-target chip must switch to the Roles tab',
      );
    },
  );

  // Guards the wiring itself: `holderCountByRole` is computed in
  // NeedsAttentionStrip from holderCountByRole(...) and passed to
  // buildNeedsAttention. If that wiring were ever dropped (the arg replaced
  // with `const {}`), buildNeedsAttention's default would silently read zero
  // and this test must fail.
  final heldCard = RoleScorecard(
    id: 'rs1',
    companyId: 'c',
    jobTitle: 'Held Role',
    missionStatement: '',
    responsibilities: const [],
    kpis: const [],
    wageType: 'MONTHLY',
    workHoursPerDay: 8,
    workDaysPerWeek: 'MON_FRI',
    isActive: true,
    effectiveDate: DateTime(2026),
  );
  final unfilledCard = RoleScorecard(
    id: 'rs2',
    companyId: 'c',
    jobTitle: 'Unfilled Role',
    missionStatement: '',
    responsibilities: const [],
    kpis: const [],
    wageType: 'MONTHLY',
    workHoursPerDay: 8,
    workDaysPerWeek: 'MON_FRI',
    isActive: true,
    effectiveDate: DateTime(2026),
  );
  final holder = Employee(
    id: 'h1',
    companyId: 'c',
    employeeNumber: 'h1',
    firstName: 'Holder',
    lastName: 'X',
    roleScorecardId: 'rs1',
    employmentType: 'FULL_TIME',
    employmentStatus: 'ACTIVE',
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

  testWidgets(
    'flags a role with no ACTIVE holder, with its real count',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            wpPersonLoadsProvider.overrideWith((ref) async => const []),
            wpTasksProvider.overrideWith((ref) async => const []),
            // rs1 is staffed; rs2 has no holder at all, so exactly one role
            // is unfilled -- a count of 2 would mean the filter is ignoring
            // holders, and 0 would mean the wiring was dropped.
            wpActiveEmployeesProvider.overrideWith((ref) async => [holder]),
            roleScorecardListProvider.overrideWith(
              (ref) async => [heldCard, unfilledCard],
            ),
            kpiLibraryProvider.overrideWith((ref) async => const []),
            kpiAssignedEmployeesProvider.overrideWith((ref) async => const {}),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: DefaultTabController(
                length: 5,
                child: NeedsAttentionStrip(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1 role nobody holds'), findsOneWidget);
    },
  );
}
