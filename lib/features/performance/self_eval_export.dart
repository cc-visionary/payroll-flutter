import 'dart:io';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/repositories/lark_self_eval_repository.dart';

/// XLSX exporter for synced self-evaluation responses (HR / Power BI analysis).
///
/// Workbook layout:
///   - One sheet per `review_type` present. Columns: Employee #, Last Name,
///     First Name, Department, Position, Employment Type, Submitted At, then
///     that type's question columns (numeric-rating questions first, then text,
///     each group sorted). One row per response, newest first.
///   - Plus one "All Responses (tidy)" long-format sheet for pivoting:
///     Employee #, Name, Department, Review Type, Submitted At, Question,
///     Answer, Rating — one row per (response × question). Rating is filled
///     only when the question is numeric.
///
/// Mobile uses the share-sheet flow; desktop uses a save dialog. Mirrors the
/// helper conventions in `disbursement_export.dart` / `payables_export.dart`.

/// Sanitise a file name so the OS save dialog accepts it on every platform.
String _safeFileName(String raw) {
  return raw.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
}

/// Excel forbids: \ / ? * [ ] : and caps name length at 31.
String _clampSheetName(String name) {
  final cleaned = name.replaceAll(RegExp(r'[\\/?*\[\]:]'), ' ').trim();
  return cleaned.length <= 31 ? cleaned : cleaned.substring(0, 31);
}

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
  final target = path.toLowerCase().endsWith('.xlsx') ? path : '$path.xlsx';
  await File(target).writeAsBytes(bytes);
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

/// Friendly, ≤31-char sheet / label name for a review type.
String _reviewTypeLabel(String reviewType) {
  switch (reviewType) {
    case 'PROBATIONARY_M1':
      return 'Probationary M1';
    case 'PROBATIONARY_M3':
      return 'Probationary M3';
    case 'PROBATIONARY_M6':
      return 'Probationary M6';
    case 'QUARTERLY':
      return 'Quarterly';
    default:
      return reviewType.isEmpty ? 'Other' : reviewType.replaceAll('_', ' ');
  }
}

/// Preferred display order for known review types; unknown types sort after,
/// alphabetically.
const _reviewTypeOrder = <String>[
  'PROBATIONARY_M1',
  'PROBATIONARY_M3',
  'PROBATIONARY_M6',
  'QUARTERLY',
];

int _reviewTypeRank(String t) {
  final i = _reviewTypeOrder.indexOf(t);
  return i < 0 ? _reviewTypeOrder.length : i;
}

String _fmtDateTime(DateTime? dt) {
  if (dt == null) return '';
  return DateFormat('yyyy-MM-dd HH:mm').format(dt.toLocal());
}

double? _numeric(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse('$v');
}

String _text(Object? v) => v == null ? '' : '$v';

/// Union of question keys for a set of responses, split into numeric-rating
/// questions (any response carries a numeric value for it) and text questions.
/// Each group sorted for stable column order.
({List<String> ratingKeys, List<String> textKeys}) _questionColumns(
  List<SelfEvalExportRow> rows,
) {
  final ratingKeys = <String>{};
  final textKeys = <String>{};
  for (final r in rows) {
    for (final k in r.ratings.keys) {
      if (_numeric(r.ratings[k]) != null) ratingKeys.add(k);
    }
  }
  for (final r in rows) {
    for (final k in r.answers.keys) {
      if (!ratingKeys.contains(k)) textKeys.add(k);
    }
  }
  final rk = ratingKeys.toList()..sort();
  final tk = textKeys.toList()..sort();
  return (ratingKeys: rk, textKeys: tk);
}

void _appendTypeSheet(
  Excel excel,
  String reviewType,
  List<SelfEvalExportRow> rows,
) {
  final ws = excel[_clampSheetName(_reviewTypeLabel(reviewType))];
  final cols = _questionColumns(rows);

  ws.appendRow(<CellValue?>[
    TextCellValue('Employee #'),
    TextCellValue('Last Name'),
    TextCellValue('First Name'),
    TextCellValue('Department'),
    TextCellValue('Position'),
    TextCellValue('Employment Type'),
    TextCellValue('Submitted At'),
    for (final k in cols.ratingKeys) TextCellValue(k),
    for (final k in cols.textKeys) TextCellValue(k),
  ]);

  for (final r in rows) {
    ws.appendRow(<CellValue?>[
      TextCellValue(r.employeeNumber),
      TextCellValue(r.lastName),
      TextCellValue(r.firstName),
      TextCellValue(r.departmentName ?? ''),
      TextCellValue(r.jobTitle ?? ''),
      TextCellValue(r.employmentType ?? ''),
      TextCellValue(_fmtDateTime(r.submittedAt)),
      for (final k in cols.ratingKeys)
        () {
          final n = _numeric(r.ratings[k]);
          return n == null ? null : DoubleCellValue(n);
        }(),
      for (final k in cols.textKeys)
        () {
          final v = r.answers[k];
          return v == null ? null : TextCellValue(_text(v));
        }(),
    ]);
  }
}

void _appendTidySheet(Excel excel, List<SelfEvalExportRow> rows) {
  final ws = excel[_clampSheetName('All Responses (tidy)')];
  ws.appendRow(<CellValue?>[
    TextCellValue('Employee #'),
    TextCellValue('Name'),
    TextCellValue('Department'),
    TextCellValue('Review Type'),
    TextCellValue('Submitted At'),
    TextCellValue('Question'),
    TextCellValue('Answer'),
    TextCellValue('Rating'),
  ]);

  for (final r in rows) {
    final questions = <String>{...r.answers.keys, ...r.ratings.keys}.toList()
      ..sort();
    for (final q in questions) {
      final rating = _numeric(r.ratings[q]);
      ws.appendRow(<CellValue?>[
        TextCellValue(r.employeeNumber),
        TextCellValue(r.fullName),
        TextCellValue(r.departmentName ?? ''),
        TextCellValue(_reviewTypeLabel(r.reviewType)),
        TextCellValue(_fmtDateTime(r.submittedAt)),
        TextCellValue(q),
        TextCellValue(_text(r.answers[q])),
        rating == null ? null : DoubleCellValue(rating),
      ]);
    }
  }
}

/// Build and save the self-eval workbook. Returns the file path written, or
/// null when the user cancelled the save dialog / dismissed the share sheet.
Future<String?> exportSelfEvalsXlsx({
  required List<SelfEvalExportRow> rows,
}) async {
  if (rows.isEmpty) return null;

  // Group by review type.
  final byType = <String, List<SelfEvalExportRow>>{};
  for (final r in rows) {
    byType.putIfAbsent(r.reviewType, () => []).add(r);
  }
  final types = byType.keys.toList()
    ..sort((a, b) {
      final rc = _reviewTypeRank(a).compareTo(_reviewTypeRank(b));
      return rc != 0 ? rc : a.compareTo(b);
    });

  final excel = Excel.createExcel();
  final defaultSheet = excel.getDefaultSheet();

  for (final t in types) {
    final typeRows = byType[t]!
      ..sort((a, b) => (b.submittedAt ?? DateTime(0))
          .compareTo(a.submittedAt ?? DateTime(0)));
    _appendTypeSheet(excel, t, typeRows);
  }
  _appendTidySheet(excel, rows);

  // Drop the auto-created default sheet unless one of ours reused its name.
  if (defaultSheet != null && excel.sheets.keys.length > 1) {
    final ours = {
      for (final t in types) _clampSheetName(_reviewTypeLabel(t)),
      _clampSheetName('All Responses (tidy)'),
    };
    if (!ours.contains(defaultSheet)) {
      excel.delete(defaultSheet);
    }
  }

  final fileName =
      'Self-Evaluations - ${DateFormat('yyyy-MM-dd').format(DateTime.now())}.xlsx';

  if (_useMobileShareSheet) {
    return _shareExcel(excel, fileName);
  }
  final path = await _promptSaveLocation(
    dialogTitle: 'Save self-evaluations',
    fileName: fileName,
  );
  if (path == null) return null;
  await _writeExcel(excel, path);
  return path;
}
