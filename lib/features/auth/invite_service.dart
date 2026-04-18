import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Auth operations beyond plain sign-in: signup for new employers, password
/// reset, and (server-side) bootstrapping a new company after signup.
///
/// The app is for employers / HR / payroll admins. Individual employees do
/// NOT log in — they are tracked as `employees` rows by their employer.
class InviteService {
  final SupabaseClient _client;
  InviteService(this._client);

  /// Create a new employer account AND bootstrap the company record so the
  /// user can immediately start using the app.
  ///
  /// Flow:
  /// 1. `auth.signUp` creates the Supabase auth user. With email confirmation
  ///    disabled in Supabase settings, the returned session is live and the
  ///    user is signed in. With confirmation ON the session is null — the
  ///    caller should surface "check your inbox" and abort the bootstrap.
  /// 2. While the new session is live we invoke the `bootstrap-company` Edge
  ///    Function with the company name. The function (using the service-role
  ///    key server-side) creates a `companies` row, a `users` row linking the
  ///    auth user to that company, and sets `app_metadata.app_role =
  ///    SUPER_ADMIN` + `app_metadata.company_id = NEW_UUID` so the JWT RLS
  ///    helpers work on the next request.
  /// 3. The caller must sign out + sign back in (or refresh the session) so
  ///    the JWT picks up the new `app_metadata` claims.
  Future<SignUpOutcome> signUpEmployer({
    required String email,
    required String password,
    required String companyName,
  }) async {
    final auth = await _client.auth.signUp(
      email: email,
      password: password,
      data: {'company_name': companyName},
    );
    if (auth.user == null) {
      throw const AuthException(
          'Sign-up failed — Supabase returned no user.');
    }
    if (auth.session == null) {
      // Email confirmation is on. We cannot bootstrap now; the user must
      // click the confirmation link first, then sign in normally. Bootstrap
      // happens on that first sign-in via a different path (optional — for
      // MVP we ask admins to disable email confirmation).
      return SignUpOutcome.emailConfirmationRequired;
    }
    // Session live — bootstrap the company server-side.
    final res = await _client.functions.invoke(
      'bootstrap-company',
      body: {'company_name': companyName},
    );
    final data = (res.data as Map?) ?? const {};
    if (data['ok'] != true) {
      throw Exception(
          data['error']?.toString() ?? 'Company bootstrap failed');
    }
    // Refresh the session so the new app_metadata claims appear in the JWT.
    await _client.auth.refreshSession();
    return SignUpOutcome.readyToUse;
  }

  /// Trigger a password-reset email. Supabase silently returns 200 even for
  /// unknown emails (prevents enumeration), so always show a generic message.
  Future<void> sendPasswordReset(String email, {String? redirectTo}) async {
    await _client.auth.resetPasswordForEmail(email, redirectTo: redirectTo);
  }
}

enum SignUpOutcome {
  /// Session is live and the company row exists — route to dashboard.
  readyToUse,

  /// Supabase needs the user to click an email link first. Caller should
  /// show "check your inbox" and stop.
  emailConfirmationRequired,
}

final inviteServiceProvider =
    Provider<InviteService>((ref) => InviteService(Supabase.instance.client));
