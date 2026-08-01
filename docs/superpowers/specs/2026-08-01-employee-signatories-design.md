# Employee Signatories — Design

**Date:** 2026-08-01
**Status:** Approved (pending user review of this doc)

## Problem

Signatory identities are scattered and hardcoded:

- The payslip PDF hardcodes "Brixter Del Mundo / HR Manager" (`lib/features/payroll/payslips/payslip_pdf.dart` `_signatureBlock`).
- The 12 document templates prefill signatory names from free-text hiring-entity fields (`legal_signatory_name`, `legal_signatory_role`, `hr_manager_name`) — plain strings, not linked to employee records.
- No generated document carries an actual signature; every sign line is blank.

## Goal

Flag employees as authorized signatories on their profile. Generated documents (the 12 templates + the payslip PDF) automatically carry the assigned signatory's printed name, title, and transparent-PNG signature image — rendered over the sign line so documents come out already signed.

## Decisions made during brainstorming

| Decision | Choice |
|----------|--------|
| Where assignments live | Flags on the employee record (not per hiring entity, not a separate settings screen) |
| Granularity | Signing **capacity**: `HR Signatory` and `Legal/Authorized Signatory` — matches the two slots templates already have (`hrManagerName` / `authorizedSignatoryName`-family) |
| Signature image | Yes — transparent PNG uploaded per signatory, rendered overlapping the sign line |
| Storage approach | Approach B: columns directly on `employees` (user's explicit choice over a dedicated table) |
| Historical fidelity | Signature PNG is **snapshotted into the saved document inputs JSON** at generation time; saved docs never silently re-sign |

## 1. Schema — new migration

Four columns on `employees`:

```sql
ALTER TABLE employees
  ADD COLUMN is_hr_signatory boolean NOT NULL DEFAULT false,
  ADD COLUMN is_legal_signatory boolean NOT NULL DEFAULT false,
  ADD COLUMN signatory_title text,
  ADD COLUMN signature_png text;  -- base64 transparent PNG
```

At most one signatory per capacity per company, enforced by the DB:

```sql
CREATE UNIQUE INDEX employees_one_hr_signatory
  ON employees (company_id) WHERE is_hr_signatory;
CREATE UNIQUE INDEX employees_one_legal_signatory
  ON employees (company_id) WHERE is_legal_signatory;
```

- `signatory_title` is the title **printed on documents** (e.g. "HR Manager"), deliberately independent of the internal role name.
- No data backfill. Brixter gets flagged through the UI after deploy.
- One employee may hold both capacities.
- The hiring-entity fields (`legal_signatory_name`, `legal_signatory_role`, `hr_manager_name`) are kept unchanged as fallback — no removal in this project.

## 2. Employee model + repository

- `Employee` model (`lib/data/models/employee.dart`) gains the four fields, wired through `fromRow`/save payload.
- `EmployeeRepository` gains a lookup for the flagged signatory per capacity (company-scoped), plus updates that set/clear the flags. Transfer = clear the current holder, then set the new one (two updates; the partial unique index is the backstop).
- List fetches use `select()` (all columns); only 1–2 rows will ever carry a PNG (~20–50 KB), so bloat is negligible.

## 3. Employee profile UI

New **"Authorized Signatory"** card on the employee profile (`lib/features/employees/profile/`), visible and editable to HR admins only (existing role gating):

- Toggles: HR Signatory, Legal Signatory.
- Title field (defaults empty → placeholder suggests the employee's role title).
- Transparent-PNG upload with preview + remove, following the hiring-entity logo picker pattern (base64, PNG only).
- Enabling a capacity someone else holds → confirm dialog "Transfer HR Signatory from X to Y?" → on confirm, clear X's flag, then set Y's.

## 4. PDF signature blocks

`SignatureBlock`, `MultiSignatureBlock`/`SignatoryParty`, and `CenteredSignatureBlock` (`lib/features/documents/blocks/`) gain an optional signature-image parameter (`Uint8List`), rendered overlapping the sign line — transparent PNG, ~40 pt tall, anchored so it sits on/above the line like a wet signature.

**Only company-side parties get the image.** Employee/counterparty lines always stay blank for physical signing.

## 5. Document generation (12 templates)

- The generate screen's prefill (`lib/features/documents/generate_screen.dart`) resolves the flagged HR + Legal signatories once, then fills the existing per-template fields (`hrManagerName`, `authorizedSignatoryName`, `employerSignatoryName`, `signatoryRole`, etc.) from the flagged employee's name + `signatory_title`.
- Fallback order per field: flagged signatory → hiring-entity default (current behavior) → empty. Users can still overtype any field.
- Each template with a company-side sign line gains an optional base64 PNG field in its inputs class (`toJson`/`fromJson`/`copyWith`), snapshotted at generation. Saved documents re-render with the signature as it was signed; JSON without the field (all existing saved docs) renders exactly as today (`fromJson` default = null).
- Bulk generate flows pick this up automatically since they go through the same inputs.

## 6. Payslip

- `loadPayslipPdfContext` (`lib/features/payroll/payslips/payslip_pdf_context.dart`) resolves the company's HR signatory alongside the hiring entity; `PayslipPdfContext` and `PayslipPdfInput` gain `hrSignatoryName`, `hrSignatoryTitle`, `hrSignaturePng`.
- `_signatureBlock` in `payslip_pdf.dart` drops the hardcoded name and renders the resolved trio; the PNG overlaps the line when present.
- Fallback when nobody is flagged: hiring entity's `hr_manager_name` with title "HR Manager", no image; if that's also empty, the sign line renders with no printed name.
- One seam covers preview, bulk ZIP export, and the Lark approval send flow.

## 7. Security

- `signature_png` is readable by anyone who can read `employees` (company-scoped RLS) — accepted trade-off of storing it on the employee row.
- Writes go through existing HR-admin employee-edit policies; no new RLS policies needed.

## 8. Testing

- Inputs-model round-trip tests: PNG field survives `toJson`/`fromJson`; missing field defaults to null (backward compat with existing saved docs).
- Signatory resolution: flagged employee wins over entity default; fallback chain when unflagged.
- Payslip PDF build smoke test with signature bytes present and absent.
- Gate on `flutter analyze` (repo is NOT gated on `dart format` — match surrounding style).

## Out of scope

- Removing the hiring-entity signatory text fields.
- Per-document-type signatory overrides.
- Counterparty/employee e-signatures.
- Any edge-function/Lark changes (payslip PDFs are built client-side before send).
