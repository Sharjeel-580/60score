// Per-match merge sync (v1.3.5).
//
// The whole-dataset timestamp rule lost real data on 2026-10-22/23:
// a device rejected newer remote matches (its local clock read
// newer), then pushed its stale copy over them. Matches are now
// merged per record — union of ids, most advanced record wins —
// so a completed match can never be un-completed or erased by a
// staler copy, whichever side it sits on.
import 'package:flutter_test/flutter_test.dart';
import 'package:cricket_scorer_app/models.dart';
import 'package:cricket_scorer_app/sync_service.dart';

InningsState inn({
  int legalBalls = 0,
  int events = 0,
  int totalRuns = 0,
}) {
  final i = InningsState(
    battingTeamId: 'ta',
    bowlingTeamId: 'tb',
    battingXI: const ['a1', 'a2'],
    bowlingXI: const ['b1', 'b2'],
    oversLimit: 8,
    ballsPerOver: 6,
  );
  i.legalBalls = legalBalls;
  i.totalRuns = totalRuns;
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

Match match(
  String id, {
  String status = 'upcoming',
  String resultText = '',
  List<InningsState>? innings,
}) {
  return Match(
    id: id,
    teamAId: 'ta',
    teamBId: 'tb',
    xiA: const ['a1', 'a2'],
    xiB: const ['b1', 'b2'],
    tossWinnerId: 'ta',
    status: status,
    resultText: resultText,
    innings: innings,
  );
}

void main() {
  group('SyncService.mergeMatches (v1.3.5)', () {
    test('(a) local stale "live" copy vs remote completed same id: '
        'the completed record wins', () {
      final local = [
        match('m1', status: 'live', innings: [inn(legalBalls: 11)]),
      ];
      final remote = [
        match('m1',
            status: 'completed',
            resultText: 'Team A won by 8 wickets',
            innings: [inn(legalBalls: 48), inn(legalBalls: 48)]),
      ];
      final merged = SyncService.mergeMatches(local, remote);
      expect(merged, hasLength(1));
      expect(merged.single.status, 'completed');
      expect(merged.single.resultText, 'Team A won by 8 wickets');
    });

    test('(b) local completed vs remote stale "live": the local '
        'completed record wins', () {
      final local = [
        match('m1',
            status: 'completed',
            resultText: 'Team A won by 8 wickets',
            innings: [inn(legalBalls: 48), inn(legalBalls: 48)]),
      ];
      final remote = [
        match('m1', status: 'live', innings: [inn(legalBalls: 11)]),
      ];
      final merged = SyncService.mergeMatches(local, remote);
      expect(merged.single.status, 'completed');
      expect(merged.single.resultText, 'Team A won by 8 wickets');
    });

    test('(c) ids unique to each side all survive the merge', () {
      final local = [match('m1'), match('m2', status: 'live')];
      final remote = [match('m2', status: 'live'), match('m3')];
      final merged = SyncService.mergeMatches(local, remote);
      expect(merged.map((m) => m.id), ['m1', 'm2', 'm3']);
    });

    test('(d) two completed copies: the one with more ball events '
        'wins', () {
      final thin = match('m1',
          status: 'completed',
          resultText: 'Team A won',
          innings: [inn(legalBalls: 48, events: 12)]);
      final rich = match('m1',
          status: 'completed',
          resultText: 'Team A won',
          innings: [inn(legalBalls: 48, events: 96)]);
      expect(
        SyncService.mergeMatches([thin], [rich]).single,
        same(rich),
      );
      expect(
        SyncService.mergeMatches([rich], [thin]).single,
        same(rich),
      );
    });

    test('a completed record is never replaced by a non-completed '
        'one, even when the live copy has more balls', () {
      final done = match('m1',
          status: 'completed',
          resultText: 'Team B won by 3 runs',
          innings: [inn(legalBalls: 20)]);
      final live = match('m1',
          status: 'live', innings: [inn(legalBalls: 48, events: 50)]);
      expect(SyncService.compareMatchAdvancement(done, live),
          greaterThan(0));
      expect(SyncService.mergeMatches([live], [done]).single.status,
          'completed');
    });

    test('equal rank and balls: a non-empty result text breaks '
        'the tie', () {
      final bare = match('m1', status: 'live', innings: [inn(legalBalls: 6)]);
      final withResult = match('m1',
          status: 'live',
          resultText: 'Team A won by 8 wickets',
          innings: [inn(legalBalls: 6)]);
      expect(
        SyncService.mergeMatches([bare], [withResult]).single.resultText,
        'Team A won by 8 wickets',
      );
    });

    test('status ranks: completed > noResult/cancelled > live > '
        'upcoming', () {
      expect(SyncService.matchStatusRank('completed'),
          greaterThan(SyncService.matchStatusRank('noResult')));
      expect(SyncService.matchStatusRank('cancelled'),
          greaterThan(SyncService.matchStatusRank('live')));
      expect(SyncService.matchStatusRank('live'),
          greaterThan(SyncService.matchStatusRank('upcoming')));
    });

    test('sameMatchContent compares records, not identity', () {
      final a = match('m1', status: 'live', innings: [inn(legalBalls: 6)]);
      final b = Match.fromJson(a.toJson());
      expect(SyncService.sameMatchContent([a], [b]), isTrue);
      b.status = 'completed';
      expect(SyncService.sameMatchContent([a], [b]), isFalse);
      expect(SyncService.sameMatchContent([a], [a, b]), isFalse);
    });
  });
}
