// 60Score account login — Ocean theme.
// Three methods: Email/password, Google, Phone OTP.
// Login is OPTIONAL: the app works fully offline; an account enables
// cross-device data sync.
import 'package:flutter/material.dart';

import '../auth_service.dart';
import '../store.dart';
import '../sync_service.dart';
import '../theme.dart';

class LoginScreen extends StatefulWidget {
  final Store? store;

  /// Gate mode: the screen is shown right after the splash when nobody
  /// is logged in. There is no route to pop — [onGatePassed] fires when
  /// the user logs in OR taps "Continue as Guest".
  final bool gateMode;
  final VoidCallback? onGatePassed;

  const LoginScreen({
    super.key,
    this.store,
    this.gateMode = false,
    this.onGatePassed,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _auth = AuthService();

  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();

  bool _isSignUp = false;
  bool _busy = false;
  String? _error;
  String? _verificationId;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  Future<void> _run(Future<AuthResult> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.status == AuthStatus.ok) {
      // Pull cloud data after a successful login (last-write-wins).
      final store = widget.store;
      if (store != null) {
        await SyncService().pull(store);
      }
      if (!mounted) return;
      final gatePassed = widget.onGatePassed;
      if (gatePassed != null) {
        gatePassed();
      } else {
        Navigator.pop(context, true);
      }
    } else {
      setState(() => _error = result.message ?? 'Something went wrong.');
    }
  }

  Future<void> _continueAsGuest() async {
    // Remembered on-device: a returning guest skips the gate.
    await _auth.setGuestMode();
    if (!mounted) return;
    final gatePassed = widget.onGatePassed;
    if (gatePassed != null) {
      gatePassed();
    } else {
      Navigator.pop(context, false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kOceanBlack,
      appBar: AppBar(
        backgroundColor: kOceanBlack,
        foregroundColor: kWhite,
        elevation: 0,
        automaticallyImplyLeading: !widget.gateMode,
        title: const Text('Account',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [kOceanBlack, kSunsetNavyDeep],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 8),
              // Logo header
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: kSunsetGradient,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: kSunsetOrange.withValues(alpha: 0.4),
                      blurRadius: 24,
                    ),
                  ],
                ),
                child: const Icon(Icons.sports_cricket,
                    color: kWhite, size: 40),
              ),
              const SizedBox(height: 12),
              const Text(
                'Sync across devices',
                style: TextStyle(
                    color: kWhite,
                    fontSize: 20,
                    fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              const Text(
                'Log in to keep your data in sync\non all your devices.',
                textAlign: TextAlign.center,
                style: TextStyle(color: kOceanFaint, fontSize: 13),
              ),
              const SizedBox(height: 16),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: kOceanDeep,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: kOceanSteel.withValues(alpha: 0.4)),
                ),
                child: TabBar(
                  controller: _tabs,
                  // v1.2.2: without this the M3 default sizes the pill
                  // to the label, rendering a small oval behind the
                  // text instead of a full tab-segment highlight.
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicator: BoxDecoration(
                    gradient: kSunsetGradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  indicatorPadding: const EdgeInsets.all(4),
                  labelColor: kWhite,
                  unselectedLabelColor: kOceanFaint,
                  labelStyle: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 13),
                  tabs: const [
                    Tab(text: 'Email'),
                    Tab(text: 'Google'),
                    Tab(text: 'Phone'),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    _emailTab(),
                    _googleTab(),
                    _phoneTab(),
                  ],
                ),
              ),
              if (widget.gateMode) _guestBar(),
            ],
          ),
        ),
      ),
    );
  }

  /// Gate-only footer: guests skip login and use the app offline with
  /// local data (cloud sync stays login-only; public tournament
  /// search still works).
  Widget _guestBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                  child: Divider(
                      color: kOceanSteel.withValues(alpha: 0.4))),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Text('or',
                    style:
                        TextStyle(color: kOceanFaint, fontSize: 12)),
              ),
              Expanded(
                  child: Divider(
                      color: kOceanSteel.withValues(alpha: 0.4))),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _continueAsGuest,
              icon: const Icon(Icons.person_outline, size: 19),
              label: const Text('Continue as Guest'),
              style: OutlinedButton.styleFrom(
                foregroundColor: kWhite,
                side: BorderSide(
                    color: kOceanSteel.withValues(alpha: 0.7)),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 14),
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Guests keep data on this device only.',
            style: TextStyle(color: kOceanFaint, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _card(Widget child) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: kOceanCardGradient,
          borderRadius: BorderRadius.circular(20),
          border:
              Border.all(color: kOceanSteel.withValues(alpha: 0.4)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: child,
      ),
    );
  }

  Widget _errorBox() {
    if (_error == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kRed.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kRed.withValues(alpha: 0.4)),
      ),
      child: Text(_error!,
          style: const TextStyle(color: kRed, fontSize: 13)),
    );
  }

  Widget _primaryButton(String label, VoidCallback? onTap) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _busy ? null : onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 15),
            decoration: BoxDecoration(
              gradient: kSunsetGradient,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: kSunsetOrange.withValues(alpha: 0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Center(
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: kWhite, strokeWidth: 2))
                  : Text(label,
                      style: const TextStyle(
                          color: kWhite,
                          fontWeight: FontWeight.w800,
                          fontSize: 15)),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _field(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, color: kOceanFaint, size: 20),
      filled: true,
      fillColor: kOceanBlack.withValues(alpha: 0.5),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
            color: kOceanSteel.withValues(alpha: 0.4)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
            color: kOceanSteel.withValues(alpha: 0.4)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide:
            const BorderSide(color: kSunsetOrange, width: 1.5),
      ),
    );
  }

  // ---------- Email tab ----------

  Widget _emailTab() {
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _errorBox(),
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            style: const TextStyle(color: kWhite),
            decoration: _field('Email address', Icons.email_outlined),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passCtrl,
            obscureText: true,
            style: const TextStyle(color: kWhite),
            decoration: _field('Password', Icons.lock_outline),
          ),
          const SizedBox(height: 16),
          _primaryButton(
              _isSignUp ? 'Create Account' : 'Log In',
              () => _run(() => _isSignUp
                  ? _auth.signUpWithEmail(
                      _emailCtrl.text, _passCtrl.text)
                  : _auth.signInWithEmail(
                      _emailCtrl.text, _passCtrl.text))),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() => _isSignUp = !_isSignUp),
            child: Text(
              _isSignUp
                  ? 'Already have an account? Log in'
                  : "Don't have an account? Sign up",
              style: const TextStyle(color: kSunsetOrangeSoft),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- Google tab ----------

  Widget _googleTab() {
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _errorBox(),
          const Icon(Icons.account_circle,
              color: kOceanFaint, size: 56),
          const SizedBox(height: 12),
          const Text(
            'One tap with your Google account.\nFast and secure.',
            textAlign: TextAlign.center,
            style: TextStyle(color: kOceanFaint, fontSize: 13),
          ),
          const SizedBox(height: 16),
          _primaryButton('Continue with Google',
              () => _run(() => _auth.signInWithGoogle())),
        ],
      ),
    );
  }

  // ---------- Phone tab ----------

  Widget _phoneTab() {
    final codeSent = _verificationId != null;
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _errorBox(),
          if (!codeSent) ...[
            TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              style: const TextStyle(color: kWhite),
              decoration:
                  _field('+92 3XX XXXXXXX', Icons.phone_outlined),
            ),
            const SizedBox(height: 16),
            _primaryButton(
                'Send SMS Code',
                () => _run(() async {
                      final r = await _auth.startPhoneVerification(
                        _phoneCtrl.text,
                        onCodeSent: (vid) =>
                            setState(() => _verificationId = vid),
                        onFailed: (msg) =>
                            setState(() => _error = msg),
                      );
                      return r;
                    })),
          ] else ...[
            const Text(
              'Enter the 6-digit code sent to your phone.',
              style: TextStyle(color: kOceanFaint, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _otpCtrl,
              keyboardType: TextInputType.number,
              maxLength: 6,
              style: const TextStyle(
                  color: kWhite,
                  fontSize: 22,
                  letterSpacing: 8,
                  fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
              decoration: _field('------', Icons.sms_outlined),
            ),
            const SizedBox(height: 16),
            _primaryButton(
                'Verify & Log In',
                () => _run(() => _auth.confirmPhoneCode(
                    _verificationId!, _otpCtrl.text))),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                        _verificationId = null;
                        _otpCtrl.clear();
                      }),
              child: const Text('Use a different number',
                  style: TextStyle(color: kSunsetOrangeSoft)),
            ),
          ],
        ],
      ),
    );
  }
}
