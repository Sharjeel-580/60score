// Voice commentary (TTS) service + pure spoken-phrase builders.
//
// The phrase builders at the top are pure top-level functions with
// no TTS dependency, so they are fully unit-testable and the
// scoring UI can preview exactly what would be spoken. The
// [TtsService] class below them wraps flutter_tts; every call is
// guarded so a TTS failure can never break scoring, and speech is
// OFF by default (the user opts in from settings).

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Pure phrase builders
// ---------------------------------------------------------------------------

String _ballWord(int n) => n == 1 ? 'ball' : 'balls';
String _runWord(int n) => n == 1 ? 'run' : 'runs';

/// Over label for speech: "6.0" → "6", "6.3" stays "6.3",
/// "6" stays "6".
String _overLabel(String oversText) {
  final t = oversText.trim();
  if (t.endsWith('.0')) return t.substring(0, t.length - 2);
  return t;
}

/// End-of-over summary, e.g. "End of over 6. Dolphins 85 for 3."
///
/// When [target] is set (a chase), chase context is appended when
/// the balls information is available: "Need 34 off 12 balls."
/// (from target − runs and [ballsTotal] − [ballsBowled]). With a
/// target but no balls information it appends "Need 34 runs to
/// win."; once the target is reached it appends "Target reached."
/// [inningsNo] is accepted for call-site context (the UI knows
/// which innings it is summarising); it does not change the phrase.
String ttsOverSummary({
  required String teamName,
  required int runs,
  required int wickets,
  required String oversText,
  int? target,
  int? inningsNo,
  int? ballsBowled,
  int? ballsTotal,
}) {
  final buf = StringBuffer(
    'End of over ${_overLabel(oversText)}. $teamName $runs for $wickets.',
  );
  if (target != null) {
    final need = target - runs;
    if (need <= 0) {
      buf.write(' Target reached.');
    } else if (ballsBowled != null && ballsTotal != null) {
      final ballsLeft = ballsTotal - ballsBowled;
      if (ballsLeft > 0) {
        buf.write(' Need $need off $ballsLeft ${_ballWord(ballsLeft)}.');
      } else {
        buf.write(' Need $need ${_runWord(need)} to win.');
      }
    } else {
      buf.write(' Need $need ${_runWord(need)} to win.');
    }
  }
  return buf.toString();
}

/// Wicket announcement, e.g.
/// "Wicket! Ahmed out. Dolphins 85 for 3."
String ttsWicket({
  required String batsmanName,
  required String teamName,
  required int runs,
  required int wickets,
}) {
  return 'Wicket! $batsmanName out. $teamName $runs for $wickets.';
}

/// Milestone announcement. The caller decides when a milestone has
/// been reached; the wording follows the score: 100 or more reads
/// as a "Hundred for …!" announcement, 50 or more as "Fifty
/// for …!", and anything lower falls back to a "reaches" phrase.
String ttsMilestone({required String batsmanName, required int runs}) {
  if (runs >= 100) return 'Hundred for $batsmanName!';
  if (runs >= 50) return 'Fifty for $batsmanName!';
  return '$batsmanName reaches $runs.';
}

// ---------------------------------------------------------------------------
// TTS service
// ---------------------------------------------------------------------------

/// SharedPreferences key for the voice-commentary opt-in.
const String kTtsEnabledPrefsKey = 'score60_tts_enabled';

/// Thin, failure-proof wrapper around FlutterTts.
///
/// * Disabled by default; [enabled] is backed by SharedPreferences
///   (key [kTtsEnabledPrefsKey]) via [loadEnabled] / [setEnabled].
/// * [speak] is a no-op while disabled and swallows every error —
///   scoring must never break because speech failed.
/// * The engine is initialised lazily on first speech, with
///   language 'en-US' and speech rate 0.95.
class TtsService {
  /// Shared singleton for the app.
  static final TtsService instance = TtsService._();

  /// Plain constructor (tests / a second isolated instance).
  TtsService();

  TtsService._();

  FlutterTts? _tts;
  bool _initialised = false;

  /// Whether voice commentary is on. Defaults to false until
  /// [loadEnabled] reads the persisted preference.
  bool enabled = false;

  /// Read the persisted opt-in into [enabled]. Never throws.
  Future<void> loadEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      enabled = prefs.getBool(kTtsEnabledPrefsKey) ?? false;
    } catch (e) {
      debugPrint('TtsService.loadEnabled failed: $e');
      enabled = false;
    }
  }

  /// Persist the opt-in; disabling also stops any current speech.
  /// Never throws.
  Future<void> setEnabled(bool value) async {
    enabled = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kTtsEnabledPrefsKey, value);
    } catch (e) {
      debugPrint('TtsService.setEnabled failed: $e');
    }
    if (!value) await stop();
  }

  Future<void> _ensureInitialised() async {
    if (_initialised) return;
    final tts = _tts ??= FlutterTts();
    try {
      await tts.setLanguage('en-US');
    } catch (_) {
      // Language may be unavailable on-device; speech can still
      // proceed with the platform default voice.
    }
    try {
      await tts.setSpeechRate(0.95);
    } catch (_) {}
    try {
      await tts.setPitch(1.0);
    } catch (_) {}
    _initialised = true;
  }

  /// Speak [text] if enabled. No-op when disabled or for blank
  /// text. All errors are swallowed.
  Future<void> speak(String text) async {
    if (!enabled) return;
    if (text.trim().isEmpty) return;
    try {
      await _ensureInitialised();
      await _tts?.speak(text);
    } catch (e) {
      debugPrint('TtsService.speak failed: $e');
    }
  }

  /// Stop any current speech. Never throws.
  Future<void> stop() async {
    try {
      await _tts?.stop();
    } catch (e) {
      debugPrint('TtsService.stop failed: $e');
    }
  }
}
