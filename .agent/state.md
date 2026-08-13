# STATE

Task: the KPI cascade, definitions half — KPIs gain level/parent/rollup
type/data method and a default target; desired outcomes sit between a
role's accountability areas and its KPIs; a person's KPIs become their
role's KPIs (pure inheritance).
Branch: kpi-cascade (worktree .claude/worktrees/kpi-cascade)
Base: main @ 4c8541c        Last commit: a1132a8, plus this fix wave
Agent: Claude (2026-08-13)

## Done
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
   this fix wave.
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

## Final fix wave (this session, base `a1132a8`)
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

## In flight
None. This branch is complete pending the operator's `supabase db push`
(see Blockers) and a merge decision.

## Decisions
- `dataMethod` default `MANUAL_PERIODIC` is deliberate (see Done §1).
- `role_outcomes`' area link is deliberately unenforced (see Done §3).
- Grandfathering an always-unmeasurable role-KPI link is deliberate
  (see Done §7).
- Pure inheritance was chosen over keeping `employee_kpis` as an override
  layer: a role now defines 2-4 KPIs and whoever holds it inherits them,
  so a new hire is measurable on assignment and a role change moves
  measurement with no per-employee setup. The cost is the one-way door
  in the Blockers section below.

## Next
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
  this branch ships.
- Deferred, not blocking: the searchable `DropdownMenu` typed-filter test
  gap (Done §6) and the grandfathered-link in-app visibility gap
  (Done §7) — both triaged by the whole-branch review as acceptable to
  ship, revisit only if they cause a real support ticket.

## Blockers

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
