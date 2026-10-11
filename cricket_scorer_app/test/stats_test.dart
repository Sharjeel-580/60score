import 'package:flutter_test/flutter_test.dart';
import 'package:cricket_scorer_app/models.dart';
import 'package:cricket_scorer_app/scoring.dart';

Match playedMatch() {
  // 1-over match, XI of 3. Team A: 8/1. Team B: 9/0 chase.
  final m = Match(
    id: 'm1',
    tournamentId: 't1',
    teamAId: 'ta',
    teamBId: 'tb',
    xiA: ['a1', 'a2', 'a3'],
    xiB: ['b1', 'b2', 'b3'],
    oversLimit: 1,
    ballsPerOver: 6,
    tossWinnerId: 'ta',
    tossDecision: 'bat',
  );
  final i1 = startInnings(m, 1);
  setOpeners(i1, 'a1', 'a2', 'b1');
  applyBall(i1, BallInput(batRuns: 4));
  applyBall(i1, BallInput(batRuns: 2));
  applyBall(
    i1,
    BallInput(isWicket: true, wicketType: 'caught', fielderId: 'b2'),
  );
  setNextBatter(i1, 'a3');
  applyBall(
    i1,
    BallInput(batRuns: 1),
  ); // a3 scores, a2 crosses? a3 on strike scores 1 -> swap
  applyBall(i1, BallInput(batRuns: 1)); // a2 scores 1
  applyBall(i1, BallInput(batRuns: 0));
  expect(i1.isComplete, isTrue);
  expect(i1.totalRuns, 8);

  final i2 = startInnings(m, 2);
  setOpeners(i2, 'b1', 'b2', 'a1');
  applyBall(i2, BallInput(batRuns: 6));
  applyBall(i2, BallInput(batRuns: 2));
  applyBall(i2, BallInput(batRuns: 1));
  expect(i2.isComplete, isTrue);
  computeResult(m, (id) => id);
  expect(m.status, 'completed');
  return m;
}

void main() {
  group('career stats aggregation', () {
    test('batting, bowling, fielding and MVP aggregate correctly', () {
      final m = playedMatch();
      final stats = computeCareerStats([m]);
      final a1 = stats['a1']!;
      expect(a1.matches, 1);
      expect(a1.runs, 6); // 4 + 2 before getting out
      expect(a1.ballsFaced, 3);
      expect(a1.fours, 1);
      expect(a1.highScore, 6);
      // a1 also bowled innings 2: conceded 9, no wickets
      expect(a1.runsConceded, 9);
      final b1 = stats['b1']!;
      expect(b1.wickets, 1); // bowled innings 1, took the caught wicket
      expect(b1.runs, 9); // 6+2+1 batting in chase
      expect(b1.ballsFaced, 3);
      expect(b1.notOuts, 1);
      final b2 = stats['b2']!;
      expect(b2.catches, 1);
      expect(b2.mvpPoints, greaterThan(0));
      // MVP: b1 = 9 runs + 20*1 wicket = 29
      expect(b1.mvpPoints, 29);
    });

    test('tournament filter excludes other matches', () {
      final m = playedMatch();
      final other = computeCareerStats([m], tournamentId: 'other');
      expect(other['a1']?.runs ?? 0, 0);
      final inT = computeCareerStats([m], tournamentId: 't1');
      expect(inT['a1']!.runs, 6);
    });

    test('manual entries add into career totals', () {
      final m = playedMatch();
      final stats = computeCareerStats([m]);
      applyManualStats(stats, [
        ManualStatEntry(
          id: 'e1',
          playerId: 'a1',
          playerName: 'A One',
          matchLabel: 'Season 1',
          runs: 54,
          balls: 30,
          fours: 6,
          sixes: 1,
          wickets: 2,
          runsConceded: 21,
          ballsBowled: 24,
        ),
      ]);
      final a1 = stats['a1']!;
      expect(a1.matches, 2);
      expect(a1.runs, 60);
      expect(a1.fifties, 1);
      expect(a1.highScore, 54);
      expect(a1.wickets, 2);
      expect(a1.bestFigures, '2/21');
    });
  });

  group('team stats & head-to-head', () {
    test('win/loss, bat-first/chase splits, toss and H2H', () {
      final m = playedMatch(); // B chased and won; A won toss, batted first
      final ts = computeTeamStats([m]);
      expect(ts['ta']!.lost, 1);
      expect(ts['tb']!.won, 1);
      expect(ts['ta']!.battedFirst, 1);
      expect(ts['ta']!.wonBattingFirst, 0);
      expect(ts['tb']!.wonChasing, 1);
      expect(ts['ta']!.tossWon, 1);
      expect(ts['tb']!.winPct, 100);
      final h = headToHead([m], 'ta', 'tb');
      expect(h.played, 1);
      expect(h.bWins, 1);
      expect(h.aWins, 0);
    });
  });
}
