# STATE

Task: Accountability Chart (Plan C) — EOS seats, seat tree, chart screen
Contract: docs/superpowers/plans/2026-08-12-accountability-chart.md
Branch: accountability-chart (worktree .claude/worktrees/accountability-chart)
Base: main @ cfe90a2        Last commit: 320017c
Agent: Claude (subagent-driven; 2026-08-12 → 2026-08-13)

## Done
- All 5 plan tasks implemented, individually reviewed, fix rounds closed.
  Per-task findings and rulings: `.superpowers/sdd/2026-08-12-accountability-chart/progress.md`
  — read that before re-deciding anything; it records WHY, not just what.
  1. Vocabulary: the responsibility card is the SEAT (12 strings, 2 tests).
  2. `role_scorecards.parent_id` + index + cycle-guard trigger, and the
     role details pane now carries `parentId` forward on save (it did not —
     every ordinary "Save Role" wiped the seat's chart placement).
  3. `seat_tree.dart`: `seatBoxes` (one box per ACTIVE holder, sorted by full
     name; exactly ONE open box for a seat with none) and `seatDropError`.
  4. `/accountability-chart` screen, drag-to-reparent, explicit route guard
     at `router.dart:112` (the `/workforce-planning` prefix does NOT cover it).
  5. Two Needs-attention chips: ">5 roles" and "open seats".
- Final whole-branch review: seams clean. One real defect found and fixed
  (deleting a parent seat threw an uncaught FK error at two screens this
  branch never touched) — FK is now `on delete set null`, and both confirm
  dialogs say how many seats will re-root.
- Verified on the final tree, directly: **1377 passing / 1 skipped**,
  `flutter analyze lib test` **0 errors / 0 warnings / 192 infos**.

## In flight
- none. Tree is clean; 12 commits sit on `accountability-chart` awaiting the
  owner's integration decision (merge locally / PR / keep).

## Decisions
- The chart counts a seat's roles from AUTHORED areas (`wp_tasks` via
  `areasBySeat`), NOT `RoleScorecard.responsibilities`, which appends
  shared-in areas and is what the role-card PDF renders. So the chart shows
  fewer roles than the PDF for a seat with shared work — intentional: an EOS
  role is a seat's own accountability, and shared work has its primary owner
  elsewhere. The Needs-attention chip calls the same function so the chip and
  the box can never disagree.
- `on delete set null`, not `cascade` (would delete real seats and their
  holders' role assignment) and not the default `no action` (the bug).
- `toUpsertPayload` always emitting `parent_id` was left alone deliberately —
  see Blockers. It is a release-ordering fact, not a defect, and defending
  against it in code would leave permanent complexity behind a one-time step.

## Next
- The owner picks: merge to `main` locally, open a PR, or keep the branch.
- Then GUI smoke: open `/accountability-chart`, drag a seat onto another,
  confirm the Balance tab's two new chips show real counts, and delete a
  parent seat to confirm its children re-root instead of failing silently.

## Blockers
- **SHIP ORDER.** Four migrations must be applied TOGETHER and BEFORE or WITH
  the code, never after: `20260811000001`, `20260811000002`, `20260812000001`
  (Spec A) and `20260813000001` (this branch). If the code reaches users
  first, every "Save Role" and "New Role" in the app fails with a
  column-not-found error — including HR workflows unrelated to this feature.
  Applied by a human with `supabase db push`; no agent may run it.

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
