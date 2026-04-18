import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../constants.dart';

/// Disbursement XLSX exporter — mirrors the payrollos format byte-for-byte.
///
/// Columns per sheet (9):
///   Corporate Code | Client Reference Number | Last Name | First Name |
///   Middle Name | Destination Account | Amount | Remarks | Beneficiary E-mail
///
/// Destination Account:
///   - CASH source → empty string.
///   - Bank source → primary bank-matched account number with dashes stripped.
///   - Forced to string cell type to preserve leading zeros.
///
/// Remarks:
///   - Literal string `"{Month D} - {Month D}, {Year} Cutoff Salary "`
///     (trailing space intentional, mirrors JS `toLocaleString`).
///
/// Filenames:
///   - Per-group: `{SourceAccountName} - {Remarks.trim()}.xlsx`
///     e.g. `GCash Chris - November 15 - November 30, 2025 Cutoff Salary.xlsx`
///   - All: `Disbursement {Month D} - {Month D}, {Year}.xlsx`

class DisbursementExportRow {
  final String firstName;
  final String? middleName;
  final String lastName;
  final Decimal netPay;
  final String? accountNumber; // may contain dashes; cleaned in sheet data
  final String? accountName;
  final bool isCash;
  const DisbursementExportRow({
    required this.firstName,
    this.middleName,
    required this.lastName,
    required this.netPay,
    this.accountNumber,
    this.accountName,
    required this.isCash,
  });

  /// Strip a DB payslip row into an export row using the same account lookup
  /// as the on-screen table. `source` is the payslip's payment_source_account.
  factory DisbursementExportRow.fromPayslipRow(
    Map<String, dynamic> r, {
    required String? source,
    required (String?, String?) Function(Map<String, dynamic>, String?) resolveAccount,
  }) {
    final emp = r['employees'] as Map<String, dynamic>? ?? const {};
    final (num, name) = resolveAccount(r, source);
    return DisbursementExportRow(
      firstName: (emp['first_name'] as String?) ?? '',
      middleName: emp['middle_name'] as String?,
      lastName: (emp['last_name'] as String?) ?? '',
      netPay: Decimal.parse((r['net_pay'] ?? '0').toString()),
      accountNumber: num,
      accountName: name,
      isCash: source == 'CASH',
    );
  }
}

class DisbursementGroupExport {
  final String sourceAccountName; // e.g. "GCash Chris"
  final List<DisbursementExportRow> items;
  const DisbursementGroupExport({
    required this.sourceAccountName,
    required this.items,
  });
}

/// `"{Month D} - {Month D}, {Year} Cutoff Salary "` — trailing space intentional.
String formatRemarks(DateTime? start, DateTime? end) {
  if (start == null || end == null) return 'Cutoff Salary ';
  final fmt = DateFormat('MMMM d');
  return '${fmt.format(start)} - ${fmt.format(end)}, ${end.year} Cutoff Salary ';
}

String _dateRangeLabel(DateTime? start, DateTime? end) {
  if (start == null || end == null) return 'Payroll';
  final fmt = DateFormat('MMMM d');
  return '${fmt.format(start)} - ${fmt.format(end)}, ${end.year}';
}

/// Sanitise a file name so the OS save dialog accepts it on any platform.
String _safeFileName(String raw) {
  return raw.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
}

/// Replace `-` with nothing. Matches the JS `acctNum.replace(/-/g, "")`.
String _stripDashes(String s) => s.replaceAll('-', '');

List<List<CellValue?>> _buildSheetRows(
  DisbursementGroupExport group,
  String remarks,
) {
  final header = <CellValue?>[
    TextCellValue('Corporate Code'),
    TextCellValue('Client Reference Number'),
    TextCellValue('Last Name'),
    TextCellValue('First Name'),
    TextCellValue('Middle Name'),
    TextCellValue('Destination Account'),
    TextCellValue('Amount'),
    TextCellValue('Remarks'),
    TextCellValue('Beneficiary E-mail'),
  ];
  final rows = <List<CellValue?>>[header];
  for (final item in group.items) {
    final destAcct = item.isCash ? '' : _stripDashes(item.accountNumber ?? '');
    rows.add(<CellValue?>[
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(item.lastName),
      TextCellValue(item.firstName),
      TextCellValue(item.middleName ?? ''),
      // Force text so leading zeros on account numbers are preserved.
      TextCellValue(destAcct),
      DoubleCellValue(item.netPay.toDouble()),
      TextCellValue(remarks),
      TextCellValue(''),
    ]);
  }
  return rows;
}

/// True when we should use the mobile share-sheet flow instead of a native
/// save-as dialog. iOS has no concept of "save to arbitrary location" outside
/// the Files app share extension; Android's SAF works but share is more
/// idiomatic for "export and send to accountant".
bool get _useMobileShareSheet {
  if (kIsWeb) return false;
  try {
    return Platform.isIOS || Platform.isAndroid;
  } catch (_) {
    return false;
  }
}

Future<String?> _promptSaveLocation({
  required String dialogTitle,
  required String fileName,
}) async {
  return FilePicker.platform.saveFile(
    dialogTitle: dialogTitle,
    fileName: _safeFileName(fileName),
    type: FileType.custom,
    allowedExtensions: const ['xlsx'],
  );
}

Future<void> _writeExcel(Excel excel, String path) async {
  final bytes = excel.save();
  if (bytes == null) {
    throw Exception('Excel.save() returned null');
  }
  // Ensure `.xlsx` suffix — the save dialog may strip or omit it.
  final target = path.toLowerCase().endsWith('.xlsx') ? path : '$path.xlsx';
  await File(target).writeAsBytes(bytes);
}

/// Mobile path — write to app temp dir, invoke share sheet, return the temp
/// path so callers can report a meaningful message. Files in temp get cleaned
/// up by the OS automatically.
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
  // Treat dismiss as "no export happened" so the UI doesn't report a false
  // success; the temp file still exists for the OS to clean up.
  if (result.status == ShareResultStatus.dismissed) return null;
  return path;
}

/// Export a single payment-source group. Returns the file path written, or
/// null when the user cancelled the save dialog.
Future<String?> exportDisbursementGroupXlsx({
  required DisbursementGroupExport group,
  required DateTime? periodStart,
  required DateTime? periodEnd,
}) async {
  final remarks = formatRemarks(periodStart, periodEnd);
  final filename = '${group.sourceAccountName} - ${remarks.trim()}.xlsx';

  final excel = Excel.createExcel();
  excel.rename(excel.getDefaultSheet() ?? 'Sheet1', 'Sheet 1');
  final ws = excel['Sheet 1'];
  final rows = _buildSheetRows(group, remarks);
  for (final r in rows) {
    ws.appendRow(r);
  }

  if (_useMobileShareSheet) {
    return _shareExcel(excel, filename);
  }
  final path = await _promptSaveLocation(
    dialogTitle: 'Save ${group.sourceAccountName} disbursement',
    fileName: filename,
  );
  if (path == null) return null;
  await _writeExcel(excel, path);
  return path;
}

/// Export every group into a single multi-sheet workbook. Sheet names are
/// truncated to 31 characters (Excel limit).
Future<String?> exportDisbursementAllXlsx({
  required List<DisbursementGroupExport> groups,
  required DateTime? periodStart,
  required DateTime? periodEnd,
}) async {
  if (groups.isEmpty) return null;
  final filename =
      'Disbursement ${_dateRangeLabel(periodStart, periodEnd)}.xlsx';

  final remarks = formatRemarks(periodStart, periodEnd);
  final excel = Excel.createExcel();
  final defaultSheet = excel.getDefaultSheet();
  for (final group in groups) {
    final sheetName = _clampSheetName(group.sourceAccountName);
    final ws = excel[sheetName];
    for (final r in _buildSheetRows(group, remarks)) {
      ws.appendRow(r);
    }
  }
  if (defaultSheet != null &&
      !groups.any((g) => _clampSheetName(g.sourceAccountName) == defaultSheet)) {
    excel.delete(defaultSheet);
  }

  if (_useMobileShareSheet) {
    return _shareExcel(excel, filename);
  }
  final path = await _promptSaveLocation(
    dialogTitle: 'Save disbursement',
    fileName: filename,
  );
  if (path == null) return null;
  await _writeExcel(excel, path);
  return path;
}

String _clampSheetName(String name) {
  // Excel forbids: \ / ? * [ ] : and caps name length at 31.
  final cleaned = name.replaceAll(RegExp(r'[\\/?*\[\]:]'), ' ').trim();
  return cleaned.length <= 31 ? cleaned : cleaned.substring(0, 31);
}

/// Build the TSV representation used by the per-group "Copy" button. Kept
/// here so the Copy output and the XLSX stay in sync format-wise.
String buildGroupTsv(DisbursementGroupExport group) {
  final buf = StringBuffer();
  buf.writeln('Employee\tNet Pay\tAccount Number\tAccount Name');
  var sub = Decimal.zero;
  for (final r in group.items) {
    final name = _fullName(r);
    sub += r.netPay;
    final num = r.isCash ? '-' : (r.accountNumber ?? '');
    final acct = r.isCash ? '-' : (r.accountName ?? '');
    buf.writeln('$name\t${r.netPay.toStringAsFixed(3)}\t$num\t$acct');
  }
  buf.writeln('TOTAL\t${sub.toStringAsFixed(3)}\t\t');
  return buf.toString();
}

String _fullName(DisbursementExportRow r) {
  final parts = [r.firstName, r.middleName, r.lastName]
      .where((s) => s != null && s.isNotEmpty)
      .toList();
  return parts.join(' ');
}

/// Source-name lookup helper — the group label in the tab, but stripped of
/// the "No Source Account" fallback so the filename reads cleanly.
String exportSourceAccountName(String? sourceKey) {
  if (sourceKey == null || sourceKey.isEmpty) return 'No Source';
  return paymentSourceLabel(sourceKey);
}
