import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/widgets/pending_migration_notice.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The real thing, verbatim from the failing screen — table name, code and
/// the misleading hint included, so this test breaks if the shape changes.
final _missingTable = PostgrestException(
  message: "Could not find the table 'public.kpi_results' in the schema cache",
  code: 'PGRST205',
  details: 'Not Found',
  hint: "Perhaps you meant the table 'public.review_kpi_results'",
);

final _missingColumn = PostgrestException(
  message: "Could not find the 'level' column of 'kpis' in the schema cache",
  code: 'PGRST204',
);

Future<void> _pump(WidgetTester tester, Object error) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PendingMigrationNotice(error: error, feature: 'KPI results'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('a pending migration reads as pending, not as a crash', () {
    testWidgets('a missing table explains itself and names the remedy', (
      tester,
    ) async {
      await _pump(tester, _missingTable);
      expect(find.text('KPI results is not set up yet'), findsOneWidget);
      expect(find.textContaining('supabase db push'), findsOneWidget);
    });

    testWidgets('a missing column counts too', (tester) async {
      // PGRST204 is what an unapplied ALTER TABLE looks like, and it means
      // the same thing to the person reading the screen.
      await _pump(tester, _missingColumn);
      expect(find.text('KPI results is not set up yet'), findsOneWidget);
    });

    testWidgets('the raw error stays reachable, not discarded', (tester) async {
      // Whoever runs the migration wants the exact code; burying it entirely
      // would trade one unhelpful screen for another.
      await _pump(tester, _missingTable);
      expect(find.text('Technical details'), findsOneWidget);
      await tester.tap(find.text('Technical details'));
      await tester.pumpAndSettle();
      expect(find.textContaining('PGRST205'), findsOneWidget);
    });
  });

  group('a real fault is NOT dressed up as a pending migration', () {
    testWidgets('a permission error shows as an error', (tester) async {
      // The dangerous failure this widget could introduce: a genuine fault
      // wearing a reassuring message, so nobody investigates. RLS denials,
      // constraint violations and network failures must all still read as
      // errors.
      await _pump(
        tester,
        PostgrestException(
          message: 'permission denied for table kpi_results',
          code: '42501',
        ),
      );
      expect(find.textContaining('not set up yet'), findsNothing);
      expect(find.textContaining('permission denied'), findsOneWidget);
    });

    testWidgets('a constraint violation shows as an error', (tester) async {
      await _pump(
        tester,
        PostgrestException(
          message: 'duplicate key value violates unique constraint',
          code: '23505',
        ),
      );
      expect(find.textContaining('not set up yet'), findsNothing);
    });

    testWidgets('a plain exception shows as an error', (tester) async {
      await _pump(tester, Exception('socket closed'));
      expect(find.textContaining('not set up yet'), findsNothing);
      expect(find.textContaining('socket closed'), findsOneWidget);
    });
  });

  group('isPendingMigrationError', () {
    test('accepts only the two schema-cache codes', () {
      expect(isPendingMigrationError(_missingTable), isTrue);
      expect(isPendingMigrationError(_missingColumn), isTrue);
      expect(
        isPendingMigrationError(
          PostgrestException(message: 'nope', code: '42501'),
        ),
        isFalse,
      );
      expect(
        isPendingMigrationError(
          PostgrestException(message: 'no code at all'),
        ),
        isFalse,
      );
      expect(isPendingMigrationError(Exception('x')), isFalse);
      expect(isPendingMigrationError('a bare string'), isFalse);
    });
  });
}
