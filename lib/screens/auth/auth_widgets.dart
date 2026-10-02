import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_strings.dart';
import '../../main.dart';
import '../../providers/settings_provider.dart';
import '../../services/auth_service.dart';
import '../../widgets/motion.dart';

/// Shows an auth error as a SnackBar. Silently ignores user cancellation.
void showAuthError(BuildContext context, Object e) {
  if (e is AuthException && e.code == AuthException.cancelled) return;
  final lang = context.read<SettingsProvider>().language;
  final message = e is AuthException ? e.message(lang) : e.toString();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
  );
}

/// Branded header used on all auth screens.
class AuthHeader extends StatelessWidget {
  final String titleKey;
  final String subtitleKey;

  const AuthHeader({
    super.key,
    required this.titleKey,
    required this.subtitleKey,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        StaggeredEntrance(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Image.asset('assets/app_logo.png', width: 84, height: 84),
          ),
        ),
        const SizedBox(height: 12),
        const StaggeredEntrance(
          delayMs: 90,
          child: Text(
            'Kharcha',
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.bold,
              color: kGold,
              letterSpacing: 1.1,
            ),
          ),
        ),
        const SizedBox(height: 6),
        StaggeredEntrance(
          delayMs: 160,
          child: Text(
            tr(context, titleKey),
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 4),
        StaggeredEntrance(
          delayMs: 220,
          child: Text(
            tr(context, subtitleKey),
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Theme.of(context).hintColor),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

/// Consistent text field styling for auth forms.
class AuthField extends StatelessWidget {
  final TextEditingController controller;
  final String labelKey;
  final String hintKey;
  final TextInputType keyboardType;
  final bool obscure;
  final Widget? suffix;
  final String? Function(String?)? validator;
  final void Function(String)? onSubmitted;

  const AuthField({
    super.key,
    required this.controller,
    required this.labelKey,
    required this.hintKey,
    this.keyboardType = TextInputType.text,
    this.obscure = false,
    this.suffix,
    this.validator,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscure,
      validator: validator,
      onFieldSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: tr(context, labelKey),
        hintText: tr(context, hintKey),
        suffixIcon: suffix,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

/// "or" divider between login methods.
class AuthOrDivider extends StatelessWidget {
  const AuthOrDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            tr(context, 'auth_or'),
            style: TextStyle(color: Theme.of(context).hintColor),
          ),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }
}

/// Google "G" badge (no official icon in Material).
class GoogleBadge extends StatelessWidget {
  const GoogleBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      child: const Text(
        'G',
        style: TextStyle(
          color: Color(0xFF4285F4),
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
    );
  }
}
