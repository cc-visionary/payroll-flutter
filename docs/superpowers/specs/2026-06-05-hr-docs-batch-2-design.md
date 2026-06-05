# HR Documents Batch 2 — Final Pay, Salary Adjustment, NOD, Regularization, Resignation Acceptance

**Date:** 2026-06-05
**Status:** Draft, pending user review
**Owner:** payroll-flutter

## Summary

Ship 5 new document templates that close loops the system currently leaves half-open:

1. **Final Pay Computation Breakdown** — formal computation disclosure for separated employees (basic + 13th-month + leave conversion − deductions). Auto-computes from the existing payroll engine + `finalPayBreakdownProvider`; HR can override any line. **Legally required** under DOLE Labor Advisory 06-20 (release of final pay).
2. **Salary Adjustment / Promotion Letter** — single template with a type toggle. Source PDF: `~/Downloads/GameCove Notice of Salary Adjustment_TAGUIAM.pdf`. Promotion path also shows old→new role; both paths show old→new salary.
3. **Notice of Decision (NOD)** — disciplinary decision pairing with the existing NTE. Optional NTE picker auto-fills charges/findings from the linked NTE. Closes the PH Labor Code Art. 297-299 due-process cycle.
4. **Probationary Regularization Letter** — positive inverse of the existing Non-Reg template. Issued when the Performance MVP's 5-month review concludes "regularize."
5. **Resignation Acceptance Letter** — formal HR response to a resignation submission. Standard memo with separation date + clearance reference.

Brings the total templates from 7 to 12. All five share the existing block library (PartyBlock, MemoHeader, signature blocks, AmountWithBreakdown, etc.) and standard autofill sources (Employee + HiringEntity + RoleScorecard).

## Motivation

| Doc | Pain it solves today |
|---|---|
| Final Pay | Brixter currently writes ad-hoc computations in WhatsApp/Lark when employees ask "how much will I get?" No paper trail; legally required disclosure under DOLE LA 06-20. |
| Salary Adjustment | Annual increase / mid-cycle raise letters get typed from scratch every time. Compensation decisions don't generate a formal artifact. |
| NOD | NTEs are issued without proper NOD follow-through. **Legal compliance gap** under Art. 297-299 — weakens any termination case in a labor dispute. |
| Regularization | The Performance 5-month review is the regularization decision point, but a "yes" decision currently produces only a Lark message, not a formal letter. Employee has no document confirming their REGULAR status. |
| Resignation Acceptance | When an employee resigns, HR's formal acceptance isn't documented. Often referenced later by COE and final pay disclosure. |

## Decisions locked from brainstorm

1. **Sources**: Salary Adjustment uses `~/Downloads/GameCove Notice of Salary Adjustment_TAGUIAM.pdf` verbatim. The other 4 are designed from scratch following PH labor law conventions + sibling-template patterns (NOD mirrors NTE; Regularization mirrors Non-Reg; Resignation Acceptance is a standard memo; Final Pay is a BIR/DOLE-standard computation table).
2. **Salary template**: ONE template with a `Type` toggle (`SALARY_ADJUSTMENT` / `PROMOTION`). Rationale (user-stated): promotions almost always include a salary change, so promotion is salary-adjustment-plus-role-change.
3. **Final Pay**: auto-compute from `finalPayBreakdownProvider` + HR can override any line. Matches the existing Quitclaim pattern's `AmountWithBreakdown` widget.
4. **NOD linkage**: optional NTE picker. HR can select a prior NTE on the employee; the NOD auto-fills the charges/findings from that NTE and references it by date in the body. HR can also write a standalone NOD.
5. **Ship cadence**: all 5 in one branch (`feat/hr-docs-batch-2`), one spec/plan, one merge.

## Scope (in)

For each of the 5 templates:
- Inputs class (e.g., `FinalPayInputs`) with autofill defaults
- `validate*` pure function returning `List<ValidationError>`
- `*Template extends DocumentTemplate` with `autofill(AutofillContext)` and `build(I inputs)`
- Form widget under `lib/features/documents/forms/`
- Registration in `lib/features/documents/templates/template_registry.dart`
- Filename prefix in `lib/core/pdf/pdf_filename.dart`
- Wiring branch in `lib/features/documents/generate_screen.dart`
- Pagination golden test under `test/features/documents/goldens/`

Plus shared work:
- **NTE picker provider**: a `ntesByEmployeeProvider(employeeId)` that returns `employee_documents` rows where `document_type = 'NTE'` for the optional NOD link. Reuses existing `employee_documents` table.
- **Final pay HR-override storage**: the form already uses `AmountWithBreakdown` which supports a `locked` flag; reuse as-is.

## Scope (out — v2 or later)

- **Auto-generation from workflows / Performance MVP**: e.g., when a PROBATION_5M check-in completes COMPLETED with rating ≥ 4, auto-prefill a Probationary Regularization Letter. Defer.
- **Multi-employee bulk generate** for any of these (already supported by the bulk-generate flow — works for free once registered).
- **Final pay computation in the payroll engine itself**: any improvements to the engine's `finalPayBreakdownProvider` (e.g., DOLE prorating math edge cases) are NOT in scope. We consume the provider as-is.
- **NOD → termination workflow trigger**: when an NOD concludes "termination," automatically firing the SEPARATION workflow is a v2 enhancement.
- **PDF storage**: same as the rest of the documents feature — generate-then-print/share; persistence to Supabase storage deferred.

## Integration principle (carry-over)

Same rule from prior MVPs: reuse FKs, no duplicated data.

- All 5 templates take an `employeeId` (or applicantId for Salary Adjustment when a candidate is getting an offer-time adjustment — actually OUT of scope, this is employee-only).
- All resolve company/signatory data via `hiringEntityByIdProvider`.
- NOD references the NTE via the existing `employee_documents.id` — no copy of the NTE's body, just an FK reference for auto-fill at NOD creation time. (Once filled, the NOD is independent — the NTE's body could later be edited without affecting historical NODs. This is intentional, matches the skill_ratings snapshot pattern.)
- Salary Adjustment for a PROMOTION refers to old and new `roleScorecardId`. Both old and new are FKs; the letter snapshots `RoleScorecard.jobTitle` and `RoleScorecard.baseSalary` at letter creation time.

## Per-template specs

### 1. Final Pay Computation Breakdown — `FinalPay`

**Filename prefix:** `FinalPay`

**Inputs (`FinalPayInputs`):**

```
employeeId, employeeFullName, employeePosition, employeeHireDate, employeeSeparationDate
companyId, companyName, companyAddress, hrManagerName
// computation (auto-filled, HR can override each)
lastNetPay (Decimal)               // pro-rated last cutoff
thirteenthMonth (Decimal)
unusedLeaveConversion (Decimal)
outstandingCashAdvance (Decimal)   // subtracted
otherDeductions (Decimal)          // optional extra deduction line
otherDeductionsLabel (String?)
// reference dates
computedAsOf (DateTime)
releaseDate (DateTime)             // when HR will actually disburse
```

**Autofill:**
- Identity from Employee (fullName, jobTitle, hireDate, separationDate).
- Computation from `finalPayBreakdownProvider(employeeId)` (existing). Auto-fills `lastNetPay`, `thirteenthMonth`, `unusedLeaveConversion`, `outstandingCashAdvance`.
- `otherDeductions` defaults to 0.
- `computedAsOf` defaults to today.
- `releaseDate` defaults to today + 30 days (DOLE LA 06-20 max release window).

**Gates:** employee must have a `separationDate` set OR `employmentStatus != 'ACTIVE'`. Otherwise the gate reads "Final pay is only computed for separated employees."

**Validation:**
- Identity fields required.
- All computation lines ≥ 0.
- `releaseDate ≥ computedAsOf`.
- `releaseDate ≤ computedAsOf + 30 days` (warn, not block — DOLE max disclosure window).

**Block tree:**
- `CompanyHeaderBlock(companyName, companyAddress)` + logo
- `LetterMetaBlock(date: computedAsOf, recipient: employeeFullName, address: employeePosition, subject: 'Final Pay Computation Breakdown')`
- `SpacerBlock(12)`
- Salutation paragraph + intro: "Per DOLE Labor Advisory 06-20, this document discloses the computation of your final pay following separation effective {separationDate}."
- `HeadingBlock('Computation')` + `KeyValueBlock` rows:
  - "Last salary (pro-rated)" → `lastNetPay`
  - "13th month pay (pro-rated)" → `thirteenthMonth`
  - "Unused leave conversion" → `unusedLeaveConversion`
  - "Less: Outstanding cash advances" → `(${outstandingCashAdvance})`
  - (if otherDeductions > 0) "Less: {otherDeductionsLabel ?? 'Other deductions'}" → `(${otherDeductions})`
  - **`TOTAL FINAL PAY`** (bold, larger) → sum
- `ParagraphBlock` body: "The release date is {releaseDate}. Please report to HR with valid ID to claim. Any disputes should be raised in writing within 7 days of receipt."
- `SpacerBlock(40)`
- `MultiSignatureBlock` — HR Manager + Employee acknowledgment

**Reused widgets:** `AmountWithBreakdown` for each Decimal field (locked toggle bound to "I'm overriding this line").

---

### 2. Salary Adjustment / Promotion Letter — `SalaryAdjustment`

**Filename prefix:** `SalaryAdjustment`

**Source:** `~/Downloads/GameCove Notice of Salary Adjustment_TAGUIAM.pdf` — transcribed verbatim. The source structure (per Brixter's standard) is:
- Brand header
- Date / "To: {Employee}" / "Re: Notice of Salary Adjustment"
- Body: "We are pleased to inform you that, effective {effectiveDate}, your monthly salary will be adjusted from ₱{oldSalary} to ₱{newSalary}. {reason}"
- Closing + signatures (HR Manager + acknowledged-by Employee)

**Inputs (`SalaryAdjustmentInputs`):**

```
type (enum: 'SALARY_ADJUSTMENT' | 'PROMOTION')
employeeId, employeeFullName, employeePosition
companyId, companyName, companyAddress, hrManagerName
// when type == PROMOTION
oldRoleScorecardId (String?)       // current role
newRoleScorecardId (String?)       // target role
oldPosition (String?)              // snapshotted from old scorecard
newPosition (String?)              // snapshotted from new scorecard
// salary change (always)
oldSalary (Decimal)
newSalary (Decimal)
salaryPeriod (enum: 'MONTHLY' | 'DAILY')
// effective date + reason
effectiveDate (DateTime)
reason (String)                    // multi-line, optional rich-text body
```

**Autofill:**
- Identity from Employee.
- `oldSalary` from current employee's RoleScorecard.baseSalary (or `declaredWageOverride` if set).
- `salaryPeriod` from RoleScorecard.wageType.
- For PROMOTION mode: `oldRoleScorecardId` defaults to current `employee.roleScorecardId`. `newRoleScorecardId` empty; HR picks. When `newRoleScorecardId` is set, `newPosition` and `newSalary` autofill from that scorecard.
- For SALARY_ADJUSTMENT mode: `newSalary` empty (HR types); position unchanged.
- `effectiveDate` defaults to first day of next month.

**Gates:** none — applies to any active employee.

**Validation:**
- All identity + company fields required.
- `oldSalary > 0`, `newSalary > 0`.
- For PROMOTION: `newRoleScorecardId` required; `newRoleScorecardId != oldRoleScorecardId`.
- `effectiveDate ≥ today` (warn if past).
- `reason` non-empty.

**Block tree (matches the GameCove source):**
- `LogoBlock` (brand logo from HiringEntity)
- `LetterMetaBlock(date, recipient, subject: type == PROMOTION ? 'Notice of Promotion' : 'Notice of Salary Adjustment')`
- `SpacerBlock(12)`
- Salutation: "Dear Ms./Mr. {lastName},"
- `ParagraphBlock` body:
  - PROMOTION case: "We are pleased to inform you that, effective {effectiveDate}, you are being promoted from **{oldPosition}** to **{newPosition}**. In line with this promotion, your monthly salary will be adjusted from **₱{oldSalary}** to **₱{newSalary}**. {reason}"
  - SALARY_ADJUSTMENT case: "We are pleased to inform you that, effective {effectiveDate}, your monthly salary will be adjusted from **₱{oldSalary}** to **₱{newSalary}**. {reason}"
- `ParagraphBlock` closing: "All other terms of your employment remain unchanged. Please acknowledge receipt of this letter below."
- `SpacerBlock(40)`
- `MultiSignatureBlock` — HR Manager (signs) + Employee (acknowledged-by)

---

### 3. Notice of Decision (NOD) — `Nod`

**Filename prefix:** `NOD`

**Inputs (`NodInputs`):**

```
employeeId, employeeFullName, employeePosition
companyId, companyName, companyAddress, hrManagerName
linkedNteDocumentId (String?)      // optional FK to employee_documents
nteDate (DateTime?)                // auto-filled from linked NTE; otherwise HR enters
charges (String)                   // multi-line; auto-filled from NTE if linked
employeeResponseSummary (String)   // multi-line; HR summarizes the explanation received
findings (String)                  // multi-line HR analysis
decision (enum: 'REPRIMAND' | 'WRITTEN_WARNING' | 'SUSPENSION' | 'TERMINATION' | 'NO_ACTION')
suspensionDays (int?)              // when decision == SUSPENSION
effectiveDate (DateTime)
issueDate (DateTime)
```

**Autofill:**
- Identity from Employee.
- When `linkedNteDocumentId` is set (via picker): `nteDate` = NTE document's `created_at`; `charges` = NTE's `findings` / body text. Reading the NTE's stored fields requires querying its `employee_documents` row + (if available) the original generation inputs — for v1, pull the NTE's `title` and let HR copy/paste charges manually; full NTE-input autofill is a v2 polish.
- `issueDate` defaults to today.
- `effectiveDate` defaults to today (for REPRIMAND/WARNING) or today+7 (for SUSPENSION/TERMINATION — gives notice period).

**Gates:** none.

**Validation:**
- Identity required.
- `charges`, `employeeResponseSummary`, `findings` non-empty.
- `decision` required.
- When `decision == 'SUSPENSION'`: `suspensionDays > 0`.
- `issueDate ≤ effectiveDate`.

**Block tree (mirrors NTE structure):**
- `LogoBlock` (brand)
- `MemoHeaderBlock(date: issueDate, to: '{employeeFullName} / {employeePosition}', from: '{hrManagerName} / HR Manager', subject: 'Notice of Decision', recipientHonorific: Mr./Ms.)`
- `SpacerBlock(12)`
- Intro: "This Notice of Decision is issued in response to the Notice to Explain dated {nteDate ?? '___'}, and your written explanation received thereafter."
- `HeadingBlock('Charges')` + `ParagraphBlock(charges)`
- `HeadingBlock('Employee Response')` + `ParagraphBlock(employeeResponseSummary)`
- `HeadingBlock('Findings')` + `ParagraphBlock(findings)`
- `HeadingBlock('Decision')` + `EmphasisParagraphBlock` with bold decision text:
  - REPRIMAND: "After careful consideration, management has decided to issue a **verbal/written reprimand** for the above infractions."
  - WRITTEN_WARNING: "After careful consideration, management has decided to issue a **written warning**. Any repeat offense may result in stronger disciplinary action."
  - SUSPENSION: "After careful consideration, management has decided to impose a **{suspensionDays}-day suspension without pay**, effective {effectiveDate}."
  - TERMINATION: "After careful consideration, management has decided to **terminate your employment** effective {effectiveDate}, in accordance with Article 297 of the Labor Code of the Philippines."
  - NO_ACTION: "After review, management has decided that **no further disciplinary action** is warranted at this time."
- `ParagraphBlock` closing: "You may appeal this decision in writing within 5 working days of receipt. Please acknowledge receipt below."
- `SpacerBlock(40)`
- `MultiSignatureBlock` — HR Manager + Employee acknowledged-by

**NTE picker UX:** form shows a dropdown of NTE documents on this employee (from `ntesByEmployeeProvider`). Picking one fills `linkedNteDocumentId` + auto-fills `nteDate` (employee_documents.created_at) + autofills `charges` with NTE document's title (HR pastes details). No selection → all fields manual. Dropdown labeled "Link to NTE (optional)".

---

### 4. Probationary Regularization Letter — `Regularization`

**Filename prefix:** `Regularization`

**Inputs (`RegularizationInputs`):**

```
employeeId, employeeFullName, employeePosition
companyId, companyName, companyAddress, hrManagerName
hireDate (DateTime)
regularizationDate (DateTime)       // effective date of REGULAR status
baseSalary (Decimal)                // from current scorecard
salaryPeriod (enum: 'MONTHLY' | 'DAILY')
issueDate (DateTime)
performanceSummary (String?)        // optional positive context from manager
```

**Autofill:**
- Identity from Employee.
- `hireDate` from Employee.
- `regularizationDate` defaults to today; HR can override.
- `baseSalary` + `salaryPeriod` from current RoleScorecard.
- `performanceSummary` empty; HR types or pulls from the last PROBATION_5M check-in (manual paste for v1; auto-pull deferred).

**Gates:** employee's `employmentType` must be `'PROBATIONARY'`. Otherwise the gate reads "Regularization letter is only valid for probationary employees."

**Validation:**
- Identity required.
- `regularizationDate ≥ hireDate`.
- `regularizationDate ≤ hireDate + 6 months` (warn, not block — DOLE rule).
- `baseSalary > 0`.

**Block tree (mirrors Non-Reg layout):**
- `LogoBlock`
- `MemoHeaderBlock(date: issueDate, to: '{employeeFullName} / {employeePosition}', from: '{hrManagerName} / HR Manager', subject: 'Confirmation of Regularization', recipientHonorific: Mr./Ms.)`
- `SpacerBlock(12)`
- Body opening: "Congratulations! Following a comprehensive review of your performance during your probationary period (from {hireDate} to today), {companyName} is pleased to confirm your regularization effective {regularizationDate}."
- (Optional) `HeadingBlock('Performance Summary')` + `ParagraphBlock(performanceSummary)` — rendered only when non-empty.
- `HeadingBlock('Terms')` + `BulletListBlock`:
  - "Effective date: {regularizationDate}"
  - "Position: {employeePosition}"
  - "Monthly salary: ₱{baseSalary}" (or "Daily rate" for DAILY)
  - "All other terms and benefits per your existing Employment Contract apply."
- `ParagraphBlock` closing: "We look forward to your continued contribution to {companyName}. Please acknowledge receipt below."
- `SpacerBlock(40)`
- `MultiSignatureBlock` — HR Manager + Employee acknowledged-by

---

### 5. Resignation Acceptance Letter — `ResignationAcceptance`

**Filename prefix:** `ResignationAcceptance`

**Inputs (`ResignationAcceptanceInputs`):**

```
employeeId, employeeFullName, employeePosition
companyId, companyName, companyAddress, hrManagerName
resignationDate (DateTime)          // when employee submitted resignation
lastDayOfWork (DateTime)            // effective separation (typically resignation + 30 days)
issueDate (DateTime)
turnoverInstructions (String)       // HR's instructions for handover/clearance
includeClearanceMention (bool)      // toggle: include "complete clearance form to receive COE/Quitclaim"
includeFinalPayMention (bool)       // toggle: include "final pay will be released within 30 days per DOLE LA 06-20"
```

**Autofill:**
- Identity from Employee.
- `resignationDate` defaults to today (HR overrides with actual submission date).
- `lastDayOfWork` defaults to resignationDate + 30 days (Labor Code Art. 300 — 30-day notice).
- `issueDate` defaults to today.
- `turnoverInstructions` defaults to a standard template: "Please coordinate with your direct manager for proper turnover of pending tasks and Company property (laptop, ID, access cards, etc.)."
- Both `includeClearanceMention` and `includeFinalPayMention` default to true.

**Gates:** none — HR can issue for any employee.

**Validation:**
- Identity required.
- `lastDayOfWork ≥ resignationDate`.
- `lastDayOfWork ≥ today` (warn if past — most acceptances are forward-looking).
- `turnoverInstructions` non-empty.

**Block tree:**
- `LogoBlock`
- `MemoHeaderBlock(date: issueDate, to: '{employeeFullName} / {employeePosition}', from: '{hrManagerName} / HR Manager', subject: 'Acceptance of Resignation', recipientHonorific: Mr./Ms.)`
- `SpacerBlock(12)`
- Body opening: "This acknowledges receipt of your resignation letter dated {resignationDate}. {companyName} formally accepts your resignation, effective {lastDayOfWork} as your last day of work."
- `HeadingBlock('Turnover')` + `ParagraphBlock(turnoverInstructions)`
- (If `includeClearanceMention`) `ParagraphBlock`: "Please complete the company Clearance Form prior to your last day. Your Certificate of Employment and Quitclaim will be released upon clearance completion."
- (If `includeFinalPayMention`) `ParagraphBlock`: "Your final pay will be released within thirty (30) days from {lastDayOfWork} in accordance with DOLE Labor Advisory 06-20."
- `ParagraphBlock` closing: "We thank you for your contributions to {companyName} and wish you success in your future endeavors. Please acknowledge receipt below."
- `SpacerBlock(40)`
- `MultiSignatureBlock` — HR Manager + Employee acknowledged-by

---

## Shared infrastructure additions

### `ntesByEmployeeProvider`
**File:** `lib/features/documents/providers.dart` (append)

```dart
final ntesByEmployeeProvider = FutureProvider.family<List<EmployeeDocumentSummary>, String>(
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
  },
);

class EmployeeDocumentSummary {
  final String id;
  final String title;
  final DateTime createdAt;
  const EmployeeDocumentSummary({required this.id, required this.title, required this.createdAt});
  factory EmployeeDocumentSummary.fromRow(Map<String, dynamic> r) => EmployeeDocumentSummary(
    id: r['id'] as String,
    title: r['title'] as String,
    createdAt: DateTime.parse(r['created_at'] as String),
  );
}
```

Used by the NOD form's NTE picker dropdown. Generic enough to support future "pick any prior document of type X" use cases.

### Template registry update
**File:** `lib/features/documents/templates/template_registry.dart`

```dart
final kTemplates = <DocumentTemplate>[
  // existing 7…
  QuitclaimTemplate(),
  CoeTemplate(),
  NteTemplate(),
  NonRegTemplate(),
  EmploymentContractTemplate(),
  NdaTemplate(),
  LiabilityWaiverTemplate(),
  // batch 2:
  FinalPayTemplate(),
  SalaryAdjustmentTemplate(),
  NodTemplate(),
  RegularizationTemplate(),
  ResignationAcceptanceTemplate(),
];
```

Five appended. Order matches HR mental model: separation-cycle docs (Final Pay), comp docs (Salary Adjustment), disciplinary close (NOD), positive lifecycle (Regularization), then voluntary separation acceptance.

### `pdf_filename.dart`
**File:** `lib/core/pdf/pdf_filename.dart` — append five `case` branches in `_prefixFor`:

```dart
case 'final_pay': return 'FinalPay';
case 'salary_adjustment': return 'SalaryAdjustment';
case 'nod': return 'NOD';
case 'regularization': return 'Regularization';
case 'resignation_acceptance': return 'ResignationAcceptance';
```

### Generate-screen wiring
**File:** `lib/features/documents/generate_screen.dart`

Five new template branches per the existing pattern (state field, `_runAutofill`, `_onPickerEmployeeChanged`, `_formFor`, `_previewFor`, `ValueKey('$id-$_autofillRev')`). Mechanical, follows existing 7 templates exactly.

### Bulk-generate eligibility
- **Salary Adjustment, Regularization, Resignation Acceptance**: `supportsBulk = true` (autofill-complete, no per-employee unique input beyond what's in Employee).
- **Final Pay, NOD**: `supportsBulk = false` (each one needs employee-specific computation or charges — bulk doesn't make sense).

## Testing

Per-template (mirrors existing patterns):
- `<template>_inputs_test.dart` — round-trip if there's a `fromJson` (most don't need one)
- `<template>_validate_test.dart` — required-field errors, conditional rules (e.g., SUSPENSION requires days; PROMOTION requires new scorecard)
- `<template>_build_test.dart` — block tree shape (intro present, key headings present, signature block present, conditional sections render correctly)
- `<template>_pagination_test.dart` (golden) — full document → `%PDF` + reasonable byte size

Plus:
- `nte_picker_provider_test.dart` (skipped without Supabase fixtures; manual smoke documented)
- Bulk-generate smoke test: Salary Adjustment over 3 employees produces 3 PDFs + combined PDF, page numbering resets per employee.

## Phases for the implementation plan

Each template = ~5 tasks. 5 × 5 = 25 tasks + a few shared/registration tasks. Per the prior pattern:

1. **Shared: ntesByEmployeeProvider + EmployeeDocumentSummary** (1 task)
2. **Final Pay** — inputs + validate + autofill + build + form + register + golden (5 tasks)
3. **Salary Adjustment / Promotion** — same shape, with type toggle wiring (5 tasks)
4. **NOD** — same shape + NTE picker integration (5 tasks)
5. **Regularization** — same shape (5 tasks)
6. **Resignation Acceptance** — same shape (5 tasks)
7. **Registry + filename prefix + generate_screen wiring** — single batched task (1 task)
8. **Final green-bar checkpoint** (1 task)

**Total: ~27 tasks**, comparable to Hiring and Performance MVPs.

## Open questions to resolve at plan time

1. **NOD's NTE autofill depth**: v1 only autofills `nteDate` (from the NTE document's `created_at`) and copies the NTE's `title` into charges. Auto-pulling the original NTE's input fields (findings, violations) requires either persisting them at NTE generation time (we don't today) or storing them. For v1: HR pastes; v2 enhancement to persist NTE inputs at generation.
2. **Salary Adjustment / Promotion: PROMOTION mode handling of declared_wage_override**: when a promotion changes the role's scorecard, does the employee's `declaredWageOverride` need to update too? Verify with HR practice; for v1 the letter is just a notice — the actual employee record update is a separate HR action.
3. **Regularization auto-flips employmentType**: should clicking "generate" on the Regularization letter also UPDATE the employee's `employmentType` from PROBATIONARY to REGULAR and stamp `regularizationDate`? v1: NO — the letter is just a document. The employment-type flip is a separate (manual or workflow-driven) action. v2 can wire this up.

## Risks

- **NTE autofill weak in v1**: HR pasting charges into the NOD is a workaround for not having stored NTE inputs. If the user wants tight NOD→NTE coupling, we need to persist NTE inputs first (~2-3 extra tasks). Decision deferred to plan time.
- **PROMOTION mode complexity**: the form has two modes. Need careful Form widget wiring to show/hide fields based on `type`. Mirrors NDA-style toggle pattern; should be straightforward.
- **Final Pay HR overrides + provider data**: when HR overrides a line, we lose the link to the provider data. If `finalPayBreakdownProvider` updates later (e.g., due to a backdated payroll change), the document already-generated still shows the old override. That's correct historical behavior; document the snapshot semantic.
- **Probationary Regularization gate vs Performance MVP overlap**: the Performance 5-month check-in is the trigger condition, but the letter doesn't auto-fire. v1: HR manually generates after Performance review. v2 can auto-fire from PROBATION_5M completion.

## What this unblocks (downstream)

- **Closing the disciplinary loop**: NTE → NOD pair brings Luxium to PH Labor Code compliance.
- **Performance → Regularization wiring**: PROBATION_5M COMPLETED → auto-generate Regularization Letter (v2 enhancement, low effort once both halves exist).
- **Separation workflow completeness**: Resignation Acceptance plugs the "voluntary separation" gap in the existing SEPARATION workflow. NOD-with-TERMINATION-decision could auto-fire the SEPARATION workflow (v2).
- **Total templates 7 → 12**: brings document coverage to ~80% of Luxium HR's recurring letter needs. Remaining gaps (Generic Memo, Clearance Form, Recommendation Letter, Final Warning) become a future batch 3 — none are legally required.
