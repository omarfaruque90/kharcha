import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

/// Uploads and manages the user's profile picture (avatar).
///
/// Photos are stored in Firebase Storage at `avatars/{uid}.jpg` and the
/// download URL is written to the Firebase Auth user's `photoURL`, so the
/// avatar follows the account across devices. All failures are swallowed
/// and reported as `null` — the UI stays usable without a photo.
class ProfileService {
  ProfileService._();
  static final ProfileService instance = ProfileService._();

  final ImagePicker _picker = ImagePicker();

  /// Lets the user pick a photo (gallery first, camera fallback via [fromCamera])
  /// then uploads it and updates the Auth profile. Returns the download URL,
  /// or `null` when the user cancels / something fails.
  Future<String?> pickAndUploadAvatar({bool fromCamera = false}) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;

      final file = await _picker.pickImage(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
      );
      if (file == null) return null; // user cancelled

      final ref = FirebaseStorage.instance
          .ref()
          .child('avatars')
          .child('${user.uid}.jpg');
      await ref.putFile(
        File(file.path),
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final url = await ref.getDownloadURL();
      await user.updatePhotoURL(url);
      // Refresh the cached user so photoURL is visible immediately.
      await user.reload();
      return url;
    } catch (_) {
      return null;
    }
  }

  /// Current avatar URL, if the user has one.
  String? get avatarUrl {
    final url = FirebaseAuth.instance.currentUser?.photoURL;
    return (url == null || url.isEmpty) ? null : url;
  }
}
