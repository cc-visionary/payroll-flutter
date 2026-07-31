import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/payroll/leave/paid_leave_matcher.dart';

Decimal _d(String s) => Decimal.parse(s);
DateTime _u(int y, int m, int d) => DateTime.utc(y, m, d);

ApprovedLeaveDay _lv({
  required DateTime start,
  required DateTime end,
  required bool paid,
  String type = 'SIL',
  String days = '1',
}) =>
    ApprovedLeaveDay(
      start: start,
      end: end,
      isPaid: paid,
      typeName: type,
      leaveDays: _d(days),
    );

void main() {
  test('paid single-day request covering the date → paid, full day', () {
    final r = resolvePaidLeaveForDay(
      date: _u(2026, 1, 6),
      statusIsLeave: true,
      approved: [_lv(start: _u(2026, 1, 6), end: _u(2026, 1, 6), paid: true)],
    );
    expect(r.covered, isTrue);
    expect(r.isPaid, isTrue);
    expect(r.fraction, _d('1.0'));
    expect(r.typeName, 'SIL');
  });

  test('single-day half-day paid request → 0.5 fraction', () {
    final r = resolvePaidLeaveForDay(
      date: _u(2026, 1, 6),
      statusIsLeave: true,
      approved: [_lv(start: _u(2026, 1, 6), end: _u(2026, 1, 6), paid: true, days: '0.5')],
    );
    expect(r.fraction, _d('0.5'));
    expect(r.isPaid, isTrue);
  });

  test('multi-day paid request covers an interior date at full day', () {
    final r = resolvePaidLeaveForDay(
      date: _u(2026, 1, 7),
      statusIsLeave: true,
      approved: [_lv(start: _u(2026, 1, 6), end: _u(2026, 1, 9), paid: true, days: '4')],
    );
    expect(r.covered, isTrue);
    expect(r.fraction, _d('1.0'));
  });

  test('unpaid request covering the date → covered but not paid', () {
    final r = resolvePaidLeaveForDay(
      date: _u(2026, 1, 6),
      statusIsLeave: true,
      approved: [_lv(start: _u(2026, 1, 6), end: _u(2026, 1, 6), paid: false)],
    );
    expect(r.covered, isTrue);
    expect(r.isPaid, isFalse);
    expect(r.fraction, Decimal.zero);
  });

  test('ON_LEAVE day with no covering request → not covered, not paid', () {
    final r = resolvePaidLeaveForDay(
      date: _u(2026, 1, 6),
      statusIsLeave: true,
      approved: [_lv(start: _u(2026, 1, 10), end: _u(2026, 1, 10), paid: true)],
    );
    expect(r.covered, isFalse);
    expect(r.isPaid, isFalse);
  });

  test('non-leave day is never paid even if a request overlaps', () {
    final r = resolvePaidLeaveForDay(
      date: _u(2026, 1, 6),
      statusIsLeave: false,
      approved: [_lv(start: _u(2026, 1, 6), end: _u(2026, 1, 6), paid: true)],
    );
    expect(r.isPaid, isFalse);
    expect(r.covered, isFalse);
  });
}
