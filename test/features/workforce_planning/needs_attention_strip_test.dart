import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/employee.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/features/workforce_planning/tabs/needs_attention_strip.dart';
import 'package:payroll_flutter/features/workforce_planning/wp_providers.dart';
import 'package:payroll_flutter/data/repositories/role_scorecard_repository.dart';

RoleScorecard _card(String id, String title, {List<KpiItem> kpis = const []}) =>
    RoleScorecard(
      id: id,
      companyId: 'c',
      jobTitle: title,
      missionStatement: '',
      responsibilities: const [],
      kpis: kpis,
      wageType: 'MONTHLY',
      workHoursPerDay: 8,
      workDaysPerWeek: 'MON_FRI',
      isActive: true,
      effectiveDate: DateTime(2026),
    );

Employee _emp(String id, String roleId) => Employee(
  id: id,
  companyId: 'c',
  employeeNumber: id,
  firstName: id,
  lastName: 'X',
  roleScorecardId: roleId,
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

/// Hosts the strip in a 3-tab controller (Roles 0, Organization 1, All
/// tasks 2) starting on [initialIndex]; [onController] exposes it.
Widget _host({
  List<WpTask> tasks = const [],
  List<WpTaskComputed> computed = const [],
  List<Employee> employees = const [],
  List<RoleScorecard> cards = const [],
  int initialIndex = 0,
  void Function(TabController)? onController,
}) => ProviderScope(
  overrides: [
    wpPersonLoadsProvider.overrideWith((ref) async => const []),
    wpAllTaskComputedProvider.overrideWith((ref) async => computed),
    wpConfigProvider.overrideWith((ref) async => null),
    wpTasksProvider.overrideWith((ref) async => tasks),
    wpActiveEmployeesProvider.overrideWith((ref) async => employees),
    roleScorecardListProvider.overrideWith((ref) async => cards),
    kpiLibraryProvider.overrideWith((ref) async => const []),
    kpiAssignedEmployeesProvider.overrideWith((ref) async => const {}),
  ],
  child: MaterialApp(
    home: Scaffold(
      body: DefaultTabController(
        length: 3,
        initialIndex: initialIndex,
        child: Builder(
          builder: (ctx) {
            onController?.call(DefaultTabController.of(ctx));
            return const NeedsAttentionStrip();
          },
        ),
      ),
    ),
  ),
);

const _returnRate = KpiItem(
  name: 'Return Rate',
  measurement: '%',
  target: '',
  frequency: 'Weekly',
);

/// True when some InkWell above [label] handles taps. (StatusChip is a
/// Material chip with its own inert InkWell, so presence alone proves nothing.)
bool _tappable(WidgetTester tester, String label) => tester
    .widgetList<InkWell>(
      find.ancestor(of: find.text(label), matching: find.byType(InkWell)),
    )
    .any((w) => w.onTap != null);

void main() {
  testWidgets('renders nothing when there are no gaps', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    expect(find.textContaining('over capacity'), findsNothing);
    expect(find.text('Needs attention'), findsNothing);
  });

  testWidgets('surfaces an over-capacity role under People', (tester) async {
    // One holder at the 160h default, 200h of the role's work -> over.
    await tester.pumpWidget(
      _host(
        cards: [_card('rs1', 'Brand Handler', kpis: const [_returnRate])],
        employees: [_emp('ana', 'rs1')],
        tasks: const [
          WpTask(id: 't1', companyId: 'c', name: 'Pack', roleScorecardId: 'rs1'),
        ],
        computed: const [
          WpTaskComputed(taskId: 't1', companyId: 'c', hoursPerMonthBase: 200),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Needs attention'), findsOneWidget);
    expect(find.text('People'), findsOneWidget);
    expect(find.text('1 role over capacity'), findsOneWidget);
  });

  // The strip only renders on the Roles tab, so a Roles-target chip would be
  // a no-op link: it is shown as a plain, non-tappable chip instead (M2).
  testWidgets('a task with no role is a plain chip — the strip is already on Roles', (tester) async {
    await tester.pumpWidget(
      _host(
        tasks: const [
          WpTask(id: 't', companyId: 'c', name: 'Orphan', hoursPerMonth: 4),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 task with no role'), findsOneWidget);
    expect(_tappable(tester, '1 task with no role'), isFalse);
  });

  testWidgets('an uncosted chip deep-links to the All tasks tab', (
    tester,
  ) async {
    late TabController controller;
    await tester.pumpWidget(
      _host(
        tasks: const [WpTask(id: 't', companyId: 'c', name: 'Uncosted')],
        onController: (c) => controller = c,
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.index, 0);
    await tester.tap(find.text('1 essential responsibility uncosted'));
    await tester.pumpAndSettle();
    expect(controller.index, 2, reason: 'tasks chip must switch to All tasks');
  });

  testWidgets('a flagged task shows as "to check"', (tester) async {
    await tester.pumpWidget(
      _host(
        cards: [_card('rs1', 'Brand Handler', kpis: const [_returnRate])],
        employees: [_emp('ana', 'rs1')],
        tasks: const [
          WpTask(
            id: 't',
            companyId: 'c',
            name: 'Flagged',
            roleScorecardId: 'rs1',
            hoursPerMonth: 4,
            allocationReviewNote: 'was: split',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 task to check'), findsOneWidget);
  });

  testWidgets('no-KPI chip is absent when the role has a KPI', (tester) async {
    await tester.pumpWidget(
      _host(cards: [_card('card-2', 'Card With KPI', kpis: const [_returnRate])]),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('with no KPI'), findsNothing);
  });

  testWidgets(
    'flags a role with no KPI — counted per role, not per holder — as a '
    'plain (Roles-target) chip',
    (tester) async {
      await tester.pumpWidget(
        _host(
          cards: [_card('card-1', 'Card')],
          employees: [_emp('e1', 'card-1'), _emp('e2', 'card-1')],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1 role with no KPI'), findsOneWidget);
      expect(
        _tappable(tester, '1 role with no KPI'),
        isFalse,
        reason: 'a Roles-target chip is not a link on the Roles tab',
      );
    },
  );

  // Guards the wiring: holders come from the role loads the strip builds.
  // rs1 is staffed; rs2 has no holder, so exactly one role is unfilled — 2
  // would mean holders are ignored, 0 that the wiring was dropped.
  testWidgets('flags a role with no ACTIVE holder, with its real count', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        cards: [_card('rs1', 'Held Role'), _card('rs2', 'Unfilled Role')],
        employees: [_emp('h1', 'rs1')],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 role nobody holds'), findsOneWidget);
  });
}
