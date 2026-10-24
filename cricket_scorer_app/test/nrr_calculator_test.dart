import 'package:flutter_test/flutter_test.dart';
import 'package:cricket_scorer_app/models.dart';
import 'package:cricket_scorer_app/nrr_calculator.dart';
import 'package:cricket_scorer_app/scoring.dart';

// Teams: tx = the team, tr = the rival to overtake, tt = third team
// (the hypothetical opponent — its results only shape the base table).
const teamIds = ['tx', 'tr', 'tt'];
const quota = 120; // 20 overs x 6 balls

List<String> xi(String p) => [for (var i = 0; i < 11; i++) '$p$i'];

/// Completed match, hand-set figures (same pattern as nrr_test.dart):
/// [first] bats first against [second].
Match mk(
  String id,
  String first,
  String second,
  int r1,
  int w1,
  int b1,
  int r2,
  int w2,
  int b2,
) {
  final m = Match(
    id: id,
    tournamentId: 't1',
    teamAId: first,
    teamBId: second,
    xiA: xi(first),
    xiB: xi(second),
    oversLimit: 20,
    ballsPerOver: 6,
    tossWinnerId: first,
    tossDecision: 'bat',
    status: 'completed',
  );
  InningsState inn(String bat, String bowl, int r, int w, int b) {
    final s = InningsState(
      battingTeamId: bat,
      bowlingTeamId: bowl,
      battingXI: xi(bat),
      bowlingXI: xi(bowl),
      oversLimit: 20,
      ballsPerOver: 6,
    );
    s.totalRuns = r;
    s.wickets = w;
    s.legalBalls = b;
    return s;
  }

  m.innings.addAll([
    inn(first, second, r1, w1, b1),
    inn(second, first, r2, w2, b2),
  ]);
  return m;
}

/// Base table for the NRR-decided scenarios:
///  tx: 1 win (100 v 90)            -> 2 pts, NRR +0.50
///  tr: 2 wins (150 v 100, 140 v 110) -> 4 pts, NRR +2.00
/// After one more win tx has 4 pts = tr, so NRR decides.
List<Match> baseMatches() => [
      mk('b1', 'tx', 'tt', 100, 5, 120, 90, 9, 120),
      mk('b2', 'tr', 'tt', 150, 5, 120, 100, 9, 120),
      mk('b3', 'tr', 'tt', 140, 6, 120, 110, 8, 120),
    ];

PointsRow rowOf(List<Match> ms, String id) =>
    computePointsTable('t1', teamIds, ms).firstWhere((r) => r.teamId == id);

/// Strictly-ahead test, mirroring the calculator's semantics:
/// more points, or level points and NRR greater by > 1e-9.
bool ahead(PointsRow x, PointsRow r) =>
    x.points > r.points || (x.points == r.points && x.nrr > r.nrr + 1e-9);

void main() {
  group('defend (bats first)', () {
    test('calculator matches brute force over every opponent total', () {
      final base = baseMatches();
      final team = rowOf(base, 'tx');
      final rival = rowOf(base, 'tr');
      expect(team.points, 2);
      expect(rival.points, 4);
      expect(rival.nrr, closeTo(2.0, 1e-9));

      final res = runsMarginNeeded(
        team: team,
        rival: rival,
        teamScore: 150,
        oversQuotaBalls: quota,
        ballsPerOver: 6,
      );

      // Brute force: replay the hypothetical match for every legal
      // losing opponent total and recompute the real table.
      int? bruteMax;
      double? bruteNrr;
      for (var opp = 0; opp < 150; opp++) {
        final ms = [
          ...base,
          mk('h', 'tx', 'tt', 150, 5, 120, opp, 9, 120),
        ];
        if (ahead(rowOf(ms, 'tx'), rowOf(ms, 'tr'))) {
          bruteMax = opp;
          bruteNrr = rowOf(ms, 'tx').nrr;
        }
      }
      expect(bruteMax, isNotNull);
      expect(res.possible, isTrue);
      expect(res.maxOpponentRuns, bruteMax);
      expect(res.minMargin, 150 - bruteMax!);
      expect(res.resultingNrr, closeTo(bruteNrr!, 1e-9));
      // Hand-checked boundary: opp 79 passes, opp 80 does not.
      expect(res.maxOpponentRuns, 79);
      expect(res.minMargin, 71);
    });

    test('all-out first innings is deemed full quota (ICC rule)', () {
      final base = baseMatches();
      final res = runsMarginNeeded(
        team: rowOf(base, 'tx'),
        rival: rowOf(base, 'tr'),
        teamScore: 150,
        oversQuotaBalls: quota,
        ballsPerOver: 6,
        ballsFacedTeam: 90, // bowled out in 15 overs
        teamAllOut: true,
      );
      int? bruteMax;
      for (var opp = 0; opp < 150; opp++) {
        final ms = [
          ...base,
          mk('h', 'tx', 'tt', 150, 10, 90, opp, 9, 120),
        ];
        if (ahead(rowOf(ms, 'tx'), rowOf(ms, 'tr'))) bruteMax = opp;
      }
      expect(res.possible, isTrue);
      expect(res.maxOpponentRuns, bruteMax);
      expect(res.maxOpponentRuns, 79); // same as facing the full quota
    });

    test('impossible on points alone', () {
      // Rival has 6 points (3 wins); a win only takes tx to 4.
      final base = [
        ...baseMatches(),
        mk('b4', 'tr', 'tt', 160, 5, 120, 90, 9, 120),
      ];
      final res = runsMarginNeeded(
        team: rowOf(base, 'tx'),
        rival: rowOf(base, 'tr'),
        teamScore: 200,
        oversQuotaBalls: quota,
        ballsPerOver: 6,
      );
      expect(res.possible, isFalse);
      expect(res.maxOpponentRuns, isNull);
      expect(res.verdict, contains('Points'));
    });

    test('already ahead on points after any win: margin is 1 run', () {
      // tx already on 4 points; rival only 2 -> any win settles it.
      final base = [
        mk('b1', 'tx', 'tt', 100, 5, 120, 90, 9, 120),
        mk('b2', 'tx', 'tt', 120, 5, 120, 80, 9, 120),
        mk('b3', 'tr', 'tt', 200, 5, 120, 50, 9, 120),
      ];
      final res = runsMarginNeeded(
        team: rowOf(base, 'tx'),
        rival: rowOf(base, 'tr'),
        teamScore: 90,
        oversQuotaBalls: quota,
        ballsPerOver: 6,
      );
      expect(res.possible, isTrue);
      expect(res.minMargin, 1);
      expect(res.maxOpponentRuns, 89);
    });

    test('impossible even bowling the opponent out for 0', () {
      // Rival NRR +7.00 from two huge wins; tx posts only 80.
      final base = [
        mk('b1', 'tx', 'tt', 60, 5, 120, 50, 9, 120),
        mk('b2', 'tr', 'tt', 200, 5, 120, 50, 9, 120),
        mk('b3', 'tr', 'tt', 190, 5, 120, 60, 9, 120),
      ];
      final team = rowOf(base, 'tx');
      final rival = rowOf(base, 'tr');
      expect(rival.nrr, closeTo(7.0, 1e-9));
      final res = runsMarginNeeded(
        team: team,
        rival: rival,
        teamScore: 80,
        oversQuotaBalls: quota,
        ballsPerOver: 6,
      );
      expect(res.possible, isFalse);
      expect(res.maxOpponentRuns, isNull);
      // Brute force agrees: no losing opponent total puts tx ahead.
      for (var opp = 0; opp < 80; opp++) {
        final ms = [...base, mk('h', 'tx', 'tt', 80, 5, 120, opp, 9, 120)];
        expect(ahead(rowOf(ms, 'tx'), rowOf(ms, 'tr')), isFalse);
      }
    });

    test('input rows are not mutated', () {
      final base = baseMatches();
      final team = rowOf(base, 'tx');
      runsMarginNeeded(
        team: team,
        rival: rowOf(base, 'tr'),
        teamScore: 150,
        oversQuotaBalls: quota,
        ballsPerOver: 6,
      );
      expect(team.played, 1);
      expect(team.points, 2);
      expect(team.runsFor, 100);
    });
  });

  group('chase', () {
    test('calculator matches brute force over every chase length', () {
      final base = baseMatches();
      final team = rowOf(base, 'tx');
      final rival = rowOf(base, 'tr');

      final res = chaseLatestBalls(
        team: team,
        rival: rival,
        target: 131,
        oversQuotaBalls: quota,
        ballsPerOver: 6,
        oppScore: 130,
        oppBallsFaced: 120,
      );

      int? bruteLatest;
      double? bruteNrr;
      for (var balls = 1; balls <= quota; balls++) {
        final ms = [
          ...base,
          mk('h', 'tt', 'tx', 130, 8, 120, 131, 3, balls),
        ];
        if (ahead(rowOf(ms, 'tx'), rowOf(ms, 'tr'))) {
          bruteLatest = balls;
          bruteNrr = rowOf(ms, 'tx').nrr;
        }
      }
      expect(bruteLatest, isNotNull);
      expect(res.possible, isTrue);
      expect(res.latestChaseBalls, bruteLatest);
      expect(res.resultingNrr, closeTo(bruteNrr!, 1e-9));
      // Hand-checked boundary: ball 64 passes, ball 65 does not.
      expect(res.latestChaseBalls, 64);
    });

    test('chase impossible on points alone', () {
      final base = [
        ...baseMatches(),
        mk('b4', 'tr', 'tt', 160, 5, 120, 90, 9, 120),
      ];
      final res = chaseLatestBalls(
        team: rowOf(base, 'tx'),
        rival: rowOf(base, 'tr'),
        target: 100,
        oversQuotaBalls: quota,
        ballsPerOver: 6,
        oppScore: 99,
        oppBallsFaced: 120,
      );
      expect(res.possible, isFalse);
      expect(res.latestChaseBalls, isNull);
    });

    test('chase: any win enough when points already settle it', () {
      final base = [
        mk('b1', 'tx', 'tt', 100, 5, 120, 90, 9, 120),
        mk('b2', 'tx', 'tt', 120, 5, 120, 80, 9, 120),
        mk('b3', 'tr', 'tt', 200, 5, 120, 50, 9, 120),
      ];
      final res = chaseLatestBalls(
        team: rowOf(base, 'tx'),
        rival: rowOf(base, 'tr'),
        target: 75,
        oversQuotaBalls: quota,
        ballsPerOver: 6,
        oppScore: 74,
        oppBallsFaced: 120,
      );
      expect(res.possible, isTrue);
      expect(res.latestChaseBalls, quota); // may use the full quota
    });
  });

  group('ballsFromOversText', () {
    test('parses cricket overs notation', () {
      expect(ballsFromOversText('8', 6), 48);
      expect(ballsFromOversText('8.0', 6), 48);
      expect(ballsFromOversText('7.3', 6), 45);
      expect(ballsFromOversText(' 20 ', 6), 120);
      expect(ballsFromOversText('7.6', 6), isNull);
      expect(ballsFromOversText('7.25', 6), isNull);
      expect(ballsFromOversText('', 6), isNull);
      expect(ballsFromOversText('abc', 6), isNull);
      expect(ballsFromOversText('-3', 6), isNull);
    });
  });
}
