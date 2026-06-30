# Task 13 — Critical Fix: Uploaded Logo Never Rendered

**Date:** 2026-06-30
**Branch:** feat/memo-image-attachment

---

## Root Cause (pre-diagnosed)

`loadCompanyLogoBytes(HiringEntity? entity)` in `lib/features/documents/brand_logo.dart` reads `entity.logoBase64`. Every render path resolves its entity through `hiringEntityByIdProvider`, which previously scanned `HiringEntityRepository.list()`. `list()` deliberately excludes `logo_base64`/`logo_mime` to keep the picker payload light. Consequently every entity returned by `hiringEntityByIdProvider` had `logoBase64 == null`, so `loadCompanyLogoBytes` always fell through to the bundled-asset fallback — the uploaded logo was silently ignored for all 12 templates, generate_screen, document_view_screen, and bulk_generate.

The base64 was only ever fetched by `logoFor()`/`hiringEntityLogoProvider`, used solely by the settings upload preview — never by a render path.

---

## Changes Made

### 1. `lib/data/repositories/hiring_entity_repository.dart`

Added `byId(String id)` method:

```dart
/// Fetch one entity by id, INCLUDING the logo columns (unlike [list], which
/// omits them to keep the picker light). Used by render paths that need the
/// uploaded logo. Returns null when not found / soft-deleted.
Future<HiringEntity?> byId(String id) async {
  final row = await _client
      .from('hiring_entities')
      .select()
      .eq('id', id)
      .isFilter('deleted_at', null)
      .maybeSingle();
  return row == null ? null : HiringEntity.fromRow(row);
}
```

`.select()` with no column list returns all columns, including `logo_base64` and `logo_mime`. `HiringEntity.fromRow` already maps both.

### 2. `lib/features/documents/providers.dart`

**`hiringEntityByIdProvider`** — replaced list-scan with direct `byId` call:

```dart
final hiringEntityByIdProvider = FutureProvider.family<HiringEntity?, String>((
  ref,
  id,
) async {
  return ref.watch(hiringEntityRepositoryProvider).byId(id);
});
```

Uses `ref.watch` so test overrides of `hiringEntityRepositoryProvider` propagate correctly.

Removed now-unused import of `../auth/profile_provider.dart`.

**`hiringEntityLogoProvider`** — changed `ref.read` → `ref.watch` for consistency with test-override propagation:

```dart
final logo = await ref
    .watch(hiringEntityRepositoryProvider)
    .logoFor(entityId);
```

### 3. `test/features/documents/hiring_entity_logo_resolution_test.dart` (new)

Verifies the full chain: provider override → `byId` returns entity with `logoBase64` set → `loadCompanyLogoBytes` returns the decoded uploaded bytes, not the bundled fallback.

---

## Why All Render Paths Are Fixed

Every template (all 12), `generate_screen.dart`, `document_view_screen.dart`, and `bulk_generate` resolve the company entity via `hiringEntityByIdProvider`. Now that provider calls `byId()` instead of `list()`, every entity it returns carries `logoBase64`. `loadCompanyLogoBytes` checks `entity?.logoBase64` first and returns it immediately when non-null — the bundled asset is only reached if no uploaded logo exists. No template files were touched.

---

## Verification Results

```
flutter analyze lib/data/repositories/hiring_entity_repository.dart \
               lib/features/documents/providers.dart \
               test/features/documents/hiring_entity_logo_resolution_test.dart
# No issues found! (ran in 1.1s)

flutter test test/features/documents/
# +361: All tests passed!
```

---

## Files Modified

| File | Change |
|------|--------|
| `lib/data/repositories/hiring_entity_repository.dart` | Added `byId()` method |
| `lib/features/documents/providers.dart` | Rewired `hiringEntityByIdProvider` to use `byId()`; `ref.read` → `ref.watch` in `hiringEntityLogoProvider`; removed unused import |
| `test/features/documents/hiring_entity_logo_resolution_test.dart` | New test file (2 test cases) |
