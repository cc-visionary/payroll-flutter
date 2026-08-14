// Table and column names for a configurable KPI source come out of
// configuration and end up inside a SQL statement executed against an
// external database. Only the period is ever a bound parameter — an
// identifier can never be, because Postgres has no placeholder syntax for
// "the name of a table" — so every identifier that reaches a statement built
// here is validated first and refused outright if it does not match.
//
// This is the security boundary. `isValidSqlIdentifier` in
// `lib/features/kpi_results/sql_identifier.dart` enforces the same rule in
// the app so an admin gets a message in Settings instead of a broken run at
// month-end, but that check is a courtesy and this file must not assume it
// ran. A direct API call, a row written by hand, or a caller nobody has
// written yet can all reach `buildSourceSelect` without ever going through
// the Dart side.
//
// Escaping a hostile identifier was considered and rejected. Escaping is a
// judgement call about what is safe to let through; refusing is not, and an
// identifier that fails this check is refused, never sanitised and passed
// on.

const IDENTIFIER_PATTERN = /^[A-Za-z_][A-Za-z0-9_]*$/;

/// Double-quotes [value] for use as a Postgres identifier — a table, view,
/// schema, or column name — after checking it against the same shape
/// `isValidSqlIdentifier` accepts: an ASCII letter or underscore, then any
/// number of ASCII letters/digits/underscores, at most 63 bytes (Postgres's
/// `NAMEDATALEN` limit). Anything else throws rather than being escaped —
/// see the module doc comment for why.
export function quoteIdentifier(value: string): string {
  if (
    typeof value !== 'string' ||
    value.length === 0 ||
    value.length > 63 ||
    !IDENTIFIER_PATTERN.test(value)
  ) {
    throw new Error(`Invalid SQL identifier: ${JSON.stringify(value)}`);
  }
  return `"${value}"`;
}

/// Builds the `select` a configurable KPI source runs against the external
/// database, given the schema/table/column names an admin configured for
/// this source. Every name in [args] passes through `quoteIdentifier` — a
/// hostile `object`, `schema`, or column name throws before any string
/// concatenation happens, so it never reaches the returned statement.
///
/// The period is the one part of this statement that is NOT an identifier —
/// it is data, so it is left as the bound parameter `$1` rather than being
/// inlined, and the caller supplies its value separately when executing.
///
/// [denominatorColumn] is optional: a COUNT-shaped KPI has no denominator at
/// all, and the returned statement selects a literal `null` for it rather
/// than a zero — the same "absent, not zero" rule `SourceRow` in
/// `lib/features/kpi_results/source_rows.dart` follows for the row this
/// query eventually produces.
export function buildSourceSelect(args: {
  schema: string;
  object: string;
  periodColumn: string;
  subjectColumn: string;
  numeratorColumn: string;
  denominatorColumn?: string;
}): string {
  const schema = quoteIdentifier(args.schema);
  const object = quoteIdentifier(args.object);
  const periodColumn = quoteIdentifier(args.periodColumn);
  const subjectColumn = quoteIdentifier(args.subjectColumn);
  const numeratorColumn = quoteIdentifier(args.numeratorColumn);
  const denominatorSelect = args.denominatorColumn === undefined
    ? 'null as denominator'
    : `${quoteIdentifier(args.denominatorColumn)} as denominator`;

  return `select ${periodColumn} as period, ${subjectColumn} as subject_key, `
    + `${numeratorColumn} as numerator, ${denominatorSelect} `
    + `from ${schema}.${object} where ${periodColumn} = $1`;
}
