import 'package:flutter_test/flutter_test.dart';
import 'package:cricket_scorer_app/models.dart';
import 'package:cricket_scorer_app/scoring.dart';

Match makeMatch({
  int xi = 4,
  int overs = 2,
  bool lms = false,
  int totalWickets = 0,
}) {
  return Match(
    id: 'm1',
    teamAId: 'ta',
    teamBId: 'tb',
    xiA: [for (var i = 1; i <= xi; i++) 'a$i'],
    xiB: [for (var i = 1; i <= xi; i++) 'b$i'],
    oversLimit: overs,
    ballsPerOver: 6,
    tossWinnerId: 'ta',
    tossDecision: 'bat',
    lastManStands: lms,
    totalWickets: totalWickets,
  );
}

InningsState openInnings(Match m, {int n = 1}) {
  final inn = startInnings(m, n);
  setOpeners(inn, inn.battingXI[0], inn.battingXI[1], inn.bowlingXI[0]);
  return inn;
}

void ball(InningsState s, BallInput input) {
  final ok = applyBall(s, input);
  expect(
    ok,
    isTrue,
    reason: 'ball should apply: ${input.extraType} ${input.batRuns}',
  );
}

void runs(InningsState s, int r) => ball(s, BallInput(batRuns: r));

void main() {
  group('basic scoring & strike rotation', () {
    test('single swaps strike, dot does not, over-end swaps', () {
      final m = makeMatch();
      final inn = openInnings(m);
      runs(inn, 1);
      expect(inn.strikerId, 'a2');
      expect(inn.totalRuns, 1);
      runs(inn, 0);
      expect(inn.strikerId, 'a2');
      // finish over with dots: currently 2 legal balls, need 4 more
      for (var i = 0; i < 4; i++) {
        runs(inn, 0);
      }
      expect(inn.legalBalls, 6);
      // over-end swap: striker was a2, now a1 faces
      expect(inn.strikerId, 'a1');
      expect(inn.awaitingBowler, isTrue);
      expect(inn.currentBowlerId, '');
    });

    test('boundary counts fours and sixes', () {
      final m = makeMatch();
      final inn = openInnings(m);
      runs(inn, 4);
      runs(inn, 6);
      final fig = inn.batting['a1']!;
      expect(fig.runs, 10);
      expect(fig.fours, 1);
      expect(fig.sixes, 1);
    });
  });

  group('extras legality', () {
    test('wide is not a legal ball and adds penalty + extra runs', () {
      final m = makeMatch();
      final inn = openInnings(m);
      ball(inn, BallInput(extraType: 'wide', extraRuns: 2));
      expect(inn.legalBalls, 0);
      expect(inn.totalRuns, 3);
      expect(inn.widesRuns, 3);
      // 2 extra runs run => strike swaps twice? 2 is even => no swap
      expect(inn.strikerId, 'a1');
      ball(inn, BallInput(extraType: 'wide', extraRuns: 1));
      expect(inn.strikerId, 'a2'); // odd extra runs cross
      expect(inn.totalRuns, 5);
    });

    test('no ball: penalty run, bat runs count, ball faced, not legal', () {
      final m = makeMatch();
      final inn = openInnings(m);
      ball(inn, BallInput(extraType: 'noBall', batRuns: 2));
      expect(inn.legalBalls, 0);
      expect(inn.totalRuns, 3);
      expect(inn.noBallRuns, 1);
      expect(inn.batting['a1']!.runs, 2);
      expect(inn.batting['a1']!.balls, 1);
      expect(inn.bowling['b1']!.runs, 3);
    });

    test('no-ball penalty can be switched off in match settings', () {
      final m = makeMatch();
      m.noBallPenalty = false;
      final inn = openInnings(m);
      ball(inn, BallInput(extraType: 'noBall', batRuns: 1));
      expect(inn.totalRuns, 1);
      expect(inn.noBallRuns, 0);
    });

    test('bye and leg bye: legal, no bat runs, bowler not debited (bye)', () {
      final m = makeMatch();
      final inn = openInnings(m);
      ball(inn, BallInput(extraType: 'bye', batRuns: 2));
      expect(inn.legalBalls, 1);
      expect(inn.byeRuns, 2);
      expect(inn.batting['a1']!.runs, 0);
      expect(inn.batting['a1']!.balls, 1);
      expect(inn.bowling['b1']!.runs, 0);
      ball(inn, BallInput(extraType: 'legBye', batRuns: 1));
      expect(inn.legByeRuns, 1);
      expect(inn.strikerId, 'a2'); // crossed on the leg bye
    });
  });

  group('wickets', () {
    test('bowled: bowler credited, batter out, next batter awaited', () {
      final m = makeMatch();
      final inn = openInnings(m);
      ball(inn, BallInput(isWicket: true, wicketType: 'bowled'));
      expect(inn.wickets, 1);
      expect(inn.bowling['b1']!.wickets, 1);
      expect(inn.batting['a1']!.out, isTrue);
      expect(inn.awaitingBatter, isTrue);
      setNextBatter(inn, 'a3');
      expect(inn.strikerId, 'a3');
      expect(inn.awaitingBatter, isFalse);
    });

    test('wide + stumped: wicket to bowler, wide run counts, not legal', () {
      final m = makeMatch();
      final inn = openInnings(m);
      ball(
        inn,
        BallInput(
          extraType: 'wide',
          isWicket: true,
          wicketType: 'stumped',
          fielderId: 'b2',
        ),
      );
      expect(inn.legalBalls, 0);
      expect(inn.totalRuns, 1); // wide penalty still counts
      expect(inn.wickets, 1);
      expect(inn.bowling['b1']!.wickets, 1);
      expect(inn.batting['a1']!.out, isTrue);
    });

    test(
      'run out: completed runs count, bowler not credited, out end honoured',
      () {
        final m = makeMatch();
        final inn = openInnings(m);
        // 1 run completed, non-striker run out
        ball(
          inn,
          BallInput(
            batRuns: 1,
            isWicket: true,
            wicketType: 'runOut',
            outPlayerId: 'a2',
            fielderId: 'b3',
          ),
        );
        expect(inn.totalRuns, 1);
        expect(inn.wickets, 1);
        expect(inn.bowling['b1']!.wickets, 0);
        expect(inn.batting['a2']!.out, isTrue);
        // The pair crossed on the completed run; the dismissed batter was
        // heading to the striker's end, so that end is the vacant one and
        // a1 (now at the non-striker end) stays.
        expect(inn.strikerId, '');
        expect(inn.nonStrikerId, 'a1');
        expect(inn.awaitingBatter, isTrue);
      },
    );

    test('all out ends innings at XI-1 wickets', () {
      final m = makeMatch(xi: 4);
      final inn = openInnings(m);
      ball(inn, BallInput(isWicket: true, wicketType: 'bowled'));
      setNextBatter(inn, 'a3');
      ball(inn, BallInput(isWicket: true, wicketType: 'bowled'));
      setNextBatter(inn, 'a4');
      ball(inn, BallInput(isWicket: true, wicketType: 'bowled'));
      expect(inn.wickets, 3);
      expect(inn.isComplete, isTrue);
    });

    test('last man stands: innings survives XI-1 wickets', () {
      final m = makeMatch(xi: 4, lms: true);
      final inn = openInnings(m);
      ball(inn, BallInput(isWicket: true, wicketType: 'bowled'));
      setNextBatter(inn, 'a3');
      ball(inn, BallInput(isWicket: true, wicketType: 'bowled'));
      setNextBatter(inn, 'a4');
      ball(inn, BallInput(isWicket: true, wicketType: 'bowled'));
      expect(inn.wickets, 3);
      expect(inn.isComplete, isFalse);
      expect(inn.effectiveMaxWickets, 4);
    });
  });

  group('bowlers & overs', () {
    test('same bowler cannot bowl consecutive overs', () {
      final m = makeMatch(overs: 3);
      final inn = openInnings(m);
      for (var i = 0; i < 6; i++) {
        runs(inn, 0);
      }
      expect(setBowler(inn, 'b1'), isFalse);
      expect(setBowler(inn, 'b2'), isTrue);
      expect(inn.currentBowlerId, 'b2');
    });

    test('maiden counted only when no team runs in the over', () {
      final m = makeMatch(overs: 3);
      final inn = openInnings(m);
      for (var i = 0; i < 6; i++) {
        runs(inn, 0);
      }
      expect(inn.bowling['b1']!.maidens, 1);
      setBowler(inn, 'b2');
      ball(inn, BallInput(extraType: 'bye', batRuns: 1));
      for (var i = 0; i < 5; i++) {
        runs(inn, 0);
      }
      expect(inn.bowling['b2']!.maidens, 0); // bye breaks the maiden
    });

    test('undo restores previous state exactly', () {
      final m = makeMatch();
      final inn = openInnings(m);
      runs(inn, 4);
      runs(inn, 1);
      expect(inn.totalRuns, 5);
      expect(undoLastBall(inn), isTrue);
      expect(inn.totalRuns, 4);
      expect(inn.batting['a1']!.runs, 4);
      expect(inn.strikerId, 'a1');
      expect(undoLastBall(inn), isTrue);
      expect(inn.totalRuns, 0);
      expect(undoLastBall(inn), isFalse);
    });
  });

  group('match flow & result', () {
    test('chase: target set, result by wickets with balls left', () {
      final m = makeMatch(xi: 4, overs: 1);
      final i1 = openInnings(m);
      // Team A scores 10 in 1 over
      for (final r in [4, 1, 1, 2, 1, 1]) {
        runs(i1, r);
      }
      expect(i1.isComplete, isTrue);
      expect(i1.totalRuns, 10);
      final i2 = openInnings(m, n: 2);
      expect(i2.target, 11);
      expect(i2.battingTeamId, 'tb');
      runs(i2, 6);
      runs(i2, 4);
      runs(i2, 1); // reaches 11 with 3 balls left, no wickets lost
      expect(i2.isComplete, isTrue);
      final text = computeResult(m, (id) => id == 'ta' ? 'Team A' : 'Team B');
      expect(m.status, 'completed');
      expect(text, contains('Team B won by 3 wickets'));
      expect(text, contains('3 balls left'));
    });

    test('defended total: result by runs; tie gives Match tied', () {
      final m = makeMatch(xi: 4, overs: 1);
      final i1 = openInnings(m);
      for (final r in [1, 1, 1, 1, 1, 1]) {
        runs(i1, r);
      }
      final i2 = openInnings(m, n: 2);
      for (final r in [1, 1, 1, 1, 1, 1]) {
        runs(i2, r);
      }
      final text = computeResult(m, (id) => id);
      expect(text, 'Match tied');
    });
  });
}
