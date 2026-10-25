// No-ball + run-out (v1.4.5): the main UI already offered Run Out
// on a no-ball in one entry; the engine did not guard the
// combination. Law: on a no-ball the batter can only be out run out
// (plus retired out / obstructing the field, which the code already
// supports). Every other dismissal on a no-ball is rejected.
import 'package:flutter_test/flutter_test.dart';

import 'package:cricket_scorer_app/models.dart';
import 'package:cricket_scorer_app/scoring.dart';

InningsState _innings() {
  final s = InningsState(
    battingTeamId: 'ta',
    bowlingTeamId: 'tb',
    battingXI: ['a1', 'a2', 'a3', 'a4'],
    bowlingXI: ['b1', 'b2'],
    oversLimit: 8,
  );
  s.noBallPenalty = true;
  s.widePenalty = true;
  setOpeners(s, 'a1', 'a2', 'b1');
  return s;
}

void main() {
  test('run-out on a no-ball records correctly', () {
    final s = _innings();
    final ok = applyBall(
      s,
      BallInput(
        extraType: 'noBall',
        batRuns: 2,
        isWicket: true,
        wicketType: 'runOut',
        fielderId: 'b2',
        outPlayerId: 'a1',
      ),
    );
    expect(ok, isTrue);
    // 1-run penalty + 2 bat runs; illegal delivery, so no legal ball.
    expect(s.totalRuns, 3);
    expect(s.noBallCount, 1);
    expect(s.legalBalls, 0);
    expect(s.wickets, 1);
    // No bowler wicket credit for a run out; no-ball counted.
    expect(s.bowling['b1']!.wickets, 0);
    expect(s.bowling['b1']!.noBalls, 1);
    expect(s.bowling['b1']!.runs, 3);
    // Batter keeps the bat runs and the ball faced; is out.
    expect(s.batting['a1']!.runs, 2);
    expect(s.batting['a1']!.balls, 1);
    expect(s.batting['a1']!.out, isTrue);
    // Event carries both halves of the entry.
    final ev = s.events.last;
    expect(ev.extraType, 'noBall');
    expect(ev.wicketType, 'runOut');
    expect(ev.legalBall, isFalse);
    expect(ev.outPlayerId, 'a1');
    expect(s.awaitingBatter, isTrue);
    expect(s.undoStack.length, 1);
  });

  test('non-run-out dismissals on a no-ball are rejected, state '
      'untouched', () {
    const blocked = [
      'bowled',
      'caught',
      'lbw',
      'stumped',
      'hitWicket',
      'mankad',
      'hitTwice',
      'timedOut',
    ];
    for (final type in blocked) {
      final s = _innings();
      final ok = applyBall(
        s,
        BallInput(
          extraType: 'noBall',
          batRuns: 0,
          isWicket: true,
          wicketType: type,
          fielderId: 'b2',
          outPlayerId: 'a1',
        ),
      );
      expect(ok, isFalse, reason: type);
      expect(s.totalRuns, 0, reason: type);
      expect(s.wickets, 0, reason: type);
      expect(s.events, isEmpty, reason: type);
      expect(s.noBallCount, 0, reason: type);
      expect(s.undoStack, isEmpty, reason: type);
    }
  });

  test('retired out and obstructing on a no-ball are allowed', () {
    for (final type in ['retiredOut', 'obstructing']) {
      final s = _innings();
      final ok = applyBall(
        s,
        BallInput(
          extraType: 'noBall',
          batRuns: 0,
          isWicket: true,
          wicketType: type,
          outPlayerId: 'a1',
        ),
      );
      expect(ok, isTrue, reason: type);
      expect(s.wickets, 1, reason: type);
      expect(s.noBallCount, 1, reason: type);
    }
  });

  test('run-out on a normal ball still works', () {
    final s = _innings();
    final ok = applyBall(
      s,
      BallInput(
        batRuns: 1,
        isWicket: true,
        wicketType: 'runOut',
        fielderId: 'b2',
        outPlayerId: 'a1',
      ),
    );
    expect(ok, isTrue);
    expect(s.wickets, 1);
    expect(s.legalBalls, 1);
    expect(s.totalRuns, 1);
  });

  test('plain no-ball without wicket still works', () {
    final s = _innings();
    final ok = applyBall(
      s,
      BallInput(extraType: 'noBall', batRuns: 1),
    );
    expect(ok, isTrue);
    expect(s.totalRuns, 2);
    expect(s.legalBalls, 0);
    expect(s.noBallCount, 1);
    expect(s.wickets, 0);
  });
}
