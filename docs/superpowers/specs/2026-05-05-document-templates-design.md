# Document Templates — Design

**Date:** 2026-05-05
**Status:** Draft, awaiting review
**Owner:** Donald
**Replaces:** `lib/features/documents/documents_screen.dart` (currently a coming-soon placeholder); supersedes the static "Generate Document" snackbar in `lib/features/employees/profile/tabs/documents_tab.dart`.

## Goal

Give Luxium HR a code-defined, block-based document generator that produces three legal HR documents on demand:

1. **Quitclaim** — release/waiver issued at separation.
2. **Certificate of Employment (COE)** — issued only after separation.
3. **Notice to Explain (NTE)** — disciplinary notice with rich-text charges and bullet-list violations.

Generation is **fully ephemeral**: HR fills a form, sees a live PDF preview that is byte-identical to what Generate produces, and prints/saves via the OS dialog. Nothing is written to the database, no PDF bytes are uploaded to storage. If HR wants a record, they save the file themselves and upload it to the existing `employee_documents` flow (out of scope for this spec).

The system is built on a reusable block library that also covers four future templates (Notice of Non-Regularization, Preventive Suspension Memo, Employee Acknowledgment & Repayment Agreement, Employment Contract) so they can be added later as one Dart file each, no refactor.

## Non-goals

- **Saving generated PDFs** to storage or `employee_documents`. Generation is ephemeral; HR re-fills the form to re-issue.
- **Audit trail** of who generated what for whom. If HR wants a record, they save the printed PDF and upload it via the existing Documents tab.
- **HR-authored templates.** Templates are code-defined Dart classes. A future spec can lift them to a `document_templates` table once the block library is proven.
- **E-signature integration.** Signature blocks render a name + date + signature line; physical signing happens off-system.
- **Lark approval routing** (`lark_approval_instance_code` etc. on `employee_documents`). This is for uploaded artifacts, not generated previews.
- **Templates beyond the v1 three** (Quitclaim, COE, NTE). Suspension Memo, Non-Regularization, Acknowledgment & Repayment, Employment Contract are deferred. The block library is designed to express them; their template classes are future work.
- **Bulk issuance** ("annual COE runs", "policy re-acknowledgments" from the coming-soon copy). Single-document flow only.

## Architectural approach

**Approach 1 of three considered**, recommended and accepted: a code-defined `DocumentTemplate` class per template, composing reusable `Block` primitives that render to a single `pdf` package output. The right-pane preview displays the actual generated PDF via `printing.PdfPreview` — there is **one render path**, not two. This eliminates preview-vs-PDF drift, gives WYSIWYG pagination including page numbers, and matches the existing payslip preview pattern in `lib/features/payroll/payslips/payslip_preview_screen.dart`.

Approaches considered and rejected:

- **Per-template mega-widget with shared PDF helpers** — less ceremony, but every new template re-implements form/preview/PDF wiring; visual consistency depends on developer discipline.
- **JSON-driven templates from day one** — premature; we don't yet know the right block shape. Approach 1 earns the right to become this once the block library is battle-tested.

## Folder layout

```
lib/features/documents/
├── documents_screen.dart            # Replaces coming-soon. Template picker.
├── generate_screen.dart             # Form (left) + PdfPreview (right), two-pane.
│
├── blocks/                          # Block primitives — single render path (toPdf only)
│   ├── block.dart                   # abstract Block { pw.Widget toPdf(PdfTheme); }
│   ├── pdf_theme.dart               # fonts, sizes, margins, page-number footer config
│   ├── title_block.dart
│   ├── heading_block.dart
│   ├── section_heading_block.dart   # "1. Reason for Deduction" pattern
│   ├── paragraph_block.dart
│   ├── emphasis_paragraph_block.dart
│   ├── bullet_list_block.dart
│   ├── numbered_list_block.dart
│   ├── nested_numbered_list_block.dart
│   ├── rich_text_block.dart         # Quill Delta → pw.RichText
│   ├── key_value_block.dart
│   ├── company_header_block.dart
│   ├── letter_meta_block.dart       # Date/To/From/Subject KV with dividers
│   ├── memo_header_block.dart       # COMPOSITE: title + company + meta + salutation
│   ├── memo_acknowledgment_block.dart  # COMPOSITE: receipt + refusal clause + witnesses
│   ├── table_block.dart             # filled rows
│   ├── fillable_table_block.dart    # blank rows for hand-fill
│   ├── checkbox_list_block.dart     # printable checkboxes (e.g., repayment options)
│   ├── receipt_block.dart           # received-by + name & sig + date/time
│   ├── refusal_clause_block.dart
│   ├── signature_block.dart         # single signatory
│   ├── multi_signature_block.dart
│   ├── page_break_block.dart        # explicit pw.NewPage
│   └── spacer_block.dart
│
├── templates/                       # One file per template
│   ├── document_template.dart       # abstract DocumentTemplate<I extends TemplateInputs>
│   ├── quitclaim_template.dart      # v1
│   ├── coe_template.dart            # v1
│   ├── nte_template.dart            # v1
│   └── template_registry.dart       # const list of all templates
│
├── inputs/                          # Typed input models + form widgets
│   ├── input_field.dart             # base FormField wrappers + locked-with-unlock pattern
│   ├── employee_picker.dart
│   ├── company_picker.dart
│   ├── date_field.dart
│   ├── amount_with_breakdown.dart   # quitclaim final-pay chip
│   ├── charges_editor.dart          # NTE list of {title, body Delta}
│   ├── violations_editor.dart       # NTE bulleted list editor
│   └── quill_field.dart             # rich-text field used in charges_editor
│
├── pdf/
│   ├── pdf_builder.dart             # walks Block list, returns Future<Uint8List>
│   └── delta_to_pdf.dart            # Quill Delta → pw.RichText runs
│
└── providers.dart                   # Riverpod: autofill data sources
```

**Routes** (added to `lib/app/router.dart`):

- `/documents` — template picker (replaces coming-soon).
- `/documents/generate/:templateId` — form + preview, optional `?employeeId=` for prefill+lock.
- "Generate Document" button on `documents_tab.dart` opens a small template-picker dialog (filtered by gates) → pushes `/documents/generate/<id>?employeeId=<id>`.

**Permission gating:** entry points are visible only when `userProfile.canManageEmployees == true`, matching the existing pattern in `documents_tab.dart`. No new RLS work needed since there are no DB writes.

## Block model

### Single render path

```dart
abstract class Block {
  const Block();
  pw.Widget toPdf(PdfTheme theme);
}
```

There is no `toPreview(BuildContext)` method. The right-pane preview displays the actual generated PDF via `printing.PdfPreview`. One renderer, one source of truth, byte-identical preview-and-output.

### `PdfTheme`

Single shared theme so all templates render as one visual family.

```dart
class PdfTheme {
  final pw.Font displayFont;          // Satoshi
  final pw.Font bodyFont;             // Satoshi
  final pw.Font monoFont;             // Geist Mono — numbers, dates, currencies
  final PdfPageFormat pageFormat;     // A4
  final EdgeInsets pageMargin;        // 25mm
  final double titleSize;             // 22pt
  final double headingSize;           // 14pt
  final double bodySize;              // 11pt
  final PdfColor textColor;           // black
  final bool showPageNumbers;         // default true
  final PageNumberFormat pageNumberFormat;     // "Page X of Y"
  final PageNumberPosition pageNumberPosition; // default bottomCenter
  final double footerFontSize;        // 9pt
  final EdgeInsets footerMargin;      // bottom 12mm
}
```

PDFs are black-on-white. **No Luxium purple in PDFs** — these are legal documents.

### Block catalogue

**Primitives (used directly):**

| Block | Purpose | Used by (v1) | Used by (future) |
|---|---|---|---|
| `TitleBlock(text)` | Centered or left-aligned large bold title | All v1 | All future |
| `HeadingBlock(text)` | Mid-size bold heading | NTE | Suspension, Employment Contract |
| `SectionHeadingBlock(number, title)` | "1. Title" pattern | NTE charges | Acknowledgment, Employment Contract |
| `ParagraphBlock(text)` | Body paragraph; supports `{placeholder}` interpolation | All | All |
| `EmphasisParagraphBlock(text)` | Body paragraph with embedded bold spans | — | Suspension memo |
| `BulletListBlock(items)` | • items | NTE violations | Acknowledgment, Suspension |
| `NumberedListBlock(items)` | 1. 2. 3. items | — | Suspension, Acknowledgment |
| `NestedNumberedListBlock(items)` | Numbered items with bold lead and sub-numbered children | — | Acknowledgment §8 |
| `RichTextBlock(delta)` | Quill Delta with bold/italic/underline/bullet/numbered/nested | NTE charge bodies | Future free-form bodies |
| `KeyValueBlock(rows)` | Two-column aligned label/value | Quitclaim header | All future |
| `CompanyHeaderBlock(name, address)` | Letterhead pattern | All v1 | All future |
| `LetterMetaBlock(date, to, from, subject)` | Date/To/From/Subject with dividers | (used inside MemoHeaderBlock) | (used inside MemoHeaderBlock) |
| `TableBlock(headers, rows, columnWidths)` | Filled table | — | Acknowledgment |
| `FillableTableBlock(headers, blankRows, columnWidths)` | Empty rows for hand-fill | — | Acknowledgment, Suspension |
| `CheckboxListBlock(items)` | Printable empty checkbox + label + body | — | Acknowledgment |
| `ReceiptBlock(fields)` | (used inside MemoAcknowledgmentBlock) | — | — |
| `RefusalClauseBlock(text)` | (used inside MemoAcknowledgmentBlock) | — | — |
| `SignatureBlock(name, role, date)` | Single signatory line | NTE | Suspension, Non-Regularization |
| `MultiSignatureBlock(signatories)` | Two-party signing | Quitclaim, COE | Acknowledgment, Employment Contract |
| `PageBreakBlock()` | Forces `pw.NewPage` | — | Suspension, Employment Contract |
| `SpacerBlock(height)` | Vertical gap | All | All |

**Composites (compose primitives internally; templates use these for memo-style docs):**

- **`MemoHeaderBlock(titleText, company, date, to:{name, subtitle?}, from:{name, subtitle?}, subject, salutation?)`** — renders `TitleBlock` + `CompanyHeaderBlock` + horizontal divider + `LetterMetaBlock` + horizontal divider + optional salutation paragraph.
- **`MemoAcknowledgmentBlock()`** — renders the standard receipt + italic refusal-to-sign clause + quoted refusal text + Witness 1 / Witness 2 lines, matching the canonical Luxium memo footer.

These composites are the default header/footer for memo-style templates (NTE in v1; Suspension Memo, Non-Regularization later). Primitives remain available for non-memo layouts.

### `DocumentTemplate` interface

```dart
abstract class DocumentTemplate<I extends TemplateInputs> {
  String get id;                                    // 'quitclaim' | 'coe' | 'nte'
  String get name;
  String get description;                           // 1-line picker subtitle
  IconData get icon;
  int get version;                                  // bump when block tree changes

  I emptyInputs();
  Future<I> autofill(AutofillContext ctx);
  List<Gate> gates(AutofillContext ctx);
  List<ValidationError> validate(I inputs);
  List<Block> build(I inputs);
}

class AutofillContext {
  final Employee? employee;
  final HiringEntity? company;
  final Ref ref;
}

class Gate { final String reason; }                 // tooltip when blocked
class ValidationError { final String field; final String message; }

abstract class TemplateInputs {
  Map<String, dynamic> toDebugMap();                // logs only — nothing persisted
}
```

`template_registry.dart`:

```dart
const kTemplates = <DocumentTemplate>[
  QuitclaimTemplate(),
  CoeTemplate(),
  NteTemplate(),
];
```

## Locked-with-unlock field pattern

Hard data (amounts, employment dates, company) is autofilled and rendered as a read-only chip with a source caption ("From employment events · 2026-03-12") and an "Override" toggle that converts the field to manual with a warning banner. Soft data (NTE date defaults to today, employee metafields used as display strings) is freely editable from the start.

**COE separation gate is a hard block, not unlockable.** The COE card is grayed in the picker with tooltip "Available only after separation" if the employee has no `SEPARATION` event AND `employees.status != 'SEPARATED'`.

## Data flow

```
User opens /documents
        │
        ▼
TemplatePicker (reads kTemplates registry)
   • For each template + (optional) employee: run gates(ctx)
   • Disabled card with tooltip if any Gate.reason is non-empty
        │ (pick template + employee)
        ▼
GenerateScreen (templateId, employeeId?)
   ├── AutofillContext built from providers (one-shot at screen open)
   │     • employeeProvider(id)               → Employee
   │     • employmentEventsProvider(id)       → HIRE / SEPARATION dates
   │     • hiringEntityProvider(id)           → company name, address
   │     • thirteenthMonthAccrualProvider(id) → quitclaim only
   │     • payslipLinesAggregateProvider(id)  → quitclaim only
   │
   ├── template.autofill(ctx) → I prefilled (locked Autofilled chips)
   ├── template.gates(ctx)    → hard-block list (COE only)
   │
   ├── FormPane (left)                       PdfPreview (right)
   │   • renders typed inputs                • shows the PDF bytes
   │   • locked-with-unlock UX               • re-renders on input change (200ms debounce)
   │   • on change → setState                • displays "Page X of Y" footer per page
   │                                         • placeholder when validate() has errors
   │
   └── Generate button (enabled iff validate(inputs).isEmpty)
            │
            ▼
       PdfBuilder.build(blocks, theme) → Uint8List      // same call as preview
            │
            ▼
       printing.layoutPdf() — system PDF preview/print/save dialog
       (no DB writes, no storage uploads)
```

**One render path**: every input change debounces 200ms; if `validate(inputs)` is empty, the screen calls `template.build(inputs) → blocks`, then `PdfBuilder.build(blocks, theme) → Uint8List`, and `PdfPreview` displays those bytes. Generate button uses the **same call** to produce the file passed to `printing.layoutPdf`. Preview and generated file are byte-identical.

**Autofill is one-shot**, not reactive — fetched once at screen open. If upstream data changes mid-edit, HR re-opens the screen.

**State management:** one `StateNotifier<TemplateInputs>` per generate screen, scoped to the route, family-keyed by `(templateId, employeeId)`. No persistence — navigating away discards state.

**Provider reuse — to expose if not already public:**

- `employmentEventsProvider(employeeId)` — verify presence in `lib/features/employees/profile/providers.dart`; expose if missing.
- `thirteenthMonthAccrualProvider(employeeId)` — table exists per migration `20260420000001_thirteenth_month_accrual.sql`; expose query.
- `payslipLinesAggregateProvider(employeeId, {periodId?})` — thin wrapper over existing payslip-lines selectors.

No changes to existing payroll code beyond exposing these read-only providers.

### Quitclaim final-pay breakdown

Locked-with-unlock chip with expandable breakdown:

```
₱ 47,250.00 · From 13th-month + payslip lines  [▾ breakdown]  [Override]

  Breakdown:
    13th-month accrual ............. + ₱ 21,500.00
    Last cutoff net pay ............ + ₱ 18,000.00
    Unused leave conversion ........ + ₱  9,750.00
    Cash advance (outstanding) ..... − ₱  2,000.00
    ─────────────────────────────────
    Total .......................... ₱ 47,250.00
```

Each breakdown row is itself autofilled; each is individually editable via the same lock/unlock pattern, so HR can correct an off-cycle item without overriding the entire total.

## Per-template specs

### Quitclaim

**Inputs:**

- `employee` — required, locked when entered from profile.
- `company` — required (`hiring_entity` picker); autofilled from `employees.hiring_entity_id`, lock/unlock.
- `dateTerminated` — required date, autofilled from latest `employment_events` SEPARATION, lock/unlock.
- `dateSigned` — required date, default = today, freely editable.
- `finalPayAmount` — required currency, autofilled with breakdown chip, lock/unlock; breakdown lines individually editable.

**Gates:** none.

**Validation:** all required present; `finalPayAmount > 0`; `dateSigned >= dateTerminated`.

**Block tree:**

1. `CompanyHeaderBlock(company.name, company.address)`
2. `SpacerBlock(24)`
3. `TitleBlock("RELEASE, WAIVER, AND QUITCLAIM")`
4. `SpacerBlock(16)`
5. `KeyValueBlock([("Full Name", employee.fullName), ("Final Pay", "₱ {finalPayAmount}"), ("Company", company.name), ("Date Terminated", dateTerminated), ("Date Signed", dateSigned)])`
6. `SpacerBlock(16)`
7. `ParagraphBlock(quitclaimBodyText)` — fixed legal language with `{employee.fullName}`, `{finalPayAmount}`, `{company.name}` interpolation.
8. `SpacerBlock(48)`
9. `MultiSignatureBlock([(employee.fullName, "Employee", dateSigned), (company.signatoryName, company.signatoryRole + " — " + company.name, dateSigned)])`

### Certificate of Employment (COE)

**Inputs:**

- `employee` — required.
- `company` — required, autofilled from employee.
- `dateStart` — required, autofilled from latest `employment_events` HIRE, lock/unlock.
- `dateEnd` — required, autofilled from latest `employment_events` SEPARATION, lock/unlock.
- `position` — required, autofilled from `employees.position` (or current responsibility card title), freely editable.

**Gates:** **hard block** if employee has no `SEPARATION` event AND `employees.status != 'SEPARATED'`. Picker grays the COE card with tooltip "Available only after separation."

**Validation:** all required present; `dateEnd >= dateStart`.

**Block tree:**

1. `CompanyHeaderBlock(company.name, company.address)`
2. `SpacerBlock(24)`
3. `TitleBlock("CERTIFICATE OF EMPLOYMENT")`
4. `SpacerBlock(24)`
5. `ParagraphBlock("TO WHOM IT MAY CONCERN:")`
6. `SpacerBlock(12)`
7. `ParagraphBlock(coeBodyText)` — interpolates `{employee.fullName}`, `{position}`, `{dateStart}`, `{dateEnd}`, `{company.name}`.
8. `ParagraphBlock("This certification is issued upon the request of {employee.fullName} for whatever legal purpose it may serve.")`
9. `SpacerBlock(48)`
10. `SignatureBlock(company.hrManagerName, "HR Manager — " + company.name, today)`

### Notice to Explain (NTE)

**Inputs:**

- `employee` — required.
- `company` — required, autofilled.
- `dateIssued` — required, default today, freely editable.
- `subjectSubtopic` — optional. Final subject = `"Notice to Explain"` + (`subjectSubtopic.isNotEmpty` ? ` — ${subjectSubtopic}` : `""`).
- `charges` — required `List<Charge>`, min 1. Each `Charge { title: String, body: Delta }` (Quill rich text).
- `applicableViolations` — required `List<String>`, min 1, bullet items.
- `responseDeadline` — required date, default = `dateIssued + 5 calendar days`.

**Gates:** none.

**Validation:** all required present; each `Charge.title` non-empty; each `Charge.body` non-empty Delta; each violation non-empty; `responseDeadline > dateIssued`.

**Autofill:** company from employee. Employee metafields (full name, position, department, employee ID) flow into the rendered header, not into editable form fields.

**Block tree** (uses memo composites):

1. `MemoHeaderBlock(titleText: "NOTICE TO EXPLAIN" + (subtopic != null ? " — " + subtopic : ""), company, date: dateIssued, to: {name: employee.fullName, subtitle: employee.position + (department != null ? " · " + department : "")}, from: {name: company.hrManagerName, subtitle: "HR Manager"}, subject: finalSubject, salutation: "Mr./Ms. " + employee.lastName)`
2. `ParagraphBlock(nteIntroText)`
3. For each charge:
   - `SectionHeadingBlock(number: i+1, title: charge.title)`
   - `RichTextBlock(charge.body)`
   - `SpacerBlock(8)`
4. `ParagraphBlock("The above acts may constitute violations of the following Company policies:")`
5. `BulletListBlock(applicableViolations)`
6. `SpacerBlock(8)`
7. `ParagraphBlock(nteResponseInstructions)` — interpolates `{responseDeadline}`.
8. `SpacerBlock(24)`
9. `SignatureBlock(company.hrManagerName, "HR Manager — " + company.name, dateIssued)`
10. `SpacerBlock(24)`
11. `MemoAcknowledgmentBlock()`

### Fixed legal text

`quitclaimBodyText`, `coeBodyText`, `nteIntroText`, `nteResponseInstructions` live as `const String` in each template file with `{placeholder}` interpolation via a shared `interpolate(template, vars)` helper. The canonical wording will be lifted from existing Luxium HR docs in `[06] LUXIUM/[02] HR/[02] Employee Records/JAM/` at implementation time and confirmed with the user before commit.

## Error handling and edge cases

### Autofill failure modes

| Failure | Behavior |
|---|---|
| Employee has no `hiring_entity_id` | `company` field starts blank + manual; no Autofilled chip; HR picks one. |
| Selected `hiring_entity` has null `legal_signatory_name` / `legal_signatory_role` / `hr_manager_name` | Corresponding template input falls back to manual with banner: "Set a default in Settings → Hiring Entities to skip this next time." |
| No HIRE event in `employment_events` | `dateStart` blank + manual; warning banner: "No hire date on record — verify before issuing." |
| No SEPARATION event AND `status != SEPARATED` | COE: hard-block (gate). Quitclaim: `dateTerminated` blank + manual, warning banner. |
| 13th-month accrual not yet computed for current period | Final-pay breakdown row shows `—` with note "Accrual not computed for {period}". Total still editable. |
| Outstanding cash advance exists but no payment plan | Subtract full outstanding balance; show source caption "Outstanding CA balance". |
| Multiple SEPARATION events (rehire case) | Use the most recent. Surface "Rehired employee — using latest separation" caption. |
| `hiring_entities` row soft-deleted | Filter out from picker; if employee's current `hiring_entity_id` points to a deleted row, fall back to manual. |

### Validation surfaces

- **Per-field:** red border + below-field error text, matching existing form patterns.
- **Form-level:** badge on Generate button `(N issues)` with hover popover listing all errors.
- **Gate failures:** shown at template-picker step, not after entry — user never lands on a screen they cannot generate from.
- **Preview placeholder:** `PdfPreview` shows "Complete required fields" placeholder while `validate(inputs)` is non-empty.

### PDF rendering failure modes

| Failure | Behavior |
|---|---|
| Quill Delta contains unsupported attribute (image embed, color, etc.) | Strip the attribute, log debug warning, render the text. v1 Quill toolbar exposes only supported subset (bold/italic/underline/bullet/numbered/nested) so this is a guardrail, not a UX path. |
| Satoshi or Geist Mono font asset missing | Fall back to `pw.Font.helvetica()` and log. PDF still renders. |
| Block tree exceeds page bounds | `pw.MultiPage` paginates automatically. `PageBreakBlock` forces a break. |
| `printing.layoutPdf()` throws (driver issue, OS dialog cancelled) | Snackbar: "Couldn't open print dialog — try again or save the file." Form remains filled, no state change. |

### Concurrent state and permissions

- Two HR users generating for the same employee: no conflict (no DB writes). Whoever opens later sees fresher autofill.
- Employee data changes mid-edit: open form keeps its snapshot; re-open to refresh.
- Entry points are visible only when `userProfile.canManageEmployees == true`.
- `/documents/generate/<unknown-id>` → "Template not found" page with link back to `/documents`.

## Page numbers

`PdfBuilder` always uses `pw.MultiPage` (never `pw.Page`), so even single-page docs render "Page 1 of 1". Footer position bottom-center, format `"Page X of Y"`, 9pt grey, 12mm bottom margin. Configurable via `PdfTheme`. v1 always-on for all three templates. Because the right-pane preview displays the actual PDF bytes, page numbers appear in both surfaces identically.

## Testing strategy

### Unit tests (`test/features/documents/`)

| Layer | What's tested | How |
|---|---|---|
| `interpolate(text, vars)` | Placeholder substitution, missing-key error, nested braces | Pure function, table-driven |
| `validate(inputs)` per template | Each required-field error, cross-field rules | Table-driven over `(I, expected errors)` |
| `gates(ctx)` per template | COE blocks when not separated; allows when SEPARATION event exists; allows when `status == SEPARATED` even without event | Mock `AutofillContext` per combination |
| `autofill(ctx)` per template | Pulls correct fields; missing data → blank manual; multiple SEPARATION events → latest wins | Mock providers, assert returned `I` |
| `template.build(I) → List<Block>` | Block tree shape (count, types, order) for fully-filled inputs | Structural snapshot (`block.runtimeType` + key fields) |

### PDF golden tests (`test/features/documents/goldens/`)

| Test | Asserts |
|---|---|
| Each block's `toPdf()` rendered into a 1-page PDF | PDF bytes rasterized to PNG, compared to golden. |
| Each template (Quitclaim, COE, NTE) end-to-end with seeded inputs | Full multi-page PDF rasterized to golden PNGs per page. |
| Long NTE forcing pagination (6+ charges) | Footer reads "Page 1 of N", "Page 2 of N", etc. — assertion on rendered bytes. |

PDF goldens use `printing`'s raster utility (or equivalent). No block-preview goldens (no preview widget tree exists). No pixel-level font-fidelity tests — only structural goldens.

### Integration tests (`integration_test/documents/`)

- **Flow A — global Documents screen:** pick template → pick employee → form auto-fills → preview renders → Generate opens print dialog (stubbed `printing.layoutPdf` captures bytes).
- **Flow B — employee profile:** open employee → Documents tab → Generate → template-picker dialog → form opens with employee locked → Flow A continuation.
- **Flow C — gate behavior:** active employee shows COE grayed; separated employee shows COE enabled.
- **Flow D — locked-with-unlock:** autofilled field is read-only; Override → editable; warning banner; clearing the field still allows submission iff manually filled.

### Out of scope

- The `pdf` package's own rendering (third-party).
- `flutter_quill` editor internals (third-party).
- Visual fidelity at the pixel level — only structural goldens.

### Test fixtures

- `test/fixtures/employees.dart` — three seeded employees: active, separated-with-events, separated-without-events.
- `test/fixtures/payroll_snapshots.dart` — minimal snapshot for quitclaim final-pay calc.

### Coverage target

Pure layers (`interpolate`, `validate`, `gates`, `autofill`, `build`) reach 100%. Form widgets and PDF builders are covered by goldens + integration; no line-coverage target.

## Schema additions

`hiring_entities` lacks fields the templates need (signatory name and role for Quitclaim/COE signature blocks; HR manager name for NTE memo header). Adding these as nullable columns via a new migration `YYYYMMDDNNNN_hiring_entities_signatory_fields.sql`:

```sql
alter table hiring_entities
  add column legal_signatory_name varchar(255),
  add column legal_signatory_role varchar(255),
  add column hr_manager_name      varchar(255);
```

These are nullable so the migration is non-breaking. A small admin form in `lib/features/settings/hiring_entities/` lets ADMIN users fill them per brand (one-time setup). Autofill reads these into `AutofillContext.company` as `company.signatoryName`, `company.signatoryRole`, `company.hrManagerName`. When null, the corresponding template input falls back to manual entry with a warning banner ("Set a default in Settings → Hiring Entities to skip this field next time").

`company.address` is computed at autofill time by concatenating `address_line1`, `address_line2` (if present), `city`, `province`, `zip_code` into a single multi-line string. No schema change needed.

## Dependencies

New `pubspec.yaml` entries:

- `flutter_quill` — rich-text editor for NTE charge bodies. Pin to a stable major.
- (No new PDF dependency — `pdf: ^3.12.0` and `printing: ^5.14.3` already present.)

Custom code, no new dependency:

- `delta_to_pdf.dart` — Quill Delta → `pw.RichText` walker. ~150 LOC. No off-the-shelf converter targets the `pdf` package directly; existing converters target HTML or Quill's own renderer.

Font assets:

- Satoshi (Variable) — display + body. Already in `assets/fonts/` (verify; add if missing).
- Geist Mono — numbers, dates, currencies. Already in `assets/fonts/` (verify; add if missing).
- Helvetica fallback via `pw.Font.helvetica()` if either is missing at runtime.

## Implementation phases

This spec is one feature with a single implementation plan; the writing-plans skill will sequence it.

Suggested phasing for the plan author:

1. **Schema migration** — `hiring_entities` signatory + HR manager columns + admin form in Settings to fill them.
2. **Block library + `PdfTheme` + `PdfBuilder`** — primitives only, no composites yet. Goldens per primitive.
3. **`DocumentTemplate` interface, registry, picker UI, route wiring** — empty templates, picker shows them with "coming soon" generate.
4. **Quitclaim end-to-end** — first template with full form + autofill + preview + generate. Validates the architecture on the simplest doc.
5. **COE end-to-end** — adds the gate pattern.
6. **NTE end-to-end** — adds memo composites + Quill rich text + Delta-to-PDF.
7. **Polish + permissions wiring + integration tests + final goldens.**

## Open questions

None at design time. Canonical legal copy for `quitclaimBodyText`, `coeBodyText`, `nteIntroText`, `nteResponseInstructions` will be lifted from existing JAM employee record PDFs at implementation time and confirmed with the user before commit.
