import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'profile_service.dart';

/// Friend leaderboard backend (Package BH) — Firestore only.
///
/// Data model:
/// - `leaderboards/{code}` — one doc per board:
///   `{name, createdBy, createdAt, memberUids: [uid], members: [{uid, name, avatar}]}`
///   `memberUids` is the flat uid array so boards can be queried with
///   `arrayContains` (Firestore can't `array-contains` a field inside a map).
/// - `leaderboards/{code}/scores/{uid_yyyy-MM}` — one doc per member per
///   month: `{uid, name, saved, spent, month}`.
///
/// All failures are swallowed and reported as safe defaults (empty string,
/// `false`, empty list) so the UI never crashes on cloud errors.
class LeaderboardService {
  LeaderboardService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final _random = Random.secure();
  static const _codeChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  /// Best-effort display name: Firebase display name, else email prefix,
  /// else 'Guest user' (matching the auth_guest_label convention).
  static String _displayName() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 'Guest user';
    if (user.displayName?.isNotEmpty == true) return user.displayName!;
    final email = user.email;
    if (email != null && email.isNotEmpty) return email.split('@').first;
    return 'Guest user';
  }

  /// One 6-char board code from unambiguous A-Z0-9 (no 0/O/1/I).
  static String _newCode() => String.fromCharCodes(
        List.generate(
          6,
          (_) => _codeChars.codeUnitAt(_random.nextInt(_codeChars.length)),
        ),
      );

  /// Creates a board owned by the current user. Returns the 6-char code,
  /// or `''` when not signed in / on failure.
  static Future<String> createBoard(String name) async {
    try {
      final uid = _uid;
      if (uid == null) return '';
      final trimmed = name.trim();
      if (trimmed.isEmpty) return '';

      final boards = _db.collection('leaderboards');
      // Retry on the astronomically-rare code collision.
      for (var attempt = 0; attempt < 5; attempt++) {
        final code = _newCode();
        final ref = boards.doc(code);
        if ((await ref.get()).exists) continue;
        final avatar = await ProfileService.instance.getAvatarThumb();
        await ref.set({
          'name': trimmed,
          'createdBy': uid,
          'createdAt': FieldValue.serverTimestamp(),
          'memberUids': [uid],
          'members': [
            {'uid': uid, 'name': _displayName(), 'avatar': avatar},
          ],
        });
        return code;
      }
      return '';
    } catch (_) {
      return '';
    }
  }

  /// Adds the current user to the board [code]. Returns `true` on success
  /// (including already-a-member), `false` for unknown code / failure.
  static Future<bool> joinBoard(String code) async {
    try {
      final uid = _uid;
      if (uid == null) return false;
      final normalized = code.trim().toUpperCase();
      if (normalized.isEmpty) return false;

      final ref = _db.collection('leaderboards').doc(normalized);
      final snap = await ref.get();
      final data = snap.data();
      if (!snap.exists || data == null) return false;

      final uids =
          (data['memberUids'] as List?)?.whereType<String>().toList() ?? [];
      if (uids.contains(uid)) return true; // already in

      final avatar = await ProfileService.instance.getAvatarThumb();
      await ref.update({
        'memberUids': FieldValue.arrayUnion([uid]),
        'members': FieldValue.arrayUnion([
          {'uid': uid, 'name': _displayName(), 'avatar': avatar},
        ]),
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Boards the current user is a member of (each map includes 'code').
  static Future<List<Map<String, dynamic>>> myBoards() async {
    try {
      final uid = _uid;
      if (uid == null) return const [];
      final snap = await _db
          .collection('leaderboards')
          .where('memberUids', arrayContains: uid)
          .get();
      return snap.docs
          .map((d) => {'code': d.id, ...d.data()})
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  /// uid → avatar (base64) map for the board's members, for the ranking UI.
  /// Returns `{}` on any failure.
  static Future<Map<String, String>> boardAvatars(String code) async {
    try {
      final snap = await _db
          .collection('leaderboards')
          .doc(code.trim().toUpperCase())
          .get();
      final members = (snap.data()?['members'] as List?) ?? [];
      final out = <String, String>{};
      for (final m in members) {
        if (m is Map) {
          final uid = m['uid'];
          final avatar = m['avatar'];
          if (uid is String && avatar is String && avatar.isNotEmpty) {
            out[uid] = avatar;
          }
        }
      }
      return out;
    } catch (_) {
      return const {};
    }
  }

  /// Publishes the current user's score for the current month:
  /// doc `leaderboards/{code}/scores/{uid_yyyy-MM}`.
  static Future<void> publishScore(
    String code,
    double saved,
    double spent,
  ) async {
    try {
      final uid = _uid;
      if (uid == null) return;
      final now = DateTime.now();
      final m = now.month.toString().padLeft(2, '0');
      final month = '${now.year}-$m';
      await _db
          .collection('leaderboards')
          .doc(code.trim().toUpperCase())
          .collection('scores')
          .doc('${uid}_$month')
          .set({
        'uid': uid,
        'name': _displayName(),
        'saved': saved,
        'spent': spent,
        'month': month,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Cloud failure: silently ignored, UI shows a retry hint via snackbar.
    }
  }

  /// All published scores for [code] in [monthKey] (`yyyy-MM`),
  /// sorted by `saved` descending.
  static Future<List<Map<String, dynamic>>> boardScores(
    String code,
    String monthKey,
  ) async {
    try {
      final snap = await _db
          .collection('leaderboards')
          .doc(code.trim().toUpperCase())
          .collection('scores')
          .where('month', isEqualTo: monthKey)
          .get();
      final rows =
          snap.docs.map((d) => d.data()).toList(growable: false);
      rows.sort((a, b) =>
          ((b['saved'] as num?) ?? 0).compareTo((a['saved'] as num?) ?? 0));
      return rows;
    } catch (_) {
      return const [];
    }
  }
}
