# Performance MVP — Quarterly + Probationary Reviews

**Date:** 2026-05-31
**Status:** Draft, pending user review
**Owner:** payroll-flutter

## Summary

Activate the dormant `check_in_periods` + `performance_check_ins` + `check_in_goals` + `skill_ratings` schema (shipped 2026-04-14) as a structured review system. Two cadences:

- **REGULAR employees**: one quarterly company-wide period (Q1/Q2/Q3/Q4); one check-in per employee per quarter.
- **PROBATIONARY employees**: three individual review milestones at month 1, month 3, month 5 from `hire_date` (the 5-month review is the regularization decision point).

Periods are auto-generated on visit (lazy) rather than via cron — when HR opens `/performance`, the system ensures the right periods + check-ins exist for the current quarter and for any probationary milestones that have passed. Each check-in auto-seeds `skill_ratings` from the employee's RoleScorecard KPIs, with HR free to add/remove skills per check-in. The flow ties the entire feature stack together: applicant hired with a scorecard → reviewed against that exact scorecard → regularization decision at month 5 → quarterly cadence after regularization.

## Motivation

Today, performance reviews at Luxium are vibes. There's no written record of who scored what against which KPIs, and the probationary regularization decision (the most consequential people decision Brixter makes) runs on Brixter's memory of a few Lark exchanges. Specifically:

- **No KPI-anchored review record** — Responsibility Cards define KPIs but nobody scores against them. Raises and 13th-month merit splits run on impressions.
- **Probation slips through cracks** — the 5-month review is the legal regularization deadline; missing it means the employee auto-regularizes by Article 296 of the Labor Code with no documentation. Currently tracked manually.
- **No history feeding compensation decisions** — the company can't show "this employee scored 4.5/5 for three cycles" when justifying a raise.

The schema is all there. This MVP wires it.

## Decisions locked from brainstorm

1. **Period creation**: auto-generated on visit (no cron job, no manual form in v1).
2. **Cadence — REGULAR**: quarterly only (4 cycles/year).
3. **Cadence — PROBATIONARY** (user-added requirement): three per-employee milestones at month 1, month 3, month 5 from `hire_date`. The 5-month review is the regularization decision.
4. **Reviewer assignment**: picker at check-in creation; defaults to `employees.reports_to_id` (the employee's manager) when set; falls back to user-selectable.
5. **Skill seeding**: auto-seed `skill_ratings` from the employee's `RoleScorecard.kpis` at check-in creation time (snapshotting `KpiItem.metric` into `skill_name` so historical reviews don't drift when KPIs are later edited). HR can add custom skills or remove auto-seeded ones via the UI.
6. **30-day handoff with Workflows**: deferred to v2. The HIRING workflow's "30-day check-in completed" STATUS_UPDATE step stays a manual checkbox; the new hire's first formal `performance_check_in` lands at the 1-month probationary milestone (if PROBATIONARY) or the next quarter (if REGULAR).

## Scope (in)

1. Schema migration (small): extend `check_in_periods` to support per-employee probationary periods.
2. Dart models (`CheckInPeriod`, `PerformanceCheckIn`, `CheckInGoal`, `SkillRating`) with `fromRow` factories.
3. `PerformanceRepository` (list / byId / stepsForInstance equivalents + auto-gen + status transitions).
4. **Auto-generation logic** invoked lazily on `/performance` visit:
   - Ensure the current quarter's company-wide QUARTERLY period exists.
   - For each REGULAR active employee, ensure a check-in exists in that period (skill_ratings auto-seeded from scorecard).
   - For each PROBATIONARY active employee, for each milestone (1M/3M/5M from `hire_date`) that has passed: ensure an employee-specific period exists + a check-in in it.
5. `/performance` list screen — current quarter + active probationary milestones, filterable by status/employee.
6. `/performance/:id` detail screen — single check-in editor with sections: Goals, Skill Ratings, Reflection (employee self-review), Manager Review.
7. Status flow: DRAFT → SUBMITTED → UNDER_REVIEW → COMPLETED, plus manual SKIPPED.
8. Permissions:
   - HR/Admin: full read/write.
   - Employee (self): edit own self-review sections while status ≤ SUBMITTED.
   - Manager (`reviewer_id` matches current user): edit manager sections while status ≤ UNDER_REVIEW.
9. `/employees/:id/profile` Performance tab — read-only history of the employee's check-ins, newest first.
10. Nav: unhide `/performance` (currently `comingSoon: true`).

## Scope (out — v2 or later)

- **360 / multi-reviewer reviews** — schema has single `reviewer_id`. v2.
- **Calibration view** across managers to flatten rater drift.
- **1:1 agendas** — separate schema not present.
- **Department-scoped periods** — `check_in_periods` is company-scoped; cross-department cadence differentiation deferred.
- **PDF export** of completed check-ins.
- **Compensation auto-feed** — completed cycles feeding raise/13th-month decisions.
- **Lark notifications** on status transitions.
- **30-day onboarding handoff** with HIRING workflow.
- **Manual period creation form** (HR triggers an off-cycle review).
- **Promotion-readiness badge** on profile header.

## Integration principle (carry-over)

Same hard rule from Hiring + Workflows: **reuse FKs, never duplicate data.**

- `performance_check_ins.employee_id` is the FK — no employee data copies.
- `performance_check_ins.reviewer_id` references `users.id` — no copy.
- `performance_check_ins.period_id` references `check_in_periods.id` — period data lives once.
- `skill_ratings.skill_name` IS a snapshot of `RoleScorecard.kpis[i].metric` at check-in creation. This is INTENTIONAL — historical reviews must not drift when KPIs are later edited. This is the one deliberate exception, called out by name.
- `check_in_goals.check_in_id` is a strong FK with `on delete cascade`.

## Data model

### Existing schema (`supabase/migrations/20260414000012_performance.sql`)

**`check_in_periods`**: id, company_id, name, period_type (enum), start_date, end_date, due_date, is_active.
Constraint: `unique (company_id, name)`. Currently company-wide only.

**`performance_check_ins`**: id, period_id, employee_id, reviewer_id, status (enum), overall_rating, overall_comments, accomplishments, challenges, learnings, support_needed, manager_feedback, strengths, areas_for_improvement, submitted_at, reviewed_at.
Constraint: `unique (period_id, employee_id)`.

**`check_in_goals`**: id, check_in_id, goal_type (enum), title, description, target_date, progress, status (enum), self_assessment, manager_assessment, rating, carry_forward.

**`skill_ratings`**: id, check_in_id, skill_category, skill_name, self_rating, manager_rating, comments, development_plan.
Constraint: `unique (check_in_id, skill_category, skill_name)`.

**Enums**:
- `check_in_type`: MONTHLY, QUARTERLY, ANNUAL
- `check_in_status`: DRAFT, SUBMITTED, UNDER_REVIEW, COMPLETED, SKIPPED
- `goal_type`: PERFORMANCE, LEARNING, PROJECT, BEHAVIORAL
- `goal_status`: NOT_STARTED, IN_PROGRESS, COMPLETED, PARTIALLY_MET, NOT_MET, DEFERRED

### Required migration (one new file)

`supabase/migrations/20260531000001_performance_per_employee_periods.sql`:

```sql
-- Support per-employee probationary review periods. The existing
-- check_in_periods table is company-scoped (one period per Q1/Q2/Q3/Q4
-- for the whole company). Probationary reviews are individual milestones
-- tied to each employee's hire_date (month 1, 3, 5), so we need
-- employee-specific periods alongside the company-wide quarterly ones.

-- Add the three probationary period types to the enum.
alter type check_in_type add value if not exists 'PROBATION_1M';
alter type check_in_type add value if not exists 'PROBATION_3M';
alter type check_in_type add value if not exists 'PROBATION_5M';

-- A nullable employee FK on the period. Null = company-wide (existing
-- behavior, used for quarterly cycles). Non-null = scoped to that one
-- employee (used for the 3 probationary milestones).
alter table check_in_periods
  add column target_employee_id uuid references employees(id) on delete cascade;

-- Replace the company+name unique with a 3-column unique so company-wide
-- periods (target_employee_id = null) still get a single row per name,
-- AND per-employee periods can reuse names like "Probation 1M" across
-- different employees.
alter table check_in_periods drop constraint check_in_periods_company_id_name_key;
alter table check_in_periods
  add constraint check_in_periods_company_name_target_unique
  unique (company_id, name, target_employee_id);
create index on check_in_periods (target_employee_id);
```

## Architecture

### Models — `lib/data/models/`
Standard Dart classes mirroring each table. `fromRow` factories. No `copyWith` initially. Pattern matches WorkflowInstance / Applicant.

- `check_in_period.dart` — `CheckInPeriod` + `CheckInPeriodFromRow`
- `performance_check_in.dart` — `PerformanceCheckIn` + `PerformanceCheckInFromRow`
- `check_in_goal.dart` — `CheckInGoal` + `CheckInGoalFromRow`
- `skill_rating.dart` — `SkillRating` + `SkillRatingFromRow`

### Repository — `lib/data/repositories/performance_repository.dart`

`PerformanceListQuery({periodId, employeeId, statuses, includeProbation, includeQuarterly})` value class.

Methods:

- `currentQuarterPeriod(companyId)` → returns the existing or null. Helper for the auto-gen logic.
- `ensureQuarterlyPeriodForCurrentQuarter(companyId, initiatedById)` → idempotent INSERT-or-RETURN. Computes Q1/Q2/Q3/Q4 dates from `DateTime.now()`, names the period `"YYYY Q#"`, period_type=QUARTERLY, target_employee_id=null. Returns the period id.
- `ensureProbationaryPeriodsForEmployee(employee, initiatedById)` → for each milestone (1M/3M/5M) whose target date is `≤ now`, ensure a row exists with target_employee_id=employee.id, name=`"Probation {1M|3M|5M} — {employee.fullName}"`, period_type=PROBATION_*, dates derived from hire_date + offset. Returns a list of period ids.
- `ensureCheckInForEmployeeInPeriod({periodId, employeeId, reviewerId})` → idempotent. If a check-in already exists for `(period_id, employee_id)`, return its id. Otherwise INSERT with status=DRAFT, then call `_seedSkillRatingsFromScorecard(checkInId, employee)`.
- `_seedSkillRatingsFromScorecard(checkInId, employee)` → reads the employee's `role_scorecard_id`. Fetches the scorecard. For each `KpiItem`, inserts one `skill_ratings` row with `skill_category='KPI'`, `skill_name=kpi.metric` (snapshot at this moment), `self_rating=null`, `manager_rating=null`. Idempotent via the table's unique constraint.
- `list(PerformanceListQuery)` → returns a list of check-ins (joined with employee + period via providers in the UI layer).
- `byId(id)` → single check-in.
- `goalsFor(checkInId)`, `skillRatingsFor(checkInId)` — separate fetches.
- `addGoal({checkInId, goalType, title, description, targetDate})` → INSERT into `check_in_goals`.
- `updateGoal({goalId, ...})` — partial update.
- `addSkill({checkInId, category, name})` → INSERT into `skill_ratings`. HR-triggered.
- `removeSkill(skillId)` → DELETE.
- `updateSkill({skillId, selfRating?, managerRating?, comments?, developmentPlan?})` — partial update.
- `updateCheckIn({checkInId, status?, accomplishments?, challenges?, learnings?, supportNeeded?, managerFeedback?, strengths?, areasForImprovement?, overallRating?, overallComments?})` — partial update. When `status='SUBMITTED'`, stamp `submitted_at = now()`. When `status='COMPLETED'`, stamp `reviewed_at = now()`. Validate transitions (throw `IllegalTransition`).

Providers: `currentQuarterCheckInsProvider`, `checkInByIdProvider(id)`, `checkInsForEmployeeProvider(employeeId)`, `goalsForCheckInProvider(id)`, `skillRatingsForCheckInProvider(id)`.

### Auto-gen logic — `lib/features/performance/auto_generate.dart`

A pure(-ish) function called once when `/performance` is opened:

```dart
Future<void> autoGenerateForCurrentQuarter(WidgetRef ref) async {
  final profile = (await ref.read(userProfileProvider.future))!;
  final repo = ref.read(performanceRepositoryProvider);
  // 1. Ensure the quarterly period for this quarter exists.
  final quarterlyPeriodId = await repo.ensureQuarterlyPeriodForCurrentQuarter(profile.companyId!, profile.userId);
  // 2. For each active employee, generate the right check-ins.
  final employees = await ref.read(employeeListProvider(const EmployeeListQuery()).future);
  for (final emp in employees) {
    if (emp.employmentStatus != 'ACTIVE') continue;
    final reviewerId = emp.reportsToId;  // null is fine
    if (emp.employmentType == 'REGULAR') {
      await repo.ensureCheckInForEmployeeInPeriod(
        periodId: quarterlyPeriodId,
        employeeId: emp.id,
        reviewerId: reviewerId,
      );
    } else if (emp.employmentType == 'PROBATIONARY') {
      final periodIds = await repo.ensureProbationaryPeriodsForEmployee(emp, profile.userId);
      for (final pid in periodIds) {
        await repo.ensureCheckInForEmployeeInPeriod(
          periodId: pid,
          employeeId: emp.id,
          reviewerId: reviewerId,
        );
      }
    }
    // Other employment_types (CONTRACTUAL, CONSULTANT, INTERN, SEASONAL, CASUAL) skipped in v1.
  }
}
```

Lazy: runs once per `/performance` mount (with a state guard to avoid re-running on every rebuild). Idempotent at every step. If it fails mid-loop (one employee errors), the others still get their periods/check-ins.

**Performance consideration**: at ~10 employees this is 10-30 cheap SELECT-then-maybe-INSERT calls. Fine. At 100+ employees, batch this — but that's a v2 problem.

### Screens

#### `/performance` — list screen
`lib/features/performance/performance_screen.dart`. ConsumerStatefulWidget.

- Permission gate: `profile.isHrOrAdmin` OR `profile.employeeId != null` (employees see their own).
- On mount: call `autoGenerateForCurrentQuarter(ref)` once.
- Top filter bar (Wrap of FilterChips):
  - Status: DRAFT, SUBMITTED, UNDER_REVIEW, COMPLETED (default: all except COMPLETED — HR usually wants the "still in flight" list).
  - Period: dropdown of recent periods (default: current quarter).
  - Employee: autocomplete (HR only — employees see their own automatically).
- Body: a Card-per-check-in list:
  - Employee name + role (resolved from RoleScorecard.jobTitle)
  - Period name + period_type chip
  - Status chip
  - Reviewer name (resolved from users / employees by reviewerId)
  - Action: "Open" → push `/performance/:id`
- "Refresh" affordance to re-run `autoGenerateForCurrentQuarter`.

#### `/performance/:id` — detail screen
`lib/features/performance/performance_check_in_screen.dart`. ConsumerStatefulWidget.

Header: employee name, role, period name + dates, status chip, reviewer.

Tabs OR scrollable sections (decide at implementation time based on density):

1. **Self-review** (employee writes; HR/manager read-only when status > DRAFT):
   - Accomplishments (multi-line)
   - Challenges (multi-line)
   - Learnings (multi-line)
   - Support needed (multi-line)

2. **Goals** — list of `check_in_goals` for this check-in. Inline editor per goal:
   - Title, description, goal_type chip, target_date, progress (0-100 slider), status enum dropdown, self_assessment (employee), manager_assessment (manager), rating (manager, 1-5), carry_forward toggle.
   - "Add goal" button (HR/employee).
   - Delete goal (HR only).

3. **Skill ratings** — auto-seeded from scorecard, editable. Each row:
   - skill_category (default "KPI" for auto-seeded; HR can set "BEHAVIORAL" / "TECHNICAL" / etc. for manual ones)
   - skill_name (read-only after seed)
   - self_rating (1-5, employee)
   - manager_rating (1-5, manager)
   - comments
   - development_plan
   - "Add skill" (HR — for non-KPI competencies)
   - "Remove" (HR — for irrelevant auto-seeded skills)

4. **Manager review** (manager writes; visible to employee after status COMPLETED):
   - Manager feedback
   - Strengths
   - Areas for improvement
   - Overall rating (1-5 stepper)
   - Overall comments

5. **Status actions** (footer):
   - If status == DRAFT and viewer is employee: "Submit for review" button → flips to SUBMITTED, stamps `submitted_at`.
   - If status == SUBMITTED and viewer is reviewer/HR: "Start review" button → flips to UNDER_REVIEW.
   - If status == UNDER_REVIEW and viewer is reviewer/HR: "Mark complete" button → flips to COMPLETED, stamps `reviewed_at`.
   - HR-only: "Skip this cycle" → flips to SKIPPED with optional remarks.

#### Employee profile Performance tab
`lib/features/employees/profile/tabs/performance_tab.dart`. Read-only history.

- Header: "Performance history for {employee.fullName}".
- List of check-ins newest-first: period name, period_type chip, status chip, overall_rating (if completed), submitted_at, reviewed_at.
- Click row → `/performance/:id`.

#### Nav + routing
- `lib/app/router.dart`: add `/performance/:id` route alongside existing `/performance`.
- `lib/app/shell.dart`: remove `comingSoon: true` from the Performance nav item (around line 105).

### Status flow

```
DRAFT ──submit──▶ SUBMITTED ──start review──▶ UNDER_REVIEW ──complete──▶ COMPLETED
  │                  │                            │
  └───skip───────────┴────skip───────────────────┘
                                                  ▼
                                              SKIPPED
```

Validate transitions in repo (mirrors Applicant's `validateTransition`). HR can skip from any non-terminal state with required reason.

### Permissions matrix

| Viewer | DRAFT | SUBMITTED | UNDER_REVIEW | COMPLETED |
|---|---|---|---|---|
| HR/Admin | read+write everything | read+write everything | read+write everything | read everything |
| Reviewer (own check-in's reviewer_id) | read self-review fields, write manager fields | read self-review fields, write manager fields | read self-review fields, write manager fields | read everything |
| Employee (own check-in) | read+write self-review fields | read self-review (locked), wait | read self-review (locked), wait | read everything (including manager feedback) |
| Other employees | no access | no access | no access | no access |

RLS on the tables already restricts to HR/Admin + the employee themselves. App-level field-gating enforces the matrix.

## Auto-generation triggers — single source of truth

The auto-gen function runs ONLY when `/performance` is opened (lazy). It does NOT run:
- On app start.
- On every check-in detail page visit.
- On employee creation (no kickoff hook in this MVP — the employee gets their first check-in on next `/performance` visit).
- From the HIRING workflow's 30-day step (deferred to v2).

If HR never visits `/performance`, periods never get created. That's an acceptable tradeoff for v1 simplicity. A small startup-time check ("hey, you haven't visited Performance in a while") can land in v2.

## Testing

- **Models**: `fromRow` round-trip tests for each of the 4 models.
- **Repository — auto-gen**: 
  - Pure-function-style test for `ensureQuarterlyPeriodForCurrentQuarter` (idempotent, returns same id on second call).
  - Probationary milestone calculation: hire_date = 2026-01-01 → 1M = 2026-02-01, 3M = 2026-04-01, 5M = 2026-06-01.
- **Skill seeding**: given an employee with a scorecard containing 3 KPIs, `_seedSkillRatingsFromScorecard` inserts 3 rows with the right `skill_name` snapshot.
- **Status transitions**: validate DRAFT→SUBMITTED→UNDER_REVIEW→COMPLETED, reject DRAFT→COMPLETED, reject UNDER_REVIEW→DRAFT.
- **UI smoke**: list screen renders with mock data, detail screen renders all sections, action buttons appear based on viewer role.

## Phases (for the implementation plan)

1. **Migration** — add probationary enums + `target_employee_id`.
2. **Models** — 4 model files with `fromRow` + round-trip tests.
3. **Repository scaffold** — `PerformanceRepository` + `PerformanceListQuery` + provider.
4. **Read methods** — list / byId / goalsFor / skillRatingsFor + providers.
5. **Period auto-gen** — `ensureQuarterlyPeriodForCurrentQuarter` + `ensureProbationaryPeriodsForEmployee` + tests.
6. **Check-in auto-gen + skill seeding** — `ensureCheckInForEmployeeInPeriod` + `_seedSkillRatingsFromScorecard`.
7. **Status + transition validation** — mirror Applicant's validateTransition.
8. **Goal + skill CRUD** — add/update/remove for both.
9. **`/performance` list screen** — replace stub, filter bar, list, mount-time auto-gen.
10. **`/performance/:id` detail screen scaffold** — header + 5 section placeholders.
11. **Self-review section** — accomplishments/challenges/learnings/support_needed.
12. **Goals section** — list + inline editor + add/remove.
13. **Skill ratings section** — list + edit ratings + add custom + remove.
14. **Manager review section** — feedback/strengths/areas/overall.
15. **Status actions footer** — Submit / Start review / Complete / Skip.
16. **Employee profile Performance tab** — read-only history.
17. **Nav unhide + final green-bar verification**.

Estimated 17 tasks. ~2-3 sessions of subagent-driven work.

## Open questions (resolve at plan time, not now)

1. **Tabs vs scrollable single page on the detail screen**: density of all 5 sections suggests tabs would help, but the Hiring detail screen uses a single scroll. Pick at implementation time based on screen real estate.
2. **`reports_to_id` field on Employee**: verified to exist (Employee model has `reportsToId`). The auto-gen uses this directly.
3. **Probationary milestone calculation when hire_date includes a leap day or end-of-month**: e.g. hire_date = 2026-01-31, 1M = ? Use Dart's `DateTime` add-months semantics (clamps to end of month if target month is shorter). Acceptable for v1.
4. **What if an employee was REGULAR all quarter, then went PROBATIONARY mid-cycle?** Edge case — the auto-gen reads current `employmentType` so they'd get a regular Q-check-in AND probationary milestones going forward. The two coexist cleanly because they use different periods. No deduplication needed.

## Risks

- **Idempotency of auto-gen**: every step must be a no-op on second invocation. Tested per method. If a transient error mid-loop leaves orphan periods without check-ins, the next `/performance` visit completes the work.
- **Period dates for probationary milestones**: the schema requires `start_date <= end_date <= due_date`. For a 1-month milestone period, what does "start" mean? Design: start_date = hire_date + offset - 14 days (window opens 2 weeks before milestone); end_date = hire_date + offset; due_date = hire_date + offset + 7 days (HR has a week to complete the review).
- **`reports_to_id` not populated**: the auto-gen sets `reviewer_id = null` when manager is unknown. HR can pick manually from the check-in detail. Surfaces as "Reviewer: —" in the list — flagged but not blocked.
- **Scorecard changes mid-cycle**: `skill_ratings.skill_name` is snapshotted at check-in creation. Subsequent edits to `RoleScorecard.kpis[i].metric` do NOT propagate to existing check-ins. This is deliberate (historical record stability). Surface this in the UI ("Skills snapshotted at {created_at}") if confusion arises in v2.
- **PROBATION → REGULAR transition mid-quarter**: when an employee is regularized, their employment_type changes to REGULAR. The auto-gen will then also create quarterly check-ins going forward. Previously created PROBATION_5M check-in stays as-is (the regularization decision artifact). Two artifacts can coexist for the same employee in the same calendar window — that's correct.

## What this unblocks (downstream)

- **Compensation / 13th-month merit splits**: completed check-ins with overall_rating + manager_feedback feed comp decisions. A simple "average rating over the last 3 cycles" can be surfaced on the employee profile.
- **Promotion-readiness signaling**: a v2 badge on the employee profile when 3 consecutive cycles score ≥ 4.5.
- **Calibration view**: cross-manager comparison of ratings — once enough data exists.
- **30-day onboarding bridge**: the HIRING workflow's 30-day STATUS_UPDATE step can later auto-create the first PROBATION_1M check-in (since hire_date + 1M IS the 30-day milestone).
- **Lark integration**: notify managers when their reports submit reviews; remind employees when their period opens.
