// Playing XI editing (v1.3.5): the XI of a completed match can be
// corrected from the scorecard editor, and of a live match from the
// scoring screen. Defaults hold throughout: XI is 11 by default and
// the wicket limit stays 10 — an XI edit never touches maxWickets.
import 'package:flutter_test/flutter_test.dart';
import 'package:cricket_scorer_app/models.dart';
import 'package:cricket_scorer_app/scoring.dart';

Match twoInningsMatch() {
  final m = Match(
    id: 'm1',
    teamAId: 'ta',
    teamBId: 'tb',
    xiA: const ['a1', 'a2', 'a3'],
    xiB: const ['b1', 'b2', 'b3'],
    oversLimit: 8,
    ballsPerOver: 6,
    tossWinnerId: 'ta',
    status: 'completed',
  );
  final i1 = InningsState(
    battingTeamId: 'ta',
    bowlingTeamId: 'tb',
    battingXI: ['a1', 'a2', 'a3'],
    bowlingXI: ['b1', 'b2', 'b3'],
    oversLimit: 8,
  );
  i1.maxWickets = 10;
  i1.batting['a1'] = BatFig()
    ..batted = true
    ..runs = 30
    ..balls = 12;
  i1.batting['a2'] = BatFig()
    ..batted = true
    ..runs = 10
    ..balls = 8
    ..out = true;
  i1.bowling['b1'] = BowlFig()
    ..legalBalls = 12
    ..runs = 25
    ..wickets = 1;
  final i2 = InningsState(
    battingTeamId: 'tb',
    bowlingTeamId: 'ta',
    battingXI: ['b1', 'b2', 'b3'],
    bowlingXI: ['a1', 'a2', 'a3'],
    oversLimit: 8,
  );
  i2.maxWickets = 10;
  m.innings.addAll([i1, i2]);
  return m;
}

void main() {
  group('addToMatchXI', () {
    test('adds to the match XI and both innings side lists, with a '
        'did-not-bat figure row on the batting side', () {
      final m = twoInningsMatch();
      addToMatchXI(m, 'ta', 'a9');
      expect(m.xiA, contains('a9'));
      expect(m.innings[0].battingXI, contains('a9'));
      expect(m.innings[0].batting['a9'], isNotNull);
      expect(m.innings[0].batting['a9']!.batted, isFalse);
      expect(m.innings[1].bowlingXI, contains('a9'));
    });

    test('is idempotent and never touches the wicket limit', () {
      final m = twoInningsMatch();
      addToMatchXI(m, 'ta', 'a9');
      addToMatchXI(m, 'ta', 'a9');
      expect(m.xiA.where((id) => id == 'a9'), hasLength(1));
      expect(m.innings[0].maxWickets, 10);
      expect(m.innings[0].effectiveMaxWickets, 10);
    });
  });

  group('removeFromMatchXI', () {
    test('removes the player and his figures from the whole match; '
        'totals recompute from the remaining figures', () {
      final m = twoInningsMatch();
      removeFromMatchXI(m, 'ta', 'a1');
      expect(m.xiA, isNot(contains('a1')));
      expect(m.innings[0].battingXI, isNot(contains('a1')));
      expect(m.innings[0].batting.containsKey('a1'), isFalse);
      expect(m.innings[1].bowlingXI, isNot(contains('a1')));
      recomputeInningsTotals(m.innings[0]);
      expect(m.innings[0].totalRuns, 10); // only a2's runs remain
    });

    test('removing a bowler removes his bowling figures', () {
      final m = twoInningsMatch();
      removeFromMatchXI(m, 'tb', 'b1');
      expect(m.innings[0].bowling.containsKey('b1'), isFalse);
      expect(m.innings[0].bowlingXI, isNot(contains('b1')));
      expect(m.xiB, isNot(contains('b1')));
    });
  });

  group('liveXiRemovalBlock', () {
    test('the striker, non-striker and current bowler are locked', () {
      final m = twoInningsMatch();
      final inn = m.innings[0];
      inn.strikerId = 'a1';
      inn.nonStrikerId = 'a2';
      inn.currentBowlerId = 'b1';
      expect(liveXiRemovalBlock(m, inn, 'a1'), contains('striker'));
      expect(liveXiRemovalBlock(m, inn, 'a2'), contains('non-striker'));
      expect(liveXiRemovalBlock(m, inn, 'b1'), contains('bowler'));
    });

    test('a player who already batted or bowled is locked; a fresh '
        'XI player is removable', () {
      final m = twoInningsMatch();
      final inn = m.innings[0];
      expect(liveXiRemovalBlock(m, inn, 'a1'), contains('batted'));
      expect(liveXiRemovalBlock(m, inn, 'b1'), contains('bowled'));
      expect(liveXiRemovalBlock(m, inn, 'a3'), isNull);
      expect(liveXiRemovalBlock(m, inn, 'b3'), isNull);
    });
  });
}
