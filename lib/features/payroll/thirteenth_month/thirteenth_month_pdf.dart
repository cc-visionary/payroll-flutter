import 'dart:typed_data';

import 'package:decimal/decimal.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/money.dart';
import '../../../data/models/employee.dart';
import '../../../data/repositories/payroll_repository.dart';

/// All inputs the 13th-month breakdown PDF needs. Mirrors the payslip PDF
/// pipeline so company branding (logo, name, trade name, address) renders
/// identically across both documents.
class ThirteenthMonthPdfInput {
  final Employee employee;
  final ThirteenthMonthBreakdown breakdown;
  final DateTime from;
  final DateTime to;
  final String companyName;
  final String? companyTradeName;
  final String? companyAddress;
  final Uint8List? companyLogoBytes;
  final double companyLogoHeight;

  const ThirteenthMonthPdfInput({
    required this.employee,
    required this.breakdown,
    required this.from,
    required this.to,
    required this.companyName,
    this.companyTradeName,
    this.companyAddress,
    this.companyLogoBytes,
    this.companyLogoHeight = 48,
  });
}

const _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _date(DateTime d) => '${_monthNames[d.month - 1]} ${d.day}, ${d.year}';

String _fmtDays(Decimal d) {
  final s = d.toString();
  if (!s.contains('.')) return '$s days';
  var trimmed = s.replaceFirst(RegExp(r'0+$'), '');
  if (trimmed.endsWith('.')) {
    trimmed = trimmed.substring(0, trimmed.length - 1);
  }
  return '$trimmed ${d == Decimal.one ? "day" : "days"}';
}

String _periodLabel(ThirteenthMonthContribution c) {
  final s = c.periodStart;
  final e = c.periodEnd;
  if (s == null && e == null) {
    return c.payDate == null ? '—' : 'Pay ${_date(c.payDate!)}';
  }
  if (s != null && e != null) {
    final sameMonth = s.year == e.year && s.month == e.month;
    if (sameMonth) {
      return '${_monthNames[s.month - 1]} ${s.day}–${e.day}, ${s.year}';
    }
    final sameYear = s.year == e.year;
    if (sameYear) {
      return '${_monthNames[s.month - 1]} ${s.day} – '
          '${_monthNames[e.month - 1]} ${e.day}, ${s.year}';
    }
    return '${_date(s)} – ${_date(e)}';
  }
  return _date((s ?? e)!);
}

Future<Uint8List> buildThirteenthMonthPdf(ThirteenthMonthPdfInput input) async {
  final doc = pw.Document(
    title: '13th Month — ${input.employee.fullName}',
    author: input.companyName,
  );

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
  final primary = PdfColor.fromHex('#4338CA');
  final tableHead = PdfColor.fromHex('#EEF2FF');

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(32, 32, 32, 32),
      theme: theme,
      build: (_) => [
        _header(input, primary),
        pw.SizedBox(height: 12),
        pw.Divider(color: PdfColors.grey400, height: 1),
        pw.SizedBox(height: 12),
        _employeeBlock(input),
        pw.SizedBox(height: 14),
        _summaryBox(input, primary),
        pw.SizedBox(height: 14),
        _breakdownTable(input, primary, tableHead),
        pw.SizedBox(height: 12),
        _formulaFooter(input, primary),
        pw.SizedBox(height: 24),
        pw.Text(
          'This document is system-generated · contact HR for corrections.',
          style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          textAlign: pw.TextAlign.center,
        ),
      ],
    ),
  );

  return doc.save();
}

pw.Widget _header(ThirteenthMonthPdfInput i, PdfColor primary) {
  final logo = i.companyLogoBytes;
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      if (logo != null)
        pw.Expanded(
          child: pw.Align(
            alignment: pw.Alignment.centerLeft,
            child: pw.Container(
              height: i.companyLogoHeight,
              child: pw.Image(
                pw.MemoryImage(logo),
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
          pw.Text('13TH MONTH',
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.Text('Accrual Breakdown',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
          pw.Text('Range: ${_date(i.from)} – ${_date(i.to)}',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        ],
      ),
    ],
  );
}

pw.Widget _employeeBlock(ThirteenthMonthPdfInput i) {
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
              _kv('Employee', e.fullName),
              _kv('Employee #', e.employeeNumber),
              if (e.jobTitle != null) _kv('Position', e.jobTitle!),
            ],
          ),
        ),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _kv('Employment',
                  '${e.employmentType} · ${e.employmentStatus}'),
              _kv('Hire Date', _date(e.hireDate)),
              if (e.separationDate != null)
                _kv('Separation Date', _date(e.separationDate!)),
            ],
          ),
        ),
      ],
    ),
  );
}

pw.Widget _kv(String label, String value) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(children: [
      pw.SizedBox(
        width: 80,
        child: pw.Text(label,
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
      ),
      pw.Expanded(
        child: pw.Text(value,
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
      ),
    ]),
  );
}

pw.Widget _summaryBox(ThirteenthMonthPdfInput i, PdfColor primary) {
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: pw.BoxDecoration(
      color: PdfColor.fromHex('#EEF2FF'),
      borderRadius: pw.BorderRadius.circular(6),
    ),
    child: pw.Row(
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('13th Month Accrued',
                  style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                      color: primary)),
              pw.Text(
                'Payout at year-end or separation · Scoped to selected date range',
                style: pw.TextStyle(
                    fontSize: 9, color: PdfColor.fromHex('#6366F1')),
              ),
            ],
          ),
        ),
        pw.Text(
          Money.fmtPhp(i.breakdown.thirteenthMonthPayout),
          style: pw.TextStyle(
              fontSize: 20, fontWeight: pw.FontWeight.bold, color: primary),
        ),
      ],
    ),
  );
}

pw.Widget _breakdownTable(
    ThirteenthMonthPdfInput i, PdfColor primary, PdfColor headBg) {
  final rows = i.breakdown.contributions;

  pw.Widget th(String label, {bool end = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: pw.Text(label,
            textAlign: end ? pw.TextAlign.right : pw.TextAlign.left,
            style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: primary)),
      );

  pw.Widget td(String text, {bool end = false, PdfColor? color}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: pw.Text(text,
            textAlign: end ? pw.TextAlign.right : pw.TextAlign.left,
            style: pw.TextStyle(
                fontSize: 9, color: color ?? PdfColors.grey800)),
      );

  pw.Widget basicCell(ThirteenthMonthContribution c) {
    final items = c.basicItems
        .where((b) => b.days > Decimal.zero && b.rate > Decimal.zero)
        .toList();
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          for (final item in items)
            pw.Text(
              '${_fmtDays(item.days)} × ${Money.fmtPhp(item.rate)}',
              style: const pw.TextStyle(
                  fontSize: 8, color: PdfColors.grey700),
            ),
          pw.Text(
            Money.fmtPhp(c.basicPay),
            style: pw.TextStyle(
                fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
    );
  }

  return pw.Table(
    border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
    columnWidths: const {
      0: pw.FlexColumnWidth(2.4),
      1: pw.FlexColumnWidth(2.0),
      2: pw.FlexColumnWidth(1.4),
      3: pw.FlexColumnWidth(1.6),
    },
    children: [
      pw.TableRow(
        decoration: pw.BoxDecoration(color: headBg),
        children: [
          th('Period'),
          th('Basic Pay', end: true),
          th('Late/UT', end: true),
          th('Net Basic', end: true),
        ],
      ),
      for (final c in rows)
        pw.TableRow(children: [
          td(_periodLabel(c)),
          basicCell(c),
          td(
            c.lateDeduction <= Decimal.zero
                ? '—'
                : '−${Money.fmtPhp(c.lateDeduction)}',
            end: true,
            color: c.lateDeduction <= Decimal.zero
                ? PdfColors.grey500
                : PdfColor.fromHex('#B91C1C'),
          ),
          td(Money.fmtPhp(c.netBasic), end: true),
        ]),
      pw.TableRow(
        decoration: pw.BoxDecoration(color: PdfColor.fromHex('#F5F3FF')),
        children: [
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: pw.Text('Total (${rows.length} release${rows.length == 1 ? '' : 's'})',
                style: pw.TextStyle(
                    fontSize: 9, fontWeight: pw.FontWeight.bold, color: primary)),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: pw.Text(Money.fmtPhp(i.breakdown.totalBasic),
                textAlign: pw.TextAlign.right,
                style: pw.TextStyle(
                    fontSize: 9, fontWeight: pw.FontWeight.bold)),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: pw.Text(
                i.breakdown.totalLate <= Decimal.zero
                    ? '—'
                    : '−${Money.fmtPhp(i.breakdown.totalLate)}',
                textAlign: pw.TextAlign.right,
                style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    color: i.breakdown.totalLate <= Decimal.zero
                        ? PdfColors.grey500
                        : PdfColor.fromHex('#B91C1C'))),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: pw.Text(Money.fmtPhp(i.breakdown.totalNetBasic),
                textAlign: pw.TextAlign.right,
                style: pw.TextStyle(
                    fontSize: 9, fontWeight: pw.FontWeight.bold)),
          ),
        ],
      ),
    ],
  );
}

pw.Widget _formulaFooter(ThirteenthMonthPdfInput i, PdfColor primary) {
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: pw.BoxDecoration(
      color: PdfColor.fromHex('#EEF2FF'),
      borderRadius: pw.BorderRadius.circular(6),
    ),
    child: pw.Row(
      children: [
        pw.Expanded(
          child: pw.Text(
            '13th Month = ${Money.fmtPhp(i.breakdown.totalNetBasic)} ÷ 12',
            style: pw.TextStyle(
                fontSize: 10, fontWeight: pw.FontWeight.bold, color: primary),
          ),
        ),
        pw.Text(
          Money.fmtPhp(i.breakdown.thirteenthMonthPayout),
          style: pw.TextStyle(
              fontSize: 14, fontWeight: pw.FontWeight.bold, color: primary),
        ),
      ],
    ),
  );
}
