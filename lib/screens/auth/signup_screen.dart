import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../main.dart';
import '../../services/auth_service.dart';
import '../../widgets/motion.dart';
import 'auth_widgets.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _signup() async {
    if (!_formKey.currentState!.validate()) return;
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await AuthService.instance.signUpWithEmail(
        email: _email.text,
        password: _password.text,
        name: _name.text,
      );
      // Success: AuthGate's stream switches to the app automatically.
      // Pop pushed auth routes so the fresh home shows underneath.
      if (mounted) {
        Navigator.of(context).popUntil((r) => r.isFirst);
      }
    } catch (e) {
      if (mounted) showAuthError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'auth_signup_title'))),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AuthHeader(
                  titleKey: 'auth_signup_title',
                  subtitleKey: 'auth_signup_sub',
                ),
                const SizedBox(height: 24),
                StaggeredEntrance(
                  delayMs: 240,
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        AuthField(
                          controller: _name,
                          labelKey: 'auth_name',
                          hintKey: 'auth_name_hint',
                        ),
                        const SizedBox(height: 14),
                        AuthField(
                          controller: _email,
                          labelKey: 'auth_email',
                          hintKey: 'auth_email_hint',
                          keyboardType: TextInputType.emailAddress,
                          validator: (v) =>
                              (v == null || !v.contains('@')) ? '—' : null,
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
                        ),
                        const SizedBox(height: 14),
                        AuthField(
                          controller: _confirm,
                          labelKey: 'auth_password_confirm',
                          hintKey: 'auth_password_hint',
                          obscure: true,
                          validator: (v) =>
                              (v != _password.text) ? '—' : null,
                          onSubmitted: (_) => _signup(),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                StaggeredEntrance(
                  delayMs: 320,
                  child: PressableScale(
                    child: FilledButton(
                      onPressed: _busy ? null : _signup,
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
                              tr(context, 'auth_signup_btn'),
                              style: const TextStyle(fontSize: 16),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                StaggeredEntrance(
                  delayMs: 380,
                  child: TextButton(
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    child: Text(tr(context, 'auth_have_account')),
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
