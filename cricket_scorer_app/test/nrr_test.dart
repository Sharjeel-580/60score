import 'package:flutter_test/flutter_test.dart';
import 'package:cricket_scorer_app/models.dart';
import 'package:cricket_scorer_app/scoring.dart';

/// Build a completed match with hand-set innings figures (no engine).
Match fixture({
  required String id,
  required int aRuns,
  required int aWkts,
  required int aBalls,
  required int bRuns,
  required int bWkts,
  required int bBalls,
  int overs = 20,
  String status = 'completed',
  bool aBatsFirst = true,
}) {
  final m = Match(
    id: id,
    tournamentId: 't1',
    teamAId: 'ta',
    teamBId: 'tb',
    xiA: [for (var i = 0; i < 11; i++) 'a$i'],
    xiB: [for (var i = 0; i < 11; i++) 'b$i'],
    oversLimit: overs,
    ballsPerOver: 6,
    tossWinnerId: 'ta',
    tossDecision: 'bat',
    status: status,
  );
  InningsState inn(
    String bat,
    String bowl,
    int runs,
    int wkts,
    int balls,
    List<String> xi,
  ) {
    final s = InningsState(
      battingTeamId: bat,
      bowlingTeamId: bowl,
      battingXI: xi,
      bowlingXI: xi == m.xiA ? m.xiB : m.xiA,
      oversLimit: overs,
      ballsPerOver: 6,
    );
    s.totalRuns = runs;
    s.wickets = wkts;
    s.legalBalls = balls;
    return s;
  }

  final first = aBatsFirst
      ? inn('ta', 'tb', aRuns, aWkts, aBalls, m.xiA)
      : inn('tb', 'ta', bRuns, bWkts, bBalls, m.xiB);
  final second = aBatsFirst
      ? inn('tb', 'ta', bRuns, bWkts, bBalls, m.xiB)
      : inn('ta', 'tb', aRuns, aWkts, aBalls, m.xiA);
  m.innings.addAll([first, second]);
  return m;
}

void main() {
  group('ICC NRR', () {
    test('all-out side is deemed to have faced full quota; chase counts actual overs', () {
      // A all out for 100 in 15 overs (20-over match); B chases 101 in 10 overs.
      final m = fixture(
        id: 'm1',
        aRuns: 100,
        aWkts: 10,
        aBalls: 90,
        bRuns: 101,
        bWkts: 2,
        bBalls: 60,
      );
      final rows = computePointsTable('t1', ['ta', 'tb'], [m]);
      final a = rows.firstWhere((r) => r.teamId == 'ta');
      final b = rows.firstWhere((r) => r.teamId == 'tb');
      // A: scored 100 off deemed 120 balls = 5.00/over; conceded 101 off 60 = 10.10
      expect(a.nrr, closeTo(5.0 - 10.1, 1e-9));
      expect(b.nrr, closeTo(10.1 - 5.0, 1e-9));
      expect(b.points, 2);
      expect(a.points, 0);
      expect(rows.first.teamId, 'tb');
    });

    test('aggregate method across matches (not average of match NRRs)', () {
      // M1: A 200 off 120; B all out 100 off 60 (deemed 120) -> A wins by 100
      final m1 = fixture(
        id: 'm1',
        aRuns: 200,
        aWkts: 5,
        aBalls: 120,
        bRuns: 100,
        bWkts: 10,
        bBalls: 60,
      );
      // M2: B bats first 61 off 30 balls... use aBatsFirst=false:
      // B 61/30, A all out 60 off 30 (deemed 120) -> B wins
      final m2 = fixture(
        id: 'm2',
        aRuns: 60,
        aWkts: 10,
        aBalls: 30,
        bRuns: 61,
        bWkts: 1,
        bBalls: 30,
        aBatsFirst: false,
      );
      final rows = computePointsTable('t1', ['ta', 'tb'], [m1, m2]);
      final a = rows.firstWhere((r) => r.teamId == 'ta');
      // A aggregate: runsFor 260 / 240 balls = 6.50 ov rate
      //              runsAgainst 161 / (120 + 30) = 150 balls = 6.44
      expect(a.runsFor, 260);
      expect(a.ballsFor, 240);
      expect(a.runsAgainst, 161);
      expect(a.ballsAgainst, 150);
      expect(a.nrr, closeTo(6.5 - 6.44, 1e-9));
      expect(a.points, 2); // one win each
      expect(a.won, 1);
      expect(a.lost, 1);
    });

    test('no-result: 1 point each and no NRR effect', () {
      final nr = Match(
        id: 'nr',
        tournamentId: 't1',
        teamAId: 'ta',
        teamBId: 'tb',
        xiA: const [],
        xiB: const [],
        tossWinnerId: 'ta',
        status: 'noResult',
      );
      final rows = computePointsTable('t1', ['ta', 'tb'], [nr]);
      expect(rows.every((r) => r.points == 1 && r.noResult == 1), isTrue);
      expect(rows.every((r) => r.nrr == 0 && r.runsFor == 0), isTrue);
    });

    test('tie: 1 point each', () {
      final m = fixture(
        id: 'm1',
        aRuns: 120,
        aWkts: 6,
        aBalls: 120,
        bRuns: 120,
        bWkts: 8,
        bBalls: 120,
      );
      final rows = computePointsTable('t1', ['ta', 'tb'], [m]);
      expect(rows.every((r) => r.points == 1 && r.tied == 1), isTrue);
    });

    test('manual points adjustment is applied', () {
      final m = fixture(
        id: 'm1',
        aRuns: 150,
        aWkts: 5,
        aBalls: 120,
        bRuns: 100,
        bWkts: 9,
        bBalls: 120,
      );
      final rows = computePointsTable(
        't1',
        ['ta', 'tb'],
        [m],
        pointsAdjustments: {'tb': 3},
      );
      final b = rows.firstWhere((r) => r.teamId == 'tb');
      expect(b.points, 3);
      expect(rows.first.teamId, 'tb'); // adjustment lifts B above A (2 pts)
    });
  });
}
