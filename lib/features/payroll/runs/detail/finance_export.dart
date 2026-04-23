import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Finance-tracking XLSX exporter — mirrors the cashflow log format used in
/// `[06] LUXIUM/[01] Finance/[01] Cashflow/[03] GC/gc-expenses.xlsx` so the
/// rows can be pasted directly into the per-brand cashflow sheet.
///
/// Columns (5):
///   Date | Description | Amount | Type | Brand
///
/// Description format (matches existing salary rows):
///   "{FirstName} {MonStart D} - {MonEnd D} Cutoff Salary"
///   e.g. "Jeremy Dec 30 - Jan 14 Cutoff Salary"
///
/// Brand is appended as a 5th column rather than inlined into the description
/// so the existing per-brand cashflow sheets can filter by it cleanly.

class FinanceExportRow {
  final DateTime date;
  final String description;
  final Decimal amount;
  final String type;
  final String brand;
  const FinanceExportRow({
    required this.date,
    required this.description,
    required this.amount,
    required this.type,
    required this.brand,
  });

  factory FinanceExportRow.fromPayslipRow(
    Map<String, dynamic> r, {
    required DateTime payDate,
    required DateTime periodStart,
    required DateTime periodEnd,
  }) {
    final emp = r['employees'] as Map<String, dynamic>? ?? const {};
    final firstName = ((emp['first_name'] as String?) ?? '').trim();
    final entity = emp['hiring_entities'] as Map<String, dynamic>?;
    final brand = ((entity?['name'] as String?) ??
            (entity?['code'] as String?) ??
            '')
        .trim();
    final fmt = DateFormat('MMM d');
    final desc =
        '$firstName ${fmt.format(periodStart)} - ${fmt.format(periodEnd)} Cutoff Salary';
    return FinanceExportRow(
      date: payDate,
      description: desc,
      amount: Decimal.parse((r['net_pay'] ?? '0').toString()),
      type: 'Salary',
      brand: brand,
    );
  }
}

String _dateRangeLabel(DateTime? start, DateTime? end) {
  if (start == null || end == null) return 'Payroll';
  final fmt = DateFormat('MMMM d');
  return '${fmt.format(start)} - ${fmt.format(end)}, ${end.year}';
}

String _safeFileName(String raw) {
  return raw.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
}

bool get _useMobileShareSheet {
  if (kIsWeb) return false;
  try {
    return Platform.isIOS || Platform.isAndroid;
  } catch (_) {
    return false;
  }
}

Future<String> _writeExcel(Excel excel, String path) async {
  final bytes = excel.save();
  if (bytes == null) {
    throw Exception('Excel.save() returned null');
  }
  final target = path.toLowerCase().endsWith('.xlsx') ? path : '$path.xlsx';
  await File(target).writeAsBytes(bytes);
  return target;
}

Future<String?> _shareExcel(Excel excel, String fileName) async {
  final bytes = excel.save();
  if (bytes == null) {
    throw Exception('Excel.save() returned null');
  }
  final dir = await getTemporaryDirectory();
  final safe = _safeFileName(fileName);
  final named = safe.toLowerCase().endsWith('.xlsx') ? safe : '$safe.xlsx';
  final path = '${dir.path}${Platform.pathSeparator}$named';
  await File(path).writeAsBytes(bytes);
  final result = await Share.shareXFiles(
    [
      XFile(
        path,
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      ),
    ],
    subject: fileName,
  );
  if (result.status == ShareResultStatus.dismissed) return null;
  return path;
}

/// Build all rows + write a single-sheet workbook. Sorted by brand then
/// description so cashflow review reads naturally.
Future<String?> exportFinanceTrackingXlsx({
  required List<FinanceExportRow> rows,
  required DateTime? periodStart,
  required DateTime? periodEnd,
}) async {
  if (rows.isEmpty) return null;
  final filename =
      'Finance Tracking ${_dateRangeLabel(periodStart, periodEnd)}.xlsx';

  final sorted = [...rows]..sort((a, b) {
      final brandCmp = a.brand.compareTo(b.brand);
      if (brandCmp != 0) return brandCmp;
      return a.description.compareTo(b.description);
    });

  final excel = Excel.createExcel();
  excel.rename(excel.getDefaultSheet() ?? 'Sheet1', 'Sheet 1');
  final ws = excel['Sheet 1'];

  ws.appendRow(<CellValue?>[
    TextCellValue('Date'),
    TextCellValue('Description'),
    TextCellValue('Amount'),
    TextCellValue('Type'),
    TextCellValue('Brand'),
  ]);

  final dateFmt = DateFormat('M/d/yyyy');
  for (final r in sorted) {
    ws.appendRow(<CellValue?>[
      TextCellValue(dateFmt.format(r.date)),
      TextCellValue(r.description),
      DoubleCellValue(r.amount.toDouble()),
      TextCellValue(r.type),
      TextCellValue(r.brand),
    ]);
  }

  if (_useMobileShareSheet) {
    return _shareExcel(excel, filename);
  }
  final path = await FilePicker.platform.saveFile(
    dialogTitle: 'Save finance tracking export',
    fileName: _safeFileName(filename),
    type: FileType.custom,
    allowedExtensions: const ['xlsx'],
  );
  if (path == null) return null;
  return _writeExcel(excel, path);
}
