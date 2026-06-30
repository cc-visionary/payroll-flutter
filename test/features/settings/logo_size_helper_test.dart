import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/settings/hiring_entities/hiring_entities_settings_screen.dart';

void main() {
  group('logoSizeError', () {
    test('returns null for bytes exactly at the 300 KB cap', () {
      expect(logoSizeError(Uint8List(300 * 1024)), isNull);
    });

    test('returns null for bytes below the cap', () {
      expect(logoSizeError(Uint8List(1024)), isNull);
    });

    test('returns an error message for bytes one byte over the cap', () {
      final result = logoSizeError(Uint8List(300 * 1024 + 1));
      expect(result, isNotNull);
      expect(result, contains('300 KB'));
    });

    test('returns an error message for significantly oversized bytes', () {
      expect(logoSizeError(Uint8List(1024 * 1024)), isNotNull);
    });
  });
}
