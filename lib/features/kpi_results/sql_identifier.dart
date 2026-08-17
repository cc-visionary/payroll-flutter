/// Whether [value] is safe to use, unescaped, as a Postgres table or column
/// name once quoted with double quotes by the caller.
///
/// This is the courtesy half of a rule enforced in two languages. An admin
/// typing a table/column name into Settings gets a message here instead of
/// discovering the mistake at month-end compute time. The half that actually
/// guards the database is `quoteIdentifier` in
/// `supabase/functions/_shared/source_query.ts` — that one must hold even if
/// this one is bypassed entirely, so do not let this function's rules drift
/// from that one's.
///
/// The rule: an ASCII letter or underscore, followed by any number of ASCII
/// letters, digits, or underscores, at most 63 bytes long (Postgres's
/// `NAMEDATALEN` limit, one less than the 64-byte storage limit). Nothing
/// else — no dots (schema-qualification is a separate, explicitly-typed
/// field, never smuggled through the object name), no quotes, no whitespace,
/// no SQL comment markers, no operators. Anything outside that shape could
/// change the statement it ends up in, so it is refused rather than escaped.
bool isValidSqlIdentifier(String value) {
  if (value.isEmpty || value.length > 63) return false;
  return RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(value);
}
