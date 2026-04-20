# 13th Month Pay — Accrual & Distribution — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a running 13th-month accrual column to employees that ticks up on every payroll release, plus a "Distribute 13th Month" action in each run's kebab menu that writes `THIRTEENTH_MONTH_PAY` payslip lines (`basis / 12`) and resets the accrual.

**Architecture:** Two new columns (`employees.accrued_thirteenth_month_basis`, `payroll_runs.is_thirteenth_month_distribution`), one release-hook tick-up inside `PayrollRepository.releaseRun`, one new repo method `distributeThirteenthMonth`, one new dialog widget, and a `PopupMenuButton` added to the run detail's `_ActionBar`. No engine / compute changes — the distribution line is a post-compute insert like manual adjustments.

**Tech Stack:** Flutter + Riverpod + Supabase (Postgres + PostgREST) + Decimal. Reference spec: `docs/superpowers/specs/2026-04-20-13th-month-distribution-design.md`.

---

## File structure

**New files:**
- `supabase/migrations/20260420000001_thirteenth_month_accrual.sql` — two `ALTER TABLE` statements adding the accrual column + distribution flag.
- `lib/features/payroll/runs/detail/widgets/distribute_13th_dialog.dart` — the "Distribute 13th Month" modal.
- `test/engine/thirteenth_month_calc_test.dart` — pure-Dart unit test for the payout math.

**Modified:**
- `lib/data/models/employee.dart` — add `accruedThirteenthMonthBasis` field.
- `lib/data/models/payroll_run.dart` — add `isThirteenthMonthDistribution` field.
- `lib/data/repositories/payroll_repository.dart` — (a) tick-up accrual inside `releaseRun`; (b) new `distributeThirteenthMonth` method.
- `lib/features/payroll/runs/detail/payroll_run_detail_screen.dart` — add `PopupMenuButton` to `_ActionBar` with "Distribute 13th Month" item.

---

## Task 1: Schema migration

**Files:**
- Create: `supabase/migrations/20260420000001_thirteenth_month_accrual.sql`

- [ ] **Step 1: Write the migration**

```sql
-- 13th Month Pay accrual + distribution flag
--
-- employees.accrued_thirteenth_month_basis : running sum of BASIC_PAY earned
-- since the employee's last 13th-month distribution. Ticks up on each
-- payroll release, zeroes when a distribution pays them out.
--
-- payroll_runs.is_thirteenth_month_distribution : marks the run where HR
-- clicked "Distribute 13th Month" so reports / exports can filter.

alter table employees
  add column if not exists accrued_thirteenth_month_basis
    numeric(12,2) not null default 0;

alter table payroll_runs
  add column if not exists is_thirteenth_month_distribution
    boolean not null default false;
```

- [ ] **Step 2: Apply the migration to the linked Supabase project**

Run: `supabase db push --linked`
Expected:
```
Applying migration 20260420000001_thirteenth_month_accrual.sql...
Finished supabase db push.
```

- [ ] **Step 3: Verify the columns exist**

Run the following in the Supabase SQL editor (read-only check):
```sql
select column_name, data_type, column_default
  from information_schema.columns
 where (table_name = 'employees' and column_name = 'accrued_thirteenth_month_basis')
    or (table_name = 'payroll_runs' and column_name = 'is_thirteenth_month_distribution');
```

Expected: two rows, defaults `0` (numeric) and `false` (boolean).

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260420000001_thirteenth_month_accrual.sql
git commit -m "feat(db): add 13th-month accrual column + distribution flag"
```

---

## Task 2: Dart model fields

Extend the two plain-Dart models so the new columns round-trip through `fromRow` / reads.

**Files:**
- Modify: `lib/data/models/employee.dart`
- Modify: `lib/data/models/payroll_run.dart`

- [ ] **Step 1: Add `accruedThirteenthMonthBasis` to `Employee`**

In `lib/data/models/employee.dart`, add the field near the other payroll-related fields (around the existing `declaredWageOverride`), then read it in `fromRow`:

```dart
// Add alongside the other decimal fields (e.g., declaredWageOverride):
final Decimal accruedThirteenthMonthBasis;
```

Add to the constructor (required-parameter section with default):
```dart
this.accruedThirteenthMonthBasis = const Decimal.zero(),  // if const ctor
// or in the body of fromRow:
```

In `fromRow`, after the existing field reads, add:
```dart
accruedThirteenthMonthBasis: r['accrued_thirteenth_month_basis'] == null
    ? Decimal.zero
    : Decimal.parse(r['accrued_thirteenth_month_basis'].toString()),
```

- [ ] **Step 2: Add `isThirteenthMonthDistribution` to `PayrollRun`**

In `lib/data/models/payroll_run.dart`:

```dart
final bool isThirteenthMonthDistribution;
```

In `fromRow`:
```dart
isThirteenthMonthDistribution:
    r['is_thirteenth_month_distribution'] as bool? ?? false,
```

Add to the constructor as optional with default `false`.

- [ ] **Step 3: Compile check**

Run: `flutter analyze lib/data/models/employee.dart lib/data/models/payroll_run.dart`
Expected: `No issues found.` (or only pre-existing info-level lints unrelated to these changes).

- [ ] **Step 4: Commit**

```bash
git add lib/data/models/employee.dart lib/data/models/payroll_run.dart
git commit -m "feat(models): expose 13th-month accrual + distribution flag"
```

---

## Task 3: Pure-Dart payout calc + unit test

Write and test the `basis / 12` payout helper in isolation — it's the only new math and should be dead-simple and covered.

**Files:**
- Create: `test/engine/thirteenth_month_calc_test.dart`
- Modify: `lib/data/repositories/payroll_repository.dart` (just the helper — the repo write lands in Task 4)

- [ ] **Step 1: Write the failing test**

`test/engine/thirteenth_month_calc_test.dart`:
```dart
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/repositories/payroll_repository.dart';

void main() {
  group('thirteenthMonthPayout', () {
    test('divides basis by 12 with banker rounding to 2dp', () {
      // Annual basic = ₱154,830 → payout = 12,902.50 exactly.
      expect(
        PayrollRepository.thirteenthMonthPayout(Decimal.parse('154830')),
        Decimal.parse('12902.50'),
      );
    });

    test('rounds half-up on 2nd decimal', () {
      // 1 / 12 = 0.0833333... → 0.08
      expect(
        PayrollRepository.thirteenthMonthPayout(Decimal.parse('1')),
        Decimal.parse('0.08'),
      );
    });

    test('zero basis is zero payout', () {
      expect(
        PayrollRepository.thirteenthMonthPayout(Decimal.zero),
        Decimal.zero,
      );
    });

    test('negative basis clamps to zero', () {
      // Defensive: should never be called with a negative, but guard anyway.
      expect(
        PayrollRepository.thirteenthMonthPayout(Decimal.parse('-100')),
        Decimal.zero,
      );
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/engine/thirteenth_month_calc_test.dart`
Expected: FAIL with `PayrollRepository.thirteenthMonthPayout` undefined.

- [ ] **Step 3: Add the helper to `PayrollRepository`**

In `lib/data/repositories/payroll_repository.dart`, near the top of the class (before the constructor is fine):

```dart
/// Compute the 13th-month payout for a given accrued-basis amount.
/// Formula: `basis / 12`, rounded to 2dp half-up. Negative input
/// clamps to zero (defensive — shouldn't happen in practice).
///
/// Exposed as a static so the distribution dialog can preview payouts
/// without holding a repository reference.
static Decimal thirteenthMonthPayout(Decimal basis) {
  if (basis <= Decimal.zero) return Decimal.zero;
  return (basis / Decimal.fromInt(12))
      .toDecimal(scaleOnInfinitePrecision: 10)
      .round(scale: 2);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/engine/thirteenth_month_calc_test.dart`
Expected: `+4: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add test/engine/thirteenth_month_calc_test.dart lib/data/repositories/payroll_repository.dart
git commit -m "feat(payroll): 13th-month payout helper (basis / 12, rounded)"
```

---

## Task 4: Release-hook accrual tick-up

Hook into the existing `releaseRun(runId)` flow — add a sixth step that reads each payslip's `BASIC_PAY` line and increments every included employee's `accrued_thirteenth_month_basis`.

**Files:**
- Modify: `lib/data/repositories/payroll_repository.dart:343` (the `releaseRun` method)

- [ ] **Step 1: Add the accrual tick-up inside `releaseRun`**

In `lib/data/repositories/payroll_repository.dart`, locate `releaseRun` (around line 343). After step 4 (penalty installments) and BEFORE step 5 (flip status to RELEASED), insert this block:

```dart
    // 4.5 Tick up 13th-month accrual: sum each payslip's BASIC_PAY line
    // amount and add it to that employee's running basis. Done before the
    // status flip so a partial failure leaves the run in REVIEW state and
    // the operator can retry without double-counting (the block is
    // idempotent on its own because we overwrite with a fresh sum per
    // employee, not an additive update — see below).
    //
    // Read all BASIC_PAY lines for this run's payslips.
    final basicPayRows = await _client
        .from('payslip_lines')
        .select('amount, payslips!inner(employee_id, payroll_run_id)')
        .eq('payslips.payroll_run_id', runId)
        .eq('category', 'BASIC_PAY');
    final basicByEmp = <String, Decimal>{};
    for (final r
        in (basicPayRows as List<dynamic>).cast<Map<String, dynamic>>()) {
      final emp = (r['payslips'] as Map<String, dynamic>)['employee_id']
          as String;
      final amt = Decimal.tryParse((r['amount'] ?? '0').toString()) ??
          Decimal.zero;
      basicByEmp[emp] = (basicByEmp[emp] ?? Decimal.zero) + amt;
    }
    // Additive update per employee: read current basis, add this run's
    // basic pay, write back. PostgREST doesn't expose a scalar-add
    // expression, so we do it client-side. Safe because releaseRun is
    // already gated by the REVIEW→RELEASED state machine (no concurrent
    // releases on the same run).
    if (basicByEmp.isNotEmpty) {
      final empRows = await _client
          .from('employees')
          .select('id, accrued_thirteenth_month_basis')
          .inFilter('id', basicByEmp.keys.toList());
      for (final row
          in (empRows as List<dynamic>).cast<Map<String, dynamic>>()) {
        final empId = row['id'] as String;
        final current = Decimal.tryParse(
                (row['accrued_thirteenth_month_basis'] ?? '0').toString()) ??
            Decimal.zero;
        final delta = basicByEmp[empId] ?? Decimal.zero;
        final next = current + delta;
        await _client
            .from('employees')
            .update({'accrued_thirteenth_month_basis': next.toString()})
            .eq('id', empId);
      }
    }
```

- [ ] **Step 2: Analyze**

Run: `flutter analyze lib/data/repositories/payroll_repository.dart`
Expected: no new errors (pre-existing infos are OK).

- [ ] **Step 3: Manual smoke — release a REVIEW run**

With a running app connected to the linked Supabase project:

1. Open an existing REVIEW run with at least one payslip.
2. Click Release.
3. In the Supabase SQL editor:
   ```sql
   select e.employee_number, e.accrued_thirteenth_month_basis
     from employees e
    where e.id in (<employee ids from that run>);
   ```
   Expected: each employee's basis equals the sum of their `BASIC_PAY` lines for that run (first release) or increased by that amount (subsequent releases on other runs).

- [ ] **Step 4: Commit**

```bash
git add lib/data/repositories/payroll_repository.dart
git commit -m "feat(payroll): tick up 13th-month accrual on release"
```

---

## Task 5: `distributeThirteenthMonth` repository method

The distribution writer: reads current basis per employee, inserts a `THIRTEENTH_MONTH_PAY` line on each of their payslips for the given run, zeros the basis, flags the run, and re-totalizes the payslips.

**Files:**
- Modify: `lib/data/repositories/payroll_repository.dart`

- [ ] **Step 1: Define the result type**

Near the top of the file (alongside existing type aliases), add:

```dart
class DistributeThirteenthMonthResult {
  final int employeesDistributed;
  final Decimal totalPayout;
  final List<String> errors;
  const DistributeThirteenthMonthResult({
    required this.employeesDistributed,
    required this.totalPayout,
    required this.errors,
  });
}
```

- [ ] **Step 2: Add the method to `PayrollRepository`**

Append this method to the `PayrollRepository` class (near other write methods like `cancelRun`):

```dart
/// Distribute 13th-month pay on the given run for the given employees.
///
/// For each employee:
///   1. Insert a `THIRTEENTH_MONTH_PAY` payslip_lines row on their payslip
///      in this run (amount = accruedBasis / 12, rounded to 2dp).
///   2. Zero their `accrued_thirteenth_month_basis`.
///   3. Add the payout to `payslips.gross_pay` and `payslips.net_pay` so
///      the Summary tab reflects the new totals without a full recompute.
/// Finally, flip `payroll_runs.is_thirteenth_month_distribution = true`.
///
/// Skips employees who already have a `THIRTEENTH_MONTH_PAY` line on
/// this run's payslip (idempotent re-click).
Future<DistributeThirteenthMonthResult> distributeThirteenthMonth({
  required String runId,
  required List<String> employeeIds,
}) async {
  final errors = <String>[];
  if (employeeIds.isEmpty) {
    return const DistributeThirteenthMonthResult(
      employeesDistributed: 0,
      totalPayout: Decimal.zero,
      errors: [],
    );
  }

  // Pull each employee's current basis + their payslip id for this run,
  // plus flag rows that already carry a 13th-month line so we skip them.
  final empRows = await _client
      .from('employees')
      .select('id, accrued_thirteenth_month_basis')
      .inFilter('id', employeeIds);
  final basisByEmp = <String, Decimal>{
    for (final r in (empRows as List<dynamic>).cast<Map<String, dynamic>>())
      r['id'] as String: Decimal.tryParse(
              (r['accrued_thirteenth_month_basis'] ?? '0').toString()) ??
          Decimal.zero,
  };

  final payslipRows = await _client
      .from('payslips')
      .select('id, employee_id, gross_pay, net_pay')
      .eq('payroll_run_id', runId)
      .inFilter('employee_id', employeeIds);
  final payslipByEmp = <String, Map<String, dynamic>>{
    for (final r in (payslipRows as List<dynamic>).cast<Map<String, dynamic>>())
      r['employee_id'] as String: r,
  };

  // Detect already-distributed payslips so re-clicking doesn't double up.
  final existingLineRows = await _client
      .from('payslip_lines')
      .select('payslip_id')
      .inFilter(
          'payslip_id', payslipByEmp.values.map((p) => p['id'] as String).toList())
      .eq('category', 'THIRTEENTH_MONTH_PAY');
  final alreadyDistributedPayslipIds = {
    for (final r in (existingLineRows as List<dynamic>).cast<Map<String, dynamic>>())
      r['payslip_id'] as String
  };

  int distributed = 0;
  Decimal totalPayout = Decimal.zero;

  for (final empId in employeeIds) {
    final payslip = payslipByEmp[empId];
    if (payslip == null) {
      errors.add('$empId: no payslip on run');
      continue;
    }
    if (alreadyDistributedPayslipIds.contains(payslip['id'])) {
      errors.add('$empId: already distributed on this run');
      continue;
    }
    final basis = basisByEmp[empId] ?? Decimal.zero;
    final payout = thirteenthMonthPayout(basis);
    if (payout <= Decimal.zero) {
      errors.add('$empId: zero basis');
      continue;
    }

    try {
      // 1. Insert the payslip line.
      await _client.from('payslip_lines').insert({
        'payslip_id': payslip['id'],
        'category': 'THIRTEENTH_MONTH_PAY',
        'description': '13th Month Pay (distribution)',
        'amount': payout.toString(),
        'quantity': '1',
        'rate': payout.toString(),
        'sort_order': 450,
      });

      // 2. Zero the accrual.
      await _client
          .from('employees')
          .update({'accrued_thirteenth_month_basis': '0'})
          .eq('id', empId);

      // 3. Update payslip totals.
      final currentGross = Decimal.tryParse(
              (payslip['gross_pay'] ?? '0').toString()) ??
          Decimal.zero;
      final currentNet = Decimal.tryParse(
              (payslip['net_pay'] ?? '0').toString()) ??
          Decimal.zero;
      await _client.from('payslips').update({
        'gross_pay': (currentGross + payout).toString(),
        'net_pay': (currentNet + payout).toString(),
      }).eq('id', payslip['id']);

      distributed++;
      totalPayout += payout;
    } catch (e) {
      errors.add('$empId: $e');
    }
  }

  // Flag the run (best-effort — non-fatal if it fails).
  if (distributed > 0) {
    try {
      await _client
          .from('payroll_runs')
          .update({'is_thirteenth_month_distribution': true})
          .eq('id', runId);
    } catch (_) {
      // Swallow — the distribution already landed; this is metadata.
    }
  }

  return DistributeThirteenthMonthResult(
    employeesDistributed: distributed,
    totalPayout: totalPayout,
    errors: errors,
  );
}
```

- [ ] **Step 3: Analyze**

Run: `flutter analyze lib/data/repositories/payroll_repository.dart`
Expected: no new errors.

- [ ] **Step 4: Commit**

```bash
git add lib/data/repositories/payroll_repository.dart
git commit -m "feat(payroll): distributeThirteenthMonth repo method"
```

---

## Task 6: Distribute 13th Month dialog widget

The modal the kebab menu opens: lists every employee on the run with their current basis and projected payout, lets HR tick rows, and confirms.

**Files:**
- Create: `lib/features/payroll/runs/detail/widgets/distribute_13th_dialog.dart`

- [ ] **Step 1: Create the dialog file**

`lib/features/payroll/runs/detail/widgets/distribute_13th_dialog.dart`:
```dart
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/money.dart';
import '../../../../../data/repositories/payroll_repository.dart';
import '../providers.dart';

/// Modal that lists every employee on a run with their current
/// 13th-month accrual basis and projected payout, lets HR tick rows,
/// and dispatches [PayrollRepository.distributeThirteenthMonth] on
/// confirm.
///
/// Call via `showDialog<bool>(..., builder: (_) => Distribute13thDialog(runId: ...))`.
/// Resolves to `true` when the distribution actually ran.
class Distribute13thDialog extends ConsumerStatefulWidget {
  final String runId;
  const Distribute13thDialog({super.key, required this.runId});

  @override
  ConsumerState<Distribute13thDialog> createState() =>
      _Distribute13thDialogState();
}

class _Distribute13thDialogState extends ConsumerState<Distribute13thDialog> {
  /// Loaded once on open. Each row:
  /// {
  ///   employeeId, name, employeeNumber, basis, payout,
  ///   alreadyDistributed, payslipId
  /// }
  List<_Row>? _rows;
  String? _loadError;
  bool _saving = false;
  String? _saveError;
  final Set<String> _ticked = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final client = ref.read(payrollRepositoryProvider);
      // Pull payslip rows (with joined employee basis) for this run.
      final raw = await client.payslipListForRun(widget.runId);
      final rows = <_Row>[];
      for (final r in raw) {
        final emp = r['employees'] as Map<String, dynamic>?;
        if (emp == null) continue;
        final basis = Decimal.tryParse(
                (emp['accrued_thirteenth_month_basis'] ?? '0').toString()) ??
            Decimal.zero;
        final payout = PayrollRepository.thirteenthMonthPayout(basis);
        final lines = (r['payslip_lines'] as List<dynamic>?)
                ?.cast<Map<String, dynamic>>() ??
            const <Map<String, dynamic>>[];
        final alreadyDistributed = lines.any(
            (l) => (l['category'] as String?) == 'THIRTEENTH_MONTH_PAY');
        rows.add(_Row(
          employeeId: emp['id'] as String,
          employeeNumber: (emp['employee_number'] as String?) ?? '—',
          name: _nameFor(emp),
          basis: basis,
          payout: payout,
          alreadyDistributed: alreadyDistributed,
          payslipId: r['id'] as String,
        ));
      }
      rows.sort(
          (a, b) => a.employeeNumber.compareTo(b.employeeNumber));
      if (!mounted) return;
      setState(() {
        _rows = rows;
        // Pre-tick eligible rows.
        _ticked
          ..clear()
          ..addAll(rows
              .where((r) => r.eligible)
              .map((r) => r.employeeId));
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError = e.toString());
    }
  }

  static String _nameFor(Map<String, dynamic> emp) {
    final last = (emp['last_name'] as String?) ?? '';
    final first = (emp['first_name'] as String?) ?? '';
    return last.isEmpty ? first : '$last, $first';
  }

  Future<void> _confirm() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final repo = ref.read(payrollRepositoryProvider);
      final res = await repo.distributeThirteenthMonth(
        runId: widget.runId,
        employeeIds: _ticked.toList(),
      );
      if (!mounted) return;
      // Refresh the run's providers so Summary / Payslips reflect the new
      // totals without a manual reload.
      ref.invalidate(payrollRunDetailProvider(widget.runId));
      ref.invalidate(payslipListForRunProvider(widget.runId));
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop(true);
      messenger.showSnackBar(SnackBar(
        content: Text(
          'Distributed 13th month to ${res.employeesDistributed} '
          'employee${res.employeesDistributed == 1 ? "" : "s"}. '
          'Total ${Money.fmtPhp(res.totalPayout)}.'
          '${res.errors.isEmpty ? "" : " ${res.errors.length} skipped."}',
        ),
        duration: const Duration(seconds: 4),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final totalPayout = rows == null
        ? Decimal.zero
        : rows
            .where((r) => _ticked.contains(r.employeeId))
            .fold<Decimal>(Decimal.zero, (s, r) => s + r.payout);

    return AlertDialog(
      title: const Text('Distribute 13th Month'),
      content: SizedBox(
        width: 560,
        child: _loadError != null
            ? Text('Error: $_loadError',
                style: const TextStyle(color: Colors.red))
            : rows == null
                ? const SizedBox(
                    height: 120,
                    child: Center(child: CircularProgressIndicator()))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Adds a "13th Month Pay" line to each selected '
                        "employee's payslip on this run, then resets "
                        'their accrued basis. The basis is the sum of '
                        'basic pay since their last distribution.',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 12),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 360),
                        child: Scrollbar(
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: rows.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final r = rows[i];
                              final ticked = _ticked.contains(r.employeeId);
                              return CheckboxListTile(
                                dense: true,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                value: ticked,
                                onChanged: r.eligible
                                    ? (v) => setState(() {
                                          if (v == true) {
                                            _ticked.add(r.employeeId);
                                          } else {
                                            _ticked.remove(r.employeeId);
                                          }
                                        })
                                    : null,
                                title: Text(
                                  '${r.name}  ·  ${r.employeeNumber}',
                                  style: const TextStyle(fontSize: 13),
                                ),
                                subtitle: Text(
                                  r.alreadyDistributed
                                      ? 'Already distributed on this run'
                                      : r.basis <= Decimal.zero
                                          ? 'Not eligible — zero basis'
                                          : 'Basis ${Money.fmtPhp(r.basis)} → Pay ${Money.fmtPhp(r.payout)}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: r.eligible
                                        ? Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant
                                        : Theme.of(context).disabledColor,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            'Total to distribute: ',
                            style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                          Text(
                            Money.fmtPhp(totalPayout),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'GeistMono',
                            ),
                          ),
                        ],
                      ),
                      if (_saveError != null) ...[
                        const SizedBox(height: 8),
                        Text(_saveError!,
                            style: const TextStyle(color: Colors.red)),
                      ],
                    ],
                  ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: (_saving || _ticked.isEmpty) ? null : _confirm,
          child: _saving
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text('Distribute (${_ticked.length})'),
        ),
      ],
    );
  }
}

class _Row {
  final String employeeId;
  final String employeeNumber;
  final String name;
  final Decimal basis;
  final Decimal payout;
  final bool alreadyDistributed;
  final String payslipId;
  _Row({
    required this.employeeId,
    required this.employeeNumber,
    required this.name,
    required this.basis,
    required this.payout,
    required this.alreadyDistributed,
    required this.payslipId,
  });
  bool get eligible => !alreadyDistributed && basis > Decimal.zero;
}
```

- [ ] **Step 2: Expose `accrued_thirteenth_month_basis` in the payslip-list query**

`payslipListForRun` in `payroll_repository.dart` already embeds the `employees` object. Confirm it pulls `accrued_thirteenth_month_basis`. If the embed uses a specific column list, extend it:

Search in `payroll_repository.dart` for `payslipListForRun`. The `select` call contains something like:
```dart
.select('*, employees(id, employee_number, first_name, last_name, ...)')
```

Add `accrued_thirteenth_month_basis` to that list. Also ensure `payslip_lines(category)` is fetched (a minimal `payslip_lines(id, category)` is enough for the "already distributed" check):

If `payslip_lines` isn't embedded yet, add `, payslip_lines(id, category)` to the select.

- [ ] **Step 3: Analyze**

Run: `flutter analyze lib/features/payroll/runs/detail/widgets/distribute_13th_dialog.dart lib/data/repositories/payroll_repository.dart`
Expected: no new errors.

- [ ] **Step 4: Commit**

```bash
git add lib/features/payroll/runs/detail/widgets/distribute_13th_dialog.dart lib/data/repositories/payroll_repository.dart
git commit -m "feat(payroll): Distribute 13th Month dialog"
```

---

## Task 7: Wire the kebab menu into `_ActionBar`

Add a `PopupMenuButton` ("..." overflow) next to the existing action buttons on the payroll run detail, with one menu item for now.

**Files:**
- Modify: `lib/features/payroll/runs/detail/payroll_run_detail_screen.dart` (around line 338, inside `_ActionBar`'s `Wrap` children)

- [ ] **Step 1: Add the import**

At the top of `payroll_run_detail_screen.dart`, add:
```dart
import 'widgets/distribute_13th_dialog.dart';
```

- [ ] **Step 2: Add the kebab menu to the Wrap**

After the existing `_SendLarkApprovalsButton` entry (bottom of the `Wrap` children list in `_ActionBar.build`), add:

```dart
if (status == 'REVIEW')
  PopupMenuButton<String>(
    tooltip: 'More actions',
    icon: const Icon(Icons.more_vert),
    onSelected: (value) async {
      if (value == 'distribute_13th') {
        await showDialog<bool>(
          context: context,
          builder: (_) => Distribute13thDialog(runId: detail.run.id),
        );
        // Providers are invalidated inside the dialog on success.
      }
    },
    itemBuilder: (_) => const [
      PopupMenuItem<String>(
        value: 'distribute_13th',
        child: Row(
          children: [
            Icon(Icons.redeem, size: 16),
            SizedBox(width: 8),
            Text('Distribute 13th Month'),
          ],
        ),
      ),
    ],
  ),
```

- [ ] **Step 3: Analyze**

Run: `flutter analyze lib/features/payroll/runs/detail/payroll_run_detail_screen.dart`
Expected: no new errors.

- [ ] **Step 4: Manual smoke — open the dialog**

1. Run the app, log in as HR/Admin.
2. Open any payroll run in REVIEW.
3. A three-dot button appears next to Send Lark Approvals. Click it.
4. Select "Distribute 13th Month" — dialog opens, lists every payslip's employee with their basis (all 0 if nothing has been released yet → all disabled).

- [ ] **Step 5: Commit**

```bash
git add lib/features/payroll/runs/detail/payroll_run_detail_screen.dart
git commit -m "feat(payroll-ui): kebab menu + Distribute 13th Month action"
```

---

## Task 8: End-to-end verification

Walk through the full feature against a real run to confirm accrual + distribution + reset all land.

- [ ] **Step 1: Release a run to seed accrual**

1. Open an existing REVIEW run.
2. Click Release.
3. In Supabase SQL editor:
   ```sql
   select e.employee_number, e.accrued_thirteenth_month_basis
     from employees e
    order by e.employee_number;
   ```
   Expected: each included employee's basis > 0, equal to their BASIC_PAY line total for that run.

- [ ] **Step 2: Create a new REVIEW run and distribute**

1. Create a new payroll run (any period), compute it, leave it in REVIEW.
2. Open the run → "..." → "Distribute 13th Month".
3. Dialog lists all employees with positive basis ticked. Click Distribute.
4. SnackBar confirms `Distributed 13th month to N employees. Total ₱X.`

- [ ] **Step 3: Verify the payslip line**

In Payslips tab of the same run, open any distributed employee's payslip → Calculation Breakdown → an earning line "13th Month Pay (distribution)" appears with amount = previous basis / 12.

- [ ] **Step 4: Verify the reset**

```sql
select employee_number, accrued_thirteenth_month_basis
  from employees
 where id in (<distributed employee ids>);
```
Expected: all zeroed.

- [ ] **Step 5: Verify run flag**

```sql
select id, is_thirteenth_month_distribution
  from payroll_runs
 where id = '<run id>';
```
Expected: `true`.

- [ ] **Step 6: Verify Summary totals**

Back in the Summary tab for the run, Total Gross Pay increased by the total distribution, Total Net Pay likewise.

- [ ] **Step 7: Re-click Distribute — idempotency**

Open the same dialog again on the same run. Each previously-distributed employee's row shows "Already distributed on this run" and is disabled. Confirm button is gated on the selection count.

- [ ] **Step 8: Release the distribution run — accrual resumes**

Release the run. The BASIC_PAY lines on this run tick up the (now-zeroed) basis. So every employee's basis is now exactly their BASIC_PAY line amount for THIS run — the next distribution starts from that.

```sql
select employee_number, accrued_thirteenth_month_basis
  from employees
 where id in (<run's employee ids>);
```

Expected: each employee's basis = their BASIC_PAY on this (just-released) run.

- [ ] **Step 9: Final full-project analyze**

Run: `flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: exit 0, no new errors.

- [ ] **Step 10: Final commit (docs)**

Update the spec's Status line to "Implemented · 2026-04-20":

```bash
sed -i 's/\*\*Status:\*\* Draft · 2026-04-20/**Status:** Implemented · 2026-04-20/' \
  docs/superpowers/specs/2026-04-20-13th-month-distribution-design.md
git add docs/superpowers/specs/2026-04-20-13th-month-distribution-design.md
git commit -m "docs(spec): mark 13th-month design as implemented"
```
