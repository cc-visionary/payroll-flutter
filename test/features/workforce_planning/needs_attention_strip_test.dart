import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/features/workforce_planning/tabs/needs_attention_strip.dart';
import 'package:payroll_flutter/features/workforce_planning/wp_providers.dart';
import 'package:payroll_flutter/data/repositories/role_scorecard_repository.dart';

const _over = WpPersonLoad(employeeId: 'a', companyId: 'c', hoursFixed: 200, capacityHours: 160);

Widget _host({required bool withSignal}) => ProviderScope(
      overrides: [
        wpPersonLoadsProvider.overrideWith((ref) async => withSignal ? const [_over] : const []),
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
}
