import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/hiring_entity.dart';

void main() {
  test('fromRow reads logo fields when present', () {
    final e = HiringEntity.fromRow({
      'id': '1',
      'company_id': 'c',
      'code': 'GC',
      'name': 'GameCove',
      'country': 'PH',
      'is_active': true,
      'logo_base64': 'QUJD',
      'logo_mime': 'image/png',
    });
    expect(e.logoBase64, 'QUJD');
    expect(e.logoMime, 'image/png');
  });

  test('fromRow leaves logo null when columns absent (list query)', () {
    final e = HiringEntity.fromRow({
      'id': '1',
      'company_id': 'c',
      'code': 'GC',
      'name': 'GameCove',
      'country': 'PH',
      'is_active': true,
    });
    expect(e.logoBase64, isNull);
    expect(e.logoMime, isNull);
  });
}
