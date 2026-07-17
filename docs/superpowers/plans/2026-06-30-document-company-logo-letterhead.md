# Document Company-Logo Letterhead Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Dispatch Flutter/Dart implementer subagents as **mobile-app-builder**.

**Goal:** Render a company logo + name/address letterhead at the top of all 12 document templates, sourced from a base64 logo on the hiring entity, refreshing live when the Company picker changes and re-resolving at view time.

**Architecture:** A nullable base64 logo column on `hiring_entities` (excluded from the list query to keep pickers light); a `loadCompanyLogoBytes(entity)` helper that decodes it or falls back to the bundled GameCove/Luxium asset; a reusable `LetterheadBlock` plus a logo-aware `MemoHeaderBlock`; per-template `logoBytes` inputs wired through `autofill`, `build`, the saved-document re-render, and bulk generate; and a central `onCompanyChanged` path in the generate screen that patches company fields + logo without clobbering user edits.

**Tech Stack:** Flutter (Material 3, Riverpod), `pdf` package (`pw.MemoryImage`), `file_picker`, Supabase Postgres.

## Global Constraints

- Design system per `PRODUCT.md` / `CLAUDE.md`: Satoshi/Geist Mono, Luxium purple `#635BFF`, 6px radius, 4px spacing grid. No new accent colors.
- Logo image types accepted: **PNG and JPG only** (render reliably in `pw.MemoryImage`). WebP excluded.
- Logo upload size cap: **300 KB** of source bytes (pre-base64), enforced client-side with an inline error.
- `logoBytes` is binary and MUST be excluded from every `*Inputs.toJson()` (it is re-resolved at view time). It is NOT a field in `fromJson`.
- Letterhead layout: **logo above** (left-aligned), **company name (bold) + address below**, then the template's existing title/meta/body.
- Fallback when an entity has no `logo_base64`: existing `loadBrandLogoBytes(companyName, code)` (GameCove → GameCove asset, else Luxium asset).
- Run tests with `flutter test <path>`. App run: `flutter run -d linux --dart-define-from-file=env/prod.json`.
- Branch: `feat/document-company-logo` (already created off `main`).

---

## File Structure

**Create:**
- `supabase/migrations/20260630000001_hiring_entities_logo.sql` — logo columns.
- `lib/features/documents/blocks/letterhead_block.dart` — reusable logo + company header block.
- `test/features/documents/blocks/letterhead_block_test.dart`
- `test/features/documents/brand_logo_test.dart` — `loadCompanyLogoBytes` behavior.

**Modify:**
- `lib/data/models/hiring_entity.dart` — add `logoBase64`, `logoMime`.
- `lib/data/repositories/hiring_entity_repository.dart` — explicit-column `list()`, `logoFor()`, `upsert` logo params.
- `lib/features/documents/providers.dart` — `hiringEntityLogoProvider`.
- `lib/features/documents/brand_logo.dart` — `loadCompanyLogoBytes`.
- `lib/features/documents/blocks/memo_header_block.dart` — optional `logoBytes`.
- 8 `*_inputs.dart` (nda, nod, final_pay, quitclaim, regularization, resignation_acceptance, salary_adjustment, liability_waiver) — add `logoBytes`.
- 12 `*_template.dart` — `autofill` loads logo; `build` renders letterhead.
- 12 `*_form.dart` — `onCompanyChanged` callback wired to `CompanyPicker`.
- `lib/features/documents/generate_screen.dart` — `_onPickerCompanyChanged`, pass callback to forms.
- `lib/features/documents/view/saved_document_renderer.dart` — apply `logoBytes` to all 12.
- `lib/features/documents/view/document_view_screen.dart` — resolve logo from entity by `companyId`.
- `lib/features/documents/bulk/bulk_generate.dart` — per-entity logo.
- `lib/features/settings/hiring_entities/hiring_entities_settings_screen.dart` — upload UI.

---

## Task 1: Migration — logo columns on `hiring_entities`

**Files:**
- Create: `supabase/migrations/20260630000001_hiring_entities_logo.sql`

**Interfaces:**
- Produces: columns `hiring_entities.logo_base64 text`, `hiring_entities.logo_mime text` (both nullable).

- [ ] **Step 1: Write the migration**

```sql
-- Company logo for document letterheads. Stored as base64 (PNG/JPG) directly
-- on the hiring entity. Nullable; absence falls back to a bundled brand asset.
-- Intentionally NOT selected by the entity list query (see hiring_entity_repository),
-- so the picker list stays light despite the column's potential size.
alter table hiring_entities
  add column if not exists logo_base64 text,
  add column if not exists logo_mime text;

comment on column hiring_entities.logo_base64 is
  'Base64-encoded PNG/JPG logo (no data: prefix). Capped ~300KB source at the UI.';
comment on column hiring_entities.logo_mime is
  'MIME type of logo_base64, e.g. image/png or image/jpeg.';
```

- [ ] **Step 2: Apply locally / verify SQL**

Run: `supabase db reset` is destructive — instead just confirm the file parses by reviewing it. (Deploy to remote happens via the project's normal migration flow; do not run against prod from here.)
Expected: file saved; no syntax errors on review.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260630000001_hiring_entities_logo.sql
git commit -m "feat(documents): add logo_base64/logo_mime to hiring_entities"
```

---

## Task 2: `HiringEntity` model — logo fields

**Files:**
- Modify: `lib/data/models/hiring_entity.dart`
- Test: `test/data/models/hiring_entity_logo_test.dart` (create)

**Interfaces:**
- Consumes: column names `logo_base64`, `logo_mime` (Task 1).
- Produces: `HiringEntity.logoBase64` (`String?`), `HiringEntity.logoMime` (`String?`); `fromRow` maps `r['logo_base64']`, `r['logo_mime']` (null when key absent).

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll/data/models/hiring_entity.dart';

void main() {
  test('fromRow reads logo fields when present', () {
    final e = HiringEntity.fromRow({
      'id': '1', 'company_id': 'c', 'code': 'GC', 'name': 'GameCove',
      'country': 'PH', 'is_active': true,
      'logo_base64': 'QUJD', 'logo_mime': 'image/png',
    });
    expect(e.logoBase64, 'QUJD');
    expect(e.logoMime, 'image/png');
  });

  test('fromRow leaves logo null when columns absent (list query)', () {
    final e = HiringEntity.fromRow({
      'id': '1', 'company_id': 'c', 'code': 'GC', 'name': 'GameCove',
      'country': 'PH', 'is_active': true,
    });
    expect(e.logoBase64, isNull);
    expect(e.logoMime, isNull);
  });
}
```

> Note: confirm the package import prefix (`package:payroll/...`) matches `name:` in `pubspec.yaml`; adjust if different.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/models/hiring_entity_logo_test.dart`
Expected: FAIL — `logoBase64`/`logoMime` not defined.

- [ ] **Step 3: Add the fields + mapping**

In `lib/data/models/hiring_entity.dart`, add two fields near `hrManagerName`:
```dart
  final String? logoBase64;
  final String? logoMime;
```
Add to the constructor (optional, nullable):
```dart
    this.logoBase64,
    this.logoMime,
```
In `fromRow`, add to the returned constructor call:
```dart
        logoBase64: r['logo_base64'] as String?,
        logoMime: r['logo_mime'] as String?,
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/models/hiring_entity_logo_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/data/models/hiring_entity.dart test/data/models/hiring_entity_logo_test.dart
git commit -m "feat(documents): HiringEntity logoBase64/logoMime fields"
```

---

## Task 3: Repository — light `list()`, `logoFor()`, `upsert` logo params, provider

**Files:**
- Modify: `lib/data/repositories/hiring_entity_repository.dart`
- Modify: `lib/features/documents/providers.dart`
- Test: `test/data/repositories/hiring_entity_logo_repo_test.dart` (create)

**Interfaces:**
- Consumes: `HiringEntity` logo fields (Task 2).
- Produces:
  - `HiringEntityRepository.list()` selects an explicit column list that EXCLUDES `logo_base64`/`logo_mime`.
  - `Future<({String base64, String mime})?> logoFor(String entityId)`.
  - `upsert(... String? logoBase64, String? logoMime ...)`.
  - `hiringEntityLogoProvider` = `FutureProvider.family<Uint8List?, String>` returning decoded logo bytes (or null).

- [ ] **Step 1: Write the failing test (logoFor decode contract)**

The repo talks to Supabase, so unit-test only the pure decode helper exposed for testing. Add a top-level function and test it:

```dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll/data/repositories/hiring_entity_repository.dart';

void main() {
  test('decodeLogoBytes decodes base64; null/empty -> null', () {
    final b = decodeLogoBytes(base64.encode([1, 2, 3]));
    expect(b, isNotNull);
    expect(b!.toList(), [1, 2, 3]);
    expect(decodeLogoBytes(null), isNull);
    expect(decodeLogoBytes(''), isNull);
    expect(decodeLogoBytes('not valid base64 @@@'), isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/repositories/hiring_entity_logo_repo_test.dart`
Expected: FAIL — `decodeLogoBytes` not defined.

- [ ] **Step 3: Implement repo changes**

In `lib/data/repositories/hiring_entity_repository.dart`:

Add imports at top:
```dart
import 'dart:convert';
import 'dart:typed_data';
```

Add a top-level pure helper (above the class or below it):
```dart
/// Decode a base64 logo string to bytes; returns null on null/empty/invalid input.
Uint8List? decodeLogoBytes(String? base64Str) {
  if (base64Str == null || base64Str.isEmpty) return null;
  try {
    return base64.decode(base64Str);
  } catch (_) {
    return null;
  }
}
```

Replace the `list()` select line. Change:
```dart
        .from('hiring_entities')
        .select()
```
to (explicit columns, no logo):
```dart
        .from('hiring_entities')
        .select(
          'id, company_id, code, name, trade_name, tin, rdo_code, '
          'sss_employer_id, philhealth_employer_id, pagibig_employer_id, '
          'address_line1, address_line2, city, province, zip_code, country, '
          'phone_number, email, legal_signatory_name, legal_signatory_role, '
          'hr_manager_name, is_active',
        )
```

Add a method to the class:
```dart
  /// Fetch ONLY the logo columns for one entity. Kept separate from [list] so the
  /// (potentially large) base64 never rides along on the constantly-loaded picker list.
  Future<({String base64, String mime})?> logoFor(String entityId) async {
    final row = await _client
        .from('hiring_entities')
        .select('logo_base64, logo_mime')
        .eq('id', entityId)
        .maybeSingle();
    final b64 = row?['logo_base64'] as String?;
    if (b64 == null || b64.isEmpty) return null;
    return (base64: b64, mime: (row?['logo_mime'] as String?) ?? 'image/png');
  }
```

In `upsert`, add params (after `hrManagerName`):
```dart
    String? logoBase64,
    String? logoMime,
```
and add to the `payload` map:
```dart
      'logo_base64': logoBase64,
      'logo_mime': logoMime,
```

> Caveat: passing `logoBase64: null` writes NULL (clears the logo). Callers that must NOT touch the logo should call `setActive`/a narrower update instead — but the entity form always supplies the current value, so this is correct here.

- [ ] **Step 4: Add the provider**

In `lib/features/documents/providers.dart` add imports:
```dart
import 'dart:typed_data';
```
and a provider:
```dart
/// Decoded logo bytes for one hiring entity, or null when none is set.
final hiringEntityLogoProvider =
    FutureProvider.family<Uint8List?, String>((ref, entityId) async {
  final logo = await ref
      .read(hiringEntityRepositoryProvider)
      .logoFor(entityId);
  return decodeLogoBytes(logo?.base64);
});
```
Add import for `decodeLogoBytes`:
```dart
import '../../data/repositories/hiring_entity_repository.dart';
```
(already imported — confirm; if so, no new import needed.)

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/data/repositories/hiring_entity_logo_repo_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/data/repositories/hiring_entity_repository.dart lib/features/documents/providers.dart test/data/repositories/hiring_entity_logo_repo_test.dart
git commit -m "feat(documents): repo logoFor + light list() + logo provider"
```

---

## Task 4: `loadCompanyLogoBytes` helper

**Files:**
- Modify: `lib/features/documents/brand_logo.dart`
- Test: `test/features/documents/brand_logo_test.dart` (create)

**Interfaces:**
- Consumes: `HiringEntity.logoBase64` (Task 2), existing `loadBrandLogoBytes`.
- Produces: `Future<Uint8List?> loadCompanyLogoBytes(HiringEntity? entity)`.

- [ ] **Step 1: Write the failing test**

```dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll/data/models/hiring_entity.dart';
import 'package:payroll/features/documents/brand_logo.dart';

HiringEntity _entity({String? logo}) => HiringEntity(
      id: '1', companyId: 'c', code: 'X', name: 'Acme', country: 'PH',
      isActive: true, logoBase64: logo,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('prefers entity base64 over bundled asset', () async {
    final bytes = await loadCompanyLogoBytes(_entity(logo: base64.encode([9, 8, 7])));
    expect(bytes, isNotNull);
    expect(bytes!.toList(), [9, 8, 7]);
  });

  test('null entity returns null (no crash)', () async {
    // Falls through to loadBrandLogoBytes which returns null with no asset bundle.
    final bytes = await loadCompanyLogoBytes(null);
    expect(bytes, isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/documents/brand_logo_test.dart`
Expected: FAIL — `loadCompanyLogoBytes` not defined.

- [ ] **Step 3: Implement the helper**

In `lib/features/documents/brand_logo.dart` add imports + function:
```dart
import 'dart:convert';

import '../../data/models/hiring_entity.dart';
```
```dart
/// Resolve the logo bytes for a hiring entity: its uploaded base64 logo if set,
/// otherwise the bundled brand asset via [loadBrandLogoBytes]. Returns null when
/// neither is available (e.g. test env with no asset bundle).
Future<Uint8List?> loadCompanyLogoBytes(HiringEntity? entity) async {
  final b64 = entity?.logoBase64;
  if (b64 != null && b64.isNotEmpty) {
    try {
      return base64.decode(b64);
    } catch (_) {
      // fall through to bundled asset
    }
  }
  return loadBrandLogoBytes(companyName: entity?.name, code: entity?.code);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/documents/brand_logo_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/documents/brand_logo.dart test/features/documents/brand_logo_test.dart
git commit -m "feat(documents): loadCompanyLogoBytes (entity logo + asset fallback)"
```

---

## Task 5: `LetterheadBlock`

**Files:**
- Create: `lib/features/documents/blocks/letterhead_block.dart`
- Test: `test/features/documents/blocks/letterhead_block_test.dart`

**Interfaces:**
- Consumes: `LogoBlock` (existing), `CompanyHeaderBlock` (existing), `PdfTheme`.
- Produces: `LetterheadBlock({Uint8List? logoBytes, required String companyName, String? companyAddress, double logoHeight = 64})` extending `Block`.

- [ ] **Step 1: Write the failing test**

```dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll/core/pdf/pdf_theme.dart';
import 'package:payroll/features/documents/blocks/letterhead_block.dart';

void main() {
  test('renders without throwing, with and without a logo', () {
    final theme = PdfTheme.testStub();
    expect(
      () => const LetterheadBlock(companyName: 'Acme', companyAddress: '1 St')
          .toPdf(theme),
      returnsNormally,
    );
    expect(
      () => LetterheadBlock(
        logoBytes: Uint8List.fromList(const [137, 80, 78, 71]),
        companyName: 'Acme',
      ).toPdf(theme),
      returnsNormally,
    );
  });
}
```

> Confirm `PdfTheme.testStub()` exists (it's referenced by generate_screen tests). If the constructor differs, use the same stub those tests use.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/documents/blocks/letterhead_block_test.dart`
Expected: FAIL — file/class not found.

- [ ] **Step 3: Implement the block**

```dart
import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;

import '../../../core/pdf/pdf_theme.dart';
import 'block.dart';
import 'company_header_block.dart';
import 'logo_block.dart';

/// Standard letterhead: optional left-aligned logo on top, then the company
/// name (bold) + address. Used by every non-memo template; memo templates fold
/// the logo into [MemoHeaderBlock] instead (which already draws the company line).
class LetterheadBlock extends Block {
  final Uint8List? logoBytes;
  final String companyName;
  final String? companyAddress;
  final double logoHeight;
  const LetterheadBlock({
    this.logoBytes,
    required this.companyName,
    this.companyAddress,
    this.logoHeight = 64,
  });

  @override
  pw.Widget toPdf(PdfTheme theme) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (logoBytes != null) ...[
          LogoBlock(logoBytes!, height: logoHeight).toPdf(theme),
          pw.SizedBox(height: 12),
        ],
        CompanyHeaderBlock(name: companyName, address: companyAddress)
            .toPdf(theme),
      ],
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/documents/blocks/letterhead_block_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/documents/blocks/letterhead_block.dart test/features/documents/blocks/letterhead_block_test.dart
git commit -m "feat(documents): LetterheadBlock (logo + company header)"
```

---

## Task 6: `MemoHeaderBlock` optional logo

**Files:**
- Modify: `lib/features/documents/blocks/memo_header_block.dart`
- Test: `test/features/documents/blocks/memo_header_block_test.dart` (create)

**Interfaces:**
- Consumes: `LogoBlock`.
- Produces: `MemoHeaderBlock` gains `final Uint8List? logoBytes;` constructor param (optional, default null). When non-null, a `LogoBlock` + 12pt spacer render above the existing title.

- [ ] **Step 1: Write the failing test**

```dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll/core/pdf/pdf_theme.dart';
import 'package:payroll/features/documents/blocks/letter_meta_block.dart';
import 'package:payroll/features/documents/blocks/memo_header_block.dart';

void main() {
  test('accepts optional logoBytes and renders without throwing', () {
    final theme = PdfTheme.testStub();
    expect(
      () => MemoHeaderBlock(
        titleText: 'NOTICE',
        companyName: 'Acme',
        date: DateTime(2026, 6, 30),
        to: const LetterParty(name: 'Bob'),
        from: const LetterParty(name: 'HR'),
        subject: 'Hi',
        logoBytes: Uint8List.fromList(const [137, 80, 78, 71]),
      ).toPdf(theme),
      returnsNormally,
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/documents/blocks/memo_header_block_test.dart`
Expected: FAIL — no `logoBytes` parameter.

- [ ] **Step 3: Add `logoBytes`**

In `memo_header_block.dart`: add import `import 'dart:typed_data';` and `import 'logo_block.dart';`. Add field `final Uint8List? logoBytes;` and constructor param `this.logoBytes,`. In `toPdf`, make the children list start with the logo:
```dart
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        if (logoBytes != null) ...[
          LogoBlock(logoBytes!, height: 64).toPdf(theme),
          pw.SizedBox(height: 12),
        ],
        TitleBlock(titleText).toPdf(theme),
        // ... existing children unchanged ...
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/documents/blocks/memo_header_block_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/documents/blocks/memo_header_block.dart test/features/documents/blocks/memo_header_block_test.dart
git commit -m "feat(documents): MemoHeaderBlock optional logo"
```

---

## Task 7: Add `logoBytes` to the 8 inputs lacking it

**Files (each Modify):** `nda_inputs.dart`, `nod_inputs.dart`, `final_pay_inputs.dart`, `quitclaim_inputs.dart`, `regularization_inputs.dart`, `resignation_acceptance_inputs.dart`, `salary_adjustment_inputs.dart`, `liability_waiver_inputs.dart` (all under `lib/features/documents/templates/`)
- Test: `test/features/documents/templates/inputs_logo_test.dart` (create)

**Interfaces:**
- Produces: each of the 8 `*Inputs` classes gains `final Uint8List? logoBytes;`, an optional constructor param `this.logoBytes`, a `copyWith({Uint8List? logoBytes})` param with `logoBytes: logoBytes ?? this.logoBytes`, and `dart:typed_data` import. `toJson` is NOT changed (logo excluded). `fromJson` is NOT changed.

**Recipe (apply to each of the 8 files):**
1. Add `import 'dart:typed_data';` at top.
2. Add field: `final Uint8List? logoBytes;`
3. Add constructor param: `this.logoBytes,` (optional; place with other optionals).
4. Add `copyWith` param `Uint8List? logoBytes,` and pass `logoBytes: logoBytes ?? this.logoBytes,`.
5. Do NOT add to `toJson`/`fromJson`. Add a one-line comment near the field: `// Excluded from toJson — re-resolved from the entity at view time.`

Mirror the existing pattern in `nte_inputs.dart` / `coe_inputs.dart` (which already do exactly this).

- [ ] **Step 1: Write the failing test**

```dart
import 'dart:typed_data';
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll/features/documents/templates/salary_adjustment_inputs.dart';

void main() {
  final logo = Uint8List.fromList(const [1, 2, 3]);

  test('salary_adjustment copyWith carries logoBytes; toJson omits it', () {
    final i = SalaryAdjustmentInputs(
      employeeId: 'e', employeeFullName: 'B', companyId: 'c', companyName: 'Co',
      effectiveDate: DateTime(2026, 7, 1), issueDate: DateTime(2026, 6, 5),
      oldSalary: Decimal.parse('1'), newSalary: Decimal.parse('2'),
    );
    final withLogo = i.copyWith(logoBytes: logo);
    expect(withLogo.logoBytes, logo);
    expect(withLogo.toJson().containsKey('logoBytes'), isFalse);
    // copyWith without the arg preserves the existing logo
    expect(withLogo.copyWith(reason: 'x').logoBytes, logo);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/documents/templates/inputs_logo_test.dart`
Expected: FAIL — `logoBytes` not defined on `SalaryAdjustmentInputs`.

- [ ] **Step 3: Apply the recipe to all 8 inputs files**

Apply steps 1–5 of the recipe above to each of the 8 files. (`salary_adjustment_inputs.dart` `copyWith` already uses the `field ?? this.field` style — add `Uint8List? logoBytes,` to its parameter list and `logoBytes: logoBytes ?? this.logoBytes,` to the constructed object.)

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/documents/templates/inputs_logo_test.dart`
Expected: PASS.

- [ ] **Step 5: Verify nothing else broke**

Run: `flutter test test/features/documents/templates/`
Expected: PASS (existing template tests still green).

- [ ] **Step 6: Commit**

```bash
git add lib/features/documents/templates/*_inputs.dart test/features/documents/templates/inputs_logo_test.dart
git commit -m "feat(documents): add logoBytes to 8 template inputs"
```

---

## Task 8: Templates — `autofill` loads logo + `build` renders letterhead

This task updates all 12 `*_template.dart`. Split into three commits by header pattern. For EVERY template, `autofill` changes to load the logo via the new helper:

- Replace existing `loadBrandLogoBytes(companyName: co?.name, code: co?.code)` (coe, nte, non_reg) with:
  ```dart
  final logo = await loadCompanyLogoBytes(co);
  ```
  and ensure the import `import '../brand_logo.dart';` is present (it already is in those three).
- For the other 9 templates, add `import '../brand_logo.dart';`, compute `final logo = await loadCompanyLogoBytes(c);` (use whatever the company local is named — `c`/`co`), and set `logoBytes: logo` in the returned inputs. **Employment Contract** already has the field but doesn't load it — add the load + pass it.

**Interfaces:**
- Consumes: `loadCompanyLogoBytes` (Task 4), `LetterheadBlock` (Task 5), `MemoHeaderBlock.logoBytes` (Task 6), `*Inputs.logoBytes` (Task 7 + pre-existing on coe/nte/non_reg/employment_contract).

### 8a — Memo templates (fold logo into `MemoHeaderBlock`): nte, nod, regularization, resignation_acceptance

For each, set `logoBytes: i.logoBytes` on the `MemoHeaderBlock(...)` call. For **nte**, ALSO remove the now-redundant leading manual logo:
```dart
  // DELETE these two lines from NteTemplate.build:
  if (i.logoBytes != null) blocks.add(LogoBlock(i.logoBytes!));
  if (i.logoBytes != null) blocks.add(const SpacerBlock(12));
```
and add `logoBytes: i.logoBytes,` to its `MemoHeaderBlock(...)`.

- [ ] **Step 1: Write/extend failing tests**

Add to `test/features/documents/templates/nod_template_test.dart` (and analogous for the others, or a new `letterhead_render_test.dart`):
```dart
import 'dart:typed_data';
// ...
test('NOD build includes the logo when logoBytes set', () {
  final blocks = const NodTemplate().build(_i().copyWith(
    logoBytes: Uint8List.fromList(const [137, 80, 78, 71]),
  ));
  // MemoHeaderBlock is the first block and now carries the logo.
  expect(blocks.first, isA<MemoHeaderBlock>());
  expect((blocks.first as MemoHeaderBlock).logoBytes, isNotNull);
});
```
(Use each template's existing `_i()` helper; import `MemoHeaderBlock` and `dart:typed_data`.)

- [ ] **Step 2: Run to verify fail**

Run: `flutter test test/features/documents/templates/nod_template_test.dart`
Expected: FAIL — `logoBytes` getter null / not passed.

- [ ] **Step 3: Implement 8a edits** (the 4 memo templates' `build` + `autofill` logo load).

- [ ] **Step 4: Run to verify pass**

Run: `flutter test test/features/documents/templates/`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/documents/templates/nte_template.dart lib/features/documents/templates/nod_template.dart lib/features/documents/templates/regularization_template.dart lib/features/documents/templates/resignation_acceptance_template.dart test/features/documents/templates/
git commit -m "feat(documents): memo templates render logo via MemoHeaderBlock"
```

### 8b — Letterhead templates (prepend `LetterheadBlock`): salary_adjustment, non_reg, final_pay, coe

For each, add `import '../blocks/letterhead_block.dart';` and make `build` start with:
```dart
    if (i.logoBytes != null || i.companyName.isNotEmpty)
      LetterheadBlock(
        logoBytes: i.logoBytes,
        companyName: i.companyName,
        companyAddress: i.companyAddress.isEmpty ? null : i.companyAddress,
      ),
    const SpacerBlock(16),
```
Then the existing first block follows.

- **salary_adjustment**: prepend before the existing `LetterMetaBlock(...)`. (Field names: `companyName`, `companyAddress` are `String`.)
- **non_reg**: REMOVE the existing standalone `LogoBlock` lines and prepend `LetterheadBlock` instead (so the company name now shows). Its `companyAddress` may be `String?` — guard with `?? ''` / null as written.
- **final_pay**: prepend at the very start of the returned list.
- **coe**: REPLACE the existing centered `LogoBlock(i.logoBytes!, height: 100, alignment: pw.Alignment.center)` + spacer with the left-aligned `LetterheadBlock` (drops the centered look in favor of the standard letterhead).

> For `final_pay`, confirm whether its inputs expose `companyName`/`companyAddress`. If `final_pay_inputs` lacks them, add them following the salary_adjustment pattern and populate in `autofill` from `c?.name` / composed address. (Inventory: verify field names before editing.)

- [ ] **Step 1: Write failing test** (salary_adjustment — the screenshot case):

Add to `test/features/documents/templates/salary_adjustment_template_test.dart`:
```dart
import 'dart:typed_data';
import 'package:payroll/features/documents/blocks/letterhead_block.dart';
// ...
test('build prepends a LetterheadBlock with company + logo', () {
  final i = SalaryAdjustmentInputs(
    employeeId: 'e', employeeFullName: 'Bob', companyId: 'c',
    companyName: 'GameCove Online Store', companyAddress: '1 Market St',
    effectiveDate: DateTime(2026, 7, 1), issueDate: DateTime(2026, 6, 5),
    oldSalary: Decimal.parse('1'), newSalary: Decimal.parse('2'),
  ).copyWith(logoBytes: Uint8List.fromList(const [137, 80, 78, 71]));
  final blocks = const SalaryAdjustmentTemplate().build(i);
  final head = blocks.whereType<LetterheadBlock>().toList();
  expect(head, isNotEmpty);
  expect(head.first.companyName, 'GameCove Online Store');
  expect(head.first.logoBytes, isNotNull);
});
```

- [ ] **Step 2: Run to verify fail**

Run: `flutter test test/features/documents/templates/salary_adjustment_template_test.dart`
Expected: FAIL — no `LetterheadBlock` in output.

- [ ] **Step 3: Implement 8b edits** (4 templates' `build` + `autofill` logo load; add company fields to final_pay inputs if missing).

- [ ] **Step 4: Run to verify pass**

Run: `flutter test test/features/documents/templates/`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/documents/templates/salary_adjustment_template.dart lib/features/documents/templates/non_reg_template.dart lib/features/documents/templates/final_pay_template.dart lib/features/documents/templates/coe_template.dart lib/features/documents/templates/final_pay_inputs.dart test/features/documents/templates/
git commit -m "feat(documents): letterhead on salary_adjustment/non_reg/final_pay/coe"
```

### 8c — Title templates (prepend `LetterheadBlock` above the title): employment_contract, nda, quitclaim, liability_waiver

For each, add `import '../blocks/letterhead_block.dart';` and prepend before the existing `TitleBlock`/`HeadingBlock`:
```dart
    if (i.logoBytes != null || i.companyName.isNotEmpty)
      LetterheadBlock(
        logoBytes: i.logoBytes,
        companyName: i.companyName,
        companyAddress: i.companyAddress.isEmpty ? null : i.companyAddress,
      ),
    const SpacerBlock(16),
```
- **employment_contract**: already has `logoBytes`; wire `autofill` to load it (it currently ignores it) and prepend the letterhead before `TitleBlock('EMPLOYMENT CONTRACT')`. Confirm its inputs expose `companyName`/`companyAddress`; if named differently (e.g. employer fields), use those.
- **nda, quitclaim, liability_waiver**: use the `logoBytes` added in Task 7. Confirm each exposes `companyName`/`companyAddress`; if not present, add them (salary_adjustment pattern) and populate in `autofill`.

- [ ] **Step 1: Write failing test** (quitclaim):

```dart
import 'dart:typed_data';
import 'package:payroll/features/documents/blocks/letterhead_block.dart';
// in test/features/documents/templates/quitclaim_template_test.dart
test('quitclaim build prepends LetterheadBlock', () {
  final i = _i().copyWith(logoBytes: Uint8List.fromList(const [137, 80, 78, 71]));
  final blocks = const QuitclaimTemplate().build(i);
  expect(blocks.whereType<LetterheadBlock>(), isNotEmpty);
});
```
(Reuse the file's `_i()` helper; if quitclaim inputs lack `companyName`, set it in `_i()`.)

- [ ] **Step 2: Run to verify fail**

Run: `flutter test test/features/documents/templates/quitclaim_template_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement 8c edits.**

- [ ] **Step 4: Run to verify pass**

Run: `flutter test test/features/documents/templates/`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/documents/templates/employment_contract_template.dart lib/features/documents/templates/nda_template.dart lib/features/documents/templates/quitclaim_template.dart lib/features/documents/templates/liability_waiver_template.dart test/features/documents/templates/
git commit -m "feat(documents): letterhead on contract/nda/quitclaim/waiver"
```

---

## Task 9: Upload UI in the Hiring Entity form

**Files:**
- Modify: `lib/features/settings/hiring_entities/hiring_entities_settings_screen.dart`

**Interfaces:**
- Consumes: `upsert(logoBase64:, logoMime:)` (Task 3), `hiringEntityLogoProvider` (Task 3), `decodeLogoBytes` (Task 3), `file_picker`.
- Produces: a "Branding" section in `_EntityForm` with preview + Upload + Remove; `_save` passes `logoBase64`/`logoMime`.

- [ ] **Step 1: Load existing logo into form state**

Add imports:
```dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import '../../../features/documents/providers.dart';
```
Add state fields to `_FormState`:
```dart
  Uint8List? _logoBytes;      // decoded current/selected logo for preview
  String? _logoMime;          // mime of _logoBytes
  bool _logoChanged = false;  // true once user uploads/removes in this session
```
In `initState` (add one), load the existing logo when editing:
```dart
  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      ref.read(hiringEntityLogoProvider(existing.id).future).then((bytes) {
        if (!mounted || _logoChanged) return;
        setState(() {
          _logoBytes = bytes;
          _logoMime = 'image/png';
        });
      });
    }
  }
```

- [ ] **Step 2: Add the Branding UI**

Add after the "Document Defaults" section, before the `_error` block:
```dart
                const SizedBox(height: 16),
                _sectionHeader(context, 'Branding'),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 96,
                      height: 64,
                      decoration: BoxDecoration(
                        border: Border.all(color: Theme.of(context).dividerColor),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      alignment: Alignment.center,
                      child: _logoBytes == null
                          ? const Text('No logo',
                              style: TextStyle(color: Colors.grey, fontSize: 12))
                          : Image.memory(_logoBytes!, fit: BoxFit.contain),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: _pickLogo,
                      icon: const Icon(Icons.upload, size: 18),
                      label: const Text('Upload logo'),
                    ),
                    const SizedBox(width: 8),
                    if (_logoBytes != null)
                      TextButton(
                        onPressed: () => setState(() {
                          _logoBytes = null;
                          _logoMime = null;
                          _logoChanged = true;
                        }),
                        child: const Text('Remove'),
                      ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('PNG or JPG, max 300 KB. Shown as the letterhead on documents.',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                ),
```

- [ ] **Step 3: Add the picker handler**

```dart
  Future<void> _pickLogo() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg'],
      withData: true,
    );
    final file = res?.files.singleOrNull;
    final bytes = file?.bytes;
    if (bytes == null) return;
    if (bytes.lengthInBytes > 300 * 1024) {
      setState(() => _error = 'Logo too large (max 300 KB).');
      return;
    }
    final ext = (file!.extension ?? '').toLowerCase();
    setState(() {
      _logoBytes = bytes;
      _logoMime = ext == 'png' ? 'image/png' : 'image/jpeg';
      _logoChanged = true;
      _error = null;
    });
  }
```
(Add `import 'package:collection/collection.dart';` for `singleOrNull` if not present — it is used elsewhere in the codebase.)

- [ ] **Step 4: Persist in `_save`**

In the `upsert(...)` call inside `_save`, add:
```dart
            logoBase64: _logoBytes == null ? null : base64.encode(_logoBytes!),
            logoMime: _logoMime,
```

- [ ] **Step 5: Manual verify**

Run: `flutter run -d linux --dart-define-from-file=env/prod.json`
Steps: Settings → Hiring Entities → Edit an entity → Branding → Upload a small PNG → Save → reopen the dialog; the preview shows the saved logo. Try a >300 KB file; see the error.
Expected: logo persists and re-displays; oversize rejected.

- [ ] **Step 6: Commit**

```bash
git add lib/features/settings/hiring_entities/hiring_entities_settings_screen.dart
git commit -m "feat(settings): upload company logo on hiring entity"
```

---

## Task 10: Live company-change refresh in the generate screen

**Files:**
- Modify: `lib/features/documents/generate_screen.dart`
- Modify: all 12 `*_form.dart`

**Interfaces:**
- Consumes: `hiringEntityByIdProvider`, `hiringEntityLogoProvider` (Task 3), each `*Inputs.copyWith({logoBytes, companyName, companyAddress, hrManagerName})`.
- Produces: `GenerateScreen` passes `onCompanyChanged: _onPickerCompanyChanged` to every form; each form exposes `final ValueChanged<String> onCompanyChanged;` and routes `CompanyPicker.onChanged` to it (after optimistic local `companyId` set).

- [ ] **Step 1: Add `onCompanyChanged` to each form**

For EACH of the 12 forms: add constructor field `final ValueChanged<String> onCompanyChanged;` (required), and change the `CompanyPicker(onChanged:)` to:
```dart
        onChanged: (id) {
          if (id == null) return;
          _set(_i.copyWith(companyId: id)); // optimistic; or setState for forms without _set
          widget.onCompanyChanged(id);
        },
```
Remove any now-redundant local company-detail fetching (e.g. salary_adjustment's `_onCompanyChanged` and employment_contract's `_onCompanyChanged`) — that logic moves to the screen. Keep the optimistic `companyId` set.

- [ ] **Step 2: Add `_onPickerCompanyChanged` to the screen**

In `_GenerateScreenState`, add:
```dart
  Future<void> _onPickerCompanyChanged(String companyId) async {
    final tpl = findTemplateById(widget.templateId);
    if (tpl == null) return;
    final co = await ref.read(hiringEntityByIdProvider(companyId).future);
    final logo = await loadCompanyLogoBytes(co);
    if (!mounted) return;
    final name = co?.name ?? '';
    final addr = co == null ? '' : _composeCompanyAddress(co);
    final hr = co?.hrManagerName ?? '';
    setState(() {
      _dirty = true;
      if (tpl is SalaryAdjustmentTemplate && _salaryAdjustment != null) {
        _salaryAdjustment = _salaryAdjustment!.copyWith(
          companyId: companyId, companyName: name, companyAddress: addr,
          hrManagerName: _salaryAdjustment!.hrManagerName.isNotEmpty
              ? _salaryAdjustment!.hrManagerName : hr,
          logoBytes: logo,
        );
      } else if (tpl is NteTemplate && _nte != null) {
        _nte = _nte!.copyWith(
          companyId: companyId, companyName: name, companyAddress: addr,
          hrManagerName: (_nte!.hrManagerName?.isNotEmpty ?? false)
              ? _nte!.hrManagerName : hr,
          logoBytes: logo,
        );
      }
      // ... one branch per template, same shape ...
    });
  }

  String _composeCompanyAddress(dynamic co) {
    final tail = [co.city, co.province, co.zipCode]
        .where((s) => s != null && (s as String).isNotEmpty).join(', ');
    return [co.addressLine1, co.addressLine2, tail]
        .where((s) => s != null && (s as String).isNotEmpty)
        .cast<String>().join(', ');
  }
```
Add imports: `import 'brand_logo.dart';` and ensure `hiringEntityByIdProvider` is imported (via `providers.dart`, already imported).

> Write one `else if` branch per template, mirroring the field names each `*Inputs` actually exposes (some use `hrManagerName` as `String`, NTE as `String?`). For templates whose inputs lack `companyAddress`/`hrManagerName`, set only the fields they have plus `logoBytes`.

- [ ] **Step 3: Pass the callback to every form**

In `_formFor`, add `onCompanyChanged: _onPickerCompanyChanged,` to every form constructor call (all 12).

- [ ] **Step 4: Manual verify (the core bug)**

Run: `flutter run -d linux --dart-define-from-file=env/prod.json`
Steps: Documents → Salary Adjustment → pick employee → change the Company dropdown between two entities (one GameCove, one with an uploaded logo). The live preview's letterhead logo + company name update immediately on each change.
Expected: name + logo track the dropdown; typed fields (reason, salaries) are preserved.

- [ ] **Step 5: Commit**

```bash
git add lib/features/documents/generate_screen.dart lib/features/documents/forms/
git commit -m "feat(documents): refresh letterhead + logo on company change"
```

---

## Task 11: Saved-document re-render with logo for all 12

**Files:**
- Modify: `lib/features/documents/view/saved_document_renderer.dart`
- Modify: `lib/features/documents/view/document_view_screen.dart`
- Test: `test/features/documents/view/saved_document_renderer_test.dart` (create or extend)

**Interfaces:**
- Consumes: each `*Inputs.copyWith(logoBytes:)` (now all 12), `loadCompanyLogoBytes`.
- Produces: `blocksForSavedDocument` applies `.copyWith(logoBytes: logoBytes)` to ALL 12 cases; `document_view_screen` resolves the logo by `companyId` from `generation_options`.

- [ ] **Step 1: Write the failing test**

```dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll/features/documents/blocks/letterhead_block.dart';
import 'package:payroll/features/documents/view/saved_document_renderer.dart';

void main() {
  test('salary_adjustment saved render carries the passed logo', () {
    final opts = {
      '__template_id': 'salary_adjustment',
      'employeeId': 'e', 'employeeFullName': 'Bob',
      'companyId': 'c', 'companyName': 'GameCove', 'companyAddress': '1 St',
      'oldSalary': '1', 'newSalary': '2',
      'effectiveDate': '2026-07-01T00:00:00.000', 'issueDate': '2026-06-05T00:00:00.000',
      'type': 'salaryAdjustment',
    };
    final blocks = blocksForSavedDocument(opts,
        logoBytes: Uint8List.fromList(const [137, 80, 78, 71]));
    final head = blocks.whereType<LetterheadBlock>().toList();
    expect(head, isNotEmpty);
    expect(head.first.logoBytes, isNotNull);
  });
}
```

- [ ] **Step 2: Run to verify fail**

Run: `flutter test test/features/documents/view/saved_document_renderer_test.dart`
Expected: FAIL — `salary_adjustment` case ignores `logoBytes`.

- [ ] **Step 3: Apply `logoBytes` to all 12 cases**

In `blocksForSavedDocument`, change the 8 cases that currently call `.build(<Inputs>.fromJson(o))` to `.build(<Inputs>.fromJson(o).copyWith(logoBytes: logoBytes))`:
`nda`, `nod`, `final_pay`, `quitclaim`, `regularization`, `resignation_acceptance`, `salary_adjustment`, `liability_waiver`. (The 4 existing logo templates already do this.)

- [ ] **Step 4: Resolve logo by entity in the viewer**

In `document_view_screen.dart`, replace the `loadBrandLogoBytes(companyName: options['companyName'] ...)` call with resolution via the entity:
```dart
              final companyId = options['companyId'] as String?;
              final entity = (companyId == null || companyId.isEmpty)
                  ? null
                  : await ref.read(hiringEntityByIdProvider(companyId).future);
              final logo = await loadCompanyLogoBytes(entity);
              final blocks = blocksForSavedDocument(options, logoBytes: logo);
```
Add imports for `hiringEntityByIdProvider` (`../providers.dart`) and `loadCompanyLogoBytes` (`../brand_logo.dart`). Keep the existing fallback semantics (entity null → `loadCompanyLogoBytes(null)` → bundled asset).

- [ ] **Step 5: Run to verify pass**

Run: `flutter test test/features/documents/view/saved_document_renderer_test.dart test/features/documents/templates/`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/features/documents/view/saved_document_renderer.dart lib/features/documents/view/document_view_screen.dart test/features/documents/view/
git commit -m "feat(documents): saved-doc re-render resolves logo for all 12"
```

---

## Task 12: Bulk generate — per-entity logo

**Files:**
- Modify: `lib/features/documents/bulk/bulk_generate.dart`

**Interfaces:**
- Consumes: `loadCompanyLogoBytes`, each template's `autofill` (now logo-aware).

- [ ] **Step 1: Inspect the bulk path**

Read `bulk_generate.dart`. If it calls each template's `autofill(ctx)` (which now loads the logo via `loadCompanyLogoBytes(ctx.company)`), NO change is needed — confirm `ctx.company` is populated per employee's hiring entity. If it builds inputs without autofill, inject `logoBytes` by resolving the entity logo per employee with `loadCompanyLogoBytes`.

- [ ] **Step 2: Add/adjust logo resolution if needed**

If a change is required, resolve the entity for each employee and pass `logoBytes` into the per-employee inputs before `build`, mirroring `_contextFor` in the generate screen.

- [ ] **Step 3: Manual verify**

Run: `flutter run -d linux --dart-define-from-file=env/prod.json`
Steps: Documents → Bulk generate a logo-bearing template for ≥2 employees across different entities; confirm each section shows the correct letterhead.
Expected: correct per-entity logos.

- [ ] **Step 4: Commit**

```bash
git add lib/features/documents/bulk/bulk_generate.dart
git commit -m "feat(documents): bulk generate carries per-entity logo"
```

---

## Task 13: Full regression + analyzer

- [ ] **Step 1: Analyze**

Run: `flutter analyze`
Expected: no new errors.

- [ ] **Step 2: Full test suite**

Run: `flutter test`
Expected: all green.

- [ ] **Step 3: Commit any fixups**

```bash
git add -A
git commit -m "chore(documents): analyzer + test fixups for logo letterhead"
```

---

## Self-Review notes (for the implementer)

- **Verify field names before editing** each template's inputs: not all expose `companyName`/`companyAddress`/`hrManagerName`. Where missing on a template that needs the letterhead (candidates: final_pay, nda, quitclaim, liability_waiver, employment_contract), add them following the `salary_adjustment_inputs.dart` pattern and populate in `autofill`. This is the one place the plan defers to the file's actual shape.
- **`kReRenderableSavedTemplateIds`** already lists all 12; no change needed there, but keep the sync test green.
- **Package import prefix**: tests assume `package:payroll/...`. Confirm against `pubspec.yaml` `name:` and adjust all test imports if different.
- **`PdfTheme.testStub()`**: confirm the exact stub constructor used by existing `generate_screen`/template tests and match it.
- **COE visual change**: its logo moves from centered (height 100) to the standard left-aligned letterhead. This is intended per the approved design.
