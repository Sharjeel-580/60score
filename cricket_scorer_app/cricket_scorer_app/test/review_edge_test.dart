
import 'package:flutter_test/flutter_test.dart';
import 'package:cricket_scorer_app/models.dart';
import 'package:cricket_scorer_app/scoring.dart';
import 'package:cricket_scorer_app/player_io.dart';

Match _match({int xi = 4, int overs = 2}) => Match(
      id: 'mx',
      teamAId: 'ta',
      teamBId: 'tb',
      xiA: [for (var i = 1; i <= xi; i++) 'a$i'],
      xiB: [for (var i = 1; i <= xi; i++) 'b$i'],
      oversLimit: overs,
      ballsPerOver: 6,
      tossWinnerId: 'ta',
      tossDecision: 'bat',
    );

void main() {
  group('review-pass edge cases', () {
    test('undoing the winning ball reopens the innings', () {
      final m = _match(xi: 3, overs: 1);
      final i1 = startInnings(m, 1);
      setOpeners(i1, 'a1', 'a2', 'b1');
      for (var i = 0; i < 6; i++) {
        applyBall(i1, BallInput(batRuns: 1));
      }
      final i2 = startInnings(m, 2);
      setOpeners(i2, 'b1', 'b2', 'a1');
      applyBall(i2, BallInput(batRuns: 6));
      applyBall(i2, BallInput(batRuns: 1)); // 7 >= target 7
      expect(i2.isComplete, isTrue);
      computeResult(m, (id) => id);
      expect(m.status, 'completed');
      expect(undoLastBall(i2), isTrue);
      expect(i2.isComplete, isFalse);
      expect(i2.totalRuns, 6);
    });

    test('wide with penalty switched off adds only the extra runs', () {
      final m = _match();
      m.widePenalty = false;
      final inn = startInnings(m, 1);
      setOpeners(inn, 'a1', 'a2', 'b1');
      applyBall(inn, BallInput(extraType: 'wide', extraRuns: 2));
      expect(inn.totalRuns, 2);
      expect(inn.legalBalls, 0);
    });

    test('no further balls can be applied once innings is complete', () {
      final m = _match(xi: 3, overs: 1);
      final inn = startInnings(m, 1);
      setOpeners(inn, 'a1', 'a2', 'b1');
      for (var i = 0; i < 6; i++) {
        applyBall(inn, BallInput(batRuns: 0));
      }
      expect(inn.isComplete, isTrue);
      expect(applyBall(inn, BallInput(batRuns: 4)), isFalse);
      expect(inn.totalRuns, 0);
    });

    test('partnerships split at wickets and mark the unbroken pair', () {
      final m = _match();
      final inn = startInnings(m, 1);
      setOpeners(inn, 'a1', 'a2', 'b1');
      applyBall(inn, BallInput(batRuns: 2));
      applyBall(inn, BallInput(isWicket: true, wicketType: 'bowled'));
      setNextBatter(inn, 'a3');
      applyBall(inn, BallInput(batRuns: 3));
      final ps = partnerships(inn);
      expect(ps.length, 2);
      expect(ps[0].runs, 2);
      expect(ps[0].unbroken, isFalse);
      expect(ps[1].runs, 3);
      expect(ps[1].unbroken, isTrue);
    });

    test('worm and manhattan data track overs correctly', () {
      final m = _match();
      final inn = startInnings(m, 1);
      setOpeners(inn, 'a1', 'a2', 'b1');
      for (final r in [1, 2, 0, 4, 0, 1, 6, 0]) {
        if (inn.awaitingBowler) setBowler(inn, 'b2');
        applyBall(inn, BallInput(batRuns: r));
      }
      expect(manhattanData(inn), [8, 6]);
      expect(wormData(inn), [8, 14]);
    });

    test('import normalizes role and styles to canonical values', () {
      final parsed = rowsFromMatrix([
        ['Player Name', 'Role', 'Batting Style', 'Bowling Style', 'Jersey No'],
        ['Test Player', 'Batsman', 'Left Handed', 'Left arm spin', '7.0'],
      ]);
      expect(parsed.errors, isEmpty);
      final r = parsed.rows.single;
      expect(r.role, 'Batter');
      expect(r.battingStyle, 'Left-hand');
      expect(r.bowlingStyle, 'Left-arm spin');
      expect(r.jerseyNo, 7); // '7.0' must not become 70
    });

    test('csv remarks with embedded newline survive round trip', () {
      final rows = [
        PlayerRow(playerName: 'Multi Line', remarks: 'line one\nline two'),
      ];
      final parsed = parsePlayersCsv(rowsToCsv(rows));
      expect(parsed.rows.single.remarks, 'line one\nline two');
    });

    test('duplicate player names import as separate rows (no crash)', () {
      final parsed = parsePlayersCsv(
          'Player Name,Team Name\nSame Name,AB Knights\nSame Name,MA Kings\n');
      expect(parsed.rows.length, 2);
      expect(parsed.rows.map((r) => r.teamName), ['AB Knights', 'MA Kings']);
    });
  });
}
