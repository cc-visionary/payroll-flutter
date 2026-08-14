// Tests the pure parts of supabase/functions/fetch-kpi-source/index.ts that
// are reachable without a live external database:
//   - request validation (missing binding_id / period)
//   - credential-secret parsing
//   - null-preserving numeric coercion
//   - handleFetchRequest's orchestration: unknown binding -> 404, and —
//     the security-relevant, load-bearing assertion — a binding whose
//     identifiers fail buildSourceSelect's validation is rejected BEFORE
//     any credential lookup or external connection attempt.
//
// Live connectivity to an external Postgres is NOT covered here and cannot
// be: there is no external database in this environment, and Task 5's
// brief is explicit that inventing one would be worse than an honestly
// named gap. See task-5-report.md for what still needs a manual check
// against a real source.

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  type BindingRow,
  type ConnectionRow,
  type FetchRow,
  handleFetchRequest,
  parseCredentialSecret,
  parseRequestBody,
  type SourceLoader,
  toNumberOrNull,
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
// parseCredentialSecret
// ---------------------------------------------------------------------------

Deno.test('parseCredentialSecret splits on the first colon', () => {
  const { user, password } = parseCredentialSecret('ro_user:s3cr3t');
  assertEquals(user, 'ro_user');
  assertEquals(password, 's3cr3t');
});

Deno.test('parseCredentialSecret keeps everything after the first colon as password', () => {
  // A password containing a colon must not be truncated.
  const { user, password } = parseCredentialSecret('ro_user:pa:ss');
  assertEquals(user, 'ro_user');
  assertEquals(password, 'pa:ss');
});

Deno.test('parseCredentialSecret throws when there is no colon', () => {
  let threw = false;
  try {
    parseCredentialSecret('just-a-password');
  } catch {
    threw = true;
  }
  assert(threw, 'expected parseCredentialSecret to throw');
});

Deno.test('parseCredentialSecret throws on an empty user', () => {
  let threw = false;
  try {
    parseCredentialSecret(':password');
  } catch {
    threw = true;
  }
  assert(threw, 'expected parseCredentialSecret to throw on empty user');
});

Deno.test('parseCredentialSecret throws on an empty password', () => {
  let threw = false;
  try {
    parseCredentialSecret('user:');
  } catch {
    threw = true;
  }
  assert(threw, 'expected parseCredentialSecret to throw on empty password');
});

// ---------------------------------------------------------------------------
// toNumberOrNull — never coerce null to 0.
// ---------------------------------------------------------------------------

Deno.test('toNumberOrNull keeps null as null, not 0', () => {
  assertEquals(toNumberOrNull(null), null);
  assertEquals(toNumberOrNull(undefined), null);
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
// handleFetchRequest — orchestration, with a fake loader/runQuery so no
// network or database is ever touched.
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
  credential_kind: 'ENV',
  credential_ref: 'CASHFLOW_RO_CRED',
  is_active: true,
};

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

Deno.test('handleFetchRequest: missing binding_id is rejected before any lookup', async () => {
  const result = await handleFetchRequest({
    body: { period: '2026-08' },
    loader: forbiddenLoader(),
    runQuery: forbiddenRunQuery,
  });
  assertEquals(result.status, 400);
  assertEquals(result.body.code, 'BAD_REQUEST');
});

Deno.test('handleFetchRequest: unknown binding is a 404', async () => {
  const result = await handleFetchRequest({
    body: { binding_id: 'does-not-exist', period: '2026-08' },
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
      loader: forbiddenLoader({
        getBinding: async () => invalidBinding,
        getConnection: async () => validConnection,
        getCredentialSecret: async () => {
          credentialLookupCalled = true;
          return 'user:pass';
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

Deno.test('handleFetchRequest: a malformed credential secret is a 502', async () => {
  const result = await handleFetchRequest({
    body: { binding_id: validBinding.id, period: '2026-08' },
    loader: forbiddenLoader({
      getBinding: async () => validBinding,
      getConnection: async () => validConnection,
      getCredentialSecret: async () => 'no-colon-here',
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
    loader: forbiddenLoader({
      getBinding: async () => validBinding,
      getConnection: async () => validConnection,
      getCredentialSecret: async () => 'user:pass',
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
    loader: forbiddenLoader({
      getBinding: async () => validBinding,
      getConnection: async () => validConnection,
      getCredentialSecret: async () => 'user:pass',
    }),
    runQuery: async () => rows,
  });
  assertEquals(result.status, 200);
  assertEquals(result.body.rows, rows);
});
