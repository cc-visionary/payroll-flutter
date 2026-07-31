# Monthly Contributions Report Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Monthly Contributions Report" XLSX export to the Compliance screen — one row per employee showing the declared monthly salary next to the month's actual SSS/PhilHealth/Pag-IBIG/BIR deductions, plus a per-agency remittance-status block.

**Architecture:** Pure assembly functions (salary derivation, row grouping, status lines) live in a new `monthly_contributions_export.dart` beside the existing `payables_export.dart` and are unit-tested without Supabase. An async loader in the same file does the three fetches (breakdown view, employees + scorecard embed, paid summaries) and hands assembled sheet models to an Excel builder that mirrors the existing exporter's save/share plumbing. A new dialog widget (month picker + brand filter + partial-month warning) is opened from a third item in the Compliance screen's existing Export menu.

**Tech Stack:** Flutter/Dart, Riverpod, Supabase (PostgREST reads only — **no migration**), `excel`, `decimal`, `intl`, `file_picker`, `share_plus`.

**Spec:** `docs/superpowers/specs/2026-07-31-monthly-contributions-report-design.md`

## Global Constraints

- Repo is shared by concurrent Claude sessions — execute this plan in a git worktree (superpowers:using-git-worktrees) and merge back when done.
- Do NOT run `dart format` on whole files — the repo mixes formatter styles; match the surrounding style of each file. Gate on `flutter analyze` only.
- Run tests with `flutter test <path>` from the repo root.
- Package import prefix is `package:payroll_flutter/`.
- Currency values are `Decimal` (package `decimal`); division must use `(a / b).toDecimal(scaleOnInfinitePrecision: 10)` (matches `compute_engine.dart`).
- The declared monthly formula must mirror the engine's statutory-override block (`compute_engine.dart` lines 374–391): daily = DAILY→rate, HOURLY→rate×hoursPerDay, MONTHLY→rate÷26; monthly = daily×26; round to 2 decimals.
- Loans (`StatutoryAgency.employeeLoan`) are excluded everywhere in this report.
- Agency order everywhere: SSS, PhilHealth, Pag-IBIG, BIR.
- No DB migration. Reads only: `statutory_payable_breakdown_v`, `employees` (+ `role_scorecards` embed), `statutory_payments_paid_v` (via existing repo), `payroll_runs`.

---

### Task 1: Salary derivation + row models (`monthly_contributions_export.dart` part 1)

**Files:**
- Create: `lib/features/compliance/monthly_contributions_export.dart`
- Test: `test/features/compliance/monthly_contributions_export_test.dart` (create directory `test/features/compliance/`)

**Interfaces:**
- Consumes: `StatutoryAgency`, `StatutoryPayableBreakdownRow`, `StatutoryPaymentSummary`, `PayableStatus`, `classifyPayable` from `package:payroll_flutter/data/models/statutory_payable.dart`; `HiringEntity` from `package:payroll_flutter/data/models/hiring_entity.dart`.
- Produces (used by Tasks 2–4):
  - `Decimal declaredMonthlySalary({Decimal? declaredWageOverride, String? declaredWageType, Decimal? scorecardBaseSalary, String? scorecardWageType, int workHoursPerDay})`
  - `class MonthlyContributionEmployee { String employeeId; String employeeNumber; String firstName; String lastName; Decimal monthlySalary; }`
  - `class MonthlyContributionRow` with per-agency `Decimal` fields and `totalEe/totalEr/total` getters
  - `class RemittanceStatusLine { StatutoryAgency agency; Decimal due; Decimal paid; DateTime? lastPaidOn; PayableStatus? status; }`
  - `class MonthlyContributionsSheet { HiringEntity brand; List<MonthlyContributionRow> rows; List<RemittanceStatusLine> statusLines; }` plus column-total getters

- [ ] **Step 1: Write the failing tests**

Create `test/features/compliance/monthly_contributions_export_test.dart`:

```dart
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/compliance/monthly_contributions_export.dart';

Decimal _d(String s) => Decimal.parse(s);

void main() {
  group('declaredMonthlySalary', () {
    test('DAILY override: 600 x 26 = 15600.00', () {
      final v = declaredMonthlySalary(
        declaredWageOverride: _d('600'),
        declaredWageType: 'DAILY',
        scorecardBaseSalary: _d('900'),
        scorecardWageType: 'DAILY',
      );
      expect(v, _d('15600.00'));
    });

    test('HOURLY override: 100 x 8h x 26 = 20800.00', () {
      final v = declaredMonthlySalary(
        declaredWageOverride: _d('100'),
        declaredWageType: 'HOURLY',
        scorecardBaseSalary: _d('900'),
        scorecardWageType: 'DAILY',
        workHoursPerDay: 8,
      );
      expect(v, _d('20800.00'));
    });

    test('MONTHLY override round-trips to itself', () {
      final v = declaredMonthlySalary(
        declaredWageOverride: _d('25000'),
        declaredWageType: 'MONTHLY',
        scorecardBaseSalary: _d('900'),
        scorecardWageType: 'DAILY',
      );
      expect(v, _d('25000.00'));
    });

    test('no override falls back to scorecard rate', () {
      final v = declaredMonthlySalary(
        declaredWageOverride: null,
        declaredWageType: null,
        scorecardBaseSalary: _d('645'),
        scorecardWageType: 'DAILY',
      );
      expect(v, _d('16770.00'));
    });

    test('override amount without type falls back to scorecard', () {
      final v = declaredMonthlySalary(
        declaredWageOverride: _d('600'),
        declaredWageType: null,
        scorecardBaseSalary: _d('645'),
        scorecardWageType: 'DAILY',
      );
      expect(v, _d('16770.00'));
    });

    test('zero override falls back to scorecard', () {
      final v = declaredMonthlySalary(
        declaredWageOverride: Decimal.zero,
        declaredWageType: 'DAILY',
        scorecardBaseSalary: _d('645'),
        scorecardWageType: 'DAILY',
      );
      expect(v, _d('16770.00'));
    });

    test('no override, no scorecard -> zero', () {
      final v = declaredMonthlySalary(
        declaredWageOverride: null,
        declaredWageType: null,
        scorecardBaseSalary: null,
        scorecardWageType: null,
      );
      expect(v, _d('0.00'));
    });

    test('unknown wage type string treated as DAILY', () {
      final v = declaredMonthlySalary(
        declaredWageOverride: _d('600'),
        declaredWageType: 'WEEKLY',
        scorecardBaseSalary: null,
        scorecardWageType: null,
      );
      expect(v, _d('15600.00'));
    });
  });

  group('MonthlyContributionRow totals', () {
    test('totalEe includes withholding tax; totalEr does not', () {
      final row = MonthlyContributionRow(
        employee: MonthlyContributionEmployee(
          employeeId: 'e1',
          employeeNumber: 'LX-001',
          firstName: 'Juan',
          lastName: 'Dela Cruz',
          monthlySalary: _d('15600.00'),
        ),
        sssEe: _d('500'),
        sssEr: _d('1000'),
        philhealthEe: _d('250'),
        philhealthEr: _d('250'),
        pagibigEe: _d('100'),
        pagibigEr: _d('100'),
        withholdingTax: _d('50'),
      );
      expect(row.totalEe, _d('900'));
      expect(row.totalEr, _d('1350'));
      expect(row.total, _d('2250'));
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/compliance/monthly_contributions_export_test.dart`
Expected: FAIL — `monthly_contributions_export.dart` does not exist / names undefined.

- [ ] **Step 3: Write the implementation**

Create `lib/features/compliance/monthly_contributions_export.dart`:

```dart
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
  final overrideActive = declaredWageOverride != null &&
      declaredWageType != null &&
      declaredWageOverride > Decimal.zero;
  final rate =
      overrideActive ? declaredWageOverride : (scorecardBaseSalary ?? Decimal.zero);
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
```

(The grouping, loader, and workbook functions are added in Tasks 2–3; this task compiles with just the above.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/compliance/monthly_contributions_export_test.dart`
Expected: PASS (all groups).

- [ ] **Step 5: Analyze and commit**

Run: `flutter analyze lib/features/compliance/monthly_contributions_export.dart test/features/compliance/monthly_contributions_export_test.dart`
Expected: No issues.

```bash
git add lib/features/compliance/monthly_contributions_export.dart test/features/compliance/monthly_contributions_export_test.dart
git commit -m "feat(compliance): declared-monthly salary helper + report row models"
```

---

### Task 2: Row grouping + remittance status lines (pure assembly)

**Files:**
- Modify: `lib/features/compliance/monthly_contributions_export.dart` (append)
- Test: `test/features/compliance/monthly_contributions_export_test.dart` (append)

**Interfaces:**
- Consumes: Task 1 models; `StatutoryPayableBreakdownRow`, `StatutoryPaymentSummary`, `StatutoryAgency`.
- Produces:
  - `List<MonthlyContributionRow> buildMonthlyContributionRows({required List<StatutoryPayableBreakdownRow> breakdown, required Map<String, MonthlyContributionEmployee> employeesById})`
  - `List<RemittanceStatusLine> buildRemittanceStatusLines({required List<MonthlyContributionRow> rows, required List<StatutoryPaymentSummary> paidSummaries})`

- [ ] **Step 1: Write the failing tests**

Append to the test file (inside `main()`, after the existing groups). Add the imports at the top of the test file:

```dart
import 'package:payroll_flutter/data/models/statutory_payable.dart';
```

```dart
  StatutoryPayableBreakdownRow _b({
    required String empId,
    required StatutoryAgency agency,
    required String ee,
    String er = '0',
  }) =>
      StatutoryPayableBreakdownRow(
        hiringEntityId: 'brand-1',
        periodYear: 2026,
        periodMonth: 7,
        agency: agency,
        employeeId: empId,
        eeShare: _d(ee),
        erShare: _d(er),
        totalAmount: _d(ee) + _d(er),
      );

  MonthlyContributionEmployee _emp(String id, String last, String first) =>
      MonthlyContributionEmployee(
        employeeId: id,
        employeeNumber: 'LX-$id',
        firstName: first,
        lastName: last,
        monthlySalary: _d('15600.00'),
      );

  group('buildMonthlyContributionRows', () {
    test('groups agencies into one row per employee, sorted by name', () {
      final rows = buildMonthlyContributionRows(
        breakdown: [
          _b(empId: 'e2', agency: StatutoryAgency.sssContribution, ee: '450', er: '900'),
          _b(empId: 'e1', agency: StatutoryAgency.sssContribution, ee: '500', er: '1000'),
          _b(empId: 'e1', agency: StatutoryAgency.philhealthContribution, ee: '250', er: '250'),
          _b(empId: 'e1', agency: StatutoryAgency.pagibigContribution, ee: '100', er: '100'),
          _b(empId: 'e1', agency: StatutoryAgency.birWithholding, ee: '75'),
        ],
        employeesById: {
          'e1': _emp('e1', 'Alonzo', 'Ana'),
          'e2': _emp('e2', 'Bautista', 'Ben'),
        },
      );
      expect(rows, hasLength(2));
      expect(rows[0].employee.lastName, 'Alonzo');
      expect(rows[0].sssEe, _d('500'));
      expect(rows[0].sssEr, _d('1000'));
      expect(rows[0].philhealthEe, _d('250'));
      expect(rows[0].pagibigEr, _d('100'));
      expect(rows[0].withholdingTax, _d('75'));
      // e2 has no PhilHealth/Pag-IBIG/BIR rows -> zeros.
      expect(rows[1].employee.lastName, 'Bautista');
      expect(rows[1].philhealthEe, Decimal.zero);
      expect(rows[1].withholdingTax, Decimal.zero);
    });

    test('excludes employee loans', () {
      final rows = buildMonthlyContributionRows(
        breakdown: [
          _b(empId: 'e1', agency: StatutoryAgency.sssContribution, ee: '500', er: '1000'),
          _b(empId: 'e1', agency: StatutoryAgency.employeeLoan, ee: '2000'),
        ],
        employeesById: {'e1': _emp('e1', 'Alonzo', 'Ana')},
      );
      expect(rows, hasLength(1));
      expect(rows[0].totalEe, _d('500'));
      expect(rows[0].total, _d('1500'));
    });

    test('unknown employee id keeps the money with placeholder meta', () {
      final rows = buildMonthlyContributionRows(
        breakdown: [
          _b(empId: 'ghost', agency: StatutoryAgency.sssContribution, ee: '500', er: '1000'),
        ],
        employeesById: const {},
      );
      expect(rows, hasLength(1));
      expect(rows[0].employee.lastName, '');
      expect(rows[0].employee.monthlySalary, Decimal.zero);
      expect(rows[0].sssEe, _d('500'));
    });
  });

  group('buildRemittanceStatusLines', () {
    test('four agencies in order with due sums and paid matching', () {
      final rows = buildMonthlyContributionRows(
        breakdown: [
          _b(empId: 'e1', agency: StatutoryAgency.sssContribution, ee: '500', er: '1000'),
          _b(empId: 'e1', agency: StatutoryAgency.philhealthContribution, ee: '250', er: '250'),
        ],
        employeesById: {'e1': _emp('e1', 'Alonzo', 'Ana')},
      );
      final lines = buildRemittanceStatusLines(
        rows: rows,
        paidSummaries: [
          StatutoryPaymentSummary(
            hiringEntityId: 'brand-1',
            periodYear: 2026,
            periodMonth: 7,
            agency: StatutoryAgency.sssContribution,
            amountPaid: _d('1500'),
            paymentCount: 1,
            lastPaidOn: DateTime(2026, 7, 10),
          ),
        ],
      );
      expect(lines, hasLength(4));
      expect(lines[0].agency, StatutoryAgency.sssContribution);
      expect(lines[0].due, _d('1500'));
      expect(lines[0].paid, _d('1500'));
      expect(lines[0].status, PayableStatus.paid);
      expect(lines[0].lastPaidOn, DateTime(2026, 7, 10));
      expect(lines[1].agency, StatutoryAgency.philhealthContribution);
      expect(lines[1].status, PayableStatus.unpaid);
      // Pag-IBIG and BIR have zero due -> status null.
      expect(lines[2].agency, StatutoryAgency.pagibigContribution);
      expect(lines[2].status, isNull);
      expect(lines[3].agency, StatutoryAgency.birWithholding);
      expect(lines[3].status, isNull);
    });
  });
```

- [ ] **Step 2: Run tests to verify the new groups fail**

Run: `flutter test test/features/compliance/monthly_contributions_export_test.dart`
Expected: FAIL — `buildMonthlyContributionRows` / `buildRemittanceStatusLines` undefined. Task 1 groups still pass.

- [ ] **Step 3: Write the implementation**

Append to `monthly_contributions_export.dart`:

```dart
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
  final byEmployee = <String, Map<StatutoryAgency, StatutoryPayableBreakdownRow>>{};
  for (final r in breakdown) {
    if (r.agency == StatutoryAgency.employeeLoan) continue;
    byEmployee.putIfAbsent(r.employeeId, () => {})[r.agency] = r;
  }

  Decimal ee(Map<StatutoryAgency, StatutoryPayableBreakdownRow> m,
          StatutoryAgency a) =>
      m[a]?.eeShare ?? Decimal.zero;
  Decimal er(Map<StatutoryAgency, StatutoryPayableBreakdownRow> m,
          StatutoryAgency a) =>
      m[a]?.erShare ?? Decimal.zero;

  final rows = <MonthlyContributionRow>[
    for (final e in byEmployee.entries)
      MonthlyContributionRow(
        employee: employeesById[e.key] ??
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
            Decimal.zero, (s, r) => s + r.sssEe + r.sssEr),
        StatutoryAgency.philhealthContribution => rows.fold(
            Decimal.zero, (s, r) => s + r.philhealthEe + r.philhealthEr),
        StatutoryAgency.pagibigContribution => rows.fold(
            Decimal.zero, (s, r) => s + r.pagibigEe + r.pagibigEr),
        StatutoryAgency.birWithholding =>
          rows.fold(Decimal.zero, (s, r) => s + r.withholdingTax),
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/compliance/monthly_contributions_export_test.dart`
Expected: PASS (all groups).

- [ ] **Step 5: Analyze and commit**

Run: `flutter analyze lib/features/compliance/monthly_contributions_export.dart test/features/compliance/monthly_contributions_export_test.dart`
Expected: No issues.

```bash
git add lib/features/compliance/monthly_contributions_export.dart test/features/compliance/monthly_contributions_export_test.dart
git commit -m "feat(compliance): monthly contributions row grouping + remittance status lines"
```

---

### Task 3: Data loader + workbook builder + save/share

**Files:**
- Modify: `lib/features/compliance/monthly_contributions_export.dart` (append)

No unit tests — this section is Supabase I/O and Excel serialization, matching the untested-by-convention existing exporters (`payables_export.dart`). Verified by `flutter analyze` here and GUI smoke at the end of Task 4.

**Interfaces:**
- Consumes: Tasks 1–2 functions/models; `StatutoryPayablesRepository.listPaidSummaries` (existing).
- Produces (used by Task 4):
  - `Future<List<MonthlyContributionsSheet>> buildMonthlyContributionsSheets({required SupabaseClient client, required StatutoryPayablesRepository repo, required int year, required int month, required Set<String> brandFilter, required List<HiringEntity> brands})`
  - `Future<int> releasedRunCountForMonth(SupabaseClient client, int year, int month)`
  - `Future<String?> exportMonthlyContributionsXlsx({required List<MonthlyContributionsSheet> sheets, required int year, required int month})` — returns saved path, or null on user cancel.
  - `String monthlyContributionsMonthLabel(int year, int month)` — e.g. "July 2026".

- [ ] **Step 1: Append the loader + workbook code**

```dart
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
  final rows = await client
      .from('payroll_runs')
      .select('id')
      .eq('status', 'RELEASED')
      .gte('period_end', iso(monthStart))
      .lte('period_end', iso(monthEnd)) as List<dynamic>;
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
  final raw = await client
      .from('statutory_payable_breakdown_v')
      .select()
      .eq('period_year', year)
      .eq('period_month', month) as List<dynamic>;
  final breakdown = raw
      .cast<Map<String, dynamic>>()
      .map(StatutoryPayableBreakdownRow.fromRow)
      .where((r) =>
          brandFilter.isEmpty || brandFilter.contains(r.hiringEntityId))
      .toList();
  if (breakdown.isEmpty) return const [];

  final empIds = breakdown.map((r) => r.employeeId).toSet().toList();
  final empRows = await client
      .from('employees')
      .select('id, employee_number, first_name, last_name, '
          'declared_wage_override, declared_wage_type, '
          'role_scorecards(base_salary, wage_type, work_hours_per_day)')
      .inFilter('id', empIds) as List<dynamic>;
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
    ..sort((a, b) =>
        (brandById[a]?.name ?? '').compareTo(brandById[b]?.name ?? ''));

  final out = <MonthlyContributionsSheet>[];
  for (final id in sortedIds) {
    final brand = brandById[id];
    if (brand == null) continue;
    final rows = buildMonthlyContributionRows(
      breakdown: byBrand[id]!,
      employeesById: employeesById,
    );
    if (rows.isEmpty) continue;
    out.add(MonthlyContributionsSheet(
      brand: brand,
      rows: rows,
      statusLines: buildRemittanceStatusLines(
        rows: rows,
        paidSummaries:
            paid.where((p) => p.hiringEntityId == id).toList(),
      ),
    ));
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
          line.lastPaidOn == null ? '' : dateFmt.format(line.lastPaidOn!)),
      TextCellValue(s == null ? '—' : s.label.toUpperCase()),
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
```

- [ ] **Step 2: Run the full test file (regression) + analyze**

Run: `flutter test test/features/compliance/monthly_contributions_export_test.dart`
Expected: PASS.

Run: `flutter analyze lib/features/compliance/monthly_contributions_export.dart`
Expected: No issues.

- [ ] **Step 3: Commit**

```bash
git add lib/features/compliance/monthly_contributions_export.dart
git commit -m "feat(compliance): monthly contributions loader + XLSX workbook builder"
```

---

### Task 4: Export dialog + Compliance screen menu wiring

**Files:**
- Create: `lib/features/compliance/widgets/monthly_contributions_dialog.dart`
- Modify: `lib/features/compliance/compliance_screen.dart` (the `_ExportMenu.menuChildren` list, currently lines 111–124)

**Interfaces:**
- Consumes: `buildMonthlyContributionsSheets`, `exportMonthlyContributionsXlsx`, `releasedRunCountForMonth`, `monthlyContributionsMonthLabel` (Task 3); `complianceBrandsProvider`, `statutoryPayablesRepositoryProvider`, `auditRepositoryProvider` (existing).
- Produces: `class MonthlyContributionsDialog extends ConsumerStatefulWidget` — opened via `showDialog` from the Export menu.

- [ ] **Step 1: Create the dialog widget**

Create `lib/features/compliance/widgets/monthly_contributions_dialog.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/status_colors.dart';
import '../../../app/tokens.dart';
import '../../../data/repositories/audit_repository.dart';
import '../../../data/repositories/statutory_payables_repository.dart';
import '../monthly_contributions_export.dart';
import '../providers.dart';

/// Month + brand picker for the Monthly Contributions Report (the
/// per-employee declared-salary XLSX sent to the benefits accountant).
///
/// Defaults to the previous calendar month — the common case is closing
/// out last month's remittance after both cutoffs have been released.
/// Shows a warning when the selected month has fewer than 2 released
/// payroll runs, since the report would then be missing a cutoff.
class MonthlyContributionsDialog extends ConsumerStatefulWidget {
  const MonthlyContributionsDialog({super.key});

  @override
  ConsumerState<MonthlyContributionsDialog> createState() =>
      _MonthlyContributionsDialogState();
}

class _MonthlyContributionsDialogState
    extends ConsumerState<MonthlyContributionsDialog> {
  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  late int _year;
  late int _month;
  final Set<String> _brandIds = <String>{};
  bool _exporting = false;
  int? _releasedRunCount; // null = loading

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final prev = DateTime(now.year, now.month - 1, 1);
    _year = prev.year;
    _month = prev.month;
    _loadRunCount();
  }

  Future<void> _loadRunCount() async {
    setState(() => _releasedRunCount = null);
    final year = _year;
    final month = _month;
    try {
      final count = await releasedRunCountForMonth(
        Supabase.instance.client,
        year,
        month,
      );
      // Selection may have moved on while this fetch was in flight.
      if (!mounted || year != _year || month != _month) return;
      setState(() => _releasedRunCount = count);
    } catch (_) {
      // Warning is best-effort; export itself surfaces real errors.
      if (!mounted || year != _year || month != _month) return;
      setState(() => _releasedRunCount = -1);
    }
  }

  Future<void> _export() async {
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    final navigator = Navigator.of(context);
    final label = monthlyContributionsMonthLabel(_year, _month);
    setState(() => _exporting = true);
    try {
      final sheets = await buildMonthlyContributionsSheets(
        client: Supabase.instance.client,
        repo: ref.read(statutoryPayablesRepositoryProvider),
        year: _year,
        month: _month,
        brandFilter: _brandIds,
        brands: ref.read(complianceBrandsProvider).asData?.value ?? const [],
      );
      if (sheets.isEmpty) {
        messenger.showSnackBar(SnackBar(
          content: Text('No released contributions for $label.'),
        ));
        return;
      }
      final path = await exportMonthlyContributionsXlsx(
        sheets: sheets,
        year: _year,
        month: _month,
      );
      if (path == null) return; // user cancelled the save dialog
      final recordCount =
          sheets.fold<int>(0, (n, s) => n + s.rows.length);
      final fileName = path.replaceAll('\\', '/').split('/').last;
      ref.read(auditRepositoryProvider).logExport(
        description:
            'Monthly contributions export: $fileName · $label · $recordCount employees',
        entityType: 'statutory_payables',
        metadata: {
          'file_name': fileName,
          'period': label,
          'record_count': recordCount,
          'brands': [for (final s in sheets) s.brand.name],
          'report': 'monthly_contributions',
        },
      );
      messenger.showSnackBar(SnackBar(content: Text('Saved: $path')));
      navigator.pop();
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('Export failed: $e'),
        backgroundColor: errorColor,
      ));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final years = [for (var y = now.year; y >= now.year - 3; y--) y];
    final brands =
        ref.watch(complianceBrandsProvider).asData?.value ?? const [];
    final runCount = _releasedRunCount;

    return AlertDialog(
      title: const Text('Monthly Contributions Report'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Per-employee declared salary + the month\'s SSS, PhilHealth, '
              'Pag-IBIG and W/H tax deductions, for the benefits accountant.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: LuxiumSpacing.md),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _month,
                    decoration: const InputDecoration(labelText: 'Month'),
                    items: [
                      for (var m = 1; m <= 12; m++)
                        DropdownMenuItem(
                          value: m,
                          child: Text(_monthNames[m - 1]),
                        ),
                    ],
                    onChanged: _exporting
                        ? null
                        : (v) {
                            if (v == null) return;
                            setState(() => _month = v);
                            _loadRunCount();
                          },
                  ),
                ),
                const SizedBox(width: LuxiumSpacing.sm),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: years.contains(_year) ? _year : years.first,
                    decoration: const InputDecoration(labelText: 'Year'),
                    items: [
                      for (final y in years)
                        DropdownMenuItem(value: y, child: Text('$y')),
                    ],
                    onChanged: _exporting
                        ? null
                        : (v) {
                            if (v == null) return;
                            setState(() => _year = v);
                            _loadRunCount();
                          },
                  ),
                ),
              ],
            ),
            const SizedBox(height: LuxiumSpacing.md),
            Text('Brands', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: LuxiumSpacing.xs),
            Wrap(
              spacing: LuxiumSpacing.xs,
              runSpacing: LuxiumSpacing.xs,
              children: [
                FilterChip(
                  label: const Text('All'),
                  selected: _brandIds.isEmpty,
                  onSelected: _exporting
                      ? null
                      : (_) => setState(() => _brandIds.clear()),
                ),
                for (final b in brands)
                  FilterChip(
                    label: Text(b.name),
                    selected: _brandIds.contains(b.id),
                    onSelected: _exporting
                        ? null
                        : (_) => setState(() {
                              if (!_brandIds.remove(b.id)) {
                                _brandIds.add(b.id);
                              }
                            }),
                  ),
              ],
            ),
            if (runCount != null && runCount >= 0 && runCount < 2) ...[
              const SizedBox(height: LuxiumSpacing.md),
              Builder(builder: (context) {
                final warn = StatusPalette.of(context, StatusTone.warning);
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: LuxiumSpacing.md,
                    vertical: LuxiumSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: warn.background,
                    borderRadius: BorderRadius.circular(LuxiumRadius.lg),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_outlined,
                          size: 18, color: warn.foreground),
                      const SizedBox(width: LuxiumSpacing.sm),
                      Expanded(
                        child: Text(
                          runCount == 0
                              ? 'No released payroll runs found for '
                                  '${monthlyContributionsMonthLabel(_year, _month)} '
                                  '— the report will be empty.'
                              : 'Only 1 released cutoff found for '
                                  '${monthlyContributionsMonthLabel(_year, _month)} '
                                  '— the report may be missing half the month.',
                          style: TextStyle(color: warn.foreground),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _exporting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _exporting ? null : _export,
          icon: _exporting
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.file_download_outlined, size: 18),
          label: const Text('Export'),
        ),
      ],
    );
  }
}
```

- [ ] **Step 2: Wire the menu item into the Compliance screen**

In `lib/features/compliance/compliance_screen.dart`, add the import at the top with the other widget imports:

```dart
import 'widgets/monthly_contributions_dialog.dart';
```

Then in `_ExportMenu.build`, append a third `MenuItemButton` to `menuChildren` (after the "Export selected brand only" item):

```dart
        MenuItemButton(
          leadingIcon: const Icon(Icons.receipt_long_outlined),
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => const MonthlyContributionsDialog(),
          ),
          child: const Text('Monthly Contributions Report'),
        ),
```

- [ ] **Step 3: Analyze + full compliance test regression**

Run: `flutter analyze lib/features/compliance/ test/features/compliance/`
Expected: No issues.

Run: `flutter test test/features/compliance/monthly_contributions_export_test.dart`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add lib/features/compliance/widgets/monthly_contributions_dialog.dart lib/features/compliance/compliance_screen.dart
git commit -m "feat(compliance): monthly contributions report dialog + export menu entry"
```

- [ ] **Step 5: Manual GUI smoke (run the app)**

Run: `flutter run -d linux --dart-define-from-file=env/prod.json`

Checklist (per spec's Testing section):
1. Compliance → Export → "Monthly Contributions Report" opens the dialog, defaulting to last month.
2. Export a month with 2 released cutoffs — verify one sheet per brand, one row per employee, Monthly Salary matches the employee's declared wage × 26 conversion, contribution columns match the breakdown drawer for the same brand/month, TOTALS row sums, Remittance Status block shows PAID/PARTIAL/UNPAID consistent with the on-screen ledger chips.
3. Pick a month with only 1 released cutoff — warning appears; a month with none — "will be empty" warning; exporting it shows the "No released contributions" snackbar.
4. Cancel the save dialog — no snackbar, dialog stays open, no audit log entry.

Report results honestly; if any check fails, fix before closing out the plan.

---

## Self-Review (completed)

- **Spec coverage:** dialog (month picker default last month, brand selector, partial warning) → Task 4; sheet layout, columns, month label, totals, status block, loans excluded, filename → Task 3; salary derivation + fallback → Task 1; grouping/sorting/zero-fill → Task 2; audit logging parity with existing export → Task 4; error handling (empty month snackbar, cancel no-op, red failure snackbar) → Task 4 `_export`; unit tests per spec → Tasks 1–2; GUI smoke → Task 4 Step 5. No migration anywhere. ✔
- **Placeholder scan:** none — all steps carry full code. ✔
- **Type consistency:** `declaredMonthlySalary`, `MonthlyContributionEmployee`, `MonthlyContributionRow`, `RemittanceStatusLine`, `MonthlyContributionsSheet`, `buildMonthlyContributionRows`, `buildRemittanceStatusLines`, `buildMonthlyContributionsSheets`, `releasedRunCountForMonth`, `exportMonthlyContributionsXlsx`, `monthlyContributionsMonthLabel` used with identical signatures across tasks. ✔
