// Tests the pure parts of supabase/functions/fetch-kpi-source/index.ts that
// are reachable without a live external database:
//   - request validation (missing binding_id / period)
//   - null-preserving numeric coercion, including the blank-string case
//     Number('') === 0 would otherwise sneak through as
//   - SQL NULL subject_key handling (never the literal string "null")
//   - the TLS-enforcement string helper
//   - handleFetchRequest's orchestration, with three load-bearing ordering
//     assertions:
//       1. a caller `authorize()` rejects is a 403 and the (service-role)
//          loader is NEVER touched -- this is the fix for security review
//          finding 1 (any authenticated caller could otherwise read every
//          employee's numbers via the service-role bypass of RLS);
//       2. a binding whose identifiers fail buildSourceSelect's validation
//          is rejected BEFORE any credential lookup or connection attempt;
//       3. withConnectedClient always calls client.end(), even when
//          connect() throws or times out -- the fix for finding 3 (a
//          connect failure previously leaked the connection because
//          connect() sat outside the try/finally that closes it).
//
// Live connectivity to an external Postgres is NOT covered here and cannot
// be: there is no external database in this environment, and Task 5's
// brief is explicit that inventing one would be worse than an honestly
// named gap. See task-5-report.md for what still needs a manual check
// against a real source.

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  type BindingRow,
  type ConnectableClient,
  type ConnectionRow,
  type FetchRow,
  handleFetchRequest,
  parseRequestBody,
  type RawExternalRow,
  type SourceLoader,
  toFetchRow,
  toNumberOrNull,
  withConnectedClient,
  withRequireSsl,
} from '../functions/fetch-kpi-source/index.ts';

// ---------------------------------------------------------------------------
// parseRequestBody
// ---------------------------------------------------------------------------

Deno.test('parseRequestBody rejects a missing binding_id', () => {
  const result = parseRequestBody({ period: '2026-08' });
  assertEquals(result.ok, false);
  if (!result.ok) assertEquals(result.code, 'BAD_REQUEST');
});

Deno.test('parseRequestBody rejects a blank binding_id', () => {
  const result = parseRequestBody({ binding_id: '   ', period: '2026-08' });
  assertEquals(result.ok, false);
});

Deno.test('parseRequestBody rejects a missing period', () => {
  const result = parseRequestBody({ binding_id: 'b1' });
  assertEquals(result.ok, false);
  if (!result.ok) assertEquals(result.code, 'BAD_REQUEST');
});

Deno.test('parseRequestBody accepts a valid body', () => {
  const result = parseRequestBody({ binding_id: 'b1', period: '2026-08' });
  assertEquals(result.ok, true);
  if (result.ok) {
    assertEquals(result.bindingId, 'b1');
    assertEquals(result.period, '2026-08');
  }
});

// ---------------------------------------------------------------------------
// toNumberOrNull — never coerce null (or blank) to 0.
// ---------------------------------------------------------------------------

Deno.test('toNumberOrNull keeps null as null, not 0', () => {
  assertEquals(toNumberOrNull(null), null);
  assertEquals(toNumberOrNull(undefined), null);
});

Deno.test('toNumberOrNull rejects an empty string rather than letting Number("") === 0 through', () => {
  assertEquals(toNumberOrNull(''), null);
});

Deno.test('toNumberOrNull rejects a whitespace-only string for the same reason', () => {
  assertEquals(toNumberOrNull('   '), null);
});

Deno.test('toNumberOrNull preserves an honest zero', () => {
  assertEquals(toNumberOrNull(0), 0);
  assertEquals(toNumberOrNull('0'), 0);
});

Deno.test('toNumberOrNull parses a numeric string (deno-postgres decodes numeric/decimal as strings)', () => {
  assertEquals(toNumberOrNull('42.5'), 42.5);
});

Deno.test('toNumberOrNull passes a number through unchanged', () => {
  assertEquals(toNumberOrNull(7), 7);
});

Deno.test('toNumberOrNull returns null for unparseable input rather than throwing', () => {
  assertEquals(toNumberOrNull('not-a-number'), null);
  assertEquals(toNumberOrNull({}), null);
});

// ---------------------------------------------------------------------------
// toFetchRow — a SQL NULL subject_key must never become the literal "null".
// ---------------------------------------------------------------------------

Deno.test('toFetchRow maps a null subject_key to an empty string, never the literal "null"', () => {
  const row: RawExternalRow = { subject_key: null, numerator: 5, denominator: null };
  const fetched = toFetchRow(row);
  assertEquals(fetched.subject_key, '');
  assert(
    fetched.subject_key !== 'null',
    'a SQL NULL subject must not collide with a source that literally emits the text "null"',
  );
});

Deno.test('toFetchRow maps an undefined subject_key to an empty string too', () => {
  const row: RawExternalRow = { subject_key: undefined, numerator: null, denominator: null };
  assertEquals(toFetchRow(row).subject_key, '');
});

Deno.test('toFetchRow stringifies a real subject_key unchanged', () => {
  const row: RawExternalRow = { subject_key: 'alice@x.com', numerator: 1, denominator: 1 };
  assertEquals(toFetchRow(row).subject_key, 'alice@x.com');
});

// ---------------------------------------------------------------------------
// withRequireSsl — TLS enforcement (security review finding 2).
// ---------------------------------------------------------------------------

Deno.test('withRequireSsl appends sslmode=require to a bare connection string', () => {
  const result = withRequireSsl('postgres://user:pw@host.example:5432/db');
  assertEquals(result, 'postgres://user:pw@host.example:5432/db?sslmode=require');
});

Deno.test('withRequireSsl appends with & when the string already has query params', () => {
  const result = withRequireSsl('postgres://user:pw@host.example:5432/db?application_name=fetch');
  assertEquals(
    result,
    'postgres://user:pw@host.example:5432/db?application_name=fetch&sslmode=require',
  );
});

Deno.test('withRequireSsl leaves an explicit sslmode alone', () => {
  const result = withRequireSsl('postgres://user:pw@host.example:5432/db?sslmode=prefer');
  assertEquals(result, 'postgres://user:pw@host.example:5432/db?sslmode=prefer');
});

Deno.test('withRequireSsl does not re-encode or otherwise touch the rest of the string', () => {
  // A password containing a colon must survive byte-for-byte -- this is
  // exactly what a round trip through the URL class would corrupt (it
  // percent-re-encodes the whole string), which is why withRequireSsl is
  // string surgery instead.
  const withColonPassword = 'postgres://user:pa:ss@host.example:5432/db';
  assertEquals(
    withRequireSsl(withColonPassword),
    'postgres://user:pa:ss@host.example:5432/db?sslmode=require',
  );
});

// ---------------------------------------------------------------------------
// withConnectedClient — the connection MUST be closed even when connect()
// throws or times out (security review finding 3). This is the load-bearing
// leak-prevention assertion: see task-5-report.md's Fix round 2 section for
// the RED proof (temporarily moving connect() back outside the try/finally,
// as the original code had it, and watching these go red).
// ---------------------------------------------------------------------------

class FakeClient implements ConnectableClient {
  ended = false;
  endCallCount = 0;
  constructor(private readonly connectBehavior: () => Promise<void>) {}

  connect(): Promise<void> {
    return this.connectBehavior();
  }

  async end(): Promise<void> {
    this.ended = true;
    this.endCallCount++;
  }
}

Deno.test('withConnectedClient closes the client after a successful body', async () => {
  const client = new FakeClient(() => Promise.resolve());
  const result = await withConnectedClient(client, 1_000, async () => 'ok');
  assertEquals(result, 'ok');
  assertEquals(client.ended, true);
  assertEquals(client.endCallCount, 1);
});

Deno.test('withConnectedClient closes the client when connect() rejects', async () => {
  const client = new FakeClient(() => Promise.reject(new Error('ECONNREFUSED')));
  let threw = false;
  try {
    await withConnectedClient(client, 1_000, async () => 'unreached');
  } catch {
    threw = true;
  }
  assert(threw, 'expected the connect failure to propagate');
  assertEquals(client.ended, true, 'client.end() must run even though connect() rejected');
});

Deno.test('withConnectedClient closes the client when connect() times out (never resolves)', async () => {
  // Simulates the exact scenario in the finding: connect() hangs, the race
  // in withTimeout is won by the timer, and the driver's own in-flight
  // connect attempt is left running underneath. The client must still be
  // closed.
  const client = new FakeClient(() => new Promise<void>(() => {})); // never settles
  let threw = false;
  try {
    await withConnectedClient(client, 20, async () => 'unreached');
  } catch (err) {
    threw = true;
    assert((err as Error).message.includes('timed out'));
  }
  assert(threw, 'expected the connect timeout to propagate');
  assertEquals(client.ended, true, 'client.end() must run even though connect() timed out');
});

Deno.test('withConnectedClient closes the client when the body throws', async () => {
  const client = new FakeClient(() => Promise.resolve());
  let threw = false;
  try {
    await withConnectedClient(client, 1_000, async () => {
      throw new Error('query failed');
    });
  } catch {
    threw = true;
  }
  assert(threw);
  assertEquals(client.ended, true);
});

// ---------------------------------------------------------------------------
// handleFetchRequest — orchestration, with a fake authorize/loader/runQuery
// so no network or database is ever touched.
// ---------------------------------------------------------------------------

const validBinding: BindingRow = {
  id: 'binding-1',
  company_id: 'company-1',
  connection_id: 'conn-1',
  object_name: 'daily_sales_fact',
  period_column: 'period',
  subject_column: 'employee_key',
  numerator_column: 'orders_count',
  denominator_column: null,
  is_active: true,
};

const invalidBinding: BindingRow = {
  ...validBinding,
  id: 'binding-bad',
  // A semicolon is exactly the shape quoteIdentifier refuses.
  object_name: 'daily_sales_fact; drop table users',
};

const validConnection: ConnectionRow = {
  id: 'conn-1',
  host: 'db.example.internal',
  port: 5432,
  database: 'cashflow',
  db_schema: 'public',
  // Not secret — a plain column, never packed into the credential secret.
  db_user: 'cashflow_ro',
  credential_kind: 'ENV',
  credential_ref: 'CASHFLOW_RO_CRED',
  is_active: true,
};

/// An authorize function every non-authorization test uses: the caller
/// passed the HR/admin gate, so `handleFetchRequest` should proceed exactly
/// as it did before that gate existed.
const authorizedCaller = () => Promise.resolve(true);

/// A loader where every method throws unless explicitly stubbed — so any
/// test asserting "this must not be called" gets a loud failure, not a
/// silent success, if it IS called.
function forbiddenLoader(overrides: Partial<SourceLoader> = {}): SourceLoader {
  return {
    getBinding: overrides.getBinding ?? (() => {
      throw new Error('getBinding should not have been called');
    }),
    getConnection: overrides.getConnection ?? (() => {
      throw new Error('getConnection should not have been called');
    }),
    getCredentialSecret: overrides.getCredentialSecret ?? (() => {
      throw new Error('getCredentialSecret should not have been called');
    }),
  };
}

function forbiddenRunQuery(): Promise<FetchRow[]> {
  throw new Error('runQuery should not have been called');
}

Deno.test(
  'handleFetchRequest: a non-admin caller gets 403 and no binding lookup happens',
  async () => {
    const result = await handleFetchRequest({
      body: { binding_id: validBinding.id, period: '2026-08' },
      authorize: () => Promise.resolve(false),
      // forbiddenLoader with no overrides: if the authorization gate is
      // skipped, getBinding is reached and throws loudly instead of the
      // test silently passing.
      loader: forbiddenLoader(),
      runQuery: forbiddenRunQuery,
    });
    assertEquals(result.status, 403);
    assertEquals(result.body.code, 'NOT_AUTHORIZED');
  },
);

Deno.test(
  'handleFetchRequest: an authorize() that throws fails closed (403), not open',
  async () => {
    const result = await handleFetchRequest({
      body: { binding_id: validBinding.id, period: '2026-08' },
      authorize: () => {
        throw new Error('auth_is_hr_or_admin RPC unreachable');
      },
      loader: forbiddenLoader(),
      runQuery: forbiddenRunQuery,
    });
    assertEquals(result.status, 403);
  },
);

Deno.test('handleFetchRequest: missing binding_id is rejected before any lookup', async () => {
  const result = await handleFetchRequest({
    body: { period: '2026-08' },
    authorize: authorizedCaller,
    loader: forbiddenLoader(),
    runQuery: forbiddenRunQuery,
  });
  assertEquals(result.status, 400);
  assertEquals(result.body.code, 'BAD_REQUEST');
});

Deno.test('handleFetchRequest: unknown binding is a 404', async () => {
  const result = await handleFetchRequest({
    body: { binding_id: 'does-not-exist', period: '2026-08' },
    authorize: authorizedCaller,
    loader: forbiddenLoader({
      getBinding: async () => null,
    }),
    runQuery: forbiddenRunQuery,
  });
  assertEquals(result.status, 404);
  assertEquals(result.body.code, 'BINDING_NOT_FOUND');
});

Deno.test('handleFetchRequest: an inactive binding is also a 404', async () => {
  const result = await handleFetchRequest({
    body: { binding_id: validBinding.id, period: '2026-08' },
    authorize: authorizedCaller,
    loader: forbiddenLoader({
      getBinding: async () => ({ ...validBinding, is_active: false }),
    }),
    runQuery: forbiddenRunQuery,
  });
  assertEquals(result.status, 404);
});

Deno.test(
  'handleFetchRequest: a binding with an invalid identifier is rejected BEFORE any credential lookup or connection attempt',
  async () => {
    let credentialLookupCalled = false;
    const result = await handleFetchRequest({
      body: { binding_id: invalidBinding.id, period: '2026-08' },
      authorize: authorizedCaller,
      loader: forbiddenLoader({
        getBinding: async () => invalidBinding,
        getConnection: async () => validConnection,
        getCredentialSecret: async () => {
          credentialLookupCalled = true;
          return 's3cr3t';
        },
      }),
      // If validation is skipped, execution reaches here and throws loudly
      // — this is the "delete the validation call and watch it go red"
      // assertion the brief asks for.
      runQuery: forbiddenRunQuery,
    });

    assertEquals(result.status, 400);
    assertEquals(result.body.code, 'INVALID_IDENTIFIER');
    assertEquals(
      credentialLookupCalled,
      false,
      'credential lookup must not run for an invalid binding',
    );
  },
);

Deno.test('handleFetchRequest: missing credential secret is a 502, never a partial fetch', async () => {
  const result = await handleFetchRequest({
    body: { binding_id: validBinding.id, period: '2026-08' },
    authorize: authorizedCaller,
    loader: forbiddenLoader({
      getBinding: async () => validBinding,
      getConnection: async () => validConnection,
      getCredentialSecret: async () => null,
    }),
    runQuery: forbiddenRunQuery,
  });
  assertEquals(result.status, 502);
  assertEquals(result.body.code, 'CREDENTIAL_UNAVAILABLE');
});

Deno.test('handleFetchRequest: a query failure never leaks the underlying error into the response', async () => {
  const secretLookingMessage = 'password authentication failed for user "ro_user" host=db.internal';
  const result = await handleFetchRequest({
    body: { binding_id: validBinding.id, period: '2026-08' },
    authorize: authorizedCaller,
    loader: forbiddenLoader({
      getBinding: async () => validBinding,
      getConnection: async () => validConnection,
      getCredentialSecret: async () => 's3cr3t',
    }),
    runQuery: async () => {
      throw new Error(secretLookingMessage);
    },
  });
  assertEquals(result.status, 502);
  assertEquals(result.body.code, 'SOURCE_UNAVAILABLE');
  const serialized = JSON.stringify(result.body);
  assert(
    !serialized.includes('password'),
    'response body must not repeat the driver error',
  );
  assert(!serialized.includes('ro_user'));
});

Deno.test('handleFetchRequest: success returns rows exactly as runQuery produced them', async () => {
  const rows: FetchRow[] = [
    { subject_key: 'alice@x.com', numerator: 30, denominator: 30 },
    // A COUNT-shaped KPI's denominator: null, not 0.
    { subject_key: 'bob@x.com', numerator: 5, denominator: null },
  ];
  const result = await handleFetchRequest({
    body: { binding_id: validBinding.id, period: '2026-08' },
    authorize: authorizedCaller,
    loader: forbiddenLoader({
      getBinding: async () => validBinding,
      getConnection: async () => validConnection,
      getCredentialSecret: async () => 's3cr3t',
    }),
    runQuery: async () => rows,
  });
  assertEquals(result.status, 200);
  assertEquals(result.body.rows, rows);
});

Deno.test('handleFetchRequest: runQuery receives the username from connection.db_user and the password unsplit, never a "user:password" pair', async () => {
  // Regression coverage for fix round 1: the first pass packed the
  // username into the credential secret as "user:password" and parsed it
  // back apart. That's gone -- the username now comes from the
  // connection's own db_user column, and the secret IS the password, with
  // no splitting in between. A password that happens to contain a colon
  // must reach runQuery byte-for-byte.
  let receivedConnection: ConnectionRow | undefined;
  let receivedPassword: string | undefined;
  const rawPasswordWithColon = 'pa:ss:word';

  await handleFetchRequest({
    body: { binding_id: validBinding.id, period: '2026-08' },
    authorize: authorizedCaller,
    loader: forbiddenLoader({
      getBinding: async () => validBinding,
      getConnection: async () => validConnection,
      getCredentialSecret: async () => rawPasswordWithColon,
    }),
    runQuery: async (connection, password) => {
      receivedConnection = connection;
      receivedPassword = password;
      return [];
    },
  });

  assertEquals(receivedConnection?.db_user, 'cashflow_ro');
  assertEquals(receivedPassword, rawPasswordWithColon);
});
