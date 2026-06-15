# Employee Document Persistence — Design

**Date:** 2026-06-15
**Status:** Implemented (revised — see note)

> **Revised 2026-06-15 (post-implementation):** The Storage approach described
> below was **dropped**. We persist **settings only** — the input
> `generation_options` JSON in `employee_documents`; the PDF is generated on
> the fly and is **not** stored (no Storage bucket, no `file_path`). The
> settings save is **best-effort / non-blocking**: a failure warns but never
> blocks Preview/Download. Regenerating a PDF from saved settings (`fromJson` +
> render) is **deferred**. Any section below referring to a Storage bucket,
> frozen PDF, `file_path`, or signed-URL retrieval is superseded by this note.

## Goal

When an HR/Admin user generates an employee document, persist a **frozen PDF
copy** plus the **input settings** to that employee's record so there is a
permanent digital copy "if ever". Restructure the generate flow into an explicit
**Form → Generate → Preview** sequence where *Generate* is the save point.

## Current state (verified)

- **`employee_documents` table already exists** (migration
  `20260414000005_employees.sql`) with everything we need:
  `document_type`, `title`, `file_name`, `file_path`, `file_size_bytes`,
  `mime_type`, `generation_options` (jsonb, reserved for the input settings —
  currently unused), `status` (enum: DRAFT/PENDING_APPROVAL/ISSUED/SIGNED/
  VOIDED/SUPERSEDED/EXPIRED), `supersedes_document_id`, soft-delete
  `deleted_at`, plus RLS and an audit trigger.
- The **employee Documents tab** (`employeeDocumentsProvider`) and the
  **Documents hub** (`allDocumentsProvider`) already read this table. They show
  "No documents on file" only because **nothing writes to it**.
- The **generate flow** (`generate_screen.dart` + `pdf_builder.dart`) renders
  the PDF in-memory → Download/Print, and only logs an `EXPORT` row to
  `audit_logs`. No row is inserted into `employee_documents`; the full
  `TemplateInputs` object is available at PDF build time but never serialized.
- **No Supabase Storage bucket** is configured (`config.toml` buckets are
  commented out); `file_path` is unused.
- `TemplateInputs` subclasses have **`toDebugMap()` only** — no `toJson`.

## Decisions (from brainstorming)

| Decision | Choice |
|---|---|
| What is saved | **Frozen PDF (Storage) + settings (generation_options JSON)** |
| Save trigger | **Explicit Generate button** — Form → Generate → Preview |
| Status at Generate | **ISSUED** |
| Scope | **All 11 document templates** |
| Re-generate (same session) | **Update the same record** (no duplicates) |
| New session, same doc type | **New record; prior same-type doc → SUPERSEDED** |

> **"Session"** = the lifetime of one mounted generate-screen instance for a
> given employee + template. The saved record id is held in that screen's state
> (`sessionRecordId`); re-generating before leaving updates it. Navigating away
> and reopening the generator starts a new session → a new record.
| Applicant-mode offer letters | **Skip persistence in v1** (no `employee_id` FK target) |
| `logoBytes` | **Excluded from settings JSON** (baked into frozen PDF, re-derivable) |

## Architecture / Components

### 1. Storage bucket
- New **private** bucket `employee-documents`; object path
  `{employee_id}/{document_id}.pdf`.
- Migration adds the bucket + Storage RLS policies mirroring the table
  (SUPER_ADMIN / ADMIN / HR full; employee reads own + direct reports).
- `config.toml` storage entry.

### 2. Settings serialization
- Add `toJson() → Map<String, dynamic>` to the `TemplateInputs` base and **all
  ~11 subclasses**, handling nested value objects (`ContractResponsibility`,
  `ContractKpi`, `TrainingWage`, etc.). `logoBytes` is **omitted**.
- Stored verbatim in the existing `generation_options` jsonb column.
- `fromJson` / re-opening saved settings back into the form is **out of v1
  scope** (the employee tab views the frozen PDF, which needs no deserialize).

### 3. Save service
`EmployeeDocumentRepository.saveGenerated({ employeeId, documentType, title,
fileName, pdfBytes, inputs, templateId, sessionRecordId? })`:
1. Upload `pdfBytes` to Storage at `{employeeId}/{newOrExistingId}.pdf`.
2. Insert (or update the session record) into `employee_documents` with
   `generation_options = inputs.toJson()`, `file_path`, `file_size_bytes`,
   `mime_type = 'application/pdf'`, `status = 'ISSUED'`,
   `generated_from_template_id`.
3. On a **new** session where a prior `ISSUED` doc of the same type exists, set
   `supersedes_document_id` and mark the old row `SUPERSEDED`.
4. Return the saved record id (carried as `sessionRecordId` for re-generate).

### 4. Generate-screen restructure (all templates)
- **Form view:** fields + a primary **Generate** button (disabled until valid).
  Download/Print are **not** present here; nothing is saved yet.
- **Generate:** validate → `buildDocumentPdf(...)` → `saveGenerated(...)` →
  navigate to Preview.
- **Preview view:** PDF viewer + **Download** + **Print** (export the
  already-saved bytes) + **Back to edit** (revise → re-Generate updates the
  same record).

### 5. Employee Documents tab
- Already lists rows. Add a **status chip** (DRAFT/ISSUED/SUPERSEDED) and a
  **View/Download** action per row that fetches the stored PDF via a signed URL.

### 6. Audit
- The existing `employee_documents` audit trigger logs the insert/update
  automatically — no extra wiring.

## Data flow

```
form state ──Generate──▶ validate ──▶ render PDF bytes
                                         │
                          upload bytes ──┴──▶ Storage (employee-documents/{emp}/{id}.pdf)
                                         │
              insert/update employee_documents
              (generation_options = inputs.toJson(),
               file_path, file_size, status = ISSUED)
                                         │
                                  navigate ──▶ Preview ──▶ Download / Print
```

## Error handling

- **Save failure** (Storage or DB): surface an error, **stay on the form**, do
  not navigate, do not lose form state. (Unlike audit logging, a persistence
  failure must be visible — the user is relying on the saved copy.)
- **Applicant mode** (no `employee_id`): skip the save and allow Download/Print
  directly, with a small note that the copy isn't filed to an employee yet.
- **Storage RLS denial**: treated as a save failure (above).

## Testing

- `toJson` round-trip per template (every field + nested objects; `logoBytes`
  excluded).
- `saveGenerated`: uploads bytes + inserts a row with the correct columns;
  same-session update vs. new-session record; supersede logic.
- Generate flow: invalid form → button disabled; Generate → record created →
  Preview shown; save failure → stays on form.
- RLS: HR can save; an employee cannot write another employee's document.

## Out of scope (v1)

- Re-opening a saved document's settings back into the form (`fromJson`
  re-edit). Frozen-PDF view only.
- Applicant offer-letter persistence and carry-over on hire.
- Acknowledgment / e-signature workflow (columns exist; not wired here).

## Risks

- Restructuring the generate screen touches all 11 templates' UX — regression
  risk; mitigated by tests + a manual run of each path.
- Storage-bucket RLS correctness (must match table RLS).
