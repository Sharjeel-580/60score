// 60Score account service — login + cloud sync.
// Supports: Email/password, Google Sign-In, Phone OTP (all via Firebase Auth).
// The app is offline-first: everything works without login. Logging in
// enables cross-device data sync via Cloud Firestore.
//
// SETUP (one-time, by the app owner):
//   1. Create a Firebase project at console.firebase.google.com
//   2. Add an Android app (package: com.example.cricket_scorer_app — update
//      to the real applicationId) and download google-services.json
//   3. Place google-services.json in android/app/
//   4. In Firebase console > Authentication > Sign-in method, enable:
//      Email/Password, Google, and Phone.
// Until google-services.json is present, this service stays in offline mode
// and every method reports [AuthUnavailable].
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Result of an auth attempt.
enum AuthStatus {
  ok,
  /// Firebase is not configured (no google-services.json) — offline mode.
  unavailable,
  /// Wrong credentials / invalid code.
  invalidCredentials,
  /// Any other failure (network, etc.).
  failed,
}

class AuthResult {
  final AuthStatus status;
  final String? message;
  const AuthResult(this.status, [this.message]);
}

class AuthService extends ChangeNotifier {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  bool _firebaseReady = false;
  bool get firebaseReady => _firebaseReady;

  User? get currentUser =>
      _firebaseReady ? FirebaseAuth.instance.currentUser : null;
  bool get isLoggedIn => currentUser != null;
  String get displayName =>
      currentUser?.displayName ?? currentUser?.email ?? currentUser?.phoneNumber ?? '';

  /// Call once at startup. Never throws — falls back to offline mode.
  Future<void> init() async {
    try {
      await Firebase.initializeApp();
      _firebaseReady = true;
      FirebaseAuth.instance.authStateChanges().listen((_) {
        notifyListeners();
      });
    } catch (_) {
      // No google-services.json (or other init failure): stay offline.
      _firebaseReady = false;
    }
    notifyListeners();
  }

  AuthResult _guard() {
    if (!_firebaseReady) {
      return const AuthResult(AuthStatus.unavailable,
          'Cloud account is not set up yet. The app works fully offline.');
    }
    return const AuthResult(AuthStatus.ok);
  }

  // ---------- Email / password ----------

  Future<AuthResult> signInWithEmail(String email, String password) async {
    final g = _guard();
    if (g.status != AuthStatus.ok) return g;
    try {
      await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email.trim(), password: password);
      notifyListeners();
      return const AuthResult(AuthStatus.ok);
    } on FirebaseAuthException catch (e) {
      return AuthResult(AuthStatus.invalidCredentials, _friendly(e));
    } catch (e) {
      return AuthResult(AuthStatus.failed, e.toString());
    }
  }

  Future<AuthResult> signUpWithEmail(String email, String password) async {
    final g = _guard();
    if (g.status != AuthStatus.ok) return g;
    try {
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email.trim(), password: password);
      notifyListeners();
      return const AuthResult(AuthStatus.ok);
    } on FirebaseAuthException catch (e) {
      return AuthResult(AuthStatus.invalidCredentials, _friendly(e));
    } catch (e) {
      return AuthResult(AuthStatus.failed, e.toString());
    }
  }

  // ---------- Google ----------

  Future<AuthResult> signInWithGoogle() async {
    final g = _guard();
    if (g.status != AuthStatus.ok) return g;
    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        return const AuthResult(
            AuthStatus.failed, 'Google sign-in was cancelled.');
      }
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await FirebaseAuth.instance.signInWithCredential(credential);
      notifyListeners();
      return const AuthResult(AuthStatus.ok);
    } on FirebaseAuthException catch (e) {
      return AuthResult(AuthStatus.failed, _friendly(e));
    } catch (e) {
      return AuthResult(AuthStatus.failed, e.toString());
    }
  }

  // ---------- Phone OTP ----------

  /// Starts phone verification. [onCodeSent] receives the verificationId
  /// to keep while the user types the SMS code.
  Future<AuthResult> startPhoneVerification(
    String phoneNumber, {
    required void Function(String verificationId) onCodeSent,
    void Function(String message)? onFailed,
  }) async {
    final g = _guard();
    if (g.status != AuthStatus.ok) return g;
    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phoneNumber.trim(),
        verificationCompleted: (credential) async {
          await FirebaseAuth.instance.signInWithCredential(credential);
          notifyListeners();
        },
        verificationFailed: (e) {
          onFailed?.call(_friendly(e));
        },
        codeSent: (verificationId, _) => onCodeSent(verificationId),
        codeAutoRetrievalTimeout: (_) {},
        timeout: const Duration(seconds: 60),
      );
      return const AuthResult(AuthStatus.ok);
    } catch (e) {
      return AuthResult(AuthStatus.failed, e.toString());
    }
  }

  Future<AuthResult> confirmPhoneCode(
      String verificationId, String smsCode) async {
    final g = _guard();
    if (g.status != AuthStatus.ok) return g;
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode.trim(),
      );
      await FirebaseAuth.instance.signInWithCredential(credential);
      notifyListeners();
      return const AuthResult(AuthStatus.ok);
    } on FirebaseAuthException catch (e) {
      return AuthResult(AuthStatus.invalidCredentials, _friendly(e));
    } catch (e) {
      return AuthResult(AuthStatus.failed, e.toString());
    }
  }

  // ---------- Sign out ----------

  Future<void> signOut() async {
    if (!_firebaseReady) return;
    try {
      await GoogleSignIn().signOut();
    } catch (_) {}
    await FirebaseAuth.instance.signOut();
    notifyListeners();
  }

  String _friendly(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'Email address is not valid.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Wrong email or password.';
      case 'email-already-in-use':
        return 'This email is already registered. Try logging in.';
      case 'weak-password':
        return 'Password is too weak (min 6 characters).';
      case 'invalid-verification-code':
        return 'Wrong SMS code. Try again.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait and try again.';
      case 'network-request-failed':
        return 'No internet connection.';
      default:
        return e.message ?? 'Something went wrong.';
    }
  }
}
