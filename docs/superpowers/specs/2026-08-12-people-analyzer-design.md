# Spec D — The People Analyzer

**Date:** 2026-08-12
**Status:** Approved design, not yet implemented
**Depends on:** Spec C — the Accountability Chart (`2026-08-12-accountability-chart-design.md`), for the Seat vocabulary its GWC rows hang off
**Related:** Spec B — KPI logging and Employee of the Month, still unwritten

## Why

EOS's People Analyzer answers "right person, right seat": whether someone lives the company's core values, and whether they Get, Want and have the Capacity for the seat they sit in. It is deliberately fast — a grid, minutes for the whole team, once a quarter — and deliberately separate from whether they are hitting their numbers.

The app has neither core values nor GWC today.

## Decisions

1. **Standalone quarterly grid**, not a section of the review cycle. Folding it into a review would give it review cadence and review weight, and it would stop being done.
2. **Values are rated per person; GWC is rated per person per seat.** Values are about the person, fit is about the seat, and a person can hold two seats with different answers.
3. **HR and admins see everyone; a manager sees their own reports. The employee sees nothing.**
4. **The Bar is snapshotted onto each session**, not read from settings.
5. **Nothing carries forward between quarters.** EOS re-rates from scratch; pre-filling turns it into a rubber stamp.
6. **Below the bar makes someone ineligible for Employee of the Month, but contributes nothing to the score.**

## Out of scope

Anything that scores performance — that is Spec B. Any employee-facing surface. Any automatic action on a below-the-bar result: EOS's answer is a conversation and a 30-60-90, which is a human process, not a workflow to automate here.

## The grid

Rows are people, grouped: one row for the person carrying their value ratings, then one indented row per seat they hold carrying that seat's GWC. Columns are the active core values, then G, W and C.

```
PEOPLE ANALYZER · Q3 2026                    The Bar: no −, max one +/−
──────────────────────────────────────────────────────────────────────
 NAME / SEAT                    Own it  Do right  Serve │  G   W   C
──────────────────────────────────────────────────────────────────────
 Clinton                          +       +        +    │
   └ Visionary                                          │  ✓   ✓   ✓
   └ Sourcing                                           │  ✓   ✓   ✗   ⚠
 Marvin Ong                       +       +       +/−   │
   └ Technical Product & Purchasing                     │  ✓   ✓   ✓
 Evander Mercado                 +/−      +        −    │            ⚠ below the bar
   └ Sales & Ops Assistant                              │  ✓   ✓   ✓
```

Ratings are `+`, `+/−`, `−`. GWC is three booleans.

Two verdicts, deliberately kept apart, because they have different remedies:

- **Below the bar** — the person's *value* ratings breach the session's bar. The remedy is a conversation about the person.
- **Wrong seat** — any of G, W, C is false for a seat they hold. The remedy is moving that seat, not the person; someone can fail C in one seat and thrive in another.

Collapsing them into one flag loses the only actionable part. Where the UI needs a single "needs attention" marker on a row, it shows both reasons, never a merged one.

## Data model

```sql
create table core_values (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references companies(id) on delete cascade,
  name text not null,
  description text,
  sort_order int not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table people_analyzer_sessions (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references companies(id) on delete cascade,
  period text not null,                    -- '2026-Q3'
  bar_max_minus int not null default 0,    -- EOS default: no '−' at all
  bar_max_plus_minus int not null default 1,
  created_at timestamptz not null default now(),
  unique (company_id, period)
);

create table people_analyzer_value_ratings (
  session_id uuid not null references people_analyzer_sessions(id) on delete cascade,
  employee_id uuid not null references employees(id) on delete cascade,
  core_value_id uuid not null references core_values(id) on delete cascade,
  rating text not null check (rating in ('PLUS','PLUS_MINUS','MINUS')),
  primary key (session_id, employee_id, core_value_id)
);

create table people_analyzer_gwc (
  session_id uuid not null references people_analyzer_sessions(id) on delete cascade,
  employee_id uuid not null references employees(id) on delete cascade,
  role_scorecard_id uuid not null references role_scorecards(id) on delete cascade,
  gets boolean not null,
  wants boolean not null,
  capacity boolean not null,
  primary key (session_id, employee_id, role_scorecard_id)
);
```

**Why the bar lives on the session.** If it lived in settings, raising it would retroactively reclassify every past quarter's verdicts. Snapshotting keeps Q1's answers judged by Q1's bar.

Core values are authored in settings, beside the existing HR configuration screens. Deactivating a value keeps historical ratings readable and drops it from the next session's columns.

## Access control — read this before writing the policy

The obvious move is to copy `employee_kpis`'s RLS (`20260718000005`), which reads:

```sql
auth_is_performance_admin_for_employee(employee_id)
or employee_id = auth_employee_id()
or exists (select 1 from employees e
           where e.id = employee_id and e.reports_to_id = auth_employee_id())
```

**Drop the middle clause.** It is right for KPI assignments and wrong here: it would let every employee read their own values rating and GWC verdict. The chosen access is HR/admins plus managers-for-their-own-reports, with no employee-facing surface at all.

That is a two-line difference a copy-paste gets silently wrong, and its failure mode is an employee discovering they are marked below the bar with no conversation. Write the policy deliberately; do not adapt the neighbouring one.

Write access is the same set as read. A manager rates their own reports; HR and admins rate anyone.

## Relationship to Employee of the Month

**Below the bar** — the values verdict — makes someone **ineligible**. It contributes **nothing** to the 50/25/25 score.

**Wrong seat does not affect eligibility.** A failed G, W or C says the seat is misassigned, not that the person underperformed; withholding an award for it would punish someone for a placement decision that was not theirs. This distinction is the reason the two verdicts are stored and reported separately rather than as one flag.

EOS keeps "right person, right seat" and "hitting the number" as separate axes deliberately. Folding a values judgement into a performance percentage makes the score unarguable in precisely the way that gets it distrusted — and it would let a strong quarter of numbers outweigh a core-values problem, which is the opposite of what the tool is for.

Spec B owns the eligibility check; this spec owns the verdict it reads.

## Testing

Pure, unit-testable:

- bar evaluation: given ratings and a bar, below or not — including the boundary at exactly one `+/−`, and a person with no ratings yet (not below the bar; unrated)
- the two verdicts are independent: a person below the bar but right-seated, a person above the bar but wrong-seated, and both at once
- eligibility keys on the values verdict ONLY — a wrong-seat person above the bar stays eligible
- grouping seats under a person, for someone holding two
- which seats a person holds, derived the same way the chart derives it

Widget-level, on `test/support/supabase_stub.dart`:

- a person holding two seats renders one value row and two GWC rows
- deactivating a core value drops its column from a new session but not from a past one
- **a policy test that an EMPLOYEE-role user cannot read their own row** — the one that catches the copy-paste above

## Risks

- **Quarterly cadence has no reminder.** Nothing prompts the session; it exists when someone opens the grid. Adding a nag is out of scope, but a tool that is only used when remembered tends not to be.
- **Nine of eleven people hold one seat**, so the grouped two-row shape costs vertical space for most of the team to be correct for two of them. Accepted: the alternative loses which seat is wrong, which is the actionable half.
- **A below-the-bar verdict is termination-adjacent** and now lives in a database with an RLS policy. The policy is the control; there is no audit trail of who rated what beyond the session. If that matters, it is a follow-up, not a silent assumption.
