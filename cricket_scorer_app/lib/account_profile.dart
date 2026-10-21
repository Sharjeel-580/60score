// Per-account profile for 60Score (v1.3.1 batch, feature #3).
// Every signed-in account gets its own profile: a display name, the
// account contact (email or phone) and a UNIQUE user code. The code is
// derived deterministically from the Firebase uid, so it is stable on
// every device without any server round-trip or extra Firestore path —
// the profile itself lives inside the account's own scoped data and
// rides the normal backup sync (users/{uid}/backup/app_data).
import 'scoring.dart';
import 'store.dart';

/// The app owner's email. Pre-v1.3.1 (unscoped) on-device data may
/// only ever be claimed into THIS account — it is the owner's data;
/// any other account starts with its own empty workspace and the
/// legacy keys stay untouched so the owner can still claim later.
const String kOwnerEmail = 'xharitarar550@gmail.com';

/// Deterministic 6-character user code for [uid], e.g. "60S-K7QX2M".
/// Two FNV-1a passes over the uid give enough spread; the result is
/// rendered in uppercase base36. Same uid → same code, on any device,
/// forever.
String userCodeForUid(String uid) {
  int fnv(String s, int seed) {
    var h = seed;
    for (var i = 0; i < s.length; i++) {
      h ^= s.codeUnitAt(i);
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h;
  }

  final h = fnv(uid, 0x811C9DC5) ^ (fnv(uid, 0x9E3779B9) << 1);
  const space = 2176782336; // 36^6
  var v = h % space;
  const digits = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  final buf = StringBuffer();
  for (var i = 0; i < 6; i++) {
    buf.write(digits[v % 36]);
    v ~/= 36;
  }
  return '60S-${buf.toString()}';
}

/// One account's profile, stored in that account's own data scope.
class AccountProfile {
  final String uid;
  String displayName;

  /// Email address, or phone number for phone-OTP accounts.
  String contact;
  final String userCode;

  AccountProfile({
    required this.uid,
    required this.displayName,
    required this.contact,
    required this.userCode,
  });

  factory AccountProfile.create({
    required String uid,
    String? displayName,
    String? contact,
  }) {
    return AccountProfile(
      uid: uid,
      displayName: defaultProfileName(displayName, contact),
      contact: contact ?? '',
      userCode: userCodeForUid(uid),
    );
  }

  /// Name fallback chain: the auth display name, else the email
  /// prefix, else a neutral 'Player'.
  static String defaultProfileName(String? displayName, String? contact) {
    if (displayName != null && displayName.trim().isNotEmpty) {
      return displayName.trim();
    }
    if (contact != null && contact.contains('@')) {
      final prefix = contact.split('@').first.trim();
      if (prefix.isNotEmpty) return prefix;
    }
    return 'Player';
  }

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'displayName': displayName,
        'contact': contact,
        'userCode': userCode,
      };

  factory AccountProfile.fromJson(Map<String, dynamic> j) => AccountProfile(
        uid: j['uid'] as String? ?? '',
        displayName: j['displayName'] as String? ?? 'Player',
        contact: j['contact'] as String? ?? '',
        userCode: j['userCode'] as String? ?? '',
      );
}

/// "My Stats" totals for the profile screen — computed ONLY from the
/// currently active identity's own store data. Runs/wickets come from
/// the shared career engine (completed matches), never re-implemented.
class AccountTotals {
  final int tournaments;
  final int matches;
  final int teams;
  final int players;
  final int totalRuns;
  final int totalWickets;

  const AccountTotals({
    required this.tournaments,
    required this.matches,
    required this.teams,
    required this.players,
    required this.totalRuns,
    required this.totalWickets,
  });

  static AccountTotals fromStore(Store store) {
    final playerIds = <String>{
      for (final t in store.teams)
        for (final p in t.players) p.id,
      for (final r in store.regPlayers) r.id,
    };
    var runs = 0;
    var wickets = 0;
    for (final c in computeCareerStats(store.matches).values) {
      runs += c.runs;
      wickets += c.wickets;
    }
    return AccountTotals(
      tournaments: store.tournaments.length,
      matches: store.matches.length,
      teams: store.teams.length,
      players: playerIds.length,
      totalRuns: runs,
      totalWickets: wickets,
    );
  }
}
