import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/attendance_day.dart';
import 'package:payroll_flutter/data/models/shift_template.dart';
import 'package:payroll_flutter/features/payroll/runs/detail/warnings.dart';

// All clock times are LOCAL DateTimes so toLocal() is identity under any tz.
DateTime _at(int h, int m) => DateTime(2026, 6, 15, h, m);
final _today = DateTime(2026, 6, 30); // every record day below is in the past

AttendanceDay _day({
  DateTime? tIn,
  DateTime? tOut,
  String? shiftId,
  bool lateOutApproved = false,
  bool earlyInApproved = false,
  int? approvedOtMinutes,
  DateTime? date,
  String empFirst = 'Jane',
}) =>
    AttendanceDay(
      id: 'A1',
      employeeId: 'E1',
      attendanceDate: date ?? DateTime(2026, 6, 15),
      dayType: 'WORKDAY',
      actualTimeIn: tIn,
      actualTimeOut: tOut,
      attendanceStatus: 'PRESENT',
      sourceType: 'LARK',
      earlyInApproved: earlyInApproved,
      lateOutApproved: lateOutApproved,
      lateInApproved: false,
      earlyOutApproved: false,
      approvedOtMinutes: approvedOtMinutes,
      isLocked: false,
      shiftTemplateId: shiftId,
      employeeNumber: 'EMP-001',
      employeeFirstName: empFirst,
      employeeLastName: 'Doe',
    );

ShiftTemplate _shift({bool overnight = false}) => ShiftTemplate(
      id: 'S1',
      companyId: 'C1',
      code: 'DAY',
      name: 'Day Shift',
      startTime: '09:00:00',
      endTime: '18:00:00',
      isOvernight: overnight,
      breakType: 'AUTO_DEDUCT',
      breakMinutes: 60,
      graceMinutesLate: 0,
      graceMinutesEarlyOut: 0,
      scheduledWorkMinutes: 480,
      isActive: true,
    );

List<RunWarning> _run(List<AttendanceDay> records,
        {Map<String, ShiftTemplate>? shifts}) =>
    detectWarnings(
      records: records,
      shiftsById: shifts ?? {'S1': _shift()},
      today: _today,
    );

void main() {
  test('missing clock-out is flagged', () {
    final w = _run([_day(tIn: _at(9, 2), tOut: null, shiftId: 'S1')]);
    expect(w, hasLength(1));
    expect(w.single.type, WarningType.missingClockOut);
  });

  test('missing clock-in is flagged', () {
    final w = _run([_day(tIn: null, tOut: _at(18, 0), shiftId: 'S1')]);
    expect(w.single.type, WarningType.missingClockIn);
  });

  test('clock-out not after clock-in is flagged as invalid', () {
    final w = _run([_day(tIn: _at(18, 0), tOut: _at(9, 0), shiftId: 'S1')]);
    expect(w.single.type, WarningType.invalidWorkedTime);
  });

  test('a clean day inside the shift produces no warning', () {
    final w = _run([_day(tIn: _at(9, 0), tOut: _at(18, 0), shiftId: 'S1')]);
    expect(w, isEmpty);
  });

  test('both clock times null (absence) produces no warning', () {
    final w = _run([_day(tIn: null, tOut: null, shiftId: 'S1')]);
    expect(w, isEmpty);
  });

  test('45 min unapproved late-out is flagged as unapproved overtime', () {
    final w = _run([_day(tIn: _at(9, 0), tOut: _at(18, 45), shiftId: 'S1')]);
    expect(w.single.type, WarningType.unapprovedOvertime);
  });

  test('Lark-approved OT suppresses the overtime warning', () {
    final w = _run([
      _day(tIn: _at(9, 0), tOut: _at(18, 45), shiftId: 'S1', approvedOtMinutes: 60)
    ]);
    expect(w, isEmpty);
  });

  test('late-out approval flag suppresses the overtime warning', () {
    final w = _run([
      _day(tIn: _at(9, 0), tOut: _at(18, 45), shiftId: 'S1', lateOutApproved: true)
    ]);
    expect(w, isEmpty);
  });

  test('late-out under the 30-min threshold is not flagged', () {
    final w = _run([_day(tIn: _at(9, 0), tOut: _at(18, 20), shiftId: 'S1')]);
    expect(w, isEmpty);
  });

  test('40 min unapproved early-in is flagged as unapproved overtime', () {
    final w = _run([_day(tIn: _at(8, 20), tOut: _at(18, 0), shiftId: 'S1')]);
    expect(w.single.type, WarningType.unapprovedOvertime);
  });

  test('overnight shift skips the OT check but still flags missing clock-out', () {
    final shifts = {'S1': _shift(overnight: true)};
    final ot = _run([_day(tIn: _at(9, 0), tOut: _at(23, 0), shiftId: 'S1')],
        shifts: shifts);
    expect(ot, isEmpty); // OT skipped for overnight
    final missing = _run([_day(tIn: _at(9, 0), tOut: null, shiftId: 'S1')],
        shifts: shifts);
    expect(missing.single.type, WarningType.missingClockOut);
  });

  test('today/future records are skipped', () {
    final w = _run([
      _day(tIn: _at(9, 0), tOut: null, shiftId: 'S1', date: _today)
    ]);
    expect(w, isEmpty);
  });

  test('record without a shift skips OT but still flags missing clock-out', () {
    final clean = _run([_day(tIn: _at(9, 0), tOut: _at(22, 0), shiftId: null)]);
    expect(clean, isEmpty); // no shift window → no OT warning, times valid
    final missing = _run([_day(tIn: _at(9, 0), tOut: null, shiftId: null)]);
    expect(missing.single.type, WarningType.missingClockOut);
  });

  test('warnings are sorted by date then employee', () {
    final w = _run([
      _day(tIn: _at(9, 0), tOut: null, shiftId: 'S1', date: DateTime(2026, 6, 17)),
      _day(tIn: _at(9, 0), tOut: null, shiftId: 'S1', date: DateTime(2026, 6, 15)),
    ]);
    expect(w.first.date, DateTime(2026, 6, 15));
    expect(w.last.date, DateTime(2026, 6, 17));
  });

  test('early-in approval flag suppresses the overtime warning', () {
    final w = _run([
      _day(tIn: _at(8, 20), tOut: _at(18, 0), shiftId: 'S1', earlyInApproved: true)
    ]);
    expect(w, isEmpty);
  });

  test('clock-out equal to clock-in is also flagged as invalid', () {
    final w = _run([_day(tIn: _at(9, 0), tOut: _at(9, 0), shiftId: 'S1')]);
    expect(w.single.type, WarningType.invalidWorkedTime);
  });

  test('a future-dated record is skipped', () {
    final w = _run([
      _day(tIn: _at(9, 0), tOut: null, shiftId: 'S1', date: DateTime(2026, 7, 5))
    ]);
    expect(w, isEmpty);
  });

  test('same-date warnings are sorted by employee label', () {
    final date = DateTime(2026, 6, 15);
    final zara = _day(tIn: _at(9, 0), tOut: null, shiftId: 'S1', date: date, empFirst: 'Zara');
    final alice = _day(tIn: _at(9, 0), tOut: null, shiftId: 'S1', date: date, empFirst: 'Alice');
    final w = detectWarnings(records: [zara, alice], shiftsById: {'S1': _shift()}, today: _today);
    expect(w.first.employeeLabel, contains('Alice'));
    expect(w.last.employeeLabel, contains('Zara'));
  });

  test('exactly 30 min late-out is not flagged (threshold is > 30)', () {
    final w = _run([_day(tIn: _at(9, 0), tOut: _at(18, 30), shiftId: 'S1')]);
    expect(w, isEmpty);
  });

  test('31 min late-out is flagged as unapproved overtime', () {
    final w = _run([_day(tIn: _at(9, 0), tOut: _at(18, 31), shiftId: 'S1')]);
    expect(w.single.type, WarningType.unapprovedOvertime);
  });

  test('both-ends unapproved OT message names both ends', () {
    final w = _run([_day(tIn: _at(8, 20), tOut: _at(18, 45), shiftId: 'S1')]);
    expect(w.single.type, WarningType.unapprovedOvertime);
    expect(w.single.message, contains('past shift end'));
    expect(w.single.message, contains('before shift start'));
  });
}
