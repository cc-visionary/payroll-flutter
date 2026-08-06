import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/widgets/live_refresh.dart';

/// The debounce/lifecycle logic behind [LiveRefreshMixin] is extracted into
/// [RefreshDebouncer] so it can be exercised without a live Supabase socket.
/// (The Realtime channel wiring in the mixin is verified by the two-window
/// manual test documented in the design spec.)
///
/// These run under [testWidgets] purely to get flutter_test's fake clock, so
/// `tester.pump(duration)` deterministically advances the debounce [Timer].
void main() {
  testWidgets('fires once after the debounce window elapses', (tester) async {
    await tester.pumpWidget(const SizedBox());
    var fires = 0;
    final debouncer = RefreshDebouncer(
      const Duration(milliseconds: 300),
      () => fires++,
    );

    debouncer.schedule();
    expect(fires, 0, reason: 'must not fire synchronously');

    await tester.pump(const Duration(milliseconds: 299));
    expect(fires, 0, reason: 'still inside the window');

    await tester.pump(const Duration(milliseconds: 1));
    expect(fires, 1, reason: 'fires exactly at the window boundary');

    debouncer.dispose();
  });

  testWidgets('coalesces a burst of schedules into a single fire', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    var fires = 0;
    final debouncer = RefreshDebouncer(
      const Duration(milliseconds: 300),
      () => fires++,
    );

    // A bulk release touches many payslip rows in quick succession; each
    // Realtime message calls schedule(), which must reset the window.
    debouncer.schedule();
    await tester.pump(const Duration(milliseconds: 100));
    debouncer.schedule();
    await tester.pump(const Duration(milliseconds: 100));
    debouncer.schedule();

    await tester.pump(const Duration(milliseconds: 300));
    expect(fires, 1, reason: 'one refresh for the whole burst');

    debouncer.dispose();
  });

  testWidgets('does not fire when disposed before the window elapses', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    var fires = 0;
    final debouncer = RefreshDebouncer(
      const Duration(milliseconds: 300),
      () => fires++,
    );

    debouncer.schedule();
    debouncer.dispose();

    await tester.pump(const Duration(milliseconds: 300));
    expect(fires, 0, reason: 'a disposed screen must not be invalidated');
  });

  testWidgets('ignores schedule() after dispose and leaves no pending timer', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    var fires = 0;
    final debouncer = RefreshDebouncer(
      const Duration(milliseconds: 300),
      () => fires++,
    );

    debouncer.dispose();
    debouncer.schedule();

    // If schedule() armed a timer here, flutter_test would fail the test with
    // a "Timer is still pending" error at teardown.
    await tester.pump(const Duration(milliseconds: 300));
    expect(fires, 0);
  });
}
