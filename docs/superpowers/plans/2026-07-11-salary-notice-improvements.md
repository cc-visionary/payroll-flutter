# Salary-Adjustment Notice Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Daily-rate salary notices state an "estimated at 26 working days per month" clause, and the notice's signatory role becomes editable with a block on the employee signing their own notice.

**Architecture:** Both are changes to `SalaryAdjustmentTemplate` and its form. Two new serialized `SalaryAdjustmentInputs` fields (`workDaysPerMonth` default 26, `signatoryRole` default 'HR Manager') both default to today's behaviour, so old saved documents re-render identically. `build()` gains a DAILY-only estimate clause and uses `signatoryRole` in place of two hardcoded `'HR Manager'` literals; `validate` blocks self-approval.

**Tech Stack:** Flutter, Dart `decimal`, `flutter_test`, `intl`.

## Global Constraints

- Package import prefix for tests is `package:payroll_flutter/…`; `lib/` files use **relative** imports. Run tests with `flutter test <path>`.
- Repo gates on `flutter analyze` (**0 errors**); ~189 pre-existing info/warning lints (baseline: 0 errors, 20 warnings, 169 infos) — **add zero new ones**. Do NOT run `dart format`; match each file's surrounding style.
- Money is `Decimal` (`package:decimal/decimal.dart`), never `double`. Currency renders via `NumberFormat.currency(symbol: '₱', decimalDigits: 2)` (already in `build()`).
- The daily estimate figure is **26** — payroll's flat `standardWorkDaysPerMonth` (`compute_service.dart:701,752`). Do NOT derive it from the scorecard's free-text `work_days_per_week`.
- New fields default to `workDaysPerMonth = 26` and `signatoryRole = 'HR Manager'`; `fromJson` supplies those defaults when the keys are absent (backward-compat for saved documents).
- Only `SalaryAdjustmentTemplate` + its form/validate/inputs change. No migration. No other templates.
- Verified block shapes: `LetterParty { final String name; final String? subtitle; }`; `LetterMetaBlock` has `final LetterParty from`; `SignatoryParty { final String name; final String role; }`; `MultiSignatureBlock(this.signatories)` where `signatories` is `List<SignatoryParty>`.
- Multiple Claude sessions share this working dir — implement on an isolated git worktree/branch.

---

### Task 1: Add `workDaysPerMonth` + `signatoryRole` to `SalaryAdjustmentInputs`

**Files:**
- Modify: `lib/features/documents/templates/salary_adjustment_inputs.dart`
- Test: `test/features/documents/templates/salary_adjustment_from_json_test.dart` (existing round-trip test file)

**Interfaces:**
- Produces: `SalaryAdjustmentInputs` gains `final int workDaysPerMonth` (default `26`) and `final String signatoryRole` (default `'HR Manager'`), threaded through the constructor, `fromJson`, `toJson`, and `copyWith`. Tasks 2–5 consume these.

- [ ] **Step 1: Write the failing test**

Open `test/features/documents/templates/salary_adjustment_from_json_test.dart` and confirm its style (it round-trips `toJson`/`fromJson`). Append:

```dart
  test('workDaysPerMonth + signatoryRole round-trip through toJson/fromJson', () {
    final original = SalaryAdjustmentInputs(
      employeeId: 'E1',
      employeeFullName: 'Jane Cruz',
      companyId: 'CO1',
      companyName: 'Luxium',
      hrManagerName: 'Alex Reyes',
      signatoryRole: 'Chief Operating Officer',
      workDaysPerMonth: 22,
      effectiveDate: DateTime(2026, 8, 1),
      issueDate: DateTime(2026, 7, 11),
    );
    final round = SalaryAdjustmentInputs.fromJson(original.toJson());
    expect(round.workDaysPerMonth, 22);
    expect(round.signatoryRole, 'Chief Operating Officer');
  });

  test('a saved document without the new keys defaults to 26 / HR Manager', () {
    // Simulate an OLD saved document's generation_options (keys absent).
    final legacy = <String, dynamic>{
      'type': 'salaryAdjustment',
      'employeeId': 'E1',
      'employeeFullName': 'Jane Cruz',
      'companyId': 'CO1',
      'companyName': 'Luxium',
      'hrManagerName': 'Alex Reyes',
      'oldSalary': '30000',
      'newSalary': '32000',
      'salaryPeriod': 'MONTHLY',
      'effectiveDate': '2026-08-01T00:00:00.000',
      'issueDate': '2026-07-11T00:00:00.000',
      'reason': '',
    };
    final inputs = SalaryAdjustmentInputs.fromJson(legacy);
    expect(inputs.workDaysPerMonth, 26);
    expect(inputs.signatoryRole, 'HR Manager');
  });
```

> If `salary_adjustment_from_json_test.dart` does not exist, create it with the two imports the sibling tests use (`package:decimal/decimal.dart`, `package:flutter_test/flutter_test.dart`, `package:payroll_flutter/features/documents/templates/salary_adjustment_inputs.dart`) and a `void main()` wrapping the two tests above.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/documents/templates/salary_adjustment_from_json_test.dart`
Expected: FAIL — `No named parameter with the name 'signatoryRole'` (and `workDaysPerMonth`).

- [ ] **Step 3: Add the fields**

In `lib/features/documents/templates/salary_adjustment_inputs.dart`, make five additions, each placed immediately after the existing `hrManagerName` line in its section.

(a) Field declaration — after `final String hrManagerName;` (`:33`):

```dart
  /// Working days per month used to estimate monthly pay on DAILY-rate notices.
  /// Defaults to 26 — payroll's `standardWorkDaysPerMonth` (compute_service).
  final int workDaysPerMonth;

  /// The signatory's title on the notice (the "From:" subtitle + signature
  /// line). `hrManagerName` above holds the signatory's NAME, which may be a
  /// COO/GM/etc. when the HR Manager is the one being adjusted.
  final String signatoryRole;
```

(b) Constructor — after `this.hrManagerName = '',` (`:58`):

```dart
    this.workDaysPerMonth = 26,
    this.signatoryRole = 'HR Manager',
```

(c) `fromJson` — after `hrManagerName: json['hrManagerName'] as String? ?? '',` (`:100`):

```dart
      workDaysPerMonth: (json['workDaysPerMonth'] as num?)?.toInt() ?? 26,
      signatoryRole: json['signatoryRole'] as String? ?? 'HR Manager',
```

(d) `copyWith` — add params after `String? hrManagerName,` (`:123`):

```dart
    int? workDaysPerMonth,
    String? signatoryRole,
```

and assignments after `hrManagerName: hrManagerName ?? this.hrManagerName,` (`:144`):

```dart
    workDaysPerMonth: workDaysPerMonth ?? this.workDaysPerMonth,
    signatoryRole: signatoryRole ?? this.signatoryRole,
```

(e) `toJson` — after `'hrManagerName': hrManagerName,` (`:179`):

```dart
    'workDaysPerMonth': workDaysPerMonth,
    'signatoryRole': signatoryRole,
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/documents/templates/salary_adjustment_from_json_test.dart`
Expected: PASS.

- [ ] **Step 5: Verify analyze + commit**

Run: `flutter analyze lib/features/documents/templates/salary_adjustment_inputs.dart`
Expected: `No issues found!`

```bash
git add lib/features/documents/templates/salary_adjustment_inputs.dart test/features/documents/templates/salary_adjustment_from_json_test.dart
git commit -m "feat(docs): salary-adjustment inputs carry workDaysPerMonth + signatoryRole"
```

---

### Task 2: Daily-rate "estimated at 26 working days per month" clause

**Files:**
- Modify: `lib/features/documents/templates/salary_adjustment_template.dart` (autofill default + `build()`)
- Test: `test/features/documents/salary_adjustment_body_test.dart`

**Interfaces:**
- Consumes: `SalaryAdjustmentInputs.workDaysPerMonth` (Task 1).
- Produces: a top-level `const kStandardWorkDaysPerMonth = 26;`. `build()` appends `(estimated at N working days per month)` to the pay clause of every mode when `salaryPeriod == 'DAILY'`.

- [ ] **Step 1: Write the failing test**

Append to `test/features/documents/salary_adjustment_body_test.dart` (it already has `_i(type)` fixtures and `_body(blocks)` helpers; the fixtures build MONTHLY inputs by default — add a `salaryPeriod`-aware fixture or set the field directly):

```dart
  test('DAILY salary adjustment states the monthly-estimate clause', () {
    final blocks = t.build(_i(SalaryAdjustmentType.salaryAdjustment)
        .copyWith(salaryPeriod: 'DAILY'));
    expect(_body(blocks), contains('estimated at 26 working days per month'));
  });

  test('MONTHLY salary adjustment has NO estimate clause', () {
    final blocks = t.build(_i(SalaryAdjustmentType.salaryAdjustment)
        .copyWith(salaryPeriod: 'MONTHLY'));
    expect(_body(blocks), isNot(contains('working days per month')));
  });

  test('the clause also appears for a DAILY lateral transfer', () {
    final blocks =
        t.build(_i(SalaryAdjustmentType.lateral).copyWith(salaryPeriod: 'DAILY'));
    expect(_body(blocks), contains('estimated at 26 working days per month'));
  });
```

> If the file's `_i(...)` fixture doesn't expose `copyWith` on the returned inputs, use the real fixture-construction path it already uses and set `salaryPeriod: 'DAILY'` / `workDaysPerMonth: 26` at construction. Confirm the `_body` helper concatenates `ParagraphBlock.text` — the earlier tests in this file already do this.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/documents/salary_adjustment_body_test.dart`
Expected: FAIL — the DAILY assertions don't find the clause.

- [ ] **Step 3: Add the constant + estimate clause**

In `lib/features/documents/templates/salary_adjustment_template.dart`, add near the top (top-level, after the imports):

```dart
/// Working days per month used to estimate monthly pay on DAILY-rate notices.
/// Mirrors payroll's `standardWorkDaysPerMonth` (compute_service.dart).
const kStandardWorkDaysPerMonth = 26;
```

In `build()`, right after `periodLabel` is computed, add a reusable clause string:

```dart
    // On DAILY notices, help the employee estimate monthly pay. 26 is the
    // divisor payroll actually uses, so the figure reconciles with the payslip.
    final estimateClause = i.salaryPeriod == 'DAILY'
        ? ' (estimated at ${i.workDaysPerMonth} working days per month)'
        : '';
```

Then, in each `bodyText` switch arm, insert `$estimateClause` immediately after the new-salary (or, for lateral, the unchanged-salary) currency value and before the trailing `. ${i.reason}`. Concretely:

- `promotion` / `demotion` / `salaryAdjustment`: change `…to ${cf.format(i.newSalary.toDouble())}. ${i.reason}` to `…to ${cf.format(i.newSalary.toDouble())}$estimateClause. ${i.reason}`.
- `lateral`: change `…remains unchanged at ${cf.format(i.oldSalary.toDouble())}. ${i.reason}` to `…remains unchanged at ${cf.format(i.oldSalary.toDouble())}$estimateClause. ${i.reason}`.

- [ ] **Step 4: Default it in autofill**

In the `autofill(...)` return's `SalaryAdjustmentInputs(...)`, add `workDaysPerMonth: kStandardWorkDaysPerMonth,` alongside the other fields (near `salaryPeriod:`). This makes freshly-generated notices carry 26 explicitly. (When `salaryPeriod` resolves to `'DAILY'` from the scorecard/change, the clause appears automatically.)

- [ ] **Step 5: Run test + the full documents suite**

Run: `flutter test test/features/documents/salary_adjustment_body_test.dart`
Expected: PASS.

Run: `flutter test test/features/documents/`
Expected: all PASS. If a golden test fails, inspect WHY: only a golden whose fixture `salaryPeriod` is `'DAILY'` should change (its body now carries the clause — an intended change; regenerate that golden per the repo's golden-update command and eyeball the diff). A MONTHLY golden must NOT change; if one does, the clause leaked into MONTHLY — fix the `salaryPeriod == 'DAILY'` guard, don't regenerate.

- [ ] **Step 6: Verify analyze + commit**

Run: `flutter analyze lib/features/documents/templates/salary_adjustment_template.dart`
Expected: `No issues found!`

```bash
git add lib/features/documents/templates/salary_adjustment_template.dart test/features/documents/salary_adjustment_body_test.dart
git commit -m "feat(docs): DAILY salary notices estimate monthly working days"
```

---

### Task 3: Signatory role flows through `build()`

**Files:**
- Modify: `lib/features/documents/templates/salary_adjustment_template.dart` (autofill default + `build()` signatory sites)
- Test: `test/features/documents/salary_adjustment_body_test.dart`

**Interfaces:**
- Consumes: `SalaryAdjustmentInputs.signatoryRole` (Task 1).
- Produces: `build()`'s "From:" subtitle and the signatory `SignatoryParty.role` both read `i.signatoryRole`; the employee acknowledgement party is unchanged.

- [ ] **Step 1: Write the failing test**

Append to `test/features/documents/salary_adjustment_body_test.dart`:

```dart
  test('signatory role + name flow into the From line and the signature', () {
    final blocks = t.build(_i(SalaryAdjustmentType.salaryAdjustment).copyWith(
      hrManagerName: 'Jane Cruz',
      signatoryRole: 'Chief Operating Officer',
    ));

    final meta = blocks.whereType<LetterMetaBlock>().first;
    expect(meta.from.name, 'Jane Cruz');
    expect(meta.from.subtitle, 'Chief Operating Officer');

    final sig = blocks.whereType<MultiSignatureBlock>().first.signatories;
    // First signatory is the approver; second is the employee acknowledgement.
    expect(sig.first.name, 'Jane Cruz');
    expect(sig.first.role, 'Chief Operating Officer');
    expect(sig.last.role, 'Employee (Acknowledged)');
  });
```

Add the import `import 'package:payroll_flutter/features/documents/blocks/multi_signature_block.dart';` at the top of the test file if not already present (`letter_meta_block.dart` is imported by the existing subject test).

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/documents/salary_adjustment_body_test.dart`
Expected: FAIL — the signature role is `'HR Manager'`, not `'Chief Operating Officer'`.

- [ ] **Step 3: Use `signatoryRole` in the two signatory sites**

In `build()`, change the `LetterMetaBlock`'s `from:`:

```dart
        from: LetterParty(name: i.hrManagerName, subtitle: i.signatoryRole),
```

and the signatory entry in the `MultiSignatureBlock` list (the FIRST `SignatoryParty`, the approver — NOT the employee one):

```dart
        SignatoryParty(name: i.hrManagerName, role: i.signatoryRole),
```

Leave the employee's `SignatoryParty(name: i.employeeFullName, role: 'Employee (Acknowledged)')` exactly as it is.

- [ ] **Step 4: Default it in autofill**

In the `autofill(...)` return's `SalaryAdjustmentInputs(...)`, add `signatoryRole: 'HR Manager',` near `hrManagerName:`. (This preserves the default, and the form lets the user override it.)

- [ ] **Step 5: Run test + full documents suite**

Run: `flutter test test/features/documents/salary_adjustment_body_test.dart && flutter test test/features/documents/`
Expected: all PASS. Existing goldens are unaffected because the default `signatoryRole` is `'HR Manager'` — byte-identical to the old hardcoded literal.

- [ ] **Step 6: Verify analyze + commit**

Run: `flutter analyze lib/features/documents/templates/salary_adjustment_template.dart`
Expected: `No issues found!`

```bash
git add lib/features/documents/templates/salary_adjustment_template.dart test/features/documents/salary_adjustment_body_test.dart
git commit -m "feat(docs): salary notice signatory role is editable"
```

---

### Task 4: Validation — block self-approval, require signatory role

**Files:**
- Modify: `lib/features/documents/templates/salary_adjustment_validate.dart`
- Test: `test/features/documents/templates/salary_adjustment_validate_test.dart`

**Interfaces:**
- Consumes: `SalaryAdjustmentInputs.signatoryRole`, `hrManagerName`, `employeeFullName` (Task 1 / existing).
- Produces: `validateSalaryAdjustment` adds a `'hrManager'` error when the signatory name equals the employee name (trimmed, case-insensitive), and a `'signatoryRole'` error when the role is blank.

- [ ] **Step 1: Write the failing test**

Append inside `test/features/documents/templates/salary_adjustment_validate_test.dart` (it has a `_base()` helper + `copyWith`; match its style):

```dart
  test('blocks the employee signing their own notice (case/space-insensitive)', () {
    final i = _base().copyWith(
      employeeFullName: 'Jane Cruz',
      hrManagerName: '  jane   cruz ',
    );
    expect(
      validateSalaryAdjustment(i).map((e) => e.field),
      contains('hrManager'),
    );
  });

  test('a different signatory name has no self-approval error', () {
    final i = _base().copyWith(
      employeeFullName: 'Jane Cruz',
      hrManagerName: 'Alex Reyes',
    );
    expect(
      validateSalaryAdjustment(i).where((e) =>
          e.field == 'hrManager' && e.message.contains('cannot be the employee')),
      isEmpty,
    );
  });

  test('a blank signatory role is rejected', () {
    final i = _base().copyWith(signatoryRole: '   ');
    expect(
      validateSalaryAdjustment(i).map((e) => e.field),
      contains('signatoryRole'),
    );
  });
```

> Confirm `_base()` sets a non-empty `hrManagerName` and a `signatoryRole` (it defaults to `'HR Manager'` via the model). The self-approval test deliberately sets `hrManagerName` to a spaced/lowercased version of the employee name so a naive `==` would miss it — the implementation must normalise both sides.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/documents/templates/salary_adjustment_validate_test.dart`
Expected: FAIL — no `'hrManager'` self-approval error and no `'signatoryRole'` error yet.

- [ ] **Step 3: Add the two checks**

In `lib/features/documents/templates/salary_adjustment_validate.dart`, after the existing `hrManagerName` "required" check, add:

```dart
  if (i.signatoryRole.trim().isEmpty) {
    errors.add(
      const ValidationError('signatoryRole', 'Signatory title is required'),
    );
  }
  final sigName = i.hrManagerName.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  final empName = i.employeeFullName.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  if (sigName.isNotEmpty && sigName == empName) {
    errors.add(const ValidationError(
      'hrManager',
      'The signatory cannot be the employee being adjusted — choose another approver.',
    ));
  }
```

- [ ] **Step 4: Run test + the full documents suite**

Run: `flutter test test/features/documents/templates/salary_adjustment_validate_test.dart && flutter test test/features/documents/`
Expected: all PASS. Existing validate cases are unaffected (their `_base()` signatory name differs from the employee name and `signatoryRole` is non-empty).

- [ ] **Step 5: Verify analyze + commit**

Run: `flutter analyze lib/features/documents/templates/salary_adjustment_validate.dart`
Expected: `No issues found!`

```bash
git add lib/features/documents/templates/salary_adjustment_validate.dart test/features/documents/templates/salary_adjustment_validate_test.dart
git commit -m "feat(docs): block self-approval; require a signatory title"
```

---

### Task 5: Form — signatory name relabel + signatory role field

**Files:**
- Modify: `lib/features/documents/forms/salary_adjustment_form.dart`

**Interfaces:**
- Consumes: `SalaryAdjustmentInputs.signatoryRole`, `copyWith` (Task 1); `validateSalaryAdjustment` error fields `'hrManager'` / `'signatoryRole'` (Task 4).

- [ ] **Step 1: Relabel the signatory name field**

The form has a field bound to `hrManagerName` (`salary_adjustment_form.dart:141`: `value: _i.hrManagerName, onChanged: (v) => _set(_i.copyWith(hrManagerName: v))`, with `_error('hrManager')` below at `:144`). Change its label text from the current "HR manager name"-style label to **`Signatory name`**. Keep the `_error('hrManager')` line — it now also surfaces the self-approval error.

- [ ] **Step 2: Add the signatory role field**

Immediately after the signatory-name field's `_error('hrManager')`, add a role field mirroring the same widget pattern the file uses for text inputs (match the exact widget/label style already present — look at how the name field is built):

```dart
          // Signatory title — defaults to "HR Manager"; change it when someone
          // other than HR signs (e.g. the HR Manager is the one being adjusted).
          <same text-field widget as the name field above>(
            label: 'Signatory title',
            value: _i.signatoryRole,
            onChanged: (v) => _set(_i.copyWith(signatoryRole: v)),
          ),
          _error('signatoryRole'),
```

Use the real field-builder the form already uses (the name field at `:141` shows its exact constructor/props — copy that shape, only changing label/value/onChanged). Do not invent a new widget.

- [ ] **Step 3: Verify analyze + the documents suite**

Run: `flutter analyze lib/features/documents/forms/salary_adjustment_form.dart`
Expected: `No issues found!`

Run: `flutter test test/features/documents/`
Expected: all PASS (no behavioural test change here; this is form wiring).

- [ ] **Step 4: Commit**

```bash
git add lib/features/documents/forms/salary_adjustment_form.dart
git commit -m "feat(docs): editable signatory name + title on the salary notice form"
```

---

### Task 6: Full verification

**Files:** none (verification only).

- [ ] **Step 1: Whole suite + analyze**

Run: `flutter analyze`
Expected: **0 errors**; the info/warning counts must not exceed baseline (169 infos, 20 warnings). Report the severity breakdown.

Run: `flutter test`
Expected: all pass, 0 failures. Baseline before this plan is 646 passed / 1 skipped; this plan adds ~8 tests.

- [ ] **Step 2: Drive the flow (use the `run` skill)**

Launch: `flutter run -d linux --dart-define-from-file=env/prod.json`

1. Generate a **Salary Adjustment** for a DAILY-rate employee → the letter body reads "…(estimated at 26 working days per month)".
2. Generate one for a MONTHLY employee → no such clause.
3. On the form, change **Signatory title** to e.g. "Chief Operating Officer" and the **Signatory name** to a different person → the "From:" line and signature block reflect both.
4. Set the **Signatory name** equal to the employee's name → the form shows the self-approval error and blocks generation.

- [ ] **Step 3: Commit any tidy-ups**

```bash
git add -A
git commit -m "chore(docs): verification pass for salary-notice improvements"
```

---

## Self-Review

**Spec coverage:**
- A. Daily estimate clause (26, all modes, serialized field) → Tasks 1, 2.
- B. Editable signatory role in `build()` → Tasks 1, 3.
- B. Self-approval block + signatory-role-required validation → Task 4.
- B. Form relabel + role field → Task 5.
- Back-compat defaults (26 / 'HR Manager') + goldens → Task 1 (defaults), Tasks 2/3 (golden note).
- Testing + verification → Tasks 1–4 (unit), Task 6 (suite + smoke).
- Out-of-scope items (other templates, per-employee days data, auto-picking an approver) are untouched.

**Placeholder scan:** No TBD/TODO. Task 5's field-widget is given as "copy the exact shape of the name field at `:141`" rather than final Dart, because the form's field-builder is a local widget the implementer will have open; the label/value/onChanged it needs are all stated. Two steps call out "confirm the fixture/helper shape in the file" (Task 2 `_i` copyWith, Task 4 `_base`) — those depend on code the implementer opens, and both name the exact assertion to keep.

**Type consistency:** `workDaysPerMonth` (int) and `signatoryRole` (String) are defined in Task 1 and consumed identically in Tasks 2–5. `kStandardWorkDaysPerMonth` is defined and used in Task 2. Validation field codes `'hrManager'` (existing) and `'signatoryRole'` (new, Task 4) match the form's `_error(...)` calls in Task 5. Block field names (`LetterMetaBlock.from`, `LetterParty.subtitle`, `MultiSignatureBlock.signatories`, `SignatoryParty.role/name`) match the verified shapes in Global Constraints.

**Ordering:** Task 1 (fields) precedes everything. Tasks 2 and 3 both edit `build()`/`autofill` in the same file — sequential, not parallel. Task 5 depends on Tasks 1 and 4. Do not reorder.
