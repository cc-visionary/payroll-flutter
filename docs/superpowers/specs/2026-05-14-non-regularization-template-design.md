# Notice of Non-Regularization Template — Design

**Date:** 2026-05-14
**Status:** Draft, awaiting review
**Owner:** Donald
**Extends:** [`2026-05-05-document-templates-design.md`](2026-05-05-document-templates-design.md) — adds the 4th template to the v1 doc-templates system; reuses the existing block library, `DocumentTemplate` interface, registry, picker, generate-screen, and PDF pipeline.

## Goal

Add **Notice of Non-Regularization** (Non-Reg) as the 4th document template, generated through the same ephemeral, code-defined pipeline as Quitclaim / COE / NTE. HR fills a form, sees a live byte-identical PDF preview, and prints/saves via the OS dialog. No DB writes, no storage uploads — same non-goals as the v1 spec.

The Non-Reg notice is issued when a probationary employee fails to meet the agreed-upon Standards for Regularization (Annex B of the Employment Contract). It documents specific failure areas (Performance + Behavior, each with Standard / Finding / sub-findings) and ends with a separation decision and an acknowledgment-of-receipt page.

Canonical legal copy is lifted verbatim from `[06] LUXIUM/[02] HR/[02] Employee Records/JAM/NOTICE OF NON-REGULARIZATION_VIDAL - Google Docs.pdf` and committed as `const String` literals in `non_reg_template.dart`. Final copy will be surfaced in the implementation PR for confirmation before merge.

## Non-goals

Same as the v1 doc-templates spec:

- **Saving generated PDFs** to storage or `employee_documents`.
- **Audit trail** of who generated what.
- **HR-authored templates** — still code-defined Dart classes.
- **E-signature / Lark approval routing.**
- **Bulk issuance.**

Additionally:

- **Other deferred templates** (Preventive Suspension Memo, Acknowledgment & Repayment Agreement, Employment Contract) are **not** in scope. Each gets its own spec when its source legal copy is available. The block-library work in this spec is designed to be reusable by them, but no implementation is committed.

## Architecture

A single new `DocumentTemplate` subclass following the v1 pattern. **No changes** to `DocumentTemplate`, `PdfBuilder`, `PdfPreviewScaffold`, `PdfTheme`, the registry mechanism, the picker, or routing — only an additional entry in `kTemplates`.

### New blocks

**`LabelledBulletListBlock`** — bullet list where each item has a **bold lead label** followed by body text. Supports **one level of nesting** (sub-bullets rendered with `○` glyph instead of `•`).

```dart
class LabelledBulletItem {
  final String leadBold;                    // "Standard", "Finding", "Lack of Core Competency"
  final String body;                        // plain text body
  final List<LabelledBulletItem> children;  // 0-N sub-bullets (one level only)
  const LabelledBulletItem({
    required this.leadBold,
    required this.body,
    this.children = const [],
  });
}

class LabelledBulletListBlock extends Block {
  final List<LabelledBulletItem> items;
  const LabelledBulletListBlock({required this.items});

  @override
  pw.Widget toPdf(PdfTheme theme) { ... }   // renders `• **LeadBold:** body` with nested `○`
}
```

**Why a new block instead of `BulletListBlock` + inline formatting:** `BulletListBlock` takes `List<String>` and has no bold-lead pattern. `NestedNumberedListBlock` uses numbered prefixes, not bullets. The lead-label-plus-body pattern is recurring (also used in the future Suspension Memo and Acknowledgment & Repayment templates per the v1 spec), so it earns a typed block.

**Nesting limit:** one level only. The source PDF has at most 2 levels (top-level bullet, sub-bullet). If a future template needs 3+, that's a future spec — the type signature accepts arbitrary depth but the rendering will only walk one level. Validation rejects grandchildren.

### Extended blocks (backward-compatible)

**`LetterMetaBlock`** — three new optional parameters; `subject` becomes nullable:

```dart
class LetterMetaBlock extends Block {
  final DateTime date;
  final LetterParty to;
  final String? position;        // NEW: optional, renders between "To" and "From" if set
  final LetterParty from;
  final String? subject;         // CHANGED: was `required String subject` — now nullable
  final bool showDividers;       // NEW: default true; Non-Reg sets false
  const LetterMetaBlock({
    required this.date,
    required this.to,
    this.position,
    required this.from,
    this.subject,
    this.showDividers = true,
  });
  // Renders the Subject row only when subject != null && subject.isNotEmpty.
}
```

Existing call sites (`MemoHeaderBlock` from NTE) pass `subject` → behavior unchanged. Non-Reg passes `subject: null` and renders the "SUBJECT: NOTICE OF NON-REGULARIZATION" callout as a separate `HeadingBlock` below the meta block, matching the source PDF (which shows subject only as a heading, not as a meta-row).

**`SignatureBlock`** — change `date` from required non-nullable to nullable:

```dart
class SignatureBlock extends Block {
  final String? name;
  final String? role;
  final DateTime? date;           // CHANGED: was `required DateTime date`
  const SignatureBlock({this.name, this.role, this.date});

  @override
  pw.Widget toPdf(PdfTheme theme) {
    // When date != null:  "Date: November 14, 2026"
    // When date == null:  "Date: ___________"   (hand-fill line)
  }
}
```

Existing call sites pass non-null dates → no behavior change. The hand-fill rendering is used by the Non-Reg acknowledgment-page signatures, where the employee and witness sign on paper at receipt time.

### New input widget

**`findings_editor.dart`** — repeater of finding-section cards. Same UX pattern as `charges_editor.dart` (NTE).

Each card contains:
- Title text field
- Standard textarea (3 lines, expandable)
- Finding textarea (3 lines, expandable)
- Sub-findings repeater:
  - Each sub-finding row: title text field + body textarea (2 lines, expandable)
  - Add/remove/reorder controls

Outer card supports add/remove/reorder of finding sections. Min 1 finding section enforced at validation time.

### File layout

```
lib/features/documents/
├── blocks/
│   ├── labelled_bullet_list_block.dart    # NEW
│   ├── letter_meta_block.dart             # EXTEND: position, showDividers
│   └── signature_block.dart               # EXTEND: nullable date
├── inputs/
│   └── findings_editor.dart               # NEW
└── templates/
    ├── non_reg_inputs.dart                # NEW
    ├── non_reg_template.dart              # NEW
    ├── non_reg_validate.dart              # NEW
    └── template_registry.dart             # ADD NonRegTemplate() to kTemplates
```

No schema changes. No new dependencies. No new routes — `/documents/generate/:templateId` and the picker pick this up via the registry.

## Typed inputs

```dart
class NonRegInputs extends TemplateInputs {
  final Employee? employee;                // required
  final HiringEntity? company;             // required, autofilled
  final DateTime? dateIssued;              // default today
  final DateTime? probationaryStart;       // autofilled from HIRE event
  final DateTime? probationaryEnd;         // autofilled = start + 6 months
  final DateTime? effectiveEndDate;        // default = probationaryEnd; freely editable
  final String salutationName;             // default <employee.lastName>; HR prefixes "Ms./Mr." manually
  final String? noteOnScope;               // optional "Note on Scope of Evaluation"
  final List<FindingSection> findings;     // required, min 1
  final String? witnessName;               // optional; pre-fills witness signature line
}

class FindingSection {
  final String title;                      // "Failure to Meet Performance Standards (Quality of Work & Initiative)"
  final String standard;                   // body of "Standard:" bullet
  final String finding;                    // body of "Finding:" bullet
  final List<SubFinding> subFindings;      // 0-N nested sub-bullets
}

class SubFinding {
  final String title;                      // bold lead label
  final String body;                       // body text
}
```

**Plain text everywhere.** No Quill for Non-Reg findings — the source PDF has no inline italics / bold / lists inside body text; emphasis comes only from the structural lead-label pattern that the block renders automatically.

## Autofill (one-shot at screen open)

| Field | Source | Lock behavior |
|---|---|---|
| `company` | `employees.hiring_entity_id` → `hiring_entities` row | locked + Override |
| `probationaryStart` | latest `employment_events.HIRE` for employee | locked + Override |
| `probationaryEnd` | `probationaryStart + 6 months` (PH Labor Code default) | locked + Override |
| `effectiveEndDate` | = `probationaryEnd` | freely editable |
| `dateIssued` | today | freely editable |
| `salutationName` | `employee.lastName` (no honorific — HR types "Ms." / "Mr." / "Mx." in the field). Form shows hint text "e.g., Ms. Vidal". | freely editable |
| `witnessName` | blank | freely editable |
| HR Manager name (used in signature) | `hiring_entities.hr_manager_name` (from v1 migration) | falls back to manual input with banner if null |

Autofill is **one-shot**, not reactive (same pattern as Quitclaim/COE/NTE).

## Gates

**None hard.** Soft warning banner if `employee.status` is not the probationary status value (whichever enum value applies — implementation reads the current schema): *"This employee isn't flagged as probationary — verify before issuing."* Banner is informational only; generation is not blocked.

Rationale: probationary status may not be reliably maintained in `employees.status` across all hiring entities yet. Hard-blocking would create friction without preventing real errors. A soft banner is sufficient; HR can still issue if they know better than the data.

## Block tree

```
1.  LetterMetaBlock(
      date: dateIssued,
      to: LetterParty(name: employee.fullName),
      position: employee.position,
      from: LetterParty(name: company.hrManagerName),
      subject: null,                           // rendered separately as a heading (step 3)
      showDividers: false,
    )
2.  SpacerBlock(16)
3.  HeadingBlock("SUBJECT: NOTICE OF NON-REGULARIZATION")
4.  SpacerBlock(12)
5.  ParagraphBlock("Dear {salutationName},")
6.  SpacerBlock(8)
7.  EmphasisParagraphBlock(nonRegIntroText1)         // canonical intro with bold dates
8.  EmphasisParagraphBlock(nonRegIntroText2)         // Section 4 / Annex B reference
9.  if (noteOnScope != null && noteOnScope.isNotEmpty)
       EmphasisParagraphBlock("**Note on Scope of Evaluation:** {noteOnScope}")
10. ParagraphBlock("Specifically, you failed to meet the agreed-upon standards in the following areas:")
11. for i, finding in findings:
       SpacerBlock(12)
       SectionHeadingBlock(number: i+1, title: finding.title)
       LabelledBulletListBlock(items: [
         LabelledBulletItem(leadBold: "Standard", body: finding.standard),
         LabelledBulletItem(
           leadBold: "Finding",
           body: finding.finding,
           children: finding.subFindings.map((s) =>
             LabelledBulletItem(leadBold: s.title, body: s.body)
           ).toList(),
         ),
       ])
12. SpacerBlock(16)
13. HeadingBlock("DECISION")
14. EmphasisParagraphBlock(nonRegDecisionText)       // with bold effectiveEndDate
15. ParagraphBlock(nonRegFinalPayText)               // Section 14 (Final Pay) reference
16. ParagraphBlock(nonRegClosingText)                // thank-you closing
17. SpacerBlock(24)
18. ParagraphBlock("Sincerely,")
19. SpacerBlock(40)
20. SignatureBlock(
      name: company.hrManagerName,
      role: "HR Manager\n${company.name}",
      date: dateIssued,
    )
21. PageBreakBlock()
22. HeadingBlock("ACKNOWLEDGMENT OF RECEIPT")
23. SpacerBlock(8)
24. ParagraphBlock(nonRegAcknowledgmentText)
25. SpacerBlock(40)
26. SignatureBlock(name: employee.fullName, role: "", date: null)   // hand-fill date
27. SpacerBlock(24)
28. ParagraphBlock("Witnessed by:")
29. SpacerBlock(40)
30. SignatureBlock(
      name: witnessName ?? "",
      role: "",
      date: null,
    )                                                                  // hand-fill date; blank name line if not pre-filled
```

### Canonical legal copy

Lifted verbatim from `JAM/NOTICE OF NON-REGULARIZATION_VIDAL - Google Docs.pdf` (pages 1-3) and committed as `const String` in `non_reg_template.dart`:

- `nonRegIntroText1` — "This letter serves as formal notification regarding the status of your probationary employment, which commenced on **{probationaryStart}** and is scheduled to end on **{probationaryEnd}**."
- `nonRegIntroText2` — "As stipulated in **Section 4 (Probationary Evaluation)** of your Employment Contract, the Company has evaluated your performance against the **Standards for Regularization** (Annex B). After a comprehensive review, we regret to inform you that you have not met the reasonable standards required to qualify for regular employment."
- `nonRegDecisionText` — "In view of the foregoing, your probationary employment will not be regularized and will cease effective at the close of business hours on **{effectiveEndDate}**."
- `nonRegFinalPayText` — "Please arrange to return your Company ID, access keys, and any other company property currently in your possession. Your Final Pay, including your pro-rated 13th-month pay, will be processed in accordance with **Section 14 (Final Pay)** of your contract and released upon completion of the clearance process."
- `nonRegClosingText` — "We thank you for the time spent with the company and wish you the best in your future endeavors."
- `nonRegAcknowledgmentText` — "I acknowledge receipt of this notice. I understand that my signature attests only to the receipt of this letter and not necessarily my agreement with its contents."

Interpolation uses the existing shared `interpolate(template, vars)` helper. Date placeholders format as "MMMM d, yyyy" to match the source PDF.

Final copy will be surfaced in the implementation PR for explicit confirmation before merge.

## Validation

```dart
List<ValidationError> validate(NonRegInputs i) {
  // Required:
  //   employee, company, dateIssued, probationaryStart, probationaryEnd,
  //   effectiveEndDate, salutationName, findings (length >= 1)
  //
  // Per finding:
  //   title.isNotEmpty, standard.isNotEmpty, finding.isNotEmpty
  //
  // Per sub-finding:
  //   title.isNotEmpty, body.isNotEmpty
  //
  // Cross-field:
  //   probationaryEnd >= probationaryStart
  //   effectiveEndDate >= probationaryStart
  //   effectiveEndDate <= probationaryEnd + 7 days
  //     (Non-Reg must fall within or right at probation end; 7-day grace
  //      handles end-of-week-close-of-business cases without false rejections)
}
```

Validation surfaces match the v1 spec: per-field error text + form-level banner above `PdfPreviewScaffold`; Download/Print actions disabled while errors exist; preview shows "Complete required fields" placeholder.

## Error handling / edge cases

| Failure | Behavior |
|---|---|
| Employee has no `hiring_entity_id` | `company` field starts blank + manual; HR picks one. |
| Selected `hiring_entity` has null `hr_manager_name` | HR Manager input falls back to manual with banner. |
| No `HIRE` event for employee | `probationaryStart` blank + manual; banner: *"No hire date on record — verify before issuing."* `probationaryEnd` default falls back to manual since it depends on start. |
| `employee.status != PROBATIONARY` | Soft warning banner; generation not blocked. |
| `hiring_entities` row soft-deleted | Filtered from picker; if employee's `hiring_entity_id` points to a deleted row, fall back to manual company picker. |
| Multiple `HIRE` events (rehire after dismissal) | Use the most recent. Surface caption: *"Rehired employee — using latest hire date."* |
| `findings` empty at submission | Validation banner; Download/Print disabled. |
| Sub-findings empty (no nested rows) | Allowed — `Finding:` bullet renders without children. |
| Long findings forcing pagination | `pw.MultiPage` paginates automatically; footer reads "Page X of Y" via existing `buildStandardPageFooter`. `PageBreakBlock` after Sincerely guarantees acknowledgment lands on its own page. |

## Testing

### Block-level

| Test | Asserts |
|---|---|
| `labelled_bullet_list_block_test.dart` golden | Flat 3-item list renders with `•` glyph + bold lead labels + plain bodies. |
| `labelled_bullet_list_block_test.dart` nested golden | Top-level + 2 sub-items each renders with `○` glyph indented under finding. |
| `labelled_bullet_list_block_test.dart` nesting-limit | Grandchild (depth-3) items in input — only depth-1 rendered; depth-2 ignored. Documents the one-level limit. |
| `letter_meta_block_test.dart` extension | Renders `Position:` row when set; suppresses dividers when `showDividers: false`; existing 4-row variant unchanged (existing golden re-passes). |
| `signature_block_test.dart` extension | Renders `Date: ___________` line when `date == null`; existing formatted-date variant unchanged. |

### Template-level

| Test | Asserts |
|---|---|
| `non_reg_validate_test.dart` | Each required-field error; per-finding/sub-finding errors; date ordering rules. Table-driven over `(NonRegInputs, expected errors)`. |
| `non_reg_autofill_test.dart` | `probationaryEnd` defaults to `start + 6 months`; HR manager falls back to manual when `hr_manager_name` is null; multiple `HIRE` events → latest wins; `salutationName` defaults to `employee.lastName` with no honorific prefix. |
| `non_reg_build_test.dart` | Block tree shape with N findings × M sub-findings (structural snapshot — `runtimeType` + key fields). Optional `noteOnScope` inserted/omitted correctly. |

### End-to-end golden

| Test | Asserts |
|---|---|
| `test/features/documents/goldens/non_reg_full_test.dart` | Seeded `NonRegInputs` (2 findings × 2 sub-findings each, with optional scope note) → 3-page PDF rasterized to golden PNGs per page. Mirrors the source `JAM/NOTICE OF NON-REGULARIZATION_VIDAL` structurally. |
| `test/features/documents/goldens/non_reg_pagination_test.dart` | 5-finding × 3-sub-finding force pagination; footer reads "Page 1 of N" through "Page N of N" via assertion on rendered bytes. |

### Integration

No new integration test. Flow A (global Documents screen → pick template → pick employee → form → preview → Download/Print) and Flow B (employee profile → Documents tab → Generate dialog → form) from the v1 spec already cover this pathway generically. Adding `NonRegTemplate()` to `kTemplates` is sufficient to make Flow A/B exercise it; the existing test fixtures suffice as long as one fixture employee has a `HIRE` event.

### Coverage

Pure layers (`validate`, `autofill`, `build`) reach 100%. Form widget and PDF builder are covered by goldens + the existing Flow A/B integration suite; no line-coverage target.

## Dependencies

None. All required infrastructure is already present:

- `pdf`, `printing` — already in use.
- Inter via `PdfGoogleFonts` — already loaded in `PdfTheme.defaults()`.
- `interpolate(template, vars)` helper — already shared.
- `SectionHeadingBlock`, `EmphasisParagraphBlock`, `HeadingBlock`, `ParagraphBlock`, `PageBreakBlock`, `SpacerBlock` — already implemented.

## Implementation phases

Suggested phasing for the plan author (single PR, all phases together):

1. **Block-library work** — implement `LabelledBulletListBlock` with goldens; extend `LetterMetaBlock` and `SignatureBlock` with goldens for new variants and re-runs of existing goldens.
2. **Template scaffolding** — `non_reg_inputs.dart`, `non_reg_validate.dart`, skeleton `non_reg_template.dart` (`autofill` + `validate` + empty `build`).
3. **Form widget** — `findings_editor.dart` with add/remove/reorder for both section and sub-finding levels; `non_reg_form.dart` wiring autofilled-with-unlock inputs.
4. **Block tree assembly** — fill `build()` with the 30-step tree; commit canonical legal copy as `const String`.
5. **Template registration** — add `NonRegTemplate()` to `kTemplates`; verify picker / route / generate-screen work without code changes elsewhere.
6. **Tests** — block goldens, template tests, end-to-end golden, pagination golden.
7. **Source-copy review pass** — confirm canonical legal copy with user before merge.

## Open questions

None at design time. Final canonical legal copy comes from the source PDF and will be confirmed in the implementation PR before merge.
