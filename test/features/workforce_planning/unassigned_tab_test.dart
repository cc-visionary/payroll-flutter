import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/data/repositories/role_scorecard_repository.dart';
import 'package:payroll_flutter/data/repositories/workforce_planning_repository.dart';
import 'package:payroll_flutter/features/workforce_planning/tabs/unassigned_tab.dart';
import 'package:payroll_flutter/features/workforce_planning/wp_providers.dart';

class _FakeRepo implements WorkforcePlanningRepository {
  final List<(String, bool)> archived = [];
  final List<(String, String?)> carded = [];
  @override
  Future<void> setTaskArchived(String id, bool a) async => archived.add((id, a));
  @override
  Future<void> setTaskCard(String id, String? c) async => carded.add((id, c));
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeCards implements RoleScorecardRepository {
  final List<(String, List<String>)> drafted = [];
  @override
  Future<String> createDraftRoleFromTasks({
      required String companyId, required String jobTitle, required List<String> taskIds}) async {
    drafted.add((jobTitle, taskIds));
    return 'new-card';
  }
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

final _card = RoleScorecard(
  id: 'rs1', companyId: 'c', jobTitle: 'Ops', missionStatement: '',
  responsibilities: const [], kpis: const [], wageType: 'MONTHLY',
  workHoursPerDay: 8, workDaysPerWeek: 'MON_FRI', isActive: true,
  effectiveDate: DateTime(2026, 1, 1));

const _p1 = WpTask(id: 'p1', companyId: 'c', name: 'Pack orders', hoursPerMonth: 10);
const _p2 = WpTask(id: 'p2', companyId: 'c', name: 'Pack the orders', hoursPerMonth: 5);

Widget _host(_FakeRepo repo, _FakeCards cards) => ProviderScope(
      overrides: [
        wpTasksProvider.overrideWith((ref) async => const [_p1, _p2]),
        wpActiveEmployeesProvider.overrideWith((ref) async => const []),
        wpAllTaskComputedProvider.overrideWith((ref) async => const [
              WpTaskComputed(taskId: 'p1', companyId: 'c', hoursPerMonthBase: 10),
              WpTaskComputed(taskId: 'p2', companyId: 'c', hoursPerMonthBase: 5),
            ]),
        wpGrowthMultiplierProvider.overrideWithValue(1.0),
        roleScorecardListProvider.overrideWith((ref) async => [_card]),
        workforcePlanningRepositoryProvider.overrideWithValue(repo),
        roleScorecardRepositoryProvider.overrideWithValue(cards),
      ],
      child: MaterialApp(
        home: Scaffold(body: SizedBox(width: 1200, height: 900, child: const UnassignedTab())),
      ),
    );

void main() {
  testWidgets('renders a cluster of the two similar orphans with total hours', (tester) async {
    await tester.pumpWidget(_host(_FakeRepo(), _FakeCards()));
    await tester.pumpAndSettle();
    expect(find.text('Pack orders'), findsWidgets);
    expect(find.textContaining('Propose role from these'), findsOneWidget);
  });

  testWidgets('Propose role drafts an inactive card from the cluster', (tester) async {
    final cards = _FakeCards();
    await tester.pumpWidget(_host(_FakeRepo(), cards));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Propose role from these'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Draft role'));
    await tester.pumpAndSettle();
    expect(cards.drafted, hasLength(1));
    expect(cards.drafted.single.$2.toSet(), {'p1', 'p2'});
  });
}
