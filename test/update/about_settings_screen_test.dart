import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:payroll_flutter/features/settings/about/about_settings_screen.dart';
import 'package:payroll_flutter/features/settings/about/update_service.dart';

// Regression guard for the showUpdateDialog extraction (spec:
// docs/superpowers/specs/2026-08-10-startup-update-banner-design.md, line
// ~198): drives the About tab's own "Check for Updates" button — its exact
// wiring to the shared dialog — rather than exercising the dialog in
// isolation like test/update/update_dialog_test.dart does.
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

  testWidgets(
    'About tab renders release notes through the extracted showUpdateDialog',
    (tester) async {
      final service = UpdateService(
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'version': '1.0.1',
              'releaseNotes': 'Faster payroll runs',
              'platforms': {
                'windows': {'url': 'https://example.test/Setup.exe'},
              },
            }),
            200,
          ),
        ),
        manifestUrl: 'https://example.test/version.json',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [updateServiceProvider.overrideWithValue(service)],
          child: const MaterialApp(home: Scaffold(body: AboutSettingsScreen())),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Check for Updates'));
      await tester.pumpAndSettle();

      expect(find.text('Update available — v1.0.1'), findsOneWidget);
      expect(find.text('Release notes'), findsOneWidget);
      expect(find.text('Faster payroll runs'), findsOneWidget);
    },
  );
}
