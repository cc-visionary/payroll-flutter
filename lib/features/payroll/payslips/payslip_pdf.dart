import 'dart:typed_data';

import 'package:decimal/decimal.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

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
  /// Optional company logo bytes (PNG or JPG). When supplied, the header
  /// renders the logo to the left of the company name — otherwise the name
  /// stands alone. Caller is responsible for decoding from wherever the
  /// company row stores it (e.g. a `companies.logo_url` Supabase Storage
  /// path, base64 blob, local asset, etc.).
  final Uint8List? companyLogoBytes;
  /// Height (in PDF points) to render the logo at. Per-brand because
  /// different source PNGs bake in different amounts of transparent
  /// padding — the Luxium asset has significant whitespace, so its
  /// rendered visual would look ~40% smaller than GameCove's at the
  /// same container height. Defaults to 48.
  final double companyLogoHeight;
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
    this.companyLogoBytes,
    this.companyLogoHeight = 48,
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

  // Load Inter from Google Fonts as the PDF typeface.
  //
  //   - Light (300) is the default body weight — matches the "lean" look
  //     the user asked for instead of the heavy Satoshi-Variable default.
  //   - SemiBold (600) is used wherever pw.FontWeight.bold is set (title,
  //     table headers, totals, labels).
  //   - Italic + BoldItalic round out the theme so no text falls back to
  //     Helvetica (which doesn't support ₱ and triggers a Unicode warning).
  //
  // PdfGoogleFonts caches font bytes after first fetch; cold-start requires
  // network once per host but subsequent renders are offline.
  final base = await PdfGoogleFonts.interLight();
  final bold = await PdfGoogleFonts.interSemiBold();
  final italic = await PdfGoogleFonts.interLightItalic();
  final boldItalic = await PdfGoogleFonts.interSemiBoldItalic();
  final theme = pw.ThemeData.withFont(
    base: base,
    bold: bold,
    italic: italic,
    boldItalic: boldItalic,
  );
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
  final logoBytes = i.companyLogoBytes;
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      // Logo-first branding: when a logo is supplied it REPLACES the
      // company-name text block entirely. Rendering both would be
      // redundant — the mark already identifies the entity. When no
      // logo is present we fall back to the stacked name / trade name /
      // address text block so the document is still self-identifying.
      if (logoBytes != null)
        pw.Expanded(
          child: pw.Align(
            alignment: pw.Alignment.centerLeft,
            child: pw.Container(
              height: i.companyLogoHeight,
              child: pw.Image(
                pw.MemoryImage(logoBytes),
                fit: pw.BoxFit.contain,
                alignment: pw.Alignment.centerLeft,
              ),
            ),
          ),
        )
      else
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                i.companyTradeName ?? i.companyName,
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                  color: primary,
                ),
              ),
              if (i.companyTradeName != null &&
                  i.companyTradeName != i.companyName)
                pw.Text(i.companyName,
                    style: const pw.TextStyle(
                        fontSize: 9, color: PdfColors.grey700)),
              if (i.companyAddress != null)
                pw.Text(i.companyAddress!,
                    style: const pw.TextStyle(
                        fontSize: 9, color: PdfColors.grey700)),
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
  // Sort by the engine's calculation order (Basic Pay 100 → OT 200 →
  // Night Diff 300 → Holiday Pay 400-500 → Allowances / Commissions /
  // Reimbursements / Adjustments 500-900) so the payslip reads the way
  // payroll is actually computed. Ties fall back to the DB insertion order.
  final rows = p.lines
      .where((l) => _earningCats.contains(l.category))
      .toList()
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  return _sectionTable('EARNINGS', rows, p.totalEarnings);
}

pw.Widget _deductionsTable(Payslip p) {
  final rows = p.lines
      .where((l) => _deductionCats.contains(l.category))
      .toList()
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  return _sectionTable('DEDUCTIONS', rows, p.totalDeductions);
}

/// Render a tabular earnings/deductions block with Qty · Rate · Mult ·
/// Amount columns (mirrors the compute engine's internal breakdown). Cells
/// collapse to `-` when the line doesn't carry that dimension (e.g. a flat
/// reimbursement has no rate or multiplier). Hyphen, not em-dash — the
/// bundled Helvetica has no glyph for U+2014 and renders it as tofu.
pw.Widget _sectionTable(String title, List<PayslipLine> rows, Decimal total) {
  final headerStyle =
      pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold);
  const cellStyle = pw.TextStyle(fontSize: 9);
  const qtyFlex = 12;
  const rateFlex = 16;
  const multFlex = 10;
  const amountFlex = 18;
  const descFlex = 44;

  String fmtQty(Decimal? q) =>
      q == null ? '-' : q.toDouble().toStringAsFixed(3);

  /// Infer the rate's unit from the line description — the engine already
  /// embeds "5.000 days" / "480.000 mins" / "8 hours" in the description
  /// text, so no DB schema change is needed. Returns a trailing suffix
  /// like "/day" or empty string if nothing matches (flat amounts like
  /// commissions / bonuses have no unit).
  String unitSuffix(PayslipLine l) {
    final d = l.description.toLowerCase();
    if (RegExp(r'\bdays?\b').hasMatch(d)) return '/day';
    if (RegExp(r'\bmins?\b|\bminutes?\b').hasMatch(d)) return '/min';
    if (RegExp(r'\bhours?\b|\bhrs?\b').hasMatch(d)) return '/hr';
    return '';
  }

  String fmtRate(PayslipLine l) {
    final r = l.rate;
    if (r == null) return '-';
    return '${r.toDouble().toStringAsFixed(3)}${unitSuffix(l)}';
  }

  String fmtMult(Decimal? m) {
    if (m == null) return '-';
    // `1.25x` reads cleaner than `1.250` for multipliers.
    final s = m.toDouble();
    return '${s.toStringAsFixed(s == s.roundToDouble() ? 0 : 2)}x';
  }

  // Wrap each cell in a padded container with fixed alignment. Using
  // `pw.Table` (vs Row+Padding) gives us horizontal dividers between
  // rows for free — multi-line descriptions ("photocopy for sec cert sa
  // pagibig...") now cleanly own their row with no ambiguity about
  // which values belong to which line.
  pw.Widget cell(pw.Widget child, {pw.Alignment? align}) => pw.Container(
        alignment: align,
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: child,
      );
  pw.Widget headerText(String label,
          {pw.TextAlign align = pw.TextAlign.right}) =>
      pw.Text(label, style: headerStyle, textAlign: align);
  pw.Widget bodyText(String text,
          {pw.TextAlign align = pw.TextAlign.right,
          bool bold = false,
          PdfColor? color}) =>
      pw.Text(
        text,
        style: bold
            ? pw.TextStyle(
                fontSize: 9, fontWeight: pw.FontWeight.bold, color: color)
            : cellStyle.copyWith(color: color),
        textAlign: align,
      );

  final columnWidths = <int, pw.TableColumnWidth>{
    0: pw.FlexColumnWidth(descFlex.toDouble()),
    1: pw.FlexColumnWidth(qtyFlex.toDouble()),
    2: pw.FlexColumnWidth(rateFlex.toDouble()),
    3: pw.FlexColumnWidth(multFlex.toDouble()),
    4: pw.FlexColumnWidth(amountFlex.toDouble()),
  };

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      // Section title bar — lives outside the table so it spans full width
      // as a solid block header.
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        color: PdfColors.grey200,
        child: pw.Text(title,
            style: pw.TextStyle(
                fontSize: 10, fontWeight: pw.FontWeight.bold)),
      ),
      pw.Table(
        columnWidths: columnWidths,
        // Thin border around the whole table + hairline dividers between
        // every row. `horizontalInside` is the key piece — it puts a
        // visible line between consecutive body rows so a wrapping
        // description can't bleed into the next line's values.
        border: pw.TableBorder(
          top: pw.BorderSide.none,
          bottom: pw.BorderSide.none,
          left: pw.BorderSide.none,
          right: pw.BorderSide.none,
          horizontalInside: pw.BorderSide(
            color: PdfColors.grey300,
            width: 0.5,
          ),
        ),
        children: [
          // Column headers
          pw.TableRow(
            children: [
              cell(headerText('Description', align: pw.TextAlign.left),
                  align: pw.Alignment.centerLeft),
              cell(headerText('Qty'), align: pw.Alignment.centerRight),
              cell(headerText('Rate'), align: pw.Alignment.centerRight),
              cell(headerText('Mult'), align: pw.Alignment.centerRight),
              cell(headerText('Amount'), align: pw.Alignment.centerRight),
            ],
          ),
          // Body rows — one per payslip line. Table guarantees each row's
          // cells share the same baseline/height, so a 2-line description
          // pushes all five cells of THAT row down together, not just the
          // description column.
          for (final l in rows)
            pw.TableRow(
              children: [
                cell(bodyText(l.description, align: pw.TextAlign.left),
                    align: pw.Alignment.centerLeft),
                cell(bodyText(fmtQty(l.quantity)),
                    align: pw.Alignment.centerRight),
                cell(bodyText(fmtRate(l)),
                    align: pw.Alignment.centerRight),
                cell(bodyText(fmtMult(l.multiplier)),
                    align: pw.Alignment.centerRight),
                cell(bodyText(Money.fmtPhpAscii(l.amount)),
                    align: pw.Alignment.centerRight),
              ],
            ),
          // Total row
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColors.grey100),
            children: [
              cell(
                bodyText('Total ${title.toLowerCase()}',
                    align: pw.TextAlign.left, bold: true),
                align: pw.Alignment.centerLeft,
              ),
              cell(pw.SizedBox(), align: pw.Alignment.centerRight),
              cell(pw.SizedBox(), align: pw.Alignment.centerRight),
              cell(pw.SizedBox(), align: pw.Alignment.centerRight),
              cell(bodyText(Money.fmtPhpAscii(total), bold: true),
                  align: pw.Alignment.centerRight),
            ],
          ),
        ],
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

pw.Widget _signatureBlock(PayslipPdfInput i) {
  // Employee signature removed — receipt is captured via Lark approval
  // (see send-payslip-approvals edge function). Only the HR
  // authorized-representative name + title remains under the sign line.
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
              'Brixter Del Mundo',
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.Text(
              'HR Manager',
              style: const pw.TextStyle(
                fontSize: 9,
                color: PdfColors.grey700,
              ),
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

// Fixed height for every summary tile so the row stays symmetrical — the
// WORK DAYS tile needs a progress bar underneath, which makes it naturally
// taller than the other four; we pin them all to this value so they line up.
const double _kSummaryTileHeight = 58;

pw.Widget _summaryTile(String label, String value, String? unit,
    {PdfColor? color}) {
  return pw.Container(
    height: _kSummaryTileHeight,
    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: pw.BoxDecoration(
      color: PdfColor.fromHex('#F5F9FC'),
      borderRadius: pw.BorderRadius.circular(4),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
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
    'DATE', 'DAY', 'SHIFT', 'CLOCK IN', 'CLOCK OUT',
    'MINS', 'STATUS', 'DEDUCTION', 'OVERTIME',
  ];
  // Small-caps, letter-spaced header — reads as a proper table header
  // instead of just another body row. Right-aligned columns match the
  // numeric content below them.
  final headerStyle = pw.TextStyle(
    fontSize: 7.5,
    fontWeight: pw.FontWeight.bold,
    color: PdfColors.grey700,
    letterSpacing: 0.5,
  );
  final cellStyle = const pw.TextStyle(fontSize: 8);
  const rightAlignedCols = {5, 7, 8}; // Mins, Deduction, Overtime

  return pw.Table(
    // Only horizontal dividers — vertical lines make a dense 9-column
    // table read like a spreadsheet. Horizontal hairlines alone give
    // enough row separation when combined with zebra striping below.
    border: pw.TableBorder(
      horizontalInside: pw.BorderSide(color: PdfColors.grey200, width: 0.5),
    ),
    // Rebalanced widths — Status was previously 2.2 flex, which left a lot
    // of whitespace after the pill (the longest label "Regular Holiday"
    // only needs ~70pt). Narrowed to 1.5 and gave the reclaimed space
    // back to Shift / Clock In / Clock Out so the full time ranges
    // don't feel cramped.
    columnWidths: const {
      0: pw.FlexColumnWidth(0.9), // Date
      1: pw.FlexColumnWidth(0.6), // Day
      2: pw.FlexColumnWidth(1.4), // Shift
      3: pw.FlexColumnWidth(1.1), // Clock In
      4: pw.FlexColumnWidth(1.1), // Clock Out
      5: pw.FlexColumnWidth(0.9), // Mins
      6: pw.FlexColumnWidth(1.5), // Status (pill + optional holiday name)
      7: pw.FlexColumnWidth(0.9), // Deduction
      8: pw.FlexColumnWidth(0.9), // Overtime
    },
    children: [
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey100),
        children: [
          for (var i = 0; i < headers.length; i++)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 6,
              ),
              child: pw.Text(
                headers[i],
                style: headerStyle,
                textAlign: rightAlignedCols.contains(i)
                    ? pw.TextAlign.right
                    : pw.TextAlign.left,
              ),
            ),
        ],
      ),
      for (var i = 0; i < rows.length; i++)
        _attendanceRow(
          rows[i],
          cellStyle,
          // Zebra stripes on odd rows — subtle (#FAFBFC) so the colored
          // status pills still carry the visual weight.
          striped: i.isOdd,
        ),
    ],
  );
}

pw.TableRow _attendanceRow(
  AttendanceRowVm row,
  pw.TextStyle cellStyle, {
  required bool striped,
}) {
  final r = row.record;
  final shift = row.shift;
  final shiftText = shift == null
      ? '-'
      : '${_fmtShiftTime(shift.startTime)} - ${_fmtShiftTime(shift.endTime)}';
  final clockInText = _fmtClock(r?.actualTimeIn);
  final clockOutText = _fmtClock(r?.actualTimeOut);
  final mins = row.workedMinutes;
  // Drop the "mins" suffix — the column header already implies the unit
  // and the repetition steals horizontal space on every row.
  final minsText = mins == null ? '-' : mins.toStringAsFixed(3);
  final deduction = row.netDeductionMinutes;
  final overtime = row.netOvertimeMinutes;

  // Late clock-in / early clock-out detection. Tinting the time red
  // surfaces exceptions without the reader needing to compare against
  // the shift column manually. Skips when no shift is assigned.
  PdfColor? clockInColor;
  PdfColor? clockOutColor;
  if (shift != null && r?.actualTimeIn != null && r?.actualTimeOut != null) {
    final schedStart = applyTime(row.date, shift.startTime);
    final schedEnd = applyTime(row.date, shift.endTime);
    if (r!.actualTimeIn!.toLocal().isAfter(schedStart)) {
      clockInColor = PdfColors.red700;
    }
    if (r.actualTimeOut!.toLocal().isBefore(schedEnd)) {
      clockOutColor = PdfColors.red700;
    }
  }

  // Weekend rows get a faint warm tint so rest days pop even without
  // reading the Status column. Zebra striping applies underneath.
  final weekday = row.date.weekday;
  final isWeekend =
      weekday == DateTime.saturday || weekday == DateTime.sunday;
  final PdfColor? bg = isWeekend
      ? PdfColor.fromHex('#F9FAFB')
      : (striped ? PdfColor.fromHex('#FAFBFC') : null);

  return pw.TableRow(
    decoration: bg == null ? null : pw.BoxDecoration(color: bg),
    children: [
      _cell(_fmtShortDate(row.date), cellStyle),
      _cell(
        _weekdayShort(weekday),
        cellStyle,
        color: isWeekend ? PdfColors.grey600 : null,
      ),
      _cell(shiftText, cellStyle, color: PdfColors.grey700),
      _cell(clockInText, cellStyle,
          color: clockInColor,
          bold: clockInColor != null),
      _cell(clockOutText, cellStyle,
          color: clockOutColor,
          bold: clockOutColor != null),
      _cell(minsText, cellStyle, align: pw.TextAlign.right),
      _statusCell(row.status, row.holidayName, cellStyle),
      _cell(
        deduction > 0 ? deduction.toStringAsFixed(3) : '-',
        cellStyle,
        align: pw.TextAlign.right,
        color: deduction > 0 ? PdfColors.red700 : PdfColors.grey400,
        bold: deduction > 0,
      ),
      _cell(
        overtime > 0 ? overtime.toStringAsFixed(3) : '-',
        cellStyle,
        align: pw.TextAlign.right,
        color: overtime > 0 ? PdfColors.green700 : PdfColors.grey400,
        bold: overtime > 0,
      ),
    ],
  );
}

pw.Widget _cell(
  String text,
  pw.TextStyle style, {
  pw.TextAlign? align,
  PdfColor? color,
  bool bold = false,
}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
    child: pw.Text(
      text,
      style: style.copyWith(
        color: color,
        fontWeight: bold ? pw.FontWeight.bold : null,
      ),
      textAlign: align,
    ),
  );
}

/// Status cell renders the label as a colored pill. Each status carries
/// its own bg/fg tint so "Absent", "Present", "Rest Day", etc. pop at a
/// glance without the reader having to parse the word on every row.
/// Holiday rows stack the holiday name underneath in 7pt grey.
pw.Widget _statusCell(
    String status, String? holidayName, pw.TextStyle style) {
  final (label, bg, fg) = _statusPillPalette(status);
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: pw.BoxDecoration(
            color: bg,
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 7.5,
              fontWeight: pw.FontWeight.bold,
              color: fg,
            ),
          ),
        ),
        if (holidayName != null)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 1),
            child: pw.Text(
              holidayName,
              style: style.copyWith(color: PdfColors.grey600, fontSize: 7),
            ),
          ),
      ],
    ),
  );
}

/// (human label, background tint, foreground text) per status. Colors are
/// Tailwind-100/700 pairs — high contrast for print, muted enough that a
/// single page of all-Present doesn't look like a Christmas tree.
(String, PdfColor, PdfColor) _statusPillPalette(String status) {
  switch (status) {
    case 'PRESENT':
      return (
        'Present',
        PdfColor.fromHex('#DCFCE7'),
        PdfColor.fromHex('#166534'),
      );
    case 'HALF_DAY':
      return (
        'Half Day',
        PdfColor.fromHex('#FEF3C7'),
        PdfColor.fromHex('#92400E'),
      );
    case 'ABSENT':
      return (
        'Absent',
        PdfColor.fromHex('#FEE2E2'),
        PdfColor.fromHex('#991B1B'),
      );
    case 'ON_LEAVE':
      return (
        'On Leave',
        PdfColor.fromHex('#EDE9FE'),
        PdfColor.fromHex('#5B21B6'),
      );
    case 'REST_DAY':
      return (
        'Rest Day',
        PdfColor.fromHex('#F3F4F6'),
        PdfColor.fromHex('#4B5563'),
      );
    case 'REGULAR_HOLIDAY':
      return (
        'Regular Holiday',
        PdfColor.fromHex('#FED7AA'),
        PdfColor.fromHex('#9A3412'),
      );
    case 'SPECIAL_HOLIDAY':
      return (
        'Special Holiday',
        PdfColor.fromHex('#FEF3C7'),
        PdfColor.fromHex('#92400E'),
      );
    case 'SPECIAL_WORKING':
      return (
        'Special Working',
        PdfColor.fromHex('#DBEAFE'),
        PdfColor.fromHex('#1E40AF'),
      );
    case 'HOLIDAY':
      return (
        'Holiday',
        PdfColor.fromHex('#FEF3C7'),
        PdfColor.fromHex('#92400E'),
      );
    case 'NO_DATA':
      return (
        '-',
        PdfColor.fromHex('#F3F4F6'),
        PdfColor.fromHex('#9CA3AF'),
      );
    default:
      return (
        status,
        PdfColor.fromHex('#F3F4F6'),
        PdfColor.fromHex('#4B5563'),
      );
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
