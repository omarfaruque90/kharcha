import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_strings.dart';
import '../../main.dart';
import '../../services/auth_service.dart';
import '../../widgets/motion.dart';
import 'auth_widgets.dart';

/// Two-step phone login: enter number -> enter 6-digit SMS code.
class PhoneScreen extends StatefulWidget {
  const PhoneScreen({super.key});

  @override
  State<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends State<PhoneScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  String? _verificationId;
  String? _sentTo;
  bool _busy = false;

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final number = _phone.text.trim();
    if (number.replaceAll(RegExp(r'\D'), '').length < 10) {
      showAuthError(context, const AuthException('invalid-phone-number'));
      return;
    }
    setState(() => _busy = true);
    await AuthService.instance.startPhoneVerification(
      phoneNumber: number,
      onCodeSent: (verificationId) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _verificationId = verificationId;
          _sentTo = AuthService.normalizeBdPhone(number);
        });
      },
      onAutoVerified: () {
        // Firebase signed in silently — AuthGate takes over.
        if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
      },
      onFailed: (e) {
        if (!mounted) return;
        setState(() => _busy = false);
        showAuthError(context, e);
      },
    );
  }

  Future<void> _verifyCode() async {
    final id = _verificationId;
    if (id == null || _code.text.trim().length < 6) {
      showAuthError(context, const AuthException('invalid-verification-code'));
      return;
    }
    setState(() => _busy = true);
    try {
      await AuthService.instance.confirmPhoneCode(
        verificationId: id,
        smsCode: _code.text,
      );
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (mounted) showAuthError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _changeNumber() {
    setState(() {
      _verificationId = null;
      _code.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final otpStep = _verificationId != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, otpStep ? 'auth_otp_title' : 'auth_phone_title')),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AuthHeader(
                  titleKey:
                      otpStep ? 'auth_otp_title' : 'auth_phone_title',
                  subtitleKey:
                      otpStep ? 'auth_otp_sub' : 'auth_phone_sub',
                ),
                if (otpStep && _sentTo != null) ...[
                  const SizedBox(height: 8),
                  StaggeredEntrance(
                    delayMs: 200,
                    child: Text(
                      _sentTo!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: kGold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                if (!otpStep)
                  StaggeredEntrance(
                    delayMs: 260,
                    child: AuthField(
                      controller: _phone,
                      labelKey: 'auth_phone_hint',
                      hintKey: 'auth_phone_hint',
                      keyboardType: TextInputType.phone,
                      onSubmitted: (_) => _sendCode(),
                    ),
                  )
                else
                  StaggeredEntrance(
                    delayMs: 260,
                    child: TextField(
                      controller: _code,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 26,
                        letterSpacing: 8,
                        fontWeight: FontWeight.bold,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly
                      ],
                      decoration: InputDecoration(
                        hintText: tr(context, 'auth_otp_hint'),
                        counterText: '',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onSubmitted: (_) => _verifyCode(),
                    ),
                  ),
                const SizedBox(height: 18),
                StaggeredEntrance(
                  delayMs: 320,
                  child: PressableScale(
                    child: FilledButton(
                      onPressed:
                          _busy ? null : (otpStep ? _verifyCode : _sendCode),
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
                              tr(
                                  context,
                                  otpStep
                                      ? 'auth_verify_btn'
                                      : 'auth_send_otp'),
                              style: const TextStyle(fontSize: 16),
                            ),
                    ),
                  ),
                ),
                if (otpStep) ...[
                  const SizedBox(height: 8),
                  StaggeredEntrance(
                    delayMs: 380,
                    child: TextButton(
                      onPressed: _busy ? null : _changeNumber,
                      child: Text(tr(context, 'auth_change_number')),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
