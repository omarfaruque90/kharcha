import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../providers/settings_provider.dart';
import '../services/lock_service.dart';

/// Full-screen PIN pad shown at startup when app lock is enabled.
/// Calls [onUnlock] after a correct PIN or a successful biometric check.
class LockScreen extends StatefulWidget {
  final VoidCallback onUnlock;

  const LockScreen({super.key, required this.onUnlock});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String _pin = '';
  bool _bioAvailable = false;
  bool _checking = true;
  bool _error = false;
  bool _verifying = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final bioOn = await LockService.instance.isBiometricEnabled();
    final canBio = await LockService.instance.canUseBiometrics();
    if (!mounted) return;
    setState(() {
      _bioAvailable = bioOn && canBio;
      _checking = false;
    });
    if (_bioAvailable) _tryBiometric();
  }

  Future<void> _tryBiometric() async {
    final lang =
        Provider.of<SettingsProvider>(context, listen: false).language;
    final ok = await LockService.instance.authenticateBiometric(
      AppStrings.get('lock_bio_reason', lang),
    );
    if (ok && mounted) widget.onUnlock();
  }

  void _press(String digit) {
    if (_verifying || _pin.length >= 4) return;
    setState(() {
      _pin += digit;
      _error = false;
    });
    if (_pin.length == 4) _verify();
  }

  void _backspace() {
    if (_verifying || _pin.isEmpty) return;
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
      _error = false;
    });
  }

  Future<void> _verify() async {
    setState(() => _verifying = true);
    final ok = await LockService.instance.verifyPin(_pin);
    if (!mounted) return;
    if (ok) {
      widget.onUnlock();
      return;
    }
    setState(() {
      _pin = '';
      _error = true;
      _verifying = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 64),
            ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Image.asset(
                'assets/app_logo.png',
                width: 96,
                height: 96,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              tr(context, 'lock_enter_pin'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < 4)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < _pin.length
                          ? scheme.primary
                          : scheme.primary.withValues(alpha: 0.18),
                      border: _error
                          ? Border.all(color: scheme.error, width: 2)
                          : null,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 24,
              child: _error
                  ? Text(
                      tr(context, 'lock_wrong_pin'),
                      style: TextStyle(color: scheme.error),
                    )
                  : null,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _checking
                  ? const Center(child: CircularProgressIndicator())
                  : GridView.count(
                      crossAxisCount: 3,
                      shrinkWrap: true,
                      padding:
                          const EdgeInsets.symmetric(horizontal: 64),
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 1.4,
                      children: [
                        for (var d = 1; d <= 9) _padKey('$d'),
                        _bioAvailable
                            ? IconButton(
                                iconSize: 30,
                                icon: const Icon(Icons.fingerprint),
                                color: scheme.primary,
                                onPressed: _tryBiometric,
                              )
                            : const SizedBox.shrink(),
                        _padKey('0'),
                        IconButton(
                          iconSize: 28,
                          icon: const Icon(Icons.backspace_outlined),
                          onPressed: _backspace,
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _padKey(String digit) {
    return InkWell(
      borderRadius: BorderRadius.circular(48),
      onTap: () => _press(digit),
      child: Center(
        child: Text(
          digit,
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}

/// Two-step "enter PIN → confirm PIN" dialog flow used from Settings.
/// Returns true when a new PIN was saved (and the lock enabled).
class SetPinFlow {
  static Future<bool> show(BuildContext context) async {
    final first = await _askPin(context, 'lock_set_pin');
    if (first == null || first.length != 4) return false;
    if (!context.mounted) return false;
    final second = await _askPin(context, 'lock_confirm_pin');
    if (second == null) return false;
    if (first != second) {
      if (!context.mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'lock_pin_mismatch'))),
      );
      return false;
    }
    await LockService.instance.setPin(first);
    return true;
  }

  static Future<String?> _askPin(BuildContext context, String titleKey) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dctx) => AlertDialog(
        title: Text(tr(dctx, titleKey)),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          maxLength: 4,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: '••••',
            counterText: '',
            helperText: tr(dctx, 'lock_pin_hint'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(),
            child: Text(tr(dctx, 'cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dctx)
                .pop(controller.text.trim()),
            child: Text(tr(dctx, 'confirm')),
          ),
        ],
      ),
    );
  }
}
