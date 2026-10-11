// SharedPreferences repository for 60Score.
// Everything is stored on the phone only — no network, no accounts.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class Store extends ChangeNotifier {
  List<Team> teams = [];
  List<Tournament> tournaments = [];
  List<Match> matches = [];
  List<RegPlayer> regPlayers = [];
  List<Draft> drafts = [];
  List<ManualStatEntry> manualStats = [];
  bool welcomeDone = false;
  bool loaded = false;

  static const _kTeams = 'cricscore_teams_v1';
  static const _kTournaments = 'cricscore_tournaments_v1';
  static const _kMatches = 'cricscore_matches_v1';
  static const _kSeeded = 'cricscore_seeded_v1';
  static const _kReg = 'score60_regplayers_v1';
  static const _kDrafts = 'score60_drafts_v1';
  static const _kManual = 'score60_manualstats_v1';
  static const _kWelcome = 'score60_welcome_v1';

  static int _counter = 0;
  static String newId(String prefix) {
    _counter++;
    return '${prefix}_${DateTime.now().microsecondsSinceEpoch}_$_counter';
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final seeded = prefs.getBool(_kSeeded) ?? false;
    if (!seeded) {
      // First launch: seed Super Sixty League Season 2 teams (empty squads).
      const seedNames = [
        'AB Knights',
        'MA Kings',
        'US Lions',
        'Shazi Hawks',
        'Adi Dolphins',
        'Ali Panthers',
      ];
      teams = [
        for (var i = 0; i < seedNames.length; i++)
          Team(id: 'seed_team_$i', name: seedNames[i]),
      ];
      tournaments = [
        Tournament(
          id: 'seed_tournament_ssl2',
          name: 'Super Sixty League',
          teamIds: teams.map((t) => t.id).toList(),
        ),
      ];
      matches = [];
      await _saveAll(prefs);
      await prefs.setBool(_kSeeded, true);
    } else {
      teams = _decodeList(prefs.getString(_kTeams), Team.fromJson);
      tournaments = _decodeList(
        prefs.getString(_kTournaments),
        Tournament.fromJson,
      );
      matches = _decodeList(prefs.getString(_kMatches), Match.fromJson);
      regPlayers = _decodeList(prefs.getString(_kReg), RegPlayer.fromJson);
      drafts = _decodeList(prefs.getString(_kDrafts), Draft.fromJson);
      manualStats = _decodeList(
        prefs.getString(_kManual),
        ManualStatEntry.fromJson,
      );
    }
    welcomeDone = prefs.getBool(_kWelcome) ?? false;
    loaded = true;
    notifyListeners();
  }

  List<T> _decodeList<T>(
    String? raw,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
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

  Future<void> persist() async {
    await _saveAll();
    notifyListeners();
  }

  // ---------- lookups ----------
  Team? teamById(String id) {
    for (final t in teams) {
      if (t.id == id) return t;
    }
    return null;
  }

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

  String teamName(String id) => teamById(id)?.name ?? 'Unknown team';

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
