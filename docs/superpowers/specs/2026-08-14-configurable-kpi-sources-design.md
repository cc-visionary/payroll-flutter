# Spec — Configurable KPI data sources

**Date:** 2026-08-14
**Status:** Approved design, not yet implemented
**Builds on:** the KPI cascade (`2026-08-13-kpi-cascade-design.md`), merged and unapplied-migrations pending
**Sub-project:** C — external data integrations, from the Integrated Performance & Workforce Planning framework

## Why

The results engine gets its numbers from a registry of `KpiSource` objects, and every one of them is compiled in. Two exist: `app.attendance.present_days` and `app.reviews.completed_on_time`. Adding a third means writing Dart, running the suite and shipping a build.

KPIs are not stable. They get added, retired and redefined as the business learns what is worth measuring — that is the point of the quarterly rhythm. A measurement system whose every metric requires a developer is a measurement system that stops being edited, and a scorecard nobody edits stops being true.

Most of the numbers already exist. Revenue, orders, refunds, purchases and expenses live in **Cashflow** — a separate Next.js/Prisma app on its own Postgres, with `Order`, `OrderLine`, `DailySalesFact`, `Refund`, `Expense`, `Purchase` and `StockSnapshot` models. Nobody should be retyping those into a scorecard.

## Decisions

Each was chosen against a real alternative. Do not re-litigate without new information.

1. **Pull, not push.** This app fetches from configured sources rather than each source posting in. The owner chose one place to configure everything over spreading small jobs across repos. **The cost is real and accepted:** this app holds read-only credentials to other systems and opens outbound connections from an edge function. Push would have avoided credentials entirely; it was rejected because it needs code in every source system.

2. **Column mapping onto a fixed shape, not SQL and not a query builder.** Every KPI reduces to four values: a **period**, a **subject**, a **numerator** and a **denominator**. A source presents rows in that shape and configuration says which of its columns play those roles. The connector never parses or generates arbitrary SQL.
   - Rejected — stored SQL per KPI: arbitrary statements executed against production databases, SQL literacy required to add a KPI, and a typo surfaces at month-end.
   - Rejected — a structured query builder: it is a query builder, the largest of the three to build and the one most likely to meet a case it cannot express.
   - The cost: anything needing a join or a computed column requires a **view on the source side first**. Trivial in Cashflow, which the company owns.

3. **A mapping table per connection resolves identity.** A source emits whatever key it has — a staff id, an email, a name — and this app maps it to an employee or department. Nothing changes in Cashflow or Lark.
   - Rejected — matching on email or employee number: zero maintenance while it works, but it breaks silently on a personal email or a name change, and the failure is indistinguishable from "that person had no activity".
   - Rejected — requiring every source to store our employee id: unambiguous, but it is schema and code changes in every source system, which is the cross-repo work that pulling was chosen to avoid.
   - A source that already stores the employee id maps it to itself and pays nothing.

4. **Sources may produce personal rows**, not only department and company. That is why identity resolution is in scope at all.

5. **The registry is not replaced — it becomes populatable.** The two app-internal sources stay as code because they encode app logic. `computeResults` is unchanged; it already takes a registry.

6. **SQL-speaking connections only, in v1.** Lark Base (a REST API) and Excel upload (an import) fit the same binding and mapping model but neither speaks SQL. They reuse everything and are follow-ups.

## Data model

**`kpi_connections`** — a named source system.

| Column | Note |
|---|---|
| `kind` | `POSTGRES` / `SUPABASE` |
| `host`, `port`, `database`, `db_schema` | Non-secret connection detail |
| `vault_secret_name` | **A reference.** The credential lives in Supabase Vault; this table never holds a password |
| `is_active` | |

**`kpi_source_bindings`** — how one KPI reads from one connection.

| Column | Note |
|---|---|
| `kpi_id` | |
| `connection_id` | |
| `object_name` | Table or view. Validated as an identifier, never interpolated raw |
| `period_column`, `subject_column`, `numerator_column`, `denominator_column` | The mapping. `denominator_column` is nullable — a COUNT KPI has none |
| `subject_kind` | `EMPLOYEE` / `DEPARTMENT` / `NONE` |
| `period_format` | How the source writes a period, e.g. `YYYY-MM` |

**`kpi_subject_map`** — external key → subject, per connection.

`(connection_id, external_key)` unique; resolves to `employee_id` **or** `department_id` according to the binding's `subject_kind`.

## How a value is produced

1. `ConfiguredSource` implements the existing `KpiSource` interface, so the compute service is unchanged.
2. It calls an edge function with the binding id and the period.
3. The function reads the connection, fetches the credential from Vault, connects **read-only**, and runs one statement of the shape:

   ```sql
   select <period_col>, <subject_col>, <numerator_col> [, <denominator_col>]
     from <schema>.<object>
    where <period_col> = $1
   ```

   Identifiers are validated and quoted. The period is a bound parameter.
4. Rows come back as `(subject_key, numerator, denominator)`.
5. Subjects resolve through `kpi_subject_map`.
6. Aggregation per scope, in pure Dart:
   - **Personal** — the row whose subject is that employee.
   - **Department** — numerators and denominators **summed** across employees in that department.
   - **Company** — summed across all.

Because numerator and denominator arrive separately per subject, the wider scopes are correct sums rather than averages: Alice 30/30 and Bob 10/50 gives 40/80, not 60%. This is the same rule the engine already enforces for its own sources.

`subject_kind` maps onto the existing scope model: `EMPLOYEE` can produce all three scopes; `DEPARTMENT` produces department and company; `NONE` produces company only.

## Failure behaviour

Every failure resolves to `NO_DATA` with `MISSING_SOURCE` — never a partial number, never a zero. This is the engine's existing contract and the reason it can be trusted:

- connection refused, credentials rejected, timeout;
- object or column missing (a rename upstream);
- a period the source has no rows for.

**An unresolved subject counts toward company scope and marks the result incomplete.** It cannot count toward a department, because without an identity there is no department to attribute it to. This mirrors how unattributed exceptions already behave.

A failure in one source must not abort a whole recompute — `computeResults` already contains a source's throw to that KPI's own row.

## Security

The two risks pulling introduces, and what answers them:

- **Credentials.** Held in Supabase Vault, referenced by name. The connection row is readable by admins; the secret is not. The source database user must be **read-only**, and that is a deployment requirement, not a suggestion.
- **Identifier injection.** `object_name` and the four column names reach SQL. They are validated against a strict identifier pattern and quoted; the period alone is a bound parameter. This gets dedicated tests, including rejection cases.

RLS: connections, bindings and the subject map are configuration — admin-only read and write, company-scoped, using `auth_is_hr_or_admin()`. No self-read clause.

## Testing

Pure and testable without a database:

- **Row aggregation** — rows plus a subject map plus a scope produce a numerator and denominator. Pin that department is a SUM and not an average, using two subjects of different volumes so the two answers differ.
- **Subject resolution** — mapped, unmapped, and a key mapping to a soft-deleted employee.
- **Identifier validation** — accepts ordinary names, rejects quotes, semicolons, whitespace and comment markers.
- **Failure mapping** — each failure class becomes `NO_DATA` / `MISSING_SOURCE`.

The edge function's SQL construction is tested in Deno; connectivity itself is not unit-testable and needs a live check, which the plan should say plainly rather than fake.

## Done when

- An admin can add a connection, bind a KPI to a table and its columns, and see the KPI compute without a code change.
- A binding whose source is unreachable produces `NO_DATA`/`MISSING_SOURCE`, and the other KPIs in the same recompute still produce rows.
- Department and company figures from an external source are sums, not averages.
- An unmapped subject is visible somewhere an admin can fix it.
- No credential is stored outside Vault; no identifier reaches SQL unvalidated.
- Migrations committed and handed over, **not applied**.

## Not in this spec

Lark Base connections, Excel upload, and any UI for *browsing* a source's tables to help configure a binding. The last is tempting and is exactly how a column mapper turns into a database client.
