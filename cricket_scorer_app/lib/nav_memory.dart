// Navigation memory (v1.4.5, Recents resume): the last inner screen
// the user was on, so a cold start after the OS killed the process
// can restore it instead of landing on a blank home.
//
// Why this is the fix: the manifest is already correct
// (singleTop, full configChanges), and pushed routes already pop
// normally — so rotation/config changes are NOT the cause. The
// Recents symptom is an OS-killed process → cold start → home,
// because nothing remembered where the user was. This memory is
// stored in plain SharedPreferences (NOT the store's
// identity-scoped keys): it is per-device, and restore only happens
// when the referenced record still exists in the loaded store, so a
// deleted match/tournament safely falls back to home. Every method
// swallows errors — nav memory must never break boot.
//
// Lifecycle contract: each inner screen saves on entry and clears
// on dispose, but ONLY when the saved record is its own (kind+id
// match). That guard matters for pushReplacement (scoring →
// scorecard): the new screen saves first, then the old screen's
// dispose runs — without the guard it would wipe the new record.
import 'package:shared_preferences/shared_preferences.dart';

/// One saved destination: [kind] is 'scoring', 'scorecard',
/// 'tournament' or 'fixture'; [id] is the match id (scoring,
/// scorecard, fixture) or the tournament id.
class NavRestore {
  final String kind;
  final String id;
  const NavRestore(this.kind, this.id);
}

class NavMemory {
  static const _kKey = 'score60_last_route_v1';
  static const _kinds = {'scoring', 'scorecard', 'tournament', 'fixture'};

  static Future<void> save(String kind, String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kKey, '$kind|$id');
    } catch (_) {}
  }

  static Future<void> clear(String kind, String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_kKey) == '$kind|$id') {
        await prefs.remove(_kKey);
      }
    } catch (_) {}
  }

  static Future<NavRestore?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kKey);
      if (raw == null) return null;
      final sep = raw.indexOf('|');
      if (sep <= 0) return null;
      final kind = raw.substring(0, sep);
      final id = raw.substring(sep + 1);
      if (id.isEmpty || !_kinds.contains(kind)) return null;
      return NavRestore(kind, id);
    } catch (_) {
      return null;
    }
  }
}
