// SharedPreferences repository for 60Score.
// Data is stored on the phone, scoped per identity (v1.3.1): the
// signed-in account's uid, or 'guest'. A guest or a different account
// on the same phone NEVER sees — or edits — another identity's data;
// logging out hides the account's data until that same account logs
// back in. Cloud sync (per account) lives in sync_service.dart.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'account_profile.dart';
import 'draft.dart';
import 'entity_sync.dart';
import 'models.dart';
import 'publish_service.dart';
import 'sync_service.dart';
import 'tournament_engine.dart';

/// One soft-deleted record kept in Trash (Feature 1 — Trash +
/// Restore). [payload] is the entity's full `toJson()` map captured
/// BEFORE removal, so a restore can rebuild the record exactly as
/// it was (innings, players, settings — everything).
///
/// Only matches, teams and tournaments are trashed (the kinds in
/// scope for this feature). Records deleted BEFORE this feature
/// existed have no snapshot and cannot be restored — they simply
/// never appear in Trash.
class TrashEntry {
  /// Entity kind — one of the [EntityKind] values
  /// (`matches` / `teams` / `tournaments`).
  final String kind;
  final String id;

  /// Display label captured at delete time: a team's / tournament's
  /// name, or for a match its title when set, else "Team A vs Team B".
  final String name;

  /// Wall-clock ms when the record was deleted.
  final int deletedAt;

  /// The entity's full `toJson()` map.
  final Map<String, dynamic> payload;

  const TrashEntry({
    required this.kind,
    required this.id,
    required this.name,
    required this.deletedAt,
    required this.payload,
  });

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'id': id,
        'name': name,
        'deletedAt': deletedAt,
        'payload': payload,
      };

  factory TrashEntry.fromJson(Map<String, dynamic> j) => TrashEntry(
        kind: j['kind'] as String? ?? '',
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        deletedAt: (j['deletedAt'] as num?)?.toInt() ?? 0,
        payload: ((j['payload'] as Map?) ?? const {})
            .cast<String, dynamic>(),
      );
}

class Store extends ChangeNotifier implements PlayoffStore {
  List<Team> teams = [];
  List<Tournament> tournaments = [];
  @override
  List<Match> matches = [];
  List<RegPlayer> regPlayers = [];
  List<Draft> drafts = [];
  List<ManualStatEntry> manualStats = [];

  /// Deletion tombstones (Sync Fix "D", Phase C0): every delete*
  /// records one; sync carries them to the cloud so a deleted
  /// record is never resurrected by a stale copy held elsewhere
  /// (the 2026-10-23 delete-resurrection defect — see
  /// lib/entity_sync.dart and SYNC_FIX_D_PLAN.md §4). An explicit
  /// re-add of the same id (upsert / backup restore) clears the
  /// tombstone again: that is the admin-restore path.
  List<Tombstone> tombstones = [];

  /// Soft-delete snapshots (Feature 1 — Trash + Restore), scoped
  /// per identity exactly like [tombstones]. A delete of a match,
  /// team or tournament snapshots the record here BEFORE removal;
  /// restoring re-inserts it through the normal upsert path (which
  /// clears its tombstone — the admin-restore path above), and a
  /// permanent delete drops only the snapshot, leaving the
  /// tombstone in place so the record stays deleted everywhere.
  /// Records deleted before this feature have no snapshot and
  /// cannot be restored (they never appear here).
  List<TrashEntry> _trash = [];

  /// Restored-record markers (Feature 1 follow-up, D batch): when a
  /// record is explicitly restored (Trash restore, or a backup
  /// import) its local tombstone is cleared by the upsert — but the
  /// CLOUD may still hold that tombstone, and the sync merge kills
  /// any record whose tombstone it cannot out-rank. So a restore
  /// also remembers the tombstone's `deletedAt` here (key
  /// `'<kind>|<id>'`), and StoreEntityDocStore.readAll emits the
  /// record with `restored: true` and its stamp floored above this
  /// value until a sync round spends the cloud tombstone (the
  /// coordinator clears the marker at that moment). A fresh delete
  /// of the same record drops the marker again.
  Map<String, int> _restoredMarkers = {};

  /// The tombstone `deletedAt` a restored record must out-rank in
  /// the entity sync, or null when the record was not restored
  /// against a tombstone.
  int? restoredMarkerFor(String kind, String id) =>
      _restoredMarkers['$kind|$id'];

  /// Drops the restored marker for one record (the sync round has
  /// spent its tombstone, or the record was deleted again).
  void clearRestoredMarker(String kind, String id) {
    _restoredMarkers.remove('$kind|$id');
  }

  /// All (kind, id) pairs currently carrying a restored marker —
  /// the sync coordinator reconciles these after every round.
  List<(String, String)> get restoredMarkerRecords => [
        for (final key in _restoredMarkers.keys)
          if (key.contains('|'))
            (
              key.substring(0, key.indexOf('|')),
              key.substring(key.indexOf('|') + 1),
            ),
      ];

  /// Trash entries, newest first.
  List<TrashEntry> get trashEntries {
    final sorted = List<TrashEntry>.of(_trash)
      ..sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
    return List.unmodifiable(sorted);
  }

  /// This identity's account profile (feature #3) — set for signed-in
  /// accounts, always null for guests / the locked scope.
  AccountProfile? profile;
  bool welcomeDone = false;
  bool loaded = false;

  static const _kTeams = 'cricscore_teams_v1';
  static const _kTournaments = 'cricscore_tournaments_v1';
  static const _kMatches = 'cricscore_matches_v1';
  // Version stamped into exports/backups.
  static const _kSchemaVersion = 2;
  static const _kReg = 'score60_regplayers_v1';
  static const _kDrafts = 'score60_drafts_v1';
  static const _kManual = 'score60_manualstats_v1';
  static const _kProfile = 'score60_profile_v1';
  static const _kTombstones = 'score60_tombstones_v1';
  static const _kTrash = 'score60_trash_v1';
  static const _kRestored = 'score60_restored_v1';
  static const _kWelcome = 'score60_welcome_v1';
  static const _kLastModified = 'score60_last_modified_v1';

  // Per-identity storage (v1.3.1): the data keys above are BASE names.
  // Values actually live under '<base>__<identityId>', where the
  // identity id is 'guest' or a signed-in account's uid ('locked' is a
  // transient, always-empty scope used right after log-out). The
  // un-suffixed keys are the pre-v1.3.1 legacy location — only the
  // OWNER's account may claim that data (see [claimLegacyData]);
  // guests are never shown it. The welcome flag stays global.
  String _identityId = 'guest';

  /// The identity whose data is currently loaded: 'guest' or a
  /// Firebase uid. Cloud services compare against this so one
  /// identity's data can never be written to another's account.
  String get identityId => _identityId;

  String _scoped(String base) => '${base}__$_identityId';

  static int _counter = 0;
  static String newId(String prefix) {
    _counter++;
    return '${prefix}_${DateTime.now().microsecondsSinceEpoch}_$_counter';
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    // Decode defensively: a corrupt entry keeps the previous in-memory
    // list instead of wiping it (the old code replaced it with [] and
    // the next persist() then overwrote storage with the empty list).
    // A fresh install has nothing saved, so every list simply stays
    // empty — the app ships with ZERO default/seeded content, and data
    // a user saved on this device loads back exactly as it was saved.
    // Only the CURRENT identity's scope is read (see _scoped).
    teams =
        _decodeList(prefs.getString(_scoped(_kTeams)), Team.fromJson) ??
            teams;
    tournaments = _decodeList(
            prefs.getString(_scoped(_kTournaments)), Tournament.fromJson) ??
        tournaments;
    matches =
        _decodeList(prefs.getString(_scoped(_kMatches)), Match.fromJson) ??
            matches;
    regPlayers =
        _decodeList(prefs.getString(_scoped(_kReg)), RegPlayer.fromJson) ??
            regPlayers;
    drafts =
        _decodeList(prefs.getString(_scoped(_kDrafts)), Draft.fromJson) ??
            drafts;
    manualStats = _decodeList(
            prefs.getString(_scoped(_kManual)), ManualStatEntry.fromJson) ??
        manualStats;
    profile = _decodeProfile(prefs.getString(_scoped(_kProfile))) ?? profile;
    tombstones =
        _decodeTombstones(prefs.getString(_scoped(_kTombstones))) ??
            tombstones;
    _trash = _decodeTrash(prefs.getString(_scoped(_kTrash))) ?? _trash;
    _restoredMarkers =
        _decodeRestoredMarkers(prefs.getString(_scoped(_kRestored))) ??
            _restoredMarkers;
    // Load-time consistency (mirrors the tombstone self-heal in
    // [importJson]): a record that exists locally again — e.g. it
    // was restored or re-added by another path — must not also sit
    // in Trash.
    _trash.removeWhere((e) => _recordExistsLocally(e.kind, e.id));
    // A restored marker is only meaningful while its record exists
    // locally; the record being gone means the restore was itself
    // undone (deleted again / scope reset), so the marker is spent.
    _restoredMarkers.removeWhere((key, _) {
      final sep = key.indexOf('|');
      if (sep <= 0) return true;
      return !_recordExistsLocally(
          key.substring(0, sep), key.substring(sep + 1));
    });
    welcomeDone = prefs.getBool(_kWelcome) ?? false;
    loaded = true;
    notifyListeners();
  }

  /// Switches the active identity: pending cloud writes for the old
  /// identity are cancelled (so its data can never land in another
  /// account), in-memory data is cleared, and the new identity's saved
  /// data — if any — is loaded. Other identities' saved data is never
  /// touched.
  Future<void> activateIdentity(String id) async {
    SyncService().cancelPending();
    PublishService().cancelPending();
    _identityId = id;
    teams = [];
    tournaments = [];
    matches = [];
    regPlayers = [];
    drafts = [];
    manualStats = [];
    tombstones = [];
    _trash = [];
    _restoredMarkers = {};
    profile = null;
    loaded = false;
    await load();
  }

  /// Activates a signed-in account's identity: first the owner-only
  /// legacy claim (see [claimLegacyData]), then the owner-only
  /// guest migration (see [migrateGuestDataToOwner]), then the
  /// account's own scope is loaded and its profile ensured
  /// (feature #3).
  Future<void> activateAccount(
    String uid, {
    String? email,
    String? displayName,
    String? phoneNumber,
  }) async {
    await claimLegacyData(uid, email: email);
    await migrateGuestDataToOwner(uid, email: email);
    await activateIdentity(uid);
    await ensureProfile(
      displayName: displayName,
      contact: email ?? phoneNumber,
    );
  }

  /// Ensures the active identity has an account profile: creates it on
  /// first activation (display name from the auth profile, else the
  /// email prefix, else 'Player'; a unique code derived from the uid)
  /// and refreshes name/contact when fresher auth values arrive.
  /// Guests and the locked scope never get a profile. The profile is
  /// part of this identity's scoped data, so it rides the backup sync.
  Future<void> ensureProfile({String? displayName, String? contact}) async {
    if (_identityId == 'guest' || _identityId == 'locked') return;
    final existing = profile;
    if (existing == null || existing.uid != _identityId) {
      profile = AccountProfile.create(
        uid: _identityId,
        displayName: displayName,
        contact: contact,
      );
      await persist();
      return;
    }
    var changed = false;
    if (displayName != null &&
        displayName.trim().isNotEmpty &&
        displayName.trim() != existing.displayName) {
      existing.displayName = displayName.trim();
      changed = true;
    }
    if (contact != null &&
        contact.isNotEmpty &&
        contact != existing.contact) {
      existing.contact = contact;
      changed = true;
    }
    if (changed) await persist();
  }

  /// Moves pre-v1.3.1 device data (stored under the original unscoped
  /// keys) into the OWNER account's scope, then removes the legacy
  /// keys. OWNER-ONLY (claim-guard): that data is the app owner's, so
  /// it is claimed solely when the signing-in account's [email] is
  /// exactly [kOwnerEmail]. Any other account — and phone logins,
  /// which carry no email — get false here and the legacy keys are
  /// left completely untouched, so the owner can still claim the data
  /// later on the same phone. Also only runs when the owner's own
  /// scope is still empty, so existing account data is never
  /// overwritten. Returns true when data was claimed.
  Future<bool> claimLegacyData(String uid, {String? email}) async {
    if (email == null || email.trim() != kOwnerEmail) return false;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_kTeams) == null) return false;
    if (prefs.getString('${_kTeams}__$uid') != null) return false;
    final dataKeys = [
      _kTeams,
      _kTournaments,
      _kMatches,
      _kReg,
      _kDrafts,
      _kManual,
      _kTombstones,
      _kTrash,
      _kRestored,
    ];
    for (final base in dataKeys) {
      final v = prefs.getString(base);
      if (v != null) await prefs.setString('${base}__$uid', v);
      await prefs.remove(base);
    }
    final lm = prefs.getInt(_kLastModified);
    if (lm != null) {
      await prefs.setInt('${_kLastModified}__$uid', lm);
      await prefs.remove(_kLastModified);
    }
    return true;
  }

  /// Copies the GUEST workspace into the OWNER account's scope on
  /// first owner sign-in (v1.4.1): a phone that used the app as
  /// guest/offline (never signed in) holds its whole league under
  /// guest-scoped keys, and the pre-v1.3.1 legacy claim above does
  /// NOT cover those keys — without this step an owner sign-in
  /// would switch to an empty owner scope and the guest data would
  /// sit invisible behind it. OWNER-ONLY (same claim-guard as
  /// [claimLegacyData]): the signing-in account's [email] must be
  /// exactly [kOwnerEmail]; any other account — and phone logins,
  /// which carry no email — get false. Only runs when the owner's
  /// own scope is still empty, so existing account data is never
  /// overwritten. Guest keys are COPIED, never removed: they stay
  /// as a backup, and logging out still restores the guest
  /// workspace exactly as it was. Returns true when at least one
  /// key was copied.
  Future<bool> migrateGuestDataToOwner(String uid, {String? email}) async {
    if (email == null || email.trim() != kOwnerEmail) return false;
    final prefs = await SharedPreferences.getInstance();
    const dataKeys = [
      _kTeams,
      _kTournaments,
      _kMatches,
      _kReg,
      _kDrafts,
      _kManual,
      _kTombstones,
      _kTrash,
      _kRestored,
      _kProfile,
    ];
    // Owner scope must still be empty — any existing key refuses.
    for (final base in dataKeys) {
      if (prefs.getString('${base}__$uid') != null) return false;
    }
    if (prefs.getInt('${_kLastModified}__$uid') != null) return false;
    var copied = false;
    for (final base in dataKeys) {
      final v = prefs.getString('${base}__guest');
      if (v != null) {
        await prefs.setString('${base}__$uid', v);
        copied = true;
      }
    }
    final lm = prefs.getInt('${_kLastModified}__guest');
    if (lm != null) {
      await prefs.setInt('${_kLastModified}__$uid', lm);
      copied = true;
    }
    return copied;
  }

  /// Full data export for backups (§31). Versioned JSON map.
  Map<String, dynamic> exportJson() => {
    'app': '60Score',
    'schema': _kSchemaVersion,
    'exportedAt': DateTime.now().toIso8601String(),
    'profile': profile?.toJson(),
    'teams': teams.map((t) => t.toJson()).toList(),
    'tournaments': tournaments.map((t) => t.toJson()).toList(),
    'matches': matches.map((m) => m.toJson()).toList(),
    'regPlayers': regPlayers.map((r) => r.toJson()).toList(),
    'drafts': drafts.map((d) => d.toJson()).toList(),
    'manualStats': manualStats.map((e) => e.toJson()).toList(),
  };

  /// Restore by MERGING backup data (§31): same-id records are replaced,
  /// new records are added, nothing is deleted. Returns counts per entity.
  /// Atomic restore (v1.4.5, M3): decodes EVERYTHING into temp
  /// structures first and applies only on full success. The old code
  /// merged each list into the live lists as it decoded, so a
  /// corrupt entry halfway through left a partial merge live (and
  /// with merge=false the live lists were already emptied). Now a
  /// decode failure touches nothing live: the temps are discarded
  /// and the store reloads from disk, then the error is rethrown so
  /// the restore UI can say the restore failed. A persist failure
  /// after a successful apply reloads from disk the same way.
  /// Profile guard (unchanged): a present-but-corrupt profile entry
  /// is ignored and the current profile kept on the merge path.
  Future<Map<String, int>> importJson(
    Map<String, dynamic> data, {
    bool merge = true,
  }) async {
    List<T> dec<T>(String key, T Function(Map<String, dynamic>) f) {
      final raw = data[key] as List?;
      if (raw == null) return [];
      return raw.map((e) => f(e as Map<String, dynamic>)).toList();
    }

    int mergeList<T>(List<T> current, List<T> incoming, String Function(T) id) {
      var replaced = 0;
      var added = 0;
      for (final item in incoming) {
        final i = current.indexWhere((x) => id(x) == id(item));
        if (i >= 0) {
          current[i] = item;
          replaced++;
        } else {
          current.add(item);
          added++;
        }
      }
      return replaced + added;
    }

    // Decode phase: temp structures only, nothing live touched.
    late final List<Team> tmpTeams;
    late final List<Tournament> tmpTournaments;
    late final List<Match> tmpMatches;
    late final List<RegPlayer> tmpRegPlayers;
    late final List<Draft> tmpDrafts;
    late final List<ManualStatEntry> tmpManualStats;
    AccountProfile? tmpProfile;
    var profileParsed = false;
    try {
      tmpTeams = dec('teams', Team.fromJson);
      tmpTournaments = dec('tournaments', Tournament.fromJson);
      tmpMatches = dec('matches', Match.fromJson);
      tmpRegPlayers = dec('regPlayers', RegPlayer.fromJson);
      tmpDrafts = dec('drafts', Draft.fromJson);
      tmpManualStats = dec('manualStats', ManualStatEntry.fromJson);
      final rawProfile = data['profile'];
      if (rawProfile is Map<String, dynamic>) {
        try {
          tmpProfile = AccountProfile.fromJson(rawProfile);
          profileParsed = true;
        } catch (_) {
          // Corrupt profile entry: ignore it (guard as before).
          tmpProfile = null;
          profileParsed = false;
        }
      }
    } catch (_) {
      // Nothing live changed yet, but reload from disk anyway so the
      // live state is provably the stored state, then report failure.
      await load();
      rethrow;
    }

    // Apply phase: only runs after every decode succeeded.
    final counts = <String, int>{};
    if (!merge) {
      teams = tmpTeams;
      tournaments = tmpTournaments;
      matches = tmpMatches;
      regPlayers = tmpRegPlayers;
      drafts = tmpDrafts;
      manualStats = tmpManualStats;
      // Replace path mirrors the old semantics: the profile becomes
      // the backup's profile, or null when the backup has none (or a
      // corrupt one) — the old code had already emptied it above.
      profile = tmpProfile;
      counts['teams'] = tmpTeams.length;
      counts['tournaments'] = tmpTournaments.length;
      counts['matches'] = tmpMatches.length;
      counts['regPlayers'] = tmpRegPlayers.length;
      counts['drafts'] = tmpDrafts.length;
      counts['manualStats'] = tmpManualStats.length;
    } else {
      if (profileParsed) profile = tmpProfile;
      counts['teams'] = mergeList(teams, tmpTeams, (t) => t.id);
      counts['tournaments'] =
          mergeList(tournaments, tmpTournaments, (t) => t.id);
      counts['matches'] = mergeList(matches, tmpMatches, (m) => m.id);
      counts['regPlayers'] =
          mergeList(regPlayers, tmpRegPlayers, (r) => r.id);
      counts['drafts'] = mergeList(drafts, tmpDrafts, (d) => d.id);
      counts['manualStats'] =
          mergeList(manualStats, tmpManualStats, (e) => e.id);
    }
    // Restoring a record from a backup file is an explicit restore
    // (the admin-restore path): any record that exists locally
    // again loses its tombstone, or the restore would be undone by
    // the next sync round. The tombstone's deletedAt is kept as a
    // restored marker first, so the entity sync can still prove
    // this restore against a tombstone held only in the cloud.
    for (final t in tombstones) {
      if (_recordExistsLocally(t.kind, t.id)) {
        final key = '${t.kind}|${t.id}';
        final prev = _restoredMarkers[key];
        if (prev == null || t.deletedAt > prev) {
          _restoredMarkers[key] = t.deletedAt;
        }
      }
    }
    tombstones.removeWhere((t) => _recordExistsLocally(t.kind, t.id));
    // The same consistency rule for Trash: a record that exists
    // locally again must not also sit in Trash.
    _trash.removeWhere((e) => _recordExistsLocally(e.kind, e.id));
    final saved = await persist();
    if (!saved) {
      // The apply is in memory only — disk still holds the old
      // state, so reload to keep live == stored, then report failure.
      await load();
      throw StateError('Restore save failed — storage write incomplete.');
    }
    return counts;
  }

  bool _recordExistsLocally(String kind, String id) {
    switch (kind) {
      case EntityKind.matches:
        return matches.any((m) => m.id == id);
      case EntityKind.teams:
        return teams.any((t) => t.id == id);
      case EntityKind.tournaments:
        return tournaments.any((t) => t.id == id);
      case EntityKind.regPlayers:
        return regPlayers.any((r) => r.id == id);
      case EntityKind.drafts:
        return drafts.any((d) => d.id == id);
      case EntityKind.manualStats:
        return manualStats.any((e) => e.id == id);
      default:
        return false;
    }
  }

  /// Reset App (§29): explain → confirm (UI) → wipe ALL user data.
  /// The app is left completely empty — nothing is seeded or restored.
  /// Backups and exported files are left untouched.
  Future<void> resetApp() async {
    teams = [];
    tournaments = [];
    matches = [];
    regPlayers = [];
    drafts = [];
    manualStats = [];
    // A reset is a local wipe, not a sync deletion: tombstones are
    // cleared with everything else, exactly as before this fix a
    // reset left no trace in the sync layer either (the push
    // guard's empty-dataset rules govern what reaches the cloud).
    tombstones = [];
    _trash = [];
    _restoredMarkers = {};
    profile = null;
    welcomeDone = false;
    await persist();
  }

  AccountProfile? _decodeProfile(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return AccountProfile.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null; // corrupt entry: caller keeps the previous profile
    }
  }

  List<T>? _decodeList<T>(
    String? raw,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      // Per-entry fallback (launch hardening): one poisoned record
      // used to drop the WHOLE list — a single corrupt match could
      // empty the app's data on launch. Now only the bad entry is
      // skipped and every good record still loads.
      final out = <T>[];
      for (final e in list) {
        try {
          out.add(fromJson(e as Map<String, dynamic>));
        } catch (_) {
          // Skip this entry, keep the rest.
        }
      }
      return out;
    } catch (_) {
      return null; // wholly unreadable: caller keeps the previous list
    }
  }

  Future<void> _saveAll([SharedPreferences? prefs]) async {
    final p = prefs ?? await SharedPreferences.getInstance();
    await p.setString(
      _scoped(_kTeams),
      jsonEncode(teams.map((t) => t.toJson()).toList()),
    );
    await p.setString(
      _scoped(_kTournaments),
      jsonEncode(tournaments.map((t) => t.toJson()).toList()),
    );
    await p.setString(
      _scoped(_kMatches),
      jsonEncode(matches.map((m) => m.toJson()).toList()),
    );
    await p.setString(
      _scoped(_kReg),
      jsonEncode(regPlayers.map((r) => r.toJson()).toList()),
    );
    await p.setString(
      _scoped(_kDrafts),
      jsonEncode(drafts.map((d) => d.toJson()).toList()),
    );
    await p.setString(
      _scoped(_kManual),
      jsonEncode(manualStats.map((e) => e.toJson()).toList()),
    );
    final prof = profile;
    if (prof == null) {
      await p.remove(_scoped(_kProfile));
    } else {
      await p.setString(_scoped(_kProfile), jsonEncode(prof.toJson()));
    }
    await p.setString(
      _scoped(_kTombstones),
      jsonEncode(tombstones.map((t) => t.toJson()).toList()),
    );
    await p.setString(
      _scoped(_kTrash),
      jsonEncode(_trash.map((e) => e.toJson()).toList()),
    );
    await p.setString(
      _scoped(_kRestored),
      jsonEncode(_restoredMarkers),
    );
    await p.setBool(_kWelcome, welcomeDone);
  }

  List<TrashEntry>? _decodeTrash(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => TrashEntry.fromJson(e as Map<String, dynamic>))
          .where((t) => t.kind.isNotEmpty && t.id.isNotEmpty)
          .toList();
    } catch (_) {
      return null; // corrupt entry: caller keeps the previous set
    }
  }

  Map<String, int>? _decodeRestoredMarkers(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final e in map.entries)
          if (e.value is num) e.key: (e.value as num).toInt(),
      };
    } catch (_) {
      return null; // corrupt entry: caller keeps the previous set
    }
  }

  List<Tombstone>? _decodeTombstones(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => Tombstone.fromJson(e as Map<String, dynamic>))
          .where((t) => t.kind.isNotEmpty && t.id.isNotEmpty)
          .toList();
    } catch (_) {
      return null; // corrupt entry: caller keeps the previous set
    }
  }

  // ---------- tombstones (Sync Fix "D") ----------

  /// Records (or refreshes) the tombstone for one deleted record.
  void _recordTombstone(String kind, String id) {
    tombstones.removeWhere((t) => t.kind == kind && t.id == id);
    tombstones.add(Tombstone(
      kind: kind,
      id: id,
      deletedAt: DateTime.now().millisecondsSinceEpoch,
    ));
    // A fresh delete supersedes any earlier restore of this record.
    clearRestoredMarker(kind, id);
  }

  /// Clears the tombstone for one record: an explicit re-add of
  /// the same id is the admin-restore path (plan §4).
  void _clearTombstone(String kind, String id) {
    tombstones.removeWhere((t) => t.kind == kind && t.id == id);
  }

  /// Unions tombstones received from the cloud into the local set
  /// (per record, the newest deletion wins). Returns true when the
  /// local set changed. Never removes a local tombstone — a
  /// deletion this device made cannot be un-made by a pull.
  bool absorbTombstones(Iterable<Tombstone> incoming) {
    var changed = false;
    for (final t in incoming) {
      if (t.kind.isEmpty || t.id.isEmpty) continue;
      final i =
          tombstones.indexWhere((x) => x.kind == t.kind && x.id == t.id);
      if (i < 0) {
        tombstones.add(t);
        changed = true;
      } else if (t.deletedAt > tombstones[i].deletedAt) {
        tombstones[i] = t;
        changed = true;
      }
    }
    return changed;
  }

  /// Ids of matches this identity has deleted (locally or via a
  /// pulled tombstone): sync must never let such a record back in.
  Set<String> get tombstonedMatchIds => {
        for (final t in tombstones)
          if (t.kind == EntityKind.matches) t.id,
      };

  // ---------- trash (Feature 1 — Trash + Restore) ----------

  static Map<String, dynamic> _deepCopyPayload(Map<String, dynamic> m) =>
      jsonDecode(jsonEncode(m)) as Map<String, dynamic>;

  String _matchTrashName(Match m) {
    final title = m.matchTitle.trim();
    if (title.isNotEmpty) return title;
    final a = teamName(m.teamAId);
    final b = teamName(m.teamBId);
    if (a == 'Unknown team' && b == 'Unknown team') return 'Match ${m.id}';
    return '$a vs $b';
  }

  /// Snapshots [payload] into Trash for (kind, id), replacing any
  /// older entry for the same record. Called BEFORE the record is
  /// removed, so the payload is complete.
  void _snapshotToTrash(
    String kind,
    String id,
    String name,
    Map<String, dynamic> payload,
  ) {
    _trash.removeWhere((e) => e.kind == kind && e.id == id);
    _trash.add(TrashEntry(
      kind: kind,
      id: id,
      name: name,
      deletedAt: DateTime.now().millisecondsSinceEpoch,
      payload: _deepCopyPayload(payload),
    ));
  }

  /// Restores one trashed record: the snapshot is re-inserted
  /// through the existing upsert path for its kind, which clears
  /// the record's tombstone — the admin-restore semantics of the
  /// D plan §4 (a restored record beats its tombstone). See
  /// lib/entity_sync_coordinator.dart: StoreEntityDocStore marks
  /// a record that reaches a sync round still carrying its
  /// tombstone as `restored: true` with its stamp floored above
  /// the tombstone's deletedAt, so the merge/gate let it survive
  /// and spend the tombstone. The trash entry is removed and the
  /// result persisted (via the upsert's own persist).
  Future<void> restoreFromTrash(String kind, String id) async {
    final i = _trash.indexWhere((e) => e.kind == kind && e.id == id);
    if (i < 0) return;
    final entry = _trash[i];
    final payload = _deepCopyPayload(entry.payload);
    // Remember the tombstone this restore must out-rank BEFORE the
    // upsert below clears it locally: the cloud may still hold that
    // tombstone, and without the marker the next entity-sync round
    // would read this record as an ordinary (un-flagged) copy and
    // let the cloud tombstone kill it again (Feature 1 follow-up).
    final tomb = tombstoneFor(tombstones, kind, id);
    if (tomb != null) {
      _restoredMarkers['$kind|$id'] = tomb.deletedAt;
    }
    // Decode FIRST: if the payload were corrupt, the trash entry
    // must survive instead of being lost with nothing restored.
    switch (kind) {
      case EntityKind.matches:
        final m = Match.fromJson(payload);
        _trash.removeAt(i);
        await upsertMatch(m);
        break;
      case EntityKind.teams:
        final t = Team.fromJson(payload);
        _trash.removeAt(i);
        await upsertTeam(t);
        break;
      case EntityKind.tournaments:
        final t = Tournament.fromJson(payload);
        _trash.removeAt(i);
        await upsertTournament(t);
        break;
      default:
        // Unknown kind: nothing restorable — drop the entry so it
        // cannot sit in Trash forever.
        _trash.removeAt(i);
        await persist();
        break;
    }
  }

  /// Permanently deletes one trashed record: only the snapshot is
  /// dropped. The tombstone recorded at delete time MUST remain —
  /// it is what keeps the record deleted everywhere.
  Future<void> permanentlyDeleteFromTrash(String kind, String id) async {
    _trash.removeWhere((e) => e.kind == kind && e.id == id);
    await persist();
  }

  /// Wall-clock ms of the last local change (used by cloud sync).
  /// Scoped per identity: each account's sync clock is its own.
  Future<int> getLastModified() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_scoped(_kLastModified)) ?? 0;
  }

  Future<void> setLastModified(int ms) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_scoped(_kLastModified), ms);
  }

  @override
  /// Full save. Returns true when every key landed on disk, false
  /// when any write failed (v1.4.5 action feedback: callers that
  /// must tell the user — backup/restore/edit saves — check this
  /// instead of relying on a throw that nobody awaited).
  Future<bool> persist({bool skipSync = false}) async {
    try {
      await _saveAll();
      await setLastModified(DateTime.now().millisecondsSinceEpoch);
    } catch (_) {
      return false;
    }
    notifyListeners();
    if (!skipSync) {
      // Offline-first (v1.4.5): no automatic cloud push — this only
      // marks the store dirty; the next explicit sync point pushes.
      SyncService().schedulePush(this);
      // Fully local (v1.4.5): publish is off, so the republish
      // call below is a no-op — kept so the save shape stays
      // identical if publish is ever re-enabled.
      PublishService().scheduleRepublish(this);
    }
    return true;
  }

  /// Ball-path persist (v1.4.3, smoothness): writes ONLY the
  /// matches key. During scoring, the scored match is the only
  /// thing that changes — teams (with inline player photos,
  /// megabytes for a real league) and every other collection are
  /// untouched, so re-encoding them per ball was the load that
  /// froze the app. All other persist work (last-modified stamp,
  /// listeners, republish) runs exactly like [persist]; the cloud
  /// push does NOT run here anymore (v1.4.5 offline-first: saves
  /// only mark the push debt, sync points push). Every other
  /// path keeps using [persist] (full write); only the per-ball
  /// path uses this. Playoff updates persist themselves (full
  /// write) on the rare balls when they change something.
  Future<bool> persistMatchesOnly({bool skipSync = false}) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
        _scoped(_kMatches),
        jsonEncode(matches.map((m) => m.toJson()).toList()),
      );
      await setLastModified(DateTime.now().millisecondsSinceEpoch);
    } catch (_) {
      return false;
    }
    notifyListeners();
    if (!skipSync) {
      SyncService().schedulePush(this);
      PublishService().scheduleRepublish(this);
    }
    return true;
  }

  /// Tournament-edit persist (v1.4.5, stability): writes ONLY the
  /// tournaments key. Tournament edits (points-table row overrides,
  /// points adjustments) touch nothing else, but the old path used
  /// full [persist] ([_saveAll]) — re-encoding ALL data including
  /// the teams key with inline player photos (megabytes for a real
  /// league) plus a cloud push and a republish, right after the
  /// edit. That spike is the prime suspect for the silent closes
  /// the user hit on 1.4.4 just after points-table edits (no Dart
  /// error was recorded, pointing to an OS-level kill). Same shape
  /// as [persistMatchesOnly]: last-modified stamp, listeners and
  /// republish still run — only the local re-encode shrinks to the
  /// one changed key, and the cloud push does NOT run here anymore
  /// (v1.4.5 offline-first: the edit only marks the push debt;
  /// the next explicit sync point pushes).
  Future<bool> persistTournamentsOnly({bool skipSync = false}) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
        _scoped(_kTournaments),
        jsonEncode(tournaments.map((t) => t.toJson()).toList()),
      );
      await setLastModified(DateTime.now().millisecondsSinceEpoch);
    } catch (_) {
      return false;
    }
    notifyListeners();
    if (!skipSync) {
      SyncService().schedulePush(this);
      PublishService().scheduleRepublish(this);
    }
    return true;
  }

  /// Teams-only persist (v1.4.5, M1): same shape as
  /// [persistTournamentsOnly] — writes ONLY the teams key (with
  /// inline player photos, the heaviest single key). Team screens
  /// (list, detail, renames, player add/remove/edit) touch nothing
  /// else, so re-encoding every collection per team edit was pure
  /// load. Returns true/false like the other granular saves.
  Future<bool> persistTeamsOnly({bool skipSync = false}) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
        _scoped(_kTeams),
        jsonEncode(teams.map((t) => t.toJson()).toList()),
      );
      await setLastModified(DateTime.now().millisecondsSinceEpoch);
    } catch (_) {
      return false;
    }
    notifyListeners();
    if (!skipSync) {
      SyncService().schedulePush(this);
      PublishService().scheduleRepublish(this);
    }
    return true;
  }

  /// Drafts-only persist (v1.4.5, M1): writes ONLY the drafts key.
  /// Draft-screen actions (pick / skip / undo) mutate the draft
  /// object and nothing else.
  Future<bool> persistDraftsOnly({bool skipSync = false}) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
        _scoped(_kDrafts),
        jsonEncode(drafts.map((d) => d.toJson()).toList()),
      );
      await setLastModified(DateTime.now().millisecondsSinceEpoch);
    } catch (_) {
      return false;
    }
    notifyListeners();
    if (!skipSync) {
      SyncService().schedulePush(this);
      PublishService().scheduleRepublish(this);
    }
    return true;
  }

  /// Registered-players-only persist (v1.4.5, M1): writes ONLY the
  /// regPlayers key. The registration import path appends to this
  /// list and nothing else.
  Future<bool> persistRegPlayersOnly({bool skipSync = false}) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
        _scoped(_kReg),
        jsonEncode(regPlayers.map((r) => r.toJson()).toList()),
      );
      await setLastModified(DateTime.now().millisecondsSinceEpoch);
    } catch (_) {
      return false;
    }
    notifyListeners();
    if (!skipSync) {
      SyncService().schedulePush(this);
      PublishService().scheduleRepublish(this);
    }
    return true;
  }

  // ---------- lookups ----------
  Team? teamById(String id) {
    for (final t in teams) {
      if (t.id == id) return t;
    }
    return null;
  }

  @override
  Tournament? tournamentById(String? id) {
    if (id == null) return null;
    for (final t in tournaments) {
      if (t.id == id) return t;
    }
    return null;
  }

  Match? matchById(String id) {
    for (final m in matches) {
      if (m.id == id) return m;
    }
    return null;
  }

  @override
  String teamName(String id) {
    if (id.isEmpty) return 'TBD'; // playoff slot not yet assigned
    return teamById(id)?.name ?? 'Unknown team';
  }

  String playerName(String id) {
    for (final t in teams) {
      final p = t.playerById(id);
      if (p != null) return p.name;
    }
    for (final r in regPlayers) {
      if (r.id == id) return r.name;
    }
    for (final e in manualStats) {
      if (e.playerId == id && e.playerName.isNotEmpty) return e.playerName;
    }
    return id.length > 10 ? 'Player' : id;
  }

  RegPlayer? regById(String id) {
    for (final r in regPlayers) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// Shared photo lookup (v1.1.6): one player record, one photo everywhere.
  /// Prefers the Registered Players record (the canonical profile), falls
  /// back to the team-squad copy, returns '' when no photo exists anywhere.
  /// Use this wherever a player photo is displayed instead of reading a
  /// single copy's photoBase64, so a photo added in Registered Players
  /// (or Team Management) shows up in Team Management, squads, Playing XI,
  /// POTM, Summary and fixture cards without any re-import.
  String photoForPlayer(String id) {
    final reg = regById(id);
    if (reg != null && reg.photoBase64.isNotEmpty) {
      return reg.photoBase64;
    }
    final p = findPlayer(id);
    if (p != null && p.photoBase64.isNotEmpty) {
      return p.photoBase64;
    }
    return '';
  }

  Draft? draftById(String id) {
    for (final d in drafts) {
      if (d.id == id) return d;
    }
    return null;
  }

  Future<void> upsertRegPlayer(RegPlayer r) async {
    _clearTombstone(EntityKind.regPlayers, r.id);
    final i = regPlayers.indexWhere((x) => x.id == r.id);
    if (i >= 0) {
      regPlayers[i] = r;
    } else {
      regPlayers.add(r);
    }
    await persist();
  }

  Future<void> deleteRegPlayer(String id) async {
    regPlayers.removeWhere((r) => r.id == id);
    _recordTombstone(EntityKind.regPlayers, id);
    await persist();
  }

  Future<void> upsertDraft(Draft d) async {
    _clearTombstone(EntityKind.drafts, d.id);
    final i = drafts.indexWhere((x) => x.id == d.id);
    if (i >= 0) {
      drafts[i] = d;
    } else {
      drafts.insert(0, d);
    }
    await persist();
  }

  Future<void> deleteDraft(String id) async {
    drafts.removeWhere((d) => d.id == id);
    _recordTombstone(EntityKind.drafts, id);
    await persist();
  }

  /// Remove one draft pick (from Draft History / Team Squads) and re-index
  /// the remaining picks so rounds and turns stay fair.
  Future<bool> deleteDraftPick(Draft d, DraftPick pick) async {
    final removed = removePick(d, pick);
    if (removed) await persist();
    return removed;
  }

  Future<void> addManualStat(ManualStatEntry e) async {
    _clearTombstone(EntityKind.manualStats, e.id);
    manualStats.insert(0, e);
    await persist();
  }

  /// v1.3.7: insert or replace a manual entry (the edit path).
  /// Replacement happens in place so the entries list order is
  /// stable; an unknown id inserts at the top, like an add.
  Future<void> upsertManualStat(ManualStatEntry e) async {
    _clearTombstone(EntityKind.manualStats, e.id);
    final i = manualStats.indexWhere((x) => x.id == e.id);
    if (i >= 0) {
      manualStats[i] = e;
    } else {
      manualStats.insert(0, e);
    }
    await persist();
  }

  Future<void> deleteManualStat(String id) async {
    manualStats.removeWhere((e) => e.id == id);
    _recordTombstone(EntityKind.manualStats, id);
    await persist();
  }

  /// Copy a completed draft's squads into the Scorer teams. Each drafted
  /// player becomes (or updates) a team [Player] keeping the SAME id, so
  /// career stats unify across Registration, Draft and Scorer.
  Future<void> applyDraftToTeams(Draft d) async {
    for (final teamId in d.teamIds) {
      final team = teamById(teamId);
      if (team == null) continue;
      final picks = d.picks.where((p) => p.teamId == teamId).toList()
        ..sort((a, b) => a.pickNo.compareTo(b.pickNo));
      for (final pick in picks) {
        final reg = regById(pick.playerId);
        if (reg == null) continue;
        final existing = team.playerById(pick.playerId);
        if (existing == null) {
          team.players.add(reg.toTeamPlayer());
        } else {
          existing.name = reg.name;
          existing.role = reg.role;
          existing.battingStyle = reg.battingStyle;
          existing.bowlingStyle = reg.bowlingStyle;
          // v1.1.6: keep the shared photo in sync on re-apply too, so the
          // team copy never shows a stale/missing image.
          existing.photoBase64 = reg.photoBase64;
          if (reg.jerseyNo > 0) existing.jerseyNo = reg.jerseyNo;
        }
      }
    }
    d.appliedToTeams = true;
    await persist();
  }

  Player? findPlayer(String id) {
    for (final t in teams) {
      final p = t.playerById(id);
      if (p != null) return p;
    }
    return null;
  }

  // ---------- mutations ----------
  Future<void> upsertTeam(Team team) async {
    _clearTombstone(EntityKind.teams, team.id);
    // A record that exists again must not also sit in Trash.
    _trash.removeWhere(
        (e) => e.kind == EntityKind.teams && e.id == team.id);
    final i = teams.indexWhere((t) => t.id == team.id);
    if (i >= 0) {
      teams[i] = team;
    } else {
      teams.add(team);
    }
    await persist();
  }

  Future<void> deleteTeam(String id) async {
    // Snapshot into Trash BEFORE removal (Feature 1), so the team
    // can be restored exactly as it was.
    final team = teamById(id);
    if (team != null) {
      _snapshotToTrash(EntityKind.teams, id,
          team.name.isNotEmpty ? team.name : id, team.toJson());
    }
    teams.removeWhere((t) => t.id == id);
    _recordTombstone(EntityKind.teams, id);
    for (final tr in tournaments) {
      tr.teamIds.remove(id);
    }
    await persist();
  }

  Future<void> upsertTournament(Tournament t) async {
    _clearTombstone(EntityKind.tournaments, t.id);
    _trash.removeWhere(
        (e) => e.kind == EntityKind.tournaments && e.id == t.id);
    final i = tournaments.indexWhere((x) => x.id == t.id);
    if (i >= 0) {
      tournaments[i] = t;
    } else {
      tournaments.add(t);
    }
    await persist();
  }

  Future<void> deleteTournament(String id) async {
    // Snapshot into Trash BEFORE removal (Feature 1).
    final t = tournamentById(id);
    if (t != null) {
      _snapshotToTrash(EntityKind.tournaments, id,
          t.name.isNotEmpty ? t.name : id, t.toJson());
    }
    tournaments.removeWhere((t) => t.id == id);
    _recordTombstone(EntityKind.tournaments, id);
    await persist();
  }

  Future<void> upsertMatch(Match m) async {
    _clearTombstone(EntityKind.matches, m.id);
    _trash.removeWhere(
        (e) => e.kind == EntityKind.matches && e.id == m.id);
    final i = matches.indexWhere((x) => x.id == m.id);
    if (i >= 0) {
      matches[i] = m;
    } else {
      matches.insert(0, m);
    }
    await persist();
  }

  Future<void> deleteMatch(String id) async {
    // Snapshot into Trash BEFORE removal (Feature 1), so the match
    // — innings and all — can be restored exactly as it was.
    final m = matchById(id);
    if (m != null) {
      _snapshotToTrash(
          EntityKind.matches, id, _matchTrashName(m), m.toJson());
    }
    matches.removeWhere((m) => m.id == id);
    // The tombstone is the fix for the delete-resurrection defect:
    // without it, the sync union merge brings this match back from
    // the cloud (or the other phone) on the very next round.
    _recordTombstone(EntityKind.matches, id);
    await persist();
  }
}
