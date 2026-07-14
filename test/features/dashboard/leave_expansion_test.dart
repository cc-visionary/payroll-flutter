import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/dashboard/leave_expansion.dart';

void main() {
  group('expandLeaveRequest', () {
    test('a plain 3-day request yields 1.0 per day', () {
      final out = expandLeaveRequest(
        employeeId: 'e1',
        startDate: DateTime(2026, 7, 6),
        endDate: DateTime(2026, 7, 8),
        leaveDays: 3.0,
        leaveType: 'Vacation Leave',
      );
      expect(out.length, 3);
      expect(out.map((a) => a.days), everyElement(1.0));
      expect(out.first.date, DateTime(2026, 7, 6));
      expect(out.last.date, DateTime(2026, 7, 8));
      expect(out.first.employeeId, 'e1');
      expect(out.first.leaveType, 'Vacation Leave');
    });

    test('a single-day half-day request is 0.5, not 1.0', () {
      final out = expandLeaveRequest(
        employeeId: 'e1',
        startDate: DateTime(2026, 7, 6),
        endDate: DateTime(2026, 7, 6),
        leaveDays: 0.5,
        startHalf: 'AM',
        leaveType: 'Sick Leave',
      );
      expect(out.length, 1);
      expect(out.single.days, 0.5);
    });

    test('a single day with BOTH halves marked is still one whole day', () {
      // Degenerate input: some sources set both halves on a 1-day request.
      // Naively adding 0.5 + 0.5 on the same date would double-count.
      final out = expandLeaveRequest(
        employeeId: 'e1',
        startDate: DateTime(2026, 7, 6),
        endDate: DateTime(2026, 7, 6),
        leaveDays: 1.0,
        startHalf: 'AM',
        endHalf: 'PM',
        leaveType: 'Sick Leave',
      );
      expect(out.length, 1);
      expect(out.single.days, 1.0);
    });

    test('half start and half end trim both ends of a multi-day request', () {
      final out = expandLeaveRequest(
        employeeId: 'e1',
        startDate: DateTime(2026, 7, 6),
        endDate: DateTime(2026, 7, 8),
        leaveDays: 2.0,
        startHalf: 'PM',
        endHalf: 'AM',
        leaveType: 'Vacation Leave',
      );
      expect(out.map((a) => a.days).toList(), [0.5, 1.0, 0.5]);
      expect(out.fold<double>(0, (s, a) => s + a.days), 2.0);
    });

    test('a request straddling a month boundary splits across both months',
        () {
      final out = expandLeaveRequest(
        employeeId: 'e1',
        startDate: DateTime(2026, 7, 30),
        endDate: DateTime(2026, 8, 2),
        leaveDays: 4.0,
        leaveType: 'Vacation Leave',
      );
      final july = out.where((a) => a.date.month == 7);
      final august = out.where((a) => a.date.month == 8);
      expect(july.fold<double>(0, (s, a) => s + a.days), 2.0);
      expect(august.fold<double>(0, (s, a) => s + a.days), 2.0);
    });

    test('per-day values are scaled to reconcile with a disagreeing leave_days',
        () {
      // Stored leave_days says 2.0 but the span is 4 calendar days (e.g. the
      // source excluded weekends). Scale so the request still contributes
      // exactly 2.0 — bad data must not inflate the month bucket.
      final out = expandLeaveRequest(
        employeeId: 'e1',
        startDate: DateTime(2026, 7, 6),
        endDate: DateTime(2026, 7, 9),
        leaveDays: 2.0,
        leaveType: 'Vacation Leave',
      );
      expect(out.length, 4);
      expect(out.fold<double>(0, (s, a) => s + a.days), closeTo(2.0, 1e-9));
      expect(out.every((a) => a.days == 0.5), isTrue);
    });

    test('leaveDays of 0 yields no allocations', () {
      final out = expandLeaveRequest(
        employeeId: 'e1',
        startDate: DateTime(2026, 7, 6),
        endDate: DateTime(2026, 7, 6),
        leaveDays: 0,
        leaveType: 'Vacation Leave',
      );
      expect(out, isEmpty);
    });

    test('an inverted range (end before start) yields no allocations', () {
      final out = expandLeaveRequest(
        employeeId: 'e1',
        startDate: DateTime(2026, 7, 9),
        endDate: DateTime(2026, 7, 6),
        leaveDays: 2.0,
        leaveType: 'Vacation Leave',
      );
      expect(out, isEmpty);
    });
  });
}
