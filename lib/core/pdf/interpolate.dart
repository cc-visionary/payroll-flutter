/// Thrown by [interpolate] when a `{placeholder}` has no entry in `vars`.
class MissingPlaceholderError extends Error {
  final String key;
  MissingPlaceholderError(this.key);
  @override
  String toString() => 'MissingPlaceholderError: no value for "$key"';
}

/// Substitute `{key}` placeholders in [text] with values from [vars].
///
/// - Escaped braces `\{...\}` are preserved as literal `{...}`.
/// - When [lenient] is false (default), an unmatched placeholder throws
///   [MissingPlaceholderError]. When true, the placeholder is left in
///   place — useful for live previews while a form is incomplete.
String interpolate(
  String text,
  Map<String, String> vars, {
  bool lenient = false,
}) {
  final placeholder = RegExp(r'(\\\{|\\\}|\{([a-zA-Z0-9_.]+)\})');
  return text.replaceAllMapped(placeholder, (m) {
    final raw = m.group(0)!;
    if (raw == r'\{') return '{';
    if (raw == r'\}') return '}';
    final key = m.group(2)!;
    final value = vars[key];
    if (value == null) {
      if (lenient) return raw;
      throw MissingPlaceholderError(key);
    }
    return value;
  });
}
