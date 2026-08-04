import 'dart:convert';
import 'dart:typed_data';

/// Decode a base64 signature PNG. Null/empty/garbage → null so a corrupt
/// upload degrades to a blank sign line instead of crashing the render.
Uint8List? decodeSignaturePngB64(String? b64) {
  if (b64 == null || b64.isEmpty) return null;
  try {
    return base64Decode(b64);
  } catch (_) {
    return null;
  }
}
