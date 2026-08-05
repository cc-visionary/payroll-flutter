# Penalty Repayment Workflow + Agreement Document — Design

**Date:** 2026-08-05
**Status:** Drafted autonomously (user review pending)

## Problem

Recording a penalty today is a bare dialog write. `showAddPenaltyDialog`
(`lib/features/employees/profile/tabs/add_penalty_dialog.dart`) inserts a
`penalties` row plus N `penalty_installments` and stops there. Nothing
documents the deduction: no agreement for the employee to sign, no workflow
trail, no paper for a DOLE inspection. Under Labor Code Art. 113 a deduction
from wages for employer loss/damage generally needs the employee's written
authorization — the app currently produces none.

Meanwhile every other consequential HR event (separation, compensation change,
hiring) already runs through the workflow module and queues a DRAFT document.
Penalties are the outlier.

## Goal

Recording a penalty becomes a workflow: the penalty is created, a **Penalty
Repayment Agreement** document is queued as DRAFT, and a `REPAYMENT_AGREEMENT`
workflow instance tracks it to completion. The agreement renders the
installment schedule and carries a signature block the employee can sign — with
their stored signature image when they have one, otherwise a blank wet-signature
line.

## Decisions

| Decision | Choice | Why |
|---|---|---|
| Workflow type | Reuse the existing `REPAYMENT_AGREEMENT` enum value | Already in `workflow_type` on prod (verified); no ALTER TYPE migration |
| When the penalty row is written | Up front, before seeding the workflow | Mirrors `compensation_change_action.dart`; no code in this repo performs writes on step completion, and building that seam is a bigger change than this feature needs |
| Document identity | New template `penalty_agreement` → `document_type` `PENALTY_AGREEMENT` | `employee_documents.document_type` is `varchar(50)`, not an enum — no migration |
| Employee signature source | The subject employee's existing `employees.signature_png` | Column already exists (migration 20260801000001) and the profile card already uploads it for any employee; only the *read* path was capacity-scoped |
| Signature semantics | Rendered image when present, blank sign line when absent | Matches how every other template treats the employee side; no e-signature/consent flow invented |
| Migration | **None** | Enum value, doc-type column, and signature column all already exist |

## 1. The penalty workflow

New action `lib/features/employees/profile/widgets/penalty_workflow_action.dart`,
mirroring `runCompensationChange` step for step:

1. Insert the `penalties` row + N `penalty_installments` (moved out of the
   dialog into a shared helper so both the plain dialog and the workflow path
   use one split-and-insert implementation — the "last slot absorbs the
   rounding residual" rule must not fork).
2. Insert a DRAFT `employee_documents` row: `document_type: 'PENALTY_AGREEMENT'`,
   title "Penalty Repayment Agreement", `status: 'DRAFT'`.
3. Seed a `REPAYMENT_AGREEMENT` workflow via a new `seedPenaltyWorkflow` in
   `lib/features/workflows/seeders.dart`:
   - instance `context: {'penalty_id': …}`, title
     "Penalty Repayment — &lt;employee&gt;"
   - step 0 — `DOCUMENT_GENERATION` "Generate Penalty Repayment Agreement",
     `input_data: {'template_id': 'penalty_agreement', 'penalty_id': …,
     'employee_document_id': …}`, `generatedDocumentId` set
   - step 1 — `APPROVAL` "Employee signed the agreement", completed by HR when
     the signed copy is back. Deliberately a manual approval: Lark approvals
     are not wired to workflows at all (verified), so pretending otherwise
     would be fiction.
4. Invalidate `financialsByEmployeeProvider`, `employeeDocumentsProvider`,
   `allDocumentsProvider`, `workflowListProvider`.

`Add Penalty` on the Financials tab routes through this action. The edit path
keeps using the plain dialog (editing an existing penalty must not spawn a
second workflow).

### Known gap this exposes

A `DOCUMENT_GENERATION` step currently has **no path to COMPLETED** in the UI —
`_StepActions` renders "Generate now" + "Skip" only, and the generate screen
never returns to the workflow. Step 0 would strand at IN_PROGRESS forever. Fix
in scope: render "Mark complete" for `DOCUMENT_GENERATION` steps alongside
"Generate now" (the `markStepCompleted` call at
`workflow_detail_screen.dart:620` already handles `generatedDocumentId` — that
branch is currently dead code).

## 2. The document template

New template following the `final_pay` pattern exactly (closest money analog).

**`PenaltyAgreementInputs`** — employee block (`employeeId`, `employeeFullName`,
`employeePosition`), company block (`companyId`, `companyName`,
`companyAddress`, `hrManagerName`), penalty block (`penaltyId`, `description`,
`totalAmount` as `Decimal`, `effectiveDate`, `remarks`), plus
`List<PenaltyInstallmentLine> installments` (a nested class with its own
`toJson`/`fromJson`, mirroring `NteCharge`), `Uint8List? logoBytes` (excluded
from JSON), `String? companySignaturePngB64`, `String? employeeSignaturePngB64`.

**Layout** (`build`): `LetterheadBlock` → `LetterMetaBlock` → intro paragraph
naming the incident and the total → `HeadingBlock('Repayment Schedule')` →
`TableBlock` with columns *Installment · Amount · Status* → an authorization
paragraph (the employee authorizes salary deduction of the scheduled amounts) →
`MultiSignatureBlock` with two parties: HR (company signature image) and the
employee (their own image when present, blank line otherwise).

`TableBlock` is used here rather than `KeyValueBlock` because an installment
schedule is genuinely tabular; it is an existing block, just unused by document
templates so far.

**`gates()`** returns a `Gate` when the employee has no `ACTIVE` penalty —
mirroring `FinalPayTemplate`'s separated-employee gate.

**`autofill()`** resolves the penalty by `ctx.penaltyId` when threaded (the
workflow path) and otherwise the employee's most recent ACTIVE penalty, then
fills the schedule from `penalty_installments` ordered by
`installment_number`. Signature snapshots: `ctx.hrSignatory?.signaturePngB64`
for the company side, `ctx.employee?.signaturePngB64` for the employee side.

`supportsBulk` stays false — an agreement is per-penalty.

## 3. Threading `penaltyId`

Exactly mirrors how `changeId` reaches `SalaryAdjustmentTemplate` today:
`AutofillContext.penaltyId` → `?penaltyId=` query param on
`/documents/generate/:templateId` → `GenerateScreen` ctor → `_contextFor` →
`buildGenerateDocumentUrl(penaltyId:)`, and `_generateNow` in the workflow
detail screen reads `step.inputData['penalty_id']` for
`REPAYMENT_AGREEMENT` workflows.

## 4. Registration checklist

Mandatory edits for any new template (all verified against the existing code):

1. `templates/template_registry.dart` — add to the `disciplinary` category
2. `document_type_mapping.dart` — `'penalty_agreement' → 'PENALTY_AGREEMENT'`
   (enforced by test)
3. `core/pdf/pdf_filename.dart` — `_prefixFor` case
4. `view/saved_document_renderer.dart` — id in
   `kReRenderableSavedTemplateIds` **and** a `case` in the switch (enforced by
   test)
5. `generate_screen.dart` — state field, `_runAutofill`,
   `_onPickerEmployeeChanged`, `_onPickerCompanyChanged`, `_formFor`,
   `_descriptorFor`
6. `workflows/seeders.dart` — `_templateIdByDocType` + `_docLabel` entries

## 5. Employee signature UI

The "Authorized Signatory" card already uploads a PNG to
`employees.signature_png` for any employee regardless of capacity flags — only
the read path was HR/Legal-scoped. Reword the card so the signature field reads
as the employee's own signature (used on documents they sign), leaving the two
capacity toggles as-is. No schema change, no new upload widget.

## 6. Testing

- `penalty_agreement_from_json_test.dart` — round-trip including the nested
  installment list and both signature fields; missing fields default to null.
- `penalty_agreement_validate_test.dart` — total must be > 0, installments
  non-empty, schedule sums to the total.
- `penalty_agreement_build_test.dart` — builds blocks with and without each
  signature image.
- `seeders_test.dart` — new case asserting the two-step
  `REPAYMENT_AGREEMENT` seed.
- Gate on `flutter analyze` (repo is not gated on `dart format`).

## Out of scope

- Any digital-signature/e-consent flow (capture pad, `SIGNED` status
  transition, `acknowledged_at` — those columns stay unused).
- Lark approval routing for workflows (no workflow ever touches Lark today).
- Penalty types (`penalty_types` table stays unused; description remains free
  text).
- Backfilling agreements for the four existing penalties.
