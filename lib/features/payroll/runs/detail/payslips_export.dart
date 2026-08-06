import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../payslips/payslip_pdf_context.dart';

/// ZIP-of-PDF-payslips exporter for a payroll run.
///
/// Builds one PDF per payslip using the same loader the Lark dispatch + Preview
/// screen use, packs them into a ZIP, then prompts the user for a save
/// location (desktop) or hands the file to the share sheet (mobile).
///
/// Each PDF inside the ZIP is named `<EmployeeNumber>_<LastFirst>_<Period>.pdf`
/// so the files sort by employee number when extracted. The archive itself is
/// named after the pay period, e.g. `Payslips Apr 15 - Apr 29, 2026.zip`.

String _safeFileName(String raw) {
  return raw.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
}

String _periodLabel(DateTime start, DateTime end) {
  final fmt = DateFormat('MMM d');
  return '${fmt.format(start)} - ${fmt.format(end)}, ${end.year}';
}

bool get _useMobileShareSheet {
  if (kIsWeb) return false;
  try {
    return Platform.isIOS || Platform.isAndroid;
  } catch (_) {
    return false;
  }
}

class PayslipsZipExportResult {
  /// Final path the ZIP was written to (or shared from).
  final String path;

  /// Number of PDFs successfully packed.
  final int pdfCount;
  const PayslipsZipExportResult({required this.path, required this.pdfCount});
}

/// Build per-payslip PDFs for [payslipIds], pack them into a ZIP, and either
/// save the file (desktop via FilePicker) or share it (mobile). Returns
/// `null` when the user cancels the save/share dialog.
///
/// [onProgress] reports `(done, total)` after each PDF finishes building so
/// the caller can drive a progress indicator. Building PDFs is the slow part
/// (attendance + holidays per employee); zipping is essentially free.
Future<PayslipsZipExportResult?> exportPayslipsZip({
  required WidgetRef ref,
  required List<String> payslipIds,
  required DateTime periodStart,
  required DateTime periodEnd,
  void Function(int done, int total)? onProgress,
}) async {
  if (payslipIds.isEmpty) return null;

  final archive = Archive();
  final usedNames = <String>{};
  var done = 0;
  for (final id in payslipIds) {
    final results = await buildPayslipPdfsForIds(ref, [id]);
    final result = results[id];
    if (result == null) {
      throw Exception('PDF build returned no result for payslip $id');
    }
    final name = _uniqueName(_payslipFileName(result), usedNames);
    archive.addFile(_zipFileFromBytes(name, result.bytes));
    done += 1;
    onProgress?.call(done, payslipIds.length);
  }

  final encoded = ZipEncoder().encode(archive);
  if (encoded == null) {
    throw Exception('ZipEncoder.encode returned null');
  }
  final zipBytes = Uint8List.fromList(encoded);

  final periodLabel = _periodLabel(periodStart, periodEnd);
  final zipName = _safeFileName('Payslips $periodLabel.zip');

  if (_useMobileShareSheet) {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}${Platform.pathSeparator}$zipName';
    await File(path).writeAsBytes(zipBytes);
    final result = await Share.shareXFiles([
      XFile(path, mimeType: 'application/zip'),
    ], subject: zipName);
    if (result.status == ShareResultStatus.dismissed) return null;
    return PayslipsZipExportResult(path: path, pdfCount: done);
  }

  final savePath = await FilePicker.platform.saveFile(
    dialogTitle: 'Save payslips ZIP',
    fileName: zipName,
    type: FileType.custom,
    allowedExtensions: const ['zip'],
  );
  if (savePath == null) return null;
  final target = savePath.toLowerCase().endsWith('.zip')
      ? savePath
      : '$savePath.zip';
  await File(target).writeAsBytes(zipBytes);
  return PayslipsZipExportResult(path: target, pdfCount: done);
}

ArchiveFile _zipFileFromBytes(String name, Uint8List bytes) {
  return ArchiveFile(name, bytes.length, bytes);
}

String _payslipFileName(PayslipPdfBuildResult r) {
  final emp = r.employee;
  final first = emp.firstName.trim();
  final last = emp.lastName.trim();
  final number = emp.employeeNumber.trim();
  final period = _periodLabel(r.periodStart, r.periodEnd);
  final namePart = [last, first].where((s) => s.isNotEmpty).join(', ');
  final raw = [
    if (number.isNotEmpty) number,
    if (namePart.isNotEmpty) namePart,
    period,
  ].join(' - ');
  return '${_safeFileName(raw)}.pdf';
}

/// Disambiguate filenames if two payslips somehow collide on the produced
/// name (e.g. duplicate employee numbers across hiring entities). Appends
/// ` (2)`, ` (3)`, ... before the extension.
String _uniqueName(String desired, Set<String> used) {
  if (used.add(desired)) return desired;
  final dot = desired.lastIndexOf('.');
  final stem = dot >= 0 ? desired.substring(0, dot) : desired;
  final ext = dot >= 0 ? desired.substring(dot) : '';
  for (var i = 2; ; i++) {
    final candidate = '$stem ($i)$ext';
    if (used.add(candidate)) return candidate;
  }
}
