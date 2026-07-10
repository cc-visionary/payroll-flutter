import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/repositories/compensation_change_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('releasedPayrollFrom', () {
    test('maps the RPC guard error, carrying the run period from the hint', () {
      final err = PostgrestException(
        message: 'RELEASED_PAYROLL',
        hint: '2026-07-01 to 2026-07-31',
      );
      final mapped = releasedPayrollFrom(err);
      expect(mapped, isNotNull);
      expect(mapped!.runPeriod, '2026-07-01 to 2026-07-31');
    });

    test('returns null for any other Postgrest error', () {
      final err = PostgrestException(message: 'CHANGE_NOT_FOUND');
      expect(releasedPayrollFrom(err), isNull);
    });

    test('returns null for a non-Postgrest error', () {
      expect(releasedPayrollFrom(StateError('boom')), isNull);
    });

    test('maps the guard error with no hint to a null runPeriod', () {
      final err = PostgrestException(message: 'RELEASED_PAYROLL');
      final mapped = releasedPayrollFrom(err);
      expect(mapped, isNotNull);
      expect(mapped!.runPeriod, isNull);
    });
  });

  group('deleteForbiddenFrom', () {
    test('maps the RPC DELETE_FORBIDDEN sentinel', () {
      final err = PostgrestException(message: 'DELETE_FORBIDDEN');
      expect(deleteForbiddenFrom(err), isNotNull);
    });

    test('does not map RELEASED_PAYROLL to DeleteForbiddenException', () {
      final err = PostgrestException(
        message: 'RELEASED_PAYROLL',
        hint: '2026-07-01 to 2026-07-31',
      );
      expect(deleteForbiddenFrom(err), isNull);
    });
  });
}
