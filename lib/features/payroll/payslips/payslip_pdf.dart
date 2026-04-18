import 'dart:typed_data';

import 'package:decimal/decimal.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/money.dart';
import '../../../data/models/employee.dart';
import '../../../data/models/payslip.dart';
import '../../attendance/attendance_row_vm.dart';

class PayslipPdfInput {
  final Payslip payslip;
  final Employee employee;
  final String companyName;
  final String? companyTradeName;
  final String? companyAddress;
  final DateTime periodStart;
  final DateTime periodEnd;
  final DateTime payDate;
  /// Daily attendance rows for the pay period. When non-empty, the PDF grows
  /// a landscape page 2 with one row per calendar day. When null/empty, the
  /// PDF stays single-page — keeps the test fixture and legacy callers
  /// working without forcing them to assemble attendance data.
  final List<AttendanceRowVm>? attendanceRows;

  const PayslipPdfInput({
    required this.payslip,
    required this.employee,
    required this.companyName,
    this.companyTradeName,
    this.companyAddress,
    required this.periodStart,
    required this.periodEnd,
    required this.payDate,
    this.attendanceRows,
  });
}

/// Builds the payslip PDF. Layout mirrors payrollos pdfkit output:
/// header - employee block - earnings table - deductions table - YTD block - signature.
Future<Uint8List> buildPayslipPdf(PayslipPdfInput input) async {
  final doc = pw.Document(
    title: 'Payslip — ${input.employee.fullName}',
    author: input.companyName,
  );

  final theme = pw.ThemeData.base();
  final primary = PdfColor.fromHex('#0EA5E9');
  final rule = pw.Divider(color: PdfColors.grey400, height: 1);

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(32, 32, 32, 32),
      theme: theme,
      build: (ctx) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            _header(input, primary),
            pw.SizedBox(height: 12),
            rule,
            pw.SizedBox(height: 12),
            _employeeBlock(input),
            pw.SizedBox(height: 16),
            _earningsTable(input.payslip),
            pw.SizedBox(height: 8),
            _deductionsTable(input.payslip),
            pw.SizedBox(height: 12),
            _totalsBlock(input.payslip, primary),
            pw.SizedBox(height: 16),
            _ytdBlock(input.payslip),
            pw.Spacer(),
            _signatureBlock(input),
            pw.SizedBox(height: 8),
            pw.Text(
              'Receipt of this payslip is acknowledged via Lark approval. '
              'This document is system-generated - contact HR for corrections.',
              style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
              textAlign: pw.TextAlign.center,
            ),
          ],
        );
      },
    ),
  );

  final attendance = input.attendanceRows;
  if (attendance != null && attendance.isNotEmpty) {
    // Daily attendance lands on a landscape page 2 so the 9-column table
    // doesn't wrap. MultiPage so the period can span >~30 rows on page 2.
    //
    // All rows share the same scorecard, so we read workDaysPerWeek off
    // the first row to feed AttendanceStats.from — ensures the PDF
    // summary matches the employee-profile Attendance tab exactly.
    final stats = AttendanceStats.from(
      attendance,
      workDaysPerWeek: attendance.first.workDaysPerWeek,
    );
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.fromLTRB(32, 28, 32, 28),
        theme: theme,
        header: (_) => _attendanceHeader(input),
        build: (_) => [
          _attendanceSummary(stats),
          pw.SizedBox(height: 12),
          _attendanceTable(attendance),
        ],
      ),
    );
  }

  return doc.save();
}

pw.Widget _header(PayslipPdfInput i, PdfColor primary) {
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              i.companyTradeName ?? i.companyName,
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: primary),
            ),
            if (i.companyTradeName != null && i.companyTradeName != i.companyName)
              pw.Text(i.companyName, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
            if (i.companyAddress != null)
              pw.Text(i.companyAddress!, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
          ],
        ),
      ),
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Text('PAYSLIP', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.Text(i.payslip.payslipNumber ?? i.payslip.id.substring(0, 8).toUpperCase(),
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
          pw.Text('Pay Date: ${_date(i.payDate)}',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        ],
      ),
    ],
  );
}

pw.Widget _employeeBlock(PayslipPdfInput i) {
  final e = i.employee;
  return pw.Container(
    padding: const pw.EdgeInsets.all(10),
    decoration: pw.BoxDecoration(
      color: PdfColor.fromHex('#F5F9FC'),
      borderRadius: pw.BorderRadius.circular(4),
    ),
    child: pw.Row(
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _labelValue('Employee', e.fullName),
              _labelValue('Employee #', e.employeeNumber),
              if (e.jobTitle != null) _labelValue('Position', e.jobTitle!),
            ],
          ),
        ),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _labelValue('Period', '${_date(i.periodStart)} - ${_date(i.periodEnd)}'),
              _labelValue('Employment', '${e.employmentType} · ${e.employmentStatus}'),
              _labelValue('Hire Date', _date(e.hireDate)),
            ],
          ),
        ),
      ],
    ),
  );
}

pw.Widget _labelValue(String label, String value) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(children: [
      pw.SizedBox(
        width: 70,
        child: pw.Text(label, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
      ),
      pw.Expanded(
        child: pw.Text(value, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
      ),
    ]),
  );
}

const _earningCats = {
  'BASIC_PAY', 'OVERTIME_REGULAR', 'OVERTIME_REST_DAY', 'OVERTIME_HOLIDAY',
  'NIGHT_DIFFERENTIAL', 'HOLIDAY_PAY', 'REST_DAY_PAY', 'ALLOWANCE',
  'REIMBURSEMENT', 'INCENTIVE', 'BONUS', 'ADJUSTMENT_ADD', 'THIRTEENTH_MONTH_PAY',
  'TAX_REFUND',
};

const _deductionCats = {
  'LATE_DEDUCTION', 'UNDERTIME_DEDUCTION', 'LATE_UT_DEDUCTION', 'ABSENT_DEDUCTION',
  'SSS_EE', 'PHILHEALTH_EE', 'PAGIBIG_EE', 'TAX_WITHHOLDING',
  'CASH_ADVANCE_DEDUCTION', 'LOAN_DEDUCTION', 'ADJUSTMENT_DEDUCT',
  'OTHER_DEDUCTION', 'PENALTY_DEDUCTION',
};

pw.Widget _earningsTable(Payslip p) {
  final rows = p.lines.where((l) => _earningCats.contains(l.category)).toList();
  return _sectionTable('EARNINGS', rows, p.totalEarnings);
}

pw.Widget _deductionsTable(Payslip p) {
  final rows = p.lines.where((l) => _deductionCats.contains(l.category)).toList();
  return _sectionTable('DEDUCTIONS', rows, p.totalDeductions);
}

pw.Widget _sectionTable(String title, List<PayslipLine> rows, Decimal total) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        color: PdfColors.grey200,
        child: pw.Row(children: [
          pw.Expanded(
            child: pw.Text(title,
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          ),
          pw.Text('Amount',
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        ]),
      ),
      ...rows.map(
        (l) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: pw.Row(children: [
            pw.Expanded(child: pw.Text(l.description, style: const pw.TextStyle(fontSize: 9))),
            pw.Text(Money.fmtPhpAscii(l.amount), style: const pw.TextStyle(fontSize: 9)),
          ]),
        ),
      ),
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: pw.Row(children: [
          pw.Expanded(
            child: pw.Text('Total ${title.toLowerCase()}',
                style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
          ),
          pw.Text(Money.fmtPhpAscii(total),
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
        ]),
      ),
    ],
  );
}

pw.Widget _totalsBlock(Payslip p, PdfColor primary) {
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: pw.BoxDecoration(
      color: primary,
      borderRadius: pw.BorderRadius.circular(4),
    ),
    child: pw.Row(children: [
      pw.Expanded(
        child: pw.Text('NET PAY',
            style: pw.TextStyle(fontSize: 12, color: PdfColors.white, fontWeight: pw.FontWeight.bold)),
      ),
      pw.Text(Money.fmtPhpAscii(p.netPay),
          style: pw.TextStyle(fontSize: 14, color: PdfColors.white, fontWeight: pw.FontWeight.bold)),
    ]),
  );
}

pw.Widget _ytdBlock(Payslip p) {
  return pw.Container(
    padding: const pw.EdgeInsets.all(8),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.grey400),
      borderRadius: pw.BorderRadius.circular(4),
    ),
    child: pw.Column(children: [
      pw.Text('YEAR TO DATE',
          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
      pw.SizedBox(height: 4),
      pw.Row(children: [
        pw.Expanded(child: _ytdCell('Gross Pay', p.ytdGrossPay)),
        pw.Expanded(child: _ytdCell('Taxable Income', p.ytdTaxableIncome)),
        pw.Expanded(child: _ytdCell('Tax Withheld', p.ytdTaxWithheld)),
      ]),
    ]),
  );
}

pw.Widget _ytdCell(String label, Decimal value) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    children: [
      pw.Text(label, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
      pw.Text(Money.fmtPhpAscii(value),
          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
    ],
  );
}

pw.Widget _signatureBlock(PayslipPdfInput i) {
  // Employee signature removed — receipt is captured via Lark approval
  // (see send-payslip-approvals edge function). Only the HR authorized-
  // representative line remains.
  return pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.center,
    children: [
      pw.SizedBox(
        width: 240,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Container(
              height: 1,
              color: PdfColors.grey500,
              margin: const pw.EdgeInsets.symmetric(horizontal: 12),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              'Authorized Representative',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
          ],
        ),
      ),
    ],
  );
}

// ---------------------------------------------------------------------------
// Page 2 — daily attendance table.
// ---------------------------------------------------------------------------

pw.Widget _attendanceHeader(PayslipPdfInput i) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 10),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Daily Attendance',
                style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(
                '${i.employee.fullName} · ${i.employee.employeeNumber}',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
              ),
            ],
          ),
        ),
        pw.Text(
          '${_date(i.periodStart)}  to  ${_date(i.periodEnd)}',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
        ),
      ],
    ),
  );
}

/// Five stat tiles at the top of page 2 (Work Days ratio + Absent + Late/UT
/// + Overtime + On Leave). Layout matches the Attendance tab's `_StatsGrid`
/// primary row so the PDF reads like an official print-out of what the HR
/// admin saw on screen.
pw.Widget _attendanceSummary(AttendanceStats s) {
  String fmtMins(double mins) {
    if (mins < 0.001) return '-';
    return mins.toStringAsFixed(3);
  }

  final pct = s.workDays == 0
      ? 0.0
      : (s.present / s.workDays).clamp(0.0, 1.0);
  final pctLabel = s.workDays == 0 ? '' : '${(pct * 100).round()}%';

  // `crossAxisAlignment: stretch` would propagate the MultiPage's unbounded
  // height into each tile — pdf widgets then throw "height Infinity exceeds
  // page height". Default (start) lets each tile size to its own content.
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        child: _summaryWorkDays(
          present: s.present,
          total: s.workDays,
          pct: pct,
          pctLabel: pctLabel,
        ),
      ),
      pw.SizedBox(width: 8),
      pw.Expanded(
        child: _summaryTile(
          'ABSENT',
          s.absent.toString(),
          'days',
          color: s.absent > 0 ? PdfColors.red700 : null,
        ),
      ),
      pw.SizedBox(width: 8),
      pw.Expanded(
        child: _summaryTile(
          'LATE / UT',
          fmtMins(s.lateUndertimeMinutes),
          s.lateUndertimeMinutes < 0.001 ? null : 'mins',
          color: s.lateUndertimeMinutes > 0 ? PdfColors.orange700 : null,
        ),
      ),
      pw.SizedBox(width: 8),
      pw.Expanded(
        child: _summaryTile(
          'OVERTIME',
          fmtMins(s.otMinutes),
          s.otMinutes < 0.001 ? null : 'mins',
          color: s.otMinutes > 0 ? PdfColors.green700 : null,
        ),
      ),
      pw.SizedBox(width: 8),
      pw.Expanded(
        child: _summaryTile(
          'ON LEAVE',
          s.onLeave.toString(),
          'days',
          color: s.onLeave > 0 ? PdfColor.fromHex('#7C3AED') : null,
        ),
      ),
    ],
  );
}

pw.Widget _summaryTile(String label, String value, String? unit,
    {PdfColor? color}) {
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: pw.BoxDecoration(
      color: PdfColor.fromHex('#F5F9FC'),
      borderRadius: pw.BorderRadius.circular(4),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: 8,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.grey700,
            letterSpacing: 0.4,
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
                color: color,
              ),
            ),
            if (unit != null) ...[
              pw.SizedBox(width: 4),
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 2),
                child: pw.Text(
                  unit,
                  style: const pw.TextStyle(
                    fontSize: 9,
                    color: PdfColors.grey700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    ),
  );
}

pw.Widget _summaryWorkDays({
  required int present,
  required int total,
  required double pct,
  required String pctLabel,
}) {
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: pw.BoxDecoration(
      color: PdfColor.fromHex('#F5F9FC'),
      borderRadius: pw.BorderRadius.circular(4),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'WORK DAYS',
          style: pw.TextStyle(
            fontSize: 8,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.grey700,
            letterSpacing: 0.4,
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              '$present / $total',
              style: pw.TextStyle(
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.green700,
              ),
            ),
            pw.SizedBox(width: 4),
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 2),
              child: pw.Text(
                'days',
                style: const pw.TextStyle(
                  fontSize: 9,
                  color: PdfColors.grey700,
                ),
              ),
            ),
            pw.Spacer(),
            if (pctLabel.isNotEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 2),
                child: pw.Text(
                  pctLabel,
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.green700,
                  ),
                ),
              ),
          ],
        ),
        pw.SizedBox(height: 4),
        // Thin progress bar — pdf widgets lack FractionallySizedBox, so we
        // use flex ratios on two Expanded containers to render the fill.
        // `.clamp(1, 1000)` guards against flex=0 when the percentage
        // rounds down to nothing (Expanded with flex=0 throws).
        pw.ClipRRect(
          horizontalRadius: 2,
          verticalRadius: 2,
          child: pw.Container(
            height: 4,
            color: PdfColor.fromHex('#E5E7EB'),
            child: pw.Row(
              children: [
                if (pct > 0)
                  pw.Expanded(
                    flex: (pct * 1000).round().clamp(1, 1000),
                    child: pw.Container(color: PdfColors.green600),
                  ),
                if (pct < 1)
                  pw.Expanded(
                    flex: ((1 - pct) * 1000).round().clamp(1, 1000),
                    child: pw.SizedBox(),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

pw.Widget _attendanceTable(List<AttendanceRowVm> rows) {
  const headers = <String>[
    'Date', 'Day', 'Shift', 'Clock In', 'Clock Out',
    'Mins', 'Status', 'Deduction', 'Overtime',
  ];
  final headerStyle = pw.TextStyle(
    fontSize: 8,
    fontWeight: pw.FontWeight.bold,
    color: PdfColors.grey800,
  );
  final cellStyle = const pw.TextStyle(fontSize: 8);
  return pw.Table(
    border: pw.TableBorder.symmetric(
      inside: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
    ),
    columnWidths: const {
      0: pw.FlexColumnWidth(1.2), // Date
      1: pw.FlexColumnWidth(0.8), // Day
      2: pw.FlexColumnWidth(1.6), // Shift
      3: pw.FlexColumnWidth(1.2), // Clock In
      4: pw.FlexColumnWidth(1.2), // Clock Out
      5: pw.FlexColumnWidth(1.0), // Mins
      6: pw.FlexColumnWidth(2.0), // Status (may include holiday name)
      7: pw.FlexColumnWidth(1.1), // Deduction
      8: pw.FlexColumnWidth(1.1), // Overtime
    },
    children: [
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
        children: [
          for (final h in headers)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: pw.Text(h, style: headerStyle),
            ),
        ],
      ),
      for (final row in rows) _attendanceRow(row, cellStyle),
    ],
  );
}

pw.TableRow _attendanceRow(AttendanceRowVm row, pw.TextStyle cellStyle) {
  final r = row.record;
  final shift = row.shift;
  final shiftText = shift == null
      ? '-'
      : '${_fmtShiftTime(shift.startTime)} - ${_fmtShiftTime(shift.endTime)}';
  final clockIn = _fmtClock(r?.actualTimeIn);
  final clockOut = _fmtClock(r?.actualTimeOut);
  final mins = row.workedMinutes;
  final minsText = mins == null ? '-' : '${mins.toStringAsFixed(3)} mins';
  final deduction = row.netDeductionMinutes;
  final overtime = row.netOvertimeMinutes;
  final statusLabel = _statusLabel(row.status);
  final holidayName = row.holidayName;

  return pw.TableRow(
    children: [
      _cell(_fmtShortDate(row.date), cellStyle),
      _cell(_weekdayShort(row.date.weekday), cellStyle),
      _cell(shiftText, cellStyle),
      _cell(clockIn, cellStyle),
      _cell(clockOut, cellStyle),
      _cell(minsText, cellStyle, align: pw.TextAlign.right),
      _statusCell(statusLabel, holidayName, cellStyle),
      _cell(
        deduction > 0 ? '${deduction.toStringAsFixed(3)} mins' : '-',
        cellStyle,
        align: pw.TextAlign.right,
        color: deduction > 0 ? PdfColors.red700 : null,
      ),
      _cell(
        overtime > 0 ? '${overtime.toStringAsFixed(3)} mins' : '-',
        cellStyle,
        align: pw.TextAlign.right,
        color: overtime > 0 ? PdfColors.green700 : null,
      ),
    ],
  );
}

pw.Widget _cell(
  String text,
  pw.TextStyle style, {
  pw.TextAlign? align,
  PdfColor? color,
}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    child: pw.Text(
      text,
      style: color == null ? style : style.copyWith(color: color),
      textAlign: align,
    ),
  );
}

pw.Widget _statusCell(String label, String? holidayName, pw.TextStyle style) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Text(label, style: style),
        if (holidayName != null)
          pw.Text(
            holidayName,
            style: style.copyWith(color: PdfColors.grey700, fontSize: 7),
          ),
      ],
    ),
  );
}

String _statusLabel(String status) {
  switch (status) {
    case 'PRESENT':
      return 'Present';
    case 'ABSENT':
      return 'Absent';
    case 'REST_DAY':
      return 'Rest Day';
    case 'REGULAR_HOLIDAY':
      return 'Regular Holiday';
    case 'SPECIAL_HOLIDAY':
      return 'Special Holiday';
    case 'SPECIAL_WORKING':
      return 'Special Working';
    case 'ON_LEAVE':
      return 'On Leave';
    case 'HOLIDAY':
      return 'Holiday';
    case 'NO_DATA':
      return '-';
    default:
      return status;
  }
}

String _weekdayShort(int weekday) {
  const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return names[(weekday - 1).clamp(0, 6)];
}

String _fmtShortDate(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[d.month - 1]} ${d.day}';
}

String _fmtShiftTime(String hhmmss) {
  final parts = hhmmss.split(':');
  final h = parts[0].padLeft(2, '0');
  final m = (parts.length > 1 ? parts[1] : '00').padLeft(2, '0');
  return '$h:$m';
}

String _fmtClock(DateTime? t) {
  if (t == null) return '-';
  final local = t.toLocal();
  final h = local.hour;
  final m = local.minute.toString().padLeft(2, '0');
  final period = h >= 12 ? 'PM' : 'AM';
  final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
  return '${h12.toString().padLeft(2, '0')}:$m $period';
}

String _date(DateTime d) => d.toIso8601String().substring(0, 10);
