import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/attendance_day.dart';
import 'package:payroll_flutter/data/models/calendar_event.dart';
import 'package:payroll_flutter/data/models/employee.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';
import 'package:payroll_flutter/data/models/shift_template.dart';
import 'package:payroll_flutter/features/attendance/attendance_row_vm.dart'
    show isoDate;
import 'package:payroll_flutter/features/dashboard/dashboard_metrics.dart';
import 'package:payroll_flutter/features/dashboard/leave_expansion.dart';

// ---------------------------------------------------------------------------
// Builders. The models carry many required fields that are irrelevant here;
// these keep each test to the two or three fields it actually exercises.
// ---------------------------------------------------------------------------

Employee _emp({
  required String id,
  required DateTime hireDate,
  DateTime? separationDate,
  String employmentStatus = 'ACTIVE',
  DateTime? deletedAt,
  String employmentType = 'REGULAR',
  String? roleScorecardId = 'sc1',
  String? departmentId,
  String? hiringEntityId,
}) {
  return Employee(
    id: id,
    companyId: 'c1',
    employeeNumber: id,
    firstName: 'Test',
    lastName: id,
    employmentType: employmentType,
    employmentStatus: employmentStatus,
    hireDate: hireDate,
    separationDate: separationDate,
    deletedAt: deletedAt,
    roleScorecardId: roleScorecardId,
    departmentId: departmentId,
    hiringEntityId: hiringEntityId,
    isRankAndFile: true,
    isOtEligible: true,
    isNdEligible: true,
    isHolidayPayEligible: true,
    taxOnFullEarnings: false,
  );
}

/// 08:00-17:00 with a 60-minute break => 480 expected work minutes.
/// NOTE: `isActive` is required by `ShiftTemplate` but wasn't in the task
/// brief's builder — added here per the brief's own escape hatch ("add that
/// field with an obviously-inert value"). It is not read anywhere in
/// `buildAttendanceRows` / `AttendanceStats`, so its value is inert.
ShiftTemplate _shift() => const ShiftTemplate(
  id: 'sh1',
  companyId: 'c1',
  code: 'DAY',
  name: 'Day',
  startTime: '08:00:00',
  endTime: '17:00:00',
  isOvernight: false,
  breakType: 'AUTO_DEDUCT',
  breakMinutes: 60,
  graceMinutesLate: 0,
  graceMinutesEarlyOut: 0,
  scheduledWorkMinutes: 480,
  isActive: true,
);

RoleScorecard _scorecard({String id = 'sc1', String? departmentId}) =>
    RoleScorecard(
      id: id,
      companyId: 'c1',
      jobTitle: 'Staff',
      departmentId: departmentId,
      missionStatement: '',
      responsibilities: const [],
      kpis: const [],
      wageType: 'MONTHLY',
      workHoursPerDay: 8,
      workDaysPerWeek: 'Monday to Friday',
      isActive: true,
      effectiveDate: DateTime(2020, 1, 1),
      shiftTemplateId: 'sh1',
    );

AttendanceDay _day({
  required String employeeId,
  required DateTime date,
  String? timeIn,
  String? timeOut,
  String status = 'PRESENT',
  String dayType = 'WORKDAY',
  String? shiftTemplateId = 'sh1',
  int? approvedOtMinutes,
}) {
  DateTime? at(String? hhmm) {
    if (hhmm == null) return null;
    final p = hhmm.split(':');
    return DateTime(
      date.year,
      date.month,
      date.day,
      int.parse(p[0]),
      int.parse(p[1]),
    );
  }

  return AttendanceDay(
    id: '$employeeId-${date.toIso8601String()}',
    employeeId: employeeId,
    attendanceDate: date,
    dayType: dayType,
    actualTimeIn: at(timeIn),
    actualTimeOut: at(timeOut),
    attendanceStatus: status,
    sourceType: 'MANUAL',
    earlyInApproved: false,
    lateOutApproved: false,
    lateInApproved: false,
    earlyOutApproved: false,
    approvedOtMinutes: approvedOtMinutes,
    shiftTemplateId: shiftTemplateId,
    isLocked: false,
  );
}

DashboardYearInput _input({
  required List<Employee> employees,
  List<AttendanceDay> attendance = const [],
  List<LeaveDayAllocation> leaveDays = const [],
  List<DashboardPayslip> payslips = const [],
  Map<String, RoleScorecard>? scorecardsById,
  Map<String, String>? departmentNames,
  Map<String, CalendarEvent> holidaysByDate = const {},
  DateTime? today,
}) {
  return DashboardYearInput(
    year: 2026,
    employees: employees,
    scorecardsById: scorecardsById ?? {'sc1': _scorecard()},
    shiftsById: {'sh1': _shift()},
    departmentNames: departmentNames ?? const {'d1': 'Engineering'},
    hiringEntityNames: const {'h1': 'Luxium HQ'},
    holidaysByDate: holidaysByDate,
    attendance: attendance,
    leaveDays: leaveDays,
    payslips: payslips,
    applicants: const [],
    today: today ?? DateTime(2026, 12, 31),
  );
}

void main() {
  group('computeMonthMetrics — attendance', () {
    test('returns exactly 12 buckets, January first', () {
      final months = computeMonthMetrics(
        _input(
          employees: [_emp(id: 'e1', hireDate: DateTime(2020, 1, 1))],
        ),
      );
      expect(months.length, 12);
      expect(months.first.month, 1);
      expect(months.last.month, 12);
    });

    test('an on-time full day is present with no late and no OT', () {
      // 2026-07-06 is a Monday.
      final months = computeMonthMetrics(
        _input(
          employees: [_emp(id: 'e1', hireDate: DateTime(2020, 1, 1))],
          attendance: [
            _day(
              employeeId: 'e1',
              date: DateTime(2026, 7, 6),
              timeIn: '08:00',
              timeOut: '17:00',
            ),
          ],
          today: DateTime(2026, 7, 6),
        ),
      );
      final july = months[6];
      expect(july.presentDays, 1);
      expect(july.lateUndertimeMinutes, 0);
      expect(july.overtimeMinutes, 0);
    });

    test('clocking in 30m late registers 30 late minutes', () {
      final months = computeMonthMetrics(
        _input(
          employees: [_emp(id: 'e1', hireDate: DateTime(2020, 1, 1))],
          attendance: [
            _day(
              employeeId: 'e1',
              date: DateTime(2026, 7, 6),
              timeIn: '08:30',
              timeOut: '17:00',
            ),
          ],
          today: DateTime(2026, 7, 6),
        ),
      );
      expect(months[6].lateUndertimeMinutes, closeTo(30, 0.01));
    });

    test('leaving 30m early registers as late/UT too (undertime)', () {
      // The old dashboard missed this entirely — it only looked at clock-in.
      final months = computeMonthMetrics(
        _input(
          employees: [_emp(id: 'e1', hireDate: DateTime(2020, 1, 1))],
          attendance: [
            _day(
              employeeId: 'e1',
              date: DateTime(2026, 7, 6),
              timeIn: '08:00',
              timeOut: '16:30',
            ),
          ],
          today: DateTime(2026, 7, 6),
        ),
      );
      expect(months[6].lateUndertimeMinutes, closeTo(30, 0.01));
    });

    test('approved OT absorbs late minutes (net late = 0)', () {
      final months = computeMonthMetrics(
        _input(
          employees: [_emp(id: 'e1', hireDate: DateTime(2020, 1, 1))],
          attendance: [
            _day(
              employeeId: 'e1',
              date: DateTime(2026, 7, 6),
              timeIn: '08:30',
              timeOut: '17:00',
              approvedOtMinutes: 60,
            ),
          ],
          today: DateTime(2026, 7, 6),
        ),
      );
      final july = months[6];
      expect(july.lateUndertimeMinutes, 0);
      expect(july.overtimeMinutes, closeTo(30, 0.01)); // 60 OT - 30 late
    });

    test('a mid-year hire accrues no absences before the hire date', () {
      // Hired 1 July. If the window were not clipped, Jan-Jun would fill with
      // scheduled-but-absent work days.
      final months = computeMonthMetrics(
        _input(
          employees: [_emp(id: 'e1', hireDate: DateTime(2026, 7, 1))],
          today: DateTime(2026, 7, 31),
        ),
      );
      expect(months[0].workDays, 0); // January
      expect(months[0].absentDays, 0);
      expect(months[5].workDays, 0); // June
      expect(months[6].workDays, greaterThan(0)); // July
    });

    test('a mid-year separation accrues no work days after the last day', () {
      // Separated 15 May. If the window were not clipped, June-December would
      // fill with scheduled-but-absent work days.
      final months = computeMonthMetrics(
        _input(
          employees: [
            _emp(
              id: 'e1',
              hireDate: DateTime(2020, 1, 1),
              separationDate: DateTime(2026, 5, 15),
              employmentStatus: 'RESIGNED',
            ),
          ],
        ),
      );
      expect(months[4].workDays, greaterThan(0)); // May
      for (var m = 5; m < 12; m++) {
        expect(months[m].workDays, 0, reason: 'month ${m + 1}');
      }
    });

    test('attendance rate is present / (present + absent)', () {
      final months = computeMonthMetrics(
        _input(
          employees: [_emp(id: 'e1', hireDate: DateTime(2020, 1, 1))],
          attendance: [
            _day(
              employeeId: 'e1',
              date: DateTime(2026, 7, 6),
              timeIn: '08:00',
              timeOut: '17:00',
            ),
            _day(
              employeeId: 'e1',
              date: DateTime(2026, 7, 7),
              status: 'ABSENT',
            ),
          ],
          today: DateTime(2026, 7, 7),
        ),
      );
      final july = months[6];
      expect(july.presentDays, 1);
      expect(july.absentDays, 1);
      expect(july.attendanceRatePct, closeTo(50.0, 0.01));
    });

    test('scheduled-off days are rest days, and unrecorded work days are NOT '
        'absences', () {
      // The scorecard says Monday-Friday, and there are no attendance records
      // at all. Two distinct guarantees:
      //   1. Sat/Sun never land in `absent` — they are rest days.
      //   2. An unrecorded WEEKDAY is not an absence either. AttendanceStats
      //      gives it status NO_DATA (only an explicit ABSENT record counts),
      //      so a month whose attendance has not been imported yet reports
      //      zero absences rather than inventing a no-show for everyone.
      //
      // July 2026 starts on a Wednesday. Through the 11th: weekdays are
      // 1,2,3,6,7,8,9,10 (8 of them); rest days are Sat 4, Sun 5, Sat 11 (3).
      final months = computeMonthMetrics(
        _input(
          employees: [_emp(id: 'e1', hireDate: DateTime(2020, 1, 1))],
          today: DateTime(2026, 7, 11),
        ),
      );
      final july = months[6];
      expect(july.workDays, 8);
      expect(july.restDays, 3);
      expect(july.absentDays, 0);
      expect(july.presentDays, 0);
    });

    test('an unworked regular holiday on a weekday counts as a holiday, not '
        'an absence', () {
      // 2026-07-06 is a Monday. No attendance record for it at all.
      final holidayDate = DateTime(2026, 7, 6);
      final event = CalendarEvent(
        id: 'ev1',
        calendarId: 'cal1',
        date: holidayDate,
        name: 'Test Holiday',
        dayType: 'REGULAR_HOLIDAY',
        source: 'MANUAL',
      );
      final months = computeMonthMetrics(
        _input(
          employees: [_emp(id: 'e1', hireDate: holidayDate)],
          holidaysByDate: {isoDate(holidayDate): event},
          today: holidayDate,
        ),
      );
      final july = months[6];
      expect(july.regularHolidays, 1);
      expect(july.absentDays, 0);
      expect(july.workDays, 0); // unworked holiday is not a Work Day
    });

    test('rates return 0 rather than NaN when the denominator is empty', () {
      final months = computeMonthMetrics(
        _input(
          employees: [_emp(id: 'e1', hireDate: DateTime(2020, 1, 1))],
        ),
      );
      expect(months[0].attendanceRatePct, 0);
      expect(months[0].avgLateMinutesPerWorkDay, 0);
      expect(months[0].avgGrossPerEmployee, Decimal.zero);
    });
  });

  group('computeMonthMetrics — leave', () {
    test('half-day leave contributes 0.5 to the month bucket', () {
      final months = computeMonthMetrics(
        _input(
          employees: [_emp(id: 'e1', hireDate: DateTime(2020, 1, 1))],
          leaveDays: [
            LeaveDayAllocation(
              employeeId: 'e1',
              date: DateTime(2026, 7, 6),
              days: 0.5,
              leaveType: 'Sick Leave',
            ),
          ],
        ),
      );
      expect(months[6].leaveDays, 0.5);
      expect(months[6].leaveDaysByType['Sick Leave'], 0.5);
    });

    test('leave lands in the month of its date, not the request start', () {
      final months = computeMonthMetrics(
        _input(
          employees: [_emp(id: 'e1', hireDate: DateTime(2020, 1, 1))],
          leaveDays: [
            LeaveDayAllocation(
              employeeId: 'e1',
              date: DateTime(2026, 7, 31),
              days: 1.0,
              leaveType: 'Vacation Leave',
            ),
            LeaveDayAllocation(
              employeeId: 'e1',
              date: DateTime(2026, 8, 1),
              days: 1.0,
              leaveType: 'Vacation Leave',
            ),
          ],
        ),
      );
      expect(months[6].leaveDays, 1.0); // July
      expect(months[7].leaveDays, 1.0); // August
    });
  });

  group('computeMonthMetrics — movement', () {
    test('new hires land in their hire month', () {
      final months = computeMonthMetrics(
        _input(
          employees: [
            _emp(id: 'e1', hireDate: DateTime(2026, 3, 15)),
            _emp(id: 'e2', hireDate: DateTime(2026, 3, 20)),
            _emp(id: 'e3', hireDate: DateTime(2025, 1, 1)), // prior year
          ],
        ),
      );
      expect(months[2].newHires, 2); // March
      expect(months[0].newHires, 0);
    });

    test(
      'a separated AND archived employee still counts in the month they left',
      () {
        // Separation sets deleted_at (the "archive on separate" option). A
        // `deleted_at is null` filter would hide the separation entirely —
        // which is exactly what the old dashboard did.
        final months = computeMonthMetrics(
          _input(
            employees: [
              _emp(
                id: 'e1',
                hireDate: DateTime(2024, 1, 1),
                separationDate: DateTime(2026, 5, 10),
                employmentStatus: 'RESIGNED',
                deletedAt: DateTime(2026, 5, 10),
              ),
            ],
          ),
        );
        expect(months[4].separations, 1); // May
        expect(months[4].voluntarySeparations, 1);
        expect(months[4].involuntarySeparations, 0);
      },
    );

    test('an archived employee with NO separation date is not a hire and '
        'accrues no work days in any month', () {
      // deleted_at stamped via the standalone Archive button (not the
      // "archive on separate" option), so separation_date stays null. This
      // is a data cleanup, not a person leaving — it must not inflate hires
      // or Work Days. Contrast with the sibling test above: a separated AND
      // archived employee (separation_date set) DOES still count.
      final months = computeMonthMetrics(
        _input(
          employees: [
            _emp(
              id: 'e1',
              hireDate: DateTime(2026, 2, 3),
              deletedAt: DateTime(2026, 3, 1),
            ),
          ],
        ),
      );
      for (final m in months) {
        expect(m.newHires, 0, reason: 'month ${m.month}');
        expect(m.workDays, 0, reason: 'month ${m.month}');
      }
    });

    test('RESIGNED and RETIRED are voluntary; TERMINATED, END_OF_CONTRACT, '
        'AWOL and DECEASED are involuntary', () {
      final months = computeMonthMetrics(
        _input(
          employees: [
            for (final s in ['RESIGNED', 'RETIRED'])
              _emp(
                id: 'v-$s',
                hireDate: DateTime(2024, 1, 1),
                separationDate: DateTime(2026, 5, 10),
                employmentStatus: s,
              ),
            for (final s in [
              'TERMINATED',
              'END_OF_CONTRACT',
              'AWOL',
              'DECEASED',
            ])
              _emp(
                id: 'i-$s',
                hireDate: DateTime(2024, 1, 1),
                separationDate: DateTime(2026, 5, 10),
                employmentStatus: s,
              ),
          ],
        ),
      );
      expect(months[4].voluntarySeparations, 2);
      expect(months[4].involuntarySeparations, 4);
      expect(months[4].separations, 6);
    });

    test('an ACTIVE employee with a separation_date is not a separation', () {
      final months = computeMonthMetrics(
        _input(
          employees: [
            _emp(
              id: 'e1',
              hireDate: DateTime(2024, 1, 1),
              separationDate: DateTime(2026, 5, 10),
              employmentStatus: 'ACTIVE',
            ),
          ],
        ),
      );
      expect(months[4].separations, 0);
    });
  });

  group('computeMonthMetrics — payroll', () {
    test('payslips bucket by pay_date and avg gross divides by DISTINCT '
        'employees, not payslip count', () {
      // Two semi-monthly payslips for the same employee. Dividing by payslip
      // count would report an average half-month as a salary.
      Decimal d(String s) => Decimal.parse(s);
      final months = computeMonthMetrics(
        _input(
          employees: [_emp(id: 'e1', hireDate: DateTime(2020, 1, 1))],
          payslips: [
            DashboardPayslip(
              employeeId: 'e1',
              payDate: DateTime(2026, 7, 15),
              grossPay: d('15000'),
              sssEe: d('675'),
              philhealthEe: d('375'),
              pagibigEe: d('100'),
              withholdingTax: d('500'),
            ),
            DashboardPayslip(
              employeeId: 'e1',
              payDate: DateTime(2026, 7, 31),
              grossPay: d('15000'),
              sssEe: d('675'),
              philhealthEe: d('375'),
              pagibigEe: d('100'),
              withholdingTax: d('500'),
            ),
          ],
        ),
      );
      final july = months[6];
      expect(july.payrollGross, d('30000'));
      expect(july.payrollEmployeeIds.length, 1);
      expect(july.avgGrossPerEmployee, d('30000'));
      expect(july.sssTotal, d('1350'));
    });
  });

  group('aggregateMonths', () {
    test('additive metrics sum and the year total carries a null month', () {
      final months = computeMonthMetrics(
        _input(
          employees: [
            _emp(id: 'e1', hireDate: DateTime(2026, 3, 1)),
            _emp(id: 'e2', hireDate: DateTime(2026, 9, 1)),
          ],
          leaveDays: [
            LeaveDayAllocation(
              employeeId: 'e1',
              date: DateTime(2026, 4, 1),
              days: 1.0,
              leaveType: 'Vacation Leave',
            ),
            LeaveDayAllocation(
              employeeId: 'e1',
              date: DateTime(2026, 5, 1),
              days: 0.5,
              leaveType: 'Sick Leave',
            ),
          ],
        ),
      );
      final year = aggregateMonths(months, 2026);
      expect(year.month, isNull);
      expect(year.newHires, 2);
      expect(year.leaveDays, 1.5);
      expect(year.leaveDaysByType['Vacation Leave'], 1.0);
      expect(year.leaveDaysByType['Sick Leave'], 0.5);
      expect(year.workDays, months.fold<int>(0, (s, m) => s + m.workDays));
    });

    test('payroll employees are UNIONed across months, not summed', () {
      Decimal d(String s) => Decimal.parse(s);
      final months = computeMonthMetrics(
        _input(
          employees: [_emp(id: 'e1', hireDate: DateTime(2020, 1, 1))],
          payslips: [
            DashboardPayslip(
              employeeId: 'e1',
              payDate: DateTime(2026, 6, 30),
              grossPay: d('30000'),
              sssEe: Decimal.zero,
              philhealthEe: Decimal.zero,
              pagibigEe: Decimal.zero,
              withholdingTax: Decimal.zero,
            ),
            DashboardPayslip(
              employeeId: 'e1',
              payDate: DateTime(2026, 7, 31),
              grossPay: d('30000'),
              sssEe: Decimal.zero,
              philhealthEe: Decimal.zero,
              pagibigEe: Decimal.zero,
              withholdingTax: Decimal.zero,
            ),
          ],
        ),
      );
      final year = aggregateMonths(months, 2026);
      // One employee paid in two months is one employee, not two.
      expect(year.payrollEmployeeIds.length, 1);
      expect(year.payrollGross, d('60000'));
      expect(year.avgGrossPerEmployee, d('60000'));
    });
  });

  group('computeSnapshot / isActiveAsOf', () {
    test('an employee hired after the as-of date is not yet active', () {
      final e = _emp(id: 'e1', hireDate: DateTime(2026, 8, 1));
      expect(isActiveAsOf(e, DateTime(2026, 7, 31)), isFalse);
      expect(isActiveAsOf(e, DateTime(2026, 8, 1)), isTrue);
    });

    test(
      'a separated employee is active up to and including their last day',
      () {
        final e = _emp(
          id: 'e1',
          hireDate: DateTime(2024, 1, 1),
          separationDate: DateTime(2026, 5, 10),
          employmentStatus: 'RESIGNED',
          deletedAt: DateTime(2026, 5, 10),
        );
        expect(isActiveAsOf(e, DateTime(2026, 5, 10)), isTrue);
        expect(isActiveAsOf(e, DateTime(2026, 5, 11)), isFalse);
      },
    );

    test('an admin-archived employee who was never separated is excluded', () {
      final e = _emp(
        id: 'e1',
        hireDate: DateTime(2024, 1, 1),
        deletedAt: DateTime(2026, 3, 1),
      );
      expect(isActiveAsOf(e, DateTime(2026, 7, 1)), isFalse);
    });

    test('snapshot buckets by department name via the scorecard, then the '
        'employee, then Unassigned', () {
      final input = _input(
        employees: [
          _emp(id: 'e1', hireDate: DateTime(2020, 1, 1), departmentId: 'd1'),
          _emp(
            id: 'e2',
            hireDate: DateTime(2020, 1, 1),
            departmentId: null,
            roleScorecardId: null,
          ),
        ],
      );
      final snap = computeSnapshot(input, DateTime(2026, 7, 31));
      expect(snap.activeEmployees, 2);
      expect(snap.headcountByDepartment['Engineering'], 1);
      expect(snap.headcountByDepartment['Unassigned'], 1);
      expect(snap.asOf, DateTime(2026, 7, 31));
    });

    test('when the scorecard department differs from the employee\'s own '
        'department link, the scorecard wins', () {
      final input = _input(
        employees: [
          _emp(
            id: 'e1',
            hireDate: DateTime(2020, 1, 1),
            departmentId: 'd1', // employee's own link says Engineering
            roleScorecardId: 'sc1',
          ),
        ],
        scorecardsById: {'sc1': _scorecard(departmentId: 'd2')},
        departmentNames: const {'d1': 'Engineering', 'd2': 'Sales'},
      );
      final snap = computeSnapshot(input, DateTime(2026, 7, 31));
      expect(snap.headcountByDepartment['Sales'], 1);
      expect(snap.headcountByDepartment.containsKey('Engineering'), isFalse);
    });

    test('separated employee drops out of the following month snapshot', () {
      final input = _input(
        employees: [
          _emp(
            id: 'e1',
            hireDate: DateTime(2024, 1, 1),
            separationDate: DateTime(2026, 5, 10),
            employmentStatus: 'RESIGNED',
            deletedAt: DateTime(2026, 5, 10),
          ),
        ],
      );
      expect(computeSnapshot(input, DateTime(2026, 5, 31)).activeEmployees, 0);
      expect(computeSnapshot(input, DateTime(2026, 4, 30)).activeEmployees, 1);
    });
  });
}
