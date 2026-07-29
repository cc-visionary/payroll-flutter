# Employee Master-Data Sync (Lark → App) — Design Spec

> Date: 2026-07-25. The **foundational** integration piece from the Lark strategy
> (`2026-07-25-lark-integration-strategy-design.md`): new hires registered via the
> Lark "Employee Information for Onboarding" Base flow into the app as employee
> records — personal info, the four statutory IDs, and disbursement accounts —
> so payroll runs on data HR typed once, in Lark.

## Goal

A one-way (Lark → App) sync that **creates and updates** employee records from the
Lark "Employee Information" Base, matched by **employee number**, using a **smart
merge that never overwrites a field HR has edited in the app.**

## Decisions (locked in brainstorming)

| Question | Decision |
|---|---|
| Direction | **One-way, Lark → App.** No writeback to Lark. Lark is primary for the onboarding-form fields. |
| Create vs enrich | **Create from Lark.** A new hire's Lark Base record → the app **creates** the employee; an existing employee-number → **updates** the Lark-owned fields. One upsert handles both. |
| Match key | **`employee_number`** (present on both the Lark Base record and `employees`). A Lark record without one is **skipped** (can't match or create). |
| Overwrite protection | **Smart merge.** The app fields are **editable**; the sync overwrites a field only if HR hasn't changed it since the last sync (tracked via a per-employee snapshot). Once HR edits a field, their value sticks — Lark stops overwriting *that* field, but still corrects untouched ones. |
| Field ownership | **Lark-owned** = the onboarding-form fields (below). **App-owned** = department, role, employment type/status, compensation — the sync **never touches** these. |
| Login | The sync creates the employee **record**, not an app **login** (`manage-user` stays separate; a Lark-only new hire needs no login). |

## Source — the Lark "Employee Information" Base (net-new capability)

The existing `sync-lark-*` functions read Lark's attendance/approval/calendar APIs;
**none read a Lark Base (Bitable).** This sync needs new Base-read helpers in
`_shared/lark.ts` (list records from a table, paginated). Prerequisites the user
provides/configures (like the self-review form): the Base **app_token** + **table_id**,
and the Lark app granted **Bitable read** scope with the Base shared to it. The
Base is confirmed to carry a **Start Date** field (the onboarding automation fires
off it) and an **employee number** (the chosen match key).

## Target — existing tables (no new landing schema)

- **`employees`** (personal): `first_name, middle_name, last_name, birth_date,
  civil_status, personal_email, phone_number, present_address_line1,
  emergency_contact_name, emergency_contact_number, emergency_contact_relationship`;
  plus `employee_number` (match), `hire_date` (from Start Date), `company_id`
  (GameCove), `employment_type` default `PROBATIONARY`, `employment_status` `ACTIVE`.
- **`employee_statutory_ids`** (`employee_id, id_type, id_number`, unique per
  `(employee_id, id_type)`): one row each for `TIN`, `SSS`, `PHILHEALTH`, `PAGIBIG`.
- **`employee_bank_accounts`** (`employee_id, account_number, …`) + `employees.payment_method`:
  Metrobank Acct No → a bank account row; GCASH No → a GCash account row.

**Field mapping** (Lark form field → app target):

| Lark field | App target |
|---|---|
| First / Middle / Last Name | `employees.first_name / middle_name / last_name` |
| Birthday | `employees.birth_date` |
| Email Address | `employees.personal_email` |
| Present Address | `employees.present_address_line1` |
| Civil Status | `employees.civil_status` |
| Contact # | `employees.phone_number` |
| Emergency Contact / # / Relationship | `employees.emergency_contact_name / _number / _relationship` |
| TIN / SSS / PhilHealth / PAG-IBIG | `employee_statutory_ids` rows (`id_type` = `TIN`/`SSS`/`PHILHEALTH`/`PAGIBIG`) |
| Metrobank Acct. No. | `employee_bank_accounts` (bank) |
| GCASH No. | `employee_bank_accounts` (GCash) + `employees.payment_method` |
| *(Base) Employee Number* | `employees.employee_number` — **match key** |
| *(Base) Start Date* | `employees.hire_date` |

## The smart merge — how app edits are protected

Add one column: **`employees.lark_master_snapshot jsonb`** — the last set of values
Lark sent (keyed by the mapping above; statutory/bank values keyed by their
sub-key). On each sync, for every Lark-owned field:

1. **Field empty in the app** (new hire, or never set) → **fill** from Lark; record in snapshot.
2. **App value == snapshot value** (HR hasn't diverged) → **apply** Lark's new value; update snapshot.
3. **App value ≠ snapshot value** (HR edited it in the app) → **skip** — leave the app value; do not overwrite. (Lark still updates the *other*, untouched fields.)

On **create**, all fields are set from Lark and the snapshot is seeded with the
same values. This keeps Lark the source for untouched fields while making HR's
edits sacred — the exact "don't waste app changes" requirement.

## Data flow

```
Lark "Employee Information" Base (records)
        │  sync-lark-master-data (edge fn, service role)
        ▼
  for each record with an employee_number:
    match employees by (company_id, employee_number)
      ├─ none → INSERT employee (Lark fields + defaults) + statutory + bank rows; snapshot = Lark values
      └─ exists → smart-merge each Lark-owned field (fill / apply / skip); upsert statutory + bank rows the same way
        │
        ▼
  app UI shows the fields (editable, badged "synced from Lark · last synced <t>")
```

## Trigger

**HR-invoked**, matching the project's preference for control over cron: a
**"Sync from Lark"** action on the employee-directory screen (and/or the existing
sync runner), reporting created / updated / skipped / errors like the other
`sync-lark-*` jobs. Scheduling can be layered on later; not now.

## UI (app side)

- The Lark-owned fields render on the employee profile **editable**, with a small
  **"synced from Lark"** badge and a **last-synced** timestamp, so HR knows their
  origin and that an edit will "claim" the field from future overwrites.
- A **sync summary** after a run: *"3 created, 5 updated, 1 skipped (no employee
  number)."*
- App-owned fields (department, role, employment, compensation) are unchanged and
  unmarked.

## Error handling

- Record with no employee number → **skip**, counted + listed (not an error).
- Employee number that maps to a soft-deleted employee → skip (don't resurrect).
- A malformed statutory/bank value → set what's valid, note the rest; never abort
  the whole run for one bad record (per-record isolation, like `updateTaskCosts`).
- Bitable read/permission failure → fail the run with a clear message; write
  nothing partial beyond records already processed.

## Testing

- **Pure merge logic (unit):** the three-way rule — fill-empty / apply-when-unchanged
  / skip-when-app-edited — plus create-seeds-snapshot. This is the heart; test it
  as a pure function over (appValue, snapshotValue, larkValue).
- **Field mapping (unit):** a Lark record → the employees / statutory / bank writes,
  including the four `id_type`s and the two account types.
- **Deno (throwaway Postgres):** create-then-resync idempotency (no dup statutory/bank
  rows via the unique keys); skip-no-employee-number; an app-edited field survives
  a resync.
- `flutter analyze` clean; full suite green.

## Sequencing (each ships working)

1. **Migration** — add `employees.lark_master_snapshot jsonb`. (Tiny, additive.)
2. **Pure merge + mapping** — `masterDataMerge` / `mapLarkRecord` pure functions +
   tests (no Lark, no DB).
3. **Base-read helpers** in `_shared/lark.ts` (list Bitable records, paginated).
4. **`sync-lark-master-data` edge function** — read Base → upsert employees +
   statutory + bank with the merge; report counts. + Deno test.
5. **App UI** — the "Sync from Lark" action + the "synced from Lark / last synced"
   badges + the run summary.

Steps 1–2 are pure and inert; 3–4 need the Base coordinates + Bitable scope to run
live; 5 is the manager surface. The merge/mapping is fully testable without a live
Lark connection.

## Out of scope

- **Writeback app → Lark** (deferred; if a specific field ever needs it, add a
  controlled per-field push later).
- Creating app **logins** (separate `manage-user` flow).
- Syncing **app-owned** fields (department/role/employment/comp) — the app owns those.
- The **identity** mapper (`sync-lark-employees` stamping `lark_user_id` from the
  contact directory) — unchanged; complementary, different source.
