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
/// finite numeric string (deno-postgres decodes `numeric`/`decimal`
/// columns as strings to avoid float rounding on money-shaped values) is
/// parsed; anything else that isn't already a `number` also comes back
/// `null` rather than throwing — a single unparseable value in a big result
/// set should not fail the whole binding.
export function toNumberOrNull(value: unknown): number | null {
  if (value === null || value === undefined) return null;
  if (typeof value === 'number') return Number.isFinite(value) ? value : null;
  if (typeof value === 'string') {
    const n = Number(value);
    return Number.isFinite(n) ? n : null;
  }
  return null;
}

interface RawExternalRow {
  subject_key: unknown;
  numerator: unknown;
  denominator: unknown;
}

function toFetchRow(row: RawExternalRow): FetchRow {
  return {
    subject_key: String(row.subject_key),
    numerator: toNumberOrNull(row.numerator),
    denominator: toNumberOrNull(row.denominator),
  };
}

/// The orchestration this task's tests target directly. Pure aside from the
/// two injected effectful pieces (`loader`, `runQuery`), so every ordering
/// and error-mapping rule can be proven without a live database:
///   - a missing binding_id never reaches `loader` at all;
///   - an unknown binding (`loader.getBinding` -> null) is a 404 and never
///     reaches `getConnection`, credential resolution, or `runQuery`;
///   - a binding whose identifiers fail `buildSourceSelect` is rejected
///     BEFORE `loader.getCredentialSecret` or `runQuery` run — this is the
///     security-relevant ordering the brief asks to be load-bearing.
export async function handleFetchRequest(args: {
  body: unknown;
  loader: SourceLoader;
  runQuery: RunQuery;
}): Promise<{ status: number; body: Record<string, unknown> }> {
  const { body, loader, runQuery } = args;

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

function withTimeout<T>(promise: Promise<T>, ms: number, label: string): Promise<T> {
  return Promise.race([
    promise,
    new Promise<T>((_, reject) => {
      setTimeout(() => reject(new Error(`${label} timed out after ${ms}ms`)), ms);
    }),
  ]);
}

/// Reads one secret out of Supabase Vault via a DIRECT Postgres connection
/// to this project's own database (`SUPABASE_DB_URL`, auto-provided to
/// every Edge Function) — see the CREDENTIAL RESOLUTION doc comment at the
/// top of this file for why `@supabase/supabase-js` cannot reach
/// `vault.decrypted_secrets`.
async function resolveVaultSecret(dbUrl: string, ref: string): Promise<string | null> {
  const client = new PgClient(dbUrl);
  await withTimeout(client.connect(), CONNECT_TIMEOUT_MS, 'vault connect');
  try {
    const result = await withTimeout(
      client.queryObject<{ decrypted_secret: string }>(
        'select decrypted_secret from vault.decrypted_secrets where name = $1 limit 1',
        [ref],
      ),
      QUERY_TIMEOUT_MS,
      'vault query',
    );
    return result.rows[0]?.decrypted_secret ?? null;
  } finally {
    await client.end().catch(() => {});
  }
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
/// see deno-postgres's `TransactionOptions`), runs `sql` with `period` bound
/// as `$1`, and always closes the connection, success or failure.
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
    connection: { attempts: 1 },
  });

  await withTimeout(client.connect(), CONNECT_TIMEOUT_MS, 'connect');
  try {
    const tx = client.createTransaction('fetch_kpi_source', {
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
  } finally {
    await client.end().catch(() => {});
  }
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
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const dbUrl = Deno.env.get('SUPABASE_DB_URL');
  if (!url || !serviceKey || !dbUrl) {
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

  const loader = makeSupabaseLoader(admin, dbUrl, callerCompanyId);
  const result = await handleFetchRequest({ body, loader, runQuery: runExternalQuery });
  return json(result.body, result.status);
});
