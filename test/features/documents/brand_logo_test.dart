import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/hiring_entity.dart';
import 'package:payroll_flutter/features/documents/brand_logo.dart';

HiringEntity _entity({String? logo}) => HiringEntity(
  id: '1',
  companyId: 'c',
  code: 'X',
  name: 'Acme',
  country: 'PH',
  isActive: true,
  logoBase64: logo,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('prefers entity base64 over bundled asset', () async {
    final bytes = await loadCompanyLogoBytes(
      _entity(logo: base64.encode([9, 8, 7])),
    );
    expect(bytes, isNotNull);
    expect(bytes!.toList(), [9, 8, 7]);
  });

  test('null entity falls back to loadBrandLogoBytes(null, null)', () async {
    final fallback = await loadBrandLogoBytes(companyName: null, code: null);
    final bytes = await loadCompanyLogoBytes(null);
    expect(bytes, fallback); // proves the same fallback path executed
  });
}
