# Salary-Adjustment Notice Improvements — Design

**Date:** 2026-07-11
**Status:** Draft, pending user review
**Owner:** payroll-flutter

## Summary

Two independent improvements to the salary-adjustment / promotion / lateral / demotion notice
(`SalaryAdjustmentTemplate`):

- **A. Daily-rate monthly estimate.** When the rate is DAILY, the pay sentence states the number of
  working days per month used to estimate monthly pay, so the employee can gauge their monthly
  earnings from a figure that reconciles with their payslip.
- **B. Editable signatory (role + person) with a self-approval block.** The signatory's role is
  currently the hardcoded literal `'HR Manager'`; make it editable, and prevent the person being
  adjusted from signing their own notice (the common case: the HR Manager themselves gets a raise).

Both are template + form changes. No migration.

## A. Daily-rate monthly estimate

**Decision (from brainstorm):** show **26** — the exact divisor payroll uses for every daily
employee. Payroll hardcodes `standardWorkDaysPerMonth: 26` (`compute_service.dart:701,752`); the
scorecard only stores `work_days_per_week` as free text ("Monday to Saturday", …) and no per-employee
days-per-month, so 26 is the only figure that reconciles with the payslip. The purpose is estimation,
not a contractual per-employee schedule.

**Behavior.** When `salaryPeriod == 'DAILY'`, the pay clause gains `(estimated at 26 working days per
month)`. Example:

> …your daily rate will be adjusted from ₱1,076.92 to ₱1,184.61 (estimated at 26 working days per
> month). {reason}

MONTHLY output is unchanged. A single shared helper produces the clause so all four modes
(salaryAdjustment, promotion, demotion, lateral) stay consistent; it is driven purely by
`salaryPeriod == 'DAILY'`.

**Where 26 comes from.** Add `workDaysPerMonth` (int, default `26`) to `SalaryAdjustmentInputs`,
serialized like the other fields and defaulted in `autofill` from a top-level constant
`kStandardWorkDaysPerMonth = 26` that carries a comment: "mirrors payroll's
`standardWorkDaysPerMonth`." Carrying it in the serialized inputs (rather than a bare literal in
`build()`) freezes the stated figure into the saved document's settings, consistent with this
project's "documents are settings-only, re-render from saved settings" principle, and makes it
unit-testable through `build()`.

## B. Editable signatory + self-approval block

**Today.** `build()` renders the signatory as `LetterParty(name: i.hrManagerName, subtitle: 'HR
Manager')` in the "From:" line and `SignatoryParty(name: i.hrManagerName, role: 'HR Manager')` in the
signature block. The **name** (`hrManagerName`) is already an editable form field; the **role** is the
hardcoded literal `'HR Manager'` in both places. The employee's own line
(`SignatoryParty(name: employeeFullName, role: 'Employee (Acknowledged)')`) is separate and unchanged.

**Change.**
1. Add `signatoryRole` (String, default `'HR Manager'`) to `SalaryAdjustmentInputs`, serialized.
2. `build()` uses `i.signatoryRole` in place of the two hardcoded `'HR Manager'` literals (the "From:"
   subtitle and the signatory `SignatoryParty.role`). The employee acknowledgement line is untouched.
3. `autofill` defaults `signatoryRole` to `'HR Manager'` and the signatory name to the company's
   `hrManagerName` (unchanged).
4. Form: relabel the existing `hrManagerName` field from its current label to **"Signatory name"**, and
   add a **"Signatory title / role"** field bound to `signatoryRole` (default `'HR Manager'`).

**Field naming / back-compat.** Keep the Dart field and JSON key `hrManagerName` (it now holds the
signatory's name, which may be a COO/GM/etc.). Renaming the JSON key would break `fromJson` for
already-saved documents, so it stays; a doc comment notes it is the signatory name. `signatoryRole`
is a new key.

**Self-approval guard.** `validateSalaryAdjustment` gains: when `hrManagerName` and `employeeFullName`
are both non-empty and equal (trimmed, case-insensitive), add
`ValidationError('hrManager', 'The signatory cannot be the employee being adjusted — choose another
approver.')`. Also require `signatoryRole` non-empty
(`ValidationError('signatoryRole', 'Signatory title is required')`). The existing "HR manager name is
required" check stays. The preview/generate is already blocked whenever `validate` returns errors, so
this needs no new wiring.

## Back-compat & goldens

Both new fields default to today's values (`workDaysPerMonth = 26`, `signatoryRole = 'HR Manager'`):
- `fromJson` supplies those defaults when the keys are absent, so **old saved documents re-render
  byte-identically**.
- Existing golden/body tests stay green **unless a golden fixture's `salaryPeriod` is `DAILY`** — in
  which case its body legitimately gains the estimate clause and that golden is regenerated (an
  intended change, reviewed as such). The implementer confirms each golden fixture's wage type before
  regenerating anything.

## Scope (in)

1. `salary_adjustment_inputs.dart`: add `workDaysPerMonth` (int, default 26) and `signatoryRole`
   (String, default 'HR Manager') — field, constructor, `fromJson`, `toJson`, `copyWith`.
2. `salary_adjustment_template.dart`: `kStandardWorkDaysPerMonth` constant; autofill defaults; the
   DAILY estimate clause helper; `signatoryRole` in the two signatory sites.
3. `salary_adjustment_validate.dart`: self-approval guard + `signatoryRole` required.
4. `salary_adjustment_form.dart`: relabel signatory name; add signatory role field.
5. Tests (below).

## Scope (out)

- The other 11 document templates. Only `SalaryAdjustmentTemplate` changes.
- Auto-detecting an alternate approver when the employee is the HR manager — the guard blocks
  self-approval; choosing the replacement is a manual form edit.
- Any per-employee "work days per month" data model (payroll's flat 26 is authoritative).

## Testing

- **`salary_adjustment_body_test.dart`** (build() output):
  - A DAILY salary adjustment body contains `26 working days per month`; a MONTHLY one does **not**.
  - The clause also appears for a DAILY promotion and a DAILY lateral (helper is mode-agnostic).
  - `build()` with `signatoryRole: 'Chief Operating Officer'` + `hrManagerName: 'Jane Cruz'` →
    the "From:" `LetterMetaBlock.from` subtitle is `'Chief Operating Officer'` and the signatory
    `SignatoryParty` has role `'Chief Operating Officer'` / name `'Jane Cruz'`; the employee
    acknowledgement party is still `role: 'Employee (Acknowledged)'`.
- **`salary_adjustment_validate_test.dart`** (extend):
  - signatory name == employee name (case/space-insensitive) → error field `'hrManager'`.
  - a different signatory name → no `'hrManager'` self-approval error.
  - empty `signatoryRole` → error field `'signatoryRole'`.
- Full documents suite green (incl. goldens, per the back-compat note). `flutter analyze` clean, 0
  new lints.

## Files (anticipated)

**Modified**
- `lib/features/documents/templates/salary_adjustment_inputs.dart`
- `lib/features/documents/templates/salary_adjustment_template.dart`
- `lib/features/documents/templates/salary_adjustment_validate.dart`
- `lib/features/documents/forms/salary_adjustment_form.dart`
- `test/features/documents/salary_adjustment_body_test.dart`
- `test/features/documents/templates/salary_adjustment_validate_test.dart`
