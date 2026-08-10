import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:payroll_flutter/features/settings/about/startup_update_check.dart';
import 'package:payroll_flutter/features/settings/about/update_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Payroll',
      packageName: 'ph.luxium.payroll',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  UpdateService serving(String body, {int status = 200}) => UpdateService(
        httpClient: MockClient((_) async => http.Response(body, status)),
        manifestUrl: 'https://example.test/version.json',
      );

  ProviderContainer containerFor(UpdateService service) {
    final c = ProviderContainer(
      overrides: [updateServiceProvider.overrideWithValue(service)],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('surfaces an available update from the manifest', () async {
    final c = containerFor(serving(jsonEncode({
      'version': '1.0.1',
      'platforms': {
        'linux': {'url': 'https://example.test/app.AppImage'},
        'windows': {'url': 'https://example.test/Setup.exe'},
      },
    })));

    expect(
      await c.read(startupUpdateCheckProvider.future),
      isA<UpdateAvailable>(),
    );
  });

  test('reports up to date when the manifest matches the running build',
      () async {
    final c = containerFor(
      serving(jsonEncode({'version': '1.0.0', 'platforms': {}})),
    );

    expect(
      await c.read(startupUpdateCheckProvider.future),
      isA<UpdateUpToDate>(),
    );
  });

  test('a malformed manifest resolves to an error result, never a throw',
      () async {
    final c = containerFor(serving('not json at all'));

    expect(await c.read(startupUpdateCheckProvider.future), isA<UpdateError>());
  });

  test('a 404 manifest is treated as up to date', () async {
    final c = containerFor(serving('', status: 404));

    expect(
      await c.read(startupUpdateCheckProvider.future),
      isA<UpdateUpToDate>(),
    );
  });
}
