# Capability Gates — Design Spec

> Date: 2026-07-21. Design only — **no code until this is approved.**
> Prerequisite for the drop-time warnings on the Balance tab
> ("Christian doesn't meet the gate — Spoken Mandarin required").

## Why this is not just rendering

The proposal that prompted this said the gates already exist in the data model
and only need rendering. They do not. Verified against prod:

| Claim | Reality |
|---|---|
| Tasks carry a capability requirement | `wp_tasks.capability` exists but is **free text, populated on 20 of 282 rows** |
| The vocabulary is usable | Values include `'Spend authority (FAKE gate)'`, `'Judgment — NO Mandarin'`, `'Written Mandarin (soft)'`, `'English only'` |
| People carry capabilities | **Nothing.** No table, no column on `employees` |

`skill_ratings` and `review_skill_ratings` exist but are performance-review
artifacts — a 1–5 score against a review cycle, not "can this person do X".
Reusing them would mean a 3/5 in "Communication" silently deciding whether
someone may own a purchasing task.

So a gate check has **no left-hand side today**. This spec adds one.

## Scope

**In:** a controlled capability vocabulary; who holds which capability; what a
task requires; evaluation at drop time on Balance; migration of the 20
free-text values.

**Out:** proficiency levels (binary hold/not-hold only — see Risk 3);
auto-detection from performance reviews; capability expiry; gating anything
other than the Balance drop (the Tasks tab owner dropdown stays unguarded, see
"Where it surfaces").

## Data model

Three tables. All company-scoped, RLS mirroring `wp_tasks` (company read,
HR/Admin/Super-admin write).

```sql
-- The vocabulary. Free text is what made the current column unusable.
create table wp_capabilities (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null references companies(id) on delete cascade,
  name        text not null,               -- 'Spoken Mandarin'
  kind        text not null default 'SKILL'
              check (kind in ('SKILL','LANGUAGE','AUTHORITY','CERTIFICATION')),
  description text,
  created_at  timestamptz not null default now()
);
create unique index wp_capabilities_uniq
  on wp_capabilities (company_id, lower(trim(name)));

-- Who holds what. Binary: holding it or not.
create table employee_capabilities (
  employee_id   uuid not null references employees(id) on delete cascade,
  capability_id uuid not null references wp_capabilities(id) on delete cascade,
  granted_at    date not null default current_date,
  note          text,
  primary key (employee_id, capability_id)
);

-- What a task requires. Many-to-many: 'Spoken Mandarin + spend authority'
-- is TWO requirements, not one compound string — which is precisely what the
-- current free-text column cannot express.
create table wp_task_capabilities (
  task_id       uuid not null references wp_tasks(id) on delete cascade,
  capability_id uuid not null references wp_capabilities(id) on delete cascade,
  hard          boolean not null default true,
  primary key (task_id, capability_id)
);
```

`hard` distinguishes a blocker from an advisory. The existing data already makes
this distinction — `'Written Mandarin (soft)'` — and collapsing it would either
block legitimate moves or let real blockers through silently.

## Evaluation

Pure, in `capability_gates.dart`, mirroring how `rebalance.dart` keeps the
attribution rule in one place:

```dart
enum GateVerdict { ok, advisory, blocked }

GateResult evaluateGate({
  required String taskId,
  required String employeeId,
  required Map<String, List<TaskCapability>> requiredByTask,
  required Map<String, Set<String>> heldByEmployee,
});
```

- Every hard requirement held → `ok`
- A missing soft requirement only → `advisory`
- Any missing hard requirement → `blocked`, listing which

**A task with no requirements is `ok`.** With 262 of 282 rows carrying no
requirement, defaulting to blocked would make the feature unusable on day one.

## Where it surfaces

**Balance drop only, at first.** `moveError` already refuses uncosted tasks;
gates extend it:

- `blocked` → the drop is refused, naming the missing capability
- `advisory` → the drop succeeds and the task card carries a warning chip until
  Apply, so it is visible in review rather than at the moment of the gesture

Deliberately **not** wired into the Tasks tab's owner dropdown in this phase.
That dropdown is used for bulk data entry during the initial costing pass, and
blocking it before capabilities are recorded would stall that work.

## Migration of the 20 free-text values

Not automatic. The current values conflate capability, negation, and
commentary:

| Current value | Becomes |
|---|---|
| `Spoken Mandarin + authority` | two requirements: `Spoken Mandarin`, `Spend authority` |
| `Written Mandarin (soft)` | `Written Mandarin`, `hard = false` |
| `Judgment — NO Mandarin` | **not a capability** — it asserts the absence of one |
| `Spend authority (FAKE gate)` | test data — drop |
| `English only` | ambiguous: a requirement, or a note that Mandarin is *not* needed? |

So the migration creates the vocabulary and maps only the unambiguous rows,
leaving `wp_tasks.capability` in place as a `legacy_capability_note` for the
rest. **HR resolves the ambiguous ones in the UI.** Guessing here would encode
a gate nobody agreed to, and a wrong hard gate blocks real work.

## What HR must supply

The gates are only as good as the roster behind them. For 8 people:

- who speaks / writes Mandarin
- who holds spend authority, and to what limit (limits are out of scope — model
  as a single `Spend authority` capability for now)
- who has technical depth (emulation, hardware)
- who has Labor Code knowledge

**Until that is recorded, every gate evaluates to `ok`** — the feature is inert
rather than wrong, which is the correct failure mode.

## Risks

1. **A wrong hard gate blocks legitimate work.** Mitigated by defaulting new
   requirements to `hard = false`, and by refusing to guess during migration.
2. **Capability data goes stale** — someone learns Mandarin, nobody updates it.
   No expiry in this phase; `granted_at` is recorded so staleness is at least
   visible.
3. **Binary, not graded.** "Some Mandarin" cannot be expressed. Deliberate:
   proficiency scales invite exactly the argument that stops the roster ever
   being filled in. Revisit only if binary proves insufficient in practice.
4. **Scope creep into performance review.** `employee_capabilities` is an
   operational roster, NOT an appraisal. It must not feed ratings, and
   `skill_ratings` must not feed it.

## Testing

- Pure: every combination of hard/soft × held/not-held; no-requirement → ok;
  unknown employee → blocked, never silently ok.
- Widget: a blocked drop is refused with the capability named; an advisory drop
  succeeds and carries a chip through to Apply.
- Migration on throwaway Postgres: the unambiguous rows map, the ambiguous ones
  are preserved as notes and not silently converted.

## Effort

Migration + models + repo ≈ small. Evaluation + tests ≈ small. The maintenance
screen (who holds what) is the bulk. Balance wiring ≈ small, since `moveError`
is already the single choke point.

**The real cost is not code — it is HR recording the roster.** Nothing works
before that, which is why this is deferred behind the load numbers becoming
trustworthy.
