import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/models/hiring_entity.dart';
import '../../data/models/statutory_payable.dart';
import '../../data/repositories/statutory_payables_repository.dart';
import 'providers.dart';

/// XLSX exporter for the Statutory Payables Ledger.
///
/// Layout per sheet (one sheet per brand):
///
///   Row 1: Brand: HAVIT Philippines        Period: March 2026         Generated: 2026-04-23
///   Row 2: (blank)
///   Row 3: SSS Contribution
///   Row 4: Brand | Last Name | First Name | MI | Employee ID | EE Share | ER Share | Total
///   Rows 5..N: employee rows
///   Row N+1: TOTAL — SSS Contribution                          Σ EE | Σ ER | Σ Total
///   Row N+2: (blank)
///   …repeat per agency…
///   Row last-1: (blank)
///   Row last:  GRAND TOTAL                                     Σ EE | Σ ER | Σ Total
///
/// Mobile uses share-sheet flow; desktop uses save dialog. Mirrors the
/// helper conventions in `disbursement_export.dart`.

/// Per-employee row pulled from `statutory_payable_breakdown_v` and joined
/// with employees for name fields. Built once per (brand × period × agency).
class StatutoryEmployeeRow {
  final String brandName;
  final String lastName;
  final String firstName;
  final String? middleName;
  final String employeeNumber;
  final Decimal eeShare;
  final Decimal erShare;
  final Decimal total;

  const StatutoryEmployeeRow({
    required this.brandName,
    required this.lastName,
    required this.firstName,
    this.middleName,
    required this.employeeNumber,
    required this.eeShare,
    required this.erShare,
    required this.total,
  });

  String get mi {
    final m = middleName?.trim();
    if (m == null || m.isEmpty) return '';
    return m[0].toUpperCase();
  }
}

/// Group of rows for one (brand × period × agency) — keeps the per-agency
/// section grouped for the sheet layout.
class StatutoryAgencySection {
  final StatutoryAgency agency;
  final List<StatutoryEmployeeRow> rows;
  const StatutoryAgencySection({required this.agency, required this.rows});

  Decimal get totalEe =>
      rows.fold(Decimal.zero, (s, r) => s + r.eeShare);
  Decimal get totalEr =>
      rows.fold(Decimal.zero, (s, r) => s + r.erShare);
  Decimal get total =>
      rows.fold(Decimal.zero, (s, r) => s + r.total);
}

/// Per-brand bundle assembled before the export.
class StatutoryBrandSheet {
  final HiringEntity brand;
  final List<StatutoryAgencySection> sections;
  const StatutoryBrandSheet({required this.brand, required this.sections});
}

/// Sanitise a file name so the OS save dialog accepts it on every platform.
/// Mirrors `_safeFileName` in disbursement_export.dart.
String _safeFileName(String raw) {
  return raw.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
}

/// Excel forbids: \ / ? * [ ] : and caps name length at 31. Mirrors the
/// disbursement exporter's helper.
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

void _appendBrandSheet(Excel excel, StatutoryBrandSheet bundle, String periodLabel) {
  final sheetName = _clampSheetName(bundle.brand.name);
  final ws = excel[sheetName];
  final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

  // Row 1: header
  ws.appendRow(<CellValue?>[
    TextCellValue('Brand: ${bundle.brand.name}'),
    null, null,
    TextCellValue('Period: $periodLabel'),
    null, null,
    TextCellValue('Generated: $today'),
  ]);
  // Row 2: blank
  ws.appendRow(<CellValue?>[]);

  Decimal grandEe = Decimal.zero;
  Decimal grandEr = Decimal.zero;
  Decimal grandTotal = Decimal.zero;

  for (final section in bundle.sections) {
    if (section.rows.isEmpty) continue;

    // Section title
    ws.appendRow(<CellValue?>[TextCellValue(section.agency.fullLabel)]);
    // Header row
    ws.appendRow(<CellValue?>[
      TextCellValue('Brand'),
      TextCellValue('Last Name'),
      TextCellValue('First Name'),
      TextCellValue('MI'),
      TextCellValue('Employee ID'),
      TextCellValue('EE Share'),
      TextCellValue('ER Share'),
      TextCellValue('Total'),
    ]);
    for (final r in section.rows) {
      ws.appendRow(<CellValue?>[
        TextCellValue(r.brandName),
        TextCellValue(r.lastName),
        TextCellValue(r.firstName),
        TextCellValue(r.mi),
        TextCellValue(r.employeeNumber),
        DoubleCellValue(r.eeShare.toDouble()),
        DoubleCellValue(r.erShare.toDouble()),
        DoubleCellValue(r.total.toDouble()),
      ]);
    }
    // Section total
    ws.appendRow(<CellValue?>[
      TextCellValue('TOTAL — ${section.agency.fullLabel}'),
      null, null, null, null,
      DoubleCellValue(section.totalEe.toDouble()),
      DoubleCellValue(section.totalEr.toDouble()),
      DoubleCellValue(section.total.toDouble()),
    ]);
    // Blank row between sections
    ws.appendRow(<CellValue?>[]);

    grandEe += section.totalEe;
    grandEr += section.totalEr;
    grandTotal += section.total;
  }

  // Grand total
  ws.appendRow(<CellValue?>[
    TextCellValue('GRAND TOTAL'),
    null, null, null, null,
    DoubleCellValue(grandEe.toDouble()),
    DoubleCellValue(grandEr.toDouble()),
    DoubleCellValue(grandTotal.toDouble()),
  ]);
}

/// Export a multi-brand workbook (one sheet per brand). Returns the file
/// path written, or null when the user cancelled the save dialog.
Future<String?> exportPayablesXlsx({
  required List<StatutoryBrandSheet> sheets,
  required String periodLabel,
  required bool isCustomRange,
}) async {
  if (sheets.isEmpty) return null;

  final fileName = sheets.length == 1
      ? 'Statutory Payables - ${sheets.first.brand.name} - $periodLabel.xlsx'
      : 'Statutory Payables - All Brands - $periodLabel.xlsx';

  final excel = Excel.createExcel();
  final defaultSheet = excel.getDefaultSheet();
  for (final s in sheets) {
    _appendBrandSheet(excel, s, periodLabel);
  }
  if (defaultSheet != null &&
      !sheets.any(
          (s) => _clampSheetName(s.brand.name) == defaultSheet)) {
    excel.delete(defaultSheet);
  }

  if (_useMobileShareSheet) {
    return _shareExcel(excel, fileName);
  }
  final path = await _promptSaveLocation(
    dialogTitle: 'Save statutory payables',
    fileName: fileName,
  );
  if (path == null) return null;
  await _writeExcel(excel, path);
  return path;
}

/// Build the [StatutoryBrandSheet] bundles for the current filter state.
/// Pulled out so the screen can reuse the same shape for both export
/// variants (current view vs single-brand) and for the on-screen
/// breakdown sanity checks.
Future<List<StatutoryBrandSheet>> buildBrandSheetsFromCurrentFilter({
  required SupabaseClient client,
  required StatutoryPayablesRepository repo,
  required CompliancePeriod period,
  required Set<String> brandFilter,
  required Set<StatutoryAgency> agencyFilter,
  required List<HiringEntity> brands,
}) async {
  // Pull every breakdown row in the period bounds in a single fetch, then
  // partition client-side by brand + agency. The breakdown view is small
  // (≤ employee_count × 5 agencies × month_count) so a wide select is
  // cheaper than five round-trips per brand.
  final bounds = period.yearMonthBounds();
  final fromKey = bounds.fromYear * 100 + bounds.fromMonth;
  final toKey = bounds.toYear * 100 + bounds.toMonth;

  final rawBreakdown = await client
      .from('statutory_payable_breakdown_v')
      .select() as List<dynamic>;
  final breakdown = rawBreakdown
      .cast<Map<String, dynamic>>()
      .map(StatutoryPayableBreakdownRow.fromRow)
      .where((r) {
        final key = r.periodYear * 100 + r.periodMonth;
        if (key < fromKey || key > toKey) return false;
        if (brandFilter.isNotEmpty &&
            !brandFilter.contains(r.hiringEntityId)) {
          return false;
        }
        if (agencyFilter.isNotEmpty && !agencyFilter.contains(r.agency)) {
          return false;
        }
        return true;
      })
      .toList();

  if (breakdown.isEmpty) return const [];

  // Fetch employee meta in one round-trip.
  final empIds = breakdown.map((r) => r.employeeId).toSet().toList();
  final empRows = await client
      .from('employees')
      .select('id, employee_number, first_name, middle_name, last_name')
      .inFilter('id', empIds);
  final empById = <String, Map<String, dynamic>>{
    for (final e in (empRows as List<dynamic>).cast<Map<String, dynamic>>())
      e['id'] as String: e,
  };
  final brandById = <String, HiringEntity>{
    for (final b in brands) b.id: b,
  };

  // Group by brand → agency.
  final byBrand = <String, Map<StatutoryAgency, List<StatutoryEmployeeRow>>>{};
  for (final r in breakdown) {
    final brand = brandById[r.hiringEntityId];
    if (brand == null) continue;
    final emp = empById[r.employeeId] ?? const {};
    final row = StatutoryEmployeeRow(
      brandName: brand.name,
      lastName: emp['last_name'] as String? ?? '',
      firstName: emp['first_name'] as String? ?? '',
      middleName: emp['middle_name'] as String?,
      employeeNumber: emp['employee_number'] as String? ?? '',
      eeShare: r.eeShare,
      erShare: r.erShare,
      total: r.totalAmount,
    );
    final brandMap = byBrand.putIfAbsent(r.hiringEntityId, () => {});
    brandMap.putIfAbsent(r.agency, () => []).add(row);
  }

  // Convert to sorted brand sheets.
  final sortedBrandIds = byBrand.keys.toList()
    ..sort((a, b) =>
        (brandById[a]?.name ?? '').compareTo(brandById[b]?.name ?? ''));

  final out = <StatutoryBrandSheet>[];
  for (final id in sortedBrandIds) {
    final brand = brandById[id];
    if (brand == null) continue;
    final agencyMap = byBrand[id]!;
    final sections = <StatutoryAgencySection>[];
    for (final agency in StatutoryAgency.values) {
      final rows = agencyMap[agency];
      if (rows == null || rows.isEmpty) continue;
      // Sort employees by last name then first name for predictable output.
      rows.sort((a, b) {
        final lc = a.lastName.compareTo(b.lastName);
        if (lc != 0) return lc;
        return a.firstName.compareTo(b.firstName);
      });
      sections.add(StatutoryAgencySection(agency: agency, rows: rows));
    }
    if (sections.isNotEmpty) {
      out.add(StatutoryBrandSheet(brand: brand, sections: sections));
    }
  }
  return out;
}
