import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/kpi.dart';
import 'package:payroll_flutter/data/repositories/role_scorecard_repository.dart';
import 'package:payroll_flutter/features/kpi_library/kpi_library_screen.dart';

void main() {
  testWidgets('groups KPIs by category', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        kpiLibraryProvider.overrideWith((ref) async => const [
          Kpi(id: '1', companyId: 'c', name: 'Retention', category: 'Sales'),
          Kpi(id: '2', companyId: 'c', name: 'Throughput', category: 'Ops'),
        ]),
      ],
      child: const MaterialApp(home: KpiLibraryScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Sales'), findsOneWidget);
    expect(find.text('Ops'), findsOneWidget);
    expect(find.text('Retention'), findsOneWidget);
  });
}
