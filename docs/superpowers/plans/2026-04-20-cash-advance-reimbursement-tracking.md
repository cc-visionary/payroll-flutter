# Cash Advance & Reimbursement Tracking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring cash advances and reimbursements to feature parity with penalties (per-run skip + deduction/payout tracking + payslip link), plus two employee-profile polish items (PDF link on every payslip row, remove redundant HOURS card).

**Architecture:** Mirror the existing penalty skip design — array column `skipped_payroll_run_ids` on `cash_advances` and `reimbursements`, honored in the compute loaders, toggled through repository methods. The payslip breakdown tab gains Skip branches for CA (deductions) and reimbursement (earnings); the Financials tab gets a richer card that resolves the consuming payslip via a follow-up `payslip_lines` query.

**Tech Stack:** Flutter (Material 3, Riverpod, GoRouter), Supabase (Postgres migrations + PostgREST), Dart.

**Spec:** `docs/superpowers/specs/2026-04-20-cash-advance-reimbursement-tracking-design.md`

---

## File Structure

### New files

- `supabase/migrations/20260420000002_ca_reimbursement_skip.sql` — column + GIN index on both tables.

### Modified files

- `lib/features/employees/profile/tabs/payslips_tab.dart` — drop `if (released)` gate.
- `lib/features/employees/profile/tabs/role_tab.dart` — remove HOURS card, re-tune grid breakpoints.
- `lib/features/payroll/runs/compute/compute_service.dart` — honor skip arrays in `_loadCashAdvances` and `_loadReimbursements`.
- `lib/data/repositories/payroll_repository.dart` — add `setCashAdvanceSkip` and `setReimbursementSkip`.
- `lib/features/employees/profile/widgets/info_card.dart` — extend `toneForStatus` to map `DEDUCTED` → success.
- `lib/features/payroll/payslips/detail/tabs/breakdown_tab.dart` — Skip action on CA deductions and reimbursement earnings.
- `lib/features/employees/profile/providers.dart` — enrich `financialsByEmployeeProvider` with payslip id lookup.
- `lib/features/employees/profile/tabs/financials_tab.dart` — rebuild the generic card for CA/reimbursement.

---

## Task 1: PDF link on every payslip row (Piece 1)

**Files:**
- Modify: `lib/features/employees/profile/tabs/payslips_tab.dart:385-469`

- [ ] **Step 1: Remove the `released` gate**

In `lib/features/employees/profile/tabs/payslips_tab.dart`, locate the `_PayslipRow.build` method. Around line 385 there's a local `released` bool and around line 464 an `if (released)` guard on the PDF button. Remove both — the button should render unconditionally.

Replace:

```dart
    final released = p.approvalStatus == 'APPROVED' ||
        p.approvalStatus == 'RELEASED';
```

with nothing (delete those two lines), and replace:

```dart
              if (released)
                OutlinedButton.icon(
                  onPressed: () => context.push('/payslips/${p.id}'),
                  icon: const Icon(Icons.picture_as_pdf, size: 14),
                  label: const Text('PDF'),
                ),
```

with:

```dart
              OutlinedButton.icon(
                onPressed: () => context.push('/payslips/${p.id}'),
                icon: const Icon(Icons.picture_as_pdf, size: 14),
                label: const Text('PDF'),
              ),
```

- [ ] **Step 2: Static analysis**

Run: `flutter analyze lib/features/employees/profile/tabs/payslips_tab.dart`
Expected: `No issues found!`

- [ ] **Step 3: Manual smoke test**

Open any employee with draft payslips. Confirm the PDF button renders on every row. Tap one — the preview screen loads.

- [ ] **Step 4: Commit**

```bash
git add lib/features/employees/profile/tabs/payslips_tab.dart
git commit -m "feat(employee): show payslip PDF link for every row"
```

---

## Task 2: Remove redundant HOURS card on Role tab (Piece 2)

**Files:**
- Modify: `lib/features/employees/profile/tabs/role_tab.dart:92-146`

- [ ] **Step 1: Delete the HOURS card + rebalance the grid**

In `lib/features/employees/profile/tabs/role_tab.dart`, find the `LayoutBuilder` inside the "Current Role" section. Replace the block from the `cardWidth` calculation through the closing of the `Wrap` children list:

Replace:

```dart
              LayoutBuilder(builder: (ctx, c) {
                final cardWidth = c.maxWidth >= 920
                    ? (c.maxWidth - 3 * 12) / 4
                    : c.maxWidth >= 600
                        ? (c.maxWidth - 12) / 2
                        : c.maxWidth;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: cardWidth,
                      child: _TintedCard(
                        label: 'POSITION',
                        value: card.jobTitle,
                        subtitle: departmentName,
                        bg: const Color(0xFFEFF6FF),
                        fg: const Color(0xFF1D4ED8),
                      ),
                    ),
                    SizedBox(
                      width: cardWidth,
                      child: _TintedCard(
                        label: 'BASE SALARY',
                        value: card.baseSalary == null
                            ? '—'
                            : Money.fmtPhp(card.baseSalary!),
                        subtitle: card.wageType.toLowerCase(),
                        bg: const Color(0xFFECFDF5),
                        fg: const Color(0xFF047857),
                      ),
                    ),
                    SizedBox(
                      width: cardWidth,
                      child: _TintedCard(
                        label: 'WORK SCHEDULE',
                        value: '${card.workHoursPerDay}h / day',
                        subtitle: card.workDaysPerWeek,
                        bg: const Color(0xFFF5F3FF),
                        fg: const Color(0xFF6D28D9),
                      ),
                    ),
                    SizedBox(
                      width: cardWidth,
                      child: _TintedCard(
                        label: 'HOURS',
                        value: '${card.workHoursPerDay}h / day',
                        subtitle: card.workDaysPerWeek,
                        bg: null,
                        fg: null,
                      ),
                    ),
                  ],
                );
              }),
```

with:

```dart
              LayoutBuilder(builder: (ctx, c) {
                final cardWidth = c.maxWidth >= 920
                    ? (c.maxWidth - 2 * 12) / 3
                    : c.maxWidth >= 600
                        ? (c.maxWidth - 12) / 2
                        : c.maxWidth;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: cardWidth,
                      child: _TintedCard(
                        label: 'POSITION',
                        value: card.jobTitle,
                        subtitle: departmentName,
                        bg: const Color(0xFFEFF6FF),
                        fg: const Color(0xFF1D4ED8),
                      ),
                    ),
                    SizedBox(
                      width: cardWidth,
                      child: _TintedCard(
                        label: 'BASE SALARY',
                        value: card.baseSalary == null
                            ? '—'
                            : Money.fmtPhp(card.baseSalary!),
                        subtitle: card.wageType.toLowerCase(),
                        bg: const Color(0xFFECFDF5),
                        fg: const Color(0xFF047857),
                      ),
                    ),
                    SizedBox(
                      width: cardWidth,
                      child: _TintedCard(
                        label: 'WORK SCHEDULE',
                        value: '${card.workHoursPerDay}h / day',
                        subtitle: card.workDaysPerWeek,
                        bg: const Color(0xFFF5F3FF),
                        fg: const Color(0xFF6D28D9),
                      ),
                    ),
                  ],
                );
              }),
```

(Two edits: `3 * 12 / 4` → `2 * 12 / 3` on the width calc; drop the trailing HOURS `SizedBox`.)

- [ ] **Step 2: Static analysis**

Run: `flutter analyze lib/features/employees/profile/tabs/role_tab.dart`
Expected: `No issues found!`

- [ ] **Step 3: Manual smoke test**

Open an employee → Role & Responsibilities tab. At desktop width confirm three cards across one row with no trailing whitespace. Resize below 920px and confirm the 2-column fallback still works.

- [ ] **Step 4: Commit**

```bash
git add lib/features/employees/profile/tabs/role_tab.dart
git commit -m "refactor(employee): drop redundant HOURS card on Role tab"
```

---

## Task 3: DB migration — skip arrays on CA + reimbursements (Piece 3)

**Files:**
- Create: `supabase/migrations/20260420000002_ca_reimbursement_skip.sql`

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/20260420000002_ca_reimbursement_skip.sql` with exactly this content:

```sql
-- Per-run skip lists on cash_advances and reimbursements. Mirrors the penalty
-- installment pattern (migration 20260418000009): when HR decides a specific
-- payroll run should skip this record (e.g. employee already settled it
-- out-of-band, or wants a one-period deferral), the run id goes into the
-- array. The compute service then treats the record as ineligible for that
-- run only; subsequent runs still pick it up because `is_deducted` /
-- `is_paid` stay false.
--
-- Array column + GIN index keeps this a zero-join design that round-trips
-- cleanly through the Supabase Dart client.

alter table cash_advances
  add column if not exists skipped_payroll_run_ids uuid[] not null default '{}';

create index if not exists idx_cash_advances_skipped
  on cash_advances using gin (skipped_payroll_run_ids);

alter table reimbursements
  add column if not exists skipped_payroll_run_ids uuid[] not null default '{}';

create index if not exists idx_reimbursements_skipped
  on reimbursements using gin (skipped_payroll_run_ids);
```

- [ ] **Step 2: Apply the migration locally**

Run: `supabase db reset` (if a local stack is running) or `supabase db push` against the dev project, depending on the team's usual workflow. The cheapest sanity check:

```bash
cd "/home/ccvisionary/Documents/Work/[07] Projects/payroll-flutter"
supabase migration list
```

Expected: the new file appears in the list.

Run the migration against the local database and verify:

```sql
\d cash_advances
\d reimbursements
```

Expected: both tables show `skipped_payroll_run_ids uuid[] NOT NULL DEFAULT '{}'::uuid[]` and GIN indexes `idx_cash_advances_skipped` / `idx_reimbursements_skipped`.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260420000002_ca_reimbursement_skip.sql
git commit -m "feat(db): add skipped_payroll_run_ids to cash_advances and reimbursements"
```

---

## Task 4: Compute service honors the new skip arrays (Piece 4)

**Files:**
- Modify: `lib/features/payroll/runs/compute/compute_service.dart:419-464`

- [ ] **Step 1: Change `_loadCashAdvances` to accept `runId` and filter**

The method signature today is `_loadCashAdvances(String companyId, DateTime periodStart, DateTime periodEnd)`. Add `runId` and apply the skip filter client-side after the query.

Locate the method around `:419` and replace the signature and body with:

```dart
  Future<Map<String, List<Map<String, dynamic>>>> _loadCashAdvances(
      String companyId,
      DateTime periodStart,
      DateTime periodEnd,
      String runId) async {
    // Local `status` is cash_advance_status enum: PENDING / DEDUCTED / CANCELLED.
    // "Approved in Lark, not yet deducted by payroll" = status == PENDING AND
    // lark_approval_status == 'APPROVED' AND is_deducted == false.
    //
    // Date rule: only pull advances approved inside the pay period. An advance
    // approved on Mar 25 must not land in a Jan 1-15 run.
    final startIso = periodStart.toIso8601String();
    // End-of-period = endDate + 1 day (exclusive upper bound handles timezones
    // around midnight and approvals timestamped at 23:59:59.xxx).
    final endExclusiveIso = periodEnd
        .add(const Duration(days: 1))
        .toIso8601String();
    final rows = await _client
        .from('cash_advances')
        .select()
        .eq('company_id', companyId)
        .eq('status', 'PENDING')
        .eq('lark_approval_status', 'APPROVED')
        .eq('is_deducted', false)
        .gte('lark_approved_at', startIso)
        .lt('lark_approved_at', endExclusiveIso);
    // Skip-list filter — mirrors the penalty installment pattern. If HR has
    // deferred this advance for the current run, drop it; the record is
    // untouched (`is_deducted` stays false) so the next run still sees it.
    final filtered = (rows as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .where((r) {
      final skipped = r['skipped_payroll_run_ids'];
      return !(skipped is List && skipped.contains(runId));
    }).toList();
    return _groupBy(filtered, 'employee_id');
  }
```

- [ ] **Step 2: Change `_loadReimbursements` to accept `runId` and filter**

Same pattern. Replace the method around `:444`:

```dart
  Future<Map<String, List<Map<String, dynamic>>>> _loadReimbursements(
      String companyId,
      DateTime periodStart,
      DateTime periodEnd,
      String runId) async {
    // Same pattern as cash advances — local status is reimbursement_status enum
    // (PENDING / PAID / CANCELLED). The "ready to pay" filter is PENDING +
    // Lark-approved + not yet paid.
    //
    // Date rule: only pull reimbursements whose `transaction_date` (when the
    // expense was incurred) falls inside the pay period.
    final startIso = periodStart.toIso8601String().substring(0, 10);
    final endIso = periodEnd.toIso8601String().substring(0, 10);
    final rows = await _client
        .from('reimbursements')
        .select()
        .eq('company_id', companyId)
        .eq('status', 'PENDING')
        .eq('lark_approval_status', 'APPROVED')
        .eq('is_paid', false)
        .gte('transaction_date', startIso)
        .lte('transaction_date', endIso);
    final filtered = (rows as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .where((r) {
      final skipped = r['skipped_payroll_run_ids'];
      return !(skipped is List && skipped.contains(runId));
    }).toList();
    return _groupBy(filtered, 'employee_id');
  }
```

- [ ] **Step 3: Update the two call sites to pass `runId`**

Find where these loaders are invoked (look for `_loadCashAdvances(` and `_loadReimbursements(` inside `compute_service.dart` — typically in a `Future.wait` block around line 125). Each call currently passes three args; add `runId` as the fourth.

Search with: `grep -n '_loadCashAdvances\|_loadReimbursements' lib/features/payroll/runs/compute/compute_service.dart`

Each call site will have access to `runId` already (it's the method parameter driving the entire compute). Example shape — locate the existing call and append the new arg:

```dart
_loadCashAdvances(companyId, periodStart, periodEnd, runId),
_loadReimbursements(companyId, periodStart, periodEnd, runId),
```

- [ ] **Step 4: Static analysis**

Run: `flutter analyze lib/features/payroll/runs/compute/compute_service.dart`
Expected: `No issues found!` — any "not enough positional arguments" error here means Step 3 missed a call site.

- [ ] **Step 5: Commit**

```bash
git add lib/features/payroll/runs/compute/compute_service.dart
git commit -m "feat(payroll): compute honors skipped_payroll_run_ids on CA and reimbursements"
```

---

## Task 5: Repository — `setCashAdvanceSkip` (Piece 5a)

**Files:**
- Modify: `lib/data/repositories/payroll_repository.dart:335-354`

- [ ] **Step 1: Add the method directly below `setPenaltyInstallmentSkip`**

Insert this method in `lib/data/repositories/payroll_repository.dart` after `setPenaltyInstallmentSkip` (which ends around line 354). Use the same read-modify-write pattern:

```dart
  /// Defer a specific cash advance out of the given payroll run. The
  /// advance is added to `skipped_payroll_run_ids` so the next compute
  /// for that run excludes it; subsequent runs still pick it up because
  /// `is_deducted` is untouched. Caller is expected to trigger a Recompute
  /// afterwards so the payslip_lines are rebuilt without the skipped row.
  ///
  /// [skip] = true to add the run id; false to remove it (undo).
  Future<void> setCashAdvanceSkip({
    required String advanceId,
    required String runId,
    required bool skip,
  }) async {
    final row = await _client
        .from('cash_advances')
        .select('skipped_payroll_run_ids')
        .eq('id', advanceId)
        .single();
    final current =
        (row['skipped_payroll_run_ids'] as List?)?.cast<String>() ?? const [];
    final next = skip
        ? {...current, runId}.toList()
        : current.where((id) => id != runId).toList();
    await _client
        .from('cash_advances')
        .update({'skipped_payroll_run_ids': next})
        .eq('id', advanceId);
  }
```

- [ ] **Step 2: Static analysis**

Run: `flutter analyze lib/data/repositories/payroll_repository.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/data/repositories/payroll_repository.dart
git commit -m "feat(payroll): add PayrollRepository.setCashAdvanceSkip"
```

---

## Task 6: Repository — `setReimbursementSkip` (Piece 5b)

**Files:**
- Modify: `lib/data/repositories/payroll_repository.dart`

- [ ] **Step 1: Add the method directly below `setCashAdvanceSkip`**

```dart
  /// Defer a specific reimbursement out of the given payroll run. The
  /// reimbursement is added to `skipped_payroll_run_ids` so the next
  /// compute for that run excludes it; subsequent runs still pick it up
  /// because `is_paid` is untouched. Caller is expected to trigger a
  /// Recompute afterwards so the payslip_lines are rebuilt without the
  /// skipped row.
  ///
  /// [skip] = true to add the run id; false to remove it (undo).
  Future<void> setReimbursementSkip({
    required String reimbursementId,
    required String runId,
    required bool skip,
  }) async {
    final row = await _client
        .from('reimbursements')
        .select('skipped_payroll_run_ids')
        .eq('id', reimbursementId)
        .single();
    final current =
        (row['skipped_payroll_run_ids'] as List?)?.cast<String>() ?? const [];
    final next = skip
        ? {...current, runId}.toList()
        : current.where((id) => id != runId).toList();
    await _client
        .from('reimbursements')
        .update({'skipped_payroll_run_ids': next})
        .eq('id', reimbursementId);
  }
```

- [ ] **Step 2: Static analysis**

Run: `flutter analyze lib/data/repositories/payroll_repository.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/data/repositories/payroll_repository.dart
git commit -m "feat(payroll): add PayrollRepository.setReimbursementSkip"
```

---

## Task 7: Map `DEDUCTED` status to success tone

**Files:**
- Modify: `lib/features/employees/profile/widgets/info_card.dart:110-133`

- [ ] **Step 1: Add `DEDUCTED` to the success branch**

In `lib/features/employees/profile/widgets/info_card.dart` find the `toneForStatus` switch and add `case 'DEDUCTED':` to the success group (right next to `PAID`, which is already there):

Replace:

```dart
    case 'RELEASED':
    case 'APPROVED':
    case 'COMPLETED':
    case 'ACTIVE':
    case 'PAID':
      return ChipTone.success;
```

with:

```dart
    case 'RELEASED':
    case 'APPROVED':
    case 'COMPLETED':
    case 'ACTIVE':
    case 'PAID':
    case 'DEDUCTED':
      return ChipTone.success;
```

- [ ] **Step 2: Static analysis**

Run: `flutter analyze lib/features/employees/profile/widgets/info_card.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/features/employees/profile/widgets/info_card.dart
git commit -m "feat(ui): map DEDUCTED status to success tone"
```

---

## Task 8: Convert `_EarningsCard` to a ConsumerWidget with runId/runStatus

**Files:**
- Modify: `lib/features/payroll/payslips/detail/tabs/breakdown_tab.dart:56-89, 225-286`

- [ ] **Step 1: Update the two call sites to pass run context**

In `lib/features/payroll/payslips/detail/tabs/breakdown_tab.dart`, update both invocations of `_EarningsCard`. Replace the single-column call site around `:56-57`:

```dart
              _EarningsCard(
                  lines: earnings, total: _dec(payslip['total_earnings'])),
```

with:

```dart
              _EarningsCard(
                lines: earnings,
                total: _dec(payslip['total_earnings']),
                runId: runId,
                runStatus: runStatus,
              ),
```

Replace the two-column call site around `:72-77`:

```dart
                Expanded(
                  child: _EarningsCard(
                    lines: earnings,
                    total: _dec(payslip['total_earnings']),
                  ),
                ),
```

with:

```dart
                Expanded(
                  child: _EarningsCard(
                    lines: earnings,
                    total: _dec(payslip['total_earnings']),
                    runId: runId,
                    runStatus: runStatus,
                  ),
                ),
```

- [ ] **Step 2: Convert `_EarningsCard` to ConsumerWidget + add run fields**

Locate `_EarningsCard` at `:225` and replace the whole class. The Skip plumbing mirrors `_DeductionsCard`: same `_canSkip` predicate, same dialog pattern, but the row is an earning (positive amount, no minus sign). Replace:

```dart
class _EarningsCard extends StatelessWidget {
  final List<Map<String, dynamic>> lines;
  final Decimal total;
  const _EarningsCard({required this.lines, required this.total});

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Earnings',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (lines.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'No earnings.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            for (int i = 0; i < lines.length; i++) ...[
              _LineRow(
                description: lines[i]['description'] as String? ?? '—',
                subtitle: _subtitleFor(lines[i]),
                amountText: Money.fmtPhp(BreakdownTab._dec(lines[i]['amount'])),
              ),
              if (i < lines.length - 1)
                Divider(height: 1, color: Theme.of(context).dividerColor),
            ],
          Divider(height: 1, color: Theme.of(context).dividerColor),
          Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Total Earnings',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  Money.fmtPhp(total),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

with:

```dart
class _EarningsCard extends ConsumerWidget {
  final List<Map<String, dynamic>> lines;
  final Decimal total;
  final String? runId;
  final String? runStatus;
  const _EarningsCard({
    required this.lines,
    required this.total,
    this.runId,
    this.runStatus,
  });

  bool get _canSkip => runId != null && runStatus == 'REVIEW';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _Card(
      title: 'Earnings',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (lines.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'No earnings.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            for (int i = 0; i < lines.length; i++) ...[
              _LineRow(
                description: lines[i]['description'] as String? ?? '—',
                subtitle: _subtitleFor(lines[i]),
                amountText: Money.fmtPhp(BreakdownTab._dec(lines[i]['amount'])),
                trailing: _canSkip
                    ? _reimbursementSkipAction(context, ref, lines[i])
                    : null,
              ),
              if (i < lines.length - 1)
                Divider(height: 1, color: Theme.of(context).dividerColor),
            ],
          Divider(height: 1, color: Theme.of(context).dividerColor),
          Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Total Earnings',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  Money.fmtPhp(total),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Skip link — only shown on lines backed by a `reimbursement_id`. Other
  /// earning categories (basic pay, OT, allowances, etc.) stay as-is.
  Widget? _reimbursementSkipAction(
      BuildContext context, WidgetRef ref, Map<String, dynamic> line) {
    final reimbursementId = line['reimbursement_id'] as String?;
    if (reimbursementId == null) return null;
    return TextButton.icon(
      onPressed: () => _confirmAndSkipReimbursement(context, ref, reimbursementId),
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFF2563EB),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(40, 28),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: const Icon(Icons.skip_next, size: 14),
      label: const Text('Skip'),
    );
  }

  Future<void> _confirmAndSkipReimbursement(
      BuildContext context, WidgetRef ref, String reimbursementId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Skip this reimbursement?'),
        content: const Text(
          'This defers the reimbursement payout to the next pay period. '
          'The payslip needs to be recomputed for the change to take '
          'effect.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Skip'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(payrollRepositoryProvider).setReimbursementSkip(
            reimbursementId: reimbursementId,
            runId: runId!,
            skip: true,
          );
      ref.invalidate(payslipDetailProvider);
      if (!context.mounted) return;
      messenger.showSnackBar(const SnackBar(
        content: Text(
          'Reimbursement skipped. Hit Recompute on the run to rebuild '
          'payslips.',
        ),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Skip failed: $e')));
    }
  }
}
```

- [ ] **Step 3: Static analysis**

Run: `flutter analyze lib/features/payroll/payslips/detail/tabs/breakdown_tab.dart`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add lib/features/payroll/payslips/detail/tabs/breakdown_tab.dart
git commit -m "feat(payslip): add Skip action to reimbursement earnings lines"
```

---

## Task 9: Extend `_DeductionsCard._skipAction` for cash advances

**Files:**
- Modify: `lib/features/payroll/payslips/detail/tabs/breakdown_tab.dart:365-429`

- [ ] **Step 1: Replace `_skipAction` and `_confirmAndSkip` to branch on line type**

In the same file as Task 8, locate `_skipAction` at `:367` and `_confirmAndSkip` at `:384`. Replace the pair with branching logic that dispatches on whether the line carries a `penalty_installment_id` or a `cash_advance_id`. Replace:

```dart
  /// Skip link — only shown on lines backed by a `penalty_installment_id`.
  /// Other deduction categories (statutory, late, cash advance) stay as-is.
  Widget? _skipAction(
      BuildContext context, WidgetRef ref, Map<String, dynamic> line) {
    final installmentId = line['penalty_installment_id'] as String?;
    if (installmentId == null) return null;
    return TextButton.icon(
      onPressed: () => _confirmAndSkip(context, ref, installmentId),
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFF2563EB),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(40, 28),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: const Icon(Icons.skip_next, size: 14),
      label: const Text('Skip'),
    );
  }

  Future<void> _confirmAndSkip(
      BuildContext context, WidgetRef ref, String installmentId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Skip this installment?'),
        content: const Text(
          'This defers the penalty installment to the next pay period. '
          'The payslip needs to be recomputed for the change to take '
          'effect.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Skip'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(payrollRepositoryProvider).setPenaltyInstallmentSkip(
            installmentId: installmentId,
            runId: runId!,
            skip: true,
          );
      // Invalidate this payslip + any list viewing it. The user still
      // needs to hit Recompute on the run to rebuild payslip_lines; the
      // snackbar surfaces that next step.
      ref.invalidate(payslipDetailProvider);
      if (!context.mounted) return;
      messenger.showSnackBar(const SnackBar(
        content: Text(
          'Installment skipped. Hit Recompute on the run to rebuild '
          'payslips.',
        ),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Skip failed: $e')));
    }
  }
}
```

with:

```dart
  /// Skip link — shown on lines backed by a `penalty_installment_id` or a
  /// `cash_advance_id`. Statutory / late / other deduction categories stay
  /// as-is.
  Widget? _skipAction(
      BuildContext context, WidgetRef ref, Map<String, dynamic> line) {
    final installmentId = line['penalty_installment_id'] as String?;
    final advanceId = line['cash_advance_id'] as String?;
    if (installmentId == null && advanceId == null) return null;
    return TextButton.icon(
      onPressed: () {
        if (installmentId != null) {
          _confirmAndSkipInstallment(context, ref, installmentId);
        } else {
          _confirmAndSkipCashAdvance(context, ref, advanceId!);
        }
      },
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFF2563EB),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(40, 28),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: const Icon(Icons.skip_next, size: 14),
      label: const Text('Skip'),
    );
  }

  Future<void> _confirmAndSkipInstallment(
      BuildContext context, WidgetRef ref, String installmentId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Skip this installment?'),
        content: const Text(
          'This defers the penalty installment to the next pay period. '
          'The payslip needs to be recomputed for the change to take '
          'effect.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Skip'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(payrollRepositoryProvider).setPenaltyInstallmentSkip(
            installmentId: installmentId,
            runId: runId!,
            skip: true,
          );
      ref.invalidate(payslipDetailProvider);
      if (!context.mounted) return;
      messenger.showSnackBar(const SnackBar(
        content: Text(
          'Installment skipped. Hit Recompute on the run to rebuild '
          'payslips.',
        ),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Skip failed: $e')));
    }
  }

  Future<void> _confirmAndSkipCashAdvance(
      BuildContext context, WidgetRef ref, String advanceId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Skip this cash advance?'),
        content: const Text(
          'This defers the cash advance deduction to the next pay period. '
          'The payslip needs to be recomputed for the change to take '
          'effect.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Skip'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(payrollRepositoryProvider).setCashAdvanceSkip(
            advanceId: advanceId,
            runId: runId!,
            skip: true,
          );
      ref.invalidate(payslipDetailProvider);
      if (!context.mounted) return;
      messenger.showSnackBar(const SnackBar(
        content: Text(
          'Cash advance skipped. Hit Recompute on the run to rebuild '
          'payslips.',
        ),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Skip failed: $e')));
    }
  }
}
```

- [ ] **Step 2: Static analysis**

Run: `flutter analyze lib/features/payroll/payslips/detail/tabs/breakdown_tab.dart`
Expected: `No issues found!`

- [ ] **Step 3: Manual smoke test**

Open a draft run's payslip that has both a CA and a reimbursement line. Both the Earnings card (reimbursement) and Deductions card (CA + existing penalty) show Skip buttons. Tap Skip on each; dialog copy matches. Recompute the run → skipped lines disappear.

- [ ] **Step 4: Commit**

```bash
git add lib/features/payroll/payslips/detail/tabs/breakdown_tab.dart
git commit -m "feat(payslip): Skip action also covers cash advance deductions"
```

---

## Task 10: Enrich `financialsByEmployeeProvider` with payslip ids

**Files:**
- Modify: `lib/features/employees/profile/providers.dart:73-89`

- [ ] **Step 1: Replace the provider with an enrichment step for CA/reimbursement**

In `lib/features/employees/profile/providers.dart`, replace the existing `financialsByEmployeeProvider` block:

```dart
final financialsByEmployeeProvider =
    FutureProvider.family<List<Map<String, dynamic>>, FinancialsQuery>(
        (ref, q) async {
  // Penalty rows embed their installments so the UI can show "X paid of N"
  // + progress bar without a second round trip. CA/Reimbursement kinds
  // don't have installment tables so we fetch plain rows.
  final fields = q.kind == FinancialKind.penalties
      ? '*, penalty_installments(id, installment_number, amount, is_deducted)'
      : '*';
  final rows = await Supabase.instance.client
      .from(q.kind.table)
      .select(fields)
      .eq('employee_id', q.employeeId)
      .order('created_at', ascending: false)
      .limit(200);
  return (rows as List<dynamic>).cast<Map<String, dynamic>>();
});
```

with a version that, for CA/reimbursement rows with `is_deducted`/`is_paid=true`, resolves each to its consuming payslip via `payslip_lines` and attaches the id under the synthetic key `_payslip_id`:

```dart
final financialsByEmployeeProvider =
    FutureProvider.family<List<Map<String, dynamic>>, FinancialsQuery>(
        (ref, q) async {
  // Penalty rows embed their installments so the UI can show "X paid of N"
  // + progress bar without a second round trip. CA/Reimbursement kinds
  // don't have installment tables so we fetch plain rows, then enrich with
  // the consuming payslip id (resolved via payslip_lines) so the Financials
  // tab can render a "View payslip →" link for already-deducted records.
  final client = Supabase.instance.client;
  final fields = q.kind == FinancialKind.penalties
      ? '*, penalty_installments(id, installment_number, amount, is_deducted)'
      : '*';
  final rawRows = await client
      .from(q.kind.table)
      .select(fields)
      .eq('employee_id', q.employeeId)
      .order('created_at', ascending: false)
      .limit(200);
  final rows = (rawRows as List<dynamic>).cast<Map<String, dynamic>>();

  if (q.kind == FinancialKind.penalties) return rows;

  // Enrichment: for deducted CA or paid reimbursement rows, fetch the
  // payslip_lines whose FK points at them and attach the payslip id. One
  // extra roundtrip, only when there are settled rows to resolve.
  final fkColumn = q.kind == FinancialKind.cashAdvances
      ? 'cash_advance_id'
      : 'reimbursement_id';
  final settledFlag = q.kind == FinancialKind.cashAdvances
      ? 'is_deducted'
      : 'is_paid';
  final settledIds = rows
      .where((r) => r[settledFlag] == true)
      .map((r) => r['id'] as String)
      .toList();
  if (settledIds.isEmpty) return rows;

  final lineRows = await client
      .from('payslip_lines')
      .select('$fkColumn, payslip_id')
      .inFilter(fkColumn, settledIds);
  final payslipByFk = <String, String>{};
  for (final lr in (lineRows as List<dynamic>).cast<Map<String, dynamic>>()) {
    final fk = lr[fkColumn] as String?;
    final payslipId = lr['payslip_id'] as String?;
    if (fk != null && payslipId != null) payslipByFk[fk] = payslipId;
  }
  return rows.map((r) {
    final pid = payslipByFk[r['id'] as String];
    return pid == null ? r : {...r, '_payslip_id': pid};
  }).toList();
});
```

- [ ] **Step 2: Static analysis**

Run: `flutter analyze lib/features/employees/profile/providers.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/features/employees/profile/providers.dart
git commit -m "feat(employee): resolve consuming payslip id for CA/reimbursement rows"
```

---

## Task 11: Rebuild the Financials tab card for CA / Reimbursement

**Files:**
- Modify: `lib/features/employees/profile/tabs/financials_tab.dart:1-720`

- [ ] **Step 1: Add the `go_router` import**

Near the top of `lib/features/employees/profile/tabs/financials_tab.dart`, add the import if not present:

```dart
import 'package:go_router/go_router.dart';
```

- [ ] **Step 2: Replace `_buildGenericCard` with a richer layout**

Locate `_buildGenericCard` at `:591`. Replace its entire body (the method currently returns a simple amount+status row) with:

```dart
  /// Richer layout for Cash Advance / Reimbursement rows. Shows deduction/
  /// payout state, when it happened, and a link to the consuming payslip
  /// (resolved by `financialsByEmployeeProvider` via `_payslip_id`).
  Widget _buildGenericCard(BuildContext context) {
    final amount = row[kind.amountKey];
    final amountText = amount == null
        ? '—'
        : Money.fmtPhp(Decimal.parse(amount.toString()));

    final isCashAdvance = kind == FinancialKind.cashAdvances;
    final settled =
        isCashAdvance ? row['is_deducted'] == true : row['is_paid'] == true;
    final settledAtIso = (isCashAdvance
            ? row['deducted_at']
            : row['paid_at']) as String?;
    final rawStatus = (row['status'] as String?)?.toUpperCase() ?? '';
    final String displayStatus;
    if (rawStatus == 'CANCELLED') {
      displayStatus = 'CANCELLED';
    } else if (settled) {
      displayStatus = isCashAdvance ? 'DEDUCTED' : 'PAID';
    } else {
      displayStatus = rawStatus.isEmpty ? 'PENDING' : rawStatus;
    }
    final payslipId = row['_payslip_id'] as String?;
    final subtle = Theme.of(context).colorScheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _title(),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Created: ${_created()}',
                      style: TextStyle(fontSize: 12, color: subtle),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    amountText,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  StatusChip(
                    label: displayStatus,
                    tone: toneForStatus(displayStatus),
                  ),
                ],
              ),
            ],
          ),
          if (settled && settledAtIso != null) ...[
            const SizedBox(height: 8),
            Text(
              '${isCashAdvance ? 'Deducted' : 'Paid'} on ${_fmtDate(settledAtIso)}',
              style: TextStyle(fontSize: 12, color: subtle),
            ),
          ],
          if (payslipId != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => context.push('/payslips/$payslipId'),
                icon: const Icon(Icons.receipt_long, size: 14),
                label: const Text('View payslip'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(40, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
```

- [ ] **Step 3: Static analysis**

Run: `flutter analyze lib/features/employees/profile/tabs/financials_tab.dart`
Expected: `No issues found!`

- [ ] **Step 4: Manual smoke test**

Open an employee with a mix of cash advance states (PENDING + DEDUCTED) and reimbursement states (PENDING + PAID).

- PENDING rows show the `PENDING` chip + amount, no "View payslip".
- DEDUCTED CA rows show a green `DEDUCTED` chip, "Deducted on {date}", and a "View payslip" button that navigates to `/payslips/:id`.
- PAID reimbursement rows show a green `PAID` chip, "Paid on {date}", and the same "View payslip" button.
- Clicking "View payslip" opens the preview screen for the correct payslip.

- [ ] **Step 5: Commit**

```bash
git add lib/features/employees/profile/tabs/financials_tab.dart
git commit -m "feat(employee): rich CA/reimbursement card with deduction tracking + payslip link"
```

---

## Task 12: Final verification

**Files:** none modified

- [ ] **Step 1: Full static analysis**

Run: `flutter analyze`
Expected: `No issues found!` — the project-wide run catches any Riverpod/import drift that per-file runs missed.

- [ ] **Step 2: Full engine test suite (regression check)**

Run: `flutter test test/engine/`
Expected: all tests pass. None of the touched files alter payroll math, so this is a safety net for accidental cascades.

- [ ] **Step 3: End-to-end manual run**

1. Trigger `Sync from Lark` (or mock rows) so the employee has at least one pending cash advance and one pending reimbursement.
2. Open the Financials tab → cards show PENDING.
3. Start a payroll run that covers the pay period.
4. Open a draft payslip → Earnings card shows the reimbursement with a Skip button; Deductions card shows the CA with a Skip button.
5. Skip the reimbursement → Recompute → payslip_lines rebuild → reimbursement line is gone from this payslip.
6. Undo by pulling `skipped_payroll_run_ids` back to empty (SQL) and recompute — line reappears. (Skip an advance and repeat the same check.)
7. Release the run. Financials tab CA card now shows `DEDUCTED`, "Deducted on {date}", and "View payslip" — clicking navigates to the correct payslip. Reimbursement card shows `PAID` with the same behaviour.
8. Verify penalty Skip still works (regression).

- [ ] **Step 4: Confirm no stray diffs**

Run: `git status`
Expected: clean working tree; all changes committed across Tasks 1–11.

---

## Rollback notes

- Task 3 (migration) is additive only; removing the columns takes a follow-up migration but no existing data migrates.
- Tasks 5/6 (repo methods) are new surface; nothing previously called them.
- Task 10 (provider enrichment) silently degrades if `_payslip_id` isn't populated — the card just hides the "View payslip" link. Safe to revert in isolation.
- Tasks 8/9 Skip actions are gated by `runStatus == 'REVIEW'` — they cannot fire on released runs.
