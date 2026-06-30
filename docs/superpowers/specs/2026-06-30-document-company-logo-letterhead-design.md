# Document company-logo letterhead — design

**Date:** 2026-06-30
**Status:** Approved (pending spec review)
**Area:** `lib/features/documents`, `lib/features/settings/hiring_entities`, `lib/data` (hiring entity), Supabase migration

## Problem

When generating a document, changing the **Company** dropdown does not update the
rendered document. In the Salary Adjustment memo the company **name and logo never
appear at all**, and most other templates carry no logo. Three distinct gaps:

1. **Salary Adjustment renders neither company name nor logo.**
   `SalaryAdjustmentTemplate.build()` emits only `LetterMetaBlock` → body → signatures.
   No `CompanyHeaderBlock`/`MemoHeaderBlock` (name) and no `LogoBlock` (logo); its
   inputs have no `logoBytes` field and its `autofill()` never loads a logo.

2. **Changing Company does not refresh logo/name.**
   Logo bytes are loaded only inside each template's `autofill()`, which runs on initial
   load and on **employee** change (`_onPickerEmployeeChanged`). The Company picker goes
   through each form's local handler — e.g. NTE's does `copyWith(companyId: id)` only — so
   the rendered company name and logo stay stale when the company changes. There is no
   central "company changed → reload company fields + logo" path.

3. **Most documents have no logo.**
   Only NTE, COE, Non-Reg, and Employment Contract render a `LogoBlock`. The other 8
   (Salary Adjustment, NOD, Final Pay, NDA, Quitclaim, Regularization, Resignation
   Acceptance, Liability Waiver) render none.

Constraint discovered: only two logo assets exist (`assets/GameCove Logo.png`,
`assets/Luxium Logo.png`); `loadBrandLogoBytes()` maps GameCove entities → GameCove and
everything else → Luxium. The `hiring_entities` record has no logo field.

## Decisions (confirmed with stakeholder)

- **Coverage:** all 12 document templates get a logo + company-name/address letterhead.
- **Logo source:** a logo stored on the company record, as **base64 in a DB column**
  (not a Storage bucket).
- **Layout:** logo above, company name (bold) + address below, then the existing
  divider/meta block (left-aligned). Matches the shipped NTE/COE convention.
- **Fallback:** when an entity has no uploaded logo, fall back to today's bundled-asset
  heuristic (GameCove logo for GameCove entities, Luxium otherwise) so nothing regresses.
- **Out of scope:** payslips and government reports. This covers the 12 document
  templates only.

## Architecture

### 1. Data — base64 logo on the company record

- **Migration** (`supabase/migrations/<ts>_hiring_entities_logo.sql`): add nullable
  `logo_base64 text` and `logo_mime text` to `hiring_entities`. No backfill.
- **Model** (`HiringEntity`): add nullable `logoBase64` and `logoMime`. These are
  populated **only** by a targeted single-row fetch — never by the list query.
- **Repository** (`hiring_entity_repository.dart`):
  - `list()` changes from `select()` (= `select('*')`) to an **explicit column list that
    excludes `logo_base64`/`logo_mime`**. This keeps the picker list — loaded constantly,
    and the source for `hiringEntityByIdProvider` — light.
  - Add `Future<({String base64, String mime})?> logoFor(String entityId)` selecting only
    the logo columns for one row.
  - `upsert()` gains `logoBase64` / `logoMime` params (passed through; `null` clears).
- **Provider** (`documents/providers.dart`): add
  `hiringEntityLogoProvider(entityId)` (FutureProvider.family) wrapping `logoFor`.

Rationale for the explicit-column `list()`: `hiringEntityByIdProvider` resolves an entity
by scanning `list()`, so without this change every picker render would pull base64 logos
for all entities.

### 2. Upload UI — Hiring Entity edit dialog

In `_EntityForm` (`hiring_entities_settings_screen.dart`) add a **Branding** section:
- Current-logo preview (decode base64 when present; placeholder otherwise).
- **Upload logo** button using the existing `file_picker` dependency, restricted to
  **PNG/JPG** (these render in the `pdf` package's `MemoryImage`).
- **Remove** button.
- Client-side size cap **~300 KB** with an inline error (base64 inflates ~33%, so the row
  stays well-bounded). Selected bytes → base64 held in form state → persisted via
  `upsert(logoBase64:…, logoMime:…)`.

### 3. Logo resolution helper

In `brand_logo.dart` add:
```
Future<Uint8List?> loadCompanyLogoBytes(HiringEntity? entity)
```
If `entity?.logoBase64` is non-empty → decode and return. Otherwise fall back to the
existing `loadBrandLogoBytes(companyName: entity?.name, code: entity?.code)`. This is the
single seam used by generate, bulk-generate, and the saved-document viewer.

### 4. Letterhead rendering — all 12 templates

- Reusable letterhead: logo (top-left, fixed height via existing `LogoBlock`) → company
  name (bold) → address, then the template's existing divider/meta/body.
- **Memo/letter templates** that already use `MemoHeaderBlock` fold the logo into it:
  `MemoHeaderBlock` gains an optional `logoBytes`, rendering the logo above the title/
  company header it already draws (replacing the ad-hoc `LogoBlock` + `MemoHeaderBlock`
  pairing in NTE).
- **Non-memo / contract templates** prepend a shared `LetterheadBlock(logoBytes,
  companyName, companyAddress)`.
- **Salary Adjustment** (today renders neither) gets the full letterhead: logo + company
  name/address above its `LetterMetaBlock`.
- **All 12** `*Inputs` get a nullable `logoBytes` field with `copyWith` support, and it is
  **excluded from `toJson`** (binary, re-resolved at view time — matches the existing
  `logoBytes` convention on NTE/COE).
- **All 12** `autofill()` load the logo via `loadCompanyLogoBytes(ctx.company)`.

### 5. Live refresh when Company changes (core bug)

- Add `_onPickerCompanyChanged(String companyId)` to `generate_screen`, parallel to
  `_onPickerEmployeeChanged`. It loads the entity (`hiringEntityByIdProvider`) and its
  logo (`loadCompanyLogoBytes`), then **patches** the active template's inputs via
  `copyWith`: `companyId`, `companyName`, `companyAddress`, `hrManagerName` (only when
  currently empty), and `logoBytes`. It does **not** re-run full `autofill` (which would
  clobber user-entered fields).
- Standardize forms: add an `onCompanyChanged` callback to each document form, and route
  every `CompanyPicker.onChanged` through it (optimistic local `companyId` set + parent
  callback), mirroring the existing employee-picker pattern.

### 6. Saved-document re-render

- `document_view_screen` currently resolves the logo via
  `loadBrandLogoBytes(companyName: options['companyName'])`. Change it to read `companyId`
  from `generation_options`, fetch the entity + logo, call `loadCompanyLogoBytes`, and
  pass the bytes to `blocksForSavedDocument`.
- `blocksForSavedDocument` applies `logoBytes` to **all 12** templates' inputs via
  `copyWith` (today only 4). The logo is never stored in the `generation_options`
  snapshot — re-resolved at view time, consistent with the settings-only model.

### 7. Bulk generate

`bulk_generate.dart` loads the logo per entity through `loadCompanyLogoBytes` so batched
documents carry the correct letterhead.

## Testing

- Each affected template's `build()` includes the letterhead (logo present) — explicit
  coverage for Salary Adjustment plus at least two others (one memo, one contract).
- `loadCompanyLogoBytes` prefers base64 and falls back to the bundled-asset heuristic.
- `hiring_entity_repository.list()` select shape excludes the logo columns; `logoFor`
  returns the logo for a single entity.
- The company-change patch sets `logoBytes` and company fields without clobbering
  user-entered values.
- Saved-document re-render passes a logo to all 12 templates
  (`kReRenderableSavedTemplateIds` stays in sync).
- Upload UI: oversized file is rejected; PNG/JPG accepted; remove clears the logo.

## Risks / notes

- Base64 in a column bloats `hiring_entities` rows; mitigated by the explicit-column
  `list()` and the 300 KB cap. Logos are only fetched for a single entity at generate/
  view time.
- Storage buckets in this project are provisioned in the Supabase dashboard, not via
  migration (the `employee-documents` bucket has no migration). The base64 approach avoids
  needing any bucket/RLS setup.
- WebP is intentionally excluded (inconsistent `pdf` rendering); UI restricts to PNG/JPG.
