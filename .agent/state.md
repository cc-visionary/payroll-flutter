# STATE

Task: the KPI cascade, RESULTS half — turns KPI definitions (the
definitions-half branch, below) into monthly `kpi_results` rows at
Personal/Department/Company scope: automatic sources (attendance, employee
reviews), a manual-input ingestion boundary (`kpi_exceptions`/
`kpi_readings`), the compute engine that turns both into a period's rows
respecting `rollup_type` and role-linked pure inheritance, a monthly Results
screen with Recompute, a Company/Department dashboard, and personal KPI
history surfaced inside the existing quarterly check-in.
Branch: kpi-results (worktree .claude/worktrees/kpi-results)
Base: local main @ 3f49816 (definitions half + the unpaid-leave fix, both
already merged)        Last commit before this fix wave: 742bc16
Agent: Claude (2026-08-14)

## Done

All 10 buildable tasks of
`docs/superpowers/plans/2026-08-13-kpi-cascade-results.md` complete, each
reviewed clean (most after fix rounds). Full blow-by-blow history — five
plan defects (all mine, all the same shape: a default that fails toward MORE
rather than less, e.g. PERCENT needing a denominator nothing supplies, an
unknown level resolving to COMPANY), a raw-NUL-byte review-integrity bug, a
tautology the implementer caught in a brief-supplied test fixture, and every
fix round's RED/GREEN evidence — is
`.superpowers/sdd/2026-08-13-kpi-cascade-results/progress.md`. Read it before
changing anything below; this section is a summary, not a replacement.

1. `evaluateKpi` (`kpi_status.dart`) — value + `KpiStatus` from raw inputs,
   epsilon-toleranced (1e-9) on both GTE and LTE boundaries. `NO_DATA` is not
   a soft failure; it must never render as red.
2. `populationFor` (`kpi_population.dart`) — whose data counts at a scope.
   PERSONAL with no explicit `employeeId` resolves to nobody, never
   everybody — mirrors DEPARTMENT's missing-`departmentId` fail-safe.
3. `scopesFor` (`kpi_rollup.dart`) — which scopes a KPI's `rollup_type`
   produces, widening upward only (SHARED floors at DEPARTMENT so a team
   outcome is never pinned on one person). An unrecognised level computes
   nothing.
4. `kpi_results` table + `KpiResult` + `KpiResultRepository` (migration
   `20260814000004`). Coalesce-expression unique index means NO `onConflict`
   — `upsertAll` reads the period once and finds-then-inserts/updates.
   `kpi_results_write` RLS uses `auth_is_hr_or_admin()` (see this session's
   fix wave, item 1, for why that constant's reach matters).
5. `kpi_exceptions` + `kpi_readings` (migration `20260814000005`) — the
   manual-input ingestion boundary. Two shapes, not one table behind a
   `kind` column. `reported_via`/`external_ref` exist from day one so a
   future Lark sync can write through the same repository methods
   idempotently, even though only the app writes them today.
6. The automatic source registry — `AttendanceLateRateSource` and
   `ReviewsCompletedOnTimeSource` only. Two other sources the owner's KPI
   table named (`critical_vacancy_aging`, `documentation_complete`) were
   DROPPED, not deferred, after the implementer found no schema grounding
   for either — recorded in the registry's own doc comment in those exact
   words so a future reader does not invent a definition to fill the gap.
7. `computeResults` (`compute_kpi_results.dart`) — the engine. Assembly
   only; every rule (`scopesFor`, `populationFor`, `confirmedCountFor`,
   `evaluateKpi`) already has its own tested module. Pure inheritance is
   enforced via `roleKpiLinks` (`role_scorecard_kpis`), a REQUIRED
   parameter with no default — an empty default would have silently
   reproduced "everyone" in reverse ("nobody"). `_scopedExceptions` filters
   to the computed period ONCE, feeding both the confirmed sum and the
   unattributed flag from the same set, after a regression where the two
   drifted apart and one stray row permanently flagged every other month.
8. The monthly Results screen (`kpi_results_screen.dart`, route
   `/kpi-results`) — month picker, scope switch, one row per result, and
   "Recompute this month". `callerSeesAllReviews()` certifies the caller's
   role before `allReviews()` returns anything; an uncertified caller reads
   `null`, which the reviews source reports as NO_DATA rather than a
   silently-undercounted number. A single KPI source's failure is contained
   to that KPI's own row (`_readSource`), not the whole recompute.
9. The Company/Department dashboard (`kpi_dashboard_screen.dart`, route
   `/kpi-dashboard`) — off-track KPIs sorted first via a stable sort keyed
   solely on status priority. `listByPeriod` gained a total `ORDER BY`
   (every identity column, ascending) so two people reading the same month
   see the same order — added at the query, not client-side, so there is
   only one ordering to keep correct.
10. Personal KPI history inside the existing quarterly check-in
    (`performance_check_in_screen.dart`) — the last three months, isolated
    to the employee under review by a provider-level filter. The window
    anchors on `periodOf(period.endDate)` (the quarter under review), NOT
    `createdAt` (the check-in's insertion timestamp) — generation is manual
    and off-cycle, so a Q1 check-in generated in April would otherwise show
    Feb/Mar/Apr instead of Jan/Feb/Mar on the one screen a person reviews
    their own numbers on with their manager.

Task 11 (the manual-entry authoring surface) is UNBUILT and stays gated —
see Blockers.

## Final fix wave (this session, base `742bc16`)

Four items from the whole-branch review, all living in the seams between
tasks — each half correct in isolation, reviewed against a different
authority. All four done:

1. **CRITICAL — PAYROLL_ADMIN Recompute silently destroyed good rows.**
   `UserProfile.isAdmin` (→ `isHrOrAdmin`) includes PAYROLL_ADMIN, so the
   `/kpi-results` route guard admitted it — but
   `ReviewCycleRepository._kFullReviewVisibilityRoles` (mirroring the RLS
   authority `auth_is_performance_admin_for_cycle`) never did. A
   PAYROLL_ADMIN could open the screen, press Recompute, and every
   review-sourced ON_TRACK/OFF_TRACK row at all three scopes for that month
   got overwritten with NO_DATA — silently, with a success snackbar.
   **Decision: PAYROLL_ADMIN should NOT reach Recompute.** The performance
   module's own RLS (`auth_is_performance_admin_for_cycle`,
   20260717000009) deliberately excludes PAYROLL_ADMIN and FINANCE_MANAGER
   — they are payroll-scoped roles, not performance-management roles — and
   that authority cannot be widened without a migration, which is out of
   scope for this wave. So the app-side guard was narrowed to match it,
   not the other way around.
   Fix: `kPerformanceAdminRoleCodes` (`profile_provider.dart`) is now the
   SINGLE constant both sides read — `UserProfile.isPerformanceAdmin`
   (gates the `/kpi-results` route, replacing `isHrOrAdmin` there only;
   every other HR-gated route is unchanged) and
   `ReviewCycleRepository._kFullReviewVisibilityRoles` (now literally
   `= kPerformanceAdminRoleCodes`, not a second hand-written list) both
   derive from it, so the two cannot drift apart again — sharing one
   `const` makes that structural, not merely policed by a test. A test
   exists anyway, on both ends of the seam:
   `test/features/auth/profile_provider_test.dart` (pins
   `isPerformanceAdmin`'s membership and asserts the PAYROLL_ADMIN
   divergence from `isHrOrAdmin` explicitly) and
   `test/data/repositories/review_cycle_repository_test.dart` (drives
   `callerSeesAllReviews()` against a mocked `auth_app_role()` RPC for
   PAYROLL_ADMIN/FINANCE_MANAGER — false — and HR_ADMIN/SUPER_ADMIN —
   true). RED verified by reverting `isPerformanceAdmin` to `isHrOrAdmin`:
   exactly the PAYROLL_ADMIN-shaped assertions failed; restored.
   Residual, out of scope: `kpi_results_write` RLS still uses
   `auth_is_hr_or_admin()`, which DOES admit PAYROLL_ADMIN at the database
   level (deliberately — see that policy's own comment, 20260814000004).
   Narrowing that requires a migration. The app-side fix closes the actual
   defect (nobody can reach Recompute as PAYROLL_ADMIN through the UI
   any more); a direct API caller is a theoretical residual, not this
   wave's finding.

2. **CRITICAL — Department scope was unreachable for every KPI created
   in-app.** `kpi_form_dialog.dart` never rendered a department picker, so
   `_save()` always reconstructed `departmentId: null` regardless of what
   the KPI actually had (Task 6's fix only carried the field through
   round-trips of an edit that never touched it — nothing could set it in
   the first place). `compute_kpi_results.dart` gates a DEPARTMENT row on
   `kpi.departmentId != null`, so a DEPARTMENT/COMPANY-level KPI with
   rollup ALIGNED or INDEPENDENT produced ZERO rows: no row, no error, not
   even NO_DATA — indistinguishable from a KPI nobody created. Only the
   KPIs seeded by migration `20260723000002` could ever produce a
   department row.
   Fixed BOTH halves:
   - `kpi_form_dialog.dart` now has a Department dropdown in the Cascade
     section (`kpis.department_id` already existed on the model and table
     — this exposed a field, did not add one). Guarded against a
     since-deleted department the same way `role_details_pane.dart`
     already does — `_present`/`_persisted`, duplicated rather than
     imported (both private to that file) — because
     `DropdownButtonFormField` asserts exactly one item matches
     `initialValue` and a stale id would otherwise crash the dialog on
     open.
   - `RoleScorecardRepository.saveLibraryKpi` never wrote `department_id`
     to its `fields` map even under `writeCascade: true` — the second half
     of the same defect, harmless only because nothing collected the value
     to begin with. Now writes it (bundled under `writeCascade`, the same
     gate as level/parent/rollup/data-method/target, since it answers the
     same cascade question and has the same one caller).
   - The engine side: a DEPARTMENT-or-wider KPI with no `departmentId` now
     produces a VISIBLE `NO_DATA`/`MISSING_SOURCE` row (`departmentId:
     null` — legal; `kpi_results_identity`'s coalesce-expression index
     already treats null as a normal, unique key) instead of zero rows.
     "Absence must be legible" is this whole plan's own principle; a
     misconfigured KPI vanishing was the one place that principle wasn't
     applied to configuration, only to data.
   Tests: `kpi_library_cascade_test.dart` (picking a department reaches
   `saveLibraryKpi`; an edit that never touches the picker still
   round-trips it), `role_scorecard_kpi_links_test.dart`'s new
   `saveLibraryKpi writeCascade` group (asserts `department_id` in the
   actual Postgrest PATCH body, including the explicit-null-clears-it
   case), `compute_kpi_results_test.dart` (a departmentless DEPARTMENT-level
   KPI produces exactly one visible row). Each RED-verified by reverting
   its half of the fix in isolation and restoring after.

3. **Important — HYBRID dropped the unattributed flag at personal scope.**
   `_confirmedSum` (now deleted) discarded `_scopedExceptions`'
   `excludedUnattributed` and hardcoded `completeness: complete`. A personal
   HYBRID row with an unattributed exception in the period over-reported
   that person's accuracy (the error legitimately can't be subtracted from
   one specific person) AND claimed the source was complete — the exact
   half of an earlier Task 7 finding ("HYBRID was quieter and worse") that
   the original fix never reached; `MANUAL_EXCEPTION` handled it correctly
   the whole time.
   Fix: the HYBRID branch now calls `_scopedExceptions` directly and sets
   `completeness: missingSource` when `excludedUnattributed` is true,
   mirroring `MANUAL_EXCEPTION`'s existing rule. Four new tests in
   `compute_kpi_results_test.dart` mirror all four of `MANUAL_EXCEPTION`'s
   existing unattributed-row tests (COMPANY scope counts it directly and
   stays COMPLETE; PERSONAL scope flags MISSING_SOURCE; a different month
   does not taint the current period; DEPARTMENT scope counts both
   attributed and unattributed). RED-verified on the PERSONAL case by
   reverting to the hardcoded `complete`.

4. This file, rewritten — see below and Blockers.

Verified after all four: `flutter analyze lib test` 0 errors / 0 warnings /
192 infos (unchanged). Full suite: **1484 passing / 1 skipped** (was
1461/1 before this wave).

## In flight

None. Pending the operator's `supabase db push` and a merge decision — see
Blockers.

## Decisions

- PAYROLL_ADMIN does not reach `/kpi-results` or Recompute — see fix wave
  item 1. Widening `auth_is_performance_admin_for_cycle` to include it
  instead would be the opposite call and needs a migration; not taken here.
- A misconfigured DEPARTMENT-or-wider KPI renders a visible NO_DATA row
  rather than vanishing — see fix wave item 2. Consistent with every other
  "absence must be legible" ruling on this plan (Tasks 1-3's fail-toward-
  nothing defaults, Task 8's contained-source-failure).
- `numeratorSource` stays free text with no picker (raised by Task 7's
  reviewer, ruled a KPI Library concern by Tasks 8 and 9, still open — see
  tracked follow-ups).
- Task 11 stays gated on the owner's undecided in-app-vs-Lark call. Do not
  build it without that decision, even if it looks like the only thing left.

## Next

- Operator runs `supabase db push` (Blockers, below) — SEVEN migrations,
  filename order, one run.
- GUI smoke, not yet done: open `/kpi-results`, recompute a month as an
  HR/Admin user, confirm real rows render (not just NO_DATA); confirm a
  PAYROLL_ADMIN account is redirected away from `/kpi-results` instead of
  reaching Recompute; create a KPI with Level=DEPARTMENT and pick a
  department in the new picker, confirm the department row appears after
  a recompute; open `/kpi-dashboard`; open an employee's quarterly check-in
  and confirm the KPI history section shows the right three months.
- Then whole-branch merge (`superpowers:finishing-a-development-branch`),
  informed by this session's review and fix wave.
- Task 11 (manual-entry authoring surface) stays gated — do not dispatch
  until the owner picks in-app vs. Lark.

## Tracked follow-ups (record only — NOT built this session, do not build

  without a separate decision to do so)

- `KpiResultRepository.listByPeriod`/`upsertAll` have no pagination — the
  quarterly check-in's KPI history fetches a whole period THREE TIMES
  (once per month in the window) and would silently render empty under
  PostgREST's `max_rows` cap on a large company. Same class of gap already
  tracked for `attendance`/`payroll_repository`.
- `kpi.numeratorSource` is free text doubling as an exact-match registry
  key for AUTOMATIC/HYBRID KPIs, with no picker and no validation against
  `kpiSourcesProvider`'s known list — an HR typo is indistinguishable from
  a genuinely broken source. Raised by Task 7's reviewer; explicitly ruled
  a KPI Library (`kpi_form_dialog.dart`) concern by both Task 8 and Task 9,
  not a results-screen one.
- The per-KPI `exceptionsFor` calls inside a recompute run SEQUENTIALLY,
  one round trip per KPI, rather than batched — fine at today's KPI counts,
  will not scale silently.
- `MANUAL_PERIODIC` always reports `completeness: complete`, even when no
  reading exists for the period (`numerator`/`denominator` both null) —
  unlike `MANUAL_EXCEPTION`, which reports `missingSource` for the
  equivalent "nothing recorded yet" case. Inconsistent, not yet triaged as
  a defect versus a deliberate difference (a periodic KPI's silence might
  legitimately mean "zero periods have passed," where an exception KPI's
  silence cannot).

## Blockers

**SHIP ORDER — load-bearing, not just chronological.** Apply, in filename
order, as ONE `supabase db push`. This supersedes every earlier version of
this list in this file's history — the definitions-half branch's own
blocker (below, in the demoted section) named only the first four; this
branch adds two more, and the unrelated unpaid-leave fix is ALSO still
unapplied and will ride along in the same push whether or not it is
mentioned, because `db push` applies every pending migration, not a chosen
subset:

1. `20260811000001` (`kpi_measurables`) — pre-existing, unapplied before
   the definitions-half branch.
2. `20260814000001` (`kpi_cascade_fields`) — KPI level/parent/rollup
   type/data method/default target.
3. `20260814000002` (`role_outcomes`) — desired outcomes between a role's
   accountability areas and its KPIs.
4. `20260814000003` (`role_inherited_kpis`) — **DESTROYS PRODUCTION DATA,
   IRREVERSIBLY.** Drops `employee_kpis` (per-employee curated KPI
   subsets) in favour of pure inheritance. Raises a `NOTICE` naming exactly
   what is about to be lost BEFORE the `drop table` runs, while `db push`
   is interactive — the last chance to abort. Full detail, including the
   pre-push check for two now-deleted migration files that may already
   have run against this database, is in the demoted section below; it is
   NOT repeated here, but it still applies and must still be read before
   pushing.
5. `20260814000004` (`kpi_results`) — THIS branch. The derived-results
   table: one row per KPI × period × scope (+ employee/department id).
   `kpi_results_write` RLS uses `auth_is_hr_or_admin()`, which includes
   PAYROLL_ADMIN at the database level — see this session's fix wave item
   1 for why the app-side guard is narrower than that and why that gap is
   accepted, not closed, in this migration.
6. `20260814000005` (`kpi_inputs`) — THIS branch. `kpi_exceptions` +
   `kpi_readings`, the manual-input ingestion boundary Task 11 (still
   unbuilt) will eventually write through, alongside the automatic
   sources that already do.
7. `20260815000001` (`leave_types_unpaid_by_default`) — UNRELATED to KPIs.
   Flips Lark-created leave types to unpaid and changes the column
   default; does not touch released payslips. Its own handover doc,
   `docs/handover/2026-08-15-leave-unpaid-by-default.md`, has the pre-push
   exposure queries and the three post-push steps (deploy the function,
   mark genuinely-paid types in Settings, recompute open runs) — read it
   before this push, since this is the run that will apply it.

**Everything the definitions-half branch's blocker said about the
`employee_kpis` drop, the two deleted-but-possibly-already-applied
migration files, and the pre-push `schema_migrations` check still applies
verbatim and is not repeated above — see "Previous track: kpi-cascade
branch, definitions half" below for the full text.**

Applied by a human via `supabase db push`; no agent may run it.

---

## Previous track (kept, not current): kpi-cascade branch, definitions half

This is the state.md content as it stood at the end of that branch's own
final fix wave (commit `be3b0dc`, merged to local main at `bf05079`), kept
verbatim for its own record — including its own "SHIP ORDER" list, which
the results branch's Blockers section above supersedes with a longer one
rather than editing this copy in place.

Task: the KPI cascade, definitions half — KPIs gain level/parent/rollup
type/data method and a default target; desired outcomes sit between a
role's accountability areas and its KPIs; a person's KPIs become their
role's KPIs (pure inheritance).
Branch: kpi-cascade (worktree .claude/worktrees/kpi-cascade)
Base: main @ 4c8541c        Last commit: a1132a8, plus this fix wave
Agent: Claude (2026-08-13)

### Done
All 7 tasks of `docs/superpowers/plans/2026-08-13-kpi-cascade-definitions.md`
complete, each reviewed clean (some after fix rounds). Full blow-by-blow
history — including two review escapes recovered mid-task and one
disproven claim caught only on re-review — is
`.superpowers/sdd/2026-08-13-kpi-cascade-definitions/progress.md`. Read it
before changing anything below; this section is a summary, not a
replacement.

1. KPI level / parent_kpi_id / rollup_type / data_method / default target
   (migration `20260814000001`). `dataMethod` defaults to `MANUAL_PERIODIC`
   deliberately — the spec names it the type to use LEAST, and the default
   must describe an unclassified KPI honestly rather than claim to be
   automatic. Do not "fix" this default.
2. Cycle/level guard on `parent_kpi_id` (`kpi_parentage.dart`,
   `kpiParentError`) — refuses sideways, downward, self and looping parents;
   fails CLOSED on an unrecognised level on either side.
3. `role_outcomes` between a role's accountability areas and its KPIs
   (migration `20260814000002`). The area link is UNENFORCED BY DESIGN —
   `role_outcomes` keys on `(role_scorecard_id, responsibility_area TEXT)`,
   and areas are not rows, so renaming an area orphans its outcomes
   silently. The outcomes pane surfaces orphans in a labelled, editable,
   deletable section rather than hiding them.
4. Outcomes-authoring pane, staged-edit shape (like `KpisPane`, not
   `ResponsibilitiesPane` — outcomes are free-form prose, not costed rows).
5. `role_scorecard_kpis.outcome_id` linking a KPI to the outcome it proves.
   `ON DELETE SET NULL`, not `RESTRICT` — a KPI proving nothing must stay
   legal.
6. KPI Library screen speaks the cascade: level filter, parent picker
   reusing `kpiParentError` verbatim, cascade fields threaded through
   `KpiFormDialog` on both open and save. The searchable `DropdownMenu` for
   the parent picker is first-of-its-kind in this repo and is covered
   open-and-select only — no typed-filter test. Still open; not part of
   this fix wave. (Now defunct as a "still open" item — the results
   branch's fix wave item 2, above, added the Department picker to this
   same dialog; the parent-picker typed-filter gap itself was never
   revisited and remains untested.)
7. PURE INHERITANCE. `employee_kpis` (a LIVE production table) is dropped;
   `generate_employee_review` is rewritten in the same migration
   (`20260814000003`) to read every KPI on `role_scorecard_kpis` for the
   employee's role, with no per-employee subset or fallback branch. Every
   UI surface that let HR narrow an employee's tracked KPIs (Role tab
   checklist, workbench People pane per-holder editor) is removed. An
   always-unmeasurable role-KPI link is grandfathered forever, with no
   in-app path to block it beyond defining the KPI properly — ruled
   coherent, not a gap in disguise (blocking it would break five
   legacy-coexistence tests). Still open; not part of this fix wave.

### Final fix wave (that session, base `a1132a8`)
Three items from the whole-branch review, all done:

1. This file rewritten to describe the present branch instead of the
   stale `role-vocabulary` snapshot it still carried (see Blockers below
   for what was wrong and why it mattered).
2. The disproven "confirmed via git history" claim in commit `13c1fc3`
   corrected here, since that commit's message cannot be rewritten (see
   Blockers below).
3. `kpi_form_dialog.dart:140` (now shifted a line) now threads
   `Kpi.departmentId` through `_save()`'s reconstruction — the one field
   Task 6's landmine fix didn't cover, harmless only because
   `saveLibraryKpi` never wrote that column. A new test in
   `kpi_library_cascade_test.dart` pumps `KpiFormDialog` directly (not
   through `KpiLibraryScreen`, since `departmentId` never reaches
   `saveLibraryKpi`), edits only the name, and asserts the POPPED `Kpi`'s
   `departmentId` VALUE equals the original — not key presence, which the
   pre-fix version would also satisfy (a defaulted `null` is still a
   present key). Confirmed the test fails without the fix (reconstructed
   `Kpi` defaults `departmentId` to `null`) and passes with it.

Verified: `flutter analyze lib test` 0 errors / 0 warnings / 192 infos.
Full suite 1365 passing / 1 skipped (was 1364/1 at `a1132a8`; +1 for the
new `departmentId` test).

### In flight (at that point)
None. That branch was complete pending the operator's `supabase db push`
and a merge decision — both of which happened (merged to local main at
`bf05079`); the push did not, which is why its ship order is repeated
below.

### Decisions
- `dataMethod` default `MANUAL_PERIODIC` is deliberate (see Done §1).
- `role_outcomes`' area link is deliberately unenforced (see Done §3).
- Grandfathering an always-unmeasurable role-KPI link is deliberate
  (see Done §7).
- Pure inheritance was chosen over keeping `employee_kpis` as an override
  layer: a role now defines 2-4 KPIs and whoever holds it inherits them,
  so a new hire is measurable on assignment and a role change moves
  measurement with no per-employee setup. The cost is the one-way door
  in the Blockers section below.

### Next (at that point — superseded by the results branch's own Next,
  above)
- Operator runs the pre-push check and `supabase db push` (Blockers,
  below).
- GUI smoke: open the KPI Library, edit an existing KPI's cascade fields
  and department, confirm they persist; open a role's Outcomes tab and
  KPIs tab, confirm outcome linking and inherited-KPI read-out; generate
  an employee review and confirm every role KPI appears with no
  per-employee filtering.
- Then whole-branch merge (`superpowers:finishing-a-development-branch`).
- The results plan (11 tasks, not yet written) must not start until this
  branch is applied to production and merged — it builds on the schema
  this branch ships. (This happened: the results branch above is that
  plan, built against the merged-but-not-yet-pushed schema.)
- Deferred, not blocking: the searchable `DropdownMenu` typed-filter test
  gap (Done §6) and the grandfathered-link in-app visibility gap
  (Done §7) — both triaged by the whole-branch review as acceptable to
  ship, revisit only if they cause a real support ticket.

### Blockers (at that point — the first four items of the results
  branch's longer ship order, above; kept verbatim for the full
  `employee_kpis` reasoning, which the results branch's Blockers section
  references rather than repeats)

**SHIP ORDER — load-bearing, not just chronological.** Apply, in filename
order, as ONE `supabase db push`:

1. `20260811000001` (`kpi_measurables` — pre-existing, unapplied before
   this branch)
2. `20260814000001` (`kpi_cascade_fields`)
3. `20260814000002` (`role_outcomes`)
4. `20260814000003` (`role_inherited_kpis`)

The order is load-bearing because `20260811000001` READS `employee_kpis`
at line 131 (a `not exists (select 1 from employee_kpis ek where
ek.kpi_id = k.id)` guard inside its cleanup loop), and `20260814000003`
DROPS `employee_kpis`. Applied out of that order, `20260811000001` fails
against a table that no longer exists.

This branch DELETES two migrations a prior local session had already
authored and committed to local `main` — `20260811000002` and
`20260812000001` — replacing that design (a stored, authoritative
per-employee subset) with pure inheritance. They are gone from this
branch's migration directory entirely; they are not in the ship order
above and must not be applied.

**`20260814000003` DESTROYS PRODUCTION DATA — irreversibly.** It drops
`employee_kpis`, which let HR curate a SUBSET of a role's KPIs for one
employee. Pure inheritance replaces that: every holder of a role now
tracks ALL of that role's KPIs, with no per-employee override. Before the
`drop table`, the migration runs a `do $$ ... end $$` block that queries
`employee_kpis` and RAISES A NOTICE stating exactly what is about to be
lost, e.g.:

    NOTICE: employee_kpis: about to drop N row(s) covering M distinct
    employee(s). This is irreversible -- every employee with a curated
    subset widens to their full role set.

That notice prints BEFORE the `drop table if exists employee_kpis` runs,
while `supabase db push` is interactive — it is the last chance to
abort (Ctrl-C) before the table is gone. If `employee_kpis` is already
absent (e.g. a retried push after a successful first run), it instead
prints "employee_kpis already dropped -- nothing to announce" and the
drop is a no-op — the whole migration is safe to re-run.

**Blast radius, stated honestly.** The now-deleted `20260811000002`
contained a backfill `insert into employee_kpis`. If that migration ever
ran against this environment, every employee whose role gained a KPI
after 2026-08-11 is CURRENTLY NARROWED to a stale curated subset, and
`20260814000003`'s drop WIDENS them back to their full role set. That is
the intended direction and is behaviour-safe — widening can only add a
tracked KPI, never silently remove one someone depends on — but it is a
wider blast radius than "deliberately HR-curated subsets" alone would
suggest, and the operator should know that before treating the notice
above as routine.

**A disproven claim sits in git history where it will be read — corrected
here, since the commit itself cannot be rewritten.** Commit `13c1fc3`
(which deletes the unapplied-looking files `20260811000002` and
`20260812000001`) asserts they were "deleted as unapplied files,
confirmed via git history." That reasoning is FALSE, and was caught in
review (see `3b19965`'s message and this Task 7's entry in
`progress.md`): both migrations ARE present on local `main` (`bf8163e`,
`2eb9126`) — only `origin/main` lacks them — and `supabase db push`
applies from a LOCAL checkout, not from git history or from origin. Git
history alone cannot answer whether either one already ran against
production. Only `3b19965`'s commit message carries this correction;
`13c1fc3`'s does not and cannot be edited after the fact. This paragraph
is the copy an operator will actually see before running anything.

**RUN THIS FIRST, before `supabase db push`** — a runnable check, not a
description of one:

    select version from supabase_migrations.schema_migrations
    where version in ('20260811000002', '20260812000001');

- Returns NO ROWS: neither migration ever ran against this database.
  Proceed with the ship order above.
- Returns ONE OR BOTH versions: that migration DID run against
  production, under a filename this branch has now deleted from the
  local migration directory. `supabase db push` will see a mismatch
  between the local migration set and production's recorded history and
  WILL ABORT rather than push anything. Before retrying, run, for each
  returned version:

      supabase migration repair --status reverted <version>

  This only edits Supabase's migration bookkeeping (`schema_migrations`)
  to say the version is no longer part of the local set; it does not
  touch any table those migrations created or altered — the
  `employee_kpis` backfill blast radius above already accounts for that
  case. Only after `repair` succeeds for every returned version should
  `db push` be retried.

  Skipping this check does not fail loudly and instantly — it fails as a
  confusing partial push, possibly after earlier migrations in the batch
  have already applied. Running the query first turns that into a
  five-minute, well-understood repair-then-push.

Applied by a human via `supabase db push`; no agent may run it.

---

## Previous track (kept, not current): role-vocabulary branch, EOS removal

This was the state of local `main` when the `kpi-cascade` branch forked
(base `4c8541c`); no commit on `kpi-cascade` touched this section, and it
went stale relative to this branch's own ship order above (which
supersedes the three-migration list this section used to name). Kept
verbatim below for its own record, not for its blocker list, which no
longer applies.

- **People Analyzer cancelled** before this branch: quarterly reviews and
  check-ins already capture the same judgement. Branch and 3 commits
  deleted, spec and plan removed from main (`b96125b`). Nothing was
  applied to any database.
- **EOS is no longer the framework.** The direction is a lightweight
  cascading Balanced Scorecard (Company → Department → Role → Person)
  plus strategic workforce planning, with EOS kept only as management
  rhythm. That branch removed the EOS residue:
  1. `3fcde64` — the standalone `/accountability-chart` folded into the
     Structure tab, now **Organization**. Each person's box lists what
     their role owns. `areasBySeat` → `role_structure.dart`'s
     `areasByRole`, joined by `holderCountByRole`. `seat_tree.dart` and
     the chart screen are gone; `OrgChartView` gained an optional
     `details` hook. The `>5 roles` chip (a pure EOS prescription) is
     gone; the open-seat chip is now "N roles nobody holds".
  2. `1472f1a` — every user-visible "seat" reads "role" again, and
     `role_scorecards.parent_id` is removed with its never-applied
     migration.
  3. `60cb435` — the Tasks tab is the **Responsibilities** tab, through
     the class, the file and every doc comment.
- Verified on that branch: 1359 passing / 1 skipped, `flutter analyze lib
  test` 0 errors / 0 warnings / 192 infos.
- The Organization tree is `employees.reports_to_id`, not a role-parent
  tree — modelling one person holding two seats in different branches was
  an EOS concern that no longer applies, so `parent_id` became dead
  schema and was deleted rather than left dormant.
- The Accountability Chart spec and plan are kept with a SUPERSEDED
  header rather than deleted — the reasoning is still worth reading, the
  description of the app is not.

---

## Previous track (kept, not current): TASK-001 deterministic verification gate

Contract: docs/tasks/TASK-001.json — Branch main, last commit f0bbc91
(2026-08-06 → 2026-08-10). Superseded as the active task, not cancelled.

- `scripts/verify.sh` (format / analyze / test gate) is GREEN end to end.
- `dart format .` run once and committed alone (4ada116, 438 files); sha in
  `.git-blame-ignore-revs`, `blame.ignoreRevsFile` configured.
- All 19 analyzer warnings cleared (f0bbc91). `_SortOrder`'s 11 unused sort
  codes were KEPT behind a documented `ignore_for_file: unused_field` — they
  hold slots in a numbering scheme mirrored from payrollos.
- Analyze gate runs `--no-fatal-infos`; warnings/errors stay fatal. Proved
  still-failing on a planted `unused_field` (exit 1), so it is not a rubber
  stamp.
- Explore stage ran for real against TASK-001 (2026-08-10), exit 0, artifact
  valid, no worktree left behind.
- Gemini is unusable on this machine (Gemini Code Assist discontinued for
  individuals; OAuth returns IneligibleTierError). `explorer` and
  `reviewer_secondary` were rebound to read-only codex; no role is bound to
  Gemini any more. Retired, not fixed.
- Next for that track, if resumed: run the `plan` stage against TASK-001.
