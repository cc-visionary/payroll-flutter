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

  final noKpiSetCard = RoleScorecard(
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
  final noKpiSetHolder = Employee(
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

  Widget hostForNoKpiSet({
    required Map<String, Set<String>> roleKpiIdsByCard,
    required Map<String, Set<String>> assignedKpiIdsByEmployee,
  }) => ProviderScope(
    overrides: [
      wpPersonLoadsProvider.overrideWith((ref) async => const []),
      wpTasksProvider.overrideWith((ref) async => const []),
      wpActiveEmployeesProvider.overrideWith(
        (ref) async => [noKpiSetHolder],
      ),
      roleScorecardListProvider.overrideWith(
        (ref) async => [noKpiSetCard],
      ),
      kpiLibraryProvider.overrideWith((ref) async => const []),
      kpiAssignedEmployeesProvider.overrideWith((ref) async => const {}),
      wpKpiAssignmentMapsProvider.overrideWith(
        (ref) async => (
          roleKpiIdsByCard: roleKpiIdsByCard,
          assignedKpiIdsByEmployee: assignedKpiIdsByEmployee,
        ),
      ),
    ],
    child: const MaterialApp(
      home: Scaffold(
        body: DefaultTabController(length: 5, child: NeedsAttentionStrip()),
      ),
    ),
  );

  testWidgets(
    'no-KPI-set chip is absent when the holder tracks an on-role KPI',
    (tester) async {
      await tester.pumpWidget(
        hostForNoKpiSet(
          roleKpiIdsByCard: const {
            'card-1': {'k1'},
          },
          assignedKpiIdsByEmployee: const {
            'e1': {'k1'},
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('no KPI set'), findsNothing);
    },
  );

  testWidgets(
    'no-KPI-set chip is driven by wpKpiAssignmentMapsProvider — same '
    'employee/card as the previous case, only the maps differ — and '
    'deep-links to Roles',
    (tester) async {
      await tester.pumpWidget(
        hostForNoKpiSet(
          roleKpiIdsByCard: const {
            'card-1': {'k1'},
          },
          // Nobody assigned -> the holder's on-role set is empty.
          assignedKpiIdsByEmployee: const {},
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1 person has no KPI set'), findsOneWidget);

      final controller = DefaultTabController.of(
        tester.element(find.text('1 person has no KPI set')),
      );
      expect(controller.index, 0);
      await tester.tap(find.text('1 person has no KPI set'));
      await tester.pumpAndSettle();
      expect(
        controller.index,
        1,
        reason: 'a roles-target chip must switch to the Roles tab',
      );
    },
  );

  // Absent maps are NOT empty maps. Empty roleKpiIdsByCard makes every
  // holder's on-role intersection empty, so treating an unresolved provider
  // as empty reads the MAXIMUM — every ACTIVE holder in the company — rather
  // than zero. A spinner or an RLS denial upstream must not be able to tell
  // HR that nobody in the company has a KPI set.
  testWidgets(
    'no-KPI-set chip stays silent while the assignment maps are unresolved',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            // One unrelated gap so the strip itself renders and the absence
            // of the KPI chip is a real assertion, not a blank widget.
            wpPersonLoadsProvider.overrideWith((ref) async => const [_over]),
            wpTasksProvider.overrideWith((ref) async => const []),
            wpActiveEmployeesProvider.overrideWith(
              (ref) async => [noKpiSetHolder],
            ),
            roleScorecardListProvider.overrideWith(
              (ref) async => [noKpiSetCard],
            ),
            kpiLibraryProvider.overrideWith((ref) async => const []),
            kpiAssignedEmployeesProvider.overrideWith((ref) async => const {}),
            wpKpiAssignmentMapsProvider.overrideWith(
              (ref) async => throw Exception('RLS denied'),
            ),
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
      expect(
        find.text('Needs attention'),
        findsOneWidget,
        reason: 'the strip still renders its other signals',
      );
      expect(find.textContaining('no KPI set'), findsNothing);
    },
  );

  // Guards the wiring itself: `areaCountBySeat` and `holderCountBySeat` are
  // computed in NeedsAttentionStrip from `areasBySeat(tasks)` and
  // `seatBoxes(...)` and passed to buildNeedsAttention. If that wiring were
  // ever dropped (both args replaced with `const {}`), buildNeedsAttention's
  // defaults would silently read zero and this test must fail.
  final oversizedCard = RoleScorecard(
    id: 'rs1',
    companyId: 'c',
    jobTitle: 'Oversized Seat',
    missionStatement: '',
    responsibilities: const [],
    kpis: const [],
    wageType: 'MONTHLY',
    workHoursPerDay: 8,
    workDaysPerWeek: 'MON_FRI',
    isActive: true,
    effectiveDate: DateTime(2026),
  );
  final openCard = RoleScorecard(
    id: 'rs2',
    companyId: 'c',
    jobTitle: 'Open Seat',
    missionStatement: '',
    responsibilities: const [],
    kpis: const [],
    wageType: 'MONTHLY',
    workHoursPerDay: 8,
    workDaysPerWeek: 'MON_FRI',
    isActive: true,
    effectiveDate: DateTime(2026),
  );
  final oversizedHolder = Employee(
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
    'flags a seat with more than five authored roles, and a seat with no '
    'ACTIVE holder, with their real counts',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            wpPersonLoadsProvider.overrideWith((ref) async => const []),
            // rs1 authors 6 distinct responsibility areas -> oversized.
            // rs2 authors none, and (below) has no holder -> open.
            wpTasksProvider.overrideWith(
              (ref) async => [
                for (var i = 1; i <= 6; i++)
                  WpTask(
                    id: 't$i',
                    companyId: 'c',
                    name: 'Task $i',
                    roleScorecardId: 'rs1',
                    responsibilityArea: 'Area $i',
                  ),
              ],
            ),
            // rs1 is staffed (so it trips ONLY the oversized signal); rs2 has
            // no holder at all (so it trips ONLY the open-seat signal).
            wpActiveEmployeesProvider.overrideWith(
              (ref) async => [oversizedHolder],
            ),
            roleScorecardListProvider.overrideWith(
              (ref) async => [oversizedCard, openCard],
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
      expect(find.text('1 seat with more than five roles'), findsOneWidget);
      expect(find.text('1 open seat'), findsOneWidget);
    },
  );
}
