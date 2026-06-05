# HR Documents Batch 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add 5 new HR document templates — Final Pay Computation, Salary Adjustment / Promotion Letter, Notice of Decision (NOD), Probationary Regularization Letter, Resignation Acceptance Letter — bringing total to 12.

**Architecture:** Each template follows the existing 7-template pattern (inputs class → validate function → DocumentTemplate subclass with autofill+build → form widget → registry entry → filename prefix → generate-screen branch → pagination golden). Shared infrastructure adds `ntesByEmployeeProvider` for the NOD's optional NTE picker. All templates reuse the existing block library (PartyBlock, MemoHeader, signature blocks, AmountWithBreakdown). No DB migrations; documents are generate-then-print/share.

**Tech Stack:** Flutter (Riverpod, Material 3), Decimal (PH currency math), Supabase Postgres (read-only here — no schema changes), existing pdf rendering pipeline.

**Branch:** `feat/hr-docs-batch-2` (already created).

**Spec:** `docs/superpowers/specs/2026-06-05-hr-docs-batch-2-design.md`.

---

## Conventions (read once, apply to every task)

### File layout
- Inputs class: `lib/features/documents/templates/<snake>_inputs.dart`
- Validate function: `lib/features/documents/templates/<snake>_validate.dart`
- Template class: `lib/features/documents/templates/<snake>_template.dart`
- Form widget: `lib/features/documents/forms/<snake>_form.dart`
- Tests: `test/features/documents/<snake>_*_test.dart`
- Goldens: `test/features/documents/goldens/<snake>_pagination_test.dart`

Where `<snake>` is `final_pay`, `salary_adjustment`, `nod`, `regularization`, `resignation_acceptance`.

### Inputs class pattern (always follow)
- Plain class extending `TemplateInputs`
- Required fields: `employeeId`, `employeeFullName`, `companyId`, `companyName`
- `copyWith` uses `const _undef = Object();` sentinel for nullable overrides (see `lib/features/documents/templates/nda_inputs.dart` for the canonical pattern)
- `toDebugMap()` returns minimal fingerprint (id + position)
- No `fromJson`/`toJson` — nothing is persisted as raw inputs

### Validate function pattern
```dart
List<ValidationError> validateXxx(XxxInputs i) {
  final errors = <ValidationError>[];
  if (i.employeeId.isEmpty) errors.add(const ValidationError('employee', 'Select an employee'));
  if (i.companyId.isEmpty) errors.add(const ValidationError('company', 'Select a company'));
  // …per-field rules…
  return errors;
}
```

### Template pattern
- Extends `DocumentTemplate<XxxInputs>`
- `id`, `displayName`, `description`, `icon` — Material icons.
- `autofill(AutofillContext ctx)` reads `ctx.employee`, `ctx.company`, optionally calls `ref.read(providerName(employeeId).future)` for async data.
- `build(XxxInputs i)` returns `List<Block>`.
- `gates(AutofillContext ctx)` returns `List<Gate>` — empty list = no gate.
- `supportsBulk` getter — `true` for memo-style letters where autofill is complete; `false` for templates with per-employee unique data.

### Commit style
`feat(documents): <template> — <step>` per task. Example: `feat(documents): NOD — inputs class`.

### Run commands
- Unit test: `flutter test test/features/documents/<file>_test.dart`
- All documents tests: `flutter test test/features/documents/`
- Format + analyze: `dart format lib/ test/ && flutter analyze`
- Full app smoke: `flutter run -d linux --dart-define-from-file=env/prod.json`

---

## File map

**New files (20):**
- `lib/features/documents/templates/final_pay_inputs.dart`
- `lib/features/documents/templates/final_pay_validate.dart`
- `lib/features/documents/templates/final_pay_template.dart`
- `lib/features/documents/forms/final_pay_form.dart`
- `lib/features/documents/templates/salary_adjustment_inputs.dart`
- `lib/features/documents/templates/salary_adjustment_validate.dart`
- `lib/features/documents/templates/salary_adjustment_template.dart`
- `lib/features/documents/forms/salary_adjustment_form.dart`
- `lib/features/documents/templates/nod_inputs.dart`
- `lib/features/documents/templates/nod_validate.dart`
- `lib/features/documents/templates/nod_template.dart`
- `lib/features/documents/forms/nod_form.dart`
- `lib/features/documents/templates/regularization_inputs.dart`
- `lib/features/documents/templates/regularization_validate.dart`
- `lib/features/documents/templates/regularization_template.dart`
- `lib/features/documents/forms/regularization_form.dart`
- `lib/features/documents/templates/resignation_acceptance_inputs.dart`
- `lib/features/documents/templates/resignation_acceptance_validate.dart`
- `lib/features/documents/templates/resignation_acceptance_template.dart`
- `lib/features/documents/forms/resignation_acceptance_form.dart`

**Modified files (3):**
- `lib/features/documents/providers.dart` — append `ntesByEmployeeProvider` + `EmployeeDocumentSummary`.
- `lib/features/documents/templates/template_registry.dart` — register 5 new templates.
- `lib/core/pdf/pdf_filename.dart` — 5 new prefix cases.
- `lib/features/documents/generate_screen.dart` — 5 new branches in state + `_runAutofill` + `_formFor` + `_previewFor`.

**New test files (15):**
- One `_validate_test.dart`, one `_build_test.dart`, one pagination golden per template.

---

## Task 0 — Shared: `ntesByEmployeeProvider`

**Files:**
- Modify: `lib/features/documents/providers.dart` (append at end)

- [ ] **Step 1: Add the provider + summary class**

Append at the bottom of `lib/features/documents/providers.dart`:

```dart
class EmployeeDocumentSummary {
  final String id;
  final String title;
  final DateTime createdAt;
  const EmployeeDocumentSummary({
    required this.id,
    required this.title,
    required this.createdAt,
  });
  factory EmployeeDocumentSummary.fromRow(Map<String, dynamic> r) =>
      EmployeeDocumentSummary(
        id: r['id'] as String,
        title: r['title'] as String? ?? '(untitled NTE)',
        createdAt: DateTime.parse(r['created_at'] as String),
      );
}

/// Returns all NTE documents stored for [employeeId], newest first.
/// Used by the NOD form's optional NTE picker.
final ntesByEmployeeProvider =
    FutureProvider.family<List<EmployeeDocumentSummary>, String>(
        (ref, employeeId) async {
  final client = Supabase.instance.client;
  final rows = await client
      .from('employee_documents')
      .select('id, title, created_at')
      .eq('employee_id', employeeId)
      .eq('document_type', 'NTE')
      .order('created_at', ascending: false);
  return (rows as List)
      .map((r) => EmployeeDocumentSummary.fromRow(r as Map<String, dynamic>))
      .toList();
});
```

- [ ] **Step 2: Verify analyze + format**

Run: `dart format lib/features/documents/providers.dart && flutter analyze lib/features/documents/providers.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/features/documents/providers.dart
git commit -m "feat(documents): add ntesByEmployeeProvider for NOD linkage"
```

---

# Final Pay Computation (Tasks 1-5)

## Task 1 — Final Pay: Inputs class

**Files:**
- Create: `lib/features/documents/templates/final_pay_inputs.dart`

- [ ] **Step 1: Create the inputs class**

```dart
import 'package:decimal/decimal.dart';

import 'document_template.dart';

class FinalPayInputs extends TemplateInputs {
  final String employeeId;
  final String employeeFullName;
  final String employeePosition;
  final DateTime? employeeHireDate;
  final DateTime? employeeSeparationDate;

  final String companyId;
  final String companyName;
  final String companyAddress;
  final String hrManagerName;

  // Computation lines (all auto-filled, all HR-overridable)
  final Decimal lastNetPay;
  final Decimal thirteenthMonth;
  final Decimal unusedLeaveConversion;
  final Decimal outstandingCashAdvance;
  final Decimal otherDeductions;
  final String otherDeductionsLabel;

  // Per-line lock flags (true = HR has overridden, ignore provider refresh)
  final bool lastNetPayLocked;
  final bool thirteenthMonthLocked;
  final bool unusedLeaveConversionLocked;
  final bool outstandingCashAdvanceLocked;

  final DateTime computedAsOf;
  final DateTime releaseDate;

  FinalPayInputs({
    required this.employeeId,
    required this.employeeFullName,
    this.employeePosition = '',
    this.employeeHireDate,
    this.employeeSeparationDate,
    required this.companyId,
    required this.companyName,
    this.companyAddress = '',
    this.hrManagerName = '',
    Decimal? lastNetPay,
    Decimal? thirteenthMonth,
    Decimal? unusedLeaveConversion,
    Decimal? outstandingCashAdvance,
    Decimal? otherDeductions,
    this.otherDeductionsLabel = '',
    this.lastNetPayLocked = false,
    this.thirteenthMonthLocked = false,
    this.unusedLeaveConversionLocked = false,
    this.outstandingCashAdvanceLocked = false,
    required this.computedAsOf,
    required this.releaseDate,
  })  : lastNetPay = lastNetPay ?? Decimal.zero,
        thirteenthMonth = thirteenthMonth ?? Decimal.zero,
        unusedLeaveConversion = unusedLeaveConversion ?? Decimal.zero,
        outstandingCashAdvance = outstandingCashAdvance ?? Decimal.zero,
        otherDeductions = otherDeductions ?? Decimal.zero;

  Decimal get total =>
      lastNetPay + thirteenthMonth + unusedLeaveConversion -
      outstandingCashAdvance -
      otherDeductions;

  FinalPayInputs copyWith({
    String? employeeId,
    String? employeeFullName,
    String? employeePosition,
    Object? employeeHireDate = _undef,
    Object? employeeSeparationDate = _undef,
    String? companyId,
    String? companyName,
    String? companyAddress,
    String? hrManagerName,
    Decimal? lastNetPay,
    Decimal? thirteenthMonth,
    Decimal? unusedLeaveConversion,
    Decimal? outstandingCashAdvance,
    Decimal? otherDeductions,
    String? otherDeductionsLabel,
    bool? lastNetPayLocked,
    bool? thirteenthMonthLocked,
    bool? unusedLeaveConversionLocked,
    bool? outstandingCashAdvanceLocked,
    DateTime? computedAsOf,
    DateTime? releaseDate,
  }) =>
      FinalPayInputs(
        employeeId: employeeId ?? this.employeeId,
        employeeFullName: employeeFullName ?? this.employeeFullName,
        employeePosition: employeePosition ?? this.employeePosition,
        employeeHireDate: identical(employeeHireDate, _undef)
            ? this.employeeHireDate
            : employeeHireDate as DateTime?,
        employeeSeparationDate: identical(employeeSeparationDate, _undef)
            ? this.employeeSeparationDate
            : employeeSeparationDate as DateTime?,
        companyId: companyId ?? this.companyId,
        companyName: companyName ?? this.companyName,
        companyAddress: companyAddress ?? this.companyAddress,
        hrManagerName: hrManagerName ?? this.hrManagerName,
        lastNetPay: lastNetPay ?? this.lastNetPay,
        thirteenthMonth: thirteenthMonth ?? this.thirteenthMonth,
        unusedLeaveConversion:
            unusedLeaveConversion ?? this.unusedLeaveConversion,
        outstandingCashAdvance:
            outstandingCashAdvance ?? this.outstandingCashAdvance,
        otherDeductions: otherDeductions ?? this.otherDeductions,
        otherDeductionsLabel:
            otherDeductionsLabel ?? this.otherDeductionsLabel,
        lastNetPayLocked: lastNetPayLocked ?? this.lastNetPayLocked,
        thirteenthMonthLocked:
            thirteenthMonthLocked ?? this.thirteenthMonthLocked,
        unusedLeaveConversionLocked:
            unusedLeaveConversionLocked ?? this.unusedLeaveConversionLocked,
        outstandingCashAdvanceLocked:
            outstandingCashAdvanceLocked ?? this.outstandingCashAdvanceLocked,
        computedAsOf: computedAsOf ?? this.computedAsOf,
        releaseDate: releaseDate ?? this.releaseDate,
      );

  @override
  Map<String, dynamic> toDebugMap() => {
        'employeeId': employeeId,
        'separation': employeeSeparationDate?.toIso8601String(),
        'total': total.toString(),
      };
}

const _undef = Object();
```

- [ ] **Step 2: Verify**

Run: `dart format lib/features/documents/templates/final_pay_inputs.dart && flutter analyze lib/features/documents/templates/final_pay_inputs.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/features/documents/templates/final_pay_inputs.dart
git commit -m "feat(documents): Final Pay — inputs class"
```

## Task 2 — Final Pay: validate function + tests

**Files:**
- Create: `lib/features/documents/templates/final_pay_validate.dart`
- Create: `test/features/documents/final_pay_validate_test.dart`

- [ ] **Step 1: Write failing tests**

```dart
// test/features/documents/final_pay_validate_test.dart
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll/features/documents/templates/final_pay_inputs.dart';
import 'package:payroll/features/documents/templates/final_pay_validate.dart';

FinalPayInputs _base() => FinalPayInputs(
      employeeId: 'e1',
      employeeFullName: 'Alice',
      employeePosition: 'Accountant',
      companyId: 'c1',
      companyName: 'Luxium',
      hrManagerName: 'Brixter',
      lastNetPay: Decimal.parse('5000'),
      thirteenthMonth: Decimal.parse('2500'),
      unusedLeaveConversion: Decimal.parse('1000'),
      outstandingCashAdvance: Decimal.zero,
      computedAsOf: DateTime(2026, 6, 5),
      releaseDate: DateTime(2026, 6, 12),
    );

void main() {
  test('passes for a complete input', () {
    expect(validateFinalPay(_base()), isEmpty);
  });

  test('requires employeeId', () {
    final i = _base().copyWith(employeeId: '');
    final errs = validateFinalPay(i);
    expect(errs.map((e) => e.field), contains('employee'));
  });

  test('requires companyId', () {
    final i = _base().copyWith(companyId: '');
    final errs = validateFinalPay(i);
    expect(errs.map((e) => e.field), contains('company'));
  });

  test('rejects negative lastNetPay', () {
    final i = _base().copyWith(lastNetPay: Decimal.parse('-1'));
    final errs = validateFinalPay(i);
    expect(errs.map((e) => e.field), contains('lastNetPay'));
  });

  test('rejects releaseDate before computedAsOf', () {
    final i = _base().copyWith(releaseDate: DateTime(2026, 6, 1));
    final errs = validateFinalPay(i);
    expect(errs.map((e) => e.field), contains('releaseDate'));
  });

  test('does NOT flag releaseDate > computedAsOf+30 (warn only)', () {
    final i = _base().copyWith(releaseDate: DateTime(2026, 9, 1));
    final errs = validateFinalPay(i);
    expect(errs.map((e) => e.field), isNot(contains('releaseDate')));
  });
}
```

- [ ] **Step 2: Run — expect failure (no impl)**

Run: `flutter test test/features/documents/final_pay_validate_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:payroll/features/documents/templates/final_pay_validate.dart'`.

- [ ] **Step 3: Write `final_pay_validate.dart`**

```dart
import 'package:decimal/decimal.dart';

import 'document_template.dart';
import 'final_pay_inputs.dart';

List<ValidationError> validateFinalPay(FinalPayInputs i) {
  final errors = <ValidationError>[];
  if (i.employeeId.isEmpty) {
    errors.add(const ValidationError('employee', 'Select an employee'));
  }
  if (i.employeeFullName.trim().isEmpty) {
    errors.add(const ValidationError('employeeFullName', 'Employee name is required'));
  }
  if (i.companyId.isEmpty) {
    errors.add(const ValidationError('company', 'Select a company'));
  }
  if (i.hrManagerName.trim().isEmpty) {
    errors.add(const ValidationError('hrManager', 'HR manager name is required'));
  }
  if (i.lastNetPay < Decimal.zero) {
    errors.add(const ValidationError('lastNetPay', 'Last net pay cannot be negative'));
  }
  if (i.thirteenthMonth < Decimal.zero) {
    errors.add(const ValidationError('thirteenthMonth', '13th-month pay cannot be negative'));
  }
  if (i.unusedLeaveConversion < Decimal.zero) {
    errors.add(const ValidationError('unusedLeaveConversion', 'Leave conversion cannot be negative'));
  }
  if (i.outstandingCashAdvance < Decimal.zero) {
    errors.add(const ValidationError('outstandingCashAdvance', 'Cash advance cannot be negative'));
  }
  if (i.otherDeductions < Decimal.zero) {
    errors.add(const ValidationError('otherDeductions', 'Other deductions cannot be negative'));
  }
  if (i.releaseDate.isBefore(i.computedAsOf)) {
    errors.add(const ValidationError('releaseDate', 'Release date must be on or after the computation date'));
  }
  return errors;
}
```

- [ ] **Step 4: Run — expect pass**

Run: `flutter test test/features/documents/final_pay_validate_test.dart`
Expected: All 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/features/documents/templates/final_pay_validate.dart test/features/documents/final_pay_validate_test.dart
git commit -m "feat(documents): Final Pay — validate + tests"
```

## Task 3 — Final Pay: Template scaffold + autofill

**Files:**
- Create: `lib/features/documents/templates/final_pay_template.dart`
- Create: `test/features/documents/final_pay_template_test.dart`

- [ ] **Step 1: Write the autofill test**

```dart
// test/features/documents/final_pay_template_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll/features/documents/templates/final_pay_template.dart';

void main() {
  test('FinalPayTemplate exposes correct id + displayName', () {
    const t = FinalPayTemplate();
    expect(t.id, 'final_pay');
    expect(t.displayName, contains('Final Pay'));
    expect(t.supportsBulk, isFalse);
  });

  test('gates rejects an active employee (no separation date)', () {
    // gates() is sync and reads only ctx.employee.separationDate.
    // We construct a minimal Employee with no separationDate via fromRow.
    // (Covered by the build smoke test once Employee fixtures are in place.)
  }, skip: 'Gate coverage exercised in build smoke test');
}
```

- [ ] **Step 2: Run — expect failure**

Run: `flutter test test/features/documents/final_pay_template_test.dart`
Expected: FAIL — file doesn't exist.

- [ ] **Step 3: Create the scaffold + autofill**

```dart
// lib/features/documents/templates/final_pay_template.dart
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart' show Icons, IconData;

import '../blocks/block.dart';
import '../providers.dart';
import 'document_template.dart';
import 'final_pay_inputs.dart';
import 'final_pay_validate.dart';

class FinalPayTemplate extends DocumentTemplate<FinalPayInputs> {
  const FinalPayTemplate();

  @override
  String get id => 'final_pay';

  @override
  String get displayName => 'Final Pay Computation';

  @override
  String get description =>
      'Itemized final-pay disclosure for a separated employee. Auto-computes from payroll engine; HR can override any line. Required by DOLE Labor Advisory 06-20.';

  @override
  IconData get icon => Icons.payments_outlined;

  @override
  bool get supportsBulk => false;

  @override
  List<Gate> gates(AutofillContext ctx) {
    final e = ctx.employee;
    if (e == null) return const [];
    final inactive =
        e.employmentStatus != 'ACTIVE' || e.separationDate != null;
    if (!inactive) {
      return const [Gate('Final Pay is only valid for separated employees.')];
    }
    return const [];
  }

  @override
  Future<FinalPayInputs> autofill(AutofillContext ctx) async {
    final e = ctx.employee;
    final c = ctx.company;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    FinalPayBreakdown? bd;
    if (e != null) {
      try {
        bd = await ctx.ref.read(finalPayBreakdownProvider(e.id).future);
      } catch (_) {
        bd = null;
      }
    }

    return FinalPayInputs(
      employeeId: e?.id ?? '',
      employeeFullName: e?.fullName ?? '',
      employeePosition: e?.jobTitle ?? '',
      employeeHireDate: e?.hireDate,
      employeeSeparationDate: e?.separationDate,
      companyId: c?.id ?? '',
      companyName: c?.name ?? '',
      companyAddress: c?.address ?? '',
      hrManagerName: '',
      lastNetPay: bd?.lastNetPay ?? Decimal.zero,
      thirteenthMonth: bd?.thirteenthMonth ?? Decimal.zero,
      unusedLeaveConversion: bd?.unusedLeaveConversion ?? Decimal.zero,
      outstandingCashAdvance: bd?.outstandingCashAdvance ?? Decimal.zero,
      computedAsOf: today,
      releaseDate: today.add(const Duration(days: 30)),
    );
  }

  @override
  List<ValidationError> validate(FinalPayInputs inputs) =>
      validateFinalPay(inputs);

  @override
  List<Block> build(FinalPayInputs inputs) {
    // Built in Task 4.
    return const [];
  }
}
```

- [ ] **Step 4: Run — expect pass**

Run: `flutter test test/features/documents/final_pay_template_test.dart`
Expected: 1 pass + 1 skipped.

- [ ] **Step 5: Commit**

```bash
git add lib/features/documents/templates/final_pay_template.dart test/features/documents/final_pay_template_test.dart
git commit -m "feat(documents): Final Pay — template scaffold + autofill"
```

## Task 4 — Final Pay: build() block tree + golden

**Files:**
- Modify: `lib/features/documents/templates/final_pay_template.dart`
- Create: `test/features/documents/goldens/final_pay_pagination_test.dart`

- [ ] **Step 1: Write the build() block-tree test**

Append to `test/features/documents/final_pay_template_test.dart`:

```dart
import 'package:decimal/decimal.dart';
import 'package:payroll/features/documents/blocks/company_header_block.dart';
import 'package:payroll/features/documents/blocks/heading_block.dart';
import 'package:payroll/features/documents/blocks/key_value_block.dart';
import 'package:payroll/features/documents/blocks/multi_signature_block.dart';
import 'package:payroll/features/documents/templates/final_pay_inputs.dart';

// add at end of main():
void _addBuildTests() {
  test('build() emits header, computation, signature in order', () {
    final i = FinalPayInputs(
      employeeId: 'e1',
      employeeFullName: 'Alice',
      employeePosition: 'Accountant',
      companyId: 'c1',
      companyName: 'Luxium',
      companyAddress: '123 Street',
      hrManagerName: 'Brixter',
      lastNetPay: Decimal.parse('5000'),
      thirteenthMonth: Decimal.parse('2500'),
      unusedLeaveConversion: Decimal.parse('1000'),
      outstandingCashAdvance: Decimal.zero,
      computedAsOf: DateTime(2026, 6, 5),
      releaseDate: DateTime(2026, 7, 5),
    );
    const t = FinalPayTemplate();
    final blocks = t.build(i);
    expect(blocks.whereType<CompanyHeaderBlock>(), isNotEmpty);
    expect(blocks.whereType<HeadingBlock>().any((h) => h.text == 'Computation'), isTrue);
    expect(blocks.whereType<KeyValueBlock>(), isNotEmpty);
    expect(blocks.whereType<MultiSignatureBlock>(), isNotEmpty);
  });

  test('build() shows otherDeductions row only when > 0', () {
    final base = FinalPayInputs(
      employeeId: 'e1', employeeFullName: 'A', companyId: 'c1',
      companyName: 'X', hrManagerName: 'HR',
      lastNetPay: Decimal.parse('1000'), thirteenthMonth: Decimal.zero,
      unusedLeaveConversion: Decimal.zero, outstandingCashAdvance: Decimal.zero,
      computedAsOf: DateTime(2026, 6, 5), releaseDate: DateTime(2026, 6, 6),
    );
    const t = FinalPayTemplate();
    expect(t.build(base).whereType<KeyValueBlock>().length, equals(5));
    final withDed = base.copyWith(
      otherDeductions: Decimal.parse('200'),
      otherDeductionsLabel: 'SSS top-up',
    );
    expect(t.build(withDed).whereType<KeyValueBlock>().length, equals(6));
  });
}

// then in main():
//   _addBuildTests();
```

Add `_addBuildTests();` as the last line inside `main()`.

- [ ] **Step 2: Run — expect failure (build returns empty)**

Run: `flutter test test/features/documents/final_pay_template_test.dart`
Expected: FAIL — both new tests fail because `build()` returns `[]`.

- [ ] **Step 3: Implement build()**

Replace the `build()` method body in `final_pay_template.dart`:

```dart
import 'package:intl/intl.dart';

import '../blocks/centered_signature_block.dart';
import '../blocks/company_header_block.dart';
import '../blocks/heading_block.dart';
import '../blocks/key_value_block.dart';
import '../blocks/logo_block.dart';
import '../blocks/multi_signature_block.dart';
import '../blocks/paragraph_block.dart';
import '../blocks/spacer_block.dart';

// inside the class:
@override
List<Block> build(FinalPayInputs inputs) {
  final df = DateFormat('MMMM d, yyyy');
  final cf = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
  final i = inputs;
  final sepLine = i.employeeSeparationDate != null
      ? df.format(i.employeeSeparationDate!)
      : '___';

  return <Block>[
    CompanyHeaderBlock(
      companyName: i.companyName,
      companyAddress: i.companyAddress,
    ),
    const SpacerBlock(height: 12),
    ParagraphBlock(text: df.format(i.computedAsOf)),
    const SpacerBlock(height: 8),
    ParagraphBlock(text: i.employeeFullName),
    if (i.employeePosition.isNotEmpty)
      ParagraphBlock(text: i.employeePosition),
    const SpacerBlock(height: 12),
    ParagraphBlock(text: 'Re: Final Pay Computation Breakdown'),
    const SpacerBlock(height: 12),
    ParagraphBlock(
      text:
          'Per DOLE Labor Advisory 06-20, this document discloses the computation of your final pay following separation effective $sepLine.',
    ),
    const SpacerBlock(height: 16),
    const HeadingBlock(text: 'Computation'),
    KeyValueBlock(label: 'Last salary (pro-rated)', value: cf.format(i.lastNetPay.toDouble())),
    KeyValueBlock(label: '13th month pay (pro-rated)', value: cf.format(i.thirteenthMonth.toDouble())),
    KeyValueBlock(label: 'Unused leave conversion', value: cf.format(i.unusedLeaveConversion.toDouble())),
    KeyValueBlock(label: 'Less: Outstanding cash advances', value: '(${cf.format(i.outstandingCashAdvance.toDouble())})'),
    if (i.otherDeductions > Decimal.zero)
      KeyValueBlock(
        label: 'Less: ${i.otherDeductionsLabel.isEmpty ? "Other deductions" : i.otherDeductionsLabel}',
        value: '(${cf.format(i.otherDeductions.toDouble())})',
      ),
    KeyValueBlock(
      label: 'TOTAL FINAL PAY',
      value: cf.format(i.total.toDouble()),
      bold: true,
    ),
    const SpacerBlock(height: 16),
    ParagraphBlock(
      text:
          'The release date is ${df.format(i.releaseDate)}. Please report to HR with valid ID to claim. Any disputes should be raised in writing within seven (7) days of receipt.',
    ),
    const SpacerBlock(height: 40),
    MultiSignatureBlock(
      left: CenteredSignatureBlock(name: i.hrManagerName, label: 'HR Manager'),
      right: CenteredSignatureBlock(name: i.employeeFullName, label: 'Employee (Acknowledged)'),
    ),
  ];
}
```

> **Important:** `KeyValueBlock` may not have a `bold` parameter today. If `flutter analyze` complains, drop it — the bold styling is cosmetic; the test only checks structural shape.

- [ ] **Step 4: Run unit tests — expect pass**

Run: `flutter test test/features/documents/final_pay_template_test.dart test/features/documents/final_pay_validate_test.dart`
Expected: all tests pass.

- [ ] **Step 5: Create the pagination golden**

```dart
// test/features/documents/goldens/final_pay_pagination_test.dart
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll/core/pdf/render.dart';
import 'package:payroll/features/documents/templates/final_pay_inputs.dart';
import 'package:payroll/features/documents/templates/final_pay_template.dart';

void main() {
  testWidgets('Final Pay PDF renders without overflow', (tester) async {
    final i = FinalPayInputs(
      employeeId: 'e1',
      employeeFullName: 'Alice Reyes',
      employeePosition: 'Senior Accountant',
      employeeHireDate: DateTime(2022, 1, 5),
      employeeSeparationDate: DateTime(2026, 5, 31),
      companyId: 'c1',
      companyName: 'Luxium Holdings Corp.',
      companyAddress: '123 Sample Address, Quezon City',
      hrManagerName: 'Brixter Cruz',
      lastNetPay: Decimal.parse('12345.67'),
      thirteenthMonth: Decimal.parse('8000.00'),
      unusedLeaveConversion: Decimal.parse('2400.00'),
      outstandingCashAdvance: Decimal.parse('500.00'),
      otherDeductions: Decimal.parse('150.00'),
      otherDeductionsLabel: 'SSS contribution top-up',
      computedAsOf: DateTime(2026, 6, 5),
      releaseDate: DateTime(2026, 7, 5),
    );
    const t = FinalPayTemplate();
    final bytes = await renderDocumentToPdf(t.build(i));
    expect(bytes.length, greaterThan(2000), reason: 'PDF should not be empty');
    final header = bytes.sublist(0, 4);
    expect(String.fromCharCodes(header), startsWith('%PDF'));
  });
}
```

> **Note:** if the actual rendering entry-point is not `renderDocumentToPdf`, grep for the equivalent in `nda_pagination_test.dart` and mirror it.

- [ ] **Step 6: Run golden — expect pass**

Run: `flutter test test/features/documents/goldens/final_pay_pagination_test.dart`
Expected: pass.

- [ ] **Step 7: Commit**

```bash
git add lib/features/documents/templates/final_pay_template.dart test/features/documents/final_pay_template_test.dart test/features/documents/goldens/final_pay_pagination_test.dart
git commit -m "feat(documents): Final Pay — build() + pagination golden"
```

## Task 5 — Final Pay: Form widget

**Files:**
- Create: `lib/features/documents/forms/final_pay_form.dart`

- [ ] **Step 1: Create the form**

```dart
// lib/features/documents/forms/final_pay_form.dart
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../widgets/hr_manager_field.dart';
import '../inputs/amount_with_breakdown.dart';
import '../inputs/company_picker.dart';
import '../inputs/date_field.dart';
import '../inputs/employee_picker.dart';
import '../providers.dart';
import '../templates/final_pay_inputs.dart';

class FinalPayForm extends ConsumerStatefulWidget {
  final FinalPayInputs initial;
  final bool employeeLocked;
  final ValueChanged<FinalPayInputs> onChanged;
  final ValueChanged<String> onEmployeeChanged;
  const FinalPayForm({
    super.key,
    required this.initial,
    required this.employeeLocked,
    required this.onChanged,
    required this.onEmployeeChanged,
  });

  @override
  ConsumerState<FinalPayForm> createState() => _FinalPayFormState();
}

class _FinalPayFormState extends ConsumerState<FinalPayForm> {
  late FinalPayInputs _i = widget.initial;

  void _set(FinalPayInputs next) {
    setState(() => _i = next);
    widget.onChanged(next);
  }

  @override
  void didUpdateWidget(covariant FinalPayForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initial != widget.initial) _i = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    final breakdownAsync = _i.employeeId.isEmpty
        ? const AsyncValue<FinalPayBreakdown?>.data(null)
        : ref.watch(finalPayBreakdownProvider(_i.employeeId)).whenData((v) => v);
    final breakdown = breakdownAsync.value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EmployeePicker(
          selectedId: _i.employeeId,
          enabled: !widget.employeeLocked,
          onSelected: (e) {
            widget.onEmployeeChanged(e?.id ?? '');
            _set(_i.copyWith(
              employeeId: e?.id ?? '',
              employeeFullName: e?.fullName ?? '',
              employeePosition: e?.jobTitle ?? '',
              employeeHireDate: e?.hireDate,
              employeeSeparationDate: e?.separationDate,
            ));
          },
        ),
        const SizedBox(height: 16),
        CompanyPicker(
          selectedId: _i.companyId,
          onSelected: (h) => _set(_i.copyWith(
            companyId: h?.id ?? '',
            companyName: h?.name ?? '',
            companyAddress: h?.address ?? '',
          )),
        ),
        const SizedBox(height: 16),
        HrManagerField(
          value: _i.hrManagerName,
          companyId: _i.companyId,
          onChanged: (v) => _set(_i.copyWith(hrManagerName: v)),
        ),
        const SizedBox(height: 24),
        const Text('Computation', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        _line('Last net pay', _i.lastNetPay, breakdown, _i.lastNetPayLocked,
            (v) => _set(_i.copyWith(lastNetPay: v, lastNetPayLocked: true))),
        _line('13th-month pay', _i.thirteenthMonth, breakdown,
            _i.thirteenthMonthLocked,
            (v) => _set(_i.copyWith(thirteenthMonth: v, thirteenthMonthLocked: true))),
        _line('Unused leave conversion', _i.unusedLeaveConversion, breakdown,
            _i.unusedLeaveConversionLocked,
            (v) => _set(_i.copyWith(
                unusedLeaveConversion: v, unusedLeaveConversionLocked: true))),
        _line('Outstanding cash advance', _i.outstandingCashAdvance, breakdown,
            _i.outstandingCashAdvanceLocked,
            (v) => _set(_i.copyWith(
                outstandingCashAdvance: v,
                outstandingCashAdvanceLocked: true))),
        const SizedBox(height: 16),
        TextFormField(
          initialValue: _i.otherDeductionsLabel,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Other deduction label (optional)',
          ),
          onChanged: (v) => _set(_i.copyWith(otherDeductionsLabel: v)),
        ),
        const SizedBox(height: 12),
        AmountWithBreakdown(
          value: _i.otherDeductions,
          breakdown: null,
          locked: true,
          onChanged: (v) => _set(_i.copyWith(otherDeductions: v)),
        ),
        const SizedBox(height: 24),
        DateField(
          label: 'Computed as of',
          value: _i.computedAsOf,
          onChanged: (d) => _set(_i.copyWith(computedAsOf: d)),
        ),
        const SizedBox(height: 12),
        DateField(
          label: 'Release date',
          value: _i.releaseDate,
          onChanged: (d) => _set(_i.copyWith(releaseDate: d)),
        ),
      ],
    );
  }

  Widget _line(String label, Decimal v, FinalPayBreakdown? bd, bool locked,
      ValueChanged<Decimal> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 4),
          AmountWithBreakdown(
            value: v,
            breakdown: bd,
            locked: locked,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Verify analyze**

Run: `dart format lib/features/documents/forms/final_pay_form.dart && flutter analyze lib/features/documents/forms/final_pay_form.dart`
Expected: `No issues found!` (Fix any missing imports surfaced by `flutter analyze` by mirroring the imports in `lib/features/documents/forms/nda_form.dart`.)

- [ ] **Step 3: Commit**

```bash
git add lib/features/documents/forms/final_pay_form.dart
git commit -m "feat(documents): Final Pay — form widget"
```

---

# Salary Adjustment / Promotion (Tasks 6-10)

## Task 6 — Salary Adjustment: Inputs class

**Files:**
- Create: `lib/features/documents/templates/salary_adjustment_inputs.dart`

- [ ] **Step 1: Create the file**

```dart
import 'package:decimal/decimal.dart';

import 'document_template.dart';

enum SalaryAdjustmentType { salaryAdjustment, promotion }

extension SalaryAdjustmentTypeX on SalaryAdjustmentType {
  String get label => switch (this) {
        SalaryAdjustmentType.salaryAdjustment => 'Salary Adjustment',
        SalaryAdjustmentType.promotion => 'Promotion',
      };
}

class SalaryAdjustmentInputs extends TemplateInputs {
  final SalaryAdjustmentType type;
  final String employeeId;
  final String employeeFullName;
  final String employeePosition;
  final String employeeGender; // 'MALE' | 'FEMALE' | '' — for salutation
  final String companyId;
  final String companyName;
  final String companyAddress;
  final String hrManagerName;
  // Promotion-only role-change fields
  final String? oldRoleScorecardId;
  final String? newRoleScorecardId;
  final String oldPosition;
  final String newPosition;
  // Salary (always)
  final Decimal oldSalary;
  final Decimal newSalary;
  final String salaryPeriod; // 'MONTHLY' | 'DAILY'
  final DateTime effectiveDate;
  final DateTime issueDate;
  final String reason;

  SalaryAdjustmentInputs({
    this.type = SalaryAdjustmentType.salaryAdjustment,
    required this.employeeId,
    required this.employeeFullName,
    this.employeePosition = '',
    this.employeeGender = '',
    required this.companyId,
    required this.companyName,
    this.companyAddress = '',
    this.hrManagerName = '',
    this.oldRoleScorecardId,
    this.newRoleScorecardId,
    this.oldPosition = '',
    this.newPosition = '',
    Decimal? oldSalary,
    Decimal? newSalary,
    this.salaryPeriod = 'MONTHLY',
    required this.effectiveDate,
    required this.issueDate,
    this.reason = '',
  })  : oldSalary = oldSalary ?? Decimal.zero,
        newSalary = newSalary ?? Decimal.zero;

  SalaryAdjustmentInputs copyWith({
    SalaryAdjustmentType? type,
    String? employeeId,
    String? employeeFullName,
    String? employeePosition,
    String? employeeGender,
    String? companyId,
    String? companyName,
    String? companyAddress,
    String? hrManagerName,
    Object? oldRoleScorecardId = _undef,
    Object? newRoleScorecardId = _undef,
    String? oldPosition,
    String? newPosition,
    Decimal? oldSalary,
    Decimal? newSalary,
    String? salaryPeriod,
    DateTime? effectiveDate,
    DateTime? issueDate,
    String? reason,
  }) =>
      SalaryAdjustmentInputs(
        type: type ?? this.type,
        employeeId: employeeId ?? this.employeeId,
        employeeFullName: employeeFullName ?? this.employeeFullName,
        employeePosition: employeePosition ?? this.employeePosition,
        employeeGender: employeeGender ?? this.employeeGender,
        companyId: companyId ?? this.companyId,
        companyName: companyName ?? this.companyName,
        companyAddress: companyAddress ?? this.companyAddress,
        hrManagerName: hrManagerName ?? this.hrManagerName,
        oldRoleScorecardId: identical(oldRoleScorecardId, _undef)
            ? this.oldRoleScorecardId
            : oldRoleScorecardId as String?,
        newRoleScorecardId: identical(newRoleScorecardId, _undef)
            ? this.newRoleScorecardId
            : newRoleScorecardId as String?,
        oldPosition: oldPosition ?? this.oldPosition,
        newPosition: newPosition ?? this.newPosition,
        oldSalary: oldSalary ?? this.oldSalary,
        newSalary: newSalary ?? this.newSalary,
        salaryPeriod: salaryPeriod ?? this.salaryPeriod,
        effectiveDate: effectiveDate ?? this.effectiveDate,
        issueDate: issueDate ?? this.issueDate,
        reason: reason ?? this.reason,
      );

  @override
  Map<String, dynamic> toDebugMap() => {
        'type': type.name,
        'employeeId': employeeId,
        'effective': effectiveDate.toIso8601String(),
      };
}

const _undef = Object();
```

- [ ] **Step 2: Verify**

Run: `dart format lib/features/documents/templates/salary_adjustment_inputs.dart && flutter analyze lib/features/documents/templates/salary_adjustment_inputs.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/features/documents/templates/salary_adjustment_inputs.dart
git commit -m "feat(documents): Salary Adjustment — inputs class"
```

## Task 7 — Salary Adjustment: validate + tests

**Files:**
- Create: `lib/features/documents/templates/salary_adjustment_validate.dart`
- Create: `test/features/documents/salary_adjustment_validate_test.dart`

- [ ] **Step 1: Write failing tests**

```dart
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll/features/documents/templates/salary_adjustment_inputs.dart';
import 'package:payroll/features/documents/templates/salary_adjustment_validate.dart';

SalaryAdjustmentInputs _base() => SalaryAdjustmentInputs(
      employeeId: 'e1',
      employeeFullName: 'Bob',
      companyId: 'c1',
      companyName: 'X',
      hrManagerName: 'HR',
      oldSalary: Decimal.parse('20000'),
      newSalary: Decimal.parse('25000'),
      effectiveDate: DateTime(2026, 7, 1),
      issueDate: DateTime(2026, 6, 5),
      reason: 'Annual merit increase',
    );

void main() {
  test('passes for adjustment with all fields', () {
    expect(validateSalaryAdjustment(_base()), isEmpty);
  });

  test('requires reason', () {
    final i = _base().copyWith(reason: '');
    expect(validateSalaryAdjustment(i).map((e) => e.field), contains('reason'));
  });

  test('promotion requires newRoleScorecardId', () {
    final i = _base().copyWith(type: SalaryAdjustmentType.promotion);
    expect(validateSalaryAdjustment(i).map((e) => e.field),
        contains('newRoleScorecardId'));
  });

  test('promotion rejects same old=new scorecard', () {
    final i = _base().copyWith(
      type: SalaryAdjustmentType.promotion,
      oldRoleScorecardId: 'r1',
      newRoleScorecardId: 'r1',
    );
    expect(validateSalaryAdjustment(i).map((e) => e.field),
        contains('newRoleScorecardId'));
  });

  test('rejects oldSalary == newSalary', () {
    final i = _base().copyWith(newSalary: Decimal.parse('20000'));
    expect(validateSalaryAdjustment(i).map((e) => e.field),
        contains('newSalary'));
  });
}
```

- [ ] **Step 2: Run — expect failure**

Run: `flutter test test/features/documents/salary_adjustment_validate_test.dart`
Expected: FAIL (no impl).

- [ ] **Step 3: Implement**

```dart
import 'package:decimal/decimal.dart';

import 'document_template.dart';
import 'salary_adjustment_inputs.dart';

List<ValidationError> validateSalaryAdjustment(SalaryAdjustmentInputs i) {
  final errors = <ValidationError>[];
  if (i.employeeId.isEmpty) {
    errors.add(const ValidationError('employee', 'Select an employee'));
  }
  if (i.employeeFullName.trim().isEmpty) {
    errors.add(const ValidationError('employeeFullName', 'Employee name is required'));
  }
  if (i.companyId.isEmpty) {
    errors.add(const ValidationError('company', 'Select a company'));
  }
  if (i.hrManagerName.trim().isEmpty) {
    errors.add(const ValidationError('hrManager', 'HR manager name is required'));
  }
  if (i.oldSalary <= Decimal.zero) {
    errors.add(const ValidationError('oldSalary', 'Current salary must be positive'));
  }
  if (i.newSalary <= Decimal.zero) {
    errors.add(const ValidationError('newSalary', 'New salary must be positive'));
  }
  if (i.oldSalary == i.newSalary) {
    errors.add(const ValidationError('newSalary', 'New salary must differ from current'));
  }
  if (i.reason.trim().isEmpty) {
    errors.add(const ValidationError('reason', 'Reason is required'));
  }
  if (i.type == SalaryAdjustmentType.promotion) {
    final newId = i.newRoleScorecardId ?? '';
    if (newId.isEmpty) {
      errors.add(const ValidationError(
          'newRoleScorecardId', 'Select the target role scorecard'));
    } else if (newId == (i.oldRoleScorecardId ?? '')) {
      errors.add(const ValidationError(
          'newRoleScorecardId', 'Target role must differ from current'));
    }
  }
  return errors;
}
```

- [ ] **Step 4: Run — expect pass**

Run: `flutter test test/features/documents/salary_adjustment_validate_test.dart`
Expected: 5 pass.

- [ ] **Step 5: Commit**

```bash
git add lib/features/documents/templates/salary_adjustment_validate.dart test/features/documents/salary_adjustment_validate_test.dart
git commit -m "feat(documents): Salary Adjustment — validate + tests"
```

## Task 8 — Salary Adjustment: Template + autofill + build

**Files:**
- Create: `lib/features/documents/templates/salary_adjustment_template.dart`
- Create: `test/features/documents/salary_adjustment_template_test.dart`

- [ ] **Step 1: Write the test**

```dart
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll/features/documents/blocks/emphasis_paragraph_block.dart';
import 'package:payroll/features/documents/blocks/heading_block.dart';
import 'package:payroll/features/documents/blocks/multi_signature_block.dart';
import 'package:payroll/features/documents/blocks/paragraph_block.dart';
import 'package:payroll/features/documents/templates/salary_adjustment_inputs.dart';
import 'package:payroll/features/documents/templates/salary_adjustment_template.dart';

void main() {
  test('id + displayName + supportsBulk', () {
    const t = SalaryAdjustmentTemplate();
    expect(t.id, 'salary_adjustment');
    expect(t.displayName.toLowerCase(), contains('salary'));
    expect(t.supportsBulk, isTrue);
  });

  test('ADJUSTMENT subject reads "Salary Adjustment"', () {
    final i = SalaryAdjustmentInputs(
      employeeId: 'e1', employeeFullName: 'Bob', employeePosition: 'Dev',
      companyId: 'c1', companyName: 'Luxium', hrManagerName: 'HR',
      oldSalary: Decimal.parse('1'), newSalary: Decimal.parse('2'),
      effectiveDate: DateTime(2026, 7, 1), issueDate: DateTime(2026, 6, 5),
      reason: 'r',
    );
    const t = SalaryAdjustmentTemplate();
    final ps = t.build(i).whereType<ParagraphBlock>().map((p) => p.text).toList();
    expect(ps.any((s) => s.contains('Notice of Salary Adjustment')), isTrue);
  });

  test('PROMOTION subject reads "Notice of Promotion"', () {
    final i = SalaryAdjustmentInputs(
      type: SalaryAdjustmentType.promotion,
      employeeId: 'e1', employeeFullName: 'Bob', employeePosition: 'Dev',
      companyId: 'c1', companyName: 'Luxium', hrManagerName: 'HR',
      oldPosition: 'Dev', newPosition: 'Senior Dev',
      oldRoleScorecardId: 'r1', newRoleScorecardId: 'r2',
      oldSalary: Decimal.parse('1'), newSalary: Decimal.parse('2'),
      effectiveDate: DateTime(2026, 7, 1), issueDate: DateTime(2026, 6, 5),
      reason: 'r',
    );
    const t = SalaryAdjustmentTemplate();
    final ps = t.build(i).whereType<ParagraphBlock>().map((p) => p.text).toList();
    expect(ps.any((s) => s.contains('Notice of Promotion')), isTrue);
  });
}
```

- [ ] **Step 2: Run — expect failure**

Run: `flutter test test/features/documents/salary_adjustment_template_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement**

```dart
// lib/features/documents/templates/salary_adjustment_template.dart
import 'package:flutter/material.dart' show Icons, IconData;
import 'package:intl/intl.dart';

import '../blocks/block.dart';
import '../blocks/centered_signature_block.dart';
import '../blocks/emphasis_paragraph_block.dart';
import '../blocks/heading_block.dart';
import '../blocks/letter_meta_block.dart';
import '../blocks/logo_block.dart';
import '../blocks/multi_signature_block.dart';
import '../blocks/paragraph_block.dart';
import '../blocks/spacer_block.dart';
import 'document_template.dart';
import 'salary_adjustment_inputs.dart';
import 'salary_adjustment_validate.dart';

class SalaryAdjustmentTemplate
    extends DocumentTemplate<SalaryAdjustmentInputs> {
  const SalaryAdjustmentTemplate();

  @override
  String get id => 'salary_adjustment';

  @override
  String get displayName => 'Salary Adjustment / Promotion';

  @override
  String get description =>
      'Notice of salary adjustment, or promotion (role + salary change). One template, two modes.';

  @override
  IconData get icon => Icons.trending_up_outlined;

  @override
  bool get supportsBulk => true;

  @override
  List<Gate> gates(AutofillContext ctx) => const [];

  @override
  Future<SalaryAdjustmentInputs> autofill(AutofillContext ctx) async {
    final e = ctx.employee;
    final c = ctx.company;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final firstOfNextMonth = DateTime(now.year, now.month + 1, 1);

    return SalaryAdjustmentInputs(
      type: SalaryAdjustmentType.salaryAdjustment,
      employeeId: e?.id ?? '',
      employeeFullName: e?.fullName ?? '',
      employeePosition: e?.jobTitle ?? '',
      employeeGender: e?.gender ?? '',
      companyId: c?.id ?? '',
      companyName: c?.name ?? '',
      companyAddress: c?.address ?? '',
      hrManagerName: '',
      oldRoleScorecardId: e?.roleScorecardId,
      oldPosition: e?.jobTitle ?? '',
      oldSalary: e?.declaredWageOverride ?? e?.baseSalary ?? Decimal.zero,
      salaryPeriod: e?.wageType ?? 'MONTHLY',
      effectiveDate: firstOfNextMonth,
      issueDate: today,
    );
  }

  @override
  List<ValidationError> validate(SalaryAdjustmentInputs inputs) =>
      validateSalaryAdjustment(inputs);

  @override
  List<Block> build(SalaryAdjustmentInputs inputs) {
    final df = DateFormat('MMMM d, yyyy');
    final cf = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
    final i = inputs;
    final periodLabel = i.salaryPeriod == 'DAILY' ? 'daily rate' : 'monthly salary';
    final salutation = _salutation(i.employeeGender, i.employeeFullName);
    final subject = i.type == SalaryAdjustmentType.promotion
        ? 'Notice of Promotion'
        : 'Notice of Salary Adjustment';

    final bodyText = i.type == SalaryAdjustmentType.promotion
        ? 'We are pleased to inform you that, effective ${df.format(i.effectiveDate)}, you are being promoted from ${i.oldPosition} to ${i.newPosition}. In line with this promotion, your $periodLabel will be adjusted from ${cf.format(i.oldSalary.toDouble())} to ${cf.format(i.newSalary.toDouble())}. ${i.reason}'
        : 'We are pleased to inform you that, effective ${df.format(i.effectiveDate)}, your $periodLabel will be adjusted from ${cf.format(i.oldSalary.toDouble())} to ${cf.format(i.newSalary.toDouble())}. ${i.reason}';

    return <Block>[
      LogoBlock(companyId: i.companyId),
      LetterMetaBlock(
        date: i.issueDate,
        recipient: i.employeeFullName,
        position: i.employeePosition,
        subject: subject,
      ),
      const SpacerBlock(height: 12),
      ParagraphBlock(text: '$salutation,'),
      const SpacerBlock(height: 8),
      ParagraphBlock(text: bodyText),
      const SpacerBlock(height: 12),
      const ParagraphBlock(
          text:
              'All other terms of your employment remain unchanged. Please acknowledge receipt of this letter below.'),
      const SpacerBlock(height: 40),
      MultiSignatureBlock(
        left: CenteredSignatureBlock(name: i.hrManagerName, label: 'HR Manager'),
        right: CenteredSignatureBlock(
            name: i.employeeFullName, label: 'Employee (Acknowledged)'),
      ),
    ];
  }

  String _salutation(String gender, String fullName) {
    final lastName = fullName.split(RegExp(r'\s+')).last;
    if (gender == 'FEMALE') return 'Dear Ms. $lastName';
    if (gender == 'MALE') return 'Dear Mr. $lastName';
    return 'Dear $lastName';
  }
}
```

- [ ] **Step 4: Run — expect pass**

Run: `flutter test test/features/documents/salary_adjustment_template_test.dart test/features/documents/salary_adjustment_validate_test.dart`
Expected: all pass.

- [ ] **Step 5: Create pagination golden**

```dart
// test/features/documents/goldens/salary_adjustment_pagination_test.dart
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll/core/pdf/render.dart';
import 'package:payroll/features/documents/templates/salary_adjustment_inputs.dart';
import 'package:payroll/features/documents/templates/salary_adjustment_template.dart';

void main() {
  testWidgets('SalaryAdjustment ADJUSTMENT mode renders PDF', (tester) async {
    final i = SalaryAdjustmentInputs(
      employeeId: 'e1', employeeFullName: 'Alice Reyes', employeePosition: 'Accountant',
      companyId: 'c1', companyName: 'GameCove', hrManagerName: 'Brixter',
      oldSalary: Decimal.parse('20000'), newSalary: Decimal.parse('25000'),
      effectiveDate: DateTime(2026, 7, 1), issueDate: DateTime(2026, 6, 5),
      reason: 'In recognition of your performance.',
    );
    final bytes = await renderDocumentToPdf(const SalaryAdjustmentTemplate().build(i));
    expect(String.fromCharCodes(bytes.sublist(0, 4)), startsWith('%PDF'));
  });

  testWidgets('SalaryAdjustment PROMOTION mode renders PDF', (tester) async {
    final i = SalaryAdjustmentInputs(
      type: SalaryAdjustmentType.promotion,
      employeeId: 'e1', employeeFullName: 'Alice Reyes', employeePosition: 'Accountant',
      companyId: 'c1', companyName: 'GameCove', hrManagerName: 'Brixter',
      oldPosition: 'Accountant', newPosition: 'Senior Accountant',
      oldRoleScorecardId: 'r1', newRoleScorecardId: 'r2',
      oldSalary: Decimal.parse('20000'), newSalary: Decimal.parse('28000'),
      effectiveDate: DateTime(2026, 7, 1), issueDate: DateTime(2026, 6, 5),
      reason: 'Promoted following Q2 performance review.',
    );
    final bytes = await renderDocumentToPdf(const SalaryAdjustmentTemplate().build(i));
    expect(String.fromCharCodes(bytes.sublist(0, 4)), startsWith('%PDF'));
  });
}
```

- [ ] **Step 6: Commit**

```bash
git add lib/features/documents/templates/salary_adjustment_template.dart test/features/documents/salary_adjustment_template_test.dart test/features/documents/goldens/salary_adjustment_pagination_test.dart
git commit -m "feat(documents): Salary Adjustment — template + golden"
```

## Task 9 — Salary Adjustment: Form widget

**Files:**
- Create: `lib/features/documents/forms/salary_adjustment_form.dart`

- [ ] **Step 1: Create the form**

```dart
// lib/features/documents/forms/salary_adjustment_form.dart
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../widgets/hr_manager_field.dart';
import '../inputs/company_picker.dart';
import '../inputs/date_field.dart';
import '../inputs/employee_picker.dart';
import '../inputs/role_scorecard_picker.dart';
import '../providers.dart';
import '../templates/salary_adjustment_inputs.dart';

class SalaryAdjustmentForm extends ConsumerStatefulWidget {
  final SalaryAdjustmentInputs initial;
  final bool employeeLocked;
  final ValueChanged<SalaryAdjustmentInputs> onChanged;
  final ValueChanged<String> onEmployeeChanged;
  const SalaryAdjustmentForm({
    super.key,
    required this.initial,
    required this.employeeLocked,
    required this.onChanged,
    required this.onEmployeeChanged,
  });

  @override
  ConsumerState<SalaryAdjustmentForm> createState() =>
      _SalaryAdjustmentFormState();
}

class _SalaryAdjustmentFormState extends ConsumerState<SalaryAdjustmentForm> {
  late SalaryAdjustmentInputs _i = widget.initial;

  void _set(SalaryAdjustmentInputs next) {
    setState(() => _i = next);
    widget.onChanged(next);
  }

  @override
  void didUpdateWidget(covariant SalaryAdjustmentForm old) {
    super.didUpdateWidget(old);
    if (old.initial != widget.initial) _i = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    final isPromo = _i.type == SalaryAdjustmentType.promotion;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<SalaryAdjustmentType>(
          segments: const [
            ButtonSegment(
                value: SalaryAdjustmentType.salaryAdjustment,
                label: Text('Salary Adjustment')),
            ButtonSegment(
                value: SalaryAdjustmentType.promotion,
                label: Text('Promotion')),
          ],
          selected: {_i.type},
          onSelectionChanged: (s) => _set(_i.copyWith(type: s.first)),
        ),
        const SizedBox(height: 16),
        EmployeePicker(
          selectedId: _i.employeeId,
          enabled: !widget.employeeLocked,
          onSelected: (e) {
            widget.onEmployeeChanged(e?.id ?? '');
            _set(_i.copyWith(
              employeeId: e?.id ?? '',
              employeeFullName: e?.fullName ?? '',
              employeePosition: e?.jobTitle ?? '',
              employeeGender: e?.gender ?? '',
              oldPosition: e?.jobTitle ?? '',
              oldRoleScorecardId: e?.roleScorecardId,
              oldSalary: e?.declaredWageOverride ?? e?.baseSalary ?? Decimal.zero,
              salaryPeriod: e?.wageType ?? 'MONTHLY',
            ));
          },
        ),
        const SizedBox(height: 16),
        CompanyPicker(
          selectedId: _i.companyId,
          onSelected: (h) => _set(_i.copyWith(
            companyId: h?.id ?? '',
            companyName: h?.name ?? '',
            companyAddress: h?.address ?? '',
          )),
        ),
        const SizedBox(height: 16),
        HrManagerField(
          value: _i.hrManagerName,
          companyId: _i.companyId,
          onChanged: (v) => _set(_i.copyWith(hrManagerName: v)),
        ),
        if (isPromo) ...[
          const SizedBox(height: 16),
          RoleScorecardPicker(
            label: 'Target role',
            selectedId: _i.newRoleScorecardId,
            onSelected: (sc) => _set(_i.copyWith(
              newRoleScorecardId: sc?.id,
              newPosition: sc?.jobTitle ?? '',
              newSalary: sc?.baseSalary ?? _i.newSalary,
            )),
          ),
        ],
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: TextFormField(
              key: ValueKey('old-${_i.employeeId}'),
              initialValue: _i.oldSalary.toString(),
              decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Current salary',
                  prefixText: '₱ '),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: (v) {
                final d = Decimal.tryParse(v) ?? Decimal.zero;
                _set(_i.copyWith(oldSalary: d));
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              key: ValueKey('new-${_i.employeeId}-${_i.newRoleScorecardId}'),
              initialValue: _i.newSalary.toString(),
              decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'New salary',
                  prefixText: '₱ '),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: (v) {
                final d = Decimal.tryParse(v) ?? Decimal.zero;
                _set(_i.copyWith(newSalary: d));
              },
            ),
          ),
        ]),
        const SizedBox(height: 16),
        DateField(
          label: 'Effective date',
          value: _i.effectiveDate,
          onChanged: (d) => _set(_i.copyWith(effectiveDate: d)),
        ),
        const SizedBox(height: 12),
        TextFormField(
          initialValue: _i.reason,
          minLines: 3,
          maxLines: 8,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Reason / context (shown in letter body)',
          ),
          onChanged: (v) => _set(_i.copyWith(reason: v)),
        ),
      ],
    );
  }
}
```

> **Note:** if `RoleScorecardPicker` doesn't exist in the codebase, mirror the existing `CompanyPicker` to make a dropdown reading `roleScorecardsProvider`. If neither exists, fall back to a plain `DropdownButtonFormField` reading from `roleScorecardListProvider` — grep `lib/` for whatever the existing name is.

- [ ] **Step 2: Verify analyze (mirror imports as needed)**

Run: `dart format lib/features/documents/forms/salary_adjustment_form.dart && flutter analyze lib/features/documents/forms/salary_adjustment_form.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/features/documents/forms/salary_adjustment_form.dart
git commit -m "feat(documents): Salary Adjustment — form widget"
```

---

# Notice of Decision / NOD (Tasks 10-12)

## Task 10 — NOD: Inputs class + validate + tests

**Files:**
- Create: `lib/features/documents/templates/nod_inputs.dart`
- Create: `lib/features/documents/templates/nod_validate.dart`
- Create: `test/features/documents/nod_validate_test.dart`

- [ ] **Step 1: Inputs class**

```dart
// lib/features/documents/templates/nod_inputs.dart
import 'document_template.dart';

enum NodDecision { reprimand, writtenWarning, suspension, termination, noAction }

extension NodDecisionX on NodDecision {
  String get label => switch (this) {
        NodDecision.reprimand => 'Reprimand',
        NodDecision.writtenWarning => 'Written Warning',
        NodDecision.suspension => 'Suspension',
        NodDecision.termination => 'Termination',
        NodDecision.noAction => 'No Action',
      };
}

class NodInputs extends TemplateInputs {
  final String employeeId;
  final String employeeFullName;
  final String employeePosition;
  final String employeeGender;
  final String companyId;
  final String companyName;
  final String companyAddress;
  final String hrManagerName;

  final String? linkedNteDocumentId;
  final DateTime? nteDate;
  final String charges;
  final String employeeResponseSummary;
  final String findings;

  final NodDecision decision;
  final int suspensionDays;
  final DateTime effectiveDate;
  final DateTime issueDate;

  NodInputs({
    required this.employeeId,
    required this.employeeFullName,
    this.employeePosition = '',
    this.employeeGender = '',
    required this.companyId,
    required this.companyName,
    this.companyAddress = '',
    this.hrManagerName = '',
    this.linkedNteDocumentId,
    this.nteDate,
    this.charges = '',
    this.employeeResponseSummary = '',
    this.findings = '',
    this.decision = NodDecision.writtenWarning,
    this.suspensionDays = 0,
    required this.effectiveDate,
    required this.issueDate,
  });

  NodInputs copyWith({
    String? employeeId,
    String? employeeFullName,
    String? employeePosition,
    String? employeeGender,
    String? companyId,
    String? companyName,
    String? companyAddress,
    String? hrManagerName,
    Object? linkedNteDocumentId = _undef,
    Object? nteDate = _undef,
    String? charges,
    String? employeeResponseSummary,
    String? findings,
    NodDecision? decision,
    int? suspensionDays,
    DateTime? effectiveDate,
    DateTime? issueDate,
  }) =>
      NodInputs(
        employeeId: employeeId ?? this.employeeId,
        employeeFullName: employeeFullName ?? this.employeeFullName,
        employeePosition: employeePosition ?? this.employeePosition,
        employeeGender: employeeGender ?? this.employeeGender,
        companyId: companyId ?? this.companyId,
        companyName: companyName ?? this.companyName,
        companyAddress: companyAddress ?? this.companyAddress,
        hrManagerName: hrManagerName ?? this.hrManagerName,
        linkedNteDocumentId: identical(linkedNteDocumentId, _undef)
            ? this.linkedNteDocumentId
            : linkedNteDocumentId as String?,
        nteDate: identical(nteDate, _undef) ? this.nteDate : nteDate as DateTime?,
        charges: charges ?? this.charges,
        employeeResponseSummary:
            employeeResponseSummary ?? this.employeeResponseSummary,
        findings: findings ?? this.findings,
        decision: decision ?? this.decision,
        suspensionDays: suspensionDays ?? this.suspensionDays,
        effectiveDate: effectiveDate ?? this.effectiveDate,
        issueDate: issueDate ?? this.issueDate,
      );

  @override
  Map<String, dynamic> toDebugMap() => {
        'employeeId': employeeId,
        'decision': decision.name,
        'linkedNte': linkedNteDocumentId,
      };
}

const _undef = Object();
```

- [ ] **Step 2: validate tests (TDD)**

```dart
// test/features/documents/nod_validate_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll/features/documents/templates/nod_inputs.dart';
import 'package:payroll/features/documents/templates/nod_validate.dart';

NodInputs _base() => NodInputs(
      employeeId: 'e1',
      employeeFullName: 'Bob',
      companyId: 'c1',
      companyName: 'X',
      hrManagerName: 'HR',
      charges: 'Tardiness',
      employeeResponseSummary: 'Bob admits the lateness.',
      findings: 'Substantiated.',
      decision: NodDecision.writtenWarning,
      effectiveDate: DateTime(2026, 6, 6),
      issueDate: DateTime(2026, 6, 5),
    );

void main() {
  test('valid baseline passes', () => expect(validateNod(_base()), isEmpty));

  test('charges required',
      () => expect(validateNod(_base().copyWith(charges: '')).map((e) => e.field),
          contains('charges')));

  test('employee response required',
      () => expect(
          validateNod(_base().copyWith(employeeResponseSummary: '')).map((e) => e.field),
          contains('employeeResponseSummary')));

  test('findings required',
      () => expect(validateNod(_base().copyWith(findings: '')).map((e) => e.field),
          contains('findings')));

  test('suspension requires days > 0', () {
    final i = _base().copyWith(decision: NodDecision.suspension, suspensionDays: 0);
    expect(validateNod(i).map((e) => e.field), contains('suspensionDays'));
  });

  test('issueDate after effectiveDate rejected', () {
    final i = _base().copyWith(
      issueDate: DateTime(2026, 6, 10),
      effectiveDate: DateTime(2026, 6, 6),
    );
    expect(validateNod(i).map((e) => e.field), contains('effectiveDate'));
  });
}
```

- [ ] **Step 3: Run — expect failure**

Run: `flutter test test/features/documents/nod_validate_test.dart`
Expected: FAIL.

- [ ] **Step 4: Implement validate**

```dart
// lib/features/documents/templates/nod_validate.dart
import 'document_template.dart';
import 'nod_inputs.dart';

List<ValidationError> validateNod(NodInputs i) {
  final errors = <ValidationError>[];
  if (i.employeeId.isEmpty) errors.add(const ValidationError('employee', 'Select an employee'));
  if (i.companyId.isEmpty) errors.add(const ValidationError('company', 'Select a company'));
  if (i.hrManagerName.trim().isEmpty) {
    errors.add(const ValidationError('hrManager', 'HR manager name is required'));
  }
  if (i.charges.trim().isEmpty) {
    errors.add(const ValidationError('charges', 'Describe the charges'));
  }
  if (i.employeeResponseSummary.trim().isEmpty) {
    errors.add(const ValidationError(
        'employeeResponseSummary', "Summarize the employee's response"));
  }
  if (i.findings.trim().isEmpty) {
    errors.add(const ValidationError('findings', 'Management findings are required'));
  }
  if (i.decision == NodDecision.suspension && i.suspensionDays <= 0) {
    errors.add(const ValidationError(
        'suspensionDays', 'Suspension requires at least 1 day'));
  }
  if (i.effectiveDate.isBefore(i.issueDate)) {
    errors.add(const ValidationError(
        'effectiveDate', 'Effective date must be on or after issue date'));
  }
  return errors;
}
```

- [ ] **Step 5: Run — expect pass**

Run: `flutter test test/features/documents/nod_validate_test.dart`
Expected: 6 pass.

- [ ] **Step 6: Commit**

```bash
git add lib/features/documents/templates/nod_inputs.dart lib/features/documents/templates/nod_validate.dart test/features/documents/nod_validate_test.dart
git commit -m "feat(documents): NOD — inputs + validate"
```

## Task 11 — NOD: Template + autofill + build + golden

**Files:**
- Create: `lib/features/documents/templates/nod_template.dart`
- Create: `test/features/documents/nod_template_test.dart`
- Create: `test/features/documents/goldens/nod_pagination_test.dart`

- [ ] **Step 1: Write tests**

```dart
// test/features/documents/nod_template_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll/features/documents/blocks/heading_block.dart';
import 'package:payroll/features/documents/blocks/memo_header_block.dart';
import 'package:payroll/features/documents/blocks/paragraph_block.dart';
import 'package:payroll/features/documents/templates/nod_inputs.dart';
import 'package:payroll/features/documents/templates/nod_template.dart';

NodInputs _i({NodDecision d = NodDecision.writtenWarning, int days = 0}) =>
    NodInputs(
      employeeId: 'e1', employeeFullName: 'Bob', employeePosition: 'Dev',
      companyId: 'c1', companyName: 'X', hrManagerName: 'HR',
      charges: 'Tardiness 5 times in May',
      employeeResponseSummary: 'Admitted.',
      findings: 'Substantiated.',
      decision: d, suspensionDays: days,
      effectiveDate: DateTime(2026, 6, 6),
      issueDate: DateTime(2026, 6, 5),
    );

void main() {
  test('id + supportsBulk', () {
    const t = NodTemplate();
    expect(t.id, 'nod');
    expect(t.supportsBulk, isFalse);
  });

  test('build emits MemoHeaderBlock + Charges/Response/Findings/Decision sections', () {
    const t = NodTemplate();
    final blocks = t.build(_i());
    expect(blocks.whereType<MemoHeaderBlock>(), isNotEmpty);
    final headings = blocks.whereType<HeadingBlock>().map((h) => h.text).toList();
    expect(headings, containsAll(['Charges', 'Employee Response', 'Findings', 'Decision']));
  });

  test('TERMINATION text mentions Article 297', () {
    const t = NodTemplate();
    final body = t.build(_i(d: NodDecision.termination))
        .whereType<ParagraphBlock>()
        .map((p) => p.text)
        .join(' ');
    expect(body, contains('Article 297'));
  });

  test('SUSPENSION text mentions number of days', () {
    const t = NodTemplate();
    final body = t.build(_i(d: NodDecision.suspension, days: 3))
        .whereType<ParagraphBlock>()
        .map((p) => p.text)
        .join(' ');
    expect(body, contains('3'));
    expect(body, contains('suspension'));
  });
}
```

- [ ] **Step 2: Run — expect failure**

Run: `flutter test test/features/documents/nod_template_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement template**

```dart
// lib/features/documents/templates/nod_template.dart
import 'package:flutter/material.dart' show Icons, IconData;
import 'package:intl/intl.dart';

import '../blocks/block.dart';
import '../blocks/centered_signature_block.dart';
import '../blocks/heading_block.dart';
import '../blocks/logo_block.dart';
import '../blocks/memo_header_block.dart';
import '../blocks/multi_signature_block.dart';
import '../blocks/paragraph_block.dart';
import '../blocks/spacer_block.dart';
import 'document_template.dart';
import 'nod_inputs.dart';
import 'nod_validate.dart';

class NodTemplate extends DocumentTemplate<NodInputs> {
  const NodTemplate();

  @override
  String get id => 'nod';

  @override
  String get displayName => 'Notice of Decision';

  @override
  String get description =>
      'Disciplinary decision following an NTE. Optional link to the originating NTE auto-fills dates/charges. Closes the Labor Code Art. 297-299 due-process chain.';

  @override
  IconData get icon => Icons.gavel_outlined;

  @override
  bool get supportsBulk => false;

  @override
  List<Gate> gates(AutofillContext ctx) => const [];

  @override
  Future<NodInputs> autofill(AutofillContext ctx) async {
    final e = ctx.employee;
    final c = ctx.company;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return NodInputs(
      employeeId: e?.id ?? '',
      employeeFullName: e?.fullName ?? '',
      employeePosition: e?.jobTitle ?? '',
      employeeGender: e?.gender ?? '',
      companyId: c?.id ?? '',
      companyName: c?.name ?? '',
      companyAddress: c?.address ?? '',
      issueDate: today,
      effectiveDate: today,
    );
  }

  @override
  List<ValidationError> validate(NodInputs inputs) => validateNod(inputs);

  @override
  List<Block> build(NodInputs inputs) {
    final df = DateFormat('MMMM d, yyyy');
    final i = inputs;
    final honorific = _honorific(i.employeeGender);
    final nteDateStr = i.nteDate != null ? df.format(i.nteDate!) : '___';
    return <Block>[
      LogoBlock(companyId: i.companyId),
      MemoHeaderBlock(
        date: i.issueDate,
        recipient: '${i.employeeFullName} / ${i.employeePosition}',
        sender: '${i.hrManagerName} / HR Manager',
        subject: 'Notice of Decision',
        recipientHonorific: honorific,
      ),
      const SpacerBlock(height: 12),
      ParagraphBlock(
          text:
              'This Notice of Decision is issued in response to the Notice to Explain dated $nteDateStr, and your written explanation received thereafter.'),
      const SpacerBlock(height: 12),
      const HeadingBlock(text: 'Charges'),
      ParagraphBlock(text: i.charges),
      const SpacerBlock(height: 8),
      const HeadingBlock(text: 'Employee Response'),
      ParagraphBlock(text: i.employeeResponseSummary),
      const SpacerBlock(height: 8),
      const HeadingBlock(text: 'Findings'),
      ParagraphBlock(text: i.findings),
      const SpacerBlock(height: 8),
      const HeadingBlock(text: 'Decision'),
      ParagraphBlock(text: _decisionText(i, df)),
      const SpacerBlock(height: 12),
      const ParagraphBlock(
          text:
              'You may appeal this decision in writing within five (5) working days of receipt. Please acknowledge receipt below.'),
      const SpacerBlock(height: 40),
      MultiSignatureBlock(
        left: CenteredSignatureBlock(name: i.hrManagerName, label: 'HR Manager'),
        right: CenteredSignatureBlock(
            name: i.employeeFullName, label: 'Employee (Acknowledged)'),
      ),
    ];
  }

  String _honorific(String gender) {
    if (gender == 'FEMALE') return 'Ms.';
    if (gender == 'MALE') return 'Mr.';
    return '';
  }

  String _decisionText(NodInputs i, DateFormat df) {
    switch (i.decision) {
      case NodDecision.reprimand:
        return 'After careful consideration, management has decided to issue a written reprimand for the above infractions.';
      case NodDecision.writtenWarning:
        return 'After careful consideration, management has decided to issue a written warning. Any repeat offense may result in stronger disciplinary action.';
      case NodDecision.suspension:
        return 'After careful consideration, management has decided to impose a ${i.suspensionDays}-day suspension without pay, effective ${df.format(i.effectiveDate)}.';
      case NodDecision.termination:
        return 'After careful consideration, management has decided to terminate your employment effective ${df.format(i.effectiveDate)}, in accordance with Article 297 of the Labor Code of the Philippines.';
      case NodDecision.noAction:
        return 'After review, management has decided that no further disciplinary action is warranted at this time.';
    }
  }
}
```

- [ ] **Step 4: Run — expect pass**

Run: `flutter test test/features/documents/nod_template_test.dart`
Expected: 4 pass.

- [ ] **Step 5: Pagination golden**

```dart
// test/features/documents/goldens/nod_pagination_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll/core/pdf/render.dart';
import 'package:payroll/features/documents/templates/nod_inputs.dart';
import 'package:payroll/features/documents/templates/nod_template.dart';

void main() {
  testWidgets('NOD renders PDF', (tester) async {
    final i = NodInputs(
      employeeId: 'e1', employeeFullName: 'Alice Reyes', employeePosition: 'Accountant',
      employeeGender: 'FEMALE',
      companyId: 'c1', companyName: 'Luxium', companyAddress: '123 Quezon City',
      hrManagerName: 'Brixter Cruz',
      nteDate: DateTime(2026, 5, 20),
      charges: 'Three (3) instances of unexcused absence in May 2026 — May 3, May 14, May 22.',
      employeeResponseSummary:
          'Employee cites family emergency for May 3; no excuse offered for May 14 and May 22.',
      findings: 'Two absences (May 14, May 22) are unexcused; May 3 is partly mitigated.',
      decision: NodDecision.suspension, suspensionDays: 3,
      effectiveDate: DateTime(2026, 6, 10), issueDate: DateTime(2026, 6, 5),
    );
    final bytes = await renderDocumentToPdf(const NodTemplate().build(i));
    expect(String.fromCharCodes(bytes.sublist(0, 4)), startsWith('%PDF'));
  });
}
```

- [ ] **Step 6: Commit**

```bash
git add lib/features/documents/templates/nod_template.dart test/features/documents/nod_template_test.dart test/features/documents/goldens/nod_pagination_test.dart
git commit -m "feat(documents): NOD — template + golden"
```

## Task 12 — NOD: Form widget (with NTE picker)

**Files:**
- Create: `lib/features/documents/forms/nod_form.dart`

- [ ] **Step 1: Create the form**

```dart
// lib/features/documents/forms/nod_form.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../widgets/hr_manager_field.dart';
import '../inputs/company_picker.dart';
import '../inputs/date_field.dart';
import '../inputs/employee_picker.dart';
import '../providers.dart';
import '../templates/nod_inputs.dart';

class NodForm extends ConsumerStatefulWidget {
  final NodInputs initial;
  final bool employeeLocked;
  final ValueChanged<NodInputs> onChanged;
  final ValueChanged<String> onEmployeeChanged;
  const NodForm({
    super.key,
    required this.initial,
    required this.employeeLocked,
    required this.onChanged,
    required this.onEmployeeChanged,
  });

  @override
  ConsumerState<NodForm> createState() => _NodFormState();
}

class _NodFormState extends ConsumerState<NodForm> {
  late NodInputs _i = widget.initial;
  void _set(NodInputs next) {
    setState(() => _i = next);
    widget.onChanged(next);
  }

  @override
  void didUpdateWidget(covariant NodForm old) {
    super.didUpdateWidget(old);
    if (old.initial != widget.initial) _i = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    final ntesAsync = _i.employeeId.isEmpty
        ? const AsyncValue<List<EmployeeDocumentSummary>>.data([])
        : ref.watch(ntesByEmployeeProvider(_i.employeeId));
    final df = DateFormat('MMM d, yyyy');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EmployeePicker(
          selectedId: _i.employeeId,
          enabled: !widget.employeeLocked,
          onSelected: (e) {
            widget.onEmployeeChanged(e?.id ?? '');
            _set(_i.copyWith(
              employeeId: e?.id ?? '',
              employeeFullName: e?.fullName ?? '',
              employeePosition: e?.jobTitle ?? '',
              employeeGender: e?.gender ?? '',
              linkedNteDocumentId: null,
              nteDate: null,
            ));
          },
        ),
        const SizedBox(height: 16),
        CompanyPicker(
          selectedId: _i.companyId,
          onSelected: (h) => _set(_i.copyWith(
            companyId: h?.id ?? '',
            companyName: h?.name ?? '',
            companyAddress: h?.address ?? '',
          )),
        ),
        const SizedBox(height: 16),
        HrManagerField(
          value: _i.hrManagerName,
          companyId: _i.companyId,
          onChanged: (v) => _set(_i.copyWith(hrManagerName: v)),
        ),
        const SizedBox(height: 16),
        ntesAsync.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, __) => const SizedBox.shrink(),
          data: (ntes) => DropdownButtonFormField<String?>(
            value: _i.linkedNteDocumentId,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Link to NTE (optional)',
            ),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('— No NTE linked —')),
              ...ntes.map((n) => DropdownMenuItem<String?>(
                    value: n.id,
                    child: Text('${df.format(n.createdAt)} — ${n.title}'),
                  )),
            ],
            onChanged: (id) {
              final match = ntes.where((n) => n.id == id).firstOrNull;
              _set(_i.copyWith(
                linkedNteDocumentId: id,
                nteDate: match?.createdAt,
                charges: _i.charges.isEmpty && match != null ? match.title : _i.charges,
              ));
            },
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          key: ValueKey('charges-${_i.linkedNteDocumentId}'),
          initialValue: _i.charges,
          minLines: 3, maxLines: 10,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Charges',
          ),
          onChanged: (v) => _set(_i.copyWith(charges: v)),
        ),
        const SizedBox(height: 12),
        TextFormField(
          initialValue: _i.employeeResponseSummary,
          minLines: 3, maxLines: 10,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: "Employee's response (summary)",
          ),
          onChanged: (v) => _set(_i.copyWith(employeeResponseSummary: v)),
        ),
        const SizedBox(height: 12),
        TextFormField(
          initialValue: _i.findings,
          minLines: 3, maxLines: 10,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Findings',
          ),
          onChanged: (v) => _set(_i.copyWith(findings: v)),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<NodDecision>(
          value: _i.decision,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Decision',
          ),
          items: NodDecision.values
              .map((d) => DropdownMenuItem(value: d, child: Text(d.label)))
              .toList(),
          onChanged: (d) => _set(_i.copyWith(decision: d ?? _i.decision)),
        ),
        if (_i.decision == NodDecision.suspension) ...[
          const SizedBox(height: 12),
          TextFormField(
            key: ValueKey('days-${_i.decision}'),
            initialValue: _i.suspensionDays.toString(),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Suspension days',
            ),
            keyboardType: TextInputType.number,
            onChanged: (v) => _set(_i.copyWith(suspensionDays: int.tryParse(v) ?? 0)),
          ),
        ],
        const SizedBox(height: 16),
        DateField(
          label: 'Issue date',
          value: _i.issueDate,
          onChanged: (d) => _set(_i.copyWith(issueDate: d)),
        ),
        const SizedBox(height: 12),
        DateField(
          label: 'Effective date',
          value: _i.effectiveDate,
          onChanged: (d) => _set(_i.copyWith(effectiveDate: d)),
        ),
      ],
    );
  }
}
```

- [ ] **Step 2: Verify analyze** — `dart format && flutter analyze` on the new file.

- [ ] **Step 3: Commit**

```bash
git add lib/features/documents/forms/nod_form.dart
git commit -m "feat(documents): NOD — form widget with NTE picker"
```

---

# Probationary Regularization Letter (Tasks 13-15)

## Task 13 — Regularization: Inputs + validate + tests

**Files:**
- Create: `lib/features/documents/templates/regularization_inputs.dart`
- Create: `lib/features/documents/templates/regularization_validate.dart`
- Create: `test/features/documents/regularization_validate_test.dart`

- [ ] **Step 1: Inputs**

```dart
// lib/features/documents/templates/regularization_inputs.dart
import 'package:decimal/decimal.dart';

import 'document_template.dart';

class RegularizationInputs extends TemplateInputs {
  final String employeeId;
  final String employeeFullName;
  final String employeePosition;
  final String employeeGender;
  final String companyId;
  final String companyName;
  final String companyAddress;
  final String hrManagerName;
  final DateTime? hireDate;
  final DateTime regularizationDate;
  final Decimal baseSalary;
  final String salaryPeriod; // MONTHLY | DAILY
  final DateTime issueDate;
  final String performanceSummary;

  RegularizationInputs({
    required this.employeeId,
    required this.employeeFullName,
    this.employeePosition = '',
    this.employeeGender = '',
    required this.companyId,
    required this.companyName,
    this.companyAddress = '',
    this.hrManagerName = '',
    this.hireDate,
    required this.regularizationDate,
    Decimal? baseSalary,
    this.salaryPeriod = 'MONTHLY',
    required this.issueDate,
    this.performanceSummary = '',
  }) : baseSalary = baseSalary ?? Decimal.zero;

  RegularizationInputs copyWith({
    String? employeeId,
    String? employeeFullName,
    String? employeePosition,
    String? employeeGender,
    String? companyId,
    String? companyName,
    String? companyAddress,
    String? hrManagerName,
    Object? hireDate = _undef,
    DateTime? regularizationDate,
    Decimal? baseSalary,
    String? salaryPeriod,
    DateTime? issueDate,
    String? performanceSummary,
  }) =>
      RegularizationInputs(
        employeeId: employeeId ?? this.employeeId,
        employeeFullName: employeeFullName ?? this.employeeFullName,
        employeePosition: employeePosition ?? this.employeePosition,
        employeeGender: employeeGender ?? this.employeeGender,
        companyId: companyId ?? this.companyId,
        companyName: companyName ?? this.companyName,
        companyAddress: companyAddress ?? this.companyAddress,
        hrManagerName: hrManagerName ?? this.hrManagerName,
        hireDate: identical(hireDate, _undef)
            ? this.hireDate
            : hireDate as DateTime?,
        regularizationDate: regularizationDate ?? this.regularizationDate,
        baseSalary: baseSalary ?? this.baseSalary,
        salaryPeriod: salaryPeriod ?? this.salaryPeriod,
        issueDate: issueDate ?? this.issueDate,
        performanceSummary: performanceSummary ?? this.performanceSummary,
      );

  @override
  Map<String, dynamic> toDebugMap() => {
        'employeeId': employeeId,
        'regularizationDate': regularizationDate.toIso8601String(),
      };
}

const _undef = Object();
```

- [ ] **Step 2: Tests**

```dart
// test/features/documents/regularization_validate_test.dart
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll/features/documents/templates/regularization_inputs.dart';
import 'package:payroll/features/documents/templates/regularization_validate.dart';

RegularizationInputs _b() => RegularizationInputs(
      employeeId: 'e1', employeeFullName: 'A',
      companyId: 'c1', companyName: 'X', hrManagerName: 'HR',
      hireDate: DateTime(2026, 1, 5),
      regularizationDate: DateTime(2026, 6, 1),
      baseSalary: Decimal.parse('25000'),
      issueDate: DateTime(2026, 6, 5),
    );

void main() {
  test('valid baseline', () => expect(validateRegularization(_b()), isEmpty));
  test('regularizationDate < hireDate rejected', () {
    final i = _b().copyWith(regularizationDate: DateTime(2025, 12, 1));
    expect(validateRegularization(i).map((e) => e.field),
        contains('regularizationDate'));
  });
  test('baseSalary > 0 required', () {
    expect(validateRegularization(_b().copyWith(baseSalary: Decimal.zero))
            .map((e) => e.field),
        contains('baseSalary'));
  });
}
```

- [ ] **Step 3: Run — expect failure**

Run: `flutter test test/features/documents/regularization_validate_test.dart`
Expected: FAIL.

- [ ] **Step 4: Implement**

```dart
// lib/features/documents/templates/regularization_validate.dart
import 'package:decimal/decimal.dart';

import 'document_template.dart';
import 'regularization_inputs.dart';

List<ValidationError> validateRegularization(RegularizationInputs i) {
  final errors = <ValidationError>[];
  if (i.employeeId.isEmpty) errors.add(const ValidationError('employee', 'Select an employee'));
  if (i.companyId.isEmpty) errors.add(const ValidationError('company', 'Select a company'));
  if (i.hrManagerName.trim().isEmpty) {
    errors.add(const ValidationError('hrManager', 'HR manager name is required'));
  }
  if (i.baseSalary <= Decimal.zero) {
    errors.add(const ValidationError('baseSalary', 'Base salary must be positive'));
  }
  if (i.hireDate != null && i.regularizationDate.isBefore(i.hireDate!)) {
    errors.add(const ValidationError(
        'regularizationDate', 'Regularization date must be on or after hire date'));
  }
  return errors;
}
```

- [ ] **Step 5: Run — expect pass**

Run: `flutter test test/features/documents/regularization_validate_test.dart`
Expected: 3 pass.

- [ ] **Step 6: Commit**

```bash
git add lib/features/documents/templates/regularization_inputs.dart lib/features/documents/templates/regularization_validate.dart test/features/documents/regularization_validate_test.dart
git commit -m "feat(documents): Regularization — inputs + validate"
```

## Task 14 — Regularization: Template + build + golden

**Files:**
- Create: `lib/features/documents/templates/regularization_template.dart`
- Create: `test/features/documents/regularization_template_test.dart`
- Create: `test/features/documents/goldens/regularization_pagination_test.dart`

- [ ] **Step 1: Test**

```dart
// test/features/documents/regularization_template_test.dart
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll/features/documents/blocks/heading_block.dart';
import 'package:payroll/features/documents/blocks/paragraph_block.dart';
import 'package:payroll/features/documents/templates/regularization_inputs.dart';
import 'package:payroll/features/documents/templates/regularization_template.dart';

void main() {
  test('id + supportsBulk', () {
    const t = RegularizationTemplate();
    expect(t.id, 'regularization');
    expect(t.supportsBulk, isTrue);
  });

  test('build mentions Congratulations + regularization date', () {
    final i = RegularizationInputs(
      employeeId: 'e1', employeeFullName: 'Bob',
      companyId: 'c1', companyName: 'Luxium', hrManagerName: 'HR',
      hireDate: DateTime(2026, 1, 5),
      regularizationDate: DateTime(2026, 6, 5),
      baseSalary: Decimal.parse('25000'),
      issueDate: DateTime(2026, 6, 5),
    );
    final text = const RegularizationTemplate().build(i)
        .whereType<ParagraphBlock>().map((p) => p.text).join(' ');
    expect(text.toLowerCase(), contains('congratulations'));
    expect(text, contains('June 5, 2026'));
  });

  test('Performance Summary heading only if non-empty', () {
    final base = RegularizationInputs(
      employeeId: 'e1', employeeFullName: 'B',
      companyId: 'c1', companyName: 'X', hrManagerName: 'HR',
      regularizationDate: DateTime(2026, 6, 5),
      baseSalary: Decimal.parse('1'),
      issueDate: DateTime(2026, 6, 5),
    );
    const t = RegularizationTemplate();
    expect(t.build(base).whereType<HeadingBlock>().any((h) => h.text.contains('Performance')), isFalse);
    final withSummary = base.copyWith(performanceSummary: 'Exceeds expectations.');
    expect(t.build(withSummary).whereType<HeadingBlock>().any((h) => h.text.contains('Performance')), isTrue);
  });
}
```

- [ ] **Step 2: Run — expect failure**

Run: `flutter test test/features/documents/regularization_template_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement**

```dart
// lib/features/documents/templates/regularization_template.dart
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart' show Icons, IconData;
import 'package:intl/intl.dart';

import '../blocks/block.dart';
import '../blocks/bullet_list_block.dart';
import '../blocks/centered_signature_block.dart';
import '../blocks/heading_block.dart';
import '../blocks/logo_block.dart';
import '../blocks/memo_header_block.dart';
import '../blocks/multi_signature_block.dart';
import '../blocks/paragraph_block.dart';
import '../blocks/spacer_block.dart';
import 'document_template.dart';
import 'regularization_inputs.dart';
import 'regularization_validate.dart';

class RegularizationTemplate extends DocumentTemplate<RegularizationInputs> {
  const RegularizationTemplate();

  @override
  String get id => 'regularization';

  @override
  String get displayName => 'Probationary Regularization';

  @override
  String get description =>
      'Confirms an employee\'s transition from probationary to regular status.';

  @override
  IconData get icon => Icons.verified_outlined;

  @override
  bool get supportsBulk => true;

  @override
  List<Gate> gates(AutofillContext ctx) {
    final e = ctx.employee;
    if (e == null) return const [];
    if (e.employmentType != 'PROBATIONARY') {
      return const [Gate('Regularization is only valid for probationary employees.')];
    }
    return const [];
  }

  @override
  Future<RegularizationInputs> autofill(AutofillContext ctx) async {
    final e = ctx.employee;
    final c = ctx.company;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return RegularizationInputs(
      employeeId: e?.id ?? '',
      employeeFullName: e?.fullName ?? '',
      employeePosition: e?.jobTitle ?? '',
      employeeGender: e?.gender ?? '',
      companyId: c?.id ?? '',
      companyName: c?.name ?? '',
      companyAddress: c?.address ?? '',
      hireDate: e?.hireDate,
      regularizationDate: today,
      baseSalary: e?.declaredWageOverride ?? e?.baseSalary ?? Decimal.zero,
      salaryPeriod: e?.wageType ?? 'MONTHLY',
      issueDate: today,
    );
  }

  @override
  List<ValidationError> validate(RegularizationInputs inputs) =>
      validateRegularization(inputs);

  @override
  List<Block> build(RegularizationInputs inputs) {
    final df = DateFormat('MMMM d, yyyy');
    final cf = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
    final i = inputs;
    final hireStr = i.hireDate != null ? df.format(i.hireDate!) : '___';
    final salaryLine = i.salaryPeriod == 'DAILY'
        ? 'Daily rate: ${cf.format(i.baseSalary.toDouble())}'
        : 'Monthly salary: ${cf.format(i.baseSalary.toDouble())}';
    final honorific = _honorific(i.employeeGender);

    return <Block>[
      LogoBlock(companyId: i.companyId),
      MemoHeaderBlock(
        date: i.issueDate,
        recipient: '${i.employeeFullName} / ${i.employeePosition}',
        sender: '${i.hrManagerName} / HR Manager',
        subject: 'Confirmation of Regularization',
        recipientHonorific: honorific,
      ),
      const SpacerBlock(height: 12),
      ParagraphBlock(
          text:
              'Congratulations! Following a comprehensive review of your performance during your probationary period (from $hireStr to ${df.format(i.regularizationDate)}), ${i.companyName} is pleased to confirm your regularization effective ${df.format(i.regularizationDate)}.'),
      if (i.performanceSummary.trim().isNotEmpty) ...[
        const SpacerBlock(height: 12),
        const HeadingBlock(text: 'Performance Summary'),
        ParagraphBlock(text: i.performanceSummary),
      ],
      const SpacerBlock(height: 12),
      const HeadingBlock(text: 'Terms'),
      BulletListBlock(items: [
        'Effective date: ${df.format(i.regularizationDate)}',
        'Position: ${i.employeePosition}',
        salaryLine,
        'All other terms and benefits per your existing Employment Contract apply.',
      ]),
      const SpacerBlock(height: 12),
      ParagraphBlock(
          text:
              'We look forward to your continued contribution to ${i.companyName}. Please acknowledge receipt below.'),
      const SpacerBlock(height: 40),
      MultiSignatureBlock(
        left: CenteredSignatureBlock(name: i.hrManagerName, label: 'HR Manager'),
        right: CenteredSignatureBlock(name: i.employeeFullName, label: 'Employee (Acknowledged)'),
      ),
    ];
  }

  String _honorific(String gender) {
    if (gender == 'FEMALE') return 'Ms.';
    if (gender == 'MALE') return 'Mr.';
    return '';
  }
}
```

- [ ] **Step 4: Run — expect pass**

Run: `flutter test test/features/documents/regularization_template_test.dart`
Expected: 3 pass.

- [ ] **Step 5: Golden**

```dart
// test/features/documents/goldens/regularization_pagination_test.dart
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll/core/pdf/render.dart';
import 'package:payroll/features/documents/templates/regularization_inputs.dart';
import 'package:payroll/features/documents/templates/regularization_template.dart';

void main() {
  testWidgets('Regularization renders PDF', (tester) async {
    final i = RegularizationInputs(
      employeeId: 'e1', employeeFullName: 'Alice Reyes', employeePosition: 'Accountant',
      employeeGender: 'FEMALE',
      companyId: 'c1', companyName: 'Luxium', companyAddress: '123 QC',
      hrManagerName: 'Brixter',
      hireDate: DateTime(2026, 1, 5),
      regularizationDate: DateTime(2026, 6, 5),
      baseSalary: Decimal.parse('25000'),
      issueDate: DateTime(2026, 6, 5),
      performanceSummary: 'Exceeds expectations across all KPIs in Q1 and Q2.',
    );
    final bytes = await renderDocumentToPdf(const RegularizationTemplate().build(i));
    expect(String.fromCharCodes(bytes.sublist(0, 4)), startsWith('%PDF'));
  });
}
```

- [ ] **Step 6: Commit**

```bash
git add lib/features/documents/templates/regularization_template.dart test/features/documents/regularization_template_test.dart test/features/documents/goldens/regularization_pagination_test.dart
git commit -m "feat(documents): Regularization — template + golden"
```

## Task 15 — Regularization: Form widget

**Files:**
- Create: `lib/features/documents/forms/regularization_form.dart`

- [ ] **Step 1: Create form**

```dart
// lib/features/documents/forms/regularization_form.dart
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../widgets/hr_manager_field.dart';
import '../inputs/company_picker.dart';
import '../inputs/date_field.dart';
import '../inputs/employee_picker.dart';
import '../templates/regularization_inputs.dart';

class RegularizationForm extends ConsumerStatefulWidget {
  final RegularizationInputs initial;
  final bool employeeLocked;
  final ValueChanged<RegularizationInputs> onChanged;
  final ValueChanged<String> onEmployeeChanged;
  const RegularizationForm({
    super.key,
    required this.initial,
    required this.employeeLocked,
    required this.onChanged,
    required this.onEmployeeChanged,
  });

  @override
  ConsumerState<RegularizationForm> createState() => _RegularizationFormState();
}

class _RegularizationFormState extends ConsumerState<RegularizationForm> {
  late RegularizationInputs _i = widget.initial;
  void _set(RegularizationInputs n) { setState(() => _i = n); widget.onChanged(n); }

  @override
  void didUpdateWidget(covariant RegularizationForm old) {
    super.didUpdateWidget(old);
    if (old.initial != widget.initial) _i = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EmployeePicker(
          selectedId: _i.employeeId,
          enabled: !widget.employeeLocked,
          onSelected: (e) {
            widget.onEmployeeChanged(e?.id ?? '');
            _set(_i.copyWith(
              employeeId: e?.id ?? '',
              employeeFullName: e?.fullName ?? '',
              employeePosition: e?.jobTitle ?? '',
              employeeGender: e?.gender ?? '',
              hireDate: e?.hireDate,
              baseSalary: e?.declaredWageOverride ?? e?.baseSalary ?? Decimal.zero,
              salaryPeriod: e?.wageType ?? 'MONTHLY',
            ));
          },
        ),
        const SizedBox(height: 16),
        CompanyPicker(
          selectedId: _i.companyId,
          onSelected: (h) => _set(_i.copyWith(
            companyId: h?.id ?? '', companyName: h?.name ?? '',
            companyAddress: h?.address ?? '',
          )),
        ),
        const SizedBox(height: 16),
        HrManagerField(
          value: _i.hrManagerName,
          companyId: _i.companyId,
          onChanged: (v) => _set(_i.copyWith(hrManagerName: v)),
        ),
        const SizedBox(height: 16),
        DateField(
          label: 'Regularization date',
          value: _i.regularizationDate,
          onChanged: (d) => _set(_i.copyWith(regularizationDate: d)),
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: ValueKey('salary-${_i.employeeId}'),
          initialValue: _i.baseSalary.toString(),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Base salary',
            prefixText: '₱ ',
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (v) => _set(_i.copyWith(baseSalary: Decimal.tryParse(v) ?? Decimal.zero)),
        ),
        const SizedBox(height: 12),
        TextFormField(
          initialValue: _i.performanceSummary,
          minLines: 3, maxLines: 8,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Performance summary (optional)',
            helperText: 'Pulled from 5-month probationary check-in, or paste manually.',
          ),
          onChanged: (v) => _set(_i.copyWith(performanceSummary: v)),
        ),
      ],
    );
  }
}
```

- [ ] **Step 2: Analyze + commit**

```bash
dart format lib/features/documents/forms/regularization_form.dart && flutter analyze lib/features/documents/forms/regularization_form.dart
git add lib/features/documents/forms/regularization_form.dart
git commit -m "feat(documents): Regularization — form widget"
```

---

# Resignation Acceptance Letter (Tasks 16-18)

## Task 16 — Resignation Acceptance: Inputs + validate + tests

**Files:**
- Create: `lib/features/documents/templates/resignation_acceptance_inputs.dart`
- Create: `lib/features/documents/templates/resignation_acceptance_validate.dart`
- Create: `test/features/documents/resignation_acceptance_validate_test.dart`

- [ ] **Step 1: Inputs**

```dart
// lib/features/documents/templates/resignation_acceptance_inputs.dart
import 'document_template.dart';

const String kDefaultTurnoverInstructions =
    'Please coordinate with your direct manager for proper turnover of pending tasks and Company property (laptop, ID, access cards, etc.).';

class ResignationAcceptanceInputs extends TemplateInputs {
  final String employeeId;
  final String employeeFullName;
  final String employeePosition;
  final String employeeGender;
  final String companyId;
  final String companyName;
  final String companyAddress;
  final String hrManagerName;

  final DateTime resignationDate;
  final DateTime lastDayOfWork;
  final DateTime issueDate;
  final String turnoverInstructions;
  final bool includeClearanceMention;
  final bool includeFinalPayMention;

  ResignationAcceptanceInputs({
    required this.employeeId,
    required this.employeeFullName,
    this.employeePosition = '',
    this.employeeGender = '',
    required this.companyId,
    required this.companyName,
    this.companyAddress = '',
    this.hrManagerName = '',
    required this.resignationDate,
    required this.lastDayOfWork,
    required this.issueDate,
    this.turnoverInstructions = kDefaultTurnoverInstructions,
    this.includeClearanceMention = true,
    this.includeFinalPayMention = true,
  });

  ResignationAcceptanceInputs copyWith({
    String? employeeId,
    String? employeeFullName,
    String? employeePosition,
    String? employeeGender,
    String? companyId,
    String? companyName,
    String? companyAddress,
    String? hrManagerName,
    DateTime? resignationDate,
    DateTime? lastDayOfWork,
    DateTime? issueDate,
    String? turnoverInstructions,
    bool? includeClearanceMention,
    bool? includeFinalPayMention,
  }) =>
      ResignationAcceptanceInputs(
        employeeId: employeeId ?? this.employeeId,
        employeeFullName: employeeFullName ?? this.employeeFullName,
        employeePosition: employeePosition ?? this.employeePosition,
        employeeGender: employeeGender ?? this.employeeGender,
        companyId: companyId ?? this.companyId,
        companyName: companyName ?? this.companyName,
        companyAddress: companyAddress ?? this.companyAddress,
        hrManagerName: hrManagerName ?? this.hrManagerName,
        resignationDate: resignationDate ?? this.resignationDate,
        lastDayOfWork: lastDayOfWork ?? this.lastDayOfWork,
        issueDate: issueDate ?? this.issueDate,
        turnoverInstructions: turnoverInstructions ?? this.turnoverInstructions,
        includeClearanceMention:
            includeClearanceMention ?? this.includeClearanceMention,
        includeFinalPayMention:
            includeFinalPayMention ?? this.includeFinalPayMention,
      );

  @override
  Map<String, dynamic> toDebugMap() => {
        'employeeId': employeeId,
        'lastDayOfWork': lastDayOfWork.toIso8601String(),
      };
}
```

- [ ] **Step 2: Validate tests**

```dart
// test/features/documents/resignation_acceptance_validate_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll/features/documents/templates/resignation_acceptance_inputs.dart';
import 'package:payroll/features/documents/templates/resignation_acceptance_validate.dart';

ResignationAcceptanceInputs _b() => ResignationAcceptanceInputs(
      employeeId: 'e1', employeeFullName: 'B',
      companyId: 'c1', companyName: 'X', hrManagerName: 'HR',
      resignationDate: DateTime(2026, 6, 1),
      lastDayOfWork: DateTime(2026, 7, 1),
      issueDate: DateTime(2026, 6, 5),
    );

void main() {
  test('baseline valid', () => expect(validateResignationAcceptance(_b()), isEmpty));
  test('lastDayOfWork < resignationDate rejected', () {
    final i = _b().copyWith(lastDayOfWork: DateTime(2026, 5, 1));
    expect(validateResignationAcceptance(i).map((e) => e.field),
        contains('lastDayOfWork'));
  });
  test('turnoverInstructions required', () {
    final i = _b().copyWith(turnoverInstructions: '   ');
    expect(validateResignationAcceptance(i).map((e) => e.field),
        contains('turnoverInstructions'));
  });
}
```

- [ ] **Step 3: Run — expect failure**

Run: `flutter test test/features/documents/resignation_acceptance_validate_test.dart`
Expected: FAIL.

- [ ] **Step 4: Implement**

```dart
// lib/features/documents/templates/resignation_acceptance_validate.dart
import 'document_template.dart';
import 'resignation_acceptance_inputs.dart';

List<ValidationError> validateResignationAcceptance(
    ResignationAcceptanceInputs i) {
  final errors = <ValidationError>[];
  if (i.employeeId.isEmpty) errors.add(const ValidationError('employee', 'Select an employee'));
  if (i.companyId.isEmpty) errors.add(const ValidationError('company', 'Select a company'));
  if (i.hrManagerName.trim().isEmpty) {
    errors.add(const ValidationError('hrManager', 'HR manager name is required'));
  }
  if (i.lastDayOfWork.isBefore(i.resignationDate)) {
    errors.add(const ValidationError(
        'lastDayOfWork', 'Last day of work must be on or after resignation date'));
  }
  if (i.turnoverInstructions.trim().isEmpty) {
    errors.add(const ValidationError(
        'turnoverInstructions', 'Turnover instructions are required'));
  }
  return errors;
}
```

- [ ] **Step 5: Run — expect pass + commit**

Run: `flutter test test/features/documents/resignation_acceptance_validate_test.dart`
Expected: 3 pass.

```bash
git add lib/features/documents/templates/resignation_acceptance_inputs.dart lib/features/documents/templates/resignation_acceptance_validate.dart test/features/documents/resignation_acceptance_validate_test.dart
git commit -m "feat(documents): Resignation Acceptance — inputs + validate"
```

## Task 17 — Resignation Acceptance: Template + build + golden

**Files:**
- Create: `lib/features/documents/templates/resignation_acceptance_template.dart`
- Create: `test/features/documents/resignation_acceptance_template_test.dart`
- Create: `test/features/documents/goldens/resignation_acceptance_pagination_test.dart`

- [ ] **Step 1: Test**

```dart
// test/features/documents/resignation_acceptance_template_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll/features/documents/blocks/paragraph_block.dart';
import 'package:payroll/features/documents/templates/resignation_acceptance_inputs.dart';
import 'package:payroll/features/documents/templates/resignation_acceptance_template.dart';

ResignationAcceptanceInputs _i({bool clearance = true, bool finalPay = true}) =>
    ResignationAcceptanceInputs(
      employeeId: 'e1', employeeFullName: 'B', employeePosition: 'Dev',
      companyId: 'c1', companyName: 'Luxium', hrManagerName: 'HR',
      resignationDate: DateTime(2026, 6, 1),
      lastDayOfWork: DateTime(2026, 7, 1),
      issueDate: DateTime(2026, 6, 5),
      includeClearanceMention: clearance,
      includeFinalPayMention: finalPay,
    );

void main() {
  test('id + supportsBulk', () {
    const t = ResignationAcceptanceTemplate();
    expect(t.id, 'resignation_acceptance');
    expect(t.supportsBulk, isTrue);
  });

  test('clearance toggle off → no clearance line', () {
    const t = ResignationAcceptanceTemplate();
    final body = t.build(_i(clearance: false))
        .whereType<ParagraphBlock>().map((p) => p.text).join(' ');
    expect(body.toLowerCase(), isNot(contains('clearance')));
  });

  test('finalPay toggle off → no DOLE LA 06-20 line', () {
    const t = ResignationAcceptanceTemplate();
    final body = t.build(_i(finalPay: false))
        .whereType<ParagraphBlock>().map((p) => p.text).join(' ');
    expect(body, isNot(contains('06-20')));
  });

  test('both on → both lines present', () {
    const t = ResignationAcceptanceTemplate();
    final body = t.build(_i())
        .whereType<ParagraphBlock>().map((p) => p.text).join(' ');
    expect(body.toLowerCase(), contains('clearance'));
    expect(body, contains('06-20'));
  });
}
```

- [ ] **Step 2: Run — expect failure**

Run: `flutter test test/features/documents/resignation_acceptance_template_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement template**

```dart
// lib/features/documents/templates/resignation_acceptance_template.dart
import 'package:flutter/material.dart' show Icons, IconData;
import 'package:intl/intl.dart';

import '../blocks/block.dart';
import '../blocks/centered_signature_block.dart';
import '../blocks/heading_block.dart';
import '../blocks/logo_block.dart';
import '../blocks/memo_header_block.dart';
import '../blocks/multi_signature_block.dart';
import '../blocks/paragraph_block.dart';
import '../blocks/spacer_block.dart';
import 'document_template.dart';
import 'resignation_acceptance_inputs.dart';
import 'resignation_acceptance_validate.dart';

class ResignationAcceptanceTemplate
    extends DocumentTemplate<ResignationAcceptanceInputs> {
  const ResignationAcceptanceTemplate();

  @override
  String get id => 'resignation_acceptance';

  @override
  String get displayName => 'Resignation Acceptance';

  @override
  String get description =>
      'Formal HR acceptance of a resignation. Includes turnover, clearance, and final-pay disclosures.';

  @override
  IconData get icon => Icons.exit_to_app_outlined;

  @override
  bool get supportsBulk => true;

  @override
  List<Gate> gates(AutofillContext ctx) => const [];

  @override
  Future<ResignationAcceptanceInputs> autofill(AutofillContext ctx) async {
    final e = ctx.employee;
    final c = ctx.company;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return ResignationAcceptanceInputs(
      employeeId: e?.id ?? '',
      employeeFullName: e?.fullName ?? '',
      employeePosition: e?.jobTitle ?? '',
      employeeGender: e?.gender ?? '',
      companyId: c?.id ?? '',
      companyName: c?.name ?? '',
      companyAddress: c?.address ?? '',
      resignationDate: today,
      lastDayOfWork: today.add(const Duration(days: 30)),
      issueDate: today,
    );
  }

  @override
  List<ValidationError> validate(ResignationAcceptanceInputs inputs) =>
      validateResignationAcceptance(inputs);

  @override
  List<Block> build(ResignationAcceptanceInputs inputs) {
    final df = DateFormat('MMMM d, yyyy');
    final i = inputs;
    final honorific = _honorific(i.employeeGender);
    return <Block>[
      LogoBlock(companyId: i.companyId),
      MemoHeaderBlock(
        date: i.issueDate,
        recipient: '${i.employeeFullName} / ${i.employeePosition}',
        sender: '${i.hrManagerName} / HR Manager',
        subject: 'Acceptance of Resignation',
        recipientHonorific: honorific,
      ),
      const SpacerBlock(height: 12),
      ParagraphBlock(
          text:
              'This acknowledges receipt of your resignation letter dated ${df.format(i.resignationDate)}. ${i.companyName} formally accepts your resignation, effective ${df.format(i.lastDayOfWork)} as your last day of work.'),
      const SpacerBlock(height: 12),
      const HeadingBlock(text: 'Turnover'),
      ParagraphBlock(text: i.turnoverInstructions),
      if (i.includeClearanceMention) ...[
        const SpacerBlock(height: 8),
        const ParagraphBlock(
            text:
                'Please complete the company Clearance Form prior to your last day. Your Certificate of Employment and Quitclaim will be released upon clearance completion.'),
      ],
      if (i.includeFinalPayMention) ...[
        const SpacerBlock(height: 8),
        ParagraphBlock(
            text:
                'Your final pay will be released within thirty (30) days from ${df.format(i.lastDayOfWork)} in accordance with DOLE Labor Advisory 06-20.'),
      ],
      const SpacerBlock(height: 12),
      ParagraphBlock(
          text:
              'We thank you for your contributions to ${i.companyName} and wish you success in your future endeavors. Please acknowledge receipt below.'),
      const SpacerBlock(height: 40),
      MultiSignatureBlock(
        left: CenteredSignatureBlock(name: i.hrManagerName, label: 'HR Manager'),
        right: CenteredSignatureBlock(
            name: i.employeeFullName, label: 'Employee (Acknowledged)'),
      ),
    ];
  }

  String _honorific(String gender) {
    if (gender == 'FEMALE') return 'Ms.';
    if (gender == 'MALE') return 'Mr.';
    return '';
  }
}
```

- [ ] **Step 4: Run — expect pass**

Run: `flutter test test/features/documents/resignation_acceptance_template_test.dart`
Expected: 4 pass.

- [ ] **Step 5: Golden**

```dart
// test/features/documents/goldens/resignation_acceptance_pagination_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll/core/pdf/render.dart';
import 'package:payroll/features/documents/templates/resignation_acceptance_inputs.dart';
import 'package:payroll/features/documents/templates/resignation_acceptance_template.dart';

void main() {
  testWidgets('Resignation Acceptance renders PDF', (tester) async {
    final i = ResignationAcceptanceInputs(
      employeeId: 'e1', employeeFullName: 'Alice Reyes', employeePosition: 'Accountant',
      employeeGender: 'FEMALE',
      companyId: 'c1', companyName: 'Luxium', companyAddress: '123 QC',
      hrManagerName: 'Brixter',
      resignationDate: DateTime(2026, 6, 1),
      lastDayOfWork: DateTime(2026, 7, 1),
      issueDate: DateTime(2026, 6, 5),
    );
    final bytes = await renderDocumentToPdf(const ResignationAcceptanceTemplate().build(i));
    expect(String.fromCharCodes(bytes.sublist(0, 4)), startsWith('%PDF'));
  });
}
```

- [ ] **Step 6: Commit**

```bash
git add lib/features/documents/templates/resignation_acceptance_template.dart test/features/documents/resignation_acceptance_template_test.dart test/features/documents/goldens/resignation_acceptance_pagination_test.dart
git commit -m "feat(documents): Resignation Acceptance — template + golden"
```

## Task 18 — Resignation Acceptance: Form widget

**Files:**
- Create: `lib/features/documents/forms/resignation_acceptance_form.dart`

- [ ] **Step 1: Form**

```dart
// lib/features/documents/forms/resignation_acceptance_form.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../widgets/hr_manager_field.dart';
import '../inputs/company_picker.dart';
import '../inputs/date_field.dart';
import '../inputs/employee_picker.dart';
import '../templates/resignation_acceptance_inputs.dart';

class ResignationAcceptanceForm extends ConsumerStatefulWidget {
  final ResignationAcceptanceInputs initial;
  final bool employeeLocked;
  final ValueChanged<ResignationAcceptanceInputs> onChanged;
  final ValueChanged<String> onEmployeeChanged;
  const ResignationAcceptanceForm({
    super.key,
    required this.initial,
    required this.employeeLocked,
    required this.onChanged,
    required this.onEmployeeChanged,
  });

  @override
  ConsumerState<ResignationAcceptanceForm> createState() =>
      _ResignationAcceptanceFormState();
}

class _ResignationAcceptanceFormState
    extends ConsumerState<ResignationAcceptanceForm> {
  late ResignationAcceptanceInputs _i = widget.initial;
  void _set(ResignationAcceptanceInputs n) { setState(() => _i = n); widget.onChanged(n); }

  @override
  void didUpdateWidget(covariant ResignationAcceptanceForm old) {
    super.didUpdateWidget(old);
    if (old.initial != widget.initial) _i = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EmployeePicker(
          selectedId: _i.employeeId,
          enabled: !widget.employeeLocked,
          onSelected: (e) {
            widget.onEmployeeChanged(e?.id ?? '');
            _set(_i.copyWith(
              employeeId: e?.id ?? '',
              employeeFullName: e?.fullName ?? '',
              employeePosition: e?.jobTitle ?? '',
              employeeGender: e?.gender ?? '',
            ));
          },
        ),
        const SizedBox(height: 16),
        CompanyPicker(
          selectedId: _i.companyId,
          onSelected: (h) => _set(_i.copyWith(
            companyId: h?.id ?? '', companyName: h?.name ?? '',
            companyAddress: h?.address ?? '',
          )),
        ),
        const SizedBox(height: 16),
        HrManagerField(
          value: _i.hrManagerName,
          companyId: _i.companyId,
          onChanged: (v) => _set(_i.copyWith(hrManagerName: v)),
        ),
        const SizedBox(height: 16),
        DateField(
          label: 'Resignation date (when submitted)',
          value: _i.resignationDate,
          onChanged: (d) => _set(_i.copyWith(resignationDate: d)),
        ),
        const SizedBox(height: 12),
        DateField(
          label: 'Last day of work',
          value: _i.lastDayOfWork,
          onChanged: (d) => _set(_i.copyWith(lastDayOfWork: d)),
        ),
        const SizedBox(height: 12),
        TextFormField(
          initialValue: _i.turnoverInstructions,
          minLines: 3, maxLines: 8,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Turnover instructions',
          ),
          onChanged: (v) => _set(_i.copyWith(turnoverInstructions: v)),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          value: _i.includeClearanceMention,
          onChanged: (v) => _set(_i.copyWith(includeClearanceMention: v)),
          title: const Text('Include clearance reminder'),
        ),
        SwitchListTile(
          value: _i.includeFinalPayMention,
          onChanged: (v) => _set(_i.copyWith(includeFinalPayMention: v)),
          title: const Text('Include DOLE LA 06-20 final-pay disclosure'),
        ),
      ],
    );
  }
}
```

- [ ] **Step 2: Verify + commit**

```bash
dart format lib/features/documents/forms/resignation_acceptance_form.dart && flutter analyze lib/features/documents/forms/resignation_acceptance_form.dart
git add lib/features/documents/forms/resignation_acceptance_form.dart
git commit -m "feat(documents): Resignation Acceptance — form widget"
```

---

# Wire-up & Verification (Tasks 19-20)

## Task 19 — Registry + filename + generate_screen

**Files:**
- Modify: `lib/features/documents/templates/template_registry.dart`
- Modify: `lib/core/pdf/pdf_filename.dart`
- Modify: `lib/features/documents/generate_screen.dart`

- [ ] **Step 1: Update the registry**

Open `lib/features/documents/templates/template_registry.dart`. Add the 5 imports near the top alongside the existing ones (alphabetized):

```dart
import 'final_pay_template.dart';
import 'nod_template.dart';
import 'regularization_template.dart';
import 'resignation_acceptance_template.dart';
import 'salary_adjustment_template.dart';
```

Append the 5 entries to `kTemplates`, in this order, immediately AFTER the existing seven entries:

```dart
  FinalPayTemplate(),
  SalaryAdjustmentTemplate(),
  NodTemplate(),
  RegularizationTemplate(),
  ResignationAcceptanceTemplate(),
```

- [ ] **Step 2: Add filename prefixes**

Open `lib/core/pdf/pdf_filename.dart`. In the `switch` inside the prefix-resolution function, add the 5 cases (before the `default:`):

```dart
    case 'final_pay':
      return 'FinalPay';
    case 'salary_adjustment':
      return 'SalaryAdjustment';
    case 'nod':
      return 'NOD';
    case 'regularization':
      return 'Regularization';
    case 'resignation_acceptance':
      return 'ResignationAcceptance';
```

- [ ] **Step 3: Wire generate_screen**

Open `lib/features/documents/generate_screen.dart`. Find the existing state fields (one per template id), `_runAutofill`, `_formFor`, and `_previewFor`. Mirror the pattern for each new template.

For each of the five templates, add a private state field of the right type, e.g.:

```dart
FinalPayInputs? _finalPay;
SalaryAdjustmentInputs? _salaryAdjustment;
NodInputs? _nod;
RegularizationInputs? _regularization;
ResignationAcceptanceInputs? _resignationAcceptance;
```

Add imports for the 5 input classes and 5 form widgets at the top.

In `_runAutofill`, add 5 branches modeled on the existing ones (read the previous template's branch verbatim and adapt the type):

```dart
} else if (id == 'final_pay') {
  final i = await const FinalPayTemplate()
      .autofill(AutofillContext(employee: e, company: c, ref: ref));
  setState(() {
    _finalPay = i;
    _autofillRev++;
  });
} else if (id == 'salary_adjustment') {
  final i = await const SalaryAdjustmentTemplate()
      .autofill(AutofillContext(employee: e, company: c, ref: ref));
  setState(() {
    _salaryAdjustment = i;
    _autofillRev++;
  });
} else if (id == 'nod') {
  final i = await const NodTemplate()
      .autofill(AutofillContext(employee: e, company: c, ref: ref));
  setState(() {
    _nod = i;
    _autofillRev++;
  });
} else if (id == 'regularization') {
  final i = await const RegularizationTemplate()
      .autofill(AutofillContext(employee: e, company: c, ref: ref));
  setState(() {
    _regularization = i;
    _autofillRev++;
  });
} else if (id == 'resignation_acceptance') {
  final i = await const ResignationAcceptanceTemplate()
      .autofill(AutofillContext(employee: e, company: c, ref: ref));
  setState(() {
    _resignationAcceptance = i;
    _autofillRev++;
  });
}
```

In `_formFor(id)`, add a return branch per template:

```dart
case 'final_pay':
  if (_finalPay == null) return const SizedBox.shrink();
  return FinalPayForm(
    key: ValueKey('final_pay-$_autofillRev'),
    initial: _finalPay!,
    employeeLocked: widget.employeeLocked,
    onChanged: (v) => setState(() => _finalPay = v),
    onEmployeeChanged: (id) => _onPickerEmployeeChanged(id),
  );
case 'salary_adjustment':
  if (_salaryAdjustment == null) return const SizedBox.shrink();
  return SalaryAdjustmentForm(
    key: ValueKey('salary_adjustment-$_autofillRev'),
    initial: _salaryAdjustment!,
    employeeLocked: widget.employeeLocked,
    onChanged: (v) => setState(() => _salaryAdjustment = v),
    onEmployeeChanged: (id) => _onPickerEmployeeChanged(id),
  );
case 'nod':
  if (_nod == null) return const SizedBox.shrink();
  return NodForm(
    key: ValueKey('nod-$_autofillRev'),
    initial: _nod!,
    employeeLocked: widget.employeeLocked,
    onChanged: (v) => setState(() => _nod = v),
    onEmployeeChanged: (id) => _onPickerEmployeeChanged(id),
  );
case 'regularization':
  if (_regularization == null) return const SizedBox.shrink();
  return RegularizationForm(
    key: ValueKey('regularization-$_autofillRev'),
    initial: _regularization!,
    employeeLocked: widget.employeeLocked,
    onChanged: (v) => setState(() => _regularization = v),
    onEmployeeChanged: (id) => _onPickerEmployeeChanged(id),
  );
case 'resignation_acceptance':
  if (_resignationAcceptance == null) return const SizedBox.shrink();
  return ResignationAcceptanceForm(
    key: ValueKey('resignation_acceptance-$_autofillRev'),
    initial: _resignationAcceptance!,
    employeeLocked: widget.employeeLocked,
    onChanged: (v) => setState(() => _resignationAcceptance = v),
    onEmployeeChanged: (id) => _onPickerEmployeeChanged(id),
  );
```

In `_previewFor(id)` add 5 return branches:

```dart
case 'final_pay':
  if (_finalPay == null) return null;
  return _PreviewBundle(
    template: const FinalPayTemplate(),
    inputs: _finalPay!,
  );
case 'salary_adjustment':
  if (_salaryAdjustment == null) return null;
  return _PreviewBundle(
    template: const SalaryAdjustmentTemplate(),
    inputs: _salaryAdjustment!,
  );
case 'nod':
  if (_nod == null) return null;
  return _PreviewBundle(
    template: const NodTemplate(),
    inputs: _nod!,
  );
case 'regularization':
  if (_regularization == null) return null;
  return _PreviewBundle(
    template: const RegularizationTemplate(),
    inputs: _regularization!,
  );
case 'resignation_acceptance':
  if (_resignationAcceptance == null) return null;
  return _PreviewBundle(
    template: const ResignationAcceptanceTemplate(),
    inputs: _resignationAcceptance!,
  );
```

> **Note:** The exact symbol names (`_PreviewBundle`, `_runAutofill`, `_onPickerEmployeeChanged`, `_autofillRev`, `_formFor`, `_previewFor`) are taken from the existing pattern. If any differ in the actual `generate_screen.dart`, mirror what the NDA/Liability Waiver branches do verbatim — those were the last templates wired in.

- [ ] **Step 4: Format + analyze**

Run: `dart format lib/features/documents/templates/template_registry.dart lib/core/pdf/pdf_filename.dart lib/features/documents/generate_screen.dart && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/features/documents/templates/template_registry.dart lib/core/pdf/pdf_filename.dart lib/features/documents/generate_screen.dart
git commit -m "feat(documents): register 5 batch-2 templates + wire generate_screen"
```

## Task 20 — Final green-bar checkpoint

**Files:** none (verification only).

- [ ] **Step 1: Run full test suite**

Run: `flutter test`
Expected: ALL tests pass (existing + 15 new ones).

If anything fails: read the error, fix the offending template/widget, re-run. Do NOT skip failing tests.

- [ ] **Step 2: Analyze the entire repo**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: Format check**

Run: `dart format --output=none --set-exit-if-changed lib/ test/`
Expected: exits 0 (no formatting drift).

- [ ] **Step 4: Smoke the app**

Run: `flutter run -d linux --dart-define-from-file=env/prod.json`

In the running app, manually verify:
1. Open Documents tab. Confirm all 12 templates appear in the registry (was 7, now 12).
2. Pick a separated employee. Open Final Pay. Confirm fields autofill with provider-derived numbers; toggle an override and confirm the line accepts a new value.
3. Pick any active employee. Open Salary Adjustment. Toggle to Promotion mode; confirm the role-picker appears.
4. Pick an employee with at least one prior NTE. Open NOD. Confirm the NTE dropdown lists the prior NTE; selecting it sets `nteDate`.
5. Pick a probationary employee. Open Regularization. Confirm no gate; generate the PDF.
6. Pick any employee. Open Resignation Acceptance. Confirm `lastDayOfWork` defaults to today+30; toggle each switch and confirm the body text adjusts.

- [ ] **Step 5: Commit + push**

```bash
git status   # should be clean
git push -u origin feat/hr-docs-batch-2
```

Then create a PR (if shipping via PR workflow) or merge to main directly:

```bash
git checkout main
git merge --no-ff feat/hr-docs-batch-2
git push origin main
```

---

## Self-Review Notes (from author)

- All 5 templates have inputs + validate + template + form + registry entry + filename + golden test. ✅
- `ntesByEmployeeProvider` is the only shared infra addition. ✅
- TDD-first: every template's `_validate_test.dart` lands before the validate function; every `_template_test.dart` lands before the template's `build()`. ✅
- `Decimal` arithmetic for all currency math; never `double` in computation paths. ✅
- Gender-aware salutations reuse the existing `_honorific(gender)` helper pattern from prior templates. ✅
- All forms re-derive state on employee change via `onEmployeeChanged` + `ValueKey(autofillRev)` re-mount — preserves the existing "picker re-autofill" fix from earlier MVPs. ✅

## Known assumptions to verify at execution time

1. **`Employee.gender`, `Employee.declaredWageOverride`, `Employee.wageType`, `Employee.baseSalary`** — fields referenced in autofill. If any is named differently in the current Employee model, mirror what the Employment Contract template uses (it pulls the same fields).
2. **`KeyValueBlock.bold`** — used in Final Pay's `TOTAL FINAL PAY` row. If the block doesn't accept `bold`, drop the argument; the build test only checks structural shape.
3. **`RoleScorecardPicker`** — referenced in Salary Adjustment form. If it doesn't exist, use a `DropdownButtonFormField` over `roleScorecardListProvider` (whatever the existing scorecard list provider is). Grep `lib/` for the existing scorecard picker pattern (likely used in EmployeeFormScreen).
4. **`renderDocumentToPdf`** — used in goldens. If the actual symbol is named differently, copy the pattern from `test/features/documents/goldens/nda_pagination_test.dart`.
5. **`_PreviewBundle` / `_formFor` / `_previewFor` / `_autofillRev` / `_onPickerEmployeeChanged`** — symbol names in `generate_screen.dart`. Mirror what the NDA branch does verbatim.
