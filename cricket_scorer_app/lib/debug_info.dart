// Debug info (v1.4.3): captures the latest app error so a crash can
// be reported with facts instead of guesswork. The latest error is
// kept in memory and persisted lightly (two small prefs keys) so it
// survives a restart and shows on the debug screen.
//
// Error behavior is NOT changed: framework errors are still
// presented as usual, and uncaught async errors still return false
// (unhandled), so the platform treats them exactly as before —
// only now the cause is recorded first.
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Must match pubspec.yaml's version — bump this in the SAME change
/// whenever pubspec.yaml's version changes, or the Debug info screen
/// will report a stale version. This bit us in 1.4.4: the screen
/// showed 1.4.3+26 while 1.4.4+27 was running, which made a real
/// 1.4.4 crash look like a 1.4.3 crash. No version plugin is used
/// on purpose: adding a native plugin changes the Firebase
/// registrar set, which broke login in v1.4.0.
const String kAppVersion = '1.4.7+30';

class DebugInfo {
  static const _prefsKey = 'debug_last_error_v1';
  static const _maxChars = 2000;

  static String? lastError;
  static DateTime? lastErrorAt;

  static void record(Object error, [StackTrace? stack]) {
    final text = stack == null ? '$error' : '$error\n$stack';
    lastError =
        text.length > _maxChars ? text.substring(0, _maxChars) : text;
    lastErrorAt = DateTime.now();
    unawaited(_persist());
  }

  static Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, lastError ?? '');
      final at = lastErrorAt;
      if (at != null) {
        await prefs.setInt('${_prefsKey}_at', at.millisecondsSinceEpoch);
      }
    } catch (_) {
      // Debug recording must never break the app itself.
    }
  }

  /// Loads the persisted error from a previous launch, but only
  /// when this launch has not recorded one yet (a live error wins).
  static Future<void> loadPersisted() async {
    if (lastError != null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final text = prefs.getString(_prefsKey);
      final at = prefs.getInt('${_prefsKey}_at');
      if (text != null && text.isNotEmpty) {
        lastError = text;
        lastErrorAt =
            at == null ? null : DateTime.fromMillisecondsSinceEpoch(at);
      }
    } catch (_) {
      // See _persist.
    }
  }

  static void installHooks() {
    FlutterError.onError = (details) {
      record(details.exception, details.stack);
      FlutterError.presentError(details);
    };
    ui.PlatformDispatcher.instance.onError = (error, stack) {
      record(error, stack);
      return false;
    };
  }
}
