# KPI Library (Phase 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Unify today's per-role-card KPI JSON into a first-class `kpis` library + `role_scorecard_kpis` link, losslessly, so KPIs gain stable IDs (needed by later per-employee tracking) and can be picked from a grouped library.

**Architecture:** New `kpis` (library) and `role_scorecard_kpis` (link) tables. A forward migration seeds them from `role_scorecards.kpis` and re-points `generate_employee_review`. The Dart repository backfills `RoleScorecard.kpis` from the join so read-only consumers (PDF, contract, detail) don't change; only the role-card editor's write path and a new KPI-library screen are new. The legacy `role_scorecards.kpis` column is kept for rollback.

**Tech Stack:** Supabase Postgres (forward migrations), Deno (edge — none here), Flutter + Riverpod + GoRouter, the `supabase_flutter` PostgREST client.

## Global Constraints

- Gate on `flutter analyze` only — mixed formatter styles; do NOT run `dart format`. Match surrounding style.
- Migrations are **forward-only** — the 20260717* migrations are applied on prod; never edit them.
- The seed migration must be **lossless**: every existing role-card KPI becomes one `role_scorecard_kpis` link preserving its exact `target`/`frequency`; identical names collapse to one `kpis` row per company (deduped on `lower(trim(name))`).
- Keep `role_scorecards.kpis` JSON column in place (do not drop) — rollback safety.
- `target`/`frequency` are stored as `text` (targets like "3%" are free text today; no numeric coercion).
- RLS matches the existing role-card convention: select = `company_id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN'`; write = `auth_app_role() in ('SUPER_ADMIN','ADMIN','HR')` and company match.
- Test any prod-bound migration against an isolated local replica first (ports 643xx; seed `supabase/seed/01_company.sql` before `20260418000002`) — see the repo's local-RLS-testing notes.
- Design system per `PRODUCT.md`: single Luxium purple CTA, 6px radius, tables via `lib/widgets/responsive_table.dart`, no new colors/packages.

---

### Task 1: `kpis` + `role_scorecard_kpis` tables, RLS, and lossless seed migration

**Files:**
- Create: `supabase/migrations/20260718000001_kpi_library.sql`

**Interfaces:**
- Produces: tables `kpis(id, company_id, name, category, description, measurement_unit, is_active, created_at, updated_at)` and `role_scorecard_kpis(id, role_scorecard_id, kpi_id, target, frequency, sort_order, created_at, updated_at)`; both seeded from `role_scorecards.kpis`. Consumed by Tasks 2–5.

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/20260718000001_kpi_library.sql`:

```sql
-- Phase 1 of KPI tracking: promote role-card KPIs (JSON on role_scorecards.kpis)
-- into a first-class library + link, losslessly. The legacy JSON column is kept
-- for rollback; a later migration drops it once this path is proven.

create table kpis (
  id                uuid primary key default gen_random_uuid(),
  company_id        uuid not null references companies(id),
  name              text not null,
  category          text,
  description       text,
  measurement_unit  text,
  is_active         boolean not null default true,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  constraint kpis_name_not_blank check (length(trim(name)) > 0)
);
create unique index kpis_company_lower_name on kpis (company_id, lower(trim(name)));
create index kpis_company_category on kpis (company_id, category);

create trigger _kpis_updated before update on kpis
  for each row execute function set_updated_at();

create table role_scorecard_kpis (
  id                 uuid primary key default gen_random_uuid(),
  role_scorecard_id  uuid not null references role_scorecards(id) on delete cascade,
  kpi_id             uuid not null references kpis(id) on delete restrict,
  target             text,
  frequency          text,
  sort_order         integer not null default 0,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  unique (role_scorecard_id, kpi_id)
);
create index role_scorecard_kpis_role on role_scorecard_kpis (role_scorecard_id);
create index role_scorecard_kpis_kpi on role_scorecard_kpis (kpi_id);

create trigger _role_scorecard_kpis_updated before update on role_scorecard_kpis
  for each row execute function set_updated_at();

-- Seed: one library KPI per distinct name per company; one link per role-card KPI.
insert into kpis (company_id, name, measurement_unit)
select distinct on (rs.company_id, lower(trim(coalesce(k->>'name', k->>'metric'))))
  rs.company_id,
  trim(coalesce(k->>'name', k->>'metric')),
  nullif(trim(coalesce(k->>'measurement', '')), '')
from role_scorecards rs
  cross join lateral jsonb_array_elements(coalesce(rs.kpis, '[]'::jsonb)) as k
where length(trim(coalesce(k->>'name', k->>'metric', ''))) > 0
on conflict (company_id, lower(trim(name))) do nothing;

insert into role_scorecard_kpis (role_scorecard_id, kpi_id, target, frequency, sort_order)
select
  rs.id,
  lib.id,
  nullif(trim(coalesce(k->>'target', '')), ''),
  nullif(trim(coalesce(k->>'frequency', '')), ''),
  (k_index - 1)::int
from role_scorecards rs
  cross join lateral jsonb_array_elements(coalesce(rs.kpis, '[]'::jsonb))
    with ordinality as arr(k, k_index)
  join kpis lib
    on lib.company_id = rs.company_id
    and lower(trim(lib.name)) = lower(trim(coalesce(arr.k->>'name', arr.k->>'metric', '')))
where length(trim(coalesce(arr.k->>'name', arr.k->>'metric', ''))) > 0
on conflict (role_scorecard_id, kpi_id) do nothing;

-- RLS: company-scoped, mirroring role_scorecards.
alter table kpis enable row level security;
create policy kpis_company_select on kpis for select
  using (company_id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN');
create policy kpis_company_write on kpis for all
  using (auth_app_role() in ('SUPER_ADMIN','ADMIN','HR')
    and (company_id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN'))
  with check (auth_app_role() in ('SUPER_ADMIN','ADMIN','HR')
    and (company_id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN'));

-- role_scorecard_kpis has no company_id; scope via its parent role card, whose
-- own select policy is already company-read.
alter table role_scorecard_kpis enable row level security;
create policy role_scorecard_kpis_select on role_scorecard_kpis for select
  using (exists (
    select 1 from role_scorecards rs where rs.id = role_scorecard_id
      and (rs.company_id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN')));
create policy role_scorecard_kpis_write on role_scorecard_kpis for all
  using (auth_app_role() in ('SUPER_ADMIN','ADMIN','HR') and exists (
    select 1 from role_scorecards rs where rs.id = role_scorecard_id
      and (rs.company_id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN')))
  with check (auth_app_role() in ('SUPER_ADMIN','ADMIN','HR') and exists (
    select 1 from role_scorecards rs where rs.id = role_scorecard_id
      and (rs.company_id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN')));
```

- [ ] **Step 2: Apply + assert losslessness on an isolated local replica**

Bring up an isolated stack (ports 643xx), apply migrations in order seeding `supabase/seed/01_company.sql` before `20260418000002` (see the repo's local-RLS-testing notes), then:

Run (psql against the replica):
```sql
-- link count == total KPI entries across all role cards
select
  (select count(*) from role_scorecard_kpis) as links,
  (select coalesce(sum(jsonb_array_length(coalesce(kpis,'[]'::jsonb))),0)
     from role_scorecards
     where kpis is not null) as json_kpis;
-- library rows == distinct lower(name) per company
select
  (select count(*) from kpis) as lib_rows,
  (select count(*) from (
     select distinct rs.company_id, lower(trim(k->>'name'))
     from role_scorecards rs, jsonb_array_elements(coalesce(rs.kpis,'[]'::jsonb)) k
     where length(trim(coalesce(k->>'name',k->>'metric','')))>0) d) as distinct_names;
```
Expected: `links == json_kpis` minus (a) blank-name entries and (b) any **intra-card duplicate-normalized names** — a card links a library KPI at most once, so duplicates collapse to the first (lowest index) occurrence, deterministically. `lib_rows == distinct_names`. Spot-check targets survive: `select target, frequency, sort_order from role_scorecard_kpis where role_scorecard_id = '<id>' order by sort_order;`

**Controller gate (before prod push):** run the intra-card duplicate check — `select role_scorecard_id, lower(trim(coalesce(k->>'name',k->>'metric'))) nm, count(*) from role_scorecards, jsonb_array_elements(coalesce(kpis,'[]'::jsonb)) k group by 1,2 having count(*)>1;`. If it returns rows, a real target would be dropped — surface those cards to the user (data to clean up) rather than silently pushing.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260718000001_kpi_library.sql
git commit -m "feat(kpi): kpis library + role_scorecard_kpis link with lossless seed"
```

*(Do NOT `supabase db push` to prod yet — that happens once the whole Phase 1 is reviewed and the replica assertions pass.)*

---

### Task 2: Re-point `generate_employee_review` to read the join

**Files:**
- Create: `supabase/migrations/20260718000002_generate_review_from_kpi_link.sql`

**Interfaces:**
- Consumes: `role_scorecard_kpis` + `kpis` (Task 1).
- Produces: an updated `generate_employee_review` that snapshots KPIs from the link instead of `v_card.kpis`. `review_kpi_results` shape unchanged.

- [ ] **Step 1: Read the current function**

Run: `sed -n '/create or replace function generate_employee_review/,/^\$\$;/p' supabase/migrations/20260717000002_review_cycle_foundation.sql`
This is the authoritative body to copy forward. Only the KPI snapshot loop changes.

- [ ] **Step 2: Write the forward migration**

Create `supabase/migrations/20260718000002_generate_review_from_kpi_link.sql` as a `create or replace function generate_employee_review(...)` that is **byte-identical to the current body except** the KPI snapshot loop, which becomes:

```sql
  v_index := 0;
  for v_item in
    select jsonb_build_object(
      'name', k.name,
      'measurement', k.measurement_unit,
      'target', rsk.target
    ) as value
    from role_scorecard_kpis rsk
      join kpis k on k.id = rsk.kpi_id
    where rsk.role_scorecard_id = v_card.id
    order by rsk.sort_order
  loop
    insert into review_kpi_results (
      review_id, snapshot_order, kpi_name, description,
      measurement_unit, target_value, is_qualitative
    ) values (
      v_review_id, v_index,
      coalesce(v_item->>'name', ''),
      null, v_item->>'measurement', v_item->>'target',
      false
    );
    v_index := v_index + 1;
  end loop;
```

**Critical boundary note.** In the current function, `v_index integer;` and `v_item` are shared: `v_index := 0;` appears at line 53 (before the KPI loop) AND again at line 70 (before the skills loops), and the two skills loops that follow use `v_item` **as jsonb** (`v_item->>'name'`). So `v_item` MUST stay whatever type it is declared as (jsonb) — that is why the new KPI loop yields a single `value` jsonb column (via `jsonb_build_object`) exactly like the original `select value from jsonb_array_elements(...)`, rather than a multi-column record. Replace ONLY the block from the KPI-loop's `v_index := 0;` (line 53) through its matching `end loop;` (line 68) with the block above. Leave the second `v_index := 0;` and both skills loops untouched. Preserve the ENTIRE rest of the function verbatim by copying it from the sed output in Step 1 — do NOT retype it from memory (the `create or replace` restates the whole body; a transcription slip corrupts a live function reviews depend on).

- [ ] **Step 3: Apply on the replica + verify identical snapshot**

On the replica: seed a role card with 2 KPIs, an employee on that role, generate a review, and confirm `review_kpi_results` has the same `kpi_name`/`target_value`/`measurement_unit`/`snapshot_order` as before Task 1 (compare against a review generated from the pre-migration JSON path on a separate replay, or against the known seed values).

Run: `psql "<replica>" -c "select snapshot_order, kpi_name, target_value, measurement_unit from review_kpi_results where review_id='<id>' order by snapshot_order;"`
Expected: rows match the seeded role card's KPIs in order.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260718000002_generate_review_from_kpi_link.sql
git commit -m "feat(kpi): generate_employee_review snapshots KPIs from the link"
```

---

### Task 3: Model + repository read path — backfill `RoleScorecard.kpis` from the join

**Files:**
- Modify: `lib/data/models/role_scorecard.dart` (`fromRow` KPI parsing ~line 141-148; `toUpsertPayload` ~line 203)
- Modify: `lib/data/repositories/role_scorecard_repository.dart` (`list`, `byId` selects; add link-persist + library helpers)
- Test: `test/data/models/role_scorecard_kpi_link_test.dart`

**Interfaces:**
- Consumes: `role_scorecard_kpis`, `kpis` (Task 1).
- Produces:
  - `RoleScorecard.fromRow` reads KPIs from an embedded `role_scorecard_kpis` list when present, else from the legacy `kpis` JSON (back-compat for the upsert-return row).
  - `RoleScorecard.toUpsertPayload()` no longer emits `'kpis'`.
  - `KpiLink` value type: `class KpiLink { final String? kpiId; final String name; final String? measurement; final String? category; final String target; final String frequency; }` (used by Task 4).
  - Repo methods consumed by Tasks 4–5:
    - `Future<List<Kpi>> RoleScorecardRepository.listKpis()` → library KPIs.
    - `Future<Kpi> upsertKpi(Kpi kpi)`.
    - `Future<void> saveRoleScorecardKpis(String roleScorecardId, List<KpiLinkInput> links)` — replaces the card's links (create library KPIs for new names, then insert/update/delete `role_scorecard_kpis`).

- [ ] **Step 1: Write the failing test for join parsing**

Create `test/data/models/role_scorecard_kpi_link_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';

Map<String, dynamic> baseRow(Object? embeddedKpis) => {
  'id': 'card-1',
  'company_id': 'co-1',
  'job_title': 'Brand Associate',
  'department_id': null,
  'mission_statement': 'Own the storefront.',
  'key_responsibilities': [],
  'kpis': [], // legacy column, ignored when embed present
  'required_skills': [],
  'behavioral_expectations': [],
  'version': 1,
  'salary_range_min': null,
  'salary_range_max': null,
  'base_salary': null,
  'wage_type': 'MONTHLY',
  'work_hours_per_day': 8,
  'work_days_per_week': 'MON_FRI',
  'is_active': true,
  'effective_date': '2026-01-01',
  'hiring_entity_id': null,
  'role_scorecard_kpis': embeddedKpis,
};

void main() {
  test('kpis come from the embedded link, ordered by sort_order', () {
    final card = RoleScorecard.fromRow(baseRow([
      {'target': '3%', 'frequency': 'Monthly', 'sort_order': 1,
       'kpis': {'name': 'Retention', 'measurement_unit': '%'}},
      {'target': '10/day', 'frequency': 'Weekly', 'sort_order': 0,
       'kpis': {'name': 'Throughput', 'measurement_unit': 'orders'}},
    ]));
    expect(card.kpis.map((k) => k.name), ['Throughput', 'Retention']);
    expect(card.kpis.first.measurement, 'orders');
    expect(card.kpis.first.target, '10/day');
    expect(card.kpis[1].frequency, 'Monthly');
  });

  test('falls back to legacy kpis JSON when no embed present', () {
    final row = baseRow(null)..['kpis'] = [
      {'name': 'Legacy', 'measurement': 'x', 'target': '1', 'frequency': 'Monthly'},
    ];
    final card = RoleScorecard.fromRow(row);
    expect(card.kpis.single.name, 'Legacy');
  });

  test('toUpsertPayload no longer includes kpis', () {
    final card = RoleScorecard.fromRow(baseRow(const []));
    expect(card.toUpsertPayload().containsKey('kpis'), isFalse);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/data/models/role_scorecard_kpi_link_test.dart`
Expected: FAIL — `fromRow` still reads the legacy column unconditionally, and `toUpsertPayload` still emits `kpis`.

- [ ] **Step 3: Update `fromRow` KPI parsing**

In `lib/data/models/role_scorecard.dart`, replace the KPI-parsing block (the `List<KpiItem> kpis; if (rawKpis is List) {...} else {...}`) with:

```dart
    List<KpiItem> kpis;
    final embeddedKpis = r['role_scorecard_kpis'];
    if (embeddedKpis is List) {
      // Authoritative source post-KPI-library migration: the link table,
      // ordered by sort_order. measurement comes from the library KPI.
      final links = embeddedKpis.whereType<Map>().toList()
        ..sort((a, b) =>
            (a['sort_order'] as int? ?? 0).compareTo(b['sort_order'] as int? ?? 0));
      kpis = [
        for (final link in links)
          KpiItem(
            name: (link['kpis'] as Map?)?['name'] as String? ?? '',
            measurement:
                (link['kpis'] as Map?)?['measurement_unit'] as String? ?? '',
            target: link['target'] as String? ?? '',
            frequency: link['frequency'] as String? ?? '',
          ),
      ];
    } else if (rawKpis is List) {
      // Back-compat: the upsert-return row and any pre-migration read.
      kpis = rawKpis.cast<Map<String, dynamic>>().map(KpiItem.fromJson).toList();
    } else {
      kpis = const [];
    }
```

- [ ] **Step 4: Drop `kpis` from `toUpsertPayload`**

In the same file, remove the line `'kpis': kpis.map((k) => k.toJson()).toList(),` from `toUpsertPayload()`. (KPIs are now persisted via `saveRoleScorecardKpis`, Step 6.)

- [ ] **Step 5: Run the model test to verify it passes**

Run: `flutter test test/data/models/role_scorecard_kpi_link_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 6: Add the `Kpi` model + repository read/write methods**

Add a `Kpi` model file `lib/data/models/kpi.dart`:

```dart
class Kpi {
  final String id;
  final String companyId;
  final String name;
  final String? category;
  final String? description;
  final String? measurementUnit;
  final bool isActive;
  const Kpi({
    required this.id,
    required this.companyId,
    required this.name,
    this.category,
    this.description,
    this.measurementUnit,
    this.isActive = true,
  });
  factory Kpi.fromRow(Map<String, dynamic> r) => Kpi(
    id: r['id'] as String,
    companyId: r['company_id'] as String,
    name: r['name'] as String,
    category: r['category'] as String?,
    description: r['description'] as String?,
    measurementUnit: r['measurement_unit'] as String?,
    isActive: r['is_active'] as bool? ?? true,
  );
  Map<String, dynamic> toInsert(String companyId) => {
    'company_id': companyId,
    'name': name.trim(),
    'category': (category?.trim().isEmpty ?? true) ? null : category!.trim(),
    'description':
        (description?.trim().isEmpty ?? true) ? null : description!.trim(),
    'measurement_unit': (measurementUnit?.trim().isEmpty ?? true)
        ? null
        : measurementUnit!.trim(),
    'is_active': isActive,
  };
}

/// One KPI attached to a role card, as edited in the form.
class KpiLinkInput {
  final String? kpiId; // null → create the library KPI on save
  final String name;
  final String? measurementUnit;
  final String? category;
  final String target;
  final String frequency;
  const KpiLinkInput({
    this.kpiId,
    required this.name,
    this.measurementUnit,
    this.category,
    required this.target,
    required this.frequency,
  });
}
```

In `lib/data/repositories/role_scorecard_repository.dart`:
- Change `list()`'s select to embed the link:
  `.from('role_scorecards').select('*, role_scorecard_kpis(target, frequency, sort_order, kpis(name, measurement_unit))')` (keep the `is_active`/order clauses).
- Change `byId()`'s select the same way.
- Add:

```dart
  Future<List<Kpi>> listKpis({bool onlyActive = true}) async {
    var q = _client.from('kpis').select();
    if (onlyActive) q = q.eq('is_active', true);
    final rows = await q.order('category').order('name');
    return rows.cast<Map<String, dynamic>>().map(Kpi.fromRow).toList();
  }

  Future<Kpi> upsertKpi(String companyId, Kpi kpi) async {
    // The library dedupes case-insensitively via a FUNCTIONAL unique index
    // (company_id, lower(trim(name))), which PostgREST's onConflict cannot
    // target — so find-then-insert, not upsert. Stored names are trimmed on
    // write, so a lower-case compare suffices.
    final name = kpi.name.trim();
    final rows = await _client.from('kpis').select().eq('company_id', companyId);
    for (final r in (rows as List).cast<Map<String, dynamic>>()) {
      if ((r['name'] as String).trim().toLowerCase() == name.toLowerCase()) {
        return Kpi.fromRow(r);
      }
    }
    final row = await _client
        .from('kpis')
        .insert(kpi.toInsert(companyId))
        .select()
        .single();
    return Kpi.fromRow(row);
  }

  /// Replaces a role card's KPI links with [links]. Creates library KPIs for
  /// entries with a null kpiId (find-or-create by name), then reconciles the
  /// link rows (insert new, update target/frequency/order, delete removed).
  Future<void> saveRoleScorecardKpis(
    String roleScorecardId,
    String companyId,
    List<KpiLinkInput> links,
  ) async {
    // 1. Resolve every link to a kpi_id (create library rows for new names).
    final resolved = <({String kpiId, String target, String frequency})>[];
    for (var i = 0; i < links.length; i++) {
      final link = links[i];
      var kpiId = link.kpiId;
      if (kpiId == null) {
        final kpi = await upsertKpi(companyId, Kpi(
          id: '', companyId: companyId, name: link.name,
          category: link.category, measurementUnit: link.measurementUnit));
        kpiId = kpi.id;
      }
      resolved.add((kpiId: kpiId, target: link.target, frequency: link.frequency));
    }
    // Collapse duplicate kpi_ids (same library KPI attached twice) to the first
    // occurrence — matches (role_scorecard_id, kpi_id) uniqueness and avoids
    // Postgres 21000 ("ON CONFLICT DO UPDATE cannot affect row a second time").
    final seen = <String>{};
    final deduped = [
      for (final r in resolved)
        if (seen.add(r.kpiId)) r,
    ];
    // 2. Delete links no longer present.
    final keepIds = deduped.map((r) => r.kpiId).toList();
    var del = _client.from('role_scorecard_kpis').delete()
        .eq('role_scorecard_id', roleScorecardId);
    if (keepIds.isNotEmpty) {
      del = del.not('kpi_id', 'in', '(${keepIds.join(',')})');
    }
    await del;
    // 3. Upsert the current links with their order.
    if (deduped.isNotEmpty) {
      await _client.from('role_scorecard_kpis').upsert([
        for (var i = 0; i < deduped.length; i++)
          {
            'role_scorecard_id': roleScorecardId,
            'kpi_id': deduped[i].kpiId,
            'target': deduped[i].target.trim().isEmpty ? null : deduped[i].target.trim(),
            'frequency': deduped[i].frequency.trim().isEmpty ? null : deduped[i].frequency.trim(),
            'sort_order': i,
          },
      ], onConflict: 'role_scorecard_id,kpi_id');
    }
  }
```

- [ ] **Step 7: Verify analyze + full suite**

Run: `flutter analyze lib/data/models/role_scorecard.dart lib/data/models/kpi.dart lib/data/repositories/role_scorecard_repository.dart test/data/models/role_scorecard_kpi_link_test.dart`
Expected: no errors.
Run: `flutter test`
Expected: all pass (the role-card PDF / contract / detail tests still pass because `card.kpis` is unchanged in shape).

- [ ] **Step 8: Commit**

```bash
git add lib/data/models/role_scorecard.dart lib/data/models/kpi.dart lib/data/repositories/role_scorecard_repository.dart test/data/models/role_scorecard_kpi_link_test.dart
git commit -m "feat(kpi): read RoleScorecard.kpis from the link; KPI library repo methods"
```

---

### Task 4: Role-card editor — library picker + persist to `role_scorecard_kpis`

**Files:**
- Modify: `lib/features/responsibility_cards/role_scorecard_form_screen.dart` (KPI section `_kpiEditor`/`_KpiDraft` ~line 41, 89-91, 138-147, 523-537, 573-612, 729-734; the `_save` handler)

**Interfaces:**
- Consumes: `Kpi`, `KpiLinkInput`, `RoleScorecardRepository.listKpis/saveRoleScorecardKpis` (Task 3).
- Produces: the editor writes KPIs to `role_scorecard_kpis` instead of the JSON blob.

- [ ] **Step 1: Extend `_KpiDraft` to carry a library id**

In `role_scorecard_form_screen.dart`, change `_KpiDraft` (~line 729) to:

```dart
class _KpiDraft {
  String? kpiId; // null until picked from / saved to the library
  String name;
  String measurement;
  String? category;
  String target;
  String frequency;
  _KpiDraft(this.name, this.measurement, this.target, this.frequency,
      {this.kpiId, this.category});
}
```

Load path (~line 89-91) stays valid — a loaded card's KPIs have no `kpiId` in `KpiItem`, so they'll re-resolve by name on save (find-or-create is idempotent). To carry the id through, load from the card's links instead: leave `_KpiDraft(k.name, k.measurement, k.target, k.frequency)` as-is for now (name-based resolution is lossless because `upsertKpi` is find-or-create by name).

- [ ] **Step 2: Load the library for the picker**

`RoleScorecardFormScreen` is a `ConsumerStatefulWidget` — confirm via `grep -n "class RoleScorecardFormScreen" role_scorecard_form_screen.dart`; if it is a plain `StatefulWidget`, convert to `ConsumerStatefulWidget` (mirror `employee_form_screen.dart`). In `build`, read the library:

```dart
final kpiLibrary = ref.watch(kpiLibraryProvider).asData?.value ?? const <Kpi>[];
```

Add the provider to `lib/data/repositories/role_scorecard_repository.dart`:

```dart
final kpiLibraryProvider = FutureProvider<List<Kpi>>((ref) {
  return ref.watch(roleScorecardRepositoryProvider).listKpis();
});
```

- [ ] **Step 3: Replace the KPI name field with a library Autocomplete**

In `_kpiEditor(int index)` (~line 573), replace the free-text **name** `TextFormField` with an `Autocomplete<Kpi>` that suggests library KPIs by name and, on selection, fills `kpiId`, `name`, `measurement`, `category`; typing a new name leaves `kpiId` null (created on save). Keep the **target** and **frequency** fields as free text (per-role). Keep **measurement** editable but prefilled from the picked KPI. Mirror the existing field layout/spacing. Concretely, the name field becomes:

```dart
Autocomplete<Kpi>(
  initialValue: TextEditingValue(text: _kpis[index].name),
  optionsBuilder: (v) => v.text.isEmpty
      ? kpiLibrary
      : kpiLibrary.where((k) =>
          k.name.toLowerCase().contains(v.text.toLowerCase())),
  displayStringForOption: (k) => k.name,
  onSelected: (k) => setState(() {
    _kpis[index]
      ..kpiId = k.id
      ..name = k.name
      ..measurement = k.measurementUnit ?? _kpis[index].measurement
      ..category = k.category;
  }),
  fieldViewBuilder: (context, controller, focusNode, onSubmit) => TextFormField(
    controller: controller,
    focusNode: focusNode,
    decoration: const InputDecoration(labelText: 'KPI name'),
    onChanged: (value) => setState(() {
      _kpis[index].name = value;
      _kpis[index].kpiId = null; // typing a fresh name = new library KPI
    }),
  ),
),
```

- [ ] **Step 4: Persist to the link on save**

In `_save`, after `upsert(card)` returns the saved card, replace the KPI-into-jsonb behaviour with a `saveRoleScorecardKpis` call. Since `toUpsertPayload` no longer carries `kpis` (Task 3), build the `KpiLinkInput` list from `_kpis` and call:

```dart
final saved = await ref.read(roleScorecardRepositoryProvider).upsert(card);
await ref.read(roleScorecardRepositoryProvider).saveRoleScorecardKpis(
  saved.id,
  saved.companyId,
  [
    for (final k in _kpis)
      if (k.name.trim().isNotEmpty)
        KpiLinkInput(
          kpiId: k.kpiId,
          name: k.name.trim(),
          measurementUnit: k.measurement.trim(),
          category: k.category,
          target: k.target.trim(),
          frequency: k.frequency.trim(),
        ),
  ],
);
ref.invalidate(roleScorecardListProvider);
ref.invalidate(scorecardEmployeeCountProvider);
ref.invalidate(kpiLibraryProvider);
ref.invalidate(roleScorecardByIdProvider(saved.id));
```

Remove the old `kpis: [for (final k in _kpis) KpiItem(...)]` argument from the `RoleScorecard(...)` construction in `_save` (the model no longer needs it for persistence; pass `kpis: const []` since `toUpsertPayload` ignores it).

- [ ] **Step 5: Verify analyze + full suite + manual smoke**

Run: `flutter analyze lib/features/responsibility_cards/role_scorecard_form_screen.dart lib/data/repositories/role_scorecard_repository.dart`
Expected: no errors.
Run: `flutter test`
Expected: all pass.
Manual (coordinator, no headless GUI): create a role card, add a KPI from the library + one new-name KPI with a target, save, reopen — both KPIs persist with targets; the new one appears in the library.

- [ ] **Step 6: Commit**

```bash
git add lib/features/responsibility_cards/role_scorecard_form_screen.dart lib/data/repositories/role_scorecard_repository.dart
git commit -m "feat(kpi): role-card editor picks from the KPI library and saves links"
```

---

### Task 5: KPI library management screen + nav

**Files:**
- Create: `lib/features/kpi_library/kpi_library_screen.dart`
- Create: `lib/features/kpi_library/kpi_form_dialog.dart`
- Modify: `lib/app/router.dart` (import + route + guard)
- Modify: `lib/app/shell.dart` (nav entry, sibling to Responsibility Cards)
- Test: `test/features/kpi_library/kpi_library_screen_test.dart`

**Interfaces:**
- Consumes: `kpiLibraryProvider`, `Kpi`, `RoleScorecardRepository.upsertKpi` (Tasks 3–4); a new `deactivateKpi`.
- Produces: `KpiLibraryScreen` at `/kpi-library`.

- [ ] **Step 1: Add a soft-delete repo method + provider (if not present)**

In `lib/data/repositories/role_scorecard_repository.dart`:

```dart
  Future<void> deactivateKpi(String kpiId) async {
    await _client.from('kpis').update({'is_active': false}).eq('id', kpiId);
  }
```

- [ ] **Step 2: Write the failing widget test (grouped-by-category render)**

Create `test/features/kpi_library/kpi_library_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/kpi.dart';
import 'package:payroll_flutter/data/repositories/role_scorecard_repository.dart';
import 'package:payroll_flutter/features/kpi_library/kpi_library_screen.dart';

void main() {
  testWidgets('groups KPIs by category', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        kpiLibraryProvider.overrideWith((ref) async => const [
          Kpi(id: '1', companyId: 'c', name: 'Retention', category: 'Sales'),
          Kpi(id: '2', companyId: 'c', name: 'Throughput', category: 'Ops'),
        ]),
      ],
      child: const MaterialApp(home: KpiLibraryScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Sales'), findsOneWidget);
    expect(find.text('Ops'), findsOneWidget);
    expect(find.text('Retention'), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run it to verify it fails**

Run: `flutter test test/features/kpi_library/kpi_library_screen_test.dart`
Expected: FAIL — `KpiLibraryScreen` does not exist.

- [ ] **Step 4: Build the screen**

Create `lib/features/kpi_library/kpi_library_screen.dart` — a `ConsumerWidget` that watches `kpiLibraryProvider`, groups the list by `category` (null → "Uncategorized"), and renders each group as a section with its KPIs; an AppBar "New KPI" action and per-row edit/deactivate open `KpiFormDialog` (Step 5). Follow the layout of an existing settings list (e.g. `lib/features/settings/roles/roles_settings_screen.dart`) and use `lib/widgets/responsive_table.dart` if tabular. Group in Dart:

```dart
final grouped = <String, List<Kpi>>{};
for (final k in kpis) {
  (grouped[k.category?.trim().isNotEmpty == true ? k.category!.trim() : 'Uncategorized'] ??= []).add(k);
}
```
On create/edit/deactivate, `await` the repo call then `ref.invalidate(kpiLibraryProvider)`.

- [ ] **Step 5: Build the create/edit dialog**

Create `lib/features/kpi_library/kpi_form_dialog.dart` — an `AlertDialog` (mirror an existing form dialog such as the shift-template or role dialog) with fields `name` (required), `category`, `measurement_unit`, `description`; returns a `Kpi` on save. The caller persists via `upsertKpi` and invalidates `kpiLibraryProvider`.

- [ ] **Step 6: Run the widget test to verify it passes**

Run: `flutter test test/features/kpi_library/kpi_library_screen_test.dart`
Expected: PASS.

- [ ] **Step 7: Route + nav**

In `lib/app/router.dart`: add `import '../features/kpi_library/kpi_library_screen.dart';`, a route inside the ShellRoute `GoRoute(path: '/kpi-library', builder: (c, s) => const KpiLibraryScreen())`, and extend the responsibility-cards HR guard to also cover it: change the existing `if (loc.startsWith('/responsibility-cards') && !loc.endsWith('/pdf') && !profile.isHrOrAdmin)` guard's sibling by adding `if (loc.startsWith('/kpi-library') && !profile.isHrOrAdmin) return '/dashboard';`.

In `lib/app/shell.dart`: add a `_NavItem` for "KPI Library" (icon `Icons.speed_outlined` or similar Material icon) pointing at `/kpi-library`, placed next to the Responsibility Cards entry, gated the same way that entry is.

- [ ] **Step 8: Verify analyze + full suite**

Run: `flutter analyze lib/features/kpi_library/ lib/app/router.dart lib/app/shell.dart`
Expected: no errors.
Run: `flutter test`
Expected: all pass.

- [ ] **Step 9: Commit**

```bash
git add lib/features/kpi_library/ lib/app/router.dart lib/app/shell.dart lib/data/repositories/role_scorecard_repository.dart test/features/kpi_library/kpi_library_screen_test.dart
git commit -m "feat(kpi): KPI library management screen + nav"
```

---

## After all tasks: prod migration

Only once every task is reviewed and the replica assertions in Tasks 1–2 pass: `supabase db push` applies `20260718000001` + `20260718000002` to prod. Confirm `supabase migration list` shows both on Remote, then smoke-test a role-card edit and a review generation on prod.

## Notes for the implementer

- The legacy `role_scorecards.kpis` JSON column is intentionally kept and no longer written after Task 3 — do not drop it in this plan.
- `saveRoleScorecardKpis` resolves new KPI names via `upsertKpi` (find-or-create on `company_id,name`), so a role card's KPIs stay lossless even if the draft lost its `kpiId`.
- Task 4's Autocomplete is the one genuinely new UI pattern; everything else mirrors existing form/list/dialog code — follow the neighbours rather than inventing.
