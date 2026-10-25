import 'package:flutter_test/flutter_test.dart';
import 'package:cricket_scorer_app/models.dart';

// The undo stack must never be persisted: every ball re-encodes the whole
// dataset, and a persisted, uncapped stack grows quadratically per innings
// (the 1.4.2 crash-during-scoring cause). The stack stays in-memory only.
// (v1.4.4: the stack holds UndoStep reverse steps, not snapshot strings,
// and a legacy string stack in a payload is dropped on load.)

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

InningsState _innings() => InningsState(
      battingTeamId: 'ta',
      bowlingTeamId: 'tb',
      battingXI: ['a1', 'a2'],
      bowlingXI: ['b1', 'b2'],
      oversLimit: 8,
    );

void main() {
  test('toJson never contains undoStack, even when the stack is non-empty',
      () {
    final s = _innings();
    s.undoStack.add(_step());
    s.undoStack.add(_step());
    expect(s.toJson().containsKey('undoStack'), isFalse);
  });

  test('fromJson without undoStack yields an empty stack', () {
    final j = _innings().toJson();
    expect(j.containsKey('undoStack'), isFalse);
    final restored = InningsState.fromJson(j);
    expect(restored.undoStack, isEmpty);
  });

  test('fromJson tolerates a legacy payload that still carries undoStack',
      () {
    // v1.4.4: the legacy string stack is DROPPED on load (undo is
    // session-only; restoring old snapshots would reintroduce the
    // snapshot balloon). Tolerated = no throw, empty stack.
    final j = _innings().toJson()..['undoStack'] = ['{"totalRuns":1}'];
    final restored = InningsState.fromJson(j);
    expect(restored.undoStack, isEmpty);
  });
}
