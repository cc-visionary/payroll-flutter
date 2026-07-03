import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Coalesces a burst of refresh triggers into a single deferred callback.
///
/// A cross-client change (e.g. a colleague releasing a run) can arrive as
/// several Realtime messages in quick succession — one per touched row. Firing
/// [onFire] for each would re-fetch the list many times over. [schedule]
/// (re)arms a single timer for [window]; only the last one in a burst survives,
/// so the whole burst produces exactly one [onFire].
///
/// After [dispose] the debouncer is inert: any pending fire is cancelled and
/// further [schedule] calls are ignored (so a widget that unmounted mid-window
/// is never invalidated).
class RefreshDebouncer {
  RefreshDebouncer(this.window, this.onFire);

  final Duration window;
  final VoidCallback onFire;

  Timer? _timer;
  bool _disposed = false;

  void schedule() {
    if (_disposed) return;
    _timer?.cancel();
    _timer = Timer(window, () {
      if (!_disposed) onFire();
    });
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}

/// Mixin that gives a [ConsumerStatefulWidget]'s state cross-client live
/// refresh: subscribe to Supabase Realtime changes on a set of tables and run a
/// (debounced) callback whenever any of them change server-side.
///
/// This is the list-screen counterpart to the per-row Realtime wiring already
/// used on the run detail screen (`payroll_run_detail_screen.dart`). A list
/// wants *every* row's changes, so — unlike the detail screen — no row filter
/// is applied.
///
/// Usage:
/// ```dart
/// class _MyScreenState extends ConsumerState<MyScreen>
///     with LiveRefreshMixin<MyScreen> {
///   @override
///   void initState() {
///     super.initState();
///     startLiveRefresh(
///       channel: 'my-screen',
///       tables: ['payroll_runs', 'payslips'],
///       onChange: () => ref.invalidate(myListProvider),
///     );
///   }
/// }
/// ```
mixin LiveRefreshMixin<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  RealtimeChannel? _liveChannel;
  RefreshDebouncer? _liveDebouncer;

  /// Opens one Realtime channel listening for all changes on [tables] and calls
  /// [onChange] (debounced by [debounce]) whenever any of them change. Safe to
  /// call once from `initState`. The channel is torn down automatically in
  /// [dispose].
  void startLiveRefresh({
    required String channel,
    required List<String> tables,
    required VoidCallback onChange,
    Duration debounce = const Duration(milliseconds: 300),
  }) {
    _liveDebouncer = RefreshDebouncer(debounce, () {
      if (mounted) onChange();
    });

    var builder = Supabase.instance.client.channel(channel);
    for (final table in tables) {
      builder = builder.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        callback: (_) => _liveDebouncer?.schedule(),
      );
    }
    _liveChannel = builder.subscribe();
  }

  @override
  void dispose() {
    _liveDebouncer?.dispose();
    _liveChannel?.unsubscribe();
    super.dispose();
  }
}
