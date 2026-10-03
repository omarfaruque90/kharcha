import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../main.dart';
import '../../services/auth_service.dart';
import '../../widgets/motion.dart';
import 'auth_widgets.dart';
import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      // Success: AuthGate's stream switches to the app automatically.
    } catch (e) {
      if (mounted) showAuthError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _loginEmail() {
    if (!_formKey.currentState!.validate()) return;
    _run(() => AuthService.instance.signInWithEmail(
          email: _email.text,
          password: _password.text,
        ));
  }

  void _goSignup() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SignupScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AuthHeader(
                  titleKey: 'auth_login_title',
                  subtitleKey: 'auth_login_sub',
                ),
                const SizedBox(height: 28),
                StaggeredEntrance(
                  delayMs: 280,
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        AuthField(
                          controller: _email,
                          labelKey: 'auth_email',
                          hintKey: 'auth_email_hint',
                          keyboardType: TextInputType.emailAddress,
                          validator: (v) =>
                              (v == null || !v.contains('@')) ? '—' : null,
                          onSubmitted: (_) => _loginEmail(),
                        ),
                        const SizedBox(height: 14),
                        AuthField(
                          controller: _password,
                          labelKey: 'auth_password',
                          hintKey: 'auth_password_hint',
                          obscure: _obscure,
                          suffix: IconButton(
                            icon: Icon(_obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                          validator: (v) =>
                              (v == null || v.length < 6) ? '—' : null,
                          onSubmitted: (_) => _loginEmail(),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                StaggeredEntrance(
                  delayMs: 340,
                  child: PressableScale(
                    child: FilledButton(
                      onPressed: _busy ? null : _loginEmail,
                      style: FilledButton.styleFrom(
                        backgroundColor: kEmerald,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              tr(context, 'auth_login_btn'),
                              style: const TextStyle(fontSize: 16),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                StaggeredEntrance(
                  delayMs: 400,
                  child: TextButton(
                    onPressed: _busy ? null : _goSignup,
                    child: Text(tr(context, 'auth_no_account')),
                  ),
                ),
                const SizedBox(height: 12),
                const StaggeredEntrance(
                    delayMs: 440, child: AuthOrDivider()),
                const SizedBox(height: 12),
                StaggeredEntrance(
                  delayMs: 480,
                  child: PressableScale(
                    child: OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () =>
                              _run(AuthService.instance.signInWithGoogle),
                      icon: const GoogleBadge(),
                      label: Text(tr(context, 'auth_google_btn')),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                StaggeredEntrance(
                  delayMs: 520,
                  child: PressableScale(
                    child: OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _run(AuthService
                              .instance.signInAnonymously),
                      icon: const Icon(Icons.person_outline),
                      label: Text(tr(context, 'auth_guest_btn')),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
