import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/app/shell.dart';
import 'package:payroll_flutter/features/settings/about/startup_update_check.dart';
import 'package:payroll_flutter/features/settings/about/update_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

UpdateAvailable _available() => UpdateAvailable(
  currentVersion: '1.0.0',
  channel: UpdateChannel.sideloadAndroid,
  manifest: UpdateManifest(
    version: '1.0.1',
    platforms: const {
      'android': PlatformAsset(url: 'https://example.test/app.apk'),
    },
    stores: const {},
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // Regression guard for the mobile mount point (Finding 1 of the
  // whole-branch review): the shell used to return the routed child
  // directly on narrow windows, skipping the banner entirely — dropping it
  // for both a narrowed desktop window and the sideloaded-Android channel
  // that `_bannerChannels` explicitly enables.
  testWidgets('renders the update banner at mobile width', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          startupUpdateCheckProvider.overrideWith((ref) async => _available()),
        ],
        child: const MaterialApp(
          home: AppShell(child: Text('routed content')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MaterialBanner), findsOneWidget);
    expect(find.textContaining('Update available'), findsOneWidget);
    expect(find.text('routed content'), findsOneWidget);
  });
}
