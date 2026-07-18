# Role Card → PDF — Design Spec

> Employee-facing PDF export of a Responsibility Card (role scorecard).
> Date: 2026-07-18.

## Goal

Let HR/managers hand an employee a clean, printable definition of their role —
mission, responsibilities, KPIs, required skills, and behavioral expectations —
generated on demand from the current role scorecard. The same document is the
reference the performance review is scored against, so it is reachable from the
employee review screen too.

## Scope

**In:**
- A "Download / Print PDF" action on the role scorecard detail screen.
- A "View role reference (PDF)" link on the employee review detail screen.
- Both render the **current** role card (no version/snapshot logic).
- Company letterhead (logo) when the card has a hiring entity.

**Out (YAGNI):**
- No compensation/salary fields (employee-facing document).
- No bulk export.
- No as-scored snapshot reconstruction or version-drift handling.
- No saved document record — the PDF is ephemeral, rendered on the fly, exactly
  like the rest of the document system ("settings-only, re-render on view").

## Users

Internal HR + managers, generating a one-off role handout for an employee.
Desktop use. No new permissions: anyone who can already open a role scorecard or
an employee review can export the PDF (the underlying data is already visible to
them on those screens; RLS on `role_scorecards` still applies to the fetch).

## Architecture

Reuse the existing document PDF layer end to end. Three new pieces plus two
call-site edits and one provider.

### 1. Block mapping — `lib/features/responsibility_cards/role_card_pdf.dart`

A pure function, no I/O:

```dart
List<Block> roleCardBlocks(RoleScorecard card, {Uint8List? logoBytes})
```

Section order (each section is **omitted** when its source list/string is empty,
so a sparse card never renders a blank heading):

| Section | Source | Block(s) |
|---|---|---|
| Letterhead | `logoBytes` | `LetterheadBlock` / `CompanyHeaderBlock` (as documents use) |
| Title | `card.jobTitle` | `TitleBlock` |
| Meta line | effective date · active/inactive | `KeyValueBlock` (or a single caption paragraph) |
| Mission | `card.missionStatement` | `SectionHeadingBlock` + `ParagraphBlock` |
| Responsibilities | `card.responsibilities` (`ResponsibilityArea`: area + tasks) | `SectionHeadingBlock`, then per area a sub-heading + `BulletListBlock` of tasks |
| KPIs | `card.kpis` (`KpiItem`: name/measurement/target/frequency) | `SectionHeadingBlock` + `TableBlock` (4 columns) |
| Required skills | `card.requiredSkills` (`RequiredSkill`: name + description) | `SectionHeadingBlock` + `LabelledBulletListBlock` |
| Behavioral expectations | `card.behavioralExpectations` (name + description) | `SectionHeadingBlock` + `LabelledBulletListBlock` |

Exact block choices are validated against the block library during
implementation; the table above is the intent, and the point is that every
section maps to an existing block — no new block types.

### 2. Preview screen — `lib/features/responsibility_cards/role_card_pdf_screen.dart`

`RoleCardPdfScreen(String cardId)`, a `ConsumerWidget`:
- `ref.watch(roleScorecardByIdProvider(cardId))` → the card (loading / error /
  not-found states mirror `document_view_screen.dart`).
- Resolve the letterhead: if `card.hiringEntityId != null`, read
  `hiringEntityByIdProvider(card.hiringEntityId!)` then `loadCompanyLogoBytes`;
  otherwise render with no logo.
- Return `PdfPreviewScaffold(filename: '<slug of job title>-role-card.pdf',
  buildPdf: (format) async => buildDocumentPdf(blocks: roleCardBlocks(card,
  logoBytes: logo), theme: await PdfTheme.defaults()))`.

`PdfPreviewScaffold` (in `lib/core/pdf/pdf_preview_scaffold.dart`) already
provides print, download, and share.

### 3. Provider — `lib/data/repositories/role_scorecard_repository.dart`

Add next to `roleScorecardListProvider`:

```dart
final roleScorecardByIdProvider =
    FutureProvider.family<RoleScorecard?, String>((ref, id) =>
        ref.watch(roleScorecardRepositoryProvider).byId(id));
```

`RoleScorecardRepository.byId(String)` already exists.

### 4. Route — `lib/app/router.dart`

One route inside the existing `ShellRoute`:

```dart
GoRoute(
  path: '/responsibility-cards/:id/pdf',
  builder: (c, s) => RoleCardPdfScreen(cardId: s.pathParameters['id']!),
)
```

Placed so it does not shadow existing `/responsibility-cards/...` routes.

### 5. Entry points (call-site edits)

- **Role scorecard detail** (`role_scorecard_detail_screen.dart`): an AppBar
  action (icon `Icons.picture_as_pdf_outlined` or `Icons.print_outlined`,
  Luxium purple CTA) → `context.push('/responsibility-cards/$cardId/pdf')`.
- **Employee review detail** (`employee_review_detail_screen.dart`): a
  `TextButton.icon` "View role reference" →
  `context.push('/responsibility-cards/${review.responsibilityCardId}/pdf')`.

## Data flow

```
detail screen action ─┐
                       ├─→ /responsibility-cards/:id/pdf ─→ RoleCardPdfScreen
review screen link  ──┘        │
                               ├─ roleScorecardByIdProvider(id) → RoleScorecard
                               ├─ hiringEntityByIdProvider → loadCompanyLogoBytes
                               ├─ roleCardBlocks(card, logoBytes) → List<Block>
                               └─ PdfPreviewScaffold → buildDocumentPdf → Uint8List
```

Nothing is written to the database. The PDF is regenerated from the live card on
every open.

## Error / edge handling

- **Card not found / deleted** (e.g. a review points at a card since removed):
  the by-id fetch returns null → show a "Role card not found" message in place
  of the preview, not a crash.
- **Empty sections:** omitted (see the mapping table). A brand-new card with
  only a job title renders a title + meta line and nothing else.
- **No hiring entity / no logo:** render without letterhead logo.
- **RLS denial:** `byId` returns null under RLS the same as not-found; same
  friendly message.

## Testing

Unit test on `roleCardBlocks` (mirrors the existing document autofill tests):
- A fully-populated card produces the sections in the expected order.
- A card with empty KPIs / skills / behaviors omits exactly those sections and
  does not throw.
- A card with a single responsibility area renders its tasks as a bullet list.

`flutter analyze` clean; existing suite stays green.

## Design system

Inherits `PdfTheme` (Satoshi, brand typography), letterhead, and spacing from
the block layer — no new colors, fonts, or packages. The in-app action button
uses the single Luxium purple CTA per `PRODUCT.md`.

## Files touched

New:
- `lib/features/responsibility_cards/role_card_pdf.dart`
- `lib/features/responsibility_cards/role_card_pdf_screen.dart`
- `test/features/responsibility_cards/role_card_pdf_test.dart`

Edited:
- `lib/data/repositories/role_scorecard_repository.dart` (+1 provider)
- `lib/app/router.dart` (+1 route)
- `lib/features/responsibility_cards/role_scorecard_detail_screen.dart` (+action)
- `lib/features/performance/employee_review_detail_screen.dart` (+link)
