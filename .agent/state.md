# STATE

Task: drop the EOS vocabulary; fold the chart into an Organization tab
Branch: role-vocabulary (worktree .claude/worktrees/role-vocabulary)
Base: main @ b96125b        Last commit: (this branch's head)
Agent: Claude (2026-08-13)

## Done
- **People Analyzer cancelled** before this branch: quarterly reviews and
  check-ins already capture the same judgement. Branch and 3 commits deleted,
  spec and plan removed from main (`b96125b`). Nothing was applied to any
  database.
- **EOS is no longer the framework.** The direction is a lightweight cascading
  Balanced Scorecard (Company → Department → Role → Person) plus strategic
  workforce planning, with EOS kept only as management rhythm. This branch
  removes the EOS residue:
  1. `3fcde64` — the standalone `/accountability-chart` is folded into the
     Structure tab, now **Organization**. Each person's box lists what their
     role owns. `areasBySeat` → `role_structure.dart`'s `areasByRole`, joined
     by `holderCountByRole`. `seat_tree.dart` and the chart screen are gone;
     `OrgChartView` gained an optional `details` hook. The `>5 roles` chip (a
     pure EOS prescription) is gone; the open-seat chip is now "N roles nobody
     holds".
  2. `1472f1a` — every user-visible "seat" reads "role" again, and
     `role_scorecards.parent_id` is removed with its never-applied migration.
  3. `60cb435` — the Tasks tab is the **Responsibilities** tab, through the
     class, the file and every doc comment.
- Verified on this branch: **1359 passing / 1 skipped**, `flutter analyze lib
  test` 0 errors / 0 warnings / 192 infos.

## In flight
- none. Awaiting the owner's integration decision.

## Decisions
- The Organization tree is `employees.reports_to_id`, not a role-parent tree.
  The role tree existed to model one person holding two seats in different
  branches — an EOS concern that no longer applies — so `parent_id` became
  dead schema and was deleted rather than left dormant.
- The role-details-pane carry-forward guard was RETARGETED, not deleted:
  the pane rebuilds the card field-by-field on save, so a forgotten field
  silently reverts to null, and the model test cannot catch it because
  fromRow/toUpsertPayload round-trip fine while the CALLER drops the value.
  It now pins `shiftTemplateId`.
- The Accountability Chart spec and plan are kept with a SUPERSEDED header
  rather than deleted — the reasoning is still worth reading, the description
  of the app is not.

## Next
- The owner picks: merge to `main` locally, open a PR, or keep the branch.
- Then: write the **Integrated Performance & Workforce Planning** spec —
  cascading Company → Department → Role → Person scorecards, a Desired
  Outcomes layer between responsibility and KPI, and two new fields on every
  KPI definition (Roll-Up Type: direct / aligned / independent; Data Method:
  automatic / hybrid / manual-exception / manual-periodic). Source material:
  the owner's 2026-08-13 message and
  `/home/ccvisionary/Downloads/Luxium_People_Workforce_KPI_App_Update_Spec.docx`.
  The stated planning order is company-first, then department, then role, with
  bottom-up validation against controllability and available data.

## Blockers
- **SHIP ORDER.** THREE migrations must be applied TOGETHER and BEFORE or WITH
  the code, never after: `20260811000001`, `20260811000002`, `20260812000001`.
  (The fourth, `20260813000001`, is deleted by this branch.) Applied by a human
  with `supabase db push`; no agent may run it.

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
