import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/settings/about/dismissed_update_version.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('starts as null when nothing was ever dismissed', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(await c.read(dismissedUpdateVersionProvider.future), isNull);
  });

  test('reads a previously stored dismissal', () async {
    SharedPreferences.setMockInitialValues({
      kDismissedUpdateVersionKey: '1.0.1',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(await c.read(dismissedUpdateVersionProvider.future), '1.0.1');
  });

  test('dismiss persists the version and updates the state', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(dismissedUpdateVersionProvider.future);

    await c.read(dismissedUpdateVersionProvider.notifier).dismiss('1.0.2');

    expect(c.read(dismissedUpdateVersionProvider).value, '1.0.2');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kDismissedUpdateVersionKey), '1.0.2');
  });
}
