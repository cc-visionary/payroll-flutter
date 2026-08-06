import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/core/pdf/interpolate.dart';

void main() {
  group('interpolate', () {
    test('substitutes single placeholder', () {
      expect(interpolate('Hello {name}', {'name': 'Donald'}), 'Hello Donald');
    });

    test('substitutes multiple placeholders', () {
      expect(
        interpolate('{a} + {b} = {c}', {'a': '1', 'b': '2', 'c': '3'}),
        '1 + 2 = 3',
      );
    });

    test('throws on missing placeholder by default', () {
      expect(
        () => interpolate('Hello {name}', {}),
        throwsA(isA<MissingPlaceholderError>()),
      );
    });

    test('lenient mode leaves missing placeholders intact', () {
      expect(interpolate('Hello {name}', {}, lenient: true), 'Hello {name}');
    });

    test('escaped braces stay literal', () {
      expect(
        interpolate(r'Use \{notAPlaceholder\} here', {}),
        'Use {notAPlaceholder} here',
      );
    });
  });
}
