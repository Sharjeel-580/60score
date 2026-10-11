// Tests for the free-touch wagon wheel (v4 redesign).
import 'package:flutter_test/flutter_test.dart';
import 'package:cricket_scorer_app/models.dart';
import 'package:cricket_scorer_app/scoring.dart';

InningsState _innings() {
  final m = Match(
    id: 'm1',
    tournamentId: 't1',
    teamAId: 'ta',
    teamBId: 'tb',
    xiA: const ['b1', 'b2'],
    xiB: const ['p1', 'p2'],
    oversLimit: 10,
    tossWinnerId: 'ta',
  );
  final inn = startInnings(m, 1);
  setOpeners(inn, 'b1', 'b2', 'p1');
  return inn;
}

void main() {
  group('wagonWheelShots', () {
    test('records plotted shots with coordinates and outcome', () {
      final inn = _innings();
      expect(applyBall(inn, BallInput(batRuns: 6, shotX: 0.5, shotY: -0.8)),
          isTrue);
      expect(applyBall(inn, BallInput(batRuns: 4, shotX: -0.9, shotY: 0.2)),
          isTrue);
      expect(applyBall(inn, BallInput(batRuns: 1, shotX: 0.2, shotY: 0.3)),
          isTrue);

      final shots = wagonWheelShots(inn, 'b1');
      expect(shots.length, 3);
      expect(shots[0].runs, 6);
      expect(shots[0].x, 0.5);
      expect(shots[0].y, -0.8);
      expect(shots[0].isWicket, isFalse);
      expect(shots[1].runs, 4);
      expect(shots[2].runs, 1);
    });

    test('wicket shots are flagged red', () {
      final inn = _innings();
      expect(
          applyBall(
              inn,
              BallInput(
                  batRuns: 0,
                  isWicket: true,
                  wicketType: 'bowled',
                  shotX: 0.1,
                  shotY: 0.1)),
          isTrue);

      final shots = wagonWheelShots(inn, 'b1');
      expect(shots.length, 1);
      expect(shots[0].isWicket, isTrue);
    });

    test('unplotted balls and wides are skipped', () {
      final inn = _innings();
      expect(applyBall(inn, BallInput(batRuns: 2)), isTrue); // no coords
      expect(applyBall(inn, BallInput(extraType: 'wide', extraRuns: 1)),
          isTrue);

      final shots = wagonWheelShots(inn, 'b1');
      expect(shots, isEmpty);
    });

    test('only the selected batter is included', () {
      final inn = _innings();
      expect(applyBall(inn, BallInput(batRuns: 4, shotX: 0.5, shotY: 0.5)),
          isTrue);
      // rotate strike with an odd run, then plot for the other batter
      expect(applyBall(inn, BallInput(batRuns: 1, shotX: -0.5, shotY: -0.5)),
          isTrue);

      final shotsB1 = wagonWheelShots(inn, 'b1');
      final shotsB2 = wagonWheelShots(inn, 'b2');
      expect(shotsB1.length + shotsB2.length, 2);
    });
  });

  group('legacy zone data', () {
    test('old zone JSON converts to a shot point', () {
      final ev = BallEvent.fromJson({
        'strikerId': 'b1',
        'nonStrikerId': 'b2',
        'bowlerId': 'p1',
        'zone': 4,
      });
      expect(ev.shotX, isNotNull);
      expect(ev.shotY, isNotNull);
      // zone 4 mid-angle: (4-1)*pi/4 + pi/4 = pi -> x ~ -0.72, y ~ 0
      expect(ev.shotX!, closeTo(-0.72, 0.01));
      expect(ev.shotY!, closeTo(0.0, 0.01));
    });

    test('explicit shotX/shotY win over legacy zone', () {
      final ev = BallEvent.fromJson({
        'strikerId': 'b1',
        'nonStrikerId': 'b2',
        'bowlerId': 'p1',
        'zone': 4,
        'shotX': 0.3,
        'shotY': 0.4,
      });
      expect(ev.shotX, 0.3);
      expect(ev.shotY, 0.4);
    });

    test('shot coordinates survive a JSON round-trip', () {
      final ev = BallEvent(
        strikerId: 'b1',
        nonStrikerId: 'b2',
        bowlerId: 'p1',
        batRuns: 6,
        shotX: 0.55,
        shotY: -0.75,
      );
      final back = BallEvent.fromJson(ev.toJson());
      expect(back.shotX, 0.55);
      expect(back.shotY, -0.75);
      expect(back.batRuns, 6);
    });
  });
}
