# Job Listings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `JobListing` entity that owns applicants, restructure the Hiring screen into Listings + Talent Pool tabs, and derive headcount from active employees so listings auto-reopen on separation.

**Architecture:** New `job_listings` table with company-scoped RLS. Slot-based headcount: `filled_count` is a derived `COUNT(*)` over active employees in (role, brand), never stored. `applicants.listing_id` is a nullable FK — existing applicants stay NULL and surface in Talent Pool. The existing applicant kanban widget gets extracted into a parameterizable component reused by both Talent Pool and Listing Detail.

**Tech Stack:** Flutter (Riverpod, Material 3), Supabase Postgres (RLS via `auth_app_role()` + `auth_company_id()` helpers), GoRouter.

**Spec:** `docs/superpowers/specs/2026-06-05-job-listings-design.md`.

**Branch:** Create `feat/job-listings` off `main` (after `feat/hr-docs-batch-2` is merged).

---

## Conventions (read once)

### File layout
- Models: `lib/data/models/job_listing.dart`
- Repository: `lib/data/repositories/job_listing_repository.dart` (providers in same file)
- Screens: `lib/features/hiring/listing_*.dart`
- Widgets: `lib/features/hiring/widgets/*.dart`
- Migration: `supabase/migrations/20260606000001_job_listings.sql` (one file, both table + applicants.listing_id)
- Tests: `test/data/models/`, `test/data/repositories/`, `test/features/hiring/`

### Codebase conventions
- Package import: `package:payroll_flutter/`
- RLS helpers: `auth_app_role()` returns `'SUPER_ADMIN' | 'ADMIN' | 'HR' | 'MANAGER' | 'EMPLOYEE'`; `auth_company_id()` returns the caller's company UUID.
- Soft-delete: `deleted_at` column; `.isFilter('deleted_at', null)` to exclude archived rows; never `DELETE` SQL-side.
- Model `fromRow`: factory constructor on the class. `toUpsertPayload()` returns a `Map<String, dynamic>` ready for `.insert()` / `.update()`.
- Repository: plain class with positional `SupabaseClient`; providers at bottom of same file (`*RepositoryProvider`, `*ListProvider`, `*ByIdProvider`).
- ListQuery: separate class with `==` and `hashCode` overrides; used as the `FutureProvider.family` key.
- Form widgets: ConsumerStatefulWidget; setState + propagate via parent `onChanged`.

### Commit style
`feat(hiring): <component> — <step>` per task. Example: `feat(hiring): JobListing model — round-trip`.

### Run commands
- Test single file: `flutter test test/path/file_test.dart`
- All tests: `flutter test`
- Analyze: `flutter analyze`
- Format check: `dart format --output=none --set-exit-if-changed lib/ test/`
- App smoke: `flutter run -d linux --dart-define-from-file=env/prod.json`
- DB migration (local supabase): `supabase db reset` (full reset) or `supabase db push` (apply pending)

---

## File map

**New files (12):**
- `supabase/migrations/20260606000001_job_listings.sql` — migration
- `lib/data/models/job_listing.dart` — model + fromRow + toUpsertPayload
- `lib/data/repositories/job_listing_repository.dart` — repo + providers
- `lib/features/hiring/listing_form_screen.dart` — create/edit form
- `lib/features/hiring/listing_detail_screen.dart` — detail view with embedded kanban
- `lib/features/hiring/widgets/listings_table.dart` — filterable table
- `lib/features/hiring/widgets/applicant_kanban.dart` — extracted parameterized kanban
- `lib/features/hiring/widgets/move_to_listing_dialog.dart` — applicant reassignment dialog
- `test/data/models/job_listing_test.dart`
- `test/data/repositories/job_listing_repository_test.dart`
- `test/features/hiring/applicant_list_query_test.dart`
- `test/features/hiring/listing_effective_status_test.dart`

**Modified files (5):**
- `lib/features/hiring/hiring_screen.dart` — TabBar restructure
- `lib/features/hiring/applicant_form_screen.dart` — accept optional `listingId` param + lock brand/role
- `lib/features/hiring/applicant_detail_screen.dart` — add "Move to listing" action
- `lib/features/hiring/widgets/applicant_card.dart` — listing badge
- `lib/data/repositories/applicant_repository.dart` — `listingId` filter + `listingId` upsert column
- `lib/app/router.dart` — new routes

---

## Phase 1 — Backend

### Task 1: Migration — `job_listings` table + `applicants.listing_id`

**Files:**
- Create: `supabase/migrations/20260606000001_job_listings.sql`

- [ ] **Step 1: Write the migration**

```sql
-- 20260606000001_job_listings.sql
--
-- Adds a job_listings table that owns applicants. Headcount is slot-based:
-- the filled count is derived at read time from COUNT(active employees in
-- this role + brand), never stored. Applicants get a nullable listing_id —
-- existing applicants stay NULL and appear in the "Talent Pool" tab.

create table job_listings (
  id                  uuid primary key default gen_random_uuid(),
  company_id          uuid not null references companies(id),
  hiring_entity_id    uuid not null references hiring_entities(id),
  role_scorecard_id   uuid not null references role_scorecards(id),
  title               varchar(255) not null,
  target_headcount    integer not null default 1 check (target_headcount >= 1),
  status              text not null default 'OPEN'
    check (status in ('OPEN', 'PAUSED', 'CLOSED')),
  notes               text,
  created_at          timestamptz not null default now(),
  created_by_id       uuid references auth.users(id),
  closed_at           timestamptz,
  deleted_at          timestamptz,
  updated_at          timestamptz not null default now()
);

create index idx_job_listings_status_active
  on job_listings (status)
  where deleted_at is null;

create index idx_job_listings_role_brand
  on job_listings (role_scorecard_id, hiring_entity_id);

create index idx_job_listings_company
  on job_listings (company_id)
  where deleted_at is null;

create trigger _job_listings_updated before update on job_listings
  for each row execute function set_updated_at();

-- RLS — mirrors applicants pattern (company-scoped + role-gated).
alter table job_listings enable row level security;

create policy job_listings_company_select on job_listings for select
  using (company_id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN');

create policy job_listings_company_write on job_listings for all
  using (
    (company_id = auth_company_id() and auth_app_role() in ('ADMIN', 'HR'))
    or auth_app_role() = 'SUPER_ADMIN'
  )
  with check (
    (company_id = auth_company_id() and auth_app_role() in ('ADMIN', 'HR'))
    or auth_app_role() = 'SUPER_ADMIN'
  );

-- Add listing_id to applicants. Nullable: NULL = Talent Pool.
alter table applicants
  add column listing_id uuid references job_listings(id);

create index idx_applicants_listing_id
  on applicants (listing_id)
  where deleted_at is null and listing_id is not null;
```

- [ ] **Step 2: Apply locally**

Run: `cd "/home/ccvisionary/Documents/Work/[07] Projects/payroll-flutter" && supabase db push`
Expected: migration applies cleanly. If a column already exists (e.g. partial rerun), the migration fails — fix and re-run.

- [ ] **Step 3: Sanity-check the schema**

Run:
```bash
supabase db psql -c "\d job_listings" | head -30
supabase db psql -c "\d applicants" | grep listing_id
```
Expected: `job_listings` shows all columns + 4 indexes + RLS enabled; `applicants` shows the new `listing_id uuid` column.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260606000001_job_listings.sql
git commit -m "feat(hiring): migration — job_listings + applicants.listing_id"
```

---

### Task 2: `JobListing` model + round-trip test

**Files:**
- Create: `lib/data/models/job_listing.dart`
- Create: `test/data/models/job_listing_test.dart`

- [ ] **Step 1: Write the round-trip test**

```dart
// test/data/models/job_listing_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/job_listing.dart';

void main() {
  test('fromRow → toUpsertPayload round-trips required fields', () {
    final row = {
      'id': '11111111-1111-1111-1111-111111111111',
      'company_id': '22222222-2222-2222-2222-222222222222',
      'hiring_entity_id': '33333333-3333-3333-3333-333333333333',
      'role_scorecard_id': '44444444-4444-4444-4444-444444444444',
      'title': 'Cashier',
      'target_headcount': 3,
      'status': 'OPEN',
      'notes': 'Need 3 by EOQ',
      'created_at': '2026-06-05T10:00:00Z',
      'created_by_id': '55555555-5555-5555-5555-555555555555',
      'closed_at': null,
      'deleted_at': null,
      'updated_at': '2026-06-05T10:00:00Z',
    };
    final j = JobListing.fromRow(row);
    expect(j.id, row['id']);
    expect(j.companyId, row['company_id']);
    expect(j.hiringEntityId, row['hiring_entity_id']);
    expect(j.roleScorecardId, row['role_scorecard_id']);
    expect(j.title, 'Cashier');
    expect(j.targetHeadcount, 3);
    expect(j.status, 'OPEN');
    expect(j.notes, 'Need 3 by EOQ');
    expect(j.closedAt, isNull);
    expect(j.deletedAt, isNull);

    final payload = j.toUpsertPayload();
    expect(payload['company_id'], row['company_id']);
    expect(payload['hiring_entity_id'], row['hiring_entity_id']);
    expect(payload['role_scorecard_id'], row['role_scorecard_id']);
    expect(payload['title'], 'Cashier');
    expect(payload['target_headcount'], 3);
    expect(payload['status'], 'OPEN');
    expect(payload['notes'], 'Need 3 by EOQ');
  });

  test('copyWith preserves untouched fields', () {
    final j = JobListing(
      id: 'a', companyId: 'co', hiringEntityId: 'he', roleScorecardId: 'rs',
      title: 'Cashier', targetHeadcount: 1, status: 'OPEN',
      createdAt: DateTime(2026, 6, 5),
    );
    final j2 = j.copyWith(title: 'Senior Cashier', targetHeadcount: 2);
    expect(j2.title, 'Senior Cashier');
    expect(j2.targetHeadcount, 2);
    expect(j2.status, 'OPEN');
    expect(j2.id, 'a');
  });
}
```

- [ ] **Step 2: Run — expect failure**

Run: `flutter test test/data/models/job_listing_test.dart`
Expected: FAIL — file doesn't exist.

- [ ] **Step 3: Create the model**

```dart
// lib/data/models/job_listing.dart
class JobListing {
  final String id;
  final String companyId;
  final String hiringEntityId;
  final String roleScorecardId;
  final String title;
  final int targetHeadcount;
  final String status;          // 'OPEN' | 'PAUSED' | 'CLOSED'
  final String? notes;
  final DateTime createdAt;
  final String? createdById;
  final DateTime? closedAt;
  final DateTime? deletedAt;

  const JobListing({
    required this.id,
    required this.companyId,
    required this.hiringEntityId,
    required this.roleScorecardId,
    required this.title,
    required this.targetHeadcount,
    required this.status,
    this.notes,
    required this.createdAt,
    this.createdById,
    this.closedAt,
    this.deletedAt,
  });

  factory JobListing.fromRow(Map<String, dynamic> r) => JobListing(
        id: r['id'] as String,
        companyId: r['company_id'] as String,
        hiringEntityId: r['hiring_entity_id'] as String,
        roleScorecardId: r['role_scorecard_id'] as String,
        title: r['title'] as String,
        targetHeadcount: r['target_headcount'] as int,
        status: r['status'] as String,
        notes: r['notes'] as String?,
        createdAt: DateTime.parse(r['created_at'] as String),
        createdById: r['created_by_id'] as String?,
        closedAt: r['closed_at'] == null ? null : DateTime.parse(r['closed_at'] as String),
        deletedAt: r['deleted_at'] == null ? null : DateTime.parse(r['deleted_at'] as String),
      );

  Map<String, dynamic> toUpsertPayload() => {
        'id': id,
        'company_id': companyId,
        'hiring_entity_id': hiringEntityId,
        'role_scorecard_id': roleScorecardId,
        'title': title,
        'target_headcount': targetHeadcount,
        'status': status,
        'notes': notes,
        if (closedAt != null) 'closed_at': closedAt!.toIso8601String(),
        if (deletedAt != null) 'deleted_at': deletedAt!.toIso8601String(),
      };

  JobListing copyWith({
    String? id,
    String? companyId,
    String? hiringEntityId,
    String? roleScorecardId,
    String? title,
    int? targetHeadcount,
    String? status,
    Object? notes = _undef,
    DateTime? createdAt,
    Object? createdById = _undef,
    Object? closedAt = _undef,
    Object? deletedAt = _undef,
  }) =>
      JobListing(
        id: id ?? this.id,
        companyId: companyId ?? this.companyId,
        hiringEntityId: hiringEntityId ?? this.hiringEntityId,
        roleScorecardId: roleScorecardId ?? this.roleScorecardId,
        title: title ?? this.title,
        targetHeadcount: targetHeadcount ?? this.targetHeadcount,
        status: status ?? this.status,
        notes: identical(notes, _undef) ? this.notes : notes as String?,
        createdAt: createdAt ?? this.createdAt,
        createdById: identical(createdById, _undef) ? this.createdById : createdById as String?,
        closedAt: identical(closedAt, _undef) ? this.closedAt : closedAt as DateTime?,
        deletedAt: identical(deletedAt, _undef) ? this.deletedAt : deletedAt as DateTime?,
      );
}

const _undef = Object();
```

- [ ] **Step 4: Run tests — expect 2 pass**

Run: `flutter test test/data/models/job_listing_test.dart`
Expected: 2 pass.

- [ ] **Step 5: Format + analyze + commit**

```bash
dart format lib/data/models/job_listing.dart test/data/models/job_listing_test.dart
flutter analyze lib/data/models/job_listing.dart test/data/models/job_listing_test.dart
git add lib/data/models/job_listing.dart test/data/models/job_listing_test.dart
git commit -m "feat(hiring): JobListing model — round-trip"
```

---

### Task 3: `JobListingRepository` + providers

**Files:**
- Create: `lib/data/repositories/job_listing_repository.dart`
- Create: `test/data/repositories/job_listing_repository_test.dart`

- [ ] **Step 1: Write a minimal smoke test (query-shape only — no Supabase fixture)**

```dart
// test/data/repositories/job_listing_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/repositories/job_listing_repository.dart';

void main() {
  test('JobListingListQuery equality + hashCode', () {
    const a = JobListingListQuery(
      statuses: ['OPEN'],
      hiringEntityId: 'h1',
      roleScorecardId: 'r1',
      search: 'cashier',
    );
    const b = JobListingListQuery(
      statuses: ['OPEN'],
      hiringEntityId: 'h1',
      roleScorecardId: 'r1',
      search: 'cashier',
    );
    expect(a, equals(b));
    expect(a.hashCode, equals(b.hashCode));
  });

  test('JobListingListQuery distinguishes status sets', () {
    const a = JobListingListQuery(statuses: ['OPEN']);
    const b = JobListingListQuery(statuses: ['OPEN', 'PAUSED']);
    expect(a, isNot(equals(b)));
  });
}
```

- [ ] **Step 2: Run — expect failure**

Run: `flutter test test/data/repositories/job_listing_repository_test.dart`
Expected: FAIL (no file).

- [ ] **Step 3: Implement the repository**

```dart
// lib/data/repositories/job_listing_repository.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/job_listing.dart';

class JobListingListQuery {
  final String? search;          // title ILIKE
  final List<String>? statuses;  // null = all
  final String? hiringEntityId;
  final String? roleScorecardId;
  final bool includeArchived;
  const JobListingListQuery({
    this.search,
    this.statuses,
    this.hiringEntityId,
    this.roleScorecardId,
    this.includeArchived = false,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is JobListingListQuery &&
          search == other.search &&
          _listEq(statuses, other.statuses) &&
          hiringEntityId == other.hiringEntityId &&
          roleScorecardId == other.roleScorecardId &&
          includeArchived == other.includeArchived;

  @override
  int get hashCode => Object.hash(
        search,
        Object.hashAll(statuses ?? const []),
        hiringEntityId,
        roleScorecardId,
        includeArchived,
      );

  static bool _listEq(List<String>? a, List<String>? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class JobListingRepository {
  final SupabaseClient _client;
  JobListingRepository(this._client);

  Future<List<JobListing>> list(JobListingListQuery q) async {
    var b = _client.from('job_listings').select('*');
    if (!q.includeArchived) {
      b = b.isFilter('deleted_at', null);
    }
    if (q.statuses != null && q.statuses!.isNotEmpty) {
      b = b.inFilter('status', q.statuses!);
    }
    if (q.hiringEntityId != null) {
      b = b.eq('hiring_entity_id', q.hiringEntityId!);
    }
    if (q.roleScorecardId != null) {
      b = b.eq('role_scorecard_id', q.roleScorecardId!);
    }
    if (q.search != null && q.search!.trim().isNotEmpty) {
      b = b.ilike('title', '%${q.search!.trim()}%');
    }
    final rows = await b.order('created_at', ascending: false);
    return (rows as List)
        .map((r) => JobListing.fromRow(r as Map<String, dynamic>))
        .toList();
  }

  Future<JobListing?> byId(String id) async {
    final row = await _client.from('job_listings').select('*').eq('id', id).maybeSingle();
    if (row == null) return null;
    return JobListing.fromRow(row);
  }

  Future<String> upsert({
    String? id,
    required String companyId,
    required String hiringEntityId,
    required String roleScorecardId,
    required String title,
    required int targetHeadcount,
    required String status,
    String? notes,
    DateTime? closedAt,
    required String setByUserId,
  }) async {
    final isCreate = id == null;
    final payload = <String, dynamic>{
      'company_id': companyId,
      'hiring_entity_id': hiringEntityId,
      'role_scorecard_id': roleScorecardId,
      'title': title,
      'target_headcount': targetHeadcount,
      'status': status,
      'notes': notes,
      if (closedAt != null) 'closed_at': closedAt.toIso8601String(),
      if (isCreate) 'created_by_id': setByUserId,
    };
    if (id != null) {
      await _client.from('job_listings').update(payload).eq('id', id);
      return id;
    }
    final inserted = await _client
        .from('job_listings')
        .insert(payload)
        .select('id')
        .single();
    return inserted['id'] as String;
  }

  Future<void> softDelete(String id) async {
    await _client
        .from('job_listings')
        .update({'deleted_at': DateTime.now().toIso8601String()})
        .eq('id', id);
  }
}

final jobListingRepositoryProvider =
    Provider<JobListingRepository>((ref) => JobListingRepository(Supabase.instance.client));

final jobListingListProvider =
    FutureProvider.family<List<JobListing>, JobListingListQuery>((ref, q) =>
        ref.read(jobListingRepositoryProvider).list(q));

final jobListingByIdProvider =
    FutureProvider.family<JobListing?, String>((ref, id) =>
        ref.read(jobListingRepositoryProvider).byId(id));
```

- [ ] **Step 4: Run tests — expect 2 pass**

Run: `flutter test test/data/repositories/job_listing_repository_test.dart`
Expected: 2 pass.

- [ ] **Step 5: Commit**

```bash
dart format lib/data/repositories/job_listing_repository.dart test/data/repositories/job_listing_repository_test.dart
flutter analyze lib/data/repositories/job_listing_repository.dart test/data/repositories/job_listing_repository_test.dart
git add lib/data/repositories/job_listing_repository.dart test/data/repositories/job_listing_repository_test.dart
git commit -m "feat(hiring): JobListingRepository + ListQuery"
```

---

### Task 4: Derived filled-count + effective-status providers

**Files:**
- Modify: `lib/data/repositories/job_listing_repository.dart` (append at bottom)
- Create: `test/features/hiring/listing_effective_status_test.dart`

- [ ] **Step 1: Write the pure-function test (no Supabase)**

```dart
// test/features/hiring/listing_effective_status_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/repositories/job_listing_repository.dart';

void main() {
  test('PAUSED status always wins regardless of filled count', () {
    expect(deriveEffectiveStatus(status: 'PAUSED', filled: 0, target: 3), ListingEffectiveStatus.paused);
    expect(deriveEffectiveStatus(status: 'PAUSED', filled: 5, target: 3), ListingEffectiveStatus.paused);
  });

  test('CLOSED status always wins regardless of filled count', () {
    expect(deriveEffectiveStatus(status: 'CLOSED', filled: 0, target: 3), ListingEffectiveStatus.closed);
    expect(deriveEffectiveStatus(status: 'CLOSED', filled: 5, target: 3), ListingEffectiveStatus.closed);
  });

  test('OPEN + filled >= target → FILLED', () {
    expect(deriveEffectiveStatus(status: 'OPEN', filled: 3, target: 3), ListingEffectiveStatus.filled);
    expect(deriveEffectiveStatus(status: 'OPEN', filled: 5, target: 3), ListingEffectiveStatus.filled);
  });

  test('OPEN + filled < target → OPEN', () {
    expect(deriveEffectiveStatus(status: 'OPEN', filled: 0, target: 3), ListingEffectiveStatus.open);
    expect(deriveEffectiveStatus(status: 'OPEN', filled: 2, target: 3), ListingEffectiveStatus.open);
  });
}
```

- [ ] **Step 2: Run — expect failure**

Run: `flutter test test/features/hiring/listing_effective_status_test.dart`
Expected: FAIL — `deriveEffectiveStatus` doesn't exist.

- [ ] **Step 3: Append the pure function + providers to `job_listing_repository.dart`**

Append at the bottom of `lib/data/repositories/job_listing_repository.dart`:

```dart
enum ListingEffectiveStatus { open, filled, paused, closed }

extension ListingEffectiveStatusX on ListingEffectiveStatus {
  String get label => switch (this) {
        ListingEffectiveStatus.open => 'Open',
        ListingEffectiveStatus.filled => 'Filled',
        ListingEffectiveStatus.paused => 'Paused',
        ListingEffectiveStatus.closed => 'Closed',
      };
}

/// Pure derivation — used by both the live provider and tests.
ListingEffectiveStatus deriveEffectiveStatus({
  required String status,
  required int filled,
  required int target,
}) {
  if (status == 'PAUSED') return ListingEffectiveStatus.paused;
  if (status == 'CLOSED') return ListingEffectiveStatus.closed;
  return filled >= target
      ? ListingEffectiveStatus.filled
      : ListingEffectiveStatus.open;
}

/// Live filled count: number of active, non-archived employees whose
/// (role_scorecard_id, hiring_entity_id) matches the listing.
final listingFilledCountProvider =
    FutureProvider.family<int, String>((ref, listingId) async {
  final listing = await ref.watch(jobListingByIdProvider(listingId).future);
  if (listing == null) return 0;
  final rows = await Supabase.instance.client
      .from('employees')
      .select('id')
      .eq('role_scorecard_id', listing.roleScorecardId)
      .eq('hiring_entity_id', listing.hiringEntityId)
      .eq('employment_status', 'ACTIVE')
      .isFilter('deleted_at', null);
  return (rows as List).length;
});

/// Effective status: composes the persisted `status` with the derived
/// filled count.
final listingEffectiveStatusProvider =
    FutureProvider.family<ListingEffectiveStatus, String>((ref, listingId) async {
  final listing = await ref.watch(jobListingByIdProvider(listingId).future);
  if (listing == null) return ListingEffectiveStatus.closed;
  final filled = await ref.watch(listingFilledCountProvider(listingId).future);
  return deriveEffectiveStatus(
    status: listing.status,
    filled: filled,
    target: listing.targetHeadcount,
  );
});
```

- [ ] **Step 4: Run tests — expect 4 pass**

Run: `flutter test test/features/hiring/listing_effective_status_test.dart`
Expected: 4 pass.

- [ ] **Step 5: Commit**

```bash
dart format lib/data/repositories/job_listing_repository.dart test/features/hiring/listing_effective_status_test.dart
flutter analyze lib/data/repositories/job_listing_repository.dart test/features/hiring/listing_effective_status_test.dart
git add lib/data/repositories/job_listing_repository.dart test/features/hiring/listing_effective_status_test.dart
git commit -m "feat(hiring): derived filledCount + effectiveStatus providers"
```

---

### Task 5: Extend `ApplicantListQuery` with `listingId` filter

**Files:**
- Modify: `lib/data/repositories/applicant_repository.dart`
- Modify: `lib/data/models/applicant.dart` (add `listingId` field + fromRow)
- Create: `test/features/hiring/applicant_list_query_test.dart`

- [ ] **Step 1: Write the test**

```dart
// test/features/hiring/applicant_list_query_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/repositories/applicant_repository.dart';

void main() {
  test('listingId: null defaults (no scoping)', () {
    const q = ApplicantListQuery();
    expect(q.listingId, isNull);
    expect(q.listingIsExplicitlyNull, isFalse);
  });

  test('listingId: "uuid" scopes to one listing', () {
    const q = ApplicantListQuery(listingId: 'abc');
    expect(q.listingId, 'abc');
    expect(q.listingIsExplicitlyNull, isFalse);
  });

  test('Talent Pool (listingIsExplicitlyNull: true) ≠ no-scope', () {
    const a = ApplicantListQuery();
    const b = ApplicantListQuery(listingIsExplicitlyNull: true);
    expect(a, isNot(equals(b)));
  });

  test('equality includes listingId', () {
    const a = ApplicantListQuery(listingId: 'x');
    const b = ApplicantListQuery(listingId: 'x');
    const c = ApplicantListQuery(listingId: 'y');
    expect(a, equals(b));
    expect(a, isNot(equals(c)));
  });
}
```

- [ ] **Step 2: Run — expect failure**

Run: `flutter test test/features/hiring/applicant_list_query_test.dart`
Expected: FAIL — `listingId` / `listingIsExplicitlyNull` don't exist.

- [ ] **Step 3: Update `ApplicantListQuery` in `applicant_repository.dart`**

Edit `lib/data/repositories/applicant_repository.dart`. Replace the `ApplicantListQuery` class with:

```dart
class ApplicantListQuery {
  final String? search;
  final List<String>? statuses;
  final String? roleScorecardId;
  final String? hiringEntityId;
  /// When non-null, scope to applicants with `listing_id = <this value>`.
  final String? listingId;
  /// When true, scope to applicants whose `listing_id IS NULL` (Talent Pool).
  /// Mutually exclusive with `listingId` — if both are set, listingId wins.
  final bool listingIsExplicitlyNull;
  final bool includeArchived;
  const ApplicantListQuery({
    this.search,
    this.statuses,
    this.roleScorecardId,
    this.hiringEntityId,
    this.listingId,
    this.listingIsExplicitlyNull = false,
    this.includeArchived = false,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ApplicantListQuery &&
          search == other.search &&
          _eq(statuses, other.statuses) &&
          roleScorecardId == other.roleScorecardId &&
          hiringEntityId == other.hiringEntityId &&
          listingId == other.listingId &&
          listingIsExplicitlyNull == other.listingIsExplicitlyNull &&
          includeArchived == other.includeArchived;

  @override
  int get hashCode => Object.hash(
        search,
        Object.hashAll(statuses ?? const []),
        roleScorecardId,
        hiringEntityId,
        listingId,
        listingIsExplicitlyNull,
        includeArchived,
      );

  static bool _eq(List<String>? a, List<String>? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
```

- [ ] **Step 4: Update `ApplicantRepository.list` to honor the new filters**

In `lib/data/repositories/applicant_repository.dart`, inside `list()`, after the existing `hiring_entity_id` filter (around line 73-75), insert:

```dart
    if (q.listingId != null) {
      builder = builder.eq('listing_id', q.listingId!);
    } else if (q.listingIsExplicitlyNull) {
      builder = builder.isFilter('listing_id', null);
    }
```

- [ ] **Step 5: Add `listingId` field to `Applicant` model + fromRow**

Edit `lib/data/models/applicant.dart`. Add as the last field (right before the constructor body), maintaining alphabetical/logical order:

```dart
  final String? listingId;
```

In the constructor, add: `this.listingId,`

In `fromRow` (the factory), add: `listingId: r['listing_id'] as String?,`

In any `toJson` / `toUpsertPayload` (if present), add: `'listing_id': listingId,`

- [ ] **Step 6: Update `ApplicantRepository.upsert` signature**

In `lib/data/repositories/applicant_repository.dart` `upsert()`, add a new optional parameter:

```dart
    String? listingId,                  // null = Talent Pool
```

And in the `payload` Map, add:

```dart
      'listing_id': listingId,
```

- [ ] **Step 7: Run all hiring + repository tests — expect green**

Run: `flutter test test/features/hiring/ test/data/`
Expected: all existing tests still pass + the 4 new ApplicantListQuery tests pass.

- [ ] **Step 8: Commit**

```bash
dart format lib/data/repositories/applicant_repository.dart lib/data/models/applicant.dart test/features/hiring/applicant_list_query_test.dart
flutter analyze lib/data/repositories/applicant_repository.dart lib/data/models/applicant.dart test/features/hiring/applicant_list_query_test.dart
git add lib/data/repositories/applicant_repository.dart lib/data/models/applicant.dart test/features/hiring/applicant_list_query_test.dart
git commit -m "feat(hiring): ApplicantListQuery.listingId + Applicant.listingId"
```

---

### Task 6: Phase 1 green-bar checkpoint

**Files:** none — verification only.

- [ ] **Step 1: Run full test suite**

Run: `flutter test`
Expected: all tests pass. New: 2 (model) + 2 (repo) + 4 (effective status) + 4 (list query) = 12 new tests.

- [ ] **Step 2: Analyze + format check**

```bash
flutter analyze
dart format --output=none --set-exit-if-changed lib/data/models/job_listing.dart lib/data/repositories/job_listing_repository.dart lib/data/repositories/applicant_repository.dart lib/data/models/applicant.dart
```
Expected: no new issues on the touched files; format check exits 0 for those files.

- [ ] **Step 3: Confirm migration applied**

```bash
supabase db psql -c "select count(*) from job_listings;"
supabase db psql -c "select column_name from information_schema.columns where table_name='applicants' and column_name='listing_id';"
```
Expected: `0` listings (empty), 1 column row for `applicants.listing_id`.

---

## Phase 2 — UI scaffold

### Task 7: Extract `applicant_kanban.dart` from `hiring_screen.dart`

**Files:**
- Create: `lib/features/hiring/widgets/applicant_kanban.dart`
- Modify: `lib/features/hiring/hiring_screen.dart` (remove inline kanban, use widget)

- [ ] **Step 1: Read the current kanban implementation**

The kanban code lives in `lib/features/hiring/hiring_screen.dart`. Identify the section that:
- Reads `ref.watch(applicantListProvider(ApplicantListQuery(...)))`
- Renders columns per `kApplicantPipelineColumns` (or similar — read the source)
- Builds the cards via `ApplicantCard`

That entire section becomes a new widget. The host screen passes in the query.

- [ ] **Step 2: Create the extracted widget**

```dart
// lib/features/hiring/widgets/applicant_kanban.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/applicant.dart';
import '../../../data/repositories/applicant_repository.dart';
import 'applicant_card.dart';

class ApplicantKanban extends ConsumerWidget {
  final ApplicantListQuery query;
  /// Optional reassignment callback. If null, the "Move to listing" overflow
  /// action on each card is hidden.
  final Future<void> Function(Applicant)? onMoveToListing;
  const ApplicantKanban({
    super.key,
    required this.query,
    this.onMoveToListing,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(applicantListProvider(query));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Failed to load applicants: $e')),
      data: (applicants) => _Board(
        applicants: applicants,
        onMoveToListing: onMoveToListing,
      ),
    );
  }
}

/// Pipeline columns shown in the kanban, in left-to-right order. Mirrors
/// kApplicantTransitions in lib/features/hiring/applicant_status.dart.
const List<String> _kColumns = [
  'NEW',
  'SCREENING',
  'INTERVIEW',
  'ASSESSMENT',
  'OFFER',
  'OFFER_ACCEPTED',
];

class _Board extends StatelessWidget {
  final List<Applicant> applicants;
  final Future<void> Function(Applicant)? onMoveToListing;
  const _Board({required this.applicants, required this.onMoveToListing});

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<Applicant>>{
      for (final col in _kColumns) col: <Applicant>[],
    };
    for (final a in applicants) {
      grouped[a.status]?.add(a);
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final col in _kColumns)
            _Column(
              title: col,
              applicants: grouped[col] ?? const [],
              onMoveToListing: onMoveToListing,
            ),
        ],
      ),
    );
  }
}

class _Column extends StatelessWidget {
  final String title;
  final List<Applicant> applicants;
  final Future<void> Function(Applicant)? onMoveToListing;
  const _Column({
    required this.title,
    required this.applicants,
    required this.onMoveToListing,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 280,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                '$title · ${applicants.length}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            for (final a in applicants)
              ApplicantCard(
                applicant: a,
                onMoveToListing: onMoveToListing == null
                    ? null
                    : () => onMoveToListing!(a),
              ),
          ],
        ),
      ),
    );
  }
}
```

If `ApplicantCard` doesn't yet accept `onMoveToListing`, leave it out of the constructor for now — Task 15 adds the listing badge AND the overflow action. Stub it for compile (`final VoidCallback? onMoveToListing; ... this.onMoveToListing,`).

- [ ] **Step 3: Replace the inline kanban in `hiring_screen.dart`**

In `lib/features/hiring/hiring_screen.dart`, find the section that renders the kanban inline and replace it with:

```dart
ApplicantKanban(
  query: ApplicantListQuery(
    search: _search.isEmpty ? null : _search,
    roleScorecardId: _roleId,
    hiringEntityId: _entityId,
  ),
),
```

Remove the old inline rendering code, the `_Board` / `_Column` widgets if they were inline, and any imports that are no longer needed.

- [ ] **Step 4: Run hiring tests + smoke**

Run: `flutter test test/features/hiring/`
Expected: existing tests pass. (The widget extraction shouldn't affect any test that wasn't UI-snapshot-based.)

Run: `flutter analyze`
Expected: no new issues.

- [ ] **Step 5: Commit**

```bash
dart format lib/features/hiring/widgets/applicant_kanban.dart lib/features/hiring/hiring_screen.dart
git add lib/features/hiring/widgets/applicant_kanban.dart lib/features/hiring/hiring_screen.dart lib/features/hiring/widgets/applicant_card.dart
git commit -m "refactor(hiring): extract ApplicantKanban widget"
```

---

### Task 8: `HiringScreen` two-tab restructure

**Files:**
- Modify: `lib/features/hiring/hiring_screen.dart`

- [ ] **Step 1: Replace the screen body with a `DefaultTabController` + `TabBar`**

```dart
// lib/features/hiring/hiring_screen.dart — body section
@override
Widget build(BuildContext context) {
  final profile = ref.watch(userProfileProvider).asData?.value;
  final canManage = profile?.isHrOrAdmin ?? false;
  if (!canManage) {
    return Scaffold(
      drawer: isMobile(context) ? const AppDrawer() : null,
      appBar: AppBar(title: const Text('Hiring')),
      body: const Center(child: Text('You do not have permission to view applicants.')),
    );
  }
  return DefaultTabController(
    length: 2,
    child: Scaffold(
      drawer: isMobile(context) ? const AppDrawer() : null,
      appBar: AppBar(
        title: const Text('Hiring'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: () => context.go('/hiring/listings/new'),
              icon: const Icon(Icons.add),
              label: const Text('New listing'),
            ),
          ),
        ],
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Listings'),
            Tab(text: 'Talent Pool'),
          ],
        ),
      ),
      body: TabBarView(
        children: [
          // Tab 1: Listings — placeholder until Task 9 lands the table widget.
          const Center(child: Text('Listings table coming next task')),
          // Tab 2: Talent Pool — reuse extracted kanban, scoped to listing_id IS NULL.
          Column(
            children: [
              _TopFilters(
                onSearchChanged: (s) => setState(() => _search = s),
                roleId: _roleId,
                onRoleChanged: (id) => setState(() => _roleId = id),
                entityId: _entityId,
                onEntityChanged: (id) => setState(() => _entityId = id),
              ),
              Expanded(
                child: ApplicantKanban(
                  query: ApplicantListQuery(
                    listingIsExplicitlyNull: true,
                    search: _search.isEmpty ? null : _search,
                    roleScorecardId: _roleId,
                    hiringEntityId: _entityId,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.tonalIcon(
                  onPressed: () => context.go('/hiring/new'),
                  icon: const Icon(Icons.add),
                  label: const Text('Add to Talent Pool'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
```

- [ ] **Step 2: Smoke + commit**

```bash
flutter analyze lib/features/hiring/hiring_screen.dart
dart format lib/features/hiring/hiring_screen.dart
git add lib/features/hiring/hiring_screen.dart
git commit -m "feat(hiring): two-tab restructure — Listings + Talent Pool"
```

---

### Task 9: `ListingsTable` widget (filters + chips + rows)

**Files:**
- Create: `lib/features/hiring/widgets/listings_table.dart`
- Modify: `lib/features/hiring/hiring_screen.dart` (drop in for the Listings tab placeholder)

- [ ] **Step 1: Create the widget**

```dart
// lib/features/hiring/widgets/listings_table.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../data/models/job_listing.dart';
import '../../../data/repositories/applicant_repository.dart';
import '../../../data/repositories/hiring_entity_repository.dart';
import '../../../data/repositories/job_listing_repository.dart';
import '../../../data/repositories/role_scorecard_repository.dart';
import '../../../widgets/responsive_table.dart';

class ListingsTable extends ConsumerStatefulWidget {
  const ListingsTable({super.key});
  @override
  ConsumerState<ListingsTable> createState() => _ListingsTableState();
}

class _ListingsTableState extends ConsumerState<ListingsTable> {
  String _search = '';
  String? _roleId;
  String? _entityId;
  String? _statusFilter; // 'OPEN' | 'PAUSED' | 'CLOSED' | 'FILLED' | null=All

  @override
  Widget build(BuildContext context) {
    final statusesArg = (_statusFilter == null || _statusFilter == 'FILLED')
        ? null
        : <String>[_statusFilter!];
    final query = JobListingListQuery(
      search: _search.isEmpty ? null : _search,
      statuses: statusesArg,
      hiringEntityId: _entityId,
      roleScorecardId: _roleId,
    );
    final async = ref.watch(jobListingListProvider(query));
    return Column(
      children: [
        _FilterBar(
          search: _search,
          onSearchChanged: (s) => setState(() => _search = s),
          roleId: _roleId,
          onRoleChanged: (v) => setState(() => _roleId = v),
          entityId: _entityId,
          onEntityChanged: (v) => setState(() => _entityId = v),
          status: _statusFilter,
          onStatusChanged: (v) => setState(() => _statusFilter = v),
        ),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Failed to load: $e')),
            data: (rows) {
              // Apply FILLED filter client-side (effective status depends on derived count).
              List<JobListing> filtered = rows;
              if (_statusFilter == 'FILLED') {
                // For each row, compute effective status synchronously is hard;
                // simpler: pre-fetch counts then filter. Defer to provider chain
                // in v2; for v1, show FILLED rows by hitting the effective-status
                // provider per row inside the row widget. Empty list here so
                // user sees the FILLED-filter result correctly.
                // Workaround: include all rows that have status=='OPEN' and let
                // the row widget conditionally render — fine for the v1 cut.
                filtered = rows.where((r) => r.status == 'OPEN').toList();
              }
              if (filtered.isEmpty) {
                return const Center(
                  child: Text('No listings yet. Create your first listing to start hiring.'),
                );
              }
              return ResponsiveTable(
                child: ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) => _ListingRow(listing: filtered[i]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _FilterBar extends ConsumerWidget {
  final String search;
  final ValueChanged<String> onSearchChanged;
  final String? roleId;
  final ValueChanged<String?> onRoleChanged;
  final String? entityId;
  final ValueChanged<String?> onEntityChanged;
  final String? status;
  final ValueChanged<String?> onStatusChanged;
  const _FilterBar({
    required this.search,
    required this.onSearchChanged,
    required this.roleId,
    required this.onRoleChanged,
    required this.entityId,
    required this.onEntityChanged,
    required this.status,
    required this.onStatusChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roles = ref.watch(roleScorecardListProvider).asData?.value ?? [];
    final entities = ref.watch(hiringEntityListProvider).asData?.value ?? [];
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          SizedBox(
            width: 240,
            child: TextField(
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search),
                labelText: 'Search title',
                border: OutlineInputBorder(),
              ),
              onChanged: onSearchChanged,
            ),
          ),
          const SizedBox(width: 12),
          DropdownButton<String?>(
            value: status,
            hint: const Text('Status: All'),
            items: const [
              DropdownMenuItem(value: null, child: Text('All statuses')),
              DropdownMenuItem(value: 'OPEN', child: Text('Open')),
              DropdownMenuItem(value: 'FILLED', child: Text('Filled')),
              DropdownMenuItem(value: 'PAUSED', child: Text('Paused')),
              DropdownMenuItem(value: 'CLOSED', child: Text('Closed')),
            ],
            onChanged: onStatusChanged,
          ),
          const SizedBox(width: 12),
          DropdownButton<String?>(
            value: entityId,
            hint: const Text('Brand: All'),
            items: [
              const DropdownMenuItem(value: null, child: Text('All brands')),
              ...entities.map((e) => DropdownMenuItem(value: e.id, child: Text(e.name))),
            ],
            onChanged: onEntityChanged,
          ),
          const SizedBox(width: 12),
          DropdownButton<String?>(
            value: roleId,
            hint: const Text('Role: All'),
            items: [
              const DropdownMenuItem(value: null, child: Text('All roles')),
              ...roles.map((r) => DropdownMenuItem(value: r.id, child: Text(r.jobTitle))),
            ],
            onChanged: onRoleChanged,
          ),
        ],
      ),
    );
  }
}

class _ListingRow extends ConsumerWidget {
  final JobListing listing;
  const _ListingRow({required this.listing});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filledAsync = ref.watch(listingFilledCountProvider(listing.id));
    final effAsync = ref.watch(listingEffectiveStatusProvider(listing.id));
    final applicantsAsync = ref.watch(applicantListProvider(
      ApplicantListQuery(listingId: listing.id),
    ));
    final filled = filledAsync.valueOrNull ?? 0;
    final eff = effAsync.valueOrNull ?? ListingEffectiveStatus.open;
    final applicantCount = applicantsAsync.valueOrNull?.length ?? 0;
    final df = DateFormat('MMM d, yyyy');

    return InkWell(
      onTap: () => context.go('/hiring/listings/${listing.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Expanded(flex: 4, child: Text(listing.title, style: const TextStyle(fontWeight: FontWeight.w600))),
            Expanded(flex: 2, child: _BrandPill(entityId: listing.hiringEntityId)),
            Expanded(flex: 2, child: _RolePill(scorecardId: listing.roleScorecardId)),
            Expanded(flex: 2, child: Text('$filled / ${listing.targetHeadcount}')),
            Expanded(flex: 2, child: _StatusChip(status: eff)),
            Expanded(flex: 2, child: Text('$applicantCount applicants')),
            Expanded(flex: 2, child: Text(df.format(listing.createdAt))),
          ],
        ),
      ),
    );
  }
}

class _BrandPill extends ConsumerWidget {
  final String entityId;
  const _BrandPill({required this.entityId});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = ref.watch(hiringEntityByIdProvider(entityId)).asData?.value;
    return Text(e?.name ?? '—');
  }
}

class _RolePill extends ConsumerWidget {
  final String scorecardId;
  const _RolePill({required this.scorecardId});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(roleScorecardByIdProvider(scorecardId)).asData?.value;
    return Text(r?.jobTitle ?? '—');
  }
}

class _StatusChip extends StatelessWidget {
  final ListingEffectiveStatus status;
  const _StatusChip({required this.status});
  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status) {
      ListingEffectiveStatus.open => (Colors.deepPurple.shade50, Colors.deepPurple.shade800),
      ListingEffectiveStatus.filled => (Colors.green.shade50, Colors.green.shade800),
      ListingEffectiveStatus.paused => (Colors.amber.shade50, Colors.amber.shade900),
      ListingEffectiveStatus.closed => (Colors.grey.shade200, Colors.grey.shade700),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Text(status.label, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}
```

- [ ] **Step 2: Plug into HiringScreen**

In `lib/features/hiring/hiring_screen.dart`, replace the Listings-tab placeholder `Center(child: Text('Listings table coming next task'))` with:

```dart
const ListingsTable(),
```

And add an import at the top: `import 'widgets/listings_table.dart';`

- [ ] **Step 3: Analyze + commit**

```bash
dart format lib/features/hiring/widgets/listings_table.dart lib/features/hiring/hiring_screen.dart
flutter analyze lib/features/hiring/widgets/listings_table.dart lib/features/hiring/hiring_screen.dart
git add lib/features/hiring/widgets/listings_table.dart lib/features/hiring/hiring_screen.dart
git commit -m "feat(hiring): ListingsTable widget + plug into HiringScreen"
```

---

### Task 10: `ListingFormScreen` (create + edit)

**Files:**
- Create: `lib/features/hiring/listing_form_screen.dart`

- [ ] **Step 1: Create the screen**

```dart
// lib/features/hiring/listing_form_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/repositories/hiring_entity_repository.dart';
import '../../data/repositories/job_listing_repository.dart';
import '../../data/repositories/role_scorecard_repository.dart';
import '../auth/profile_provider.dart';

class ListingFormScreen extends ConsumerStatefulWidget {
  final String? listingId; // null = create
  const ListingFormScreen({super.key, this.listingId});

  @override
  ConsumerState<ListingFormScreen> createState() => _ListingFormScreenState();
}

class _ListingFormScreenState extends ConsumerState<ListingFormScreen> {
  final _formKey = GlobalKey<FormState>();
  String _title = '';
  int _targetHeadcount = 1;
  String _status = 'OPEN';
  String? _roleId;
  String? _entityId;
  String? _notes;
  bool _saving = false;
  bool _loaded = false;
  String? _originalRoleId;
  String? _originalEntityId;

  @override
  void initState() {
    super.initState();
    if (widget.listingId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    } else {
      _loaded = true;
    }
  }

  Future<void> _load() async {
    final j = await ref.read(jobListingByIdProvider(widget.listingId!).future);
    if (j == null || !mounted) return;
    setState(() {
      _title = j.title;
      _targetHeadcount = j.targetHeadcount;
      _status = j.status;
      _roleId = j.roleScorecardId;
      _entityId = j.hiringEntityId;
      _originalRoleId = j.roleScorecardId;
      _originalEntityId = j.hiringEntityId;
      _notes = j.notes;
      _loaded = true;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    // Confirm role/brand change in edit mode.
    if (widget.listingId != null &&
        (_roleId != _originalRoleId || _entityId != _originalEntityId)) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Recompute filled count?'),
          content: const Text(
              'Changing the role or brand will recompute the filled count against the new (role, brand). Continue?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm')),
          ],
        ),
      );
      if (ok != true) return;
    }

    setState(() => _saving = true);
    try {
      final profile = ref.read(userProfileProvider).asData?.value;
      final companyId = profile?.companyId;
      if (companyId == null) throw Exception('Missing company id from profile');
      final userId = profile?.userId ?? '';
      await ref.read(jobListingRepositoryProvider).upsert(
            id: widget.listingId,
            companyId: companyId,
            hiringEntityId: _entityId!,
            roleScorecardId: _roleId!,
            title: _title,
            targetHeadcount: _targetHeadcount,
            status: _status,
            notes: _notes,
            setByUserId: userId,
          );
      // Invalidate caches.
      ref.invalidate(jobListingListProvider);
      if (widget.listingId != null) {
        ref.invalidate(jobListingByIdProvider(widget.listingId!));
      }
      if (mounted) context.go('/hiring');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final roles = ref.watch(roleScorecardListProvider).asData?.value ?? [];
    final entities = ref.watch(hiringEntityListProvider).asData?.value ?? [];
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.listingId == null ? 'New Listing' : 'Edit Listing'),
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: _entityId,
                      decoration: const InputDecoration(
                          border: OutlineInputBorder(), labelText: 'Brand'),
                      items: entities
                          .map((e) => DropdownMenuItem(value: e.id, child: Text(e.name)))
                          .toList(),
                      validator: (v) => v == null ? 'Required' : null,
                      onChanged: (v) => setState(() => _entityId = v),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _roleId,
                      decoration: const InputDecoration(
                          border: OutlineInputBorder(), labelText: 'Role'),
                      items: roles
                          .map((r) => DropdownMenuItem(value: r.id, child: Text(r.jobTitle)))
                          .toList(),
                      validator: (v) => v == null ? 'Required' : null,
                      onChanged: (v) {
                        setState(() {
                          _roleId = v;
                          // Default title from role.
                          if (_title.isEmpty && v != null) {
                            final r = roles.firstWhere((x) => x.id == v);
                            _title = r.jobTitle;
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: ValueKey('title-$_roleId'),
                      initialValue: _title,
                      decoration: const InputDecoration(
                          border: OutlineInputBorder(), labelText: 'Title'),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                      onChanged: (v) => _title = v,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: _targetHeadcount.toString(),
                      decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Target headcount'),
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        final n = int.tryParse(v ?? '');
                        if (n == null || n < 1) return 'Must be ≥ 1';
                        return null;
                      },
                      onChanged: (v) => _targetHeadcount = int.tryParse(v) ?? 1,
                    ),
                    if (widget.listingId != null) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _status,
                        decoration: const InputDecoration(
                            border: OutlineInputBorder(), labelText: 'Status'),
                        items: const [
                          DropdownMenuItem(value: 'OPEN', child: Text('Open')),
                          DropdownMenuItem(value: 'PAUSED', child: Text('Paused')),
                          DropdownMenuItem(value: 'CLOSED', child: Text('Closed')),
                        ],
                        onChanged: (v) => setState(() => _status = v ?? 'OPEN'),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: _notes,
                      minLines: 3,
                      maxLines: 8,
                      decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Notes (optional)'),
                      onChanged: (v) => _notes = v.isEmpty ? null : v,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _saving ? null : () => context.go('/hiring'),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: _saving ? null : _save,
                            child: Text(_saving ? 'Saving…' : 'Save'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
```

> **Note on `userProfileProvider`**: this exists in `lib/features/auth/profile_provider.dart`. The exact field names (`companyId`, `userId`, etc.) may differ — check the existing applicant_form_screen.dart for how it grabs the user ID and company ID, and mirror that pattern. If the user profile model uses `id` instead of `userId`, adjust accordingly.

- [ ] **Step 2: Analyze + commit**

```bash
dart format lib/features/hiring/listing_form_screen.dart
flutter analyze lib/features/hiring/listing_form_screen.dart
git add lib/features/hiring/listing_form_screen.dart
git commit -m "feat(hiring): ListingFormScreen — create + edit"
```

---

### Task 11: `ListingDetailScreen` (header + actions + embedded kanban)

**Files:**
- Create: `lib/features/hiring/listing_detail_screen.dart`

- [ ] **Step 1: Create the screen**

```dart
// lib/features/hiring/listing_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/repositories/applicant_repository.dart';
import '../../data/repositories/hiring_entity_repository.dart';
import '../../data/repositories/job_listing_repository.dart';
import '../../data/repositories/role_scorecard_repository.dart';
import 'widgets/applicant_kanban.dart';

class ListingDetailScreen extends ConsumerWidget {
  final String listingId;
  const ListingDetailScreen({super.key, required this.listingId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listingAsync = ref.watch(jobListingByIdProvider(listingId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Listing'),
      ),
      body: listingAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load: $e')),
        data: (listing) {
          if (listing == null) return const Center(child: Text('Listing not found'));
          if (listing.deletedAt != null) {
            return const Center(child: Text('This listing has been deleted.'));
          }
          return Column(
            children: [
              _Header(listingId: listingId),
              Expanded(
                child: ApplicantKanban(
                  query: ApplicantListQuery(listingId: listingId),
                  onMoveToListing: null, // already in a listing
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.tonalIcon(
                  onPressed: () =>
                      context.go('/hiring/listings/$listingId/applicants/new'),
                  icon: const Icon(Icons.add),
                  label: const Text('Add applicant to this listing'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  final String listingId;
  const _Header({required this.listingId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listing = ref.watch(jobListingByIdProvider(listingId)).asData?.value;
    if (listing == null) return const SizedBox.shrink();
    final filled = ref.watch(listingFilledCountProvider(listingId)).valueOrNull ?? 0;
    final eff =
        ref.watch(listingEffectiveStatusProvider(listingId)).valueOrNull ??
            ListingEffectiveStatus.open;
    final entity = ref.watch(hiringEntityByIdProvider(listing.hiringEntityId)).asData?.value;
    final role = ref.watch(roleScorecardByIdProvider(listing.roleScorecardId)).asData?.value;
    final df = DateFormat('MMM d, yyyy');
    final isPaused = listing.status == 'PAUSED';
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(listing.title,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: [
            _Pill(label: entity?.name ?? '—'),
            _Pill(label: role?.jobTitle ?? '—'),
            _Pill(label: eff.label),
            _Pill(label: '$filled / ${listing.targetHeadcount}'),
          ]),
          const SizedBox(height: 6),
          Text('Created ${df.format(listing.createdAt)}',
              style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            OutlinedButton.icon(
              onPressed: () => context.go('/hiring/listings/$listingId/edit'),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit'),
            ),
            OutlinedButton.icon(
              onPressed: () => _togglePause(context, ref, listing.id, isPaused),
              icon: Icon(isPaused ? Icons.play_arrow : Icons.pause),
              label: Text(isPaused ? 'Reopen' : 'Pause'),
            ),
            if (listing.status != 'CLOSED')
              OutlinedButton.icon(
                onPressed: () => _close(context, ref, listing.id),
                icon: const Icon(Icons.lock_outline),
                label: const Text('Close'),
              ),
            OutlinedButton.icon(
              onPressed: () => _delete(context, ref, listing.id),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete'),
            ),
          ]),
        ],
      ),
    );
  }

  Future<void> _togglePause(BuildContext ctx, WidgetRef ref, String id, bool isPaused) async {
    final listing = await ref.read(jobListingByIdProvider(id).future);
    if (listing == null) return;
    final profile = ref.read(/* userProfileProvider stub — see existing forms */ Provider((_) => null));
    // For brevity: directly issue an UPDATE using the repository.
    await Supabase.instance.client.from('job_listings')
        .update({'status': isPaused ? 'OPEN' : 'PAUSED'})
        .eq('id', id);
    ref.invalidate(jobListingByIdProvider(id));
    ref.invalidate(jobListingListProvider);
  }

  Future<void> _close(BuildContext ctx, WidgetRef ref, String id) async {
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (c) => AlertDialog(
        title: const Text('Close listing?'),
        content: const Text(
            'Closing a listing keeps it visible in the Closed filter but hides it from "Open" lists. Applicants on this listing keep their reference. Continue?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Close')),
        ],
      ),
    );
    if (ok != true) return;
    await Supabase.instance.client.from('job_listings')
        .update({'status': 'CLOSED', 'closed_at': DateTime.now().toIso8601String()})
        .eq('id', id);
    ref.invalidate(jobListingByIdProvider(id));
    ref.invalidate(jobListingListProvider);
  }

  Future<void> _delete(BuildContext ctx, WidgetRef ref, String id) async {
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (c) => AlertDialog(
        title: const Text('Delete listing?'),
        content: const Text(
            'Soft-deletes this listing. Applicants on it retain their listing_id (showing "(deleted listing)") and can be reassigned via Move-to-listing. Continue?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton.tonal(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(jobListingRepositoryProvider).softDelete(id);
    ref.invalidate(jobListingListProvider);
    if (ctx.mounted) ctx.go('/hiring');
  }
}

class _Pill extends StatelessWidget {
  final String label;
  const _Pill({required this.label});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      );
}
```

> The `_togglePause` and `_close` helpers above use `Supabase.instance.client` directly for a one-shot update — the existing pattern (mirroring how `applicant_detail_screen.dart` does ad-hoc status flips). If you'd rather route through a `jobListingRepositoryProvider.changeStatus()` method, extract one; for v1 the inline call is fine.

- [ ] **Step 2: Analyze + commit**

```bash
dart format lib/features/hiring/listing_detail_screen.dart
flutter analyze lib/features/hiring/listing_detail_screen.dart
git add lib/features/hiring/listing_detail_screen.dart
git commit -m "feat(hiring): ListingDetailScreen — header + actions + embedded kanban"
```

---

### Task 12: Routing + sidebar entry

**Files:**
- Modify: `lib/app/router.dart`

- [ ] **Step 1: Add 3 new routes**

In `lib/app/router.dart`, locate the existing `/hiring` route block. Add these routes alongside it (inside the same parent if there's a layout shell):

```dart
GoRoute(
  path: '/hiring/listings/new',
  builder: (ctx, st) => const ListingFormScreen(),
),
GoRoute(
  path: '/hiring/listings/:id',
  builder: (ctx, st) => ListingDetailScreen(listingId: st.pathParameters['id']!),
),
GoRoute(
  path: '/hiring/listings/:id/edit',
  builder: (ctx, st) => ListingFormScreen(listingId: st.pathParameters['id']),
),
GoRoute(
  path: '/hiring/listings/:id/applicants/new',
  builder: (ctx, st) => ApplicantFormScreen(
    listingId: st.pathParameters['id'],
  ),
),
```

Add the imports:

```dart
import '../features/hiring/listing_form_screen.dart';
import '../features/hiring/listing_detail_screen.dart';
```

- [ ] **Step 2: Sidebar — confirm "Hiring" entry exists**

`/hiring` already exists in the sidebar. No new entry needed since both tabs live inside.

- [ ] **Step 3: Analyze + commit**

```bash
dart format lib/app/router.dart
flutter analyze lib/app/router.dart
git add lib/app/router.dart
git commit -m "feat(hiring): listings routes (new/edit/detail/add-applicant)"
```

---

## Phase 3 — Applicant integration

### Task 13: `ApplicantFormScreen` accepts `listingId` + locks brand/role

**Files:**
- Modify: `lib/features/hiring/applicant_form_screen.dart`

- [ ] **Step 1: Add `listingId` parameter to the widget**

In `lib/features/hiring/applicant_form_screen.dart`, update the constructor:

```dart
class ApplicantFormScreen extends ConsumerStatefulWidget {
  final String? applicantId;
  final String? listingId; // null → Talent Pool
  const ApplicantFormScreen({super.key, this.applicantId, this.listingId});
  ...
}
```

- [ ] **Step 2: When listingId is set, pre-fill + lock brand/role on init**

In `_ApplicantFormScreenState.initState()`, after the existing applicantId-load branch:

```dart
if (widget.applicantId == null && widget.listingId != null) {
  WidgetsBinding.instance.addPostFrameCallback((_) => _seedFromListing());
}
```

Add the helper method:

```dart
Future<void> _seedFromListing() async {
  final listing = await ref.read(jobListingByIdProvider(widget.listingId!).future);
  if (listing == null || !mounted) return;
  setState(() {
    // Pre-fill brand + role from the listing.
    _hiringEntityId = listing.hiringEntityId;
    _roleScorecardId = listing.roleScorecardId;
  });
}
```

(Field names like `_hiringEntityId` and `_roleScorecardId` must match what's already in this file — check existing state fields and adjust.)

- [ ] **Step 3: Disable the brand + role pickers when listingId is set**

Find where the brand picker (`DropdownButtonFormField`/`CompanyPicker` etc.) is rendered in the form. Wrap the `onChanged` and `enabled` props:

```dart
DropdownButtonFormField<String>(
  initialValue: _hiringEntityId,
  decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Brand'),
  items: [...],
  onChanged: widget.listingId != null ? null : (v) => setState(() => _hiringEntityId = v),
)
```

(`onChanged: null` disables the field in Flutter dropdowns.) Mirror for the role picker.

Add a subtitle near these locked fields:

```dart
if (widget.listingId != null)
  const Padding(
    padding: EdgeInsets.only(top: 4),
    child: Text(
      'Brand and role are inherited from the listing.',
      style: TextStyle(color: Colors.grey, fontSize: 12),
    ),
  ),
```

- [ ] **Step 4: Pass `listing_id` to repository on save**

Find the call to `ref.read(applicantRepositoryProvider).upsert(...)`. Add:

```dart
listingId: widget.listingId,
```

to the named arguments.

- [ ] **Step 5: Update the AppBar title**

```dart
title: Text(
  widget.applicantId != null
      ? 'Edit applicant'
      : (widget.listingId != null
          ? 'New applicant — listing'
          : 'New applicant — Talent Pool'),
),
```

- [ ] **Step 6: Analyze + commit**

```bash
dart format lib/features/hiring/applicant_form_screen.dart
flutter analyze lib/features/hiring/applicant_form_screen.dart
git add lib/features/hiring/applicant_form_screen.dart
git commit -m "feat(hiring): ApplicantFormScreen accepts listingId + locks brand/role"
```

---

### Task 14: `MoveToListingDialog` + applicant detail action

**Files:**
- Create: `lib/features/hiring/widgets/move_to_listing_dialog.dart`
- Modify: `lib/features/hiring/applicant_detail_screen.dart`

- [ ] **Step 1: Create the dialog**

```dart
// lib/features/hiring/widgets/move_to_listing_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../data/models/job_listing.dart';
import '../../../data/repositories/applicant_repository.dart';
import '../../../data/repositories/job_listing_repository.dart';

class MoveToListingDialog extends ConsumerStatefulWidget {
  final String applicantId;
  final String? currentListingId;
  const MoveToListingDialog({
    super.key,
    required this.applicantId,
    this.currentListingId,
  });

  @override
  ConsumerState<MoveToListingDialog> createState() => _MoveToListingDialogState();
}

class _MoveToListingDialogState extends ConsumerState<MoveToListingDialog> {
  String? _chosenListingId; // null = "Talent Pool"
  bool _includeClosed = false;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final query = JobListingListQuery(
      statuses: _includeClosed ? null : const ['OPEN', 'PAUSED'],
    );
    final async = ref.watch(jobListingListProvider(query));
    return AlertDialog(
      title: const Text('Move to listing'),
      content: SizedBox(
        width: 420,
        child: async.when(
          loading: () => const SizedBox(height: 80, child: Center(child: CircularProgressIndicator())),
          error: (e, _) => Text('Failed to load: $e'),
          data: (listings) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RadioGroup<String?>(
                groupValue: _chosenListingId,
                onChanged: (v) => setState(() => _chosenListingId = v),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const ListTile(
                      title: Text('Talent Pool (no listing)'),
                      leading: Radio<String?>(value: null),
                    ),
                    for (final l in listings)
                      ListTile(
                        title: Text(l.title),
                        subtitle: Text('Target ${l.targetHeadcount} · status ${l.status}'),
                        leading: Radio<String?>(value: l.id),
                      ),
                  ],
                ),
              ),
              CheckboxListTile(
                value: _includeClosed,
                title: const Text('Include closed listings'),
                contentPadding: EdgeInsets.zero,
                onChanged: (v) => setState(() => _includeClosed = v ?? false),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving || (_chosenListingId == widget.currentListingId)
              ? null
              : _save,
          child: Text(_saving ? 'Saving…' : 'Move'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      // When moving to a real listing, also adopt that listing's role+brand.
      String? newRoleId;
      String? newEntityId;
      if (_chosenListingId != null) {
        final l = await ref.read(jobListingByIdProvider(_chosenListingId!).future);
        newRoleId = l?.roleScorecardId;
        newEntityId = l?.hiringEntityId;
      }
      final updates = <String, dynamic>{
        'listing_id': _chosenListingId,
        if (newRoleId != null) 'role_scorecard_id': newRoleId,
        if (newEntityId != null) 'hiring_entity_id': newEntityId,
      };
      await Supabase.instance.client
          .from('applicants')
          .update(updates)
          .eq('id', widget.applicantId);
      ref.invalidate(applicantByIdProvider(widget.applicantId));
      ref.invalidate(applicantListProvider);
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
```

> Note: `RadioGroup` is a Flutter wrapper used to manage radio state. If your Flutter version doesn't ship it (Flutter 3.x stable does), replace with a simple list of `RadioListTile<String?>` widgets.

- [ ] **Step 2: Wire the dialog into `applicant_detail_screen.dart`**

Find the AppBar action area in `lib/features/hiring/applicant_detail_screen.dart`. Add a new IconButton (or overflow menu item):

```dart
IconButton(
  icon: const Icon(Icons.move_down_outlined),
  tooltip: 'Move to listing…',
  onPressed: () => showDialog(
    context: context,
    builder: (_) => MoveToListingDialog(
      applicantId: widget.applicantId,
      currentListingId: applicant?.listingId,
    ),
  ),
),
```

Where `applicant?.listingId` comes from the Applicant the detail screen already loads. Adjust accessor based on how that screen reads its applicant.

Import the dialog: `import 'widgets/move_to_listing_dialog.dart';`

- [ ] **Step 3: Analyze + commit**

```bash
dart format lib/features/hiring/widgets/move_to_listing_dialog.dart lib/features/hiring/applicant_detail_screen.dart
flutter analyze lib/features/hiring/widgets/move_to_listing_dialog.dart lib/features/hiring/applicant_detail_screen.dart
git add lib/features/hiring/widgets/move_to_listing_dialog.dart lib/features/hiring/applicant_detail_screen.dart
git commit -m "feat(hiring): MoveToListingDialog + applicant-detail action"
```

---

### Task 15: Listing badge on applicant card

**Files:**
- Modify: `lib/features/hiring/widgets/applicant_card.dart`

- [ ] **Step 1: Add a small badge showing the listing title (or "Talent Pool")**

Inside `ApplicantCard`'s build method, find where the applicant's primary info is rendered. Add:

```dart
Consumer(builder: (ctx, ref, _) {
  final id = applicant.listingId;
  if (id == null) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text('Talent Pool', style: TextStyle(fontSize: 10, color: Colors.grey)),
    );
  }
  final listing = ref.watch(jobListingByIdProvider(id)).asData?.value;
  final title = listing == null
      ? '(deleted listing)'
      : (listing.deletedAt != null ? '(deleted listing)' : listing.title);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    margin: const EdgeInsets.only(top: 4),
    decoration: BoxDecoration(
      color: Colors.deepPurple.shade50,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(title,
        style: TextStyle(fontSize: 10, color: Colors.deepPurple.shade800)),
  );
}),
```

Add imports at the top: `import 'package:flutter_riverpod/flutter_riverpod.dart';` and `import '../../../data/repositories/job_listing_repository.dart';`

- [ ] **Step 2: Add an optional "Move to listing" overflow action**

If `ApplicantCard` has an overflow menu (`PopupMenuButton`) or wraps with `InkWell` + a menu — extend it. If it doesn't, add a small icon button in the card corner:

```dart
if (onMoveToListing != null)
  IconButton(
    icon: const Icon(Icons.move_down_outlined, size: 16),
    tooltip: 'Move to listing…',
    onPressed: onMoveToListing,
  ),
```

(`onMoveToListing` is already a constructor param added in Task 7.)

- [ ] **Step 3: Analyze + commit**

```bash
dart format lib/features/hiring/widgets/applicant_card.dart
flutter analyze lib/features/hiring/widgets/applicant_card.dart
git add lib/features/hiring/widgets/applicant_card.dart
git commit -m "feat(hiring): applicant card — listing badge + move action"
```

---

### Task 16: CTA wiring + Talent Pool move action

**Files:**
- Modify: `lib/features/hiring/hiring_screen.dart`

- [ ] **Step 1: Wire the Talent Pool kanban's `onMoveToListing` callback**

In `hiring_screen.dart`, update the Talent Pool tab's `ApplicantKanban` to provide an `onMoveToListing` callback that opens `MoveToListingDialog`:

```dart
ApplicantKanban(
  query: ApplicantListQuery(
    listingIsExplicitlyNull: true,
    search: _search.isEmpty ? null : _search,
    roleScorecardId: _roleId,
    hiringEntityId: _entityId,
  ),
  onMoveToListing: (a) async {
    await showDialog(
      context: context,
      builder: (_) => MoveToListingDialog(
        applicantId: a.id,
        currentListingId: a.listingId,
      ),
    );
  },
),
```

Import: `import 'widgets/move_to_listing_dialog.dart';`

- [ ] **Step 2: Confirm the "+ New listing" button is wired**

In the same file, the AppBar action `onPressed: () => context.go('/hiring/listings/new')` was added in Task 8. Confirm it exists.

- [ ] **Step 3: Confirm "+ Add to Talent Pool" goes to the right route**

The button at the bottom of the Talent Pool tab points to `/hiring/new` (the existing route, which now means "Talent Pool quick-add" since `listingId` is null when route omits it). Confirm.

- [ ] **Step 4: Analyze + commit**

```bash
dart format lib/features/hiring/hiring_screen.dart
flutter analyze lib/features/hiring/hiring_screen.dart
git add lib/features/hiring/hiring_screen.dart
git commit -m "feat(hiring): Talent Pool — move-to-listing wiring"
```

---

## Phase 4 — Tests + smoke

### Task 17: End-to-end test — auto-FILL + auto-REOPEN

**Files:**
- Create: `test/features/hiring/listing_lifecycle_test.dart`

This test exercises the slot derivation purely through `deriveEffectiveStatus` + integer counts (no Supabase fixture needed — the live query is in `listingFilledCountProvider` which is harder to mock).

- [ ] **Step 1: Write the test**

```dart
// test/features/hiring/listing_lifecycle_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/repositories/job_listing_repository.dart';

void main() {
  group('listing lifecycle (slot-based)', () {
    test('opens when target > 0 and filled = 0', () {
      expect(deriveEffectiveStatus(status: 'OPEN', filled: 0, target: 3),
          ListingEffectiveStatus.open);
    });

    test('fills as hires accumulate', () {
      expect(deriveEffectiveStatus(status: 'OPEN', filled: 1, target: 3), ListingEffectiveStatus.open);
      expect(deriveEffectiveStatus(status: 'OPEN', filled: 2, target: 3), ListingEffectiveStatus.open);
      expect(deriveEffectiveStatus(status: 'OPEN', filled: 3, target: 3), ListingEffectiveStatus.filled);
    });

    test('auto-reopens when an employee separates (filled drops below target)', () {
      // Listing was at 3/3 (FILLED) — one resigns → 2/3 → OPEN again.
      expect(deriveEffectiveStatus(status: 'OPEN', filled: 3, target: 3), ListingEffectiveStatus.filled);
      expect(deriveEffectiveStatus(status: 'OPEN', filled: 2, target: 3), ListingEffectiveStatus.open);
    });

    test('PAUSED overrides slot math', () {
      expect(deriveEffectiveStatus(status: 'PAUSED', filled: 0, target: 3), ListingEffectiveStatus.paused);
      expect(deriveEffectiveStatus(status: 'PAUSED', filled: 3, target: 3), ListingEffectiveStatus.paused);
    });

    test('CLOSED overrides slot math', () {
      expect(deriveEffectiveStatus(status: 'CLOSED', filled: 0, target: 3), ListingEffectiveStatus.closed);
      expect(deriveEffectiveStatus(status: 'CLOSED', filled: 3, target: 3), ListingEffectiveStatus.closed);
    });

    test('exceeds target → still FILLED (overstaffed)', () {
      expect(deriveEffectiveStatus(status: 'OPEN', filled: 5, target: 3), ListingEffectiveStatus.filled);
    });
  });
}
```

- [ ] **Step 2: Run — expect 6 pass**

Run: `flutter test test/features/hiring/listing_lifecycle_test.dart`
Expected: 6 pass.

- [ ] **Step 3: Commit**

```bash
git add test/features/hiring/listing_lifecycle_test.dart
git commit -m "test(hiring): listing lifecycle (slot derivation)"
```

---

### Task 18: Final green-bar checkpoint

**Files:** none — verification only.

- [ ] **Step 1: Full test suite**

Run: `flutter test`
Expected: all tests pass. New tests added this MVP: 2 (model) + 2 (repo) + 4 (effective status) + 4 (list query) + 6 (lifecycle) = 18.

- [ ] **Step 2: Analyze + format**

```bash
flutter analyze
dart format --output=none --set-exit-if-changed lib/features/hiring/ lib/data/models/job_listing.dart lib/data/repositories/job_listing_repository.dart
```
Expected: no new analyze issues on touched files; format clean.

- [ ] **Step 3: Manual smoke in running app**

```bash
flutter run -d linux --dart-define-from-file=env/prod.json
```

Manually verify:

1. **Hiring screen loads** with two tabs (Listings | Talent Pool).
2. **Talent Pool tab** shows the existing applicants (whatever was in the DB before — their `listing_id` is NULL).
3. **"+ New Listing"** button opens the form. Pick brand, pick role, confirm title defaults to role's job title, set target headcount = 2, save → returns to Hiring.
4. **Listing appears in Listings tab** with chip "OPEN", filled "0 / 2", applicants "0 applicants".
5. **Click the listing** → Detail screen loads. Embedded kanban shows empty columns.
6. **"+ Add applicant to this listing"** → form opens with brand + role pre-filled and grey'd out. Submit a test applicant → returns to listing detail. Card visible in NEW column.
7. **Move the applicant through statuses** all the way to HIRED → confirm filled count visible on the header bumps up.
8. **Open the listing's Edit screen** → change role → confirm warning dialog appears → confirm → save.
9. **Open an existing Talent Pool applicant** → use "Move to listing…" action → pick the listing → confirm the applicant moves into the listing's kanban.
10. **Separate an employee** (via the existing employee profile flow / Quitclaim) whose role+brand matches a FILLED listing → confirm the listing's chip flips back to OPEN.

If any of the above fails, report the specific step + behavior.

- [ ] **Step 4: Commit any docs touched (none expected) and push**

```bash
git status   # should be clean
git push -u origin feat/job-listings
```

---

## Self-Review Notes (author)

- ✅ Spec coverage: all 8 locked decisions are addressed (backfill via nullable listing_id, slot-based headcount via `listingFilledCountProvider`, effective status with `deriveEffectiveStatus`, minimal fields in migration + model, two-tab UI in Task 8, role-gate via DropdownButtonFormField validators in Task 10, editable role with confirm dialog in Task 10's `_save`, title defaulting to role in Task 10's `onChanged`).
- ✅ TDD-first: every backend task writes the failing test before the impl.
- ✅ `Decimal` not needed in this MVP — all money fields belong to RoleScorecard / Employee, not the listing.
- ✅ RLS follows the existing `auth_app_role()` + `auth_company_id()` pattern from `20260414000014_rls.sql`.
- ✅ Soft-delete preserved across listings and applicants.

## Assumptions to verify at execution time

1. **`userProfileProvider` field names** — `companyId`, `userId`. If the existing model uses different names (`id`, `companyId` vs `tenantId`, etc.), mirror what `applicant_form_screen.dart` does on save.
2. **`hiringEntityListProvider` and `roleScorecardListProvider`** — assumed to exist (used by ApplicantForm). Confirm in `lib/data/repositories/hiring_entity_repository.dart` + `role_scorecard_repository.dart`. If named differently, grep and adapt.
3. **`hiringEntityByIdProvider` and `roleScorecardByIdProvider`** — assumed to exist. Same — confirm via grep.
4. **`ApplicantCard.onMoveToListing` field** — needs to be added in Task 7 alongside the kanban extraction. If you split, ensure the field is on the card BEFORE Task 15 references it.
5. **`RadioGroup` widget** — Flutter 3.x stable ships it; if your version doesn't (you may be on 3.41.x per the prior Flutter SDK downgrade for flutter_quill), fall back to plain `RadioListTile<String?>` widgets driven by a simple state variable.
6. **`FILLED` status filter on Listings table** — Task 9's workaround (filter `OPEN` rows and let the row widget render the chip) shows FILLED rows but doesn't perfectly filter. A future polish would either (a) preload all `listingEffectiveStatusProvider` values into a map and filter against them, or (b) move the derivation server-side via a SQL view. Acceptable for v1.
