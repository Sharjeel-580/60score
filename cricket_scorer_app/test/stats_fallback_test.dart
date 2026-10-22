// Figure-derived statistics fallbacks (v1.3.5).
//
// Match 01 of the Super Sixty League (2026-10-22) exists in the
// record as figures without second-innings deliveries, and the
// Detailed Stats cards for Fastest Fifty / Hundred, Best
// Partnerships and Most Catches all read "No data yet" — even
// though a 102 off 38, a ~108-run stand and three catches are in
// those figures. Derivations now fall back to the figures (and to
// fall-of-wicket scores) whenever deliveries are missing; the
// delivery-derived numbers stay preferred when they exist.
import 'package:flutter_test/flutter_test.dart';
import 'package:cricket_scorer_app/models.dart';
import 'package:cricket_scorer_app/scoring.dart';

Match baseMatch({List<InningsState>? innings}) {
  return Match(
    id: 'm1',
    teamAId: 'ta',
    teamBId: 'tb',
    xiA: const ['a1', 'a2', 'a3', 'a4', 'a5'],
    xiB: const ['b1', 'b2', 'b3'],
    oversLimit: 8,
    ballsPerOver: 6,
    tossWinnerId: 'ta',
    status: 'completed',
    resultText: 'Team B won',
    innings: innings,
  );
}

InningsState figInnings() => InningsState(
      battingTeamId: 'ta',
      bowlingTeamId: 'tb',
      battingXI: const ['a1', 'a2', 'a3', 'a4', 'a5'],
      bowlingXI: const ['b1', 'b2', 'b3'],
      oversLimit: 8,
      ballsPerOver: 6,
    );

BatFig fig(int runs, int balls, {bool out = false, String howOut = ''}) {
  final f = BatFig()
    ..batted = true
    ..runs = runs
    ..balls = balls
    ..out = out
    ..howOut = howOut;
  return f;
}

void main() {
  group('fastestMilestones figure fallback', () {
    test('a 102 off 38 with no deliveries fills Fastest Hundred '
        '(and Fifty) instead of leaving the cards empty', () {
      final inn = figInnings();
      inn.batting['a1'] = fig(102, 38);
      inn.batting['a2'] = fig(15, 10, out: true);
      final r = fastestMilestones([baseMatch(innings: [inn])]);
      expect(r.hundreds, hasLength(1));
      expect(r.hundreds.single.playerId, 'a1');
      expect(r.hundreds.single.balls, 38);
      expect(r.hundreds.single.runs, 102);
      expect(r.fifties, hasLength(1));
      expect(r.fifties.single.playerId, 'a1');
    });

    test('fallback sorts by balls ascending alongside others', () {
      final i1 = figInnings()..batting['a1'] = fig(80, 40);
      final i2 = figInnings()..batting['a2'] = fig(55, 25);
      final r = fastestMilestones([
        baseMatch(innings: [i1]),
        baseMatch(innings: [i2]),
      ]);
      expect(r.fifties.map((e) => e.playerId), ['a2', 'a1']);
    });

    test('delivery-derived milestone beats the figure fallback '
        '(no duplicate, precise ball count)', () {
      final inn = figInnings();
      // 13 balls to fifty: 12 fours and a two.
      for (var n = 0; n < 12; n++) {
        inn.events.add(BallEvent(
          strikerId: 'a1',
          nonStrikerId: 'a2',
          bowlerId: 'b1',
          batRuns: 4,
          totalRuns: 4,
          legalBall: true,
        ));
      }
      inn.events.add(BallEvent(
        strikerId: 'a1',
        nonStrikerId: 'a2',
        bowlerId: 'b1',
        batRuns: 2,
        totalRuns: 2,
        legalBall: true,
      ));
      inn.batting['a1'] = fig(60, 30); // final figure: 60 off 30
      final r = fastestMilestones([baseMatch(innings: [inn])]);
      expect(r.fifties, hasLength(1));
      expect(r.fifties.single.balls, 13);
    });
  });

  group('partnerships from fall of wickets', () {
    test('stands rebuild from FoW scores when no deliveries exist, '
        'and Best Partnerships puts the longest on top', () {
      final inn = figInnings();
      inn.batting['a1'] = fig(40, 20, out: true);
      inn.batting['a2'] = fig(10, 6, out: true);
      inn.batting['a3'] = fig(30, 14);
      inn.batting['a4'] = fig(5, 4);
      inn.totalRuns = 90;
      inn.legalBalls = 30;
      inn.fallOfWickets = [
        FallOfWicket(1, 20, '1.2', 'a2'),
        FallOfWicket(2, 55, '3.4', 'a1'),
      ];
      final stands = partnerships(inn);
      expect(stands, hasLength(3));
      // Opening stand: a1 & a2, 20 runs off 8 legal balls.
      expect(stands[0].batter1Id, 'a1');
      expect(stands[0].batter2Id, 'a2');
      expect(stands[0].runs, 20);
      expect(stands[0].balls, 8);
      // Second stand: survivor a1 with a3, 55-20 = 35 runs.
      expect(stands[1].batter1Id, 'a1');
      expect(stands[1].batter2Id, 'a3');
      expect(stands[1].runs, 35);
      // Unbroken stand: a3 & a4 to the total.
      expect(stands[2].unbroken, isTrue);
      expect(stands[2].runs, 35);

      final best = bestPartnerships([baseMatch(innings: [inn])]);
      expect(best.first.runs, 35);
      // Runs tied at 35: the longer stand (14 balls) ranks first.
      expect(best.first.balls, 14);
    });
  });

  group('fielding credits from dismissal text', () {
    test('catches / stumpings / run-outs count when the record has '
        'figures only (no ball events)', () {
      const fielder = 'player_1792000000000000_7';
      const keeper = 'player_1792000000000000_9';
      const bowler = 'player_1792000000000000_3';
      final inn = figInnings();
      inn.batting['a1'] =
          fig(10, 5, out: true, howOut: 'c $fielder b $bowler');
      inn.batting['a2'] =
          fig(4, 3, out: true, howOut: 'st $keeper b $bowler');
      inn.batting['a3'] =
          fig(7, 6, out: true, howOut: 'run out ($fielder)');
      final stats = computeCareerStats([baseMatch(innings: [inn])]);
      expect(stats[fielder]?.catches, 1);
      expect(stats[fielder]?.runOuts, 1);
      expect(stats[keeper]?.stumpings, 1);
    });

    test('a dismissal credited by a ball event is not double-counted '
        'from its howOut text', () {
      const fielder = 'player_1792000000000000_7';
      const bowler = 'player_1792000000000000_3';
      final inn = figInnings();
      inn.events.add(BallEvent(
        strikerId: 'a1',
        nonStrikerId: 'a2',
        bowlerId: bowler,
        isWicket: true,
        wicketType: 'caught',
        outPlayerId: 'a1',
        fielderId: fielder,
        legalBall: true,
      ));
      inn.batting['a1'] =
          fig(10, 5, out: true, howOut: 'c $fielder b $bowler');
      final stats = computeCareerStats([baseMatch(innings: [inn])]);
      expect(stats[fielder]?.catches, 1);
    });

    test('name-only dismissal text creates no phantom fielder', () {
      final inn = figInnings();
      inn.batting['a1'] = fig(10, 5, out: true, howOut: 'c Ahmed b Bilal');
      final stats = computeCareerStats([baseMatch(innings: [inn])]);
      expect(stats.containsKey('Ahmed'), isFalse);
      expect(fielderCreditFromHowOut('c Ahmed b Bilal'), isNull);
      expect(
        fielderCreditFromHowOut('run out (player_1792000000000000_7)'),
        ('runOut', 'player_1792000000000000_7'),
      );
    });
  });
}
