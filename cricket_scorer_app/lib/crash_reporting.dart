// Crash reporting (v1.4.0 batch): forwards Flutter framework errors
// and uncaught async errors to Firebase Crashlytics, so a future
// crash — including a launch-time crash — carries a stack trace
// instead of only a system crash count with no reason attached.
//
// Never throws and never blocks startup: when Firebase is not
// configured (offline mode, no google-services.json) this is a
// silent no-op, exactly like the rest of the Firebase layer.
import 'dart:ui' as ui;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

bool _wired = false;

/// Call once, after Firebase.initializeApp() has succeeded.
Future<void> initCrashReporting() async {
  if (_wired) return;
  try {
    if (Firebase.apps.isEmpty) return;
    final crashlytics = FirebaseCrashlytics.instance;
    FlutterError.onError = (details) {
      try {
        crashlytics.recordFlutterError(details);
      } catch (_) {
        // Reporting must never crash the app it reports on.
      }
    };
    ui.PlatformDispatcher.instance.onError = (error, stack) {
      try {
        crashlytics.recordError(error, stack, fatal: true);
      } catch (_) {}
      return true;
    };
    _wired = true;
  } catch (_) {
    // Offline / unconfigured: stay silent, stay offline.
  }
}
