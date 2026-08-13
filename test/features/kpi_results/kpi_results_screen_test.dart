import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/kpi_result.dart';
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
          kpiResultsForPeriodProvider('2026-08').overrideWith((ref) async => rows),
        ],
        child: const MaterialApp(home: KpiResultsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a NO_DATA row does not read the same as an OFF_TRACK row', (
    tester,
  ) async {
    // The whole point of the status rule, made visible. If these two ever
    // render identically the rule is correct and the screen still lies.
    await pump(tester, [
      _r(kpiId: 'k-miss', status: KpiStatus.noData),
      _r(kpiId: 'k-bad', status: KpiStatus.offTrack, value: 0.80, target: 0.99),
    ]);
    expect(find.text('No data'), findsOneWidget);
    expect(find.text('Off track'), findsOneWidget);
  });

  testWidgets('a NO_DATA row shows no invented value', (tester) async {
    await pump(tester, [_r(kpiId: 'k-miss', status: KpiStatus.noData)]);
    expect(find.text('0'), findsNothing);
    expect(find.text('0%'), findsNothing);
  });

  testWidgets('a month with no results says so', (tester) async {
    await pump(tester, const []);
    expect(find.textContaining('No results'), findsOneWidget);
  });
}
