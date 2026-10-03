import 'dart:convert';

import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../services/auth_service.dart';
import '../services/profile_service.dart';
import '../widgets/motion.dart';

/// Shows the signed-in user's profile: avatar, name, email, and a
/// change-photo flow backed by a Firestore thumbnail (no Storage needed).
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _uploading = false;
  bool _loading = true;
  String? _avatarThumb;

  @override
  void initState() {
    super.initState();
    _loadAvatar();
  }

  Future<void> _loadAvatar() async {
    final thumb = await ProfileService.instance.getAvatarThumb();
    if (!mounted) return;
    setState(() {
      _avatarThumb = thumb;
      _loading = false;
    });
  }

  ImageProvider? get _avatarImage {
    if (_avatarThumb == null || _avatarThumb!.isEmpty) return null;
    try {
      return MemoryImage(base64Decode(_avatarThumb!));
    } catch (_) {
      return null;
    }
  }

  Future<void> _changePhoto({required bool fromCamera}) async {
    if (_uploading) return;
    setState(() => _uploading = true);
    try {
      final ok = await ProfileService.instance
          .pickAndSaveAvatar(fromCamera: fromCamera);
      if (!mounted) return;
      if (ok) {
        await _loadAvatar();
        if (!mounted) return;
        _snack(tr(context, 'profile_upload_done'));
      } else {
        _snack(tr(context, 'profile_upload_failed'));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _removePhoto() async {
    if (_uploading) return;
    setState(() => _uploading = true);
    try {
      final ok = await ProfileService.instance.removeAvatar();
      if (!mounted) return;
      if (ok) {
        setState(() => _avatarThumb = null);
        _snack(tr(context, 'profile_upload_done'));
      } else {
        _snack(tr(context, 'profile_upload_failed'));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _pickSource() async {
    final hasAvatar = _avatarThumb != null && _avatarThumb!.isNotEmpty;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: Text(tr(ctx, 'profile_take_photo')),
              onTap: () => Navigator.of(ctx).pop('camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: Text(tr(ctx, 'profile_choose_gallery')),
              onTap: () => Navigator.of(ctx).pop('gallery'),
            ),
            if (hasAvatar)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: Text(tr(ctx, 'profile_remove_photo')),
                onTap: () => Navigator.of(ctx).pop('remove'),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'remove') {
      await _removePhoto();
    } else {
      await _changePhoto(fromCamera: choice == 'camera');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.currentUser;
    final displayName = user?.displayName?.isNotEmpty == true
        ? user!.displayName!
        : (user?.email ?? (user?.isAnonymous == true
            ? tr(context, 'auth_guest_label')
            : ''));
    final initial = displayName.isNotEmpty
        ? displayName[0].toUpperCase()
        : '?';
    final isGuest = user?.isAnonymous == true;
    final avatarImage = _avatarImage;

    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'profile_title'))),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          StaggeredEntrance(
            child: Center(
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 56,
                    backgroundImage: avatarImage,
                    child: (_loading || avatarImage == null)
                        ? (_loading
                            ? const SizedBox(
                                width: 28,
                                height: 28,
                                child: CircularProgressIndicator(
                                    strokeWidth: 3),
                              )
                            : Text(initial,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium))
                        : null,
                  ),
                  if (_uploading)
                    const Positioned.fill(
                      child: Center(child: CircularProgressIndicator()),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: FilledButton.tonalIcon(
              onPressed: (isGuest || _uploading) ? null : _pickSource,
              icon: const Icon(Icons.edit),
              label: Text(
                _uploading
                    ? tr(context, 'profile_uploading')
                    : tr(context, 'profile_change_photo'),
              ),
            ),
          ),
          if (isGuest) ...[
            const SizedBox(height: 8),
            Center(
              child: Text(
                tr(context, 'profile_guest_note'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
          const SizedBox(height: 24),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.person),
            title: Text(displayName.isNotEmpty
                ? displayName
                : tr(context, 'auth_account')),
            subtitle: user?.email != null ? Text(user!.email!) : null,
          ),
        ],
      ),
    );
  }
}
