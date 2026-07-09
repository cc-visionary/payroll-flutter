import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/payroll/engine/daily_rate.dart';

Decimal _d(String s) => Decimal.parse(s);

void main() {
  test('manual present wins over a non-null, different compensation-derived rate', () {
    final r = resolveDailyRateOverride(
      manualRaw: '1500',
      compensationDerived: _d('1153.846'),
    );
    expect(r, _d('1500'));
  });

  test('manual null -> compensation-derived returned', () {
    final r = resolveDailyRateOverride(
      manualRaw: null,
      compensationDerived: _d('1153.846'),
    );
    expect(r, _d('1153.846'));
  });

  test('manual present but unparseable -> falls through to compensation-derived', () {
    final r = resolveDailyRateOverride(
      manualRaw: 'abc',
      compensationDerived: _d('1153.846'),
    );
    expect(r, _d('1153.846'));
  });

  test('both null -> null', () {
    final r = resolveDailyRateOverride(
      manualRaw: null,
      compensationDerived: null,
    );
    expect(r, isNull);
  });
}
