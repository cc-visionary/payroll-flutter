import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/hiring_entity.dart';
import 'package:payroll_flutter/features/documents/brand_logo.dart';

HiringEntity _entity({String? logo}) => HiringEntity(
      id: '1', companyId: 'c', code: 'X', name: 'Acme', country: 'PH',
      isActive: true, logoBase64: logo,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('prefers entity base64 over bundled asset', () async {
    final bytes = await loadCompanyLogoBytes(_entity(logo: base64.encode([9, 8, 7])));
    expect(bytes, isNotNull);
    expect(bytes!.toList(), [9, 8, 7]);
  });

  test('null entity falls back to brand logo (no crash)', () async {
    // Falls through to loadBrandLogoBytes which loads the bundled brand asset.
    final bytes = await loadCompanyLogoBytes(null);
    // In test env with assets, this returns the Luxium logo bytes; no crash.
    expect(bytes, isNotNull);
    expect(bytes, isA<Uint8List>());
  });
}
