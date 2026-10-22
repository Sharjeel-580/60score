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

  group('wickets = 10 (v1.3.4)', () {
    test('chase won with 2 wickets down reads "won by 8 wickets" '
        'for a full XI (10 - 2, never 9)', () {
      final m = makeMatch(xi: 11, overs: 2);
      final i1 = openInnings(m);
      for (final r in [6, 6, 6, 6, 6, 0]) {
        runs(i1, r); // 30 in the only over i1 needs here
      }
      // Complete i1's second over with dots.
      setBowler(i1, 'b2');
      for (var i = 0; i < 6; i++) {
        runs(i1, 0);
      }
      expect(i1.totalRuns, 30);
      final i2 = openInnings(m, n: 2);
      expect(i2.target, 31);
      ball(i2, BallInput(isWicket: true, wicketType: 'bowled'));
      setNextBatter(i2, 'b3');
      ball(i2, BallInput(isWicket: true, wicketType: 'bowled'));
      setNextBatter(i2, 'b4');
      for (final r in [6, 6, 6, 6]) {
        runs(i2, r); // 24, over ends
      }
      setBowler(i2, 'a2');
      runs(i2, 6); // 30
      runs(i2, 1); // 31 — target reached, 2 wickets lost
      expect(i2.wickets, 2);
      expect(i2.isComplete, isTrue);
      final text = computeResult(
          m, (id) => id == 'ta' ? 'Team A' : 'Team B');
      expect(text, contains('Team B won by 8 wickets'));
      expect(text, isNot(contains('9 wickets')));
    });

    test('an explicit "11 wickets" setting is clamped to XI - 1 '
        'when the innings starts', () {
      final m = makeMatch(xi: 11, totalWickets: 11);
      final inn = startInnings(m, 1);
      expect(inn.maxWickets, 10);
      expect(inn.effectiveMaxWickets, 10);
    });

    test('a stored 11-wicket innings is clamped on load; a '
        'last-man-stands innings is not', () {
      final m = makeMatch(xi: 11);
      final inn = startInnings(m, 1);
      inn.maxWickets = 11; // as written by an older build
      final loaded = Match.fromJson(m.toJson());
      expect(loaded.innings[0].maxWickets, 10);
      expect(loaded.innings[0].effectiveMaxWickets, 10);

      final lms = makeMatch(xi: 4, lms: true);
      final lmsInn = startInnings(lms, 1);
      expect(lmsInn.maxWickets, 4); // XI length by LMS design
      final lmsLoaded = Match.fromJson(lms.toJson());
      expect(lmsLoaded.innings[0].maxWickets, 4);
    });

    test('innings is all out at 10 wickets with a full XI', () {
      final m = makeMatch(xi: 11, overs: 5);
      final inn = openInnings(m);
      var guard = 0;
      while (!inn.isComplete && guard++ < 40) {
        ball(inn, BallInput(isWicket: true, wicketType: 'bowled'));
        if (inn.isComplete) break;
        if (inn.awaitingBatter) {
          final out = inn.batting.entries
              .where((e) => e.value.out)
              .map((e) => e.key)
              .toSet();
          final next = inn.battingXI.firstWhere((id) =>
              !out.contains(id) &&
              id != inn.strikerId &&
              id != inn.nonStrikerId);
          setNextBatter(inn, next);
        }
        if (inn.awaitingBowler) {
          final bowler = inn.bowlingXI
              .firstWhere((id) => id != inn.lastBowlerId);
          setBowler(inn, bowler);
        }
      }
      expect(inn.wickets, 10);
      expect(inn.isComplete, isTrue);
    });
  });

  group('crease corrections (v1.3.4)', () {
    test('single tap: setStrikeTo gives the strike to the '
        'non-striker only', () {
      final m = makeMatch();
      final inn = openInnings(m);
      expect(inn.strikerId, 'a1');
      expect(setStrikeTo(inn, 'a2'), isTrue);
      expect(inn.strikerId, 'a2');
      expect(inn.nonStrikerId, 'a1');
      expect(setStrikeTo(inn, 'a2'), isFalse); // already on strike
      expect(setStrikeTo(inn, 'a3'), isFalse); // not at the crease
      expect(setStrikeTo(inn, ''), isFalse);
    });

    test('double tap: the wrong opener is replaced before a ball '
        'is bowled', () {
      final m = makeMatch();
      final inn = openInnings(m);
      final candidates = replaceBatsmanCandidates(inn, 'a1');
      expect(candidates, contains('a3'));
      expect(candidates, isNot(contains('a2'))); // at the crease
      expect(replaceBatsman(inn, 'a1', 'a3'), isTrue);
      expect(inn.strikerId, 'a3');
      expect(inn.batting['a3']!.batted, isTrue);
      expect(inn.batting['a1'], isNull);
    });

    test('double tap: a figure recorded under the wrong name '
        'transfers to the replacement, events included', () {
      final m = makeMatch();
      final inn = openInnings(m);
      runs(inn, 4);
      runs(inn, 2); // a1: 6 runs, 2 balls, one four; still on strike
      expect(replaceBatsman(inn, 'a1', 'a3'), isTrue);
      final fig = inn.batting['a3']!;
      expect(fig.runs, 6);
      expect(fig.balls, 2);
      expect(fig.fours, 1);
      expect(inn.batting['a1'], isNull);
      expect(inn.events.every((e) => e.strikerId == 'a3'), isTrue);
    });

    test('double tap: a player who already batted cannot be the '
        'replacement, and a dismissed player cannot be replaced',
        () {
      final m = makeMatch();
      final inn = openInnings(m);
      ball(inn, BallInput(isWicket: true, wicketType: 'bowled'));
      setNextBatter(inn, 'a3'); // a3 has now batted
      expect(replaceBatsmanCandidates(inn, 'a2'),
          isNot(contains('a3')));
      expect(replaceBatsman(inn, 'a2', 'a3'), isFalse);
      // a1 is out and no longer at the crease: nothing to replace.
      expect(replaceBatsmanCandidates(inn, 'a1'), isEmpty);
      expect(replaceBatsman(inn, 'a1', 'a4'), isFalse);
    });
  });

  group('post-match edit (v1.3.4)', () {
    Match completedMatch() {
      final m = Match(
        id: 'edit1',
        tournamentId: 'cup',
        teamAId: 'ta',
        teamBId: 'tb',
        xiA: const ['a1', 'a2', 'a3', 'a4'],
        xiB: const ['b1', 'b2', 'b3', 'b4'],
        oversLimit: 1,
        ballsPerOver: 6,
        tossWinnerId: 'ta',
        tossDecision: 'bat',
      );
      final i1 = openInnings(m);
      for (final r in [4, 1, 1, 2, 1, 1]) {
        runs(i1, r); // 10 (a1: 8 off 4, a2: 2 off 2)
      }
      final i2 = openInnings(m, n: 2);
      for (final r in [6, 4, 1]) {
        runs(i2, r); // 11 — chase won by 3 wickets
      }
      computeResult(m, (id) => id);
      return m;
    }

    test('an added six propagates: innings total, result text, '
        'points table and career stats all follow the stored '
        'figures', () {
      final m = completedMatch();
      expect(m.status, 'completed');
      expect(m.resultText, contains('won by 3 wickets'));
      var table = computePointsTable('cup', ['ta', 'tb'], [m]);
      expect(table.first.teamId, 'tb'); // chasers lead before the edit

      // The correction: a1 actually hit one more six in innings 1.
      final i1 = m.innings[0];
      final fig = i1.batting['a1']!;
      fig.sixes += 1;
      fig.runs += 6;
      recomputeInningsTotals(i1);
      expect(i1.totalRuns, 16);
      m.innings[1].target = i1.totalRuns + 1;
      // The edit screen's save sequence: computeResult returns the
      // fresh text, and the screen stores it (computeResult itself
      // only persists when the innings still reads complete — with
      // the target raised, the old chase no longer does).
      final text = computeResult(m, (id) => id);
      if (text.isNotEmpty) m.resultText = text;
      expect(text, contains('won by 5 runs'));
      expect(m.resultText, contains('won by 5 runs'));

      table = computePointsTable('cup', ['ta', 'tb'], [m]);
      expect(table.first.teamId, 'ta'); // table follows the edit
      expect(table.first.points, 2);
      final stats = computeCareerStats([m]);
      expect(stats['a1']!.sixes, 1);
      expect(stats['a1']!.runs, 14);
    });

    test('recomputeInningsTotals derives wickets and legal balls '
        'from the figures', () {
      final m = completedMatch();
      final i2 = m.innings[1];
      // Mark a second chaser out (as if a wicket was missed).
      final fig = i2.batting['b2']!;
      fig.out = true;
      fig.howOut = 'run out (a1)';
      recomputeInningsTotals(i2);
      expect(i2.wickets, 1);
      expect(i2.legalBalls, i2.bowling.values
          .fold<int>(0, (sum, f) => sum + f.legalBalls));
    });

    test('remapBattingFigure moves a figure to a player who did '
        'not bat, events included', () {
      final m = completedMatch();
      final i1 = m.innings[0];
      expect(remapBattingFigure(i1, 'a2', 'a4'), isTrue);
      expect(i1.batting['a2'], isNull);
      expect(i1.batting['a4']!.runs, 2);
      expect(i1.batting['a4']!.batted, isTrue);
      expect(
        i1.events.where((e) => e.strikerId == 'a4').length,
        2, // a2 faced exactly two balls
      );
      expect(i1.events.any((e) => e.strikerId == 'a2'), isFalse);
    });

    test('remapBattingFigure swaps two batted players figures and '
        'events without collision', () {
      final m = completedMatch();
      final i1 = m.innings[0];
      expect(remapBattingFigure(i1, 'a1', 'a2'), isTrue);
      expect(i1.batting['a1']!.runs, 2); // a2's old figure
      expect(i1.batting['a2']!.runs, 8); // a1's old figure
      expect(i1.events.where((e) => e.strikerId == 'a1').length, 2);
      expect(i1.events.where((e) => e.strikerId == 'a2').length, 4);
      // Totals are untouched by a pure name correction.
      recomputeInningsTotals(i1);
      expect(i1.totalRuns, 10);
    });

    test('remapBowlingFigure moves the bowling figure and the '
        'event attribution', () {
      final m = completedMatch();
      final i1 = m.innings[0];
      expect(remapBowlingFigure(i1, 'b1', 'b2'), isTrue);
      expect(i1.bowling['b1'], isNull);
      expect(i1.bowling['b2']!.legalBalls, 6);
      expect(i1.events.every((e) => e.bowlerId == 'b2'), isTrue);
    });

    test('remap rejects unknown targets and missing figures', () {
      final m = completedMatch();
      final i1 = m.innings[0];
      expect(remapBattingFigure(i1, 'a1', 'zz'), isFalse);
      expect(remapBattingFigure(i1, 'a3', 'a4'), isFalse); // a3 DNB
      expect(remapBattingFigure(i1, 'a1', 'a1'), isFalse);
      expect(remapBowlingFigure(i1, 'b1', 'zz'), isFalse);
    });
  });
}
