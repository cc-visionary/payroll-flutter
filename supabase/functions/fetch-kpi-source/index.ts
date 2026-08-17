// Edge Function: fetch-kpi-source
//
// The FIRST edge function in this repo to open a connection to a database
// this app does not own. Every other function under supabase/functions/
// talks to our own Supabase project through @supabase/supabase-js. This one
// reads rows out of a source system an admin configured — Cashflow's own
// Postgres today, per docs/superpowers/specs/2026-08-14-configurable-kpi-sources-design.md.
//
// POST { binding_id, period } -> { rows: [{ subject_key, numerator, denominator }] }
//                              | { error, code } with a non-2xx status
//
// Flow, in the order that matters for security:
//   0. Gate the CALLER. This function reads admin-only configuration
//      (kpi_connections/kpi_source_bindings — RLS on both is
//      `auth_is_hr_or_admin()`, no self-read clause) using the SERVICE-ROLE
//      key, which bypasses that RLS entirely — so this function, not
//      Postgres, is the only thing standing between a rank-and-file
//      employee's JWT and every employee's numerator/denominator for any
//      period. `authorizeCaller` below re-checks the caller's role via
//      `auth_is_hr_or_admin()` through a CALLER-scoped client (anon key +
//      the incoming Authorization header, mirroring
//      `send-performance-self-reviews/index.ts`'s `caller` client and
//      `ReviewCycleRepository.callerSeesAllReviews()`
//      (lib/data/repositories/review_cycle_repository.dart)). Anything
//      other than HR/admin is a 403, before the binding is even looked up
//      — see supabase/tests/fetch_kpi_source_test.ts for the test proving
//      this ordering.
//   1. Load the binding (kpi_source_bindings) and its connection
//      (kpi_connections) from OUR OWN database.
//   2. Build the external SELECT via `buildSourceSelect`
//      (../_shared/source_query.ts). THIS is where object_name and the four
//      *_column identifiers get validated — buildSourceSelect throws on
//      anything that fails `quoteIdentifier`. A binding with a bad
//      identifier must fail HERE, before any credential is looked up and
//      before any network connection to the external database is attempted.
//      `handleFetchRequest` below calls this strictly before touching
//      `loader.getCredentialSecret` or `runQuery` — see
//      supabase/tests/fetch_kpi_source_test.ts for the test that proves the
//      ordering, not just the outcome.
//   3. Resolve the credential per `connection.credential_kind` (VAULT or
//      ENV — see the CREDENTIAL RESOLUTION section below).
//   4. Connect to the external database READ-ONLY and run the one
//      statement `buildSourceSelect` produced, period bound as $1.
//   5. Return rows. numerator/denominator come back as number OR null —
//      never coerce a null to 0 (see `toNumberOrNull`). A COUNT KPI has no
//      denominator at all; a false zero would turn that honest absence into
//      a division by zero downstream in the compute engine.
//
// Every failure is a non-2xx with a SHORT, generic reason. The response
// body must never contain a connection string, a password, or a raw driver
// error — those are logged via console.error (function logs only) and
// never interpolated into anything returned to the caller.
//
// ---------------------------------------------------------------------------
// DRIVER CHOICE
// ---------------------------------------------------------------------------
// `deno-postgres` (denodrivers/postgres), pinned to v0.19.3 via
// `https://deno.land/x/postgres@v0.19.3/mod.ts` — no floating tag, matching
// this repo's existing discipline (see manage-user's
// `@supabase/supabase-js@2.45.4` pin). v0.19.3 specifically, not the newer
// v0.19.5, because it is ALREADY vetted and running in this repo —
// supabase/tests/wp_task_assignments_backfill_test.ts imports the exact
// same pin to talk to the local test database. Reusing a version already
// proven here beats introducing a second, newer pin of the same library for
// no functional gain: fewer distinct dependency versions to reason about,
// and this file's `read_only` transaction option (the feature this task
// actually needs) is unchanged between the two.
//
// Why deno-postgres at all: it is the standard pure-Deno Postgres driver —
// no native bindings, works in the Edge Functions sandbox, and its
// `Transaction` type has a first-class `read_only` option (see
// `runExternalQuery` below), which is exactly the "connect read-only"
// requirement in this task's brief. The alternative, `postgres.js` via npm
// specifier, has no equivalent already-vetted usage in this repo.
//
// ---------------------------------------------------------------------------
// CREDENTIAL RESOLUTION
// ---------------------------------------------------------------------------
// `kpi_connections.credential_kind` is 'VAULT' or 'ENV' (migration
// 20260815000002's header comment). Both paths return the PASSWORD, and
// only the password, as a plain string for `credential_ref` to name:
//   'ENV'   -> Deno.env.get(credential_ref), the same shape authFromEnv()
//              already uses for Lark (../_shared/lark.ts).
//   'VAULT' -> `select decrypted_secret from vault.decrypted_secrets where
//              name = credential_ref`, run as a DIRECT Postgres query
//              against THIS project's own database — not through
//              @supabase/supabase-js, because the `vault` schema is not
//              exposed via PostgREST (confirmed against Supabase's own
//              Vault docs: "Anyone that has access to the view has access
//              to decrypted secrets" is a warning about direct SQL access,
//              and there is no supabase-js-reachable path to it without an
//              RPC wrapper, which this task has no migration to add). The
//              connection uses `SUPABASE_DB_URL`, one of the secrets Edge
//              Functions get automatically — see resolveVaultSecret below.
//
// USERNAME: `connection.db_user`, a plain (non-secret) column on
// `kpi_connections` — NOT part of either credential path above. Fix round
// 1 resolved a defect from this task's first pass: with no `db_user`
// column, the secret value was packed as `"<user>:<password>"`, which
// disagreed with migration 20260815000002's own ENV example
// (`supabase secrets set <credential_ref>=<password>`, i.e. password-only).
// On review that convention was rejected — a username is not secret, an
// admin should be able to read it without decrypting anything, and
// rotating a password should never require re-typing the username
// alongside it. The migration now has a real `db_user text not null`
// column; this file reads it straight off `ConnectionRow` and treats
// `credential_ref`'s secret as the password, unparsed, unsplit.

import { createClient, type SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';
import { Client as PgClient } from 'https://deno.land/x/postgres@v0.19.3/mod.ts';
import { buildSourceSelect } from '../_shared/source_query.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const CONNECT_TIMEOUT_MS = 8_000;
const QUERY_TIMEOUT_MS = 15_000;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', ...corsHeaders },
  });
}

// ---------------------------------------------------------------------------
// Pure, unit-tested pieces.
// ---------------------------------------------------------------------------

export interface FetchRow {
  subject_key: string;
  numerator: number | null;
  denominator: number | null;
}

export interface BindingRow {
  id: string;
  company_id: string;
  connection_id: string;
  object_name: string;
  period_column: string;
  subject_column: string;
  numerator_column: string;
  denominator_column: string | null;
  is_active: boolean;
}

export interface ConnectionRow {
  id: string;
  host: string;
  port: number;
  database: string;
  db_schema: string;
  /** Not secret — see the CREDENTIAL RESOLUTION doc comment above. */
  db_user: string;
  credential_kind: string;
  credential_ref: string;
  is_active: boolean;
}

/// Everything `handleFetchRequest` needs to look configuration up, kept
/// behind an interface so tests can supply an in-memory fake instead of a
/// real Supabase project. The real implementation (`makeSupabaseLoader`,
/// below) is the only thing that talks to `@supabase/supabase-js` or
/// `vault.decrypted_secrets`.
export interface SourceLoader {
  getBinding(bindingId: string): Promise<BindingRow | null>;
  getConnection(connectionId: string): Promise<ConnectionRow | null>;
  /** Returns the raw PASSWORD, or null if it could not be found. The
   * username is never part of this — it's `connection.db_user`. */
  getCredentialSecret(kind: string, ref: string): Promise<string | null>;
}

/// Runs the already-built, already-validated `sql` against the external
/// database named by `connection` (whose `db_user` supplies the username),
/// using `password`, with `period` bound as `$1`. Kept as an injected
/// function (not a method `handleFetchRequest` calls directly) so tests can
/// prove `buildSourceSelect`'s validation runs before this is ever invoked,
/// without needing a real network connection.
export type RunQuery = (
  connection: ConnectionRow,
  password: string,
  sql: string,
  period: string,
) => Promise<FetchRow[]>;

/// Returns whether the CALLER (not the service-role client this function
/// otherwise uses) is HR/admin. `handleFetchRequest` treats a throw the
/// same as `false` — a role check that cannot be verified must fail
/// closed, never fail open into "assume authorized".
export type AuthorizeCaller = () => Promise<boolean>;

/// Validates the two required request fields. Pure — no lookup, no I/O —
/// so a missing `binding_id` is rejected before anything else in this
/// module runs.
export function parseRequestBody(
  body: Record<string, unknown>,
):
  | { ok: true; bindingId: string; period: string }
  | { ok: false; error: string; code: string } {
  const bindingId = body['binding_id'];
  if (typeof bindingId !== 'string' || bindingId.trim().length === 0) {
    return { ok: false, error: 'binding_id required', code: 'BAD_REQUEST' };
  }
  const period = body['period'];
  if (typeof period !== 'string' || period.trim().length === 0) {
    return { ok: false, error: 'period required', code: 'BAD_REQUEST' };
  }
  return { ok: true, bindingId, period };
}

/// `null`/`undefined` stay `null` — the one rule this function exists to
/// enforce, because `Number(null) === 0` in JavaScript and that would
/// silently turn "this source had nothing to say" into a false zero. A
/// blank/whitespace-only string is the same bug in disguise —
/// `Number('') === 0` and `Number('   ') === 0` as well — so it is rejected
/// BEFORE reaching `Number(...)`, not left to fall through and produce an
/// honest-looking zero for what was really an empty cell. A finite numeric
/// string (deno-postgres decodes `numeric`/`decimal` columns as strings to
/// avoid float rounding on money-shaped values) is parsed; anything else
/// that isn't already a `number` also comes back `null` rather than
/// throwing — a single unparseable value in a big result set should not
/// fail the whole binding.
export function toNumberOrNull(value: unknown): number | null {
  if (value === null || value === undefined) return null;
  if (typeof value === 'number') return Number.isFinite(value) ? value : null;
  if (typeof value === 'string') {
    if (value.trim().length === 0) return null;
    const n = Number(value);
    return Number.isFinite(n) ? n : null;
  }
  return null;
}

export interface RawExternalRow {
  subject_key: unknown;
  numerator: unknown;
  denominator: unknown;
}

/// A SQL `NULL` in the subject column must NOT become the literal string
/// `"null"` — naive `String(null)` does exactly that, and a subject_key of
/// `"null"` is indistinguishable from a source that genuinely emitted the
/// text "null" as a key. It resolves to `''` instead: `kpi_subject_map`'s
/// `external_key` has a NOT-BLANK CHECK constraint
/// (`kpi_subject_map_external_key_not_blank`,
/// `20260815000002_kpi_source_config.sql`), so `''` can never collide with
/// a real mapped key — it is guaranteed to miss every lookup and resolve as
/// unmapped, which is the correct, already-designed behaviour for "this row
/// has no identifiable subject": still counted toward COMPANY, excluded
/// from every DEPARTMENT/PERSONAL figure, and flagged via
/// `unresolvedPresent` (`aggregateSourceRows`, `source_rows.dart`). Dropping
/// the row instead was considered and rejected: for a
/// [SubjectKind.none]-shaped binding, `subjectKey` is ignored entirely and
/// EVERY row must still be summed, so silently discarding a null-subject
/// row would undercount a NONE-kind KPI for no reason.
export function toFetchRow(row: RawExternalRow): FetchRow {
  const subjectKey = row.subject_key;
  return {
    subject_key:
      subjectKey === null || subjectKey === undefined
        ? ''
        : String(subjectKey),
    numerator: toNumberOrNull(row.numerator),
    denominator: toNumberOrNull(row.denominator),
  };
}

/// The orchestration this task's tests target directly. Pure aside from the
/// three injected effectful pieces (`authorize`, `loader`, `runQuery`), so
/// every ordering and error-mapping rule can be proven without a live
/// database:
///   - a caller `authorize` rejects is a 403 and NEVER reaches `loader` —
///     the service-role `loader` this function otherwise uses bypasses the
///     RLS that would have enforced HR/admin-only access to this
///     configuration, so this check is the only thing enforcing it;
///   - a missing binding_id never reaches `loader` at all;
///   - an unknown binding (`loader.getBinding` -> null) is a 404 and never
///     reaches `getConnection`, credential resolution, or `runQuery`;
///   - a binding whose identifiers fail `buildSourceSelect` is rejected
///     BEFORE `loader.getCredentialSecret` or `runQuery` run — this is the
///     security-relevant ordering the brief asks to be load-bearing.
export async function handleFetchRequest(args: {
  body: unknown;
  authorize: AuthorizeCaller;
  loader: SourceLoader;
  runQuery: RunQuery;
}): Promise<{ status: number; body: Record<string, unknown> }> {
  const { body, authorize, loader, runQuery } = args;

  // --- Caller authorization happens FIRST, before body validation and
  // long before any binding/connection is loaded. Do not move this below
  // the loader calls — see supabase/tests/fetch_kpi_source_test.ts for the
  // test that fails if this ordering regresses.
  let authorized: boolean;
  try {
    authorized = await authorize();
  } catch (err) {
    console.error('[fetch-kpi-source] authorization check failed', {
      message: (err as Error)?.message,
    });
    authorized = false; // fail closed
  }
  if (!authorized) {
    return { status: 403, body: { error: 'Forbidden', code: 'NOT_AUTHORIZED' } };
  }

  if (typeof body !== 'object' || body === null || Array.isArray(body)) {
    return {
      status: 400,
      body: { error: 'Invalid request body', code: 'BAD_REQUEST' },
    };
  }

  const parsed = parseRequestBody(body as Record<string, unknown>);
  if (!parsed.ok) {
    return { status: 400, body: { error: parsed.error, code: parsed.code } };
  }

  let binding: BindingRow | null;
  try {
    binding = await loader.getBinding(parsed.bindingId);
  } catch (err) {
    console.error('[fetch-kpi-source] binding lookup failed', {
      bindingId: parsed.bindingId,
      message: (err as Error)?.message,
    });
    return {
      status: 500,
      body: { error: 'Could not load source configuration', code: 'INTERNAL' },
    };
  }
  if (!binding || !binding.is_active) {
    return {
      status: 404,
      body: { error: 'Binding not found', code: 'BINDING_NOT_FOUND' },
    };
  }

  let connection: ConnectionRow | null;
  try {
    connection = await loader.getConnection(binding.connection_id);
  } catch (err) {
    console.error('[fetch-kpi-source] connection lookup failed', {
      connectionId: binding.connection_id,
      message: (err as Error)?.message,
    });
    return {
      status: 500,
      body: { error: 'Could not load source configuration', code: 'INTERNAL' },
    };
  }
  if (!connection || !connection.is_active) {
    return {
      status: 404,
      body: { error: 'Connection not found', code: 'CONNECTION_NOT_FOUND' },
    };
  }

  // --- Identifier validation happens HERE, before any credential lookup
  // or connection attempt. Do not move this below the credential/runQuery
  // calls below it — see supabase/tests/fetch_kpi_source_test.ts for the
  // test that fails if this ordering regresses.
  let sql: string;
  try {
    sql = buildSourceSelect({
      schema: connection.db_schema,
      object: binding.object_name,
      periodColumn: binding.period_column,
      subjectColumn: binding.subject_column,
      numeratorColumn: binding.numerator_column,
      denominatorColumn: binding.denominator_column ?? undefined,
    });
  } catch (err) {
    console.error('[fetch-kpi-source] identifier validation failed', {
      bindingId: binding.id,
      message: (err as Error)?.message,
    });
    return {
      status: 400,
      body: {
        error: 'Source configuration has an invalid identifier',
        code: 'INVALID_IDENTIFIER',
      },
    };
  }

  let rawSecret: string | null;
  try {
    rawSecret = await loader.getCredentialSecret(
      connection.credential_kind,
      connection.credential_ref,
    );
  } catch (err) {
    console.error('[fetch-kpi-source] credential lookup failed', {
      connectionId: connection.id,
      kind: connection.credential_kind,
      message: (err as Error)?.message,
    });
    return {
      status: 502,
      body: {
        error: 'Could not resolve source credential',
        code: 'CREDENTIAL_UNAVAILABLE',
      },
    };
  }
  if (!rawSecret) {
    console.error('[fetch-kpi-source] credential missing', {
      connectionId: connection.id,
      kind: connection.credential_kind,
    });
    return {
      status: 502,
      body: {
        error: 'Source credential not configured',
        code: 'CREDENTIAL_UNAVAILABLE',
      },
    };
  }

  let rows: FetchRow[];
  try {
    rows = await runQuery(connection, rawSecret, sql, parsed.period);
  } catch (err) {
    console.error('[fetch-kpi-source] external query failed', {
      connectionId: connection.id,
      bindingId: binding.id,
      // Deliberately only the message, never the whole error object, which
      // for a connection failure can carry the target host/port. Still
      // function-log-only, never returned to the caller below.
      message: (err as Error)?.message,
    });
    return {
      status: 502,
      body: {
        error: 'Could not read from the configured source',
        code: 'SOURCE_UNAVAILABLE',
      },
    };
  }

  return { status: 200, body: { rows } };
}

// ---------------------------------------------------------------------------
// Real, effectful implementations — wired up in Deno.serve below, never
// exercised by the unit tests.
// ---------------------------------------------------------------------------

/// Races `promise` against a `ms`-millisecond timer, rejecting with a
/// `label`-tagged error if the timer wins. The timer handle is ALWAYS
/// cleared once the race settles either way (`finally`, not left for the
/// timer to fire into the void) — an uncleared `setTimeout` is a handle
/// leak of the same shape as the connection leak fixed by
/// `withConnectedClient` below, just smaller.
export function withTimeout<T>(promise: Promise<T>, ms: number, label: string): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<never>((_, reject) => {
    timer = setTimeout(() => reject(new Error(`${label} timed out after ${ms}ms`)), ms);
  });
  return Promise.race([promise, timeout]).finally(() => {
    if (timer !== undefined) clearTimeout(timer);
  });
}

/// The minimal shape `withConnectedClient` needs — satisfied structurally
/// by deno-postgres's `Client`, and by a hand-built fake in
/// `fetch_kpi_source_test.ts` that never touches a real socket.
export interface ConnectableClient {
  connect(): Promise<void>;
  end(): Promise<void>;
}

/// Runs `body` against `client`, connecting first (timeboxed to
/// `connectTimeoutMs` via `withTimeout`) and GUARANTEEING `client.end()` is
/// called exactly once afterward — whether `connect()` succeeds, throws, or
/// times out. This is deliberately the ONLY place either connection this
/// file opens calls `.connect()`, so a future call site cannot reintroduce
/// the leak this fixes: previously `client.connect()` sat outside the
/// `try/finally` that calls `.end()`, so a connect timeout (the timer
/// winning `withTimeout`'s race, which does NOT stop the driver's own
/// in-flight connection attempt) left the client dropped without ever
/// being closed — on the external database for `runExternalQuery`, and on
/// THIS project's own database for `resolveVaultSecret`. Putting `connect()`
/// inside the `try` means the `finally` below runs, and calls `.end()`,
/// regardless of which of those three ways `connect()` settles.
export async function withConnectedClient<C extends ConnectableClient, T>(
  client: C,
  connectTimeoutMs: number,
  body: (client: C) => Promise<T>,
): Promise<T> {
  try {
    await withTimeout(client.connect(), connectTimeoutMs, 'connect');
    return await body(client);
  } finally {
    await client.end().catch(() => {});
  }
}

/// Forces `sslmode=require` onto a Postgres connection string UNLESS it
/// already names an `sslmode` explicitly (an operator's own choice is left
/// alone). deno-postgres v0.19.3 defaults an unqualified connection to
/// `{ enabled: true, enforce: false }` — TLS is *attempted* but a source
/// that doesn't offer it is accepted anyway, silently, with the SCRAM
/// handshake and every row crossing the network in the clear. `sslmode=require`
/// parses to `{ enabled: true, enforce: true }` (confirmed against
/// deno-postgres's own `connection_params.ts` at this pin), so a source that
/// cannot do TLS fails the connection instead of downgrading it.
///
/// Deliberately string surgery, not a round trip through the `URL` class:
/// `new URL(...).toString()` percent-re-encodes the whole string, including
/// characters (like `:`) that can legitimately appear in a password —
/// silently corrupting a credential is a worse failure mode than the one
/// this function exists to close.
export function withRequireSsl(connectionString: string): string {
  if (/[?&]sslmode=/i.test(connectionString)) return connectionString;
  const separator = connectionString.includes('?') ? '&' : '?';
  return `${connectionString}${separator}sslmode=require`;
}

/// Reads one secret out of Supabase Vault via a DIRECT Postgres connection
/// to this project's own database (`SUPABASE_DB_URL`, auto-provided to
/// every Edge Function) — see the CREDENTIAL RESOLUTION doc comment at the
/// top of this file for why `@supabase/supabase-js` cannot reach
/// `vault.decrypted_secrets`.
async function resolveVaultSecret(dbUrl: string, ref: string): Promise<string | null> {
  const client = new PgClient(withRequireSsl(dbUrl));
  return await withConnectedClient(client, CONNECT_TIMEOUT_MS, async (c) => {
    const result = await withTimeout(
      c.queryObject<{ decrypted_secret: string }>(
        'select decrypted_secret from vault.decrypted_secrets where name = $1 limit 1',
        [ref],
      ),
      QUERY_TIMEOUT_MS,
      'vault query',
    );
    return result.rows[0]?.decrypted_secret ?? null;
  });
}

/// Checks the CALLER's own role via `auth_is_hr_or_admin()`
/// (`20260423000004_rls_recognize_new_roles.sql`) — the exact function the
/// RLS on `kpi_connections`/`kpi_source_bindings`/`kpi_subject_map`
/// already uses, so there is one source of truth for "who counts as
/// HR/admin" rather than a role list duplicated (and driftable) here. Runs
/// through a CLIENT built with the ANON key plus the caller's own
/// `Authorization` header — never the service-role client — so
/// `auth_app_role()` inside the RPC reads the CALLER's JWT claims, not this
/// function's own elevated identity. Mirrors
/// `supabase/functions/send-performance-self-reviews/index.ts`'s `caller`
/// client and `ReviewCycleRepository.callerSeesAllReviews()`
/// (`lib/data/repositories/review_cycle_repository.dart`), which fails
/// toward `false` for the same reason `handleFetchRequest` treats a throw
/// here as unauthorized rather than propagating it: an RPC outage must
/// degrade to "cannot certify HR/admin", never to "assume authorized".
function makeAuthorizeCaller(
  url: string,
  anonKey: string,
  authorizationHeader: string,
): AuthorizeCaller {
  return async () => {
    const caller = createClient(url, anonKey, {
      auth: { persistSession: false, autoRefreshToken: false },
      global: { headers: { Authorization: authorizationHeader } },
    });
    const { data, error } = await caller.rpc('auth_is_hr_or_admin');
    if (error) {
      console.error('[fetch-kpi-source] auth_is_hr_or_admin check failed', {
        message: error.message,
      });
      return false;
    }
    return data === true;
  };
}

function makeSupabaseLoader(
  admin: SupabaseClient,
  dbUrl: string,
  callerCompanyId: string,
): SourceLoader {
  return {
    async getBinding(bindingId) {
      const { data, error } = await admin
        .from('kpi_source_bindings')
        .select(
          'id, company_id, connection_id, object_name, period_column, subject_column, numerator_column, denominator_column, is_active',
        )
        .eq('id', bindingId)
        .eq('company_id', callerCompanyId)
        .maybeSingle();
      if (error) throw new Error(error.message);
      return (data as BindingRow | null) ?? null;
    },
    async getConnection(connectionId) {
      const { data, error } = await admin
        .from('kpi_connections')
        .select(
          'id, host, port, database, db_schema, db_user, credential_kind, credential_ref, is_active',
        )
        .eq('id', connectionId)
        .eq('company_id', callerCompanyId)
        .maybeSingle();
      if (error) throw new Error(error.message);
      return (data as ConnectionRow | null) ?? null;
    },
    async getCredentialSecret(kind, ref) {
      if (kind === 'ENV') return Deno.env.get(ref) ?? null;
      if (kind === 'VAULT') return await resolveVaultSecret(dbUrl, ref);
      throw new Error(`Unknown credential_kind: ${kind}`);
    },
  };
}

/// Connects to the external database READ-ONLY (a `read_only` transaction —
/// see deno-postgres's `TransactionOptions`) and TLS-enforced (see
/// `withRequireSsl`'s doc comment — here as an explicit `tls` option rather
/// than string surgery, since this call site already builds a `ClientOptions`
/// object), runs `sql` with `period` bound as `$1`, and always closes the
/// connection via `withConnectedClient`, success, failure, or timeout alike.
/// `connection.db_user` supplies the username; `password` is the plain
/// secret `credential_ref` names — never a compound `"user:password"`
/// value (see the CREDENTIAL RESOLUTION doc comment at the top of this
/// file).
async function runExternalQuery(
  connection: ConnectionRow,
  password: string,
  sql: string,
  period: string,
): Promise<FetchRow[]> {
  const client = new PgClient({
    hostname: connection.host,
    port: connection.port,
    database: connection.database,
    user: connection.db_user,
    password,
    tls: { enabled: true, enforce: true },
    connection: { attempts: 1 },
  });

  return await withConnectedClient(client, CONNECT_TIMEOUT_MS, async (c) => {
    const tx = c.createTransaction('fetch_kpi_source', {
      read_only: true,
      isolation_level: 'read_committed',
    });
    await tx.begin();
    try {
      const result = await withTimeout(
        tx.queryObject<RawExternalRow>(sql, [period]),
        QUERY_TIMEOUT_MS,
        'query',
      );
      await tx.commit();
      return result.rows.map(toFetchRow);
    } catch (err) {
      await tx.rollback().catch(() => {});
      throw err;
    }
  });
}

// ---------------------------------------------------------------------------
// HTTP entry point.
// ---------------------------------------------------------------------------

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') {
    return json({ error: 'POST required', code: 'BAD_REQUEST' }, 405);
  }

  const url = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const dbUrl = Deno.env.get('SUPABASE_DB_URL');
  if (!url || !anonKey || !serviceKey || !dbUrl) {
    return json({ error: 'Server not configured', code: 'INTERNAL' }, 500);
  }

  const authHeader = req.headers.get('Authorization');
  if (!authHeader?.startsWith('Bearer ')) {
    return json({ error: 'Missing Authorization', code: 'NOT_AUTHORIZED' }, 401);
  }
  const callerJwt = authHeader.substring('Bearer '.length);

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return json({ error: 'Invalid JSON', code: 'BAD_REQUEST' }, 400);
  }

  const admin = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: callerData, error: callerErr } = await admin.auth.getUser(callerJwt);
  if (callerErr || !callerData?.user) {
    return json({ error: 'Invalid token', code: 'NOT_AUTHORIZED' }, 401);
  }
  const callerCompanyId =
    (callerData.user.app_metadata?.company_id as string | undefined) ?? '';
  if (!callerCompanyId) {
    return json({ error: 'Forbidden', code: 'NOT_AUTHORIZED' }, 403);
  }

  const authorize = makeAuthorizeCaller(url, anonKey, authHeader);
  const loader = makeSupabaseLoader(admin, dbUrl, callerCompanyId);
  const result = await handleFetchRequest({
    body,
    authorize,
    loader,
    runQuery: runExternalQuery,
  });
  return json(result.body, result.status);
});
