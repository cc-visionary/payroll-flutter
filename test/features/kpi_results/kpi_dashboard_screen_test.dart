import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:payroll_flutter/data/models/kpi_result.dart';
import 'package:payroll_flutter/features/kpi_results/kpi_dashboard_screen.dart';
import 'package:payroll_flutter/features/kpi_results/kpi_results_screen.dart';

import '../../support/supabase_stub.dart';

KpiResult _r({
  required String kpiId,
  required KpiStatus status,
  num? value,
  num? target,
}) => KpiResult(
  id: 'res-$kpiId',
  companyId: 'c',
  kpiId: kpiId,
  period: '2026-08',
  scope: KpiScope.company,
  value: value,
  targetSnapshot: target,
  status: status,
  sourceCompleteness: status == KpiStatus.noData
      ? SourceCompleteness.missingSource
      : SourceCompleteness.complete,
);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initSupabaseStub();
  });

  Future<void> pump(WidgetTester tester, List<KpiResult> rows) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          kpiResultsForPeriodProvider(
            '2026-08',
          ).overrideWith((ref) async => rows),
        ],
        child: const MaterialApp(home: KpiDashboardScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('off-track sorts first, then no-data, then on-track', (
    tester,
  ) async {
    // Feed them in the WRONG order deliberately -- asserting the order you
    // supplied proves nothing about the sort.
    await pump(tester, [
      _r(kpiId: 'k-ok', status: KpiStatus.onTrack, value: 1, target: 0.9),
      _r(kpiId: 'k-miss', status: KpiStatus.noData),
      _r(kpiId: 'k-bad', status: KpiStatus.offTrack, value: 0.1, target: 0.9),
    ]);
    final chips = tester
        .widgetList<Text>(find.byKey(const ValueKey('kpi-status-label')))
        .map((t) => t.data)
        .toList();
    expect(chips, ['Off track', 'No data', 'On track']);
  });

  // UNTESTED SEAM, recorded rather than papered over: this fixture has
  // exactly one row per status, so there is no tie for the sort to break.
  // This test can tell "status-correct" apart from "status-wrong", but it
  // cannot distinguish "status-correct AND deterministic within a status"
  // from "status-correct but arbitrary within a status" -- two rows sharing
  // one status would need to appear in the same relative order on every
  // read to prove the latter, and that determinism is a property of
  // `KpiResultRepository.listByPeriod`'s query-level `ORDER BY` (see its doc
  // comment), not of anything a widget test can observe by mocking the
  // provider directly. `kpi_result_repository_test.dart` pins the query side
  // (the outgoing request carries a total `order` clause); nothing pins the
  // composition of the two end to end, because doing so would mean either
  // asserting on Postgres' actual row-return order (not observable from
  // Dart) or writing a same-status-tie assertion this fixture's mocked
  // provider would satisfy regardless of whether the query orders anything --
  // exactly the kind of test that passes for a reason other than its stated
  // one.

  testWidgets('a month with nothing computed is empty, not red', (
    tester,
  ) async {
    await pump(tester, const []);
    expect(find.textContaining('Nothing computed'), findsOneWidget);
    expect(find.text('Off track'), findsNothing);
  });
}
