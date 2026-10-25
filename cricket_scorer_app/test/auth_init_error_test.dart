// Firebase init failures must be diagnosable, not silent.
// Regression coverage for the v1.4.x login failure: Firebase.initializeApp()
// threw on the device, AuthService.init() swallowed the exception, and every
// login tap was guard-blocked with the generic "not set up yet" banner.
// Now init() keeps the reason and _guard() surfaces it.
import 'package:cricket_scorer_app/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('before init runs, the guard keeps the generic offline banner',
      () async {
    SharedPreferences.setMockInitialValues({});
    final auth = AuthService();
    expect(auth.initError, isNull);
    final result = await auth.signInWithEmail('x@example.com', 'password');
    expect(result.status, AuthStatus.unavailable);
    expect(result.message,
        'Cloud account is not set up yet. The app works fully offline.');
  });

  test('a failed Firebase init is captured, not swallowed', () async {
    SharedPreferences.setMockInitialValues({});
    final auth = AuthService();
    // No Firebase platform channel in tests, so initializeApp() throws
    // and init() must fall back to offline mode without throwing.
    await auth.init();
    expect(auth.firebaseReady, isFalse);
    expect(auth.initDone, isTrue);
    expect(auth.initError, isNotNull);
    expect(auth.initError, isNotEmpty);
  });

  test('after a failed init, a login tap shows the real reason', () async {
    SharedPreferences.setMockInitialValues({});
    final auth = AuthService();
    await auth.init();
    expect(auth.initError, isNotNull);
    final result = await auth.signInWithEmail('x@example.com', 'password');
    expect(result.status, AuthStatus.unavailable);
    expect(result.message, startsWith('Cloud setup failed: '));
    expect(result.message, isNot(equals(
        'Cloud account is not set up yet. The app works fully offline.')));
  });
}
