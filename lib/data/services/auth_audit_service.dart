import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../repositories/audit_repository.dart';

/// Subscribes to Supabase auth state changes and writes LOGIN / LOGOUT
/// rows to `audit_logs`.
///
/// Skips `initialSession` events — resumption of a persisted session
/// is not a fresh authentication, and logging it would spam the audit
/// log on every app launch. Also skips `tokenRefreshed`, `userUpdated`,
/// `passwordRecovery`, and `mfaChallengeVerified` — none represent a
/// new authentication or termination event.
///
/// Lives outside Riverpod by design: the subscription must start at
/// `main()` *before* `ProviderScope` mounts, because a persisted
/// Supabase session can already be active by the time the first widget
/// builds. We also need a single long-lived subscription that survives
/// widget rebuilds, which a Riverpod-scoped owner can't guarantee
/// without extra ceremony.
class AuthAuditService {
  AuthAuditService(this._repo);

  final AuditRepository _repo;
  StreamSubscription<AuthState>? _sub;

  // Snapshot of the previous tick's identity. We need this so logout
  // rows can be populated AFTER `currentUser` has already gone null —
  // Supabase clears the session before firing the `signedOut` event.
  String? _lastUserId;
  String? _lastUserEmail;

  /// Begins listening. Safe to call once at app startup; subsequent
  /// calls are no-ops while a subscription is active.
  void start(SupabaseClient client) {
    if (_sub != null) return;

    // Seed the snapshot from any already-restored session so an
    // immediate sign-out (before any signedIn event in this process)
    // still produces a populated audit row.
    final initial = client.auth.currentUser;
    _lastUserId = initial?.id;
    _lastUserEmail = initial?.email;

    _sub = client.auth.onAuthStateChange.listen((state) {
      final event = state.event;
      final session = state.session;
      switch (event) {
        case AuthChangeEvent.signedIn:
          _lastUserId = session?.user.id;
          _lastUserEmail = session?.user.email;
          _repo.logLogin();
          break;
        case AuthChangeEvent.signedOut:
          _repo.logLogout(_lastUserId, _lastUserEmail);
          _lastUserId = null;
          _lastUserEmail = null;
          break;
        // initialSession, tokenRefreshed, userUpdated, passwordRecovery,
        // mfaChallengeVerified: not authentication events worth logging.
        default:
          break;
      }
    });
  }

  /// Cancels the subscription. Intended for tests; production code
  /// leaves the service running for the lifetime of the process.
  void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}
