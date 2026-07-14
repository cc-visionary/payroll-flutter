# Dashboard: accuracy overhaul + month/year period filter + monthly explorer

Date: 2026-07-14
Status: Approved (design)

## Problem

The HR dashboard reports numbers that do not tie out to the rest of the app,
and several of its tiles are structurally incapable of ever being correct.

Concretely, in `lib/features/dashboard/dashboard_providers.dart`:

1. **Employee Movement is always zero.** The provider matches `event_type`
   against `'SEPARATION'`, `'TERMINATION'`, `'RESIGNATION'`, and
   `'END_OF_CONTRACT'`. None of those exist in the `employment_event_type`
   enum (`20260414000001_enums_and_helpers.sql:26`). The value the app
   actually writes is `SEPARATION_CONFIRMED`
   (`employee_repository.dart:54`). The voluntary/involuntary split reads
   `payload['kind']`, but the writer stores `payload['reason']`. The event
   `status` column is never filtered, so PENDING/REJECTED/CANCELLED events
   would be counted once the type match is repaired.

2. **Lates are a hardcoded 09:00 heuristic.** Line 273 flags any clock-in
   after 09:00 and counts minutes past 09:00. It ignores the employee's
   shift template, the shift's grace period, undertime (early-out), and the
   company rule that OT absorbs late minutes. The app already owns the
   canonical model — `AttendanceRowVm.deductionMinutes` in
   `lib/features/attendance/attendance_row_vm.dart` — used by the payslip
   PDF and the profile Attendance tab. The dashboard number cannot match a
   payslip.

   The derived "Avg Late Minutes" tile is worse than wrong: it divides by
   the count of *late samples*, so the metric **rises** when fewer people
   are late.

3. **Silent 1000-row truncation.** `supabase/config.toml` sets
   `max_rows = 1000`. The attendance query is unpaginated. At ~40 staff a
   single month is already ~1,040 rows and a full year is ~12,500 — every
   attendance-derived figure is computed on an arbitrary truncated slice.
   This is the most likely cause of the reported "inaccurate based on the
   current data".

4. **Leave is counted in whole days from attendance rows.** `ON_LEAVE`
   records are counted one-per-row, so a half-day leave counts as a full
   day (`leave_requests.leave_days` is `numeric(5,2)`, with `start_half` /
   `end_half`). Approved leave with no attendance record is invisible. The
   "Leave Used" ring is `on-leave rows ÷ total rows`, which is not leave
   utilisation by any definition.

5. **Smaller defects.** `HOLIDAY` falls through the `attendance_status`
   switch, inflating the attendance-rate denominator. Rest days are
   detected via `attendance_status` rather than the canonical "no
   `shift_template_id` → rest day" rule. Soft-deleted employees are not
   excluded from attendance. "Avg Salary" is gross ÷ *payslip count*, which
   under semi-monthly runs is an average half-month. "Open Positions" is
   really a count of open *applicants*. "New applicants this month" is
   period-scoped, so for a past year it silently means the whole year.

### Adjacent defect, same root cause

`AttendanceRepository.listByRange` (`attendance_repository.dart:75`) and
`ComputeService._loadAttendance` (`compute_service.dart:441`) are also
unpaginated. A semi-monthly run (~15 days × 40 staff ≈ 600 rows) stays under
the cap today, but a **monthly** run at 40+ staff is ~1,240 rows — payroll
would silently compute on truncated attendance. `runWarningsProvider`
(`runs/detail/providers.dart:112`) has the same exposure. This is fixed here
because it shares a root cause with the dashboard bug and cannot be left in
place while claiming the dashboard is now accurate.

## Goals

- Attendance, late/undertime, OT, and leave figures that **tie out to
  payslips**, because they are produced by the same engine.
- A period filter with **Month (default) / Year** modes.
- A bottom "Monthly Explorer" that breaks the year into month rows and
  doubles as the period selector.
- Remove the 1000-row truncation everywhere it exists.

## Non-goals

- Leave *balance* utilisation (used ÷ entitlement from `leave_balances`).
  Deferred: it requires confirming that balances are reliably maintained.
- Server-side (SQL/RPC) aggregation. Rejected because it would duplicate the
  late/OT deficit model in a second language, guaranteeing drift from
  payroll. Correctness beats latency here.
- Any change to payroll computation *results*. The pagination fix changes
  what payroll *sees*, not how it calculates.

## Architecture

**One fetch per year, sliced client-side.** `dashboardDataProvider` loads the
whole selected calendar year once, derives all 12 month buckets plus the year
total, and hands the screen a single object. Switching months is a pure
re-slice — instant, no refetch. This is what makes the explorer affordable:
a month-by-month table needs a year of attendance regardless of which period
is selected, so the top KPIs may as well be the "selected month" slice of the
same dataset.

### New files, under `lib/features/dashboard/`

**`dashboard_period.dart`**

```dart
enum DashboardPeriodMode { month, year }

class DashboardPeriod {
  final DashboardPeriodMode mode;
  final int year;
  final int month; // 1..12; ignored when mode == year
  // + value equality, copyWith, label, start, end (end clamps to today
  //   for the in-progress month/year)
}

final dashboardPeriodProvider = StateProvider<DashboardPeriod>(...);
// default: mode = month, year/month = today
```

Replaces `dashboardYearProvider`.

**`dashboard_metrics.dart`** — pure Dart, no Supabase import. Consumes the raw
year bundle and returns `List<MonthMetrics>` (12 entries) plus derived
totals. Every definition in the table below lives here, and because it is
pure it is unit-testable.

Crucially, it computes attendance by calling **`buildAttendanceRows` and
`AttendanceStats.from` from `attendance_row_vm.dart`** — the same engine the
payslip PDF (`payslip_pdf_context.dart:184`) and the profile Attendance tab
use. It is not a reimplementation. If a payslip says 6h 44m Late/UT, the
dashboard says 6h 44m.

Per employee, rows are built only across that employee's **employment
window** (`hire_date` → `separation_date ?? today`), so a July hire does not
accrue six months of phantom absences.

**`dashboard_screen.dart`** — UI only; all derivation moves out.

### Repository change

`AttendanceRepository.listByRange` gains internal pagination: loop
`.range(offset, offset + 999)` until a short page returns. Every existing
caller — attendance screen, run warnings, payslip PDF, payslip detail — is
corrected for free with no call-site change.

`ComputeService._loadAttendance` gets the same loop.

### Year bundle (what the provider fetches)

| Source | Scope |
|---|---|
| `employees` (+ `role_scorecards`, `departments`, `hiring_entities`) | all, **including soft-deleted** — separation archives the employee, so excluding `deleted_at` hides the separations we need |
| `shift_templates` | all |
| `calendar_events` (holidays) | selected year |
| `attendance_day_records` | Jan 1 – Dec 31, paginated |
| `leave_requests` | overlapping the year, `status = 'APPROVED'` |
| `payslips` (RELEASED runs, by `pay_date`) | selected year, paginated |
| `applicants` | all |

`employment_events` is no longer read by the dashboard.

## Metric definitions

### Attendance and lates

All from `AttendanceStats.from(...)`, summed across employees.

| Metric | Definition |
|---|---|
| Work days | Scheduled work days. Rest days (no `shift_template_id`, or outside the scorecard's `work_days_per_week`) and unworked holidays excluded; worked holidays included. |
| Present / Absent | Clocked-in vs scheduled-but-no-show, on work days only. |
| **Late / UT** | Σ `netDeductionMinutes` — the deficit of scheduled-window worked minutes vs the shift's expected minutes (honouring break, `late_in_approved`, `early_out_approved`), **after OT absorption**. Identical to the payslip deduction. Includes undertime, which the current dashboard misses entirely. |
| Avg late per work day | Late/UT ÷ work days. Replaces "Avg Late Minutes". |
| OT hours | Σ `netOvertimeMinutes` ÷ 60. Matches the payslip; the current raw `approved_ot_minutes` sum does not. |
| Attendance rate | Present ÷ (work days − on-leave days). Leave is not an absence, so it leaves the denominator. |

### Leave

From `leave_requests`, not from attendance rows. `status = 'APPROVED'` only.

Each request is expanded day-by-day across `start_date..end_date`. A day
contributes 1.0, except the first day when `start_half` is set and the last
day when `end_half` is set, which contribute 0.5. This makes half-days
correct and lets a request straddling Jul→Aug split across both month
buckets.

The reconstructed total is reconciled against the stored `leave_days`; if they
disagree, the per-day values are scaled proportionally so the request's
contribution always sums to `leave_days`. Bad data should not silently skew
the month buckets.

The explorer breaks leave days out by leave type.

### Movement

Sourced from `employees`, **not** `employment_events`.

- New hires = `hire_date` within the period.
- Separations = `separation_date` within the period **and**
  `employment_status != 'ACTIVE'`.
- **Voluntary** = `RESIGNED`, `RETIRED`.
- **Involuntary** = `TERMINATED`, `END_OF_CONTRACT`, `AWOL`, `DECEASED`.
  (AWOL is treated as employer-side; in practice it resolves to termination
  for cause.)

Voluntary + Involuntary always equals Separations, for the same period — the
current dashboard's "(YTD)" suffixes on those two tiles are dropped, since
every movement figure now follows the selected period.

### Snapshots (as of period end)

Headcount by department, employment type, hiring entity, tenure distribution,
active/total employees, average tenure.

An employee is **active as of date D** when `hire_date <= D` and
(`separation_date` is null or `separation_date > D`), excluding rows that were
administratively archived (`deleted_at` set) without ever being separated.

"As of" date = the period end, clamped to today for an in-progress period.
Every snapshot card carries an explicit `as of 31 Jul 2026` stamp so it is
never mistaken for a period sum.

### Payroll

Σ `gross_pay` over payslips whose payroll run is `RELEASED` and whose
`pay_date` falls in the period. Month attribution is by `pay_date`.

"Avg Salary" becomes **"Avg gross per employee"** = total gross ÷ *distinct
employee count*. The current divisor is the payslip count, which under
semi-monthly runs yields an average half-month labelled as a salary.

### Recruitment

- "Open Positions" → renamed **"Open Applicants"** (it counts applicants
  whose status is not HIRED/REJECTED/WITHDRAWN/OFFER_DECLINED, which is not a
  requisition count). This is a **live snapshot**, not period-scoped — an
  applicant is open now or not — so it carries no period stamp.
- New applicants = `applied_at` within the selected period, for real. Shown
  as the subtitle of the Open Applicants card.

### Division by zero

Every rate and average returns `0` when its denominator is 0 (a month with no
work days, no payslips, or no active employees). No `NaN`, no `∞` reaching
the UI.

## UI

### Header

Segmented control `[ Month | Year ]`, a month dropdown (hidden in Year mode),
and a year dropdown (current year + 4 back). Subtitle reads
`HR Analytics · July 2026` or `HR Analytics · 2026`.

Default state: **Month, current month.**

### KPI row

Six cards in the existing responsive wrap, promoting the two metrics this
work is about:

`Active Employees` · `Attendance Rate` · `Late / UT` · `Leave Days` ·
`OT Hours` · `Open Applicants`

`Active Employees` carries an "as of" subtitle. `Open Applicants` is a live
snapshot, with new-applicants-this-period as its subtitle. The middle four
carry the period label.

`Avg Tenure` leaves the KPI row and becomes the subtitle of the **Tenure
Distribution** card (`Avg 18.4 months · as of 31 Jul 2026`), where it belongs
next to the buckets it summarises.

### Middle rows

Same cards as today (Headcount by Department, Employment Type Distribution,
Employees by Hiring Entity, Tenure Distribution, Attendance Overview, Payroll
Summary), with the four distribution cards stamped "as of" and Attendance /
Payroll stamped with the period.

**Attendance Overview** is reworked. The three rings go away — "Leave Used"
(on-leave rows ÷ all rows) is not a real metric, and "Attendance" vs
"Present" were two renderings of nearly the same ratio. Replaced by:

- a **day-composition bar**: Present / Absent / Leave / Rest / Holiday
- four tiles: `Late / UT`, `Avg late per work day`, `OT hours`, `Leave days`

### Bottom — Monthly Explorer

Wrapped in `lib/widgets/responsive_table.dart` per project convention.

```
Monthly Explorer — 2026

Month   Work  Pres  Abs  Leave  Late/UT   OT    Hire  Sep   Payroll
───────────────────────────────────────────────────────────────────
Jan      26    612   14   18.5   4h 12m   38h    2     0    ₱1,240,300
Feb      24    580    9   12.0   3h 05m   41h    0     1    ₱1,198,450
▸ Jul    22    498   21    7.5   6h 44m   22h    1     0    ₱1,102,900
...
───────────────────────────────────────────────────────────────────
Year    302  6,940  158  164.0  52h 18m  410h   14     6   ₱14,120,600
```

Only period-scoped metrics appear. Headcount, tenure, and employment type are
snapshots and do not sum across months, so they are deliberately absent —
that is the "only those that fit monthly/yearly" rule.

Interaction:

- Clicking a month row sets the period to that month. The whole dashboard
  refilters with no refetch.
- Clicking the **Year** total row switches the period to Year mode.
- The selected row is highlighted.
- Future months of the current year render greyed and empty.

## Error handling

- The payslip fetch keeps its existing defensive wrapper: a failure yields
  zeroed payroll KPIs rather than taking down the page.
- Same treatment extended to leave requests and holidays — a failure there
  zeroes leave / degrades holiday handling but still renders attendance.
- A failed attendance page mid-pagination aborts the whole fetch and surfaces
  an error. Partial attendance is exactly the bug being fixed, so it must
  never be silently rendered.
- Employees with no linked scorecard fall back to the existing
  `work_days_per_week` default (Mon–Sat) already encoded in
  `attendance_row_vm.dart`.

## Testing

`dashboard_metrics.dart` is pure, so it gets real unit tests in
`test/features/dashboard/`:

- half-day leave contributes 0.5, not 1.0
- a leave request straddling a month boundary splits across both buckets
- a request whose day-expansion disagrees with `leave_days` is scaled to
  reconcile
- a mid-year hire accrues no absences before `hire_date`
- a separated + archived employee still counts in the month they left, and
  drops out of the following month's headcount
- OT absorbs late minutes (net late = 0 when OT ≥ late)
- undertime (early-out) registers as Late/UT
- attendance rate excludes leave days from the denominator
- a work day with no attendance record and no shift is a rest day, not an
  absence
- month buckets sum to the year total for every additive metric

`AttendanceRepository.listByRange` gets a pagination test: a >1000-row range
returns every row (asserted against a stubbed client that pages).

## Migration / rollout

No schema migration. No Edge Function change. Pure Flutter.

`dashboardYearProvider` is removed; `dashboard_screen.dart` is its only
consumer.

Verification gate: `flutter analyze` clean, new unit tests pass, and a live
smoke check that the dashboard's Late/UT and OT for a released period equal
the sum of those lines across that run's payslips.
