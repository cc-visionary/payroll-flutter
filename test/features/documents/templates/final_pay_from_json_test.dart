import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:payroll_flutter/features/documents/templates/final_pay_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/final_pay_template.dart';

void main() {
  group('FinalPayInputs.fromJson', () {
    final full = FinalPayInputs(
      employeeId: 'EMP-1',
      employeeFullName: 'Jane Doe',
      employeePosition: 'Analyst',
      employeeHireDate: DateTime.utc(2024, 1, 15),
      employeeSeparationDate: DateTime.utc(2026, 5, 31),
      companyId: 'CO-1',
      companyName: 'Acme Corp',
      companyAddress: '2 Side St, Manila',
      hrManagerName: 'Brixter',
      lastNetPay: Decimal.parse('12345.67'),
      thirteenthMonth: Decimal.parse('8000.50'),
      unusedLeaveConversion: Decimal.parse('1500.25'),
      outstandingCashAdvance: Decimal.parse('2000.00'),
      otherDeductions: Decimal.parse('300.10'),
      otherDeductionsLabel: 'Lost ID replacement',
      lastNetPayLocked: true,
      thirteenthMonthLocked: false,
      unusedLeaveConversionLocked: true,
      outstandingCashAdvanceLocked: false,
      computedAsOf: DateTime.utc(2026, 6, 1, 9, 30),
      releaseDate: DateTime.utc(2026, 6, 15),
    );

    final empty = FinalPayInputs(
      employeeId: 'EMP-2',
      employeeFullName: 'John Roe',
      companyId: 'CO-2',
      companyName: 'Beta Inc',
      // nullable dates null, money omitted (defaults to Decimal.zero),
      // locks default false, labels default ''
      employeeHireDate: null,
      employeeSeparationDate: null,
      computedAsOf: DateTime.utc(2026, 6, 2),
      releaseDate: DateTime.utc(2026, 6, 16),
    );

    test('round-trips toJson (full sample)', () {
      expect(FinalPayInputs.fromJson(full.toJson()).toJson(), full.toJson());
    });

    test('round-trips toJson (null/empty sample)', () {
      expect(FinalPayInputs.fromJson(empty.toJson()).toJson(), empty.toJson());
    });

    test('rebuilds blocks', () {
      expect(
        const FinalPayTemplate().build(FinalPayInputs.fromJson(full.toJson())),
        isNotEmpty,
      );
    });
  });
}
