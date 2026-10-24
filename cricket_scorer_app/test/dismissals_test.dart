// Full dismissal set (Feature 4): mankad, retired out, obstructing
// the field, hit the ball twice, timed out — plus retired hurt,
// which is NOT a dismissal. Bowler credit exists only for bowled /
// caught / lbw / stumped / hit wicket; everything else is a team
// wicket with no bowler credit.
import 'package:flutter_test/flutter_test.dart';
import 'package:cricket_scorer_app/models.dart';
import 'package:cricket_scorer_app/scoring.dart';

Match makeMatch({int xi = 5, int overs = 2}) {
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
  );
}

InningsState openInnings(Match m, {int n = 1}) {
  final inn = startInnings(m, n);
  setOpeners(inn, inn.battingXI[0], inn.battingXI[1], inn.bowlingXI[0]);
  return inn;
}

void ball(InningsState s, BallInput input) {
  expect(applyBall(s, input), isTrue);
}

void main() {
  group('bowler credit set', () {
    test('only bowled/caught/lbw/stumped/hitWicket credit the bowler',
        () {
      for (final t in ['bowled', 'caught', 'lbw', 'stumped', 'hitWicket']) {
        expect(bowlerGetsWicketCredit(t), isTrue, reason: t);
      }
      for (final t in [
        'runOut',
        'mankad',
        'retiredOut',
        'obstructing',
        'hitTwice',
        'timedOut',
        '',
      ]) {
        expect(bowlerGetsWicketCredit(t), isFalse, reason: t);
      }
    });
  });

  group('applyBall: new dismissal types', () {
    test('mankad: non-striker out, NO bowler wicket, bowler is the '
        'fielder of record, howOut reads Mankad (Name)', () {
      final m = makeMatch();
      final inn = openInnings(m);
      ball(
        inn,
        BallInput(
          isWicket: true,
          wicketType: 'mankad',
          outPlayerId: 'a2', // non-striker, as usual for a mankad
        ),
      );
      expect(inn.wickets, 1);
      expect(inn.bowling['b1']!.wickets, 0);
      final fig = inn.batting['a2']!;
      expect(fig.out, isTrue);
      expect(fig.batted, isTrue);
      expect(fig.howOut, 'Mankad (b1)');
      // The event carries the bowler as fielder for career credit.
      final ev = inn.events.single;
      expect(ev.wicketType, 'mankad');
      expect(ev.fielderId, 'b1');
      expect(ev.outPlayerId, 'a2');
      // Display resolves the id and does NOT read plain 'run out'.
      // (resolveHowOut only rewrites long id tokens — real player
      // ids are 'player_<digits>_…' — so resolution is exercised
      // with a stored-form token here.)
      const longBowler = 'player_1792000000000000_3';
      final display = resolveHowOut(
        'Mankad ($longBowler)',
        (id) => id == longBowler ? 'Bilal' : id,
      );
      expect(display, 'Mankad (Bilal)');
      expect(display, isNot(contains('run out')));
      // Non-striker's end is vacant; striker stays.
      expect(inn.strikerId, 'a1');
      expect(inn.nonStrikerId, '');
      expect(inn.awaitingBatter, isTrue);
      expect(inn.fallOfWickets.single.playerId, 'a2');
    });

    test('retired out (on a ball): wicket counts, no bowler credit',
        () {
      final m = makeMatch();
      final inn = openInnings(m);
      ball(inn, BallInput(isWicket: true, wicketType: 'retiredOut'));
      expect(inn.wickets, 1);
      expect(inn.bowling['b1']!.wickets, 0);
      expect(inn.batting['a1']!.out, isTrue);
      expect(inn.batting['a1']!.howOut, 'retired out');
      expect(resolveHowOut('retired out', (id) => id), 'retired out');
    });

    test('obstructing the field: wicket, no bowler/fielder credit, '
        'plain text survives name resolution untouched', () {
      final m = makeMatch();
      final inn = openInnings(m);
      ball(
        inn,
        BallInput(
          isWicket: true,
          wicketType: 'obstructing',
          fielderId: 'b3',
        ),
      );
      expect(inn.wickets, 1);
      expect(inn.bowling['b1']!.wickets, 0);
      expect(inn.batting['a1']!.howOut, 'obstructing the field');
      // A store-style lookup turns unknown long tokens into
      // 'Player'; the dismissal words must not be rewritten.
      String storeLike(String id) => id.length > 10 ? 'Player' : id;
      expect(
        resolveHowOut('obstructing the field', storeLike),
        'obstructing the field',
      );
      expect(fielderCreditFromHowOut('obstructing the field'), isNull);
    });

    test('hit the ball twice: wicket, no bowler credit', () {
      final m = makeMatch();
      final inn = openInnings(m);
      ball(inn, BallInput(isWicket: true, wicketType: 'hitTwice'));
      expect(inn.wickets, 1);
      expect(inn.bowling['b1']!.wickets, 0);
      expect(inn.batting['a1']!.out, isTrue);
      expect(inn.batting['a1']!.howOut, 'hit the ball twice');
      expect(
        resolveHowOut('hit the ball twice', (id) => id),
        'hit the ball twice',
      );
    });

    test('timed out (via the wicket dialog ball path): wicket, '
        'no bowler credit', () {
      final m = makeMatch();
      final inn = openInnings(m);
      ball(inn, BallInput(isWicket: true, wicketType: 'timedOut'));
      expect(inn.wickets, 1);
      expect(inn.bowling['b1']!.wickets, 0);
      expect(inn.batting['a1']!.howOut, 'timed out');
    });
  });

  group('fielderCreditFromHowOut: new texts', () {
    test('mankad with an id token credits that player as a run out',
        () {
      expect(
        fielderCreditFromHowOut('Mankad (player_1792000000000000_3)'),
        ('runOut', 'player_1792000000000000_3'),
      );
      expect(
        fielderCreditFromHowOut('mankad (player_1792000000000000_3)'),
        ('runOut', 'player_1792000000000000_3'),
      );
    });

    test('plain / name-only texts credit nobody', () {
      for (final t in [
        'retired out',
        'timed out',
        'obstructing the field',
        'hit the ball twice',
        'retired hurt',
        'mankad',
        'Mankad',
        'Mankad (Bilal)', // a plain name is not a player id
      ]) {
        expect(fielderCreditFromHowOut(t), isNull, reason: t);
      }
    });
  });

  group('mankad career stats', () {
    test('bowler gets a run-out credit, not a wicket; the mankaded '
        'batter counts as dismissed', () {
      const a1 = 'player_1792000000000000_1';
      const a2 = 'player_1792000000000000_2';
      const a3 = 'player_1792000000000000_3';
      const b1 = 'player_1792000000000000_11';
      const b2 = 'player_1792000000000000_12';
      const b3 = 'player_1792000000000000_13';
      final m = Match(
        id: 'mk1',
        teamAId: 'ta',
        teamBId: 'tb',
        xiA: const [a1, a2, a3],
        xiB: const [b1, b2, b3],
        oversLimit: 1,
        ballsPerOver: 6,
        tossWinnerId: 'ta',
        tossDecision: 'bat',
      );
      final i1 = startInnings(m, 1);
      setOpeners(i1, a1, a2, b1);
      ball(
        i1,
        BallInput(isWicket: true, wicketType: 'mankad', outPlayerId: a2),
      );
      setNextBatter(i1, a3);
      // Second (and last possible) wicket: bowled — innings over.
      ball(i1, BallInput(isWicket: true, wicketType: 'bowled'));
      expect(i1.isComplete, isTrue);
      final i2 = startInnings(m, 2);
      setOpeners(i2, b1, b2, a1);
      ball(i2, BallInput(batRuns: 1)); // chase the 0 total + 1 target
      expect(i2.isComplete, isTrue);
      computeResult(m, (id) => id);
      expect(m.status, 'completed');

      final stats = computeCareerStats([m]);
      expect(stats[b1]!.runOuts, 1); // mankad = run-out credit
      expect(stats[b1]!.wickets, 1); // only the bowled wicket
      expect(stats[b1]!.catches, 0);
      expect(stats[a2]!.dismissals, 1);
      expect(stats[a2]!.notOuts, 0);
    });
  });

  group('retired hurt (not a dismissal)', () {
    test('leaves the crease not out, no wicket, no ball; the marker '
        'shows via batFigStatusText', () {
      final m = makeMatch();
      final inn = openInnings(m);
      ball(inn, BallInput(batRuns: 4));
      expect(retireBatsmanHurt(inn, 'a1'), isTrue);
      expect(inn.wickets, 0);
      expect(inn.legalBalls, 1);
      final fig = inn.batting['a1']!;
      expect(fig.out, isFalse);
      expect(fig.batted, isTrue);
      expect(fig.howOut, 'retired hurt');
      expect(batFigStatusText(fig, (id) => id), 'retired hurt');
      expect(inn.strikerId, '');
      expect(inn.nonStrikerId, 'a2');
      expect(inn.awaitingBatter, isTrue);
    });

    test('only a batsman at the crease can retire hurt', () {
      final m = makeMatch();
      final inn = openInnings(m);
      expect(retireBatsmanHurt(inn, 'a3'), isFalse); // not at crease
      expect(retireBatsmanHurt(inn, ''), isFalse);
      expect(inn.wickets, 0);
      expect(inn.strikerId, 'a1');
    });

    test('resumed batsman accumulates: retire, another bats, then '
        'he returns and scores in the same figure', () {
      final m = makeMatch();
      final inn = openInnings(m);
      ball(inn, BallInput(batRuns: 4)); // a1: 4 off 1
      expect(retireBatsmanHurt(inn, 'a1'), isTrue);
      setNextBatter(inn, 'a3'); // a3 takes the striker end
      ball(inn, BallInput(isWicket: true, wicketType: 'bowled')); // a3 out
      setNextBatter(inn, 'a1'); // a1 resumes instead of a new batter
      expect(inn.strikerId, 'a1');
      expect(inn.batting['a1']!.howOut, '');
      ball(inn, BallInput(batRuns: 2));
      final fig = inn.batting['a1']!;
      expect(fig.runs, 6);
      expect(fig.balls, 2);
      expect(fig.out, isFalse);
      expect(inn.wickets, 1); // only a3's wicket ever fell
    });

    test('retired hurt at innings end counts as not out in career '
        'stats (no dismissal)', () {
      final m = makeMatch(xi: 4, overs: 1);
      final i1 = openInnings(m);
      ball(i1, BallInput(batRuns: 1)); // a1 scores, strike swaps to a2
      expect(retireBatsmanHurt(i1, 'a1'), isTrue); // non-striker retires
      setNextBatter(i1, 'a3');
      for (var i = 0; i < 5; i++) {
        ball(i1, BallInput(batRuns: 0));
      }
      expect(i1.isComplete, isTrue);
      expect(i1.wickets, 0);
      final i2 = openInnings(m, n: 2);
      ball(i2, BallInput(batRuns: 2)); // target was 2
      expect(i2.isComplete, isTrue);
      computeResult(m, (id) => id);
      expect(m.status, 'completed');
      final stats = computeCareerStats([m]);
      expect(stats['a1']!.runs, 1);
      expect(stats['a1']!.notOuts, 1);
      expect(stats['a1']!.dismissals, 0);
      expect(fielderCreditFromHowOut('retired hurt'), isNull);
    });
  });

  group('dismissals without a ball', () {
    test('timed out: wicket falls, legalBalls unchanged, batter '
        'marked batted/out with 0 balls', () {
      final m = makeMatch();
      final inn = openInnings(m);
      ball(inn, BallInput(batRuns: 3));
      final ballsBefore = inn.legalBalls;
      expect(dismissBatsmanWithoutBall(inn, 'a4', 'timedOut'), isTrue);
      expect(inn.wickets, 1);
      expect(inn.legalBalls, ballsBefore);
      expect(inn.events.length, 1); // no ball event was added
      expect(inn.totalRuns, 3);
      final fig = inn.batting['a4']!;
      expect(fig.batted, isTrue);
      expect(fig.out, isTrue);
      expect(fig.balls, 0);
      expect(fig.howOut, 'timed out');
      // FoW entry at the current score/over keeps the list
      // consistent with the wicket count.
      expect(inn.fallOfWickets, hasLength(1));
      expect(inn.fallOfWickets.single.playerId, 'a4');
      expect(inn.fallOfWickets.single.runs, 3);
      // Nobody at the crease was disturbed.
      expect(inn.strikerId, 'a2'); // crossed on the 3 runs
      expect(inn.nonStrikerId, 'a1');
      expect(inn.awaitingBatter, isFalse);
    });

    test('timed out rejects a batsman at the crease, one who has '
        'batted, and non-XI players', () {
      final m = makeMatch();
      final inn = openInnings(m);
      expect(dismissBatsmanWithoutBall(inn, 'a1', 'timedOut'), isFalse);
      ball(inn, BallInput(isWicket: true, wicketType: 'bowled'));
      setNextBatter(inn, 'a3'); // a3 has now batted (at the crease)
      expect(dismissBatsmanWithoutBall(inn, 'a3', 'timedOut'), isFalse);
      expect(dismissBatsmanWithoutBall(inn, 'zz', 'timedOut'), isFalse);
      expect(inn.wickets, 1); // only the bowled wicket
    });

    test('retired out between balls: wicket, no ball, crease '
        'vacated, cannot be re-dismissed', () {
      final m = makeMatch();
      final inn = openInnings(m);
      ball(inn, BallInput(batRuns: 2));
      expect(dismissBatsmanWithoutBall(inn, 'a1', 'retiredOut'), isTrue);
      expect(inn.wickets, 1);
      expect(inn.legalBalls, 1);
      expect(inn.batting['a1']!.out, isTrue);
      expect(inn.batting['a1']!.howOut, 'retired out');
      expect(inn.strikerId, '');
      expect(inn.awaitingBatter, isTrue);
      expect(dismissBatsmanWithoutBall(inn, 'a1', 'retiredOut'), isFalse);
      // Retired out is not for a batsman who has not come in.
      expect(dismissBatsmanWithoutBall(inn, 'a5', 'retiredOut'), isFalse);
    });

    test('other wicket types are rejected by the non-ball path', () {
      final m = makeMatch();
      final inn = openInnings(m);
      expect(dismissBatsmanWithoutBall(inn, 'a1', 'bowled'), isFalse);
      expect(dismissBatsmanWithoutBall(inn, 'a3', 'mankad'), isFalse);
      expect(inn.wickets, 0);
    });
  });

  group('batFigStatusText', () {
    test('out resolves, not out plain, retired hurt marked', () {
      final outFig = BatFig()
        ..batted = true
        ..out = true
        ..howOut = 'b player_1792000000000000_3';
      expect(
        batFigStatusText(
          outFig,
          (id) => id == 'player_1792000000000000_3' ? 'Bowler' : id,
        ),
        'b Bowler',
      );
      final notOut = BatFig()..batted = true;
      expect(batFigStatusText(notOut, (id) => id), 'not out');
      final hurt = BatFig()
        ..batted = true
        ..howOut = 'retired hurt';
      expect(batFigStatusText(hurt, (id) => id), 'retired hurt');
    });
  });
}
