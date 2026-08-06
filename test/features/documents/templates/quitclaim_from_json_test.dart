import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:payroll_flutter/features/documents/templates/quitclaim_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/quitclaim_template.dart';

void main() {
  group('QuitclaimInputs.fromJson', () {
    final full = QuitclaimInputs(
      employeeId: 'EMP-1',
      employeeFullName: 'Jane Doe',
      employeeAddress: '1 Main St, Quezon City',
      civilStatus: 'married',
      companyId: 'CO-1',
      companyName: 'Acme Corp',
      finalPayAmount: Decimal.parse('45678.90'),
      dateTerminated: DateTime.utc(2026, 5, 31),
      dateSigned: DateTime.utc(2026, 6, 15, 10, 0),
      placeSigned: 'Makati City',
    );

    final empty = QuitclaimInputs(
      employeeId: 'EMP-2',
      employeeFullName: 'John Roe',
      companyId: 'CO-2',
      companyName: 'Beta Inc',
      finalPayAmount: Decimal.zero,
      // nullable date null, optionals left default
      dateTerminated: null,
      dateSigned: DateTime.utc(2026, 6, 16),
    );

    test('round-trips toJson (full sample)', () {
      expect(QuitclaimInputs.fromJson(full.toJson()).toJson(), full.toJson());
    });

    test('round-trips toJson (null/empty sample)', () {
      expect(QuitclaimInputs.fromJson(empty.toJson()).toJson(), empty.toJson());
    });

    test('rebuilds blocks', () {
      expect(
        const QuitclaimTemplate().build(
          QuitclaimInputs.fromJson(full.toJson()),
        ),
        isNotEmpty,
      );
    });
  });
}
