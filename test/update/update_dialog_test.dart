import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/settings/about/update_dialog.dart';
import 'package:payroll_flutter/features/settings/about/update_service.dart';

UpdateAvailable _available({String? notes}) => UpdateAvailable(
      currentVersion: '1.0.0',
      channel: UpdateChannel.windowsInstaller,
      manifest: UpdateManifest(
        version: '1.0.1',
        releaseNotes: notes,
        platforms: const {
          'windows': PlatformAsset(url: 'https://example.test/Setup.exe'),
        },
        stores: const {},
      ),
    );

Future<void> _pump(WidgetTester tester, UpdateAvailable update) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showUpdateDialog(context, ref, update),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows both versions', (tester) async {
    await _pump(tester, _available());
    expect(find.text('Update available — v1.0.1'), findsOneWidget);
    expect(find.text('Current: v1.0.0'), findsOneWidget);
  });

  testWidgets('renders release notes when present', (tester) async {
    await _pump(tester, _available(notes: 'Faster payroll runs'));
    expect(find.text('Release notes'), findsOneWidget);
    expect(find.text('Faster payroll runs'), findsOneWidget);
  });

  testWidgets('omits the release-notes heading when blank', (tester) async {
    await _pump(tester, _available(notes: '   '));
    expect(find.text('Release notes'), findsNothing);
  });

  testWidgets('Later closes the dialog without launching', (tester) async {
    await _pump(tester, _available());
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(find.text('Update available — v1.0.1'), findsNothing);
  });
}
