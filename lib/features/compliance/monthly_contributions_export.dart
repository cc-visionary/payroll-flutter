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

/// Monthly Contributions Report — XLSX reference sheet for the external
/// accountant who remits SSS / PhilHealth / Pag-IBIG (and BIR withholding).
///
/// One sheet per brand (statutory entity), ONE ROW PER EMPLOYEE:
///
///   Month | Employee ID | Last Name | First Name | Monthly Salary |
///   SSS EE | SSS ER | PhilHealth EE | PhilHealth ER |
///   Pag-IBIG EE | Pag-IBIG ER | W/H Tax | Total EE | Total ER | Total
///
/// followed by a TOTALS row and a per-agency Remittance Status block
/// (Due / Paid / PAID-PARTIAL-UNPAID) sourced from the Mark-as-Paid ledger.
///
/// The Monthly Salary column is the DECLARED wage converted to a monthly
/// amount with the engine's statutory formula (see [declaredMonthlySalary]);
/// contribution cells are the month's actual deductions summed across all
/// RELEASED runs by `statutory_payable_breakdown_v`. Employee loans are
/// excluded — this report is for the benefits accountant only.
/// Spec: docs/superpowers/specs/2026-07-31-monthly-contributions-report-design.md

Decimal _div(Decimal a, Decimal b) =>
    (a / b).toDecimal(scaleOnInfinitePrecision: 10);

Decimal _round2(Decimal v) => Decimal.parse(v.toStringAsFixed(2));

/// Declared monthly salary — mirrors the statutory-override block in
/// `compute_engine.dart` (daily = DAILY as-is / HOURLY x hours / MONTHLY / 26,
/// then monthly = daily x 26). The override applies only when BOTH amount
/// and type are set and the amount is strictly positive — same partial-
/// override guard as ComputeService. Falls back to the scorecard rate,
/// converted identically, so employees without an override show their
/// actual rate (declared == actual for them).
Decimal declaredMonthlySalary({
  required Decimal? declaredWageOverride,
  required String? declaredWageType,
  required Decimal? scorecardBaseSalary,
  required String? scorecardWageType,
  int workHoursPerDay = 8,
}) {
  final overrideActive =
      declaredWageOverride != null &&
      declaredWageType != null &&
      declaredWageOverride > Decimal.zero;
  final rate = overrideActive
      ? declaredWageOverride
      : (scorecardBaseSalary ?? Decimal.zero);
  final type = overrideActive ? declaredWageType : scorecardWageType;

  Decimal daily;
  switch ((type ?? 'DAILY').toUpperCase()) {
    case 'MONTHLY':
      daily = _div(rate, Decimal.fromInt(26));
      break;
    case 'HOURLY':
      daily = rate * Decimal.fromInt(workHoursPerDay);
      break;
    case 'DAILY':
    default:
      daily = rate;
  }
  return _round2(daily * Decimal.fromInt(26));
}

/// Employee meta + derived salary for one report row.
class MonthlyContributionEmployee {
  final String employeeId;
  final String employeeNumber;
  final String firstName;
  final String lastName;
  final Decimal monthlySalary;
  const MonthlyContributionEmployee({
    required this.employeeId,
    required this.employeeNumber,
    required this.firstName,
    required this.lastName,
    required this.monthlySalary,
  });
}

/// One employee row — the month's summed deductions per agency. W/H tax is
/// EE-only (ER = 0 for BIR). Total EE deliberately includes W/H tax: the
/// column set matches the payslip's deduction block.
class MonthlyContributionRow {
  final MonthlyContributionEmployee employee;
  final Decimal sssEe;
  final Decimal sssEr;
  final Decimal philhealthEe;
  final Decimal philhealthEr;
  final Decimal pagibigEe;
  final Decimal pagibigEr;
  final Decimal withholdingTax;
  const MonthlyContributionRow({
    required this.employee,
    required this.sssEe,
    required this.sssEr,
    required this.philhealthEe,
    required this.philhealthEr,
    required this.pagibigEe,
    required this.pagibigEr,
    required this.withholdingTax,
  });

  Decimal get totalEe => sssEe + philhealthEe + pagibigEe + withholdingTax;
  Decimal get totalEr => sssEr + philhealthEr + pagibigEr;
  Decimal get total => totalEe + totalEr;
}

/// One line of the Remittance Status block. [status] is null when nothing
/// is due (renders as an em-dash).
class RemittanceStatusLine {
  final StatutoryAgency agency;
  final Decimal due;
  final Decimal paid;
  final DateTime? lastPaidOn;
  const RemittanceStatusLine({
    required this.agency,
    required this.due,
    required this.paid,
    this.lastPaidOn,
  });

  PayableStatus? get status =>
      due <= Decimal.zero ? null : classifyPayable(due, paid);
}

/// Assembled data for one brand sheet.
class MonthlyContributionsSheet {
  final HiringEntity brand;
  final List<MonthlyContributionRow> rows;
  final List<RemittanceStatusLine> statusLines;
  const MonthlyContributionsSheet({
    required this.brand,
    required this.rows,
    required this.statusLines,
  });

  Decimal _sum(Decimal Function(MonthlyContributionRow) f) =>
      rows.fold(Decimal.zero, (s, r) => s + f(r));

  Decimal get totalSssEe => _sum((r) => r.sssEe);
  Decimal get totalSssEr => _sum((r) => r.sssEr);
  Decimal get totalPhilhealthEe => _sum((r) => r.philhealthEe);
  Decimal get totalPhilhealthEr => _sum((r) => r.philhealthEr);
  Decimal get totalPagibigEe => _sum((r) => r.pagibigEe);
  Decimal get totalPagibigEr => _sum((r) => r.pagibigEr);
  Decimal get totalWithholdingTax => _sum((r) => r.withholdingTax);
  Decimal get totalEe => _sum((r) => r.totalEe);
  Decimal get totalEr => _sum((r) => r.totalEr);
  Decimal get total => _sum((r) => r.total);
}

/// Collapse breakdown rows (one per employee x agency) into one
/// [MonthlyContributionRow] per employee. Loans are dropped; agencies the
/// employee has no row for stay zero; an employee id missing from
/// [employeesById] still keeps its amounts under placeholder meta (never
/// silently drop money from a remittance report). Sorted by last name,
/// then first name — matches the existing payables export.
List<MonthlyContributionRow> buildMonthlyContributionRows({
  required List<StatutoryPayableBreakdownRow> breakdown,
  required Map<String, MonthlyContributionEmployee> employeesById,
}) {
  final byEmployee =
      <String, Map<StatutoryAgency, StatutoryPayableBreakdownRow>>{};
  for (final r in breakdown) {
    if (r.agency == StatutoryAgency.employeeLoan) continue;
    byEmployee.putIfAbsent(r.employeeId, () => {})[r.agency] = r;
  }

  Decimal ee(
    Map<StatutoryAgency, StatutoryPayableBreakdownRow> m,
    StatutoryAgency a,
  ) => m[a]?.eeShare ?? Decimal.zero;
  Decimal er(
    Map<StatutoryAgency, StatutoryPayableBreakdownRow> m,
    StatutoryAgency a,
  ) => m[a]?.erShare ?? Decimal.zero;

  final rows = <MonthlyContributionRow>[
    for (final e in byEmployee.entries)
      MonthlyContributionRow(
        employee:
            employeesById[e.key] ??
            MonthlyContributionEmployee(
              employeeId: e.key,
              employeeNumber: '',
              firstName: '',
              lastName: '',
              monthlySalary: Decimal.zero,
            ),
        sssEe: ee(e.value, StatutoryAgency.sssContribution),
        sssEr: er(e.value, StatutoryAgency.sssContribution),
        philhealthEe: ee(e.value, StatutoryAgency.philhealthContribution),
        philhealthEr: er(e.value, StatutoryAgency.philhealthContribution),
        pagibigEe: ee(e.value, StatutoryAgency.pagibigContribution),
        pagibigEr: er(e.value, StatutoryAgency.pagibigContribution),
        withholdingTax: ee(e.value, StatutoryAgency.birWithholding),
      ),
  ];
  rows.sort((a, b) {
    final lc = a.employee.lastName.compareTo(b.employee.lastName);
    if (lc != 0) return lc;
    return a.employee.firstName.compareTo(b.employee.firstName);
  });
  return rows;
}

/// Agencies rendered in the Remittance Status block, in order. Loans are
/// intentionally absent.
const _statusAgencies = [
  StatutoryAgency.sssContribution,
  StatutoryAgency.philhealthContribution,
  StatutoryAgency.pagibigContribution,
  StatutoryAgency.birWithholding,
];

/// Build the Remittance Status block for one brand sheet. Due = the sheet's
/// own column totals (so the block can never disagree with the table above
/// it); Paid/date come from the Mark-as-Paid ledger summaries, pre-filtered
/// to this brand + month by the caller.
List<RemittanceStatusLine> buildRemittanceStatusLines({
  required List<MonthlyContributionRow> rows,
  required List<StatutoryPaymentSummary> paidSummaries,
}) {
  Decimal due(StatutoryAgency a) => switch (a) {
    StatutoryAgency.sssContribution => rows.fold(
      Decimal.zero,
      (s, r) => s + r.sssEe + r.sssEr,
    ),
    StatutoryAgency.philhealthContribution => rows.fold(
      Decimal.zero,
      (s, r) => s + r.philhealthEe + r.philhealthEr,
    ),
    StatutoryAgency.pagibigContribution => rows.fold(
      Decimal.zero,
      (s, r) => s + r.pagibigEe + r.pagibigEr,
    ),
    StatutoryAgency.birWithholding => rows.fold(
      Decimal.zero,
      (s, r) => s + r.withholdingTax,
    ),
    StatutoryAgency.employeeLoan => Decimal.zero,
  };

  return [
    for (final agency in _statusAgencies)
      () {
        StatutoryPaymentSummary? paid;
        for (final p in paidSummaries) {
          if (p.agency == agency) {
            paid = p;
            break;
          }
        }
        return RemittanceStatusLine(
          agency: agency,
          due: due(agency),
          paid: paid?.amountPaid ?? Decimal.zero,
          lastPaidOn: paid?.lastPaidOn,
        );
      }(),
  ];
}

// ---------------------------------------------------------------------------
// Data loading
// ---------------------------------------------------------------------------

/// "July 2026" — used in the sheet rows, filename, dialog and audit log.
String monthlyContributionsMonthLabel(int year, int month) =>
    DateFormat('MMMM yyyy').format(DateTime(year, month));

/// Count RELEASED payroll runs whose period_end lands in (year, month) —
/// drives the dialog's partial-month warning (fewer than 2 = a cutoff is
/// missing or not yet released; the breakdown view only sees RELEASED runs).
Future<int> releasedRunCountForMonth(
  SupabaseClient client,
  int year,
  int month,
) async {
  String iso(DateTime d) => d.toIso8601String().substring(0, 10);
  final monthStart = DateTime(year, month, 1);
  final monthEnd = DateTime(year, month + 1, 0);
  final rows =
      await client
              .from('payroll_runs')
              .select('id')
              .eq('status', 'RELEASED')
              .gte('period_end', iso(monthStart))
              .lte('period_end', iso(monthEnd))
          as List<dynamic>;
  return rows.length;
}

/// Fetch + assemble one sheet per brand for (year, month). Three reads:
/// the breakdown view (already summed across the month's released cutoffs),
/// employee meta + scorecard embed for the salary column, and the paid
/// summaries for the status block. Empty brandFilter = all brands.
Future<List<MonthlyContributionsSheet>> buildMonthlyContributionsSheets({
  required SupabaseClient client,
  required StatutoryPayablesRepository repo,
  required int year,
  required int month,
  required Set<String> brandFilter,
  required List<HiringEntity> brands,
}) async {
  final raw =
      await client
              .from('statutory_payable_breakdown_v')
              .select()
              .eq('period_year', year)
              .eq('period_month', month)
          as List<dynamic>;
  final breakdown = raw
      .cast<Map<String, dynamic>>()
      .map(StatutoryPayableBreakdownRow.fromRow)
      .where(
        (r) => brandFilter.isEmpty || brandFilter.contains(r.hiringEntityId),
      )
      .toList();
  if (breakdown.isEmpty) return const [];

  final empIds = breakdown.map((r) => r.employeeId).toSet().toList();
  final empRows =
      await client
              .from('employees')
              .select(
                'id, employee_number, first_name, last_name, '
                'declared_wage_override, declared_wage_type, '
                'role_scorecards(base_salary, wage_type, work_hours_per_day)',
              )
              .inFilter('id', empIds)
          as List<dynamic>;
  final employeesById = <String, MonthlyContributionEmployee>{};
  for (final r in empRows.cast<Map<String, dynamic>>()) {
    final sc = r['role_scorecards'] as Map<String, dynamic>?;
    employeesById[r['id'] as String] = MonthlyContributionEmployee(
      employeeId: r['id'] as String,
      employeeNumber: (r['employee_number'] as String?) ?? '',
      firstName: (r['first_name'] as String?) ?? '',
      lastName: (r['last_name'] as String?) ?? '',
      monthlySalary: declaredMonthlySalary(
        declaredWageOverride: r['declared_wage_override'] == null
            ? null
            : Decimal.tryParse(r['declared_wage_override'].toString()),
        declaredWageType: r['declared_wage_type'] as String?,
        scorecardBaseSalary: sc == null
            ? null
            : Decimal.tryParse((sc['base_salary'] ?? '0').toString()),
        scorecardWageType: sc?['wage_type'] as String?,
        workHoursPerDay: (sc?['work_hours_per_day'] as int?) ?? 8,
      ),
    );
  }

  final paid = await repo.listPaidSummaries(
    fromYear: year,
    fromMonth: month,
    toYear: year,
    toMonth: month,
  );

  final brandById = <String, HiringEntity>{for (final b in brands) b.id: b};
  final byBrand = <String, List<StatutoryPayableBreakdownRow>>{};
  for (final r in breakdown) {
    byBrand.putIfAbsent(r.hiringEntityId, () => []).add(r);
  }
  final sortedIds = byBrand.keys.toList()
    ..sort(
      (a, b) => (brandById[a]?.name ?? '').compareTo(brandById[b]?.name ?? ''),
    );

  final out = <MonthlyContributionsSheet>[];
  for (final id in sortedIds) {
    final brand = brandById[id];
    if (brand == null) continue;
    final rows = buildMonthlyContributionRows(
      breakdown: byBrand[id]!,
      employeesById: employeesById,
    );
    if (rows.isEmpty) continue;
    out.add(
      MonthlyContributionsSheet(
        brand: brand,
        rows: rows,
        statusLines: buildRemittanceStatusLines(
          rows: rows,
          paidSummaries: paid.where((p) => p.hiringEntityId == id).toList(),
        ),
      ),
    );
  }
  return out;
}

// ---------------------------------------------------------------------------
// Workbook building + save/share (mirrors payables_export.dart helpers)
// ---------------------------------------------------------------------------

String _safeFileName(String raw) {
  return raw.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
}

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
  final result = await Share.shareXFiles([
    XFile(
      path,
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    ),
  ], subject: fileName);
  if (result.status == ShareResultStatus.dismissed) return null;
  return path;
}

void _appendSheet(
  Excel excel,
  MonthlyContributionsSheet sheet,
  String monthLabel,
) {
  final ws = excel[_clampSheetName(sheet.brand.name)];
  final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
  final dateFmt = DateFormat('MMM d, yyyy');

  double n(Decimal d) => d.toDouble();

  // Row 1: header meta
  ws.appendRow(<CellValue?>[
    TextCellValue('Brand: ${sheet.brand.name}'),
    null,
    null,
    TextCellValue('Month: $monthLabel'),
    null,
    null,
    TextCellValue('Generated: $today'),
  ]);
  ws.appendRow(<CellValue?>[]);

  // Header row (15 columns)
  ws.appendRow(<CellValue?>[
    TextCellValue('Month'),
    TextCellValue('Employee ID'),
    TextCellValue('Last Name'),
    TextCellValue('First Name'),
    TextCellValue('Monthly Salary'),
    TextCellValue('SSS EE'),
    TextCellValue('SSS ER'),
    TextCellValue('PhilHealth EE'),
    TextCellValue('PhilHealth ER'),
    TextCellValue('Pag-IBIG EE'),
    TextCellValue('Pag-IBIG ER'),
    TextCellValue('W/H Tax'),
    TextCellValue('Total EE'),
    TextCellValue('Total ER'),
    TextCellValue('Total'),
  ]);

  for (final r in sheet.rows) {
    ws.appendRow(<CellValue?>[
      TextCellValue(monthLabel),
      TextCellValue(r.employee.employeeNumber),
      TextCellValue(r.employee.lastName),
      TextCellValue(r.employee.firstName),
      DoubleCellValue(n(r.employee.monthlySalary)),
      DoubleCellValue(n(r.sssEe)),
      DoubleCellValue(n(r.sssEr)),
      DoubleCellValue(n(r.philhealthEe)),
      DoubleCellValue(n(r.philhealthEr)),
      DoubleCellValue(n(r.pagibigEe)),
      DoubleCellValue(n(r.pagibigEr)),
      DoubleCellValue(n(r.withholdingTax)),
      DoubleCellValue(n(r.totalEe)),
      DoubleCellValue(n(r.totalEr)),
      DoubleCellValue(n(r.total)),
    ]);
  }

  // TOTALS row — salary column left blank (a sum of monthly salaries is
  // not a remittable figure and invites misreading).
  ws.appendRow(<CellValue?>[
    TextCellValue('TOTALS'),
    null,
    null,
    null,
    null,
    DoubleCellValue(n(sheet.totalSssEe)),
    DoubleCellValue(n(sheet.totalSssEr)),
    DoubleCellValue(n(sheet.totalPhilhealthEe)),
    DoubleCellValue(n(sheet.totalPhilhealthEr)),
    DoubleCellValue(n(sheet.totalPagibigEe)),
    DoubleCellValue(n(sheet.totalPagibigEr)),
    DoubleCellValue(n(sheet.totalWithholdingTax)),
    DoubleCellValue(n(sheet.totalEe)),
    DoubleCellValue(n(sheet.totalEr)),
    DoubleCellValue(n(sheet.total)),
  ]);
  ws.appendRow(<CellValue?>[]);

  // Remittance Status block
  ws.appendRow(<CellValue?>[TextCellValue('Remittance Status')]);
  ws.appendRow(<CellValue?>[
    TextCellValue('Agency'),
    TextCellValue('Due'),
    TextCellValue('Paid'),
    TextCellValue('Last Paid On'),
    TextCellValue('Status'),
  ]);
  for (final line in sheet.statusLines) {
    final s = line.status;
    ws.appendRow(<CellValue?>[
      TextCellValue(line.agency.shortLabel),
      DoubleCellValue(n(line.due)),
      DoubleCellValue(n(line.paid)),
      TextCellValue(
        line.lastPaidOn == null ? '' : dateFmt.format(line.lastPaidOn!),
      ),
      TextCellValue(
        s == null
            ? '—'
            : s == PayableStatus.overpaid
            ? 'PAID'
            : s.label.toUpperCase(),
      ),
    ]);
  }
}

/// Write the workbook and save (desktop) / share (mobile). Returns the
/// final path, or null when the user cancels.
Future<String?> exportMonthlyContributionsXlsx({
  required List<MonthlyContributionsSheet> sheets,
  required int year,
  required int month,
}) async {
  if (sheets.isEmpty) return null;
  final monthLabel = monthlyContributionsMonthLabel(year, month);
  final fileName = sheets.length == 1
      ? 'Monthly Contributions - ${sheets.first.brand.name} - $monthLabel.xlsx'
      : 'Monthly Contributions - All Brands - $monthLabel.xlsx';

  final excel = Excel.createExcel();
  final defaultSheet = excel.getDefaultSheet();
  for (final s in sheets) {
    _appendSheet(excel, s, monthLabel);
  }
  if (defaultSheet != null &&
      !sheets.any((s) => _clampSheetName(s.brand.name) == defaultSheet)) {
    excel.delete(defaultSheet);
  }

  if (_useMobileShareSheet) {
    return _shareExcel(excel, fileName);
  }
  final path = await FilePicker.platform.saveFile(
    dialogTitle: 'Save monthly contributions report',
    fileName: _safeFileName(fileName),
    type: FileType.custom,
    allowedExtensions: const ['xlsx'],
  );
  if (path == null) return null;
  await _writeExcel(excel, path);
  return path.toLowerCase().endsWith('.xlsx') ? path : '$path.xlsx';
}
