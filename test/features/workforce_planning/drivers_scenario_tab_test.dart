import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/features/workforce_planning/tabs/drivers_scenario_tab.dart';
import 'package:payroll_flutter/features/workforce_planning/wp_providers.dart';

void main() {
  testWidgets('renders drivers, rates, and the current multiplier', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          wpDriversProvider.overrideWith(
            (ref) async => const [
              WpDriver(
                id: 'd1',
                companyId: 'c',
                name: 'Shopee orders',
                value: 120,
                grows: true,
              ),
            ],
          ),
          wpRatesProvider.overrideWith(
            (ref) async => const [
              WpRate(
                id: 'r1',
                companyId: 'c',
                name: 'SD flash',
                minutesEach: 12,
              ),
            ],
          ),
          wpConfigProvider.overrideWith(
            (ref) async => const WpConfig(
              companyId: 'c',
              growthMultiplier: 2,
              defaultCapacityHours: 160,
            ),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: DriversScenarioTab())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Shopee orders'), findsOneWidget);
    expect(find.text('SD flash'), findsOneWidget);
    expect(find.textContaining('2'), findsWidgets); // multiplier shown
  });
}
