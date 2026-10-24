// Player Insights aggregation tests.
//
// Match 1 is built ball-by-ball with the scoring engine (the
// stats_test.dart pattern); Match 2 is built from stored figures
// plus a hand-written event list (the stats_fallback_test.dart
// pattern), because a 50+ innings cannot be scored in a 1-over
// engine match. Target player throughout is 'a1'.
import 'package:flutter_test/flutter_test.dart';
import 'package:cricket_scorer_app/models.dart';
import 'package:cricket_scorer_app/player_insights.dart';
import 'package:cricket_scorer_app/scoring.dart';

/// 1-over match. a1 opens for ta, scores 10 (4, 6) and is bowled
/// by b1; then bowls tb's innings and takes one caught wicket,
/// conceding 9 off 6 balls.
Match engineMatch() {
  final m = Match(
    id: 'm1',
    tournamentId: 't1',
    teamAId: 'ta',
    teamBId: 'tb',
    xiA: ['a1', 'a2', 'a3', 'a4'],
    xiB: ['b1', 'b2', 'b3', 'b4'],
    oversLimit: 1,
    ballsPerOver: 6,
    tossWinnerId: 'ta',
    tossDecision: 'bat',
  );
  final i1 = startInnings(m, 1);
  setOpeners(i1, 'a1', 'a2', 'b1');
  applyBall(i1, BallInput(batRuns: 4)); // a1: 4
  applyBall(i1, BallInput(batRuns: 6)); // a1: 10
  applyBall(i1, BallInput(isWicket: true, wicketType: 'bowled')); // a1 out
  setNextBatter(i1, 'a3');
  applyBall(i1, BallInput(batRuns: 1)); // a3, strike swaps to a2
  applyBall(i1, BallInput(batRuns: 1)); // a2, strike swaps to a3
  applyBall(i1, BallInput(batRuns: 0));
  expect(i1.isComplete, isTrue);
  expect(i1.totalRuns, 12);

  final i2 = startInnings(m, 2);
  setOpeners(i2, 'b1', 'b2', 'a1');
  applyBall(i2, BallInput(batRuns: 2)); // b1: 2
  applyBall(
    i2,
    BallInput(isWicket: true, wicketType: 'caught', fielderId: 'a2'),
  ); // b1 c a2 b a1
  setNextBatter(i2, 'b3');
  applyBall(i2, BallInput(batRuns: 4)); // b3
  applyBall(i2, BallInput(batRuns: 2)); // b3
  applyBall(i2, BallInput(batRuns: 1)); // b3, strike swaps to b2
  applyBall(i2, BallInput(batRuns: 0)); // b2
  expect(i2.isComplete, isTrue);
  computeResult(m, (id) => id);
  expect(m.status, 'completed');
  return m;
}

BatFig batFig(int runs, int balls, {bool out = false, String howOut = ''}) {
  final f = BatFig()
    ..batted = true
    ..runs = runs
    ..balls = balls
    ..out = out
    ..howOut = howOut;
  return f;
}

BowlFig bowlFig(int legalBalls, int runs, int wickets) {
  final f = BowlFig()
    ..legalBalls = legalBalls
    ..runs = runs
    ..wickets = wickets;
  return f;
}

BallEvent ev({
  required String striker,
  required String nonStriker,
  required String bowler,
  int batRuns = 0,
  bool isWicket = false,
  String wicketType = '',
  String outPlayerId = '',
  String fielderId = '',
}) {
  return BallEvent(
    strikerId: striker,
    nonStrikerId: nonStriker,
    bowlerId: bowler,
    batRuns: batRuns,
    totalRuns: batRuns,
    legalBall: true,
    isWicket: isWicket,
    wicketType: wicketType,
    outPlayerId: outPlayerId,
    fielderId: fielderId,
  );
}

/// Figure/event match. Innings 1: a2 and a3 open, a2 falls first
/// ball, a1 comes in at position 3 and makes 55* — position and
/// runs come from the figures, order from the events.
/// Innings 2: a1 bowls — one lbw (a bowler wicket), one run-out
/// and one mankad (neither is a bowler wicket). His bowling
/// figure is 12 balls, 18 conceded, 2 wickets (lbw + mankad, per
/// applyBall's non-runOut rule).
Match figureMatch() {
  final inn1 = InningsState(
    battingTeamId: 'ta',
    bowlingTeamId: 'tb',
    battingXI: const ['a1', 'a2', 'a3', 'a4', 'a5'],
    bowlingXI: const ['b1', 'b2', 'b3', 'b4'],
    oversLimit: 8,
    ballsPerOver: 6,
  );
  inn1.events.addAll([
    ev(striker: 'a2', nonStriker: 'a3', bowler: 'b1',
        isWicket: true, wicketType: 'bowled', outPlayerId: 'a2'),
    ev(striker: 'a1', nonStriker: 'a3', bowler: 'b1', batRuns: 6),
    ev(striker: 'a1', nonStriker: 'a3', bowler: 'b2', batRuns: 4),
  ]);
  inn1.batting['a2'] = batFig(0, 1, out: true, howOut: 'b b1');
  inn1.batting['a3'] = batFig(12, 10);
  inn1.batting['a1'] = batFig(55, 30);

  final inn2 = InningsState(
    battingTeamId: 'tb',
    bowlingTeamId: 'ta',
    battingXI: const ['b1', 'b2', 'b3', 'b4'],
    bowlingXI: const ['a1', 'a2', 'a3', 'a4', 'a5'],
    oversLimit: 8,
    ballsPerOver: 6,
  );
  inn2.events.addAll([
    ev(striker: 'b1', nonStriker: 'b2', bowler: 'a1',
        isWicket: true, wicketType: 'lbw', outPlayerId: 'b1'),
    ev(striker: 'b3', nonStriker: 'b2', bowler: 'a1', batRuns: 1,
        isWicket: true, wicketType: 'runOut', outPlayerId: 'b3',
        fielderId: 'a2'),
    ev(striker: 'b4', nonStriker: 'b2', bowler: 'a1',
        isWicket: true, wicketType: 'mankad', outPlayerId: 'b2'),
  ]);
  inn2.batting['b1'] = batFig(5, 4, out: true, howOut: 'lbw b a1');
  inn2.batting['b2'] = batFig(3, 6, out: true, howOut: 'mankad');
  inn2.batting['b3'] = batFig(1, 1, out: true, howOut: 'run out (a2)');
  inn2.batting['b4'] = batFig(10, 8);
  inn2.bowling['a1'] = bowlFig(12, 18, 2);

  return Match(
    id: 'm2',
    tournamentId: 't1',
    teamAId: 'ta',
    teamBId: 'tb',
    xiA: const ['a1', 'a2', 'a3', 'a4', 'a5'],
    xiB: const ['b1', 'b2', 'b3', 'b4'],
    oversLimit: 8,
    ballsPerOver: 6,
    tossWinnerId: 'ta',
    status: 'completed',
    innings: [inn1, inn2],
  );
}

void main() {
  group('buildPlayerInsights over engine + figure matches', () {
    late PlayerInsights ins;
    setUp(() {
      ins = buildPlayerInsights([engineMatch(), figureMatch()], 'a1');
    });

    test('batting innings, not-outs and totals', () {
      expect(ins.batting.innings, 2);
      expect(ins.batting.notOuts, 1); // 55* in m2; out in m1
      expect(ins.batting.totalRuns, 65); // 10 + 55
    });

    test('runs by batting position (event first-appearance order)', () {
      // m1: a1 opened -> position 1, 10 runs.
      expect(ins.batting.runsByPosition[1]!.innings, 1);
      expect(ins.batting.runsByPosition[1]!.runs, 10);
      // m2: a2/a3 opened, a1 first seen third -> position 3, 55 runs.
      expect(ins.batting.runsByPosition[3]!.innings, 1);
      expect(ins.batting.runsByPosition[3]!.runs, 55);
      expect(ins.batting.runsByPosition.containsKey(2), isFalse);
    });

    test('dismissal type counts from events', () {
      // Only dismissal is 'bowled' in m1 (m2 innings was not out).
      expect(ins.batting.dismissalTypeCounts, {'bowled': 1});
    });

    test('runs buckets', () {
      expect(ins.batting.runsBuckets['0'], 0);
      expect(ins.batting.runsBuckets['1-9'], 0);
      expect(ins.batting.runsBuckets['10-29'], 1); // the 10
      expect(ins.batting.runsBuckets['30-49'], 0);
      expect(ins.batting.runsBuckets['50-99'], 1); // the 55
      expect(ins.batting.runsBuckets['100+'], 0);
    });

    test('bowling wicket types exclude runOut and mankad', () {
      expect(ins.bowling.wicketsByType, {'caught': 1, 'lbw': 1});
      expect(ins.bowling.mankads, 1);
    });

    test('per-match economy and overall economy', () {
      expect(ins.bowling.perMatchEconomy, hasLength(2));
      final m1 = ins.bowling.perMatchEconomy
          .firstWhere((f) => f.matchId == 'm1');
      expect(m1.balls, 6);
      expect(m1.runsConceded, 9);
      expect(m1.wickets, 1);
      expect(m1.economy, 9.0); // 9 runs off 1 over
      final m2 = ins.bowling.perMatchEconomy
          .firstWhere((f) => f.matchId == 'm2');
      expect(m2.balls, 12);
      expect(m2.runsConceded, 18);
      expect(m2.wickets, 2);
      expect(m2.economy, 9.0); // 18 runs off 2 overs
      expect(ins.bowling.totalBalls, 18);
      expect(ins.bowling.totalRunsConceded, 27);
      expect(ins.bowling.totalWickets, 3); // figures: 1 + 2
      expect(ins.bowling.overallEconomy, 9.0); // 27 off 3 overs
    });
  });

  group('figure-only fallback (no ball events)', () {
    test('position from batting-map order, dismissal from howOut', () {
      final inn = InningsState(
        battingTeamId: 'ta',
        bowlingTeamId: 'tb',
        battingXI: const ['x1', 'a1', 'x2'],
        bowlingXI: const ['b1', 'b2'],
        oversLimit: 8,
      );
      // Insertion order IS the batting order in a figure-only record.
      inn.batting['x1'] = batFig(20, 12);
      inn.batting['a1'] =
          batFig(7, 5, out: true, howOut: 'c fielder_12345678 b bowler_12345678');
      inn.batting['x2'] = batFig(3, 4);
      final m = Match(
        id: 'm3',
        teamAId: 'ta',
        teamBId: 'tb',
        xiA: const ['x1', 'a1', 'x2'],
        xiB: const ['b1', 'b2'],
        oversLimit: 8,
        tossWinnerId: 'ta',
        status: 'completed',
        innings: [inn],
      );
      final ins = buildPlayerInsights([m], 'a1');
      expect(ins.batting.innings, 1);
      expect(ins.batting.runsByPosition[2]!.runs, 7);
      expect(ins.batting.dismissalTypeCounts, {'caught': 1});
      expect(ins.batting.runsBuckets['1-9'], 1);
    });

    test('dismissalTypeFromHowOut parses the stored token forms', () {
      expect(dismissalTypeFromHowOut('b bowler_1'), 'bowled');
      expect(dismissalTypeFromHowOut('c f_1 b b_1'), 'caught');
      expect(dismissalTypeFromHowOut('lbw b b_1'), 'lbw');
      expect(dismissalTypeFromHowOut('run out (f_1)'), 'runOut');
      expect(dismissalTypeFromHowOut('st f_1 b b_1'), 'stumped');
      expect(dismissalTypeFromHowOut('hit wicket b b_1'), 'hitWicket');
      expect(dismissalTypeFromHowOut('mankad'), 'mankad');
      expect(dismissalTypeFromHowOut(''), isNull);
    });
  });

  group('honest empties and filters', () {
    test('unknown player returns empties', () {
      final ins = buildPlayerInsights([engineMatch()], 'nobody');
      expect(ins.isEmpty, isTrue);
      expect(ins.batting.innings, 0);
      expect(ins.batting.runsByPosition, isEmpty);
      expect(ins.batting.dismissalTypeCounts, isEmpty);
      expect(ins.bowling.wicketsByType, isEmpty);
      expect(ins.bowling.perMatchEconomy, isEmpty);
      expect(ins.bowling.overallEconomy, 0.0);
    });

    test('non-completed matches are ignored', () {
      final m = engineMatch();
      m.status = 'live';
      final ins = buildPlayerInsights([m], 'a1');
      expect(ins.isEmpty, isTrue);
    });

    test('runsBucketLabel boundaries', () {
      expect(runsBucketLabel(0), '0');
      expect(runsBucketLabel(1), '1-9');
      expect(runsBucketLabel(9), '1-9');
      expect(runsBucketLabel(10), '10-29');
      expect(runsBucketLabel(29), '10-29');
      expect(runsBucketLabel(30), '30-49');
      expect(runsBucketLabel(49), '30-49');
      expect(runsBucketLabel(50), '50-99');
      expect(runsBucketLabel(99), '50-99');
      expect(runsBucketLabel(100), '100+');
    });
  });
}
