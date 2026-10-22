// Result-consistency step in the per-match merge (v1.3.6).
//
// Two completed copies of the same match can tie on status and
// legal balls while one of them carries a result text that
// contradicts its own figures — the real Match 01 record read
// "won by 9 wickets" for a chase that ended 118/2 (true margin
// 8). Under the v1.3.5 comparison the corrupt copy won whenever
// it held more ball events, resurrecting its wrong player
// credits. Now, between two completed copies, the self-
// consistent one wins before ball events are ever counted;
// every other case falls through to the old steps unchanged.
import 'package:flutter_test/flutter_test.dart';
import 'package:cricket_scorer_app/models.dart';
import 'package:cricket_scorer_app/sync_service.dart';

const _xiA = [
  'a1', 'a2', 'a3', 'a4', 'a5', 'a6', 'a7', 'a8', 'a9', 'a10', 'a11',
];
const _xiB = [
  'b1', 'b2', 'b3', 'b4', 'b5', 'b6', 'b7', 'b8', 'b9', 'b10', 'b11',
];

InningsState inn({
  required String battingTeamId,
  required int runs,
  int wickets = 0,
  int legalBalls = 48,
  int events = 0,
}) {
  final i = InningsState(
    battingTeamId: battingTeamId,
    bowlingTeamId: battingTeamId == 'ta' ? 'tb' : 'ta',
    battingXI: battingTeamId == 'ta' ? _xiA : _xiB,
    bowlingXI: battingTeamId == 'ta' ? _xiB : _xiA,
    oversLimit: 8,
    ballsPerOver: 6,
  );
  i.totalRuns = runs;
  i.wickets = wickets;
  i.legalBalls = legalBalls;
  for (var n = 0; n < events; n++) {
    i.events.add(BallEvent(
      strikerId: 'a1',
      nonStrikerId: 'a2',
      bowlerId: 'b1',
      totalRuns: 1,
      legalBall: true,
    ));
  }
  return i;
}

/// A completed two-innings match: [first] batted first, [second]
/// batted second. The 11-player XIs make the wicket ceiling 10.
Match completed(
  String id, {
  required int first,
  required int second,
  int firstWickets = 8,
  int secondWickets = 2,
  required String resultText,
  int firstEvents = 0,
  int secondEvents = 0,
}) {
  return Match(
    id: id,
    teamAId: 'ta',
    teamBId: 'tb',
    xiA: _xiA,
    xiB: _xiB,
    tossWinnerId: 'ta',
    tossDecision: 'bat',
    status: 'completed',
    resultText: resultText,
    innings: [
      inn(
          battingTeamId: 'ta',
          runs: first,
          wickets: firstWickets,
          events: firstEvents),
      inn(
          battingTeamId: 'tb',
          runs: second,
          wickets: secondWickets,
          events: secondEvents),
    ],
  );
}

void main() {
  group('SyncService merge result consistency (v1.3.6)', () {
    test('(a) consistent copy with FEWER events beats an '
        'inconsistent copy with more events (117/8 vs 118/2: '
        '"8 wickets" true, "9 wickets" corrupt)', () {
      final consistent = completed('m1',
          first: 117,
          second: 118,
          resultText: 'Adi Dolphins won by 8 wickets',
          firstEvents: 12,
          secondEvents: 10);
      final corrupt = completed('m1',
          first: 117,
          second: 118,
          resultText: 'Adi Dolphins won by 9 wickets',
          firstEvents: 60,
          secondEvents: 56);
      expect(SyncService.compareMatchAdvancement(consistent, corrupt),
          greaterThan(0));
      expect(SyncService.compareMatchAdvancement(corrupt, consistent),
          lessThan(0));
      expect(SyncService.mergeMatches([corrupt], [consistent]).single,
          same(consistent));
      expect(SyncService.mergeMatches([consistent], [corrupt]).single,
          same(consistent));
    });

    test('(b) both consistent: the copy with more ball events '
        'still wins', () {
      final thin = completed('m1',
          first: 117,
          second: 118,
          resultText: 'Adi Dolphins won by 8 wickets',
          firstEvents: 12,
          secondEvents: 10);
      final rich = completed('m1',
          first: 117,
          second: 118,
          resultText: 'Adi Dolphins won by 8 wickets',
          firstEvents: 60,
          secondEvents: 56);
      expect(SyncService.mergeMatches([thin], [rich]).single,
          same(rich));
      expect(SyncService.mergeMatches([rich], [thin]).single,
          same(rich));
    });

    test('(c) winner batted first: runs-margin consistency '
        '("won by 20 runs" beats a corrupt "won by 25 runs")',
        () {
      final consistent = completed('m1',
          first: 150,
          second: 130,
          firstWickets: 7,
          secondWickets: 10,
          resultText: 'Team A won by 20 runs',
          firstEvents: 10,
          secondEvents: 8);
      final corrupt = completed('m1',
          first: 150,
          second: 130,
          firstWickets: 7,
          secondWickets: 10,
          resultText: 'Team A won by 25 runs',
          firstEvents: 60,
          secondEvents: 56);
      expect(SyncService.compareMatchAdvancement(consistent, corrupt),
          greaterThan(0));
      expect(SyncService.mergeMatches([corrupt], [consistent]).single,
          same(consistent));
    });

    test('(d) tie: equal totals + "Match tied" beats an '
        'inconsistent non-tie text with more events', () {
      final consistent = completed('m1',
          first: 120,
          second: 120,
          resultText: 'Match tied',
          firstEvents: 10,
          secondEvents: 8);
      final corrupt = completed('m1',
          first: 120,
          second: 120,
          resultText: 'Team A won by 5 runs',
          firstEvents: 60,
          secondEvents: 56);
      expect(SyncService.compareMatchAdvancement(consistent, corrupt),
          greaterThan(0));
      expect(SyncService.mergeMatches([corrupt], [consistent]).single,
          same(consistent));
    });

    test('(e) empty resultText on one side is unparseable: the '
        'check falls through and ball events decide as before',
        () {
      final bare = completed('m1',
          first: 117,
          second: 118,
          resultText: '',
          firstEvents: 60,
          secondEvents: 56);
      final consistent = completed('m1',
          first: 117,
          second: 118,
          resultText: 'Adi Dolphins won by 8 wickets',
          firstEvents: 12,
          secondEvents: 10);
      expect(SyncService.compareMatchAdvancement(bare, consistent),
          greaterThan(0));
      expect(SyncService.mergeMatches([consistent], [bare]).single,
          same(bare));
    });
  });
}
