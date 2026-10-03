import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Authentication error with a stable [code] plus Bangla/English messages.
class AuthException implements Exception {
  final String code;

  /// Special code: user dismissed the flow. UI should ignore it silently.
  static const String cancelled = 'cancelled';

  const AuthException(this.code);

  static const Map<String, String> _bn = {
    'invalid-email': 'সঠিক ইমেইল ঠিকানা দিন',
    'user-not-found': 'এই ইমেইলে কোনো অ্যাকাউন্ট নেই',
    'wrong-password': 'ভুল পাসওয়ার্ড দিয়েছেন',
    'invalid-credential': 'ইমেইল বা পাসওয়ার্ড ভুল',
    'email-already-in-use': 'এই ইমেইল দিয়ে ইতিমধ্যে অ্যাকাউন্ট আছে',
    'weak-password': 'পাসওয়ার্ড কমপক্ষে ৬ অক্ষরের হতে হবে',
    'operation-not-allowed': 'এই লগইন পদ্ধতি এখন বন্ধ আছে',
    'too-many-requests': 'অনেকবার চেষ্টা করেছেন — কিছুক্ষণ পরে আবার চেষ্টা করুন',
    'network-request-failed': 'ইন্টারনেট সংযোগ নেই, সংযোগ চেক করুন',
    'invalid-phone-number': 'সঠিক ফোন নম্বর দিন (যেমন 01XXXXXXXXX)',
    'invalid-verification-code': 'ভুল OTP কোড দিয়েছেন',
    'invalid-verification-id': 'যাচাইয়ের মেয়াদ শেষ — আবার OTP পাঠান',
    'code-expired': 'OTP-এর মেয়াদ শেষ — আবার পাঠান',
    'quota-exceeded': 'SMS পাঠানোর সীমা শেষ — পরে চেষ্টা করুন',
    'user-disabled': 'এই অ্যাকাউন্টটি বন্ধ করে দেওয়া হয়েছে',
    'account-exists-with-different-credential':
        'এই ইমেইলে অন্য পদ্ধতিতে অ্যাকাউন্ট আছে',
    'google-failed': 'Google লগইন ব্যর্থ হয়েছে, আবার চেষ্টা করুন',
    'unknown': 'কিছু একটা সমস্যা হয়েছে — আবার চেষ্টা করুন',
  };

  static const Map<String, String> _en = {
    'invalid-email': 'Please enter a valid email address',
    'user-not-found': 'No account found with this email',
    'wrong-password': 'Wrong password',
    'invalid-credential': 'Email or password is incorrect',
    'email-already-in-use': 'An account already exists with this email',
    'weak-password': 'Password must be at least 6 characters',
    'operation-not-allowed': 'This sign-in method is disabled',
    'too-many-requests': 'Too many attempts — try again later',
    'network-request-failed': 'No internet connection',
    'invalid-phone-number': 'Please enter a valid phone number (e.g. 01XXXXXXXXX)',
    'invalid-verification-code': 'Wrong OTP code',
    'invalid-verification-id': 'Verification expired — resend the OTP',
    'code-expired': 'OTP expired — resend it',
    'quota-exceeded': 'SMS quota exceeded — try again later',
    'user-disabled': 'This account has been disabled',
    'account-exists-with-different-credential':
        'An account already exists with this email using another sign-in method',
    'google-failed': 'Google sign-in failed, please try again',
    'unknown': 'Something went wrong — please try again',
  };

  String message(String lang) {
    final table = lang == 'bn' ? _bn : _en;
    return table[code] ?? table['unknown']!;
  }

  @override
  String toString() => 'AuthException($code)';
}

/// Central Firebase Authentication helper (singleton).
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _googleInitialized = false;

  /// Emits the current user (null when signed out).
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  /// google_sign_in v7: `initialize()` must be called exactly once before
  /// any other call. Memoized so it is safe to call repeatedly.
  Future<void> _ensureGoogleInitialized() async {
    if (_googleInitialized) return;
    await GoogleSignIn.instance.initialize();
    _googleInitialized = true;
  }

  Never _wrap(FirebaseAuthException e) => throw AuthException(e.code);

  /// Creates an account with email + password.
  Future<UserCredential> signUpWithEmail({
    required String email,
    required String password,
    String? name,
  }) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final displayName = name?.trim();
      if (displayName != null && displayName.isNotEmpty) {
        await cred.user?.updateDisplayName(displayName);
      }
      return cred;
    } on FirebaseAuthException catch (e) {
      _wrap(e);
    }
  }

  /// Signs in with email + password.
  Future<UserCredential> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      return await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      _wrap(e);
    }
  }

  /// Signs in with Google (v7 API: singleton + initialize + authenticate).
  /// Throws [AuthException] with code 'cancelled' when the user dismisses
  /// the picker — callers should ignore that silently.
  Future<UserCredential> signInWithGoogle() async {
    try {
      await _ensureGoogleInitialized();
      final GoogleSignInAccount account =
          await GoogleSignIn.instance.authenticate();
      // v7: idToken is available synchronously; it is all Firebase needs.
      final String? idToken = account.authentication.idToken;
      if (idToken == null) throw const AuthException('google-failed');
      final credential = GoogleAuthProvider.credential(idToken: idToken);
      return await _auth.signInWithCredential(credential);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw const AuthException(AuthException.cancelled);
      }
      throw const AuthException('google-failed');
    } on FirebaseAuthException catch (e) {
      _wrap(e);
    }
  }

  /// Anonymous / guest sign-in — no credentials needed.
  Future<UserCredential> signInAnonymously() async {
    try {
      return await _auth.signInAnonymously();
    } on FirebaseAuthException catch (e) {
      _wrap(e);
    }
  }

  /// Starts phone-number verification. Normalizes Bangladeshi numbers.
  Future<void> startPhoneVerification({
    required String phoneNumber,
    required void Function(String verificationId) onCodeSent,
    void Function()? onAutoVerified,
    void Function(AuthException error)? onFailed,
  }) async {
    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: normalizeBdPhone(phoneNumber),
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential credential) async {
          try {
            await _auth.signInWithCredential(credential);
            onAutoVerified?.call();
          } on FirebaseAuthException catch (e) {
            onFailed?.call(AuthException(e.code));
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          onFailed?.call(AuthException(e.code));
        },
        codeSent: (String verificationId, int? resendToken) {
          onCodeSent(verificationId);
        },
        codeAutoRetrievalTimeout: (String verificationId) {},
      );
    } on FirebaseAuthException catch (e) {
      onFailed?.call(AuthException(e.code));
    }
  }

  /// Confirms the SMS code received via [startPhoneVerification].
  Future<UserCredential> confirmPhoneCode({
    required String verificationId,
    required String smsCode,
  }) async {
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode.trim(),
      );
      return await _auth.signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      _wrap(e);
    }
  }

  /// Signs out from Firebase (and Google, if it was used).
  Future<void> signOut() async {
    if (_googleInitialized) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {
        // Best effort — Firebase sign-out below is what matters.
      }
    }
    await _auth.signOut();
  }

  /// Normalizes a Bangladeshi phone number to E.164 (+880...).
  static String normalizeBdPhone(String input) {
    final d = input.replaceAll(RegExp(r'[\s\-()]'), '');
    if (d.startsWith('+')) return d;
    if (d.startsWith('880')) return '+$d';
    if (d.startsWith('0')) return '+880${d.substring(1)}';
    return '+880$d';
  }
}
