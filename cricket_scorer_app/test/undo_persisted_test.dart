// Undo persistence (v1.4.5): the delta reverse-step stack IS persisted
// in InningsState JSON (capped at 50), so undo survives a restart —
// the reverse of the v1.4.3/v1.4.4 session-only rule. Steps are
// small by design (scalars + figure copies + lengths, no events,
// no JSON), which is what makes persisting them cheap, unlike the
// old full-innings snapshot strings (still dropped on load).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cricket_scorer_app/models.dart';
import 'package:cricket_scorer_app/scoring.dart';

UndoStep _step() => UndoStep(
      totalRuns: 1,
      wickets: 0,
      legalBalls: 1,
      strikerId: 'a1',
      nonStrikerId: 'a2',
      currentBowlerId: 'b1',
      lastBowlerId: '',
      awaitingBatter: false,
      awaitingBowler: false,
      batting: {},
      bowling: {},
      widesRuns: 0,
      noBallRuns: 0,
      byeRuns: 0,
      legByeRuns: 0,
      noBallCount: 0,
      wideCount: 0,
      eventsLength: 0,
      fallOfWicketsLength: 0,
      currentOverBowlerRuns: 0,
      currentOverTeamRuns: 0,
      target: 0,
      maxWickets: 0,
      widePenalty: true,
      noBallPenalty: true,
    );

InningsState _innings() {
  final s = InningsState(
    battingTeamId: 'ta',
    bowlingTeamId: 'tb',
    // Four batters: with a 2-player XI one wicket would complete
    // the innings (maxWickets defaults to XI-1) and awaitingBatter
    // would read false — the wicket test needs room for a dismissal.
    battingXI: ['a1', 'a2', 'a3', 'a4'],
    bowlingXI: ['b1', 'b2'],
    oversLimit: 8,
  );
  setOpeners(s, 'a1', 'a2', 'b1');
  return s;
}

void _ball(InningsState s, BallInput input) {
  expect(applyBall(s, input), isTrue);
}

void main() {
  test('toJson contains the undoStack once balls have been scored', () {
    final s = _innings();
    expect(s.toJson()['undoStack'], isEmpty);
    _ball(s, BallInput(batRuns: 4));
    final stack = s.toJson()['undoStack'] as List;
    expect(stack.length, 1);
    expect((stack.first as Map)['totalRuns'], 0);
  });

  test('undo survives a toJson/fromJson round-trip and restores state',
      () {
    final s = _innings();
    _ball(s, BallInput(batRuns: 4)); // a1: 4, striker stays a1
    _ball(s, BallInput(batRuns: 1)); // a1: 5, strike rotates to a2
    _ball(s, BallInput(batRuns: 6)); // a2: 6
    expect(s.totalRuns, 11);
    expect(s.legalBalls, 3);
    expect(s.events.length, 3);

    // Simulate a restart: real JSON round-trip, then reload.
    final j =
        jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>;
    final restored = InningsState.fromJson(j);
    expect(restored.totalRuns, 11);
    expect(restored.legalBalls, 3);
    expect(restored.events.length, 3);
    expect(restored.undoStack.length, 3);

    // Undo the 6: back to the pre-ball-3 state.
    expect(undoLastBall(restored), isTrue);
    expect(restored.totalRuns, 5);
    expect(restored.legalBalls, 2);
    expect(restored.events.length, 2);
    expect(restored.batting['a1']!.runs, 5);
    expect(restored.batting['a2']!.runs, 0);
    expect(restored.strikerId, 'a2');
  });

  test('multi-undo after reload walks back through balls and a wicket',
      () {
    final s = _innings();
    _ball(s, BallInput(batRuns: 4));
    _ball(s, BallInput(batRuns: 1));
    _ball(s, BallInput(batRuns: 6));
    _ball(s, BallInput(isWicket: true, wicketType: 'bowled'));
    expect(s.totalRuns, 11);
    expect(s.wickets, 1);
    expect(s.awaitingBatter, isTrue);

    final j =
        jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>;
    final restored = InningsState.fromJson(j);
    expect(restored.undoStack.length, 4);

    // Undo the wicket: figures, wickets and awaiting flag restored.
    expect(undoLastBall(restored), isTrue);
    expect(restored.wickets, 0);
    expect(restored.awaitingBatter, isFalse);
    expect(restored.batting['a2']!.out, isFalse);
    expect(restored.totalRuns, 11);
    // Undo the 6 as well.
    expect(undoLastBall(restored), isTrue);
    expect(restored.totalRuns, 5);
    expect(restored.events.length, 2);
  });

  test('Match-level round-trip keeps the stack and undo working', () {
    final m = Match(
      id: 'm1',
      teamAId: 'ta',
      teamBId: 'tb',
      xiA: ['a1', 'a2'],
      xiB: ['b1', 'b2'],
      oversLimit: 8,
      ballsPerOver: 6,
      tossWinnerId: 'ta',
      tossDecision: 'bat',
    );
    final inn = startInnings(m, 1);
    setOpeners(inn, 'a1', 'a2', 'b1');
    _ball(inn, BallInput(batRuns: 4));
    _ball(inn, BallInput(batRuns: 2));
    final j = jsonDecode(jsonEncode(m.toJson())) as Map<String, dynamic>;
    final reloaded = Match.fromJson(j);
    final reInn = reloaded.innings[0];
    expect(reInn.totalRuns, 6);
    expect(reInn.undoStack.length, 2);
    expect(undoLastBall(reInn), isTrue);
    expect(reInn.totalRuns, 4);
    expect(reInn.events.length, 1);
  });

  test('old JSON without the stack loads fine with an empty stack', () {
    final s = _innings();
    _ball(s, BallInput(batRuns: 4));
    final j = s.toJson()..remove('undoStack');
    expect(j.containsKey('undoStack'), isFalse);
    final restored = InningsState.fromJson(j);
    expect(restored.totalRuns, 4);
    expect(restored.events.length, 1);
    expect(restored.undoStack, isEmpty);
    // And the empty stack still reports honestly: nothing to undo.
    expect(undoLastBall(restored), isFalse);
  });

  test('legacy string stack is dropped, never throws', () {
    final j = _innings().toJson()
      ..['undoStack'] = ['{"totalRuns":1}', '{"totalRuns":2}'];
    final restored = InningsState.fromJson(j);
    expect(restored.undoStack, isEmpty);
  });

  test('one bad stack entry is skipped, the rest load', () {
    final good = _step().toJson();
    final j = _innings().toJson()
      ..['undoStack'] = [good, 'not-a-step', 42];
    final restored = InningsState.fromJson(j);
    expect(restored.undoStack.length, 1);
    expect(restored.undoStack.first.totalRuns, 1);
  });

  test('stack is capped at 50 on load', () {
    final s = _innings();
    for (var i = 0; i < 60; i++) {
      s.undoStack.add(_step());
    }
    final j =
        jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>;
    final restored = InningsState.fromJson(j);
    expect(restored.undoStack.length, 50);
  });
}
