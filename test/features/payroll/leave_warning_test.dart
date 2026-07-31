import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/attendance_day.dart';
import 'package:payroll_flutter/features/payroll/leave/paid_leave_matcher.dart';
import 'package:payroll_flutter/features/payroll/runs/detail/warnings.dart';

AttendanceDay _onLeaveDay() => AttendanceDay(
      id: 'A1',
      employeeId: 'e1',
      attendanceDate: DateTime.utc(2026, 1, 6),
      dayType: 'WORKDAY',
      attendanceStatus: 'ON_LEAVE',
      sourceType: 'LARK',
      earlyInApproved: false,
      lateOutApproved: false,
      lateInApproved: false,
      earlyOutApproved: false,
      isLocked: false,
    );

void main() {
  test('ON_LEAVE day with no covering approved request yields a warning', () {
    final rec = _onLeaveDay();
    final warnings = detectWarnings(
      records: [rec],
      shiftsById: const {},
      today: DateTime.utc(2026, 2, 1),
      approvedLeavesByEmployee: const {}, // no approvals → warning
    );
    expect(
      warnings.where((w) => w.type == WarningType.leaveWithoutApprovedRequest),
      hasLength(1),
    );
  });

  test('ON_LEAVE day covered by an approved request yields no leave warning', () {
    final rec = _onLeaveDay();
    final warnings = detectWarnings(
      records: [rec],
      shiftsById: const {},
      today: DateTime.utc(2026, 2, 1),
      approvedLeavesByEmployee: {
        'e1': [
          ApprovedLeaveDay(
            start: DateTime.utc(2026, 1, 6),
            end: DateTime.utc(2026, 1, 6),
            isPaid: true,
            typeName: 'SIL',
            leaveDays: Decimal.one,
          ),
        ],
      },
    );
    expect(
      warnings.where((w) => w.type == WarningType.leaveWithoutApprovedRequest),
      isEmpty,
    );
  });

  test('ON_LEAVE day with worked time, covered by a PAID request yields a '
      'paidLeaveOnWorkedDay warning and no leaveWithoutApprovedRequest', () {
    final rec = AttendanceDay(
      id: 'A2',
      employeeId: 'e1',
      attendanceDate: DateTime.utc(2026, 1, 6),
      dayType: 'WORKDAY',
      attendanceStatus: 'ON_LEAVE',
      sourceType: 'LARK',
      actualTimeIn: DateTime.utc(2026, 1, 6, 8),
      actualTimeOut: DateTime.utc(2026, 1, 6, 17),
      earlyInApproved: false,
      lateOutApproved: false,
      lateInApproved: false,
      earlyOutApproved: false,
      isLocked: false,
    );
    final warnings = detectWarnings(
      records: [rec],
      shiftsById: const {},
      today: DateTime.utc(2026, 2, 1),
      approvedLeavesByEmployee: {
        'e1': [
          ApprovedLeaveDay(
            start: DateTime.utc(2026, 1, 6),
            end: DateTime.utc(2026, 1, 6),
            isPaid: true,
            typeName: 'SIL',
            leaveDays: Decimal.one,
          ),
        ],
      },
    );
    expect(
      warnings.where((w) => w.type == WarningType.paidLeaveOnWorkedDay),
      hasLength(1),
    );
    expect(
      warnings.where((w) => w.type == WarningType.leaveWithoutApprovedRequest),
      isEmpty,
    );
  });
}
