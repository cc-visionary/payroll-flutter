import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/kpi_results/sql_identifier.dart';

void main() {
  test('accepts ordinary identifiers', () {
    for (final v in ['orders', 'order_lines', 'DailySalesFact', 'a1', '_x']) {
      expect(isValidSqlIdentifier(v), isTrue, reason: v);
    }
  });

  test('rejects everything that could change the statement', () {
    for (final v in [
      '',
      'a b',
      'a;b',
      "a'b",
      'a"b',
      'a-b',
      'a.b',
      'a--b',
      'a/*b',
      'a)b',
      '1abc',
      'orders; drop table employees',
      // Beyond the brief's list. A NUL byte, written as a Dart escape (not
      // a raw control character in source -- this repo has shipped raw
      // NUL bytes before, with real consequences for a review package's
      // diff).
      'a\u0000b',
      // A non-ASCII letter -- a Unicode-aware \w-style check would admit
      // this even though it is outside the ASCII whitelist this validator
      // commits to.
      'ord\u{e9}rs',
    ]) {
      expect(isValidSqlIdentifier(v), isFalse, reason: v);
    }
  });

  test('rejects a name longer than Postgres allows', () {
    expect(isValidSqlIdentifier('a' * 64), isFalse);
    expect(isValidSqlIdentifier('a' * 63), isTrue);
  });
}
