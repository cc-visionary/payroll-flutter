# Configurable KPI Data Sources Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let an admin point a KPI at a table in an external database and have it compute, with no code change and no developer.

**Architecture:** The existing `KpiSource` registry is not replaced — it gains entries built from configuration. Three config tables describe a connection, a per-KPI column mapping, and an identity map. An edge function runs one parameterised `SELECT` of the four mapped columns. All the correctness — aggregation per scope, subject resolution, failure mapping — is pure Dart tested without a database.

**Tech Stack:** Flutter (Material 3, Riverpod 3.x), Supabase Postgres, Deno edge functions, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-08-14-configurable-kpi-sources-design.md` — read it first, especially "Decisions", "Failure behaviour" and "Security".

## Global Constraints

- The repo gates on `flutter analyze` only: **0 errors, 0 warnings**. There are 192 pre-existing `info` lints — add none.
- **Do not run `dart format`.** This repo has mixed old/new formatter style and is not gated on it. Match the file you are editing.
- Never claim a test passed or the analyzer was clean without pasting the command output.
- **Migrations are applied by the user, never by an implementer.** You have no authority to run `supabase db push` or any database command.
- Migrations must be idempotent: `create table if not exists`, `drop policy if exists` before `create policy`.
- Widget tests use `initSupabaseStub()` from `test/support/supabase_stub.dart`.
- Baseline: **1491 passing, 1 skipped**; `flutter analyze lib test` 0 errors / 0 warnings / 192 infos.
- Migration numbering starts at `20260815000002` — `20260815000001` is the unrelated unpaid-leave fix.
- **Every failure resolves to `NO_DATA` with `MISSING_SOURCE`.** Never a partial number, never a zero. This is the engine's existing contract; see `evaluateKpi`'s doc comment.
- **No raw control characters in source.** Two raw NUL bytes have shipped in this repo; one made a whole file binary to git so its review package showed nothing. Use `'|'` if you need a separator.
- Five tautological tests have been caught in this repo — tests that pass for a reason other than the one they claim. If an assertion exists to prove a line is load-bearing, delete that line, watch it go red, restore it, and paste both outcomes. Check your test *data* as well as your assertions; the last one was in the fixture.

## Two things about this repo that this plan is the first to do

**No edge function has ever connected to an external Postgres.** Every existing function uses `@supabase/supabase-js` against our own database. Task 5 introduces a driver; it must pin a version and say why it chose that one.

**Vault has never been used here.** Lark credentials come from function env vars (`authFromEnv()`, `_shared/lark.ts:18`). The spec calls for Vault. Task 3 must **verify Vault is available on this project before the plan depends on it**, and if it is not, fall back to the existing env-var pattern and say so — with the consequence stated plainly, because it changes the product: with env vars, adding a connection needs an admin to run `supabase secrets set` once, so it is configuration-not-code but not fully self-service.

## File Structure

| File | Responsibility |
|---|---|
| `lib/features/kpi_results/source_rows.dart` (new) | Pure: rows + subject map + scope → numerator/denominator |
| `lib/features/kpi_results/sql_identifier.dart` (new) | Pure: validate a table/column identifier |
| `supabase/migrations/20260815000002_kpi_source_config.sql` (new) | Three config tables + RLS |
| `lib/data/models/kpi_source_config.dart` (new) | `KpiConnection`, `KpiSourceBinding`, `KpiSubjectMap`, `SubjectKind` |
| `lib/data/repositories/kpi_source_config_repository.dart` (new) | CRUD for the three tables |
| `supabase/functions/_shared/source_query.ts` (new) | Pure: build the SELECT, validate identifiers |
| `supabase/functions/fetch-kpi-source/index.ts` (new) | Connect read-only, run it, return rows |
| `lib/features/kpi_results/configured_source.dart` (new) | `KpiSource` backed by a binding |
| `lib/features/kpi_results/automatic_sources.dart` (modify) | Registry composes code sources + configured ones |
| `lib/features/settings/kpi_sources/kpi_sources_settings_screen.dart` (new) | Connections, bindings, subject map |
| `lib/features/settings/settings_screen.dart` (modify) | Register the tab |

---

### Task 1: Aggregating source rows

**Files:**
- Create: `lib/features/kpi_results/source_rows.dart`
- Test: `test/features/kpi_results/source_rows_test.dart`

**Interfaces:**
- Produces: `class SourceRow { final String subjectKey; final num? numerator; final num? denominator; }`; `enum SubjectKind { employee, department, none }`; `({num? numerator, num? denominator, bool unresolvedPresent}) aggregateSourceRows({required List<SourceRow> rows, required KpiScope scope, required SubjectKind subjectKind, required Map<String, String> subjectToEmployee, required Map<String, String> employeeToDepartment, String? employeeId, String? departmentId})`.
- Consumes: `KpiScope` from `lib/data/models/kpi_result.dart`.

This is where the whole feature is either correct or quietly wrong, so it is built first and tested with no database at all.

The rule that matters: **department and company are SUMS of numerators and denominators, never averages of ratios.** Alice 30/30 and Bob 10/50 is 40/80 = 0.5, not 0.6. Rows carry numerator and denominator separately precisely so this is possible.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/kpi_result.dart';
import 'package:payroll_flutter/features/kpi_results/source_rows.dart';

const _toEmployee = {'alice@x': 'e-alice', 'bob@x': 'e-bob'};
const _toDepartment = {'e-alice': 'd-ops', 'e-bob': 'd-ops', 'e-cara': 'd-mkt'};

List<SourceRow> get _rows => const [
  SourceRow(subjectKey: 'alice@x', numerator: 30, denominator: 30),
  SourceRow(subjectKey: 'bob@x', numerator: 10, denominator: 50),
];

({num? numerator, num? denominator, bool unresolvedPresent}) run({
  List<SourceRow>? rows,
  KpiScope scope = KpiScope.company,
  SubjectKind subjectKind = SubjectKind.employee,
  Map<String, String> subjectToEmployee = _toEmployee,
  String? employeeId,
  String? departmentId,
}) => aggregateSourceRows(
  rows: rows ?? _rows,
  scope: scope,
  subjectKind: subjectKind,
  subjectToEmployee: subjectToEmployee,
  employeeToDepartment: _toDepartment,
  employeeId: employeeId,
  departmentId: departmentId,
);

void main() {
  group('wider scopes SUM, they do not average', () {
    test('company sums numerator and denominator separately', () {
      // The whole reason rows carry both. Averaging the two ratios would
      // give 0.6; the correct answer is 40/80 = 0.5. The fixture uses
      // DIFFERENT volumes so the two answers cannot coincide.
      final r = run();
      expect(r.numerator, 40);
      expect(r.denominator, 80);
    });

    test('department sums only that department', () {
      final r = run(scope: KpiScope.department, departmentId: 'd-ops');
      expect(r.numerator, 40);
      expect(r.denominator, 80);
    });

    test('a department nobody belongs to is empty, not everyone', () {
      final r = run(scope: KpiScope.department, departmentId: 'd-mkt');
      expect(r.numerator, isNull);
      expect(r.denominator, isNull);
    });
  });

  group('personal scope', () {
    test('picks that employee only', () {
      final r = run(scope: KpiScope.personal, employeeId: 'e-bob');
      expect(r.numerator, 10);
      expect(r.denominator, 50);
    });

    test('an employee with no row is NO DATA, not zero', () {
      final r = run(scope: KpiScope.personal, employeeId: 'e-cara');
      expect(r.numerator, isNull);
      expect(r.denominator, isNull);
    });

    test('personal with no employeeId resolves to nobody, never everyone', () {
      final r = run(scope: KpiScope.personal);
      expect(r.numerator, isNull);
    });
  });

  group('unresolved subjects', () {
    test('count toward COMPANY and flag the result', () {
      // An unmapped key still happened. It must not vanish from a company
      // total, but it cannot be attributed to a department either.
      final r = run(
        rows: const [
          SourceRow(subjectKey: 'alice@x', numerator: 30, denominator: 30),
          SourceRow(subjectKey: 'ghost@x', numerator: 5, denominator: 5),
        ],
      );
      expect(r.numerator, 35);
      expect(r.denominator, 35);
      expect(r.unresolvedPresent, isTrue);
    });

    test('are EXCLUDED from a department but still flag it', () {
      final r = run(
        rows: const [
          SourceRow(subjectKey: 'alice@x', numerator: 30, denominator: 30),
          SourceRow(subjectKey: 'ghost@x', numerator: 5, denominator: 5),
        ],
        scope: KpiScope.department,
        departmentId: 'd-ops',
      );
      expect(r.numerator, 30, reason: 'the ghost has no department');
      expect(r.unresolvedPresent, isTrue);
    });

    test('all-resolved does not flag', () {
      expect(run().unresolvedPresent, isFalse);
    });
  });

  group('subject kinds', () {
    test('DEPARTMENT rows key on the department directly', () {
      final r = aggregateSourceRows(
        rows: const [
          SourceRow(subjectKey: 'd-ops', numerator: 8, denominator: 10),
          SourceRow(subjectKey: 'd-mkt', numerator: 2, denominator: 10),
        ],
        scope: KpiScope.department,
        subjectKind: SubjectKind.department,
        subjectToEmployee: const {},
        employeeToDepartment: const {},
        departmentId: 'd-ops',
      );
      expect(r.numerator, 8);
      expect(r.denominator, 10);
    });

    test('DEPARTMENT rows cannot produce a personal figure', () {
      final r = aggregateSourceRows(
        rows: const [SourceRow(subjectKey: 'd-ops', numerator: 8)],
        scope: KpiScope.personal,
        subjectKind: SubjectKind.department,
        subjectToEmployee: const {},
        employeeToDepartment: const {},
        employeeId: 'e-alice',
      );
      expect(r.numerator, isNull);
    });

    test('NONE is a single company figure', () {
      final r = aggregateSourceRows(
        rows: const [SourceRow(subjectKey: '', numerator: 123)],
        scope: KpiScope.company,
        subjectKind: SubjectKind.none,
        subjectToEmployee: const {},
        employeeToDepartment: const {},
      );
      expect(r.numerator, 123);
    });
  });

  group('degenerate input', () {
    test('no rows at all is NO DATA, not zero', () {
      final r = run(rows: const []);
      expect(r.numerator, isNull);
      expect(r.denominator, isNull);
    });

    test('a null denominator column stays null, it does not become zero', () {
      // COUNT KPIs have no denominator. Coercing to 0 would make every
      // ratio a division by zero instead of an honest count.
      final r = run(
        rows: const [SourceRow(subjectKey: 'alice@x', numerator: 4)],
      );
      expect(r.numerator, 4);
      expect(r.denominator, isNull);
    });

    test('rows present but all values null is NO DATA', () {
      final r = run(rows: const [SourceRow(subjectKey: 'alice@x')]);
      expect(r.numerator, isNull);
    });
  });
}
```

- [ ] **Step 2: Run it, watch it fail**

Run: `flutter test test/features/kpi_results/source_rows_test.dart`
Expected: FAIL — `source_rows.dart` does not exist.

- [ ] **Step 3: Implement, Step 4: Run it, watch it pass**

- [ ] **Step 5: Analyzer and commit**

```bash
flutter analyze lib test
git add lib/features/kpi_results/source_rows.dart test/features/kpi_results/source_rows_test.dart
git commit -m "feat(kpi): aggregate external source rows, summing rather than averaging"
```

---

### Task 2: Identifier validation

**Files:**
- Create: `lib/features/kpi_results/sql_identifier.dart`
- Create: `supabase/functions/_shared/source_query.ts`
- Test: `test/features/kpi_results/sql_identifier_test.dart`
- Test: `supabase/functions/_shared/source_query_test.ts`

**Interfaces:**
- Produces (Dart): `bool isValidSqlIdentifier(String value)`.
- Produces (TS): `export function quoteIdentifier(value: string): string` — throws on anything invalid; `export function buildSourceSelect(args: {schema: string, object: string, periodColumn: string, subjectColumn: string, numeratorColumn: string, denominatorColumn?: string}): string`.

Table and column names come from configuration and end up in SQL. **They are validated and quoted; only the period is a bound parameter.** Validation exists in both languages deliberately: Dart rejects bad input at the point an admin types it, TypeScript rejects it at the point it would execute. The TS one is the security boundary — the Dart one is a courtesy.

- [ ] **Step 1: Write both failing tests**

```dart
// test/features/kpi_results/sql_identifier_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/kpi_results/sql_identifier.dart';

void main() {
  test('accepts ordinary identifiers', () {
    for (final v in ['orders', 'order_lines', 'DailySalesFact', 'a1', '_x']) {
      expect(isValidSqlIdentifier(v), isTrue, reason: v);
    }
  });

  test('rejects everything that could change the statement', () {
    for (final v in [
      '',
      'a b',
      'a;b',
      "a'b",
      'a"b',
      'a-b',
      'a.b',
      'a--b',
      'a/*b',
      'a)b',
      '1abc',
      'orders; drop table employees',
    ]) {
      expect(isValidSqlIdentifier(v), isFalse, reason: v);
    }
  });

  test('rejects a name longer than Postgres allows', () {
    expect(isValidSqlIdentifier('a' * 64), isFalse);
    expect(isValidSqlIdentifier('a' * 63), isTrue);
  });
}
```

```ts
// supabase/functions/_shared/source_query_test.ts
// Run with: deno test supabase/functions/_shared/source_query_test.ts
import { assertEquals, assertThrows } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { buildSourceSelect, quoteIdentifier } from './source_query.ts';

Deno.test('quotes an ordinary identifier', () => {
  assertEquals(quoteIdentifier('orders'), '"orders"');
});

Deno.test('throws rather than escaping anything dangerous', () => {
  // Escaping would be a judgement call about what is safe. Refusing is not.
  for (const bad of ['a b', 'a;b', "a'b", 'a"b', 'a--b', '', 'a.b']) {
    assertThrows(() => quoteIdentifier(bad), Error, 'identifier');
  }
});

Deno.test('builds a SELECT with the period as a bound parameter', () => {
  const sql = buildSourceSelect({
    schema: 'public',
    object: 'v_fulfilment',
    periodColumn: 'period',
    subjectColumn: 'staff_email',
    numeratorColumn: 'correct_orders',
    denominatorColumn: 'total_orders',
  });
  assertEquals(
    sql,
    'select "period" as period, "staff_email" as subject_key, '
      + '"correct_orders" as numerator, "total_orders" as denominator '
      + 'from "public"."v_fulfilment" where "period" = $1',
  );
});

Deno.test('omits the denominator when the KPI has none', () => {
  const sql = buildSourceSelect({
    schema: 'public',
    object: 'v_errors',
    periodColumn: 'month',
    subjectColumn: 'buyer',
    numeratorColumn: 'error_count',
  });
  assertEquals(
    sql,
    'select "month" as period, "buyer" as subject_key, '
      + '"error_count" as numerator, null as denominator '
      + 'from "public"."v_errors" where "month" = $1',
  );
});

Deno.test('a hostile object name never reaches the statement', () => {
  assertThrows(
    () =>
      buildSourceSelect({
        schema: 'public',
        object: 'orders; drop table employees; --',
        periodColumn: 'p',
        subjectColumn: 's',
        numeratorColumn: 'n',
      }),
    Error,
    'identifier',
  );
});
```

- [ ] **Step 2: Run both, watch them fail. Step 3: Implement. Step 4: Run both, watch them pass.**

Run: `flutter test test/features/kpi_results/sql_identifier_test.dart` and `deno test supabase/functions/_shared/source_query_test.ts`

- [ ] **Step 5: Analyzer and commit**

```bash
flutter analyze lib test
git add lib/features/kpi_results/sql_identifier.dart supabase/functions/_shared/source_query.ts test/features/kpi_results/sql_identifier_test.dart supabase/functions/_shared/source_query_test.ts
git commit -m "feat(kpi): validate and quote source identifiers in both languages"
```

---

### Task 3: The configuration tables

**Files:**
- Create: `supabase/migrations/20260815000002_kpi_source_config.sql`
- Create: `lib/data/models/kpi_source_config.dart`
- Test: `test/data/models/kpi_source_config_test.dart`

**Do not apply the migration.**

**Before writing the credential column, verify Vault.** The spec says credentials live in Supabase Vault, referenced by name. **Vault has never been used in this project** — check whether `vault.create_secret` / `vault.decrypted_secrets` are available. If they are, use them. If they are not, fall back to the existing pattern (`authFromEnv()` in `_shared/lark.ts:18` reads function env vars) and **say so in your report with the consequence**: adding a connection then needs an admin to run `supabase secrets set` once per connection, so it is configuration-not-code but not self-service from the UI. Either way, **no password is ever stored in a table the app can read.**

Three tables per the spec's Data model section. `subject_kind` is `EMPLOYEE | DEPARTMENT | NONE`; `kind` is `POSTGRES | SUPABASE`. `denominator_column` is nullable — a COUNT KPI has none.

`kpi_subject_map` is unique on `(connection_id, external_key)` and resolves to either `employee_id` or `department_id`; add a check that exactly one of the two is set.

RLS: all three are configuration — admin-only read and write, company-scoped, via `auth_is_hr_or_admin()`. Read `20260814000004_kpi_results.sql`, which got this right, rather than an older policy. **No self-read clause.**

- [ ] **Step 1: Write the migration. Step 2: Models, failing test first.** Cover `fromRow`/`toUpsertPayload` for all three, the `SubjectKind` string mapping in both directions, and that a null `denominatorColumn` round-trips as null rather than becoming an empty string.

- [ ] **Step 3: Run, pass. Analyzer. Commit.**

```bash
git commit -m "feat(kpi): connection, binding and subject-map tables"
```

---

### Task 4: The configuration repository

**Files:**
- Create: `lib/data/repositories/kpi_source_config_repository.dart`
- Test: `test/data/repositories/kpi_source_config_repository_test.dart`

**Interfaces:**
- Produces: `listConnections()`, `upsertConnection(KpiConnection)`, `listBindings()`, `bindingForKpi(String kpiId)`, `upsertBinding(KpiSourceBinding)`, `deleteBinding(String id)`, `subjectMapFor(String connectionId)`, `upsertSubjectMapping(KpiSubjectMap)`, `deleteSubjectMapping(String id)`.

Single-column writes where the screen edits one thing; whole-row upserts otherwise. **When you reconstruct a model to save it, carry every field.** A caller that rebuilds an object field-by-field and forgets one has cost this repo real data twice, and the model test cannot catch it — `fromRow`/`toUpsertPayload` round-trip fine while the caller drops the value. Assert **values**, not key presence: a `containsKey` check passes against that bug.

- [ ] **Step 1: Failing test. Step 2: Run. Step 3: Implement. Step 4: Run. Step 5: Analyzer, commit.**

```bash
git commit -m "feat(kpi): read and write source configuration"
```

---

### Task 5: The fetch edge function

**Files:**
- Create: `supabase/functions/fetch-kpi-source/index.ts`
- Test: `supabase/tests/fetch_kpi_source_test.ts`

**Interfaces:**
- Consumes: `buildSourceSelect`, `quoteIdentifier` from `_shared/source_query.ts`.
- Produces: POST `{ binding_id, period }` → `{ rows: [{ subject_key, numerator, denominator }] }`, or `{ error }` with a non-2xx status.

**This is the first edge function in this repo to connect to an external Postgres.** Every existing one uses `@supabase/supabase-js` against our own database. Pin a driver version and say in your report which you chose and why.

The function: loads the binding and its connection, obtains the credential (Vault or env, per Task 3's finding), connects **read-only**, runs `buildSourceSelect` with the period bound as `$1`, and returns rows. Numerator and denominator come back as numbers or null — **never coerce a null to 0.**

Every failure returns a non-2xx with a short reason. It must not leak the connection string, the password, or the full driver error into the response body — those go to the function log.

- [ ] **Step 1: Write the failing test.** Cover the pure parts you can reach without a live database: that a missing `binding_id` is rejected, that an unknown binding is a 404, and that a binding whose identifiers fail validation is rejected **before** any connection is attempted. Say plainly in the report that live connectivity is not unit-testable and needs a manual check.

- [ ] **Step 2: Run, fail. Step 3: Implement. Step 4: Run, pass. Step 5: Commit.**

```bash
git commit -m "feat(kpi): fetch rows from a configured external source"
```

---

### Task 6: The configured source

**Files:**
- Create: `lib/features/kpi_results/configured_source.dart`
- Test: `test/features/kpi_results/configured_source_test.dart`

**Interfaces:**
- Produces: `class ConfiguredSource implements KpiSource` — `String get key` returns `'cfg:<bindingId>'`; `read({required KpiScope scope, required String period, List<String> employeeIds})`.
- Consumes: `aggregateSourceRows` (Task 1), the repository (Task 4), and a fetcher function injected through the constructor so no test touches Supabase.

The existing interface, verbatim from `automatic_sources.dart:24-32`:

```dart
abstract class KpiSource {
  String get key;
  Future<KpiSourceInput> read({
    required KpiScope scope,
    required String period,
    List<String> employeeIds = const [],
  });
}
```

**Where `employeeToDepartment` comes from, and the trap in it.** `aggregateSourceRows` needs a map of employee → department. Build it by resolving each employee's department **through their ROLE** (`role_scorecards.department_id`), never from `employees.department_id`. That column is a denormalised copy written by the employee form at save time, so it goes stale the moment a role moves to another department and its holders are not re-saved. `populationFor` in `kpi_population.dart` already resolves it correctly and has a test pinning that the stale copy loses — read it and match it rather than inventing a second rule.

**Every failure becomes `(null, null)`.** The fetcher throwing, a non-2xx, a malformed body, an unparsable number — all of them. Never a partial number and never a zero; `computeResults` turns a null into `NO_DATA`/`MISSING_SOURCE`, which is the honest answer.

- [ ] **Step 1: Write the failing test.** Cover: a happy path producing the aggregate from Task 1; the fetcher throwing → `(null, null)`; a non-2xx → `(null, null)`; a body missing the `rows` key → `(null, null)`; and a row whose numerator is a string → that row contributes nothing rather than crashing the whole read.

For each of those failure branches, delete the guard, watch the test go red, restore it, and paste both.

- [ ] **Step 2: Run, fail. Step 3: Implement. Step 4: Run, pass. Step 5: Analyzer, commit.**

```bash
git commit -m "feat(kpi): a KPI source backed by configuration"
```

---

### Task 7: Composing the registry

**Files:**
- Modify: `lib/features/kpi_results/automatic_sources.dart`
- Test: `test/features/kpi_results/automatic_sources_test.dart`

**Interfaces:**
- Modifies: `buildSourceRegistry` gains `List<ConfiguredSource> configured = const []`, merged into the same map.

Configured sources join the map the two code sources already build. **A configured source must not silently replace a code source with the same key** — the code ones are `app.attendance.present_days` and `app.reviews.completed_on_time`, configured ones are `cfg:<id>`, so a collision means something is wrong rather than something to resolve quietly.

Note the existing doc comment saying two planned sources were **dropped** by the owner rather than deferred; do not resurrect them.

- [ ] **Step 1: Failing test** — a registry built with both kinds contains both; a configured source colliding with a code key is rejected rather than overwriting. **Step 2-4: Run, implement, run. Step 5: Commit.**

```bash
git commit -m "feat(kpi): the registry takes configured sources alongside code ones"
```

---

### Task 8: Settings ▸ KPI Sources

**Files:**
- Create: `lib/features/settings/kpi_sources/kpi_sources_settings_screen.dart`
- Modify: `lib/features/settings/settings_screen.dart`
- Test: `test/features/settings/kpi_sources_settings_screen_test.dart`

Three sections: connections, bindings (per KPI), and the subject map for a chosen connection.

Follow `lib/features/settings/leave_types/leave_types_settings_screen.dart` — it is the most recent settings screen and has the shape to copy, including how it registers its tab in `settings_screen.dart`'s `_Tab` enum, its desktop tile list and its `_body()` switch. Tables wrap with `lib/widgets/responsive_table.dart`.

A binding form must not let an admin save an identifier `isValidSqlIdentifier` rejects — refuse at the point of typing, with the reason.

- [ ] **Step 1: Failing widget test.** Cover: the three sections render; an invalid identifier blocks save and says why; a binding with no denominator column saves with null rather than an empty string. **Step 2-4: Run, implement, run. Step 5: Analyzer, commit.**

```bash
git commit -m "feat(kpi): author connections, bindings and the subject map in settings"
```

---

### Task 9: Unmapped subjects are visible

**Files:**
- Modify: `lib/features/settings/kpi_sources/kpi_sources_settings_screen.dart`
- Modify: `lib/features/kpi_results/configured_source.dart`
- Test: `test/features/settings/kpi_sources_settings_screen_test.dart`

The spec's "Done when" requires an unmapped subject to be **visible somewhere an admin can fix it**. Without this the failure mode is a company figure that is right and a department figure that is quietly short — the exact silent-undercount this engine exists to avoid.

`aggregateSourceRows` already returns `unresolvedPresent`. Surface the actual unmapped keys: `ConfiguredSource` collects them, and the settings screen lists "keys this connection returned that map to nobody", each with a control to map it.

- [ ] **Step 1: Failing test** — a fetch returning an unknown key surfaces that key in the settings list, and mapping it makes it disappear. **Step 2-4: Run, implement, run. Step 5: Analyzer, commit.**

```bash
git commit -m "feat(kpi): unmapped source keys are listed where they can be fixed"
```

---

## Done when

- An admin adds a connection, binds a KPI to a table and its columns, and the KPI computes with no code change.
- A binding whose source is unreachable produces `NO_DATA`/`MISSING_SOURCE`, and the other KPIs in the same recompute still produce rows.
- Department and company figures from an external source are sums of numerator and denominator, not averages of ratios — pinned by a test whose two subjects have different volumes.
- An unmapped subject is listed in Settings where it can be mapped.
- No credential is stored outside Vault (or function secrets, per Task 3's finding), and no identifier reaches SQL unvalidated.
- `flutter test` green; `flutter analyze lib test` 0 errors, 0 warnings.
- One migration committed and handed over, **not applied**: `20260815000002`.

## Not in this plan

Lark Base connections, Excel upload, and any UI for browsing a source's tables to help build a binding. The last is tempting and is exactly how a column mapper becomes a database client.
