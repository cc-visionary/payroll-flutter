import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/settings/about/dismissed_update_version.dart';
import 'package:payroll_flutter/features/settings/about/startup_update_check.dart';
import 'package:payroll_flutter/features/settings/about/update_service.dart';
import 'package:payroll_flutter/widgets/update_banner.dart';
import 'package:shared_preferences/shared_preferences.dart';

UpdateAvailable _available({
  UpdateChannel channel = UpdateChannel.windowsInstaller,
  String version = '1.0.1',
}) =>
    UpdateAvailable(
      currentVersion: '1.0.0',
      channel: channel,
      manifest: UpdateManifest(
        version: version,
        platforms: const {
          'windows': PlatformAsset(url: 'https://example.test/Setup.exe'),
          'android': PlatformAsset(url: 'https://example.test/app.apk'),
        },
        stores: const {
          'ios': 'https://apps.apple.test/x',
          'android': 'https://play.test/x',
        },
      ),
    );

Future<void> _pump(WidgetTester tester, UpdateCheckResult? result) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        startupUpdateCheckProvider.overrideWith((ref) async => result),
      ],
      child: const MaterialApp(
        home: Scaffold(body: Column(children: [UpdateBanner()])),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('announces an available update', (tester) async {
    await _pump(tester, _available());
    expect(find.textContaining('Update available'), findsOneWidget);
    expect(find.textContaining('1.0.1'), findsOneWidget);
  });

  testWidgets('is absent when up to date', (tester) async {
    await _pump(tester, const UpdateUpToDate('1.0.0'));
    expect(find.byType(MaterialBanner), findsNothing);
  });

  testWidgets('is absent on a store channel', (tester) async {
    await _pump(tester, _available(channel: UpdateChannel.playStore));
    expect(find.byType(MaterialBanner), findsNothing);
  });

  testWidgets('is absent for an already dismissed version', (tester) async {
    SharedPreferences.setMockInitialValues({
      kDismissedUpdateVersionKey: '1.0.1',
    });
    await _pump(tester, _available(version: '1.0.1'));
    expect(find.byType(MaterialBanner), findsNothing);
  });

  testWidgets('Later persists the dismissal and hides the banner',
      (tester) async {
    await _pump(tester, _available(version: '1.0.1'));
    expect(find.byType(MaterialBanner), findsOneWidget);

    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();

    expect(find.byType(MaterialBanner), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kDismissedUpdateVersionKey), '1.0.1');
  });

  testWidgets('Update opens the shared dialog', (tester) async {
    await _pump(tester, _available());
    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();
    expect(find.text('Update available — v1.0.1'), findsOneWidget);
  });
}
