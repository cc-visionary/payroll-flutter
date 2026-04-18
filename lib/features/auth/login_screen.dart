import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'invite_service.dart';

enum _Mode { signIn, signUp }

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _companyName = TextEditingController();
  _Mode _mode = _Mode.signIn;
  bool _loading = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _companyName.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() {
      _loading = true;
      _error = null;
      _info = null;
    });
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _email.text.trim(),
        password: _password.text,
      );
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signUp() async {
    final email = _email.text.trim();
    final password = _password.text;
    final company = _companyName.text.trim();
    if (email.isEmpty || password.isEmpty || company.isEmpty) {
      setState(() => _error = 'Email, password and company name are required.');
      return;
    }
    if (password.length < 8) {
      setState(() =>
          _error = 'Password must be at least 8 characters.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _info = null;
    });
    try {
      final outcome = await ref.read(inviteServiceProvider).signUpEmployer(
            email: email,
            password: password,
            companyName: company,
          );
      if (!mounted) return;
      switch (outcome) {
        case SignUpOutcome.readyToUse:
          // Router will auto-navigate to /dashboard once the auth state
          // change lands — no explicit push needed.
          setState(() => _info = 'Welcome! Setting up your workspace…');
        case SignUpOutcome.emailConfirmationRequired:
          setState(() {
            _mode = _Mode.signIn;
            _info = 'Check your inbox — confirm your email, then sign in.';
          });
      }
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _error =
          'Enter your email first, then tap "Forgot password?".');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _info = null;
    });
    try {
      await ref.read(inviteServiceProvider).sendPasswordReset(email);
      if (!mounted) return;
      setState(() => _info =
          'If an account exists for $email, a reset link is on the way.');
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggleMode() {
    setState(() {
      _mode = _mode == _Mode.signIn ? _Mode.signUp : _Mode.signIn;
      _error = null;
      _info = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isSignUp = _mode == _Mode.signUp;
    final submit = isSignUp ? _signUp : _signIn;
    final title = isSignUp ? 'Create your workspace' : 'Sign in';
    final submitLabel = isSignUp ? 'Create account' : 'Sign in';
    final toggleLabel = isSignUp
        ? 'Already have an account? Sign in'
        : 'New employer? Create a workspace';

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      Icon(Icons.payments,
                          color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      const Text('Luxium Payroll',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 18)),
                    ]),
                    const SizedBox(height: 16),
                    Text(title,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                      isSignUp
                          ? 'Set up your company workspace. You can add hiring entities, departments, and employees once you are inside.'
                          : 'Welcome back.',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 20),
                    if (isSignUp) ...[
                      TextField(
                        controller: _companyName,
                        decoration: const InputDecoration(
                          labelText: 'Company name',
                          border: OutlineInputBorder(),
                        ),
                        textCapitalization: TextCapitalization.words,
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: _email,
                      decoration: const InputDecoration(
                          labelText: 'Email',
                          border: OutlineInputBorder()),
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _password,
                      decoration: InputDecoration(
                        labelText:
                            isSignUp ? 'Password (min 8 chars)' : 'Password',
                        border: const OutlineInputBorder(),
                      ),
                      obscureText: true,
                      autofillHints: [
                        if (isSignUp)
                          AutofillHints.newPassword
                        else
                          AutofillHints.password,
                      ],
                      onSubmitted: (_) => submit(),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                    ],
                    if (_info != null) ...[
                      const SizedBox(height: 12),
                      Text(_info!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.primary)),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _loading ? null : submit,
                      child: _loading
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(submitLabel),
                    ),
                    if (!isSignUp) ...[
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _loading ? null : _forgotPassword,
                          child: const Text('Forgot password?'),
                        ),
                      ),
                    ],
                    const Divider(height: 24),
                    Center(
                      child: TextButton(
                        onPressed: _loading ? null : _toggleMode,
                        child: Text(toggleLabel),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
