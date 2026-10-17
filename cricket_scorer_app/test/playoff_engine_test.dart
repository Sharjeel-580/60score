import 'package:flutter_test/flutter_test.dart';
import 'package:cricket_scorer_app/models.dart';
import 'package:cricket_scorer_app/scoring.dart';
import 'package:cricket_scorer_app/store.dart';
import 'package:cricket_scorer_app/tournament_engine.dart';

/// In-memory PlayoffStore for engine tests (no SharedPreferences).
class FakeStore implements PlayoffStore {
  final List<Team> teams;
  final List<Tournament> tournaments;
  final List<Match> _matches;
  int persistCalls = 0;

  FakeStore({
    required this.teams,
    required this.tournaments,
    required List<Match> matches,
  }) : _matches = matches;

  @override
  Tournament? tournamentById(String? id) {
    for (final t in tournaments) {
      if (t.id == id) return t;
    }
    return null;
  }

  @override
  String teamName(String id) {
    if (id.isEmpty) return 'TBD';
    for (final t in teams) {
      if (t.id == id) return t.name;
    }
    return 'Unknown';
  }

  @override
  List<Match> get matches => _matches;

  @override
  Future<void> persist() async {
    persistCalls++;
  }
}

const _tids = [
  'seed_team_0', // AB Knights
  'seed_team_1', // Shazi Hawks
  'seed_team_2', // MA Kings
  'seed_team_3', // Ali Panthers
  'seed_team_4', // Adi Dolphins
  'seed_team_5', // US Lions
];

Tournament _tournament() => Tournament(
  id: Store.defaultTournamentId,
  name: Store.defaultTournamentName,
  teamIds: List.of(_tids),
  venue: Store.defaultVenue,
);

List<Team> _teams() => [
  for (var i = 0; i < 6; i++)
    Team(id: _tids[i], name: Store.defaultTeamNames[i]),
];

/// Completed league match with hand-set innings figures.
Match leagueResult({
  required String id,
  required String a,
  required String b,
  required int aRuns,
  required int aWkts,
  required int aBalls,
  required int bRuns,
  required int bWkts,
  required int bBalls,
  int overs = 10,
  String status = 'completed',
}) {
  final m = Match(
    id: id,
    tournamentId: Store.defaultTournamentId,
    teamAId: a,
    teamBId: b,
    xiA: const [],
    xiB: const [],
    oversLimit: overs,
    ballsPerOver: 6,
    tossWinnerId: a,
    tossDecision: 'bat',
    status: status,
    stage: 'league',
  );
  InningsState inn(String bat, String bowl, int runs, int wkts, int balls) {
    final s = InningsState(
      battingTeamId: bat,
      bowlingTeamId: bowl,
      battingXI: const [],
      bowlingXI: const [],
      oversLimit: overs,
      ballsPerOver: 6,
    );
    s.totalRuns = runs;
    s.wickets = wkts;
    s.legalBalls = balls;
    return s;
  }

  m.innings.addAll([
    inn(a, b, aRuns, aWkts, aBalls),
    inn(b, a, bRuns, bWkts, bBalls),
  ]);
  return m;
}

void main() {
  group('Default fixture seeding', () {
    test('builds exactly 18 fixtures: 15 league + 3 playoffs', () {
      final fixtures = Store.buildDefaultFixtures([]);
      expect(fixtures.length, 18);
      expect(
        fixtures.where((m) => m.stage == 'league').length,
        15,
      );
      expect(
        fixtures.where((m) => m.stage != 'league').length,
        3,
      );
    });

    test('league fixtures match the official schedule', () {
      final fixtures = Store.buildDefaultFixtures([]);
      Match byId(String id) => fixtures.firstWhere((m) => m.id == id);
      // Spot-check spec rows: (id, date, time, teamA, teamB)
      final checks = {
        'ssl2_m01': ['2026-10-22T14:00:00', 'seed_team_1', 'seed_team_4'],
        'ssl2_m02': ['2026-10-23T15:00:00', 'seed_team_0', 'seed_team_3'],
        'ssl2_m08': ['2026-10-29T14:00:00', 'seed_team_0', 'seed_team_1'],
        'ssl2_m15': ['2026-11-05T14:00:00', 'seed_team_3', 'seed_team_5'],
      };
      checks.forEach((id, v) {
        final m = byId(id);
        expect(m.dateIso, v[0], reason: '$id date/time');
        expect(m.teamAId, v[1], reason: '$id teamA');
        expect(m.teamBId, v[2], reason: '$id teamB');
        expect(m.venue, Store.defaultVenue);
        expect(m.status, 'upcoming');
        expect(m.tournamentId, Store.defaultTournamentId);
      });
    });

    test('dates are plain local strings (no UTC shift possible)', () {
      final fixtures = Store.buildDefaultFixtures([]);
      for (final m in fixtures) {
        expect(m.dateIso.contains('T'), isTrue);
        expect(m.dateIso.endsWith('Z'), isFalse);
        expect(m.dateIso.contains('+'), isFalse);
      }
    });

    test('playoff fixtures start with TBD teams', () {
      final fixtures = Store.buildDefaultFixtures([]);
      final sf1 = fixtures.firstWhere((m) => m.id == 'ssl2_sf1');
      final sf2 = fixtures.firstWhere((m) => m.id == 'ssl2_sf2');
      final fin = fixtures.firstWhere((m) => m.id == 'ssl2_final');
      expect(sf1.stage, 'semifinal1');
      expect(sf1.dateIso, '2026-11-06T15:00:00');
      expect(sf2.dateIso, '2026-11-07T14:00:00');
      expect(fin.dateIso, '2026-11-08T14:00:00');
      for (final m in [sf1, sf2, fin]) {
        expect(m.teamAId, isEmpty);
        expect(m.teamBId, isEmpty);
        expect(m.status, 'upcoming');
      }
    });

    test('seeding is idempotent (no duplicates on re-run)', () {
      final first = Store.buildDefaultFixtures([]);
      final second = Store.buildDefaultFixtures(first);
      expect(second, isEmpty);
    });
  });

  group('League points table', () {
    test('derives from results; playoff matches excluded', () {
      final t = _tournament();
      final matches = [
        leagueResult(
          id: 'r1',
          a: _tids[0],
          b: _tids[1],
          aRuns: 120,
          aWkts: 4,
          aBalls: 60,
          bRuns: 100,
          bWkts: 8,
          bBalls: 60,
        ),
        // A playoff match must NOT pollute the league table.
        leagueResult(
          id: 'ssl2_sf1',
          a: _tids[2],
          b: _tids[3],
          aRuns: 200,
          aWkts: 2,
          aBalls: 60,
          bRuns: 50,
          bWkts: 10,
          bBalls: 30,
        )..stage = 'semifinal1',
      ];
      final table = leaguePointsTable(t, matches);
      final a = table.firstWhere((r) => r.teamId == _tids[0]);
      final b = table.firstWhere((r) => r.teamId == _tids[1]);
      expect(a.points, 2);
      expect(b.points, 0);
      // teams 2 and 3 played only the (excluded) playoff match
      final c = table.firstWhere((r) => r.teamId == _tids[2]);
      expect(c.played, 0);
      expect(table.first.teamId, _tids[0]);
    });

    test('tie on points is broken by NRR, not invented', () {
      final t = _tournament();
      final matches = [
        // A beats B narrowly
        leagueResult(
          id: 'r1', a: _tids[0], b: _tids[1],
          aRuns: 100, aWkts: 5, aBalls: 60,
          bRuns: 99, bWkts: 9, bBalls: 60,
        ),
        // C crushes D
        leagueResult(
          id: 'r2', a: _tids[2], b: _tids[3],
          aRuns: 150, aWkts: 2, aBalls: 60,
          bRuns: 60, bWkts: 10, bBalls: 40,
        ),
      ];
      final table = leaguePointsTable(t, matches);
      // A and C both on 2 points; C's NRR is far better.
      expect(table[0].teamId, _tids[2]);
      expect(table[1].teamId, _tids[0]);
      expect(table[0].nrr, greaterThan(table[1].nrr));
    });
  });

  group('Automatic qualification', () {
    FakeStore setup(List<Match> league) {
      final fixtures = Store.buildDefaultFixtures([]);
      // Mark every league fixture completed unless the test overrode it.
      for (final f in fixtures.where((m) => m.stage == 'league')) {
        if (league.every((m) => m.id != f.id)) league.add(f);
      }
      return FakeStore(
        teams: _teams(),
        tournaments: [_tournament()],
        matches: league,
      );
    }

    test('top 4 qualify; SF1 = 1v4, SF2 = 2v3', () async {
      // Complete every seeded league fixture with teamA winning.
      final store = setup([]);
      for (final m in store.matches.where((m) => m.stage == 'league')) {
        final res = leagueResult(
          id: m.id,
          a: m.teamAId,
          b: m.teamBId,
          aRuns: 130,
          aWkts: 4,
          aBalls: 60,
          bRuns: 120,
          bWkts: 7,
          bBalls: 60,
        );
        store.matches.remove(m);
        store.matches.add(res);
      }
      final update = await applyPlayoffUpdate(store, Store.defaultTournamentId);
      expect(update.changed, isTrue);
      expect(update.finalQualifiers.length, 4);
      final t = store.tournamentById(Store.defaultTournamentId)!;
      expect(t.qualificationFinalized, isTrue);

      final sf1 = store.matches.firstWhere((m) => m.id == 'ssl2_sf1');
      final sf2 = store.matches.firstWhere((m) => m.id == 'ssl2_sf2');
      // 1v4 and 2v3 in rank order
      expect(sf1.teamAId, update.finalQualifiers[0]);
      expect(sf1.teamBId, update.finalQualifiers[3]);
      expect(sf2.teamAId, update.finalQualifiers[1]);
      expect(sf2.teamBId, update.finalQualifiers[2]);
    });

    test('semifinal winners enter the grand final slots', () async {
      final store = setup([]);
      // Finalize league quickly: mark all completed via noResult-free wins.
      for (final m in store.matches.where((m) => m.stage == 'league')) {
        m.status = 'completed';
        m.innings.addAll([
          InningsState(
            battingTeamId: m.teamAId,
            bowlingTeamId: m.teamBId,
            battingXI: const [],
            bowlingXI: const [],
            oversLimit: 10,
            ballsPerOver: 6,
          )..totalRuns = 100
           ..legalBalls = 60,
          InningsState(
            battingTeamId: m.teamBId,
            bowlingTeamId: m.teamAId,
            battingXI: const [],
            bowlingXI: const [],
            oversLimit: 10,
            ballsPerOver: 6,
          )..totalRuns = 90
           ..legalBalls = 60,
        ]);
      }
      var update = await applyPlayoffUpdate(store, Store.defaultTournamentId);
      expect(update.finalQualifiers.length, 4);

      // Complete SF1: teamA wins.
      final sf1 = store.matches.firstWhere((m) => m.id == 'ssl2_sf1');
      sf1.status = 'completed';
      sf1.innings.addAll([
        InningsState(
          battingTeamId: sf1.teamAId,
          bowlingTeamId: sf1.teamBId,
          battingXI: const [],
          bowlingXI: const [],
          oversLimit: 10,
          ballsPerOver: 6,
        )..totalRuns = 140
         ..legalBalls = 60,
        InningsState(
          battingTeamId: sf1.teamBId,
          bowlingTeamId: sf1.teamAId,
          battingXI: const [],
          bowlingXI: const [],
          oversLimit: 10,
          ballsPerOver: 6,
        )..totalRuns = 120
         ..legalBalls = 60,
      ]);
      update = await applyPlayoffUpdate(store, Store.defaultTournamentId);
      final fin = store.matches.firstWhere((m) => m.id == 'ssl2_final');
      expect(fin.teamAId, sf1.teamAId); // SF1 winner -> slot A
      expect(fin.teamBId, isEmpty); // SF2 unfinished -> slot B stays TBD
    });

    test('started playoffs are never reseeded', () async {
      final store = setup([]);
      for (final m in store.matches.where((m) => m.stage == 'league')) {
        m.status = 'completed';
      }
      await applyPlayoffUpdate(store, Store.defaultTournamentId);
      final sf1 = store.matches.firstWhere((m) => m.id == 'ssl2_sf1');
      final seededA = sf1.teamAId;
      sf1.status = 'live'; // semifinal underway
      // A correction now changes the table...
      final update = await applyPlayoffUpdate(store, Store.defaultTournamentId);
      expect(sf1.teamAId, seededA); // ...but the started semi is untouched
      expect(update.needsConfirmation || !update.changed, isTrue);
    });

    test('provisional qualifiers are conservative', () {
      final t = _tournament();
      // Team 0 has max points already; others can still catch up on points
      // except team 5 which cannot reach top 4.
      final table = [
        for (var i = 0; i < 6; i++) PointsRow(_tids[i]),
      ];
      table[0].points = 20; // unbeatable
      final upcoming = <Match>[];
      final q = guaranteedQualifiers(table, upcoming);
      expect(q, contains(_tids[0]));
    });
  });
}
