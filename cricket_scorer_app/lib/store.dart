// SharedPreferences repository for 60Score.
// Everything is stored on the phone only — no network, no accounts.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'draft.dart';
import 'models.dart';
import 'publish_service.dart';
import 'sync_service.dart';
import 'tournament_engine.dart';

class Store extends ChangeNotifier implements PlayoffStore {
  List<Team> teams = [];
  List<Tournament> tournaments = [];
  @override
  List<Match> matches = [];
  List<RegPlayer> regPlayers = [];
  List<Draft> drafts = [];
  List<ManualStatEntry> manualStats = [];
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
  static const _kWelcome = 'score60_welcome_v1';
  static const _kLastModified = 'score60_last_modified_v1';

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
    teams = _decodeList(prefs.getString(_kTeams), Team.fromJson) ?? teams;
    tournaments =
        _decodeList(prefs.getString(_kTournaments), Tournament.fromJson) ??
        tournaments;
    matches = _decodeList(prefs.getString(_kMatches), Match.fromJson) ??
        matches;
    regPlayers =
        _decodeList(prefs.getString(_kReg), RegPlayer.fromJson) ?? regPlayers;
    drafts = _decodeList(prefs.getString(_kDrafts), Draft.fromJson) ?? drafts;
    manualStats =
        _decodeList(prefs.getString(_kManual), ManualStatEntry.fromJson) ??
        manualStats;
    welcomeDone = prefs.getBool(_kWelcome) ?? false;
    loaded = true;
    notifyListeners();
  }

  /// Full data export for backups (§31). Versioned JSON map.
  Map<String, dynamic> exportJson() => {
    'app': '60Score',
    'schema': _kSchemaVersion,
    'exportedAt': DateTime.now().toIso8601String(),
    'teams': teams.map((t) => t.toJson()).toList(),
    'tournaments': tournaments.map((t) => t.toJson()).toList(),
    'matches': matches.map((m) => m.toJson()).toList(),
    'regPlayers': regPlayers.map((r) => r.toJson()).toList(),
    'drafts': drafts.map((d) => d.toJson()).toList(),
    'manualStats': manualStats.map((e) => e.toJson()).toList(),
  };

  /// Restore by MERGING backup data (§31): same-id records are replaced,
  /// new records are added, nothing is deleted. Returns counts per entity.
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

    final counts = <String, int>{};
    if (!merge) {
      teams = [];
      tournaments = [];
      matches = [];
      regPlayers = [];
      drafts = [];
      manualStats = [];
    }
    counts['teams'] = mergeList(
      teams,
      dec('teams', Team.fromJson),
      (t) => t.id,
    );
    counts['tournaments'] = mergeList(
      tournaments,
      dec('tournaments', Tournament.fromJson),
      (t) => t.id,
    );
    counts['matches'] = mergeList(
      matches,
      dec('matches', Match.fromJson),
      (m) => m.id,
    );
    counts['regPlayers'] = mergeList(
      regPlayers,
      dec('regPlayers', RegPlayer.fromJson),
      (r) => r.id,
    );
    counts['drafts'] = mergeList(
      drafts,
      dec('drafts', Draft.fromJson),
      (d) => d.id,
    );
    counts['manualStats'] = mergeList(
      manualStats,
      dec('manualStats', ManualStatEntry.fromJson),
      (e) => e.id,
    );
    await persist();
    return counts;
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
    welcomeDone = false;
    await persist();
  }

  List<T>? _decodeList<T>(
    String? raw,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return null; // corrupt entry: caller keeps the previous list
    }
  }

  Future<void> _saveAll([SharedPreferences? prefs]) async {
    final p = prefs ?? await SharedPreferences.getInstance();
    await p.setString(
      _kTeams,
      jsonEncode(teams.map((t) => t.toJson()).toList()),
    );
    await p.setString(
      _kTournaments,
      jsonEncode(tournaments.map((t) => t.toJson()).toList()),
    );
    await p.setString(
      _kMatches,
      jsonEncode(matches.map((m) => m.toJson()).toList()),
    );
    await p.setString(
      _kReg,
      jsonEncode(regPlayers.map((r) => r.toJson()).toList()),
    );
    await p.setString(
      _kDrafts,
      jsonEncode(drafts.map((d) => d.toJson()).toList()),
    );
    await p.setString(
      _kManual,
      jsonEncode(manualStats.map((e) => e.toJson()).toList()),
    );
    await p.setBool(_kWelcome, welcomeDone);
  }

  /// Wall-clock ms of the last local change (used by cloud sync).
  Future<int> getLastModified() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kLastModified) ?? 0;
  }

  Future<void> setLastModified(int ms) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kLastModified, ms);
  }

  @override
  Future<void> persist({bool skipSync = false}) async {
    await _saveAll();
    await setLastModified(DateTime.now().millisecondsSinceEpoch);
    notifyListeners();
    if (!skipSync) {
      // Fire-and-forget cloud push when logged in (no-op when offline).
      SyncService().schedulePush(this);
      // Keep any published tournament snapshots fresh for followers
      // (no-op when logged out or nothing is published).
      PublishService().scheduleRepublish(this);
    }
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
    await persist();
  }

  Future<void> upsertDraft(Draft d) async {
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
    manualStats.insert(0, e);
    await persist();
  }

  Future<void> deleteManualStat(String id) async {
    manualStats.removeWhere((e) => e.id == id);
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
    final i = teams.indexWhere((t) => t.id == team.id);
    if (i >= 0) {
      teams[i] = team;
    } else {
      teams.add(team);
    }
    await persist();
  }

  Future<void> deleteTeam(String id) async {
    teams.removeWhere((t) => t.id == id);
    for (final tr in tournaments) {
      tr.teamIds.remove(id);
    }
    await persist();
  }

  Future<void> upsertTournament(Tournament t) async {
    final i = tournaments.indexWhere((x) => x.id == t.id);
    if (i >= 0) {
      tournaments[i] = t;
    } else {
      tournaments.add(t);
    }
    await persist();
  }

  Future<void> deleteTournament(String id) async {
    tournaments.removeWhere((t) => t.id == id);
    await persist();
  }

  Future<void> upsertMatch(Match m) async {
    final i = matches.indexWhere((x) => x.id == m.id);
    if (i >= 0) {
      matches[i] = m;
    } else {
      matches.insert(0, m);
    }
    await persist();
  }

  Future<void> deleteMatch(String id) async {
    matches.removeWhere((m) => m.id == id);
    await persist();
  }
}
