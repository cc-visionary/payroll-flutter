import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'profile_provider.dart';

/// Forced first-login screen. Shown when `users.must_change_password = true`.
/// The router redirect prevents navigation away until the flag is cleared.
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});
  @override
  ConsumerState<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pw = _password.text;
    if (pw.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters.');
      return;
    }
    if (pw != _confirm.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final client = Supabase.instance.client;
      await client.auth.updateUser(UserAttributes(password: pw));
      // SECURITY DEFINER RPC: flips must_change_password=false for auth.uid().
      // Going through the `users` table directly relied on column-level grants
      // + RLS that can silently drop the row under some permission shapes —
      // the RPC avoids that trap so the flag always clears.
      await client.rpc('clear_must_change_password');
      ref.invalidate(userProfileProvider);
      if (mounted) context.go('/dashboard');
    } on AuthException catch (e) {
      setState(() => _error = _friendlyAuthError(e));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _friendlyAuthError(AuthException e) {
    final code = (e is AuthApiException ? e.code : null) ?? '';
    final msg = e.message;
    switch (code) {
      case 'same_password':
        return 'Your new password must be different from the temporary password.';
      case 'weak_password':
        return 'That password is too weak. Pick something longer or less common.';
      default:
        return msg;
    }
  }

  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut();
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set a new password'),
        automaticallyImplyLeading: false,
        actions: [
          TextButton(
            onPressed: _saving ? null : _signOut,
            child: const Text('Sign out'),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Your administrator set a temporary password for you. '
                  'Choose a new password to continue.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'New password (min 8 chars)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _confirm,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Confirm password',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _saving ? null : _submit,
                  child: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Set password'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
