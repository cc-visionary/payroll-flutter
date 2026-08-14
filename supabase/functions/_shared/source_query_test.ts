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

Deno.test('throws on inputs beyond the brief\'s list', () => {
  // A NUL byte -- written as an escape, never a raw control character in
  // source (this repo has shipped raw NUL bytes before, with real
  // consequences for a review package's diff) -- and a non-ASCII letter,
  // which a Unicode-aware character class could admit even though it is
  // outside the ASCII whitelist this validator commits to.
  for (const bad of ['a\u0000b', 'ord\u00e9rs']) {
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
