// Per-ball edit replay (v1.4.5, M4b): pick a ball, edit or delete
// it, replay later balls through applyBall. Tests are engine-level
// (replayInningsBalls): the UI guards (completed-match winner /
// reopening refusals) live in _BallsTabState._editBall and are
// covered by the same replay + computeResult behaviour here.
import 'package:flutter_test/flutter_test.dart';

import 'package:cricket_scorer_app/models.dart';
import 'package:cricket_scorer_app/scoring.dart';

InningsState _innings() {
  final m = Match(
    id: 'm1',
    teamAId: 'a',
    teamBId: 'b',
    xiA: ['a1', 'a2', 'a3', 'a4'],
    xiB: ['b1', 'b2', 'b3', 'b4'],
    oversLimit: 2,
    ballsPerOver: 6,
    tossWinnerId: 'a',
    tossDecision: 'bat',
  );
  final inn = startInnings(m, 1);
  setOpeners(inn, 'a1', 'a2', 'b1');
  return inn;
}

void _ball(InningsState inn, BallInput input) {
  expect(applyBall(inn, input), isTrue);
}

void main() {
  test('edit runs changes totals and figures, later balls replay', () {
    final inn = _innings();
    _ball(inn, BallInput(batRuns: 4));
    _ball(inn, BallInput(batRuns: 1));
    _ball(inn, BallInput(batRuns: 2));
    expect(inn.totalRuns, 7);
    // Edit the first ball 4 -> 6.
    final edited = List.of(inn.events);
    edited[0] = BallEvent(
      strikerId: edited[0].strikerId,
      nonStrikerId: edited[0].nonStrikerId,
      bowlerId: edited[0].bowlerId,
      extraType: '',
      batRuns: 6,
      extraRuns: 0,
      isWicket: false,
      wicketType: '',
      outPlayerId: '',
      fielderId: '',
      zone: 0,
      shotX: 0,
      shotY: 0,
      totalRuns: 0,
      legalBall: false,
    );
    final replayed = replayInningsBalls(inn, edited);
    expect(replayed, isNotNull);
    expect(replayed!.totalRuns, 9);
    // Ball 2's single rotates strike, so ball 3 belongs to a2.
    expect(replayed.batting['a1']!.runs, 7);
    expect(replayed.batting['a1']!.fours, 0);
    expect(replayed.batting['a1']!.sixes, 1);
    expect(replayed.batting['a2']!.runs, 2);
    expect(replayed.events.length, 3);
    expect(replayed.undoStack, isEmpty);
    // The original innings is untouched by a replay.
    expect(inn.totalRuns, 7);
  });

  test('delete ball shifts totals and ball counts', () {
    final inn = _innings();
    _ball(inn, BallInput(batRuns: 4));
    _ball(inn, BallInput(batRuns: 1));
    _ball(inn, BallInput(extraType: 'wide', extraRuns: 1));
    expect(inn.totalRuns, 7);
    expect(inn.legalBalls, 2);
    final edited = List.of(inn.events)..removeAt(0);
    final replayed = replayInningsBalls(inn, edited);
    expect(replayed, isNotNull);
    expect(replayed!.totalRuns, 3);
    expect(replayed.legalBalls, 1);
    expect(replayed.wideCount, 1);
    expect(replayed.events.length, 2);
  });

  test('illegal no-ball dismissal is refused, original untouched', () {
    final inn = _innings();
    _ball(inn, BallInput(extraType: 'noBall', batRuns: 2));
    _ball(inn, BallInput(batRuns: 1));
    final edited = List.of(inn.events);
    edited[0] = BallEvent(
      strikerId: edited[0].strikerId,
      nonStrikerId: edited[0].nonStrikerId,
      bowlerId: edited[0].bowlerId,
      extraType: 'noBall',
      batRuns: 2,
      extraRuns: 0,
      isWicket: true,
      wicketType: 'bowled',
      outPlayerId: 'a1',
      fielderId: '',
      zone: 0,
      shotX: 0,
      shotY: 0,
      totalRuns: 0,
      legalBall: false,
    );
    expect(replayInningsBalls(inn, edited), isNull);
    expect(inn.totalRuns, 4);
    expect(inn.wickets, 0);
    expect(inn.events.length, 2);
  });

  test('run-out on a no-ball replays, and wicket edits replay', () {
    final inn = _innings();
    _ball(inn, BallInput(batRuns: 4));
    _ball(inn, BallInput(extraType: 'noBall', batRuns: 1));
    // Turn the no-ball into a run-out (1 run completed).
    final edited = List.of(inn.events);
    edited[1] = BallEvent(
      strikerId: edited[1].strikerId,
      nonStrikerId: edited[1].nonStrikerId,
      bowlerId: edited[1].bowlerId,
      extraType: 'noBall',
      batRuns: 1,
      extraRuns: 0,
      isWicket: true,
      wicketType: 'runOut',
      outPlayerId: 'a1',
      fielderId: 'b1',
      zone: 0,
      shotX: 0,
      shotY: 0,
      totalRuns: 0,
      legalBall: false,
    );
    final replayed = replayInningsBalls(inn, edited);
    expect(replayed, isNotNull);
    expect(replayed!.wickets, 1);
    expect(replayed.batting['a1']!.out, isTrue);
    expect(replayed.bowling['b1']!.wickets, 0); // no bowler credit
    expect(replayed.totalRuns, 6); // 4 + (1 penalty + 1 bat)
    expect(replayed.noBallCount, 1);
  });

  test('wagon-wheel points and retired-hurt markers survive replay', () {
    final inn = _innings();
    _ball(inn, BallInput(batRuns: 4, zone: 3, shotX: 0.7, shotY: 0.2));
    _ball(inn, BallInput(batRuns: 1));
    // Mark a2 retired hurt (not a ball event).
    expect(retireBatsmanHurt(inn, 'a2'), isTrue);
    final edited = List.of(inn.events);
    final replayed = replayInningsBalls(inn, edited);
    expect(replayed, isNotNull);
    expect(replayed!.events[0].zone, 3);
    expect(replayed.events[0].shotX, 0.7);
    expect(replayed.events[0].shotY, 0.2);
    expect(replayed.batting['a2']!.howOut, 'retired hurt');
  });

  test('edit that completes the innings early is refused', () {
    // 2nd innings, target 5, 6 balls recorded totalling 4.
    final m = Match(
      id: 'm1',
      teamAId: 'a',
      teamBId: 'b',
      xiA: ['a1', 'a2', 'a3', 'a4'],
      xiB: ['b1', 'b2', 'b3', 'b4'],
      oversLimit: 2,
      ballsPerOver: 6,
      tossWinnerId: 'a',
      tossDecision: 'bat',
    );
    final inn = startInnings(m, 2);
    inn.target = 5;
    setOpeners(inn, 'a1', 'a2', 'b1');
    _ball(inn, BallInput(batRuns: 1));
    _ball(inn, BallInput(batRuns: 1));
    _ball(inn, BallInput(batRuns: 1));
    _ball(inn, BallInput(batRuns: 1));
    expect(inn.totalRuns, 4);
    // Editing ball 1 to 6 reaches the target on ball 1, so balls
    // 2-4 could never have been played: the replay must refuse.
    final edited = List.of(inn.events);
    edited[0] = BallEvent(
      strikerId: edited[0].strikerId,
      nonStrikerId: edited[0].nonStrikerId,
      bowlerId: edited[0].bowlerId,
      extraType: '',
      batRuns: 6,
      extraRuns: 0,
      isWicket: false,
      wicketType: '',
      outPlayerId: '',
      fielderId: '',
      zone: 0,
      shotX: 0,
      shotY: 0,
      totalRuns: 0,
      legalBall: false,
    );
    expect(replayInningsBalls(inn, edited), isNull);
    expect(inn.totalRuns, 4);
    expect(inn.events.length, 4);
  });
}
