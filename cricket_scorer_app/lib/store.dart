// SharedPreferences repository for 60Score.
// Everything is stored on the phone only — no network, no accounts.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
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
  static const _kSeeded = 'cricscore_seeded_v1';
  static const _kSchema = 'cricscore_schema_v';
  // Bump when seed/migration logic changes; migrations are idempotent.
  static const _kSchemaVersion = 2;
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
      _seedFreshInstall();
      await _saveAll(prefs);
      await prefs.setBool(_kSeeded, true);
      await prefs.setInt(_kSchema, _kSchemaVersion);
    } else {
      // Decode defensively: a corrupt entry keeps the previous in-memory
      // list instead of wiping it (the old code replaced it with [] and
      // the next persist() then overwrote storage with the empty list).
      teams = _decodeList(prefs.getString(_kTeams), Team.fromJson) ?? teams;
      tournaments =
          _decodeList(prefs.getString(_kTournaments), Tournament.fromJson) ??
          tournaments;
      matches = _decodeList(prefs.getString(_kMatches), Match.fromJson) ??
          matches;
      regPlayers =
          _decodeList(prefs.getString(_kReg), RegPlayer.fromJson) ??
          regPlayers;
      drafts = _decodeList(prefs.getString(_kDrafts), Draft.fromJson) ??
          drafts;
      manualStats =
          _decodeList(prefs.getString(_kManual), ManualStatEntry.fromJson) ??
          manualStats;
      await _migrateIfNeeded(prefs);
    }
    welcomeDone = prefs.getBool(_kWelcome) ?? false;
    loaded = true;
    notifyListeners();
  }

  /// Default tournament identity (stable across installs).
  static const defaultTournamentId = 'seed_tournament_ssl2';
  static const defaultTournamentName = 'Super Sixty League Season 2K26';
  static const defaultVenue = '75 LOKRI CLUB';

  /// Spec team order. IDs are stable: seed_team_0..5.
  static const defaultTeamNames = [
    'AB Knights',
    'Shazi Hawks',
    'MA Kings',
    'Ali Panthers',
    'Adi Dolphins',
    'US Lions',
  ];

  /// Previous seed order (v1) for safe migration of existing installs.
  static const _v1TeamNames = [
    'AB Knights',
    'MA Kings',
    'US Lions',
    'Shazi Hawks',
    'Adi Dolphins',
    'Ali Panthers',
  ];

  void _seedFreshInstall() {
    teams = [
      for (var i = 0; i < defaultTeamNames.length; i++)
        Team(id: 'seed_team_$i', name: defaultTeamNames[i]),
    ];
    tournaments = [
      Tournament(
        id: defaultTournamentId,
        name: defaultTournamentName,
        teamIds: teams.map((t) => t.id).toList(),
        venue: defaultVenue,
      ),
    ];
    matches = [];
    regPlayers = [];
    drafts = [];
    manualStats = [];
    _seedDefaultFixtures();
  }

  /// Idempotent migration for installs seeded by older app versions.
  /// Never overwrites user-customized data: teams are renamed only when
  /// they still carry the untouched v1 default name, have no players,
  /// and are not referenced by any match.
  Future<void> _migrateIfNeeded(SharedPreferences prefs) async {
    final v = prefs.getInt(_kSchema) ?? 1;
    if (v >= _kSchemaVersion) return;
    var changed = false;

    final t = tournamentById(defaultTournamentId);
    if (t != null) {
      if (t.name != defaultTournamentName) {
        t.name = defaultTournamentName;
        changed = true;
      }
      if (t.venue.isEmpty) {
        t.venue = defaultVenue;
        changed = true;
      }
      // v1 -> v2 team rename (safe only, see doc comment above).
      for (var i = 0; i < _v1TeamNames.length; i++) {
        final team = teamById('seed_team_$i');
        if (team == null) continue;
        final wanted = defaultTeamNames[i];
        if (team.name == wanted) continue;
        final untouchedDefault = team.name == _v1TeamNames[i];
        final hasPlayers = team.players.isNotEmpty;
        final referenced = matches.any(
          (m) => m.teamAId == team.id || m.teamBId == team.id,
        );
        if (untouchedDefault && !hasPlayers && !referenced) {
          team.name = wanted;
          changed = true;
        }
      }
      t.teamIds = [
        for (var i = 0; i < defaultTeamNames.length; i++) 'seed_team_$i',
      ];
    }
    // Seed the 18 default fixtures if they are missing (per-fixture check).
    final before = matches.length;
    _seedDefaultFixtures();
    if (matches.length != before) changed = true;

    if (changed) await _saveAll(prefs);
    await prefs.setInt(_kSchema, _kSchemaVersion);
  }

  /// Creates the 15 league + 3 playoff fixtures of the default tournament.
  /// Idempotent: existing fixture IDs are never duplicated.
  /// Pure (no I/O) so it is unit-testable — pass the current match list.
  static List<Match> buildDefaultFixtures(List<Match> existing) {
    bool has(String id) => existing.any((m) => m.id == id);
    final out = <Match>[];
    String tid(String name) {
      final i = defaultTeamNames.indexOf(name);
      return 'seed_team_$i';
    }

    // (matchNo, date yyyy-MM-dd, time HH:mm 24h, teamA, teamB)
    const league = [
      ['01', '2026-10-22', '14:00', 'Shazi Hawks', 'Adi Dolphins'],
      ['02', '2026-10-23', '15:00', 'AB Knights', 'Ali Panthers'],
      ['03', '2026-10-24', '14:00', 'Shazi Hawks', 'MA Kings'],
      ['04', '2026-10-25', '14:00', 'AB Knights', 'US Lions'],
      ['05', '2026-10-26', '14:00', 'MA Kings', 'Adi Dolphins'],
      ['06', '2026-10-27', '14:00', 'Shazi Hawks', 'Ali Panthers'],
      ['07', '2026-10-28', '14:00', 'MA Kings', 'US Lions'],
      ['08', '2026-10-29', '14:00', 'AB Knights', 'Shazi Hawks'],
      ['09', '2026-10-30', '15:00', 'MA Kings', 'Ali Panthers'],
      ['10', '2026-10-31', '14:00', 'Adi Dolphins', 'US Lions'],
      ['11', '2026-11-01', '14:00', 'AB Knights', 'MA Kings'],
      ['12', '2026-11-02', '14:00', 'Ali Panthers', 'Adi Dolphins'],
      ['13', '2026-11-03', '14:00', 'Shazi Hawks', 'US Lions'],
      ['14', '2026-11-04', '14:00', 'AB Knights', 'Adi Dolphins'],
      ['15', '2026-11-05', '14:00', 'Ali Panthers', 'US Lions'],
    ];
    for (final f in league) {
      final id = 'ssl2_m${f[0]}';
      if (has(id)) continue;
      out.add(
        Match(
          id: id,
          tournamentId: defaultTournamentId,
          teamAId: tid(f[3]),
          teamBId: tid(f[4]),
          xiA: const [],
          xiB: const [],
          tossWinnerId: '',
          status: 'upcoming',
          stage: 'league',
          oversLimit: 10,
          ballsPerOver: 6,
          venue: defaultVenue,
          // Local match time as a plain string — never parsed as UTC,
          // so dates cannot shift across timezones.
          dateIso: '${f[1]}T${f[2]}:00',
          matchTitle: 'Match ${f[0]}',
          season: '2K26',
        ),
      );
    }
    // Playoff fixtures — teams stay TBD until qualification seeds them.
    const playoffs = [
      // id, stage, title, date, time
      ['ssl2_sf1', 'semifinal1', 'Semi Final 1', '2026-11-06', '15:00'],
      ['ssl2_sf2', 'semifinal2', 'Semi Final 2', '2026-11-07', '14:00'],
      ['ssl2_final', 'final', 'Grand Final', '2026-11-08', '14:00'],
    ];
    for (final p in playoffs) {
      if (has(p[0])) continue;
      out.add(
        Match(
          id: p[0],
          tournamentId: defaultTournamentId,
          teamAId: '',
          teamBId: '',
          xiA: const [],
          xiB: const [],
          tossWinnerId: '',
          status: 'upcoming',
          stage: p[1],
          oversLimit: 10,
          ballsPerOver: 6,
          venue: defaultVenue,
          dateIso: '${p[3]}T${p[4]}:00',
          matchTitle: p[2],
          season: '2K26',
        ),
      );
    }
    return out;
  }

  void _seedDefaultFixtures() {
    matches.addAll(buildDefaultFixtures(matches));
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

  /// Reset App (§29): explain → confirm (UI) → wipe user data → reseed
  /// defaults exactly once. Backups and exported files are left untouched.
  Future<void> resetApp() async {
    _seedFreshInstall();
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

  @override
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
