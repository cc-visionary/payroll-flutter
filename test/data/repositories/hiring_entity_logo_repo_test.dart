import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/repositories/hiring_entity_repository.dart';

void main() {
  test('decodeLogoBytes decodes base64; null/empty -> null', () {
    final b = decodeLogoBytes(base64.encode([1, 2, 3]));
    expect(b, isNotNull);
    expect(b!.toList(), [1, 2, 3]);
    expect(decodeLogoBytes(null), isNull);
    expect(decodeLogoBytes(''), isNull);
    expect(decodeLogoBytes('not valid base64 @@@'), isNull);
  });
}
