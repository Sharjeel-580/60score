import 'package:flutter_test/flutter_test.dart';
import 'package:cricket_scorer_app/models.dart';

// The undo stack must never be persisted: every ball re-encodes the whole
// dataset, and a persisted, uncapped stack grows quadratically per innings
// (the 1.4.2 crash-during-scoring cause). The stack stays in-memory only.

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
    s.undoStack.add('{"totalRuns":1}');
    s.undoStack.add('{"totalRuns":2}');
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
    final j = _innings().toJson()..['undoStack'] = ['{"totalRuns":1}'];
    final restored = InningsState.fromJson(j);
    expect(restored.undoStack, ['{"totalRuns":1}']);
  });
}
