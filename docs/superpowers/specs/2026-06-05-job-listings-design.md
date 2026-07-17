# Job Listings — Hiring Workflow Restructure

**Date:** 2026-06-05
**Status:** Draft, pending user review
**Owner:** payroll-flutter

## Summary

Add a new `JobListing` entity that owns applicants, and restructure the Hiring feature so HR's primary workflow is **listing-first** (open a role → collect applicants under it) instead of **applicant-first** (add an applicant → assign a role).

Headcount is **slot-based and self-healing**: each listing has a `target_headcount`; the filled count is derived from active employees in that (role, brand) at query time. When someone resigns, the listing automatically reopens. No manual reset.

Existing applicants are unaffected: their `listing_id` stays NULL and they appear in a new "Talent Pool" tab. HR can optionally move them into listings later.

The existing kanban widget is reused as the per-listing applicant view.

## Motivation

The current Hiring screen is one global kanban filtered by role/brand. It works but doesn't match how Luxium actually hires:

- HR identifies a staffing need ("we're down a cashier") → opens a job listing → collects applicants for it.
- Right now there's no representation of "the open role" — just a pile of applicants. The role is duplicated as a per-applicant FK. No way to see "we have 3 open positions across the company" at a glance.
- When an employee resigns, the company should know that role is open again. Today this is purely tribal knowledge.

Adding listings:
1. Matches Luxium HR's mental model of hiring (Brixter has said this several times).
2. Surfaces headcount/staffing-need data structurally instead of by chasing people.
3. Enables a per-role funnel view that's currently impossible (across global pool, you can't see "how many applicants for the Senior Cashier role" without filtering).
4. Auto-self-heals when employees separate — closing a real ops gap.

## Decisions (locked from brainstorm)

1. **Backfill**: `applicants.listing_id` is nullable; existing rows stay NULL and surface in Talent Pool. No data migration of existing applicants.
2. **Headcount**: slot-based. `filled_count = COUNT(active employees with this role + brand)`. Auto-derived, not stored.
3. **Effective status** is derived: explicit `PAUSED` or `CLOSED` win; otherwise `FILLED` when `filled_count >= target_headcount`, else `OPEN`. Auto-reopens on separation.
4. **Fields**: minimal (title, brand, role, target_headcount, status, notes, timestamps + soft-delete).
5. **UI**: two tabs in Hiring screen — **Listings** (table) and **Talent Pool** (kanban of listing-less applicants).
6. **Role gate**: RoleScorecard is required when creating a listing (matches existing applicant hard-gate).
7. **Role editability** (revised): listing's `role_scorecard_id` and `hiring_entity_id` are **editable** after creation, with a confirmation dialog warning that filled_count will recompute. Applicants and employees can be redirected between roles freely (HR may need to redirect mid-pipeline or via promotion).
8. **Title default**: `RoleScorecard.jobTitle` (e.g., "Cashier"). HR can override.

## Scope (in)

- New `job_listings` table + RLS policies.
- New columns: `applicants.listing_id` (nullable FK).
- `JobListing` model + `JobListingRepository` + providers.
- Derived providers: `listingFilledCountProvider(listingId)`, `listingEffectiveStatusProvider(listingId)`.
- `ApplicantListQuery` gains a `listingId` filter (`null` = Talent Pool, `'<uuid>'` = specific listing, omitted = all).
- Hiring screen restructure into two tabs.
- Listings table with filter bar.
- New / Edit Listing form screen.
- Listing Detail screen (reuses existing kanban widget, scoped).
- Talent Pool tab (reuses existing kanban widget, scoped to `listing_id IS NULL`).
- Applicant form: accepts optional `listingSeed` (pre-fills + locks brand/role when opened from a listing).
- "Move applicant to listing" action on applicant detail screen.
- Listing badge on applicant cards (when `listing_id` is set).
- Existing applicant status transitions and convert flow unchanged.

## Scope (out — v2 or later)

- **Public posting** to job boards / external sites. Listings stay internal-only.
- **Approval workflow** for opening a listing (e.g., manager → director → HR). Direct create only in v1.
- **Listing-level hiring metrics** beyond the basic filled/target chip (time-to-fill, source funnel, cost-per-hire). Defer.
- **Templates for listings** (e.g., "Cashier - HAVIT" preset to copy). Defer.
- **Auto-suggest matching applicants** from Talent Pool when a listing opens. Defer.
- **Backfill existing applicants** into listings via auto-grouping. Spec'd Option A wins: existing applicants stay in Talent Pool, no migration.
- **Listing → Workflow trigger**: when a listing CLOSES, auto-fire any wrap-up workflow. Defer (workflow infra exists; integration deferred).
- **Public/private listing visibility flag**, candidate-facing portal, etc.

## Integration with existing systems

- **Employee model**: unchanged. Slot count derives from `employees.role_scorecard_id + employees.hiring_entity_id + employees.employment_status + employees.deleted_at`.
- **Salary Adjustment / Promotion template** (Batch 2): when an employee's `role_scorecard_id` changes via this template, the affected listings naturally recompute their filled_counts on next read. No special wiring needed.
- **Separation workflow**: when an employee transitions to SEPARATED (Quitclaim path), listings naturally recompute. Auto-reopening is implicit — no listener required.
- **Hiring workflow** (kickoff on applicant conversion): unchanged. The convert flow stays exactly as it is. After conversion, the new employee row triggers a listing recompute on next read.
- **Documents**: no integration changes. Documents are scoped to employees / applicants, not listings.

## Schema

### New table `job_listings`

```sql
CREATE TABLE job_listings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  hiring_entity_id UUID NOT NULL REFERENCES hiring_entities(id),
  role_scorecard_id UUID NOT NULL REFERENCES role_scorecards(id),
  title TEXT NOT NULL,
  target_headcount INTEGER NOT NULL DEFAULT 1 CHECK (target_headcount >= 1),
  status TEXT NOT NULL DEFAULT 'OPEN' CHECK (status IN ('OPEN', 'PAUSED', 'CLOSED')),
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_by_id UUID REFERENCES auth.users(id),
  closed_at TIMESTAMPTZ,
  deleted_at TIMESTAMPTZ
);

CREATE INDEX idx_job_listings_status_not_deleted
  ON job_listings(status)
  WHERE deleted_at IS NULL;

CREATE INDEX idx_job_listings_role_brand
  ON job_listings(role_scorecard_id, hiring_entity_id);
```

Note: only three persisted statuses (`OPEN`, `PAUSED`, `CLOSED`). `FILLED` is derived. When a listing is OPEN and `filled_count >= target_headcount`, the UI displays "FILLED" as a chip but the column value stays `OPEN`. This lets the auto-reopen behavior work without writes.

### Modified `applicants`

```sql
ALTER TABLE applicants
  ADD COLUMN listing_id UUID REFERENCES job_listings(id);

CREATE INDEX idx_applicants_listing_id
  ON applicants(listing_id)
  WHERE deleted_at IS NULL;
```

`listing_id` is nullable. Existing rows are NULL — they're the Talent Pool.

### RLS policies

Same as `employees` / `applicants`: HR/Admin role required for all operations; non-HR users get zero rows. Soft-delete via `deleted_at`.

```sql
ALTER TABLE job_listings ENABLE ROW LEVEL SECURITY;

CREATE POLICY job_listings_hr_select ON job_listings FOR SELECT
  USING (auth.jwt() ->> 'role' IN ('hr', 'admin'));
CREATE POLICY job_listings_hr_insert ON job_listings FOR INSERT
  WITH CHECK (auth.jwt() ->> 'role' IN ('hr', 'admin'));
CREATE POLICY job_listings_hr_update ON job_listings FOR UPDATE
  USING (auth.jwt() ->> 'role' IN ('hr', 'admin'))
  WITH CHECK (auth.jwt() ->> 'role' IN ('hr', 'admin'));
-- No DELETE policy. Use UPDATE deleted_at = now() for soft-delete.
```

### Derived computations (no schema changes)

```dart
// Filled count: active employees in this (role, brand).
final listingFilledCountProvider = FutureProvider.family<int, String>((ref, listingId) async {
  final listing = await ref.read(jobListingByIdProvider(listingId).future);
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

// Effective status: explicit overrides win; else FILLED vs OPEN by slot count.
enum ListingEffectiveStatus { open, filled, paused, closed }

final listingEffectiveStatusProvider = FutureProvider.family<ListingEffectiveStatus, String>(
  (ref, listingId) async {
    final listing = await ref.read(jobListingByIdProvider(listingId).future);
    if (listing == null) return ListingEffectiveStatus.closed;
    if (listing.status == 'PAUSED') return ListingEffectiveStatus.paused;
    if (listing.status == 'CLOSED') return ListingEffectiveStatus.closed;
    final filled = await ref.read(listingFilledCountProvider(listingId).future);
    return filled >= listing.targetHeadcount
        ? ListingEffectiveStatus.filled
        : ListingEffectiveStatus.open;
  },
);
```

## UI

### Hiring screen → two tabs

The existing `HiringScreen` widget restructures into a `TabBar` with two tabs. The current global-kanban view is dismantled. The route stays `/hiring`.

```
┌─ Hiring ─────────────────────────────────────┐
│  [Listings] [Talent Pool]              [+ New Listing] │
├──────────────────────────────────────────────┤
│  ... selected tab content ...                │
└──────────────────────────────────────────────┘
```

### Listings tab (default)

A flat table (uses existing `ResponsiveTable` widget — `lib/widgets/responsive_table.dart`).

- **Filter bar**: search (title), brand picker, role picker, status picker (All / Open / Filled / Paused / Closed)
- **Columns**: Title · Brand · Role · Filled/Target · Status chip · Applicants · Created
- **Status chip colors** (per `PRODUCT.md` tinted-bg pattern):
  - OPEN: brand purple
  - FILLED: green-tinted
  - PAUSED: amber-tinted
  - CLOSED: neutral grey
- **Empty state**: "No listings yet. Create your first listing to start hiring."
- **Row click** → `/hiring/listings/<id>` (Listing Detail screen)

### Talent Pool tab

Reuses the existing kanban widget, parameterized to filter `listing_id IS NULL`.

- "+ Add to Talent Pool" CTA (creates applicant with `listing_id = null`)
- Each applicant card shows the existing fields plus a "Move to listing…" overflow action.
- Move-to-listing dialog: dropdown of all OPEN listings (or all listings if "Show closed" toggled), confirm button. On submit: PATCH `applicants.listing_id = <chosen>` and update `role_scorecard_id` + `hiring_entity_id` to match the target listing.

### Listing Detail screen (new) — `/hiring/listings/:id`

Header:
```
┌─ Cashier (Talent Pool) ──────────────────────────────┐
│  [Brand: HAVIT]  [Role: Cashier]  [OPEN]  [2 / 3]    │
│  Created Jun 5, 2026 by Brixter                      │
│                                                       │
│  [Edit listing]  [Pause]  [Close]  [Delete]          │
├──────────────────────────────────────────────────────┤
│  [Reused applicant kanban, scoped to listing_id = X] │
│  [+ Add applicant to this listing]                   │
└──────────────────────────────────────────────────────┘
```

- **Edit listing**: opens edit form. Editable fields: title, target_headcount, role_scorecard_id, hiring_entity_id, notes. Editing role or brand triggers a confirmation dialog: "Changing the role/brand will recompute the filled count against the new (role, brand). Continue?".
- **Pause / Reopen**: toggles `status` between `OPEN` ↔ `PAUSED`.
- **Close**: sets `status = 'CLOSED'` + `closed_at = NOW()`. Confirmation dialog.
- **Delete**: soft-delete. Confirmation dialog mentions any non-archived applicants will retain their `listing_id` reference (orphaned but not lost).

The kanban widget below is the existing applicant kanban from `lib/features/hiring/hiring_screen.dart` extracted into a reusable component (see "Refactor" section below). Scoped to `listing_id = <this.id>`.

### Applicant form changes

`lib/features/hiring/applicant_form_screen.dart` accepts an optional `listingId` parameter:

- When set (entry: "+ Add applicant to this listing"):
  - `listing_id` field set + invisible
  - Brand and Role pickers are pre-filled from the listing and **locked** (greyed out, not editable)
  - Form title: "New Applicant — <Listing Title>"
- When null (entry: "+ Add to Talent Pool"):
  - `listing_id` stays null
  - Brand + Role pickers are user-selectable (current behavior, including the hard-gate)
  - Form title: "New Applicant — Talent Pool"

### Applicant card

Add a small badge: "Talent Pool" or "<Listing Title>". On click, navigates to the listing (if not in Talent Pool).

## Refactor — extract reusable kanban

The current `HiringScreen` has the kanban hard-wired with global filtering. Extract it into a parameterizable widget:

**New file**: `lib/features/hiring/widgets/applicant_kanban.dart`

```dart
class ApplicantKanban extends ConsumerWidget {
  final ApplicantListQuery query;  // already supports listingId via new field
  final void Function(Applicant)? onCardTap;
  final void Function(String)? onMoveToListing; // null = no move action
  const ApplicantKanban({super.key, required this.query, this.onCardTap, this.onMoveToListing});
  // ... renders existing 6 columns (NEW, SCREENING, INTERVIEW, ASSESSMENT, OFFER, OFFER_ACCEPTED), with HIRED + rejected pinned in collapsed sections
}
```

Both the Talent Pool tab and Listing Detail screen instantiate this widget with different `query` and `onMoveToListing` configs.

The card-render code stays in `lib/features/hiring/widgets/applicant_card.dart` (already extracted in Hiring MVP).

## Routing

```
/hiring                        → HiringScreen (tabs: Listings | Talent Pool)
/hiring/listings/new           → ListingFormScreen (create)
/hiring/listings/:id           → ListingDetailScreen
/hiring/listings/:id/edit      → ListingFormScreen (edit)
/hiring/listings/:id/applicants/new → ApplicantFormScreen(listingId: ':id')
/hiring/new                    → ApplicantFormScreen(listingId: null) — Talent Pool quick-add
/hiring/:applicantId           → ApplicantDetailScreen (unchanged route)
```

## Tests

Per-phase TDD:

**Phase 1 (Backend)**:
- `job_listing_test.dart` — round-trip via fromRow / toJson
- `job_listing_repository_test.dart` — list / byId / insert / update / softDelete
- `listing_effective_status_test.dart` — derives FILLED vs OPEN vs PAUSED vs CLOSED correctly given different (filled_count, status) combos
- `applicant_list_query_test.dart` — `listingId: null` returns Talent Pool, `listingId: 'X'` returns scoped, omitted returns all

**Phase 2 (UI)**:
- Listings table renders rows with correct chips
- Empty state shown when no listings
- Filter bar updates the visible list
- New-listing form validates required fields (title, role, brand, target_headcount > 0)

**Phase 3 (Applicant integration)**:
- Applicant form locks brand+role when listingId is set
- Move-to-listing dialog updates `listing_id` + `role_scorecard_id` + `hiring_entity_id` atomically
- Applicant card shows correct listing badge

**Phase 4 (End-to-end)**:
- Create listing (target_headcount=2, role=Cashier) → effective_status = OPEN
- Add 2 applicants → status still OPEN
- Convert both applicants to HIRED employees → effective_status = FILLED
- Set one employee.employment_status = 'SEPARATED' → effective_status = OPEN (auto-reopen)
- Manual smoke in running app.

## Phases for the implementation plan

**Phase 1 — Backend (~6 tasks)**
1. Migration: `job_listings` table + `applicants.listing_id` column + RLS
2. `JobListing` model (fields, fromRow, toJson, copyWith)
3. `JobListingRepository` (list / byId / insert / update / softDelete) + providers
4. Derived providers: `listingFilledCountProvider`, `listingEffectiveStatusProvider`
5. Extend `ApplicantListQuery` with `listingId` filter (null/uuid/omitted semantics) + repository update
6. Phase 1 green-bar checkpoint

**Phase 2 — UI scaffold (~7 tasks)**
7. Refactor: extract `applicant_kanban.dart` from `hiring_screen.dart`
8. `HiringScreen` two-tab restructure (Listings tab + Talent Pool tab)
9. `ListingsTable` widget + filter bar + chips
10. `ListingFormScreen` (create mode)
11. `ListingFormScreen` (edit mode + role-change confirm dialog)
12. `ListingDetailScreen` (header + actions + embedded kanban)
13. Routing wiring + sidebar entry

**Phase 3 — Applicant integration (~5 tasks)**
14. `ApplicantFormScreen` accepts optional `listingId`; brand/role lock when set
15. Move-to-listing dialog + action on applicant detail
16. Applicant card: listing badge
17. CTAs: "+ Add applicant" buttons everywhere route correctly
18. "+ Add to Talent Pool" CTA on Talent Pool tab

**Phase 4 — Tests + smoke (~3 tasks)**
19. End-to-end test: create-listing → add-applicants → hire → verify auto-FILLED → separate → verify auto-OPEN
20. Full test + analyze + format pass
21. Manual smoke in running app

**Total: ~21 tasks**, comparable to prior MVPs.

## Risks

- **Filled-count query cost**: every listing display queries `employees` via `roleScorecardId + hiringEntityId`. If Luxium has many open listings, the Listings table fires N queries on render. Mitigation: cache via a single batched query in `listingFilledCountProvider` (preload-on-mount of the list page), or compute a database view. Defer optimization until measured.
- **Stale filled_count when offline**: the derived count is queried on read, not stored. If the user is offline, the count might be stale. Acceptable trade-off vs maintaining a denormalized counter that needs invalidation triggers.
- **Migration rollback**: adding a NOT NULL constraint to `listing_id` later (when we want to enforce listings) would require backfill. v1 keeps it nullable — safe.
- **Soft-delete weirdness**: deleting a listing leaves applicants with `listing_id` pointing at a soft-deleted row. The UI should show "(deleted listing)" gracefully and offer a Move-to-listing action.
- **Role change on a listing**: revised decision makes the role editable. The filled_count recompute is automatic but might surprise HR. Confirmation dialog should clearly explain the impact.

## Open questions to resolve at plan time

1. **Sidebar nav**: should "Hiring" remain a single sidebar item with the tab-bar inside, or split into "Listings" + "Talent Pool" as two separate sidebar items? v1: single "Hiring" item with internal tabs (matches current structure; less navigation churn).
2. **Talent Pool empty state**: encourage HR to create a listing? Or leave it as a quiet empty state? v1: subtle empty state with a "Create listing" link.
3. **Reordering listings**: priority field deferred (out of scope), so listings sort by `created_at DESC`. If multiple OPEN listings, no manual reordering. Add a `display_order` later if needed.

## What this unblocks (downstream)

- **Public job posting**: listings already have title + brand + role — easy to wire to a public job board v2.
- **Approval workflow**: if HR ever needs manager → director sign-off to open a listing, the `JobListing` entity gives us a stable target for the workflow infra (similar to how Separation Workflow targets an Employee today).
- **Hiring metrics dashboards**: time-to-fill, source effectiveness, cost-per-hire all become possible once applicants live under listings.
- **ATS integration**: listings give us a primary key candidates can be matched against if Luxium ever uses an external ATS.
