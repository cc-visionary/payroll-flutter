# Bulk Document Generation — Design

**Date:** 2026-05-23
**Status:** Draft

## Goal
Generate **one document type for many employees** in a single run (e.g. COEs for all separated staff, NDAs for a new-hire batch, Liability Waivers for everyone on a company outing). Output: a **combined PDF** (all employees' docs concatenated, each starting on a new page — for one print job) AND a **ZIP** of individual per-employee PDFs (for filing/emailing).

Bulk-generate, not bulk-print. The user picks a template + selects multiple employees; the system autofills each from employee/company/scorecard data, builds each doc, and produces the combined PDF + ZIP. Employees whose data fails validation (or whose template gate blocks them — e.g. COE for a still-active employee) are skipped and reported.

## Eligible templates
Only the **fully-autofill** templates support bulk (no unique per-employee manual input):
- Certificate of Employment (COE)
- Employment Contract
- Confidentiality & NDA
- Liability Waiver (Company Outing) — plus **shared** outing date + location entered once for the whole batch.

NTE, Non-Reg, Quitclaim are excluded (they need per-employee charges/findings/final-pay).

Mark eligibility on the template: add `bool get supportsBulk => false;` to `DocumentTemplate`, override `=> true` in the four eligible templates.

## Architecture

### Bulk service — `lib/features/documents/bulk/bulk_generate.dart`
```dart
class BulkSkip { final String employeeName; final String reason; }
class BulkGenerateResult {
  final Uint8List combinedPdf;                 // all docs, page-break separated
  final List<({String filename, Uint8List bytes})> files;  // per-employee PDFs (ZIP source)
  final List<BulkSkip> skipped;                // validation/gate failures
  final int generatedCount;
}

Future<BulkGenerateResult> bulkGenerate({
  required DocumentTemplate template,
  required List<String> employeeIds,
  required WidgetRef ref,
  required PdfTheme theme,
  Map<String, Object?> shared = const {},      // e.g. {'outingDate': DateTime, 'outingLocation': String}
}) async { ... }
```
Per employee id:
1. `emp = await ref.read(documentEmployeeProvider(id).future)`; if null → skip ("employee not found").
2. `co = emp.hiringEntityId == null ? null : await ref.read(hiringEntityByIdProvider(emp.hiringEntityId!).future)`.
3. `ctx = AutofillContext(employee: emp, company: co, ref: ref)`.
4. Gate check: `if (template.gates(ctx).isNotEmpty) → skip(reason = gate.reason)`.
5. `inputs = await template.autofill(ctx)`.
6. Apply shared overrides — template-specific: if `template is LiabilityWaiverTemplate`, `inputs = (inputs as LiabilityWaiverInputs).copyWith(outingDate: shared['outingDate'], outingLocation: shared['outingLocation'])`. (Only the Waiver has shared fields in v1.)
7. `errors = template.validate(inputs)`; if non-empty → skip(reason = first error message).
8. `blocks = template.build(inputs)`.
9. Append to combined list: `[...blocks, PageBreakBlock()]` (drop the trailing page break on the last). Build the per-employee PDF via `buildDocumentPdf(blocks: blocks, theme: theme)` → add `(filenameForDocument(templateId: template.id, employeeId: emp.id, employeeNumber: emp.employeeNumber, date: today), bytes)` to `files`.
10. Combined PDF: `buildDocumentPdf(blocks: combinedBlocks, theme: theme)` once over the concatenated blocks.

The combined-blocks concat with `PageBreakBlock` between employees relies on `buildDocumentPdf`/`pw.MultiPage` honoring `PageBreakBlock` → `pw.NewPage` (it does). Each employee's doc therefore starts on a fresh page.

ZIP: use the `archive` package (already used by `lib/features/payroll/payslips/payslips_export.dart` — follow that pattern: `Archive` + `ArchiveFile(name, bytes.length, bytes)` + `ZipEncoder().encode(archive)`).

### Screen — `lib/features/documents/bulk/bulk_generate_screen.dart`
Route `/documents/bulk`. ConsumerStatefulWidget. Layout: left config panel, right results.
- **Template picker**: dropdown/cards of `kTemplates.where((t) => t.supportsBulk)`.
- **Employee multi-select**: searchable checklist from `employeeListProvider` (include archived — COE targets separated staff; the gate skips ineligible ones at generate time). Show selected count.
- **Shared fields** (template-aware): when the Liability Waiver is selected, show Outing Date + Outing Location inputs (applied to all). Other templates: none.
- **Generate button** (disabled until ≥1 employee selected): calls `bulkGenerate(...)`, shows a progress spinner, then the result.
- **Results**: "{n} generated, {m} skipped". List skipped employees + reasons. Two actions: **Download Combined PDF** (`Printing.sharePdf` / save) and **Download ZIP** (`Printing.sharePdf` won't do zip — use the existing file-save approach; on desktop write to a save dialog, or reuse the payslips ZIP-download path). **Print** the combined PDF (`Printing.layoutPdf`).
- Permission gate: `userProfile.canManageEmployees` (same as the rest of Documents).
- Audit: log a single `logExport` for the bulk run (template_id, count, action).

### Entry point
On the Documents hub (`documents_screen.dart`), add a **"Bulk Generate"** button (e.g. in the "Generate a Document" section header) that navigates `context.go('/documents/bulk')`.

### Route
`lib/app/router.dart`: add `GoRoute(path: '/documents/bulk', builder: (c,s) => const BulkGenerateScreen())`.

## ZIP / download mechanics
Follow `payslips_export.dart` for the ZIP build + download. For combined PDF download/print, reuse the `PdfPreviewScaffold` actions pattern or `Printing.sharePdf`/`layoutPdf` directly. Filenames: `{Prefix}_{employeeNumber or id8}_{yyyymmdd}.pdf` via `filenameForDocument`; ZIP name `{Prefix}_bulk_{yyyymmdd}.zip`.

## Testing
- `bulk_generate_test.dart`: with a stubbed ProviderContainer (employees + entities overridden), `bulkGenerate` for COE over 2 eligible + 1 gate-blocked employee → combinedPdf `%PDF`, files.length == 2, skipped.length == 1. (If full provider stubbing is heavy, at minimum a unit test of the combined-blocks concatenation / skip logic.)
- Reuse existing template build/golden coverage for the per-doc rendering.

## Phases
1. `supportsBulk` flag on DocumentTemplate + 4 overrides.
2. `bulk_generate.dart` service (autofill loop, combined PDF, ZIP, skip list) + test.
3. `bulk_generate_screen.dart` UI + route + hub entry point.

## Out of scope (v1)
- Per-employee field editing within the bulk flow (it's autofill-only; skips on validation failure).
- Bulk for NTE/Non-Reg/Quitclaim.
- Saving generated PDFs to `employee_documents` (generation stays ephemeral).
