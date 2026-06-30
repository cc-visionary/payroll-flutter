import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/hiring_entity.dart';
import 'package:payroll_flutter/data/repositories/hiring_entity_repository.dart';
import 'package:payroll_flutter/features/documents/brand_logo.dart';
import 'package:payroll_flutter/features/documents/providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ---------------------------------------------------------------------------
// Fake repository — subclasses the real one so the provider type matches,
// but overrides byId() and logoFor() to avoid any network calls.
// ---------------------------------------------------------------------------
class _FakeHiringEntityRepository extends HiringEntityRepository {
  _FakeHiringEntityRepository()
      : super(SupabaseClient(
          'https://stub.supabase.co',
          'stub-anon-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ));

  static const _uploadedBytes = [0xFF, 0xFE];
  static final _uploadedB64 = base64.encode(_uploadedBytes);

  @override
  Future<HiringEntity?> byId(String id) async {
    return HiringEntity(
      id: id,
      companyId: 'co-1',
      code: 'LUX',
      name: 'LUXIUM TRADING CO.',
      country: 'PH',
      isActive: true,
      logoBase64: _uploadedB64,
      logoMime: 'image/png',
    );
  }

  @override
  Future<List<HiringEntity>> list(String companyId) async => const [];

  @override
  Future<({String base64, String mime})?> logoFor(String entityId) async =>
      (base64: _uploadedB64, mime: 'image/png');
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('hiringEntityByIdProvider — logo resolution', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer(
        overrides: [
          hiringEntityRepositoryProvider
              .overrideWithValue(_FakeHiringEntityRepository()),
        ],
      );
    });

    tearDown(() => container.dispose());

    test('entity returned by provider has non-null logoBase64', () async {
      final entity =
          await container.read(hiringEntityByIdProvider('x').future);
      expect(entity, isNotNull);
      expect(entity!.logoBase64, isNotNull);
      expect(entity.logoBase64, isNotEmpty);
    });

    test(
        'loadCompanyLogoBytes returns uploaded bytes, not bundled fallback',
        () async {
      final entity =
          await container.read(hiringEntityByIdProvider('x').future);
      final bytes = await loadCompanyLogoBytes(entity);
      expect(bytes, isNotNull);
      // Must equal the decoded uploaded bytes.
      expect(bytes!.toList(), _FakeHiringEntityRepository._uploadedBytes);
    });
  });
}
