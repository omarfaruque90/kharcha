import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';

/// Manages the user's profile picture (avatar) WITHOUT Firebase Storage.
///
/// Avatars are tiny: a 256x256 JPEG at 75% quality is ~10-20KB, base64
/// ~15-30KB — it fits easily in a Firestore document. The thumbnail is
/// stored at `users/{uid}` field `avatarThumb`, so it syncs across devices
/// and works on the free Spark plan (Storage now requires Blaze).
///
/// All failures are swallowed and reported as `null`/`false` — the UI
/// stays usable without a photo.
class ProfileService {
  ProfileService._();
  static final ProfileService instance = ProfileService._();

  final ImagePicker _picker = ImagePicker();

  /// In-memory cache so the settings row doesn't hit Firestore on every build.
  String? _cachedThumb;
  bool _cacheLoaded = false;

  DocumentReference<Map<String, dynamic>>? _userDoc() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance.collection('users').doc(uid);
  }

  /// Lets the user pick a photo then saves a 256px JPEG thumbnail (base64)
  /// to Firestore. Returns `true` on success, `false` on cancel/failure.
  Future<bool> pickAndSaveAvatar({bool fromCamera = false}) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.isAnonymous) return false;

      final file = await _picker.pickImage(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 256,
        maxHeight: 256,
        imageQuality: 75,
      );
      if (file == null) return false; // user cancelled

      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return false;
      final thumb = base64Encode(bytes);

      final doc = _userDoc();
      if (doc == null) return false;
      await doc.set({'avatarThumb': thumb}, SetOptions(merge: true));

      _cachedThumb = thumb;
      _cacheLoaded = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Returns the cached/fetched base64 avatar thumbnail, or `null`.
  Future<String?> getAvatarThumb() async {
    if (_cacheLoaded) return _cachedThumb;
    try {
      final doc = _userDoc();
      if (doc == null) {
        _cacheLoaded = true;
        return null;
      }
      final snap = await doc.get();
      final thumb = snap.data()?['avatarThumb'];
      _cachedThumb = (thumb is String && thumb.isNotEmpty) ? thumb : null;
      _cacheLoaded = true;
      return _cachedThumb;
    } catch (_) {
      _cacheLoaded = true;
      return null;
    }
  }

  /// Synchronous access to the cached thumbnail (null until first load).
  String? get cachedAvatarThumb => _cacheLoaded ? _cachedThumb : null;

  /// True once the avatar has been loaded at least once this session.
  bool get avatarCacheReady => _cacheLoaded;

  /// Deletes the avatar. Returns `true` on success.
  Future<bool> removeAvatar() async {
    try {
      final doc = _userDoc();
      if (doc == null) return false;
      await doc.update({'avatarThumb': FieldValue.delete()});
      _cachedThumb = null;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Clears the in-memory cache (call on logout / account switch).
  void clearCache() {
    _cachedThumb = null;
    _cacheLoaded = false;
  }
}
