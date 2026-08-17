# SDD ledger — plan: docs/superpowers/plans/2026-08-14-configurable-kpi-sources.md

Worktree: .claude/worktrees/kpi-sources (branch kpi-sources)
Base commit: 47ab053 (local main)
Baseline: 1491 passing, 1 skipped; analyzer 0 errors / 0 warnings / 192 infos.

Pre-flight scan — two conflicts found and RULED before Task 1, so neither
becomes a mid-plan interrupt:

  1. TASK 3 ASKS FOR SOMETHING THE GLOBAL CONSTRAINTS FORBID. The plan says
     "verify Vault is available on this project before the plan depends on
     it" — but an implementer has no database authority and cannot run any
     supabase command. As written the task is impossible.
     RULED: the implementer must NOT attempt to connect or verify. Design the
     schema so it works either way — a `credential_ref` (text) plus a
     `credential_kind` check constraint of `VAULT | ENV` — and document both
     retrieval paths in the migration's comment. The OWNER decides which at
     apply time, and the edge function reads `credential_kind` to know where
     to look. This is strictly better than picking one blind: it removes the
     verification step from the critical path without guessing.

  2. NAME COLLISION, same class as one caught two plans ago. Task 1 declares
     `enum SubjectKind` in `lib/features/kpi_results/source_rows.dart`, and
     Task 3 needs it in `lib/data/models/kpi_source_config.dart`. A model
     importing a feature is the exact violation this repo already ruled
     against — it is why `kpi_goal.dart` and `kpi_result.dart`'s enums live
     under `models/`.
     RULED: `SubjectKind` is declared by TASK 1 in
     `lib/data/models/kpi_source_config.dart`, and `source_rows.dart` imports
     it. Task 3 extends that file rather than creating it. Precedent: Task 1
     of the results plan created `kpi_result.dart` holding only enums, and
     Tasks 2 and 4 extended it.

Carried from the two prior plans, all still live:
  - Every failure resolves to NO_DATA / MISSING_SOURCE. Never a partial
    number, never a zero.
  - Defaults must fail toward LESS. Six defects on the previous plan were a
    fallback producing something plausible instead of nothing; one regression
    was its mirror, producing nothing when the honest answer was "this one
    number is unknown".
  - `ref.invalidate` on an UNWATCHED FutureProvider is a no-op — an
    invalidation test needs a live Consumer watcher plus a fetch-count
    override.
  - A caller that reconstructs a model field-by-field and forgets one has
    cost this repo real data twice; the model test cannot catch it. Assert
    VALUES, never key presence.
  - Two raw NUL bytes have shipped here. One made a whole file binary to git,
    so its review package showed nothing and a package-only review would have
    approved an unreviewed change. Every review on this plan reads files off
    disk.
  - Five tautological tests caught, the last in a fixture I supplied. Delete
    the guard, watch it go red, restore — and the controller spot-checks that
    claim rather than accepting it.

Department resolution: through the ROLE (`role_scorecards.department_id`),
never `employees.department_id`. That column is a denormalised copy written by
the employee form and goes stale when a role changes department.
`kpi_population.dart` already does this and has a test pinning that the stale
copy loses.

Task 1: implemented (commit 02824b5; 1506 pass / 1 skip, +15).
  Both pre-flight rulings held: SubjectKind landed in
  lib/data/models/kpi_source_config.dart and source_rows.dart imports it, so
  the data layer does not depend on a feature.
Task 1: THE IMPLEMENTER DISCLOSED ITS OWN GAP rather than hiding it — three
  of the nine SubjectKind x scope cells had no direct test and were
  implemented by extrapolating "no identity, no data". The reviewer traced
  all nine through the actual control flow and confirmed the extrapolations
  were deliberate rather than accidental.
Task 1: review — spec ✅, 1 Important, and it is the most interesting kind:
  THE CODE WAS RIGHT FOR A REASON NOBODY HAD WRITTEN DOWN.
  unresolvedPresent is computed globally and returned on every branch
  including personal, so an unrelated unmapped key flags Alice's personal
  result even though her 30/30 is untouched. That reads like a leak, and the
  reviewer proposed it as a semantic decision hiding as a control-flow side
  effect.
  CONTROLLER RULED IT MUST NOT CHANGE, after checking the precedent:
  compute_kpi_results.dart's _scopedExceptions already governs this exact
  shape — "an unattributed row has nobody to attribute it to, so it is
  excluded, but excludedUnattributed says so, rather than assert a confident,
  wrong zero". The transferable point the reviewer's analysis was missing:
  AN UNMAPPED KEY MIGHT BE ALICE'S. If the source emits alice.smith@x and
  only alice@x is mapped, she has a second row nobody resolved and her figure
  is understated. A clean COMPLETE beside a possibly-short number is the
  failure this engine exists to prevent.
Task 1: fix round 1/5 (1 addressed, 0 open; commits 02824b5..74691e9).
  NO behaviour change — documentation plus tests. The comment says why, cites
  _scopedExceptions BY NAME so the two rules read as one rule, and states the
  known over-breadth explicitly: it flags every personal row because there is
  no way to know which unresolved key belongs to whom, and a guaranteed-safe
  over-report beats a guessed under-report.
  Re-reviewer verified the mutation itself (deleted the personal branch's
  propagation, got Expected: true / Actual: false, only that test failed) and
  confirmed the DEPARTMENT-at-company test asserts a genuine SUM (8/10 + 2/10
  = 10/20) rather than a single row that would pass either way.
Task 1: complete (commits 47ab053..74691e9, review clean). 1510 pass /
  1 skip, analyzer 0 errors / 0 warnings / 192 infos.

*** THREE PASSES, THREE DIFFERENT CATCHES, worth remembering as the argument
    for this process: the implementer disclosed a gap it could have hidden;
    the reviewer found something real the implementer had missed; and the
    reviewer's own proposed conclusion was itself incomplete, resolved only
    by going and reading the precedent in a neighbouring file. ***

Task 2: implemented (commit 533450d; 1513 pass / 1 skip, +3 Dart, +6 Deno).
  The implementer treated the brief's rejection list as a FLOOR and added NUL
  and non-ASCII cases to both suites. It also caught a raw NUL byte leaking
  into its own report draft and removed it before commit — third NUL incident
  in this project, first one that never reached a committed file.
Task 2: review CLEAN — spec ✅, quality approved, no findings. Reviewed by a
  security engineer with instructions to ATTACK the validator, not read it.
  What it threw at both implementations (as escapes, in throwaway probes
  outside the repo): LF, CR, VT, FF, BEL, 0x1F, DEL, NUL; U+2028/2029; ZWJ;
  combining acute; BOM/ZWNBSP; LRM and RTL override; fullwidth "admin";
  dotless-i homoglyph; precomposed vs decomposed e-acute; all-caps, all-digit,
  whitespace-only, empty; 63 vs 64 ASCII; 60-code-unit emoji; 62-code-unit
  combining marks; 63 x 2-byte e-acute (126 bytes). ALL REJECTED by both.
Task 2: THE STRUCTURAL REASON IT HOLDS, worth keeping — the whitelist
  `^[A-Za-z_][A-Za-z0-9_]*$` is ASCII-only, so any string that passes is one
  byte per character in UTF-8. Postgres truncates identifiers at 63 BYTES; a
  63-CHARACTER check can therefore never diverge from it. The byte-vs-char
  concern the brief raised is structurally MOOT, not merely untested.
  Also verified empirically rather than assumed: `$` in both Dart's and
  Deno's non-multiline RegExp does not match before a trailing newline, so
  there is no trailing-LF bypass.
Task 2: the two implementations are genuinely independent — no shared regex,
  no import between them, and the TS doc comments explicitly warn against
  trusting the Dart side. That was the point: Dart is a courtesy at the point
  of typing, TS is the boundary at the point of execution, and it must hold
  when the Dart side is bypassed entirely.
Task 2: period binding confirmed — buildSourceSelect never touches the period
  VALUE, only the period COLUMN name; output matches the brief byte for byte.
  The optional denominator generates `null as denominator`, and SourceRow
  keeps numerator/denominator independently nullable so null never becomes 0
  downstream.
Task 2: complete (commits 74691e9..533450d, review clean). 1513 pass /
  1 skip, analyzer 0 errors / 0 warnings / 192 infos.

Task 3: implemented (commit cd0ddf5; 1523 pass / 1 skip, +10).
Task 3: THE PRE-FLIGHT RULING PAID OFF. The plan told the implementer to
  "verify Vault is available", which it cannot do — no database authority.
  Ruled before dispatch: schema carries credential_ref + credential_kind
  (VAULT|ENV), both retrieval paths documented, owner decides at apply time.
  The reviewer recognised it as a sanctioned deviation rather than flagging
  it as drift, and confirmed no password can land in an app-readable column
  either way.
Task 3: the implementer flagged TWO things instead of guessing.
  (a) Nothing stopped two bindings existing for one KPI, and the spec was
      silent. It declined to invent a rule outside its brief — correct.
  (b) Admin-only RLS departs from kpi_readings, which also admits a manager
      for their own reports.
  Reviewer ruled (b) correct: these tables hold connection details and column
  mappings, not anyone's performance data. Admin-only is right FOR
  CONFIGURATION.
Task 3: MY SPEC GAP on (a), ruled: ONE ACTIVE BINDING PER KPI. The reason is
  about selection, not tidiness — a KPI picks its source by matching
  kpis.numerator_source against a registry key, and Task 6 keys configured
  sources as cfg:<bindingId>. With two bindings allowed, an admin would have
  to paste a binding uuid into a free-text field to say which wins.
  Reviewer confirmed ZERO BLAST RADIUS before it was added: no .single(), no
  firstWhere, no kpi_id-keyed map anywhere in the tree, and Tasks 4-6 unbuilt.
  Cheap now, awkward once a consumer had picked a side.
Task 3: fix round 1/5 (1 addressed, 0 open; commits cd0ddf5..e93319b).
  Added into the SAME unapplied migration rather than a later one — fixing an
  unshipped migration with another migration is noise.
  The implementer's comment improved on my instruction: partial on is_active
  so a retired binding can be DEACTIVATED AND REPLACED without deleting
  history. I had only said "one active binding"; it worked out why partial
  was the right shape rather than a plain unique index.
  It also declined to write a Dart test for a schema-only constraint nothing
  reads yet, and said so plainly instead of asserting nothing. After five
  tautologies on the previous plan, that is the right instinct.
Task 3: complete (commits 533450d..e93319b, review clean). 1523 pass /
  1 skip, analyzer 0 errors / 0 warnings / 192 infos.

Task 4: implemented (commit 57419de; 1538 pass / 1 skip, +15). Plan-doc typo
  fix 31a680e alongside.
Task 4: MY FOURTH BRIEF DEFECT, caught the same way as the others — the brief
  named the model KpiSubjectMapping; Task 3 actually created KpiSubjectMap.
  The implementer used the REAL type and flagged the mismatch rather than
  inventing a class to satisfy the brief. Corrected in the plan (31a680e) so
  Tasks 6, 8 and 9 do not inherit it; a wrong type name in a brief is how a
  later implementer ends up writing an adapter for something that never
  existed.
Task 4: review CLEAN — spec ✅, quality approved, no findings.
  bindingForKpi is `.eq('kpi_id').eq('is_active', true).maybeSingle()` —
  filters on BOTH columns (inactive bindings for the same KPI legitimately
  exist and must not be returned) and uses maybeSingle rather than single, so
  "no binding" is a normal state instead of a throw. The test asserts the
  outgoing request carries is_active=eq.true explicitly rather than passing
  by accident.
  THE FIELD-DROP BUG HAS NO SURFACE HERE, and the reviewer worked out WHY
  rather than only checking: the repository never RECONSTRUCTS a model. Every
  upsert forwards the caller's own toUpsertPayload() whole. That is a
  structural answer rather than a per-field audit passing by luck — though it
  produced the per-field table anyway, and all 29 fields survive.
  denominatorColumn survives as null via the model's _blankToNull, pinned by
  a test asserting present-and-null plus a second asserting a real value.
Task 4: no single-column methods, and the class doc explains why by
  contrasting with LeaveTypeRepository.setPaid/setActive — deliberate rather
  than an omission. Only the base provider is declared, matching
  KpiResultRepository; the FutureProvider LeaveTypeRepository has exists
  because its screen already does, and Task 8's does not yet.
Task 4: controller verified the full suite itself — the reviewer disclosed it
  had skipped that run. 1538 pass / 1 skip, confirmed.
Task 4: complete (commits e93319b..31a680e, review clean).

Task 5: implemented (commit b2d3968) — the first edge function in this repo to
  connect to a FOREIGN database. Driver pinned to deno-postgres v0.19.3,
  reusing a pin wp_task_assignments_backfill_test.ts already exercises rather
  than introducing a second one.
Task 5: MY FIFTH SCHEMA GAP, flagged by the implementer instead of guessed —
  kpi_connections had credential_ref and credential_kind but NO USERNAME. It
  resolved by requiring the secret to be "user:password" split on the FIRST
  colon (so a password containing colons still works) and asked for sign-off.
  RULED THE OTHER WAY: the implementation was correct, but schema and function
  disagreed — the migration comment implied password-only. Username is not a
  secret; it is configuration. An admin cannot see which user a connection
  authenticates as without reading a secret they may not have access to;
  rotating a password should not require re-typing a username; and a parsing
  convention has to be documented, honoured twice and remembered a year on.
  Fix round 1 (1bef870) added db_user across migration/model/function.
  THE REPOSITORY NEEDED NO CHANGE — it forwards toUpsertPayload() whole, the
  structural property Task 4's review identified, already paying off.
Task 5: security review (opus) — spec ✅, 3 Important + 3 Minor.
  IMPORTANT 1, the worst: NO ROLE GATE. The function accepted any caller with
  a company_id claim, then read admin-only config with the SERVICE-ROLE key.
  A rank-and-file employee's JWT could POST arbitrary binding_ids and receive
  every employee's subject_key/numerator/denominator for any period, plus a
  404-vs-502 oracle for enumerating binding UUIDs and probing whether a
  configured host:port answers. The service key was bypassing exactly the RLS
  the spec relies on.
  IMPORTANT 2: TLS NOT ENFORCED. deno-postgres v0.19.3 defaults to
  {enabled: true, enforce: false}, so against a source without SSL the driver
  SILENTLY CONTINUES IN PLAINTEXT — SCRAM handshake and every row in the
  clear, with no signal. The kind of default that looks fine in every test and
  matters exactly once.
  IMPORTANT 3: connect() sat outside try/finally, so a session landing after
  the 8s timeout stayed open on the external database and, via the Vault path,
  on ours. The timer was never cleared either.
  MINOR: Number('') === 0 — the exact null-becomes-zero class this plan bans;
  String(null) subject_key becoming the literal "null"; stale user:password
  text left in the migration and report.
Task 5: fix round 2/5 (5 addressed, 0 open; commits 1bef870..a120c16).
  authorize() runs FIRST, fails closed on throw/timeout/unexpected, and uses a
  CALLER-SCOPED client (anon key + the caller's Authorization header) —
  re-reviewer confirmed it is distinct from the service key, which is now used
  only after the caller has passed.
  tls enforce:true on the external path; withRequireSsl for the Vault DSN via
  string surgery rather than the URL class, which re-encodes and would corrupt
  a password. Four tests cover no-query, existing-query, existing-sslmode and
  a colon-in-password case.
  withConnectedClient is now the single place either connection calls
  connect(), inside try/finally; .end() is swallowed so it cannot mask the
  original error.
  Deno tests 17 -> 32, and the re-reviewer confirmed all 15 additions map to
  distinct behaviour changes rather than padding.
Task 5: THREE SABOTAGE PROOFS, one reproduced independently by the reviewer —
  removing the 403 branch turns 2 tests red (500s from forbiddenLoader,
  proving the loader was reached, which is the right failure signature).
Task 5: complete (commits 31a680e..a120c16, review clean). Deno 32/32,
  1539 pass / 1 skip, analyzer 0 errors / 0 warnings / 192 infos.

*** READ-ONLY IS ENFORCED IN CODE **AND** REMAINS A DEPLOYMENT REQUIREMENT.
    createTransaction(..., {read_only: true}) emits a real BEGIN ... READ ONLY
    in the pinned driver, verified in its source, so a write is refused by
    Postgres itself. That does NOT bound what can be READ — the grants on
    db_user are the only control there. When the owner creates that user in
    Cashflow, grant select on the specific views being exposed, not the
    schema. ***

STILL UNTESTED AND NEEDING A LIVE CHECK (honest list, confirmed complete by
the reviewer, and no test fakes any of it): a real connect, a real Vault read,
TLS negotiation AND the enforce-refusal path, deno-postgres numeric/bigint OID
decoding, timeout behaviour under a slow host, and whether the deployed
db_user is genuinely read-only.

Task 6: complete (commits 2f4c7b0, 4fe6054, 7e8cd62; re-review clean).
  1562 pass / 1 skip, analyzer 0 errors / 0 warnings / 192 infos.

*** THE SCOPE-DEPENDENT COLLAPSE IN read() IS NOT AN INCONSISTENCY.
    configured_source.dart:222 collapses to (null,null) on an unresolved
    subject for PERSONAL and DEPARTMENT but NOT for COMPANY. Reason, verified
    against source_rows.dart:154-177 rather than assumed: COMPANY sums ALL
    rows including unresolved ones, so its figure is already correct and
    blanking it would throw away a good number; PERSONAL/DEPARTMENT filter to
    resolved rows, so an unmapped key can make those short. Anyone
    "simplifying" this into uniform collapsing takes every company KPI from a
    configured source down over one unmapped key. The comment at :200-220
    carries the reason; a test pins each direction. ***

Task 6: MY BRIEF UNDERSTATED THE CONSTRUCTOR. It said the repository plus a
  fetcher; aggregateSourceRows also needs employeeToDepartment, so the
  implementer injected the full KpiSourceBinding (not an id — there is no
  bindingById repo method), a subjectMapFor-shaped reader, and plain
  employees/roles lists. Task 7 has to supply all of that.

Task 7: complete (commits 8ef8cd1, 2733bf8, 9219743; review clean, one Minor
  taken as a comment). 1571 pass / 1 skip, analyzer 0/0/192.

*** TASK 7 WAS THE TASK THAT MADE THIS FEATURE EXIST AT ALL. My plan gave
    Tasks 7-9 as registry / settings screen / unmapped-subject visibility and
    NEVER connected bindings to a recompute -- Tasks 1-6 would have shipped as
    dead code an admin could configure and nothing would ever read. I also
    never noticed that ConfiguredSourceFetcher had no implementation, so no
    configured source could reach the Task 5 edge function. Both folded into
    Task 7 (Parts C and D). Look for this gap class in Tasks 8-9. ***

*** THE REGISTRY KEY IS cfg:<kpiId>, NOT cfg:<bindingId> (changed in 8ef8cd1).
    The key must sit verbatim in kpis.numerator_source for
    registry[kpi.numeratorSource] to resolve. Keyed by binding id, retiring a
    binding and creating a replacement (legal -- the partial unique index only
    constrains ACTIVE rows) mints a new id and SILENTLY drops that KPI to
    NO_DATA until someone rewrites the column. Task 8's binding form must
    write 'cfg:<kpiId>' into numerator_source; it is knowable before the
    binding row is inserted, which is half the point. ***

Task 7: the plan's stated collision (a configured key equal to a code key) is
  structurally unreachable -- configured keys are cfg:-prefixed, code keys are
  bare app.* -- confirmed by the reviewer. The guard is generic and stays; the
  tested collision is the reachable one, two configured sources sharing a
  kpiId.

*** A REGISTRY THAT CANNOT BE BUILT ABORTS THE WHOLE RECOMPUTE, ON PURPOSE.
    kpi_results_screen.dart's degrade-catch wraps listBindings() ONLY. The
    ConfiguredSource loop and buildSourceRegistry sit outside it, so an
    ArgumentError (null binding.id) or StateError (key collision) kills the
    whole run. That is intended: a source that cannot be READ has a per-KPI
    blast radius (_readSource contains it), but a registry that cannot be
    BUILT means we do not know which source belongs to which KPI, so there is
    nothing to fall back to. Widening the catch would turn a broken config
    into a silent partial recompute. Comment at :304. ***

Task 8: complete (commit 06cf8e2, review clean, no Critical/Important).
  1578 pass / 1 skip, analyzer 0/0/192.

*** BINDING A KPI WRITES kpis.numerator_source VIA setKpiNumeratorSource
    (kpi_source_config_repository.dart:290) -- a single-column update, NOT
    saveLibraryKpi(writeDefinition: true). writeDefinition rewrites the whole
    definition block (value_type, numerator_label, denominator_source, unit,
    cadence, proof_type) and Postgrest writes every key present in the map,
    so binding a KPI through it would blank the formula as a side effect.
    That defect has already happened twice in that file's history. Unbinding
    AND deactivating both clear the column back to null -- a KPI pointing at
    a dead source is the same silent NO_DATA in reverse. ***

Task 8: MY BRIEF WAS WRONG that the repository "already has every read you
  need" -- the methods existed but none were wired into Riverpod, which is how
  every sibling settings screen exposes reads. The implementer added
  kpiConnectionsProvider / kpiSourceBindingsProvider / kpiSubjectMapProvider
  (family-keyed by connectionId). Reviewer traced every write path's
  invalidation; no stale-list gap.

Task 8: two Flutter traps now fixed and worth remembering -- PendingMigration-
  Notice's ExpansionTile hard-errors without a Material ancestor (use Card,
  not a BoxDecoration'd Container), and DropdownButtonFormField overflows and
  throws without isExpanded: true once a label is long enough.

Task 9: complete (commits 2bbdaff + a doc fix; review clean, no Critical or
  Important). 1584 pass / 1 skip, analyzer 0/0/192. ALL NINE TASKS DONE.

*** TASK 6 SHIPPED A REAL DEFECT AND TASK 6'S REVIEW MISSED IT. Until Task 9,
    ConfiguredSource resolved ONLY EMPLOYEE-kind bindings through
    kpi_subject_map (06cf8e2's configured_source.dart:352-356), and
    unresolvedSubjectKeys was gated on subjectKind == employee, so a
    DEPARTMENT-kind binding could never report an unmapped key. A department
    KPI fed by an external source would have reported a SHORT number with
    nothing flagged -- precisely the silent undercount this branch exists to
    prevent. It surfaced only because Task 9 tried to build a UI on top of
    that data and found it permanently empty. Verified independently against
    06cf8e2 by the reviewer, not taken on the implementer's word.
    LESSON: a review that checks "does the code do what the brief said"
    cannot catch a brief that only ever described one of three enum cases. ***

Task 9: the DEPARTMENT fix translates subjectKey through subjectToDepartment
  into `effectiveRows` BEFORE aggregateSourceRows sees them, because
  aggregateSourceRows (source_rows.dart:104-118) does raw equality against
  departments.id and translates nothing. An unmapped code falls through as
  the raw external key: excluded at DEPARTMENT (matches no department id),
  still summed at COMPANY -- same rule as EMPLOYEE-kind, which is what
  read()'s scope-dependent collapse depends on. A raw key colliding with a
  real department uuid is not structurally prevented, only practically
  implausible.

WHOLE-BRANCH REVIEW: done, two reviewers (correctness + security).
  Security: no Critical/High exploitable. Two Mediums, both hardening and
  neither a blocker -- kpi_connections.host/port are free-text so a
  compromised admin account can use the edge function as a reachability
  oracle for internal addresses (an egress allowlist as a function secret
  would close it WITHOUT a migration); and no deno.lock pins the transitive
  dep tree (pre-existing repo pattern, not this branch).
  Correctness: one Important -- the unpaginated config reads, fixed in the
  single fix wave (8daeb5a).

*** THE FIX WAVE'S OWN RE-REVIEW FOUND A SECOND BUG IN THE FIX. Paging by a
    NON-UNIQUE column is not stable across requests: Postgres may split a
    tied group differently per page, dropping some rows and repeating others.
    listConnections ordered by `name` and listBindings by `object_name`,
    neither unique -- and object_name ties are the NORMAL case, since many
    KPIs read from one view. That would have converted a truncation bug
    (consistently short) into an intermittent wrong-rows bug (harder to see,
    harder to diagnose). Fixed in f3a4240 by adding .order('id') to all three.
    Precedent: attendance_repository.dart:102-103 already does this. ***

*** postgrest-dart's .order() DEFAULTS TO DESCENDING. Found by writing the
    test for the above, not by either review: the bare .order('name') listed
    connections Z-to-A in Settings. All three reads now pass
    ascending: true explicitly. Siblings that pass ascending: false do so
    deliberately, for dates they want newest-first. ***

*** A ROW-COUNT PAGINATION TEST CANNOT CATCH AN UNSTABLE SORT. Proven, not
    assumed: under the sabotage that drops listBindings' tiebreaker, the
    "returns every row past 1000" test stays GREEN and only the order-clause
    test goes red. The fake slices a fixed in-memory list by offset/limit, so
    it always pages deterministically and can never reproduce tie-splitting.
    The three new tests assert the emitted `order=` query parameter instead.
    That blind spot is exactly how the missing tiebreaker survived the fix
    wave that added the paging. ***

Final: 1592 pass / 1 skip, analyzer 0 errors / 0 warnings / 192 infos.
REMAINING: the merge menu. Branch is ready.
