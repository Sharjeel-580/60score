import 'package:flutter_test/flutter_test.dart';
import 'package:cricket_scorer_app/models.dart';
import 'package:cricket_scorer_app/scoring.dart';
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
    required this._matches,
  });

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

// The app ships with zero seeded content, so the tests build their own
// tournament, teams and fixtures — nothing comes from Store defaults.
const _tournamentId = 'cup_1';
const _tids = ['team_0', 'team_1', 'team_2', 'team_3', 'team_4', 'team_5'];
const _teamNames = ['Alpha', 'Bravo', 'Comets', 'Dynamos', 'Eagles', 'Falcons'];

Tournament _tournament() => Tournament(
  id: _tournamentId,
  name: 'Test Cup',
  teamIds: List.of(_tids),
  venue: 'Test Ground',
);

List<Team> _teams() => [
  for (var i = 0; i < 6; i++) Team(id: _tids[i], name: _teamNames[i]),
];

Match _fixture({
  required String id,
  required String a,
  required String b,
  required String stage,
  String title = '',
}) {
  return Match(
    id: id,
    tournamentId: _tournamentId,
    teamAId: a,
    teamBId: b,
    xiA: const [],
    xiB: const [],
    tossWinnerId: '',
    status: 'upcoming',
    stage: stage,
    oversLimit: 10,
    ballsPerOver: 6,
    venue: 'Test Ground',
    dateIso: '2026-10-22T14:00:00',
    matchTitle: title,
  );
}

/// A full fixture list for the test tournament: a 15-match round-robin
/// league (every pair of the 6 teams once) + 2 semifinals + the final,
/// with playoff teams TBD — the same structure a user would create by
/// hand in the app.
List<Match> _fixtures() {
  final out = <Match>[];
  var n = 0;
  for (var i = 0; i < _tids.length; i++) {
    for (var j = i + 1; j < _tids.length; j++) {
      n++;
      out.add(
        _fixture(
          id: 'lg${n.toString().padLeft(2, '0')}',
          a: _tids[i],
          b: _tids[j],
          stage: 'league',
          title: 'Match $n',
        ),
      );
    }
  }
  out.add(
    _fixture(
      id: 'sf1',
      a: '',
      b: '',
      stage: 'semifinal1',
      title: 'Semi Final 1',
    ),
  );
  out.add(
    _fixture(
      id: 'sf2',
      a: '',
      b: '',
      stage: 'semifinal2',
      title: 'Semi Final 2',
    ),
  );
  out.add(
    _fixture(id: 'fin', a: '', b: '', stage: 'final', title: 'Grand Final'),
  );
  return out;
}

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
    tournamentId: _tournamentId,
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
          id: 'play1',
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
          id: 'r1',
          a: _tids[0],
          b: _tids[1],
          aRuns: 100,
          aWkts: 5,
          aBalls: 60,
          bRuns: 99,
          bWkts: 9,
          bBalls: 60,
        ),
        // C crushes D
        leagueResult(
          id: 'r2',
          a: _tids[2],
          b: _tids[3],
          aRuns: 150,
          aWkts: 2,
          aBalls: 60,
          bRuns: 60,
          bWkts: 10,
          bBalls: 40,
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
      final fixtures = _fixtures();
      // Add every fixture unless the test overrode it.
      for (final f in fixtures) {
        if (league.every((m) => m.id != f.id)) league.add(f);
      }
      return FakeStore(
        teams: _teams(),
        tournaments: [_tournament()],
        matches: league,
      );
    }

    test('top 4 qualify; SF1 = 1v4, SF2 = 2v3', () async {
      // Complete every league fixture with teamA winning.
      final store = setup([]);
      for (final m
          in store.matches.where((m) => m.stage == 'league').toList()) {
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
      final update = await applyPlayoffUpdate(store, _tournamentId);
      expect(update.changed, isTrue);
      expect(update.finalQualifiers.length, 4);
      final t = store.tournamentById(_tournamentId)!;
      expect(t.qualificationFinalized, isTrue);

      final sf1 = store.matches.firstWhere((m) => m.id == 'sf1');
      final sf2 = store.matches.firstWhere((m) => m.id == 'sf2');
      // 1v4 and 2v3 in rank order
      expect(sf1.teamAId, update.finalQualifiers[0]);
      expect(sf1.teamBId, update.finalQualifiers[3]);
      expect(sf2.teamAId, update.finalQualifiers[1]);
      expect(sf2.teamBId, update.finalQualifiers[2]);
    });

    test('semifinal winners enter the grand final slots', () async {
      final store = setup([]);
      // Finalize league quickly: mark all completed via noResult-free wins.
      for (final m
          in store.matches.where((m) => m.stage == 'league').toList()) {
        m.status = 'completed';
        m.innings.addAll([
          InningsState(
              battingTeamId: m.teamAId,
              bowlingTeamId: m.teamBId,
              battingXI: const [],
              bowlingXI: const [],
              oversLimit: 10,
              ballsPerOver: 6,
            )
            ..totalRuns = 100
            ..legalBalls = 60,
          InningsState(
              battingTeamId: m.teamBId,
              bowlingTeamId: m.teamAId,
              battingXI: const [],
              bowlingXI: const [],
              oversLimit: 10,
              ballsPerOver: 6,
            )
            ..totalRuns = 90
            ..legalBalls = 60,
        ]);
      }
      var update = await applyPlayoffUpdate(store, _tournamentId);
      expect(update.finalQualifiers.length, 4);

      // Complete SF1: teamA wins.
      final sf1 = store.matches.firstWhere((m) => m.id == 'sf1');
      sf1.status = 'completed';
      sf1.innings.addAll([
        InningsState(
            battingTeamId: sf1.teamAId,
            bowlingTeamId: sf1.teamBId,
            battingXI: const [],
            bowlingXI: const [],
            oversLimit: 10,
            ballsPerOver: 6,
          )
          ..totalRuns = 140
          ..legalBalls = 60,
        InningsState(
            battingTeamId: sf1.teamBId,
            bowlingTeamId: sf1.teamAId,
            battingXI: const [],
            bowlingXI: const [],
            oversLimit: 10,
            ballsPerOver: 6,
          )
          ..totalRuns = 120
          ..legalBalls = 60,
      ]);
      update = await applyPlayoffUpdate(store, _tournamentId);
      final fin = store.matches.firstWhere((m) => m.id == 'fin');
      expect(fin.teamAId, sf1.teamAId); // SF1 winner -> slot A
      expect(fin.teamBId, isEmpty); // SF2 unfinished -> slot B stays TBD
    });

    test('started playoffs are never reseeded', () async {
      final store = setup([]);
      for (final m
          in store.matches.where((m) => m.stage == 'league').toList()) {
        m.status = 'completed';
      }
      await applyPlayoffUpdate(store, _tournamentId);
      final sf1 = store.matches.firstWhere((m) => m.id == 'sf1');
      final seededA = sf1.teamAId;
      sf1.status = 'live'; // semifinal underway
      // A correction now changes the table...
      final update = await applyPlayoffUpdate(store, _tournamentId);
      expect(sf1.teamAId, seededA); // ...but the started semi is untouched
      expect(update.needsConfirmation || !update.changed, isTrue);
    });

    test('provisional qualifiers are conservative', () {
      // Team 0 has max points already; others can still catch up on points
      // except team 5 which cannot reach top 4.
      final table = [for (var i = 0; i < 6; i++) PointsRow(_tids[i])];
      table[0].points = 20; // unbeatable
      final upcoming = <Match>[];
      final q = guaranteedQualifiers(table, upcoming);
      expect(q, contains(_tids[0]));
    });

    test('Super 4: incomplete league leaves semifinal slots TBA', () async {
      final store = setup([]);
      // Complete every league fixture except one.
      final league =
          store.matches.where((m) => m.stage == 'league').toList();
      for (var i = 0; i < league.length - 1; i++) {
        final m = league[i];
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
      final update = await applyPlayoffUpdate(store, _tournamentId);
      expect(update.changed, isFalse);
      expect(
        store.tournamentById(_tournamentId)!.qualificationFinalized,
        isFalse,
      );
      final sf1 = store.matches.firstWhere((m) => m.id == 'sf1');
      final sf2 = store.matches.firstWhere((m) => m.id == 'sf2');
      expect(sf1.teamAId, isEmpty);
      expect(sf1.teamBId, isEmpty);
      expect(sf2.teamAId, isEmpty);
      expect(sf2.teamBId, isEmpty);
    });

    test('Super 4: noResult league matches count as terminal', () async {
      final store = setup([]);
      for (final m
          in store.matches.where((m) => m.stage == 'league').toList()) {
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
          status: 'noResult',
        );
        store.matches.remove(m);
        store.matches.add(res);
      }
      final update = await applyPlayoffUpdate(store, _tournamentId);
      expect(update.changed, isTrue);
      expect(update.finalQualifiers.length, 4);
      final sf1 = store.matches.firstWhere((m) => m.id == 'sf1');
      final sf2 = store.matches.firstWhere((m) => m.id == 'sf2');
      expect(sf1.teamAId, update.finalQualifiers[0]);
      expect(sf1.teamBId, update.finalQualifiers[3]);
      expect(sf2.teamAId, update.finalQualifiers[1]);
      expect(sf2.teamBId, update.finalQualifiers[2]);
    });

    test('Super 4: cancelled league matches do NOT trigger auto-fill',
        () async {
      final store = setup([]);
      // Complete every league fixture except one, which is cancelled.
      final league =
          store.matches.where((m) => m.stage == 'league').toList();
      for (var i = 0; i < league.length - 1; i++) {
        final m = league[i];
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
      final cancelled = league.last;
      final cancelledRes = leagueResult(
        id: cancelled.id,
        a: cancelled.teamAId,
        b: cancelled.teamBId,
        aRuns: 0,
        aWkts: 0,
        aBalls: 0,
        bRuns: 0,
        bWkts: 0,
        bBalls: 0,
        status: 'cancelled',
      );
      store.matches.remove(cancelled);
      store.matches.add(cancelledRes);
      final update = await applyPlayoffUpdate(store, _tournamentId);
      expect(update.changed, isFalse);
      expect(
        store.tournamentById(_tournamentId)!.qualificationFinalized,
        isFalse,
      );
      final sf1 = store.matches.firstWhere((m) => m.id == 'sf1');
      final sf2 = store.matches.firstWhere((m) => m.id == 'sf2');
      expect(sf1.teamAId, isEmpty);
      expect(sf1.teamBId, isEmpty);
      expect(sf2.teamAId, isEmpty);
      expect(sf2.teamBId, isEmpty);
    });

    test('Super 4: filled slots are never auto-overwritten', () async {
      final store = setup([]);
      Future<void> completeLeague({required bool bWins}) async {
        for (final m
            in store.matches.where((m) => m.stage == 'league').toList()) {
          final res = leagueResult(
            id: m.id,
            a: m.teamAId,
            b: m.teamBId,
            aRuns: bWins ? 120 : 130,
            aWkts: 4,
            aBalls: 60,
            bRuns: bWins ? 130 : 120,
            bWkts: 7,
            bBalls: 60,
          );
          store.matches.remove(m);
          store.matches.add(res);
        }
      }

      await completeLeague(bWins: false);
      final first = await applyPlayoffUpdate(store, _tournamentId);
      expect(first.changed, isTrue);
      final sf1 = store.matches.firstWhere((m) => m.id == 'sf1');
      final sf2 = store.matches.firstWhere((m) => m.id == 'sf2');
      final sf1A = sf1.teamAId;
      final sf1B = sf1.teamBId;
      final sf2A = sf2.teamAId;
      final sf2B = sf2.teamBId;
      expect(sf1A, isNotEmpty);
      // Reverse every result: the final table flips, but the filled
      // slots must stick even on a forced correction pass.
      await completeLeague(bWins: true);
      await applyPlayoffUpdate(store, _tournamentId, force: true);
      expect(
        store.tournamentById(_tournamentId)!.qualifiedTeamIds,
        isNot(equals(first.finalQualifiers)),
      );
      expect(sf1.teamAId, sf1A);
      expect(sf1.teamBId, sf1B);
      expect(sf2.teamAId, sf2A);
      expect(sf2.teamBId, sf2B);
    });
  });
}
