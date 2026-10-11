import 'package:flutter_test/flutter_test.dart';
import 'package:cricket_scorer_app/models.dart';
import 'package:cricket_scorer_app/scoring.dart';

Match mkMatch(String id, {String? tid}) => Match(
  id: id,
  tournamentId: tid,
  teamAId: 'ta',
  teamBId: 'tb',
  xiA: const ['a1', 'a2', 'a3', 'a4'],
  xiB: const ['b1', 'b2', 'b3', 'b4'],
  oversLimit: 10,
  tossWinnerId: 'ta',
);

void runs(InningsState s, int r) {
  // A completed over clears the bowler; pick the next eligible one.
  if (s.currentBowlerId.isEmpty) {
    final next = s.bowlingXI.firstWhere((id) => id != s.lastBowlerId);
    expect(setBowler(s, next), isTrue);
  }
  expect(applyBall(s, BallInput(batRuns: r)), isTrue);
}

InningsState openFirst(Match m) {
  final inn = startInnings(m, 1);
  setOpeners(inn, 'a1', 'a2', 'b1');
  return inn;
}

// 5x6 + 3 keeps the same batter on strike across the over-end swap.
void over33(InningsState inn) {
  for (final r in [6, 6, 6, 6, 6, 3]) {
    runs(inn, r);
  }
}

// Hand-built event stream for milestone-logic tests (the engine path is
// already covered by scoring_test.dart and the tests below).
BallEvent ev(String striker, int r, {String extra = 'none'}) => BallEvent(
  strikerId: striker,
  nonStrikerId: 'a2',
  bowlerId: 'b1',
  extraType: extra,
  batRuns: r,
  totalRuns: extra == 'wide' ? 1 : r,
  legalBall: extra != 'wide',
);

Match fakeMatch(String id, String tid, List<BallEvent> events) {
  final m = mkMatch(id, tid: tid);
  final inn = InningsState(
    battingTeamId: 'ta',
    bowlingTeamId: 'tb',
    battingXI: const ['a1', 'a2', 'a3', 'a4'],
    bowlingXI: const ['b1', 'b2', 'b3', 'b4'],
    oversLimit: 10,
  );
  inn.events.addAll(events);
  m.innings.add(inn);
  m.status = 'completed';
  return m;
}

void main() {
  group('fastestMilestones', () {
    test('fifty recorded with balls faced in order (engine)', () {
      final m = mkMatch('m1', tid: 't1');
      final inn = openFirst(m);
      over33(inn); // a1 33/6, keeps strike
      for (final r in [6, 6, 6]) {
        runs(inn, r);
      } // a1 51/9 -> fifty in 9 balls
      m.status = 'completed';
      final f = fastestMilestones([m], tournamentId: 't1');
      expect(f.fifties.length, 1);
      expect(f.fifties.first.playerId, 'a1');
      expect(f.fifties.first.balls, 9);
      expect(f.fifties.first.runs, 51);
      expect(f.hundreds, isEmpty);
    });

    test('wides do not count as balls faced (engine)', () {
      final m = mkMatch('m1', tid: 't1');
      final inn = openFirst(m);
      over33(inn);
      runs(inn, 6);
      runs(inn, 6);
      expect(applyBall(inn, BallInput(extraType: 'wide')), isTrue);
      runs(inn, 6); // 51 runs off 9 balls faced
      m.status = 'completed';
      final f = fastestMilestones([m], tournamentId: 't1');
      expect(f.fifties.first.balls, 9);
    });

    test('hundred tracked after fifty for the same batter', () {
      final events = <BallEvent>[
        for (var i = 0; i < 8; i++) ev('a1', 6), // 48/8
        ev('a1', 2), // 50/9 -> fifty in 9
        for (var i = 0; i < 8; i++) ev('a1', 6), // 98/17
        ev('a1', 2), // 100/18 -> hundred in 18
      ];
      final m = fakeMatch('m1', 't1', events);
      final f = fastestMilestones([m], tournamentId: 't1');
      expect(f.fifties.length, 1);
      expect(f.fifties.first.balls, 9);
      expect(f.hundreds.length, 1);
      expect(f.hundreds.first.playerId, 'a1');
      expect(f.hundreds.first.balls, 18);
      expect(f.hundreds.first.runs, 100);
    });

    test('byes do not count toward milestone runs', () {
      final events = <BallEvent>[
        for (var i = 0; i < 8; i++) ev('a1', 6), // 48/8
        ev('a1', 4, extra: 'bye'), // ball 9, batter still 48
        ev('a1', 2), // 50/10 -> fifty in 10 balls faced
      ];
      final m = fakeMatch('m1', 't1', events);
      final f = fastestMilestones([m], tournamentId: 't1');
      expect(f.fifties.length, 1);
      expect(f.fifties.first.balls, 10);
      expect(f.fifties.first.runs, 50);
    });

    test('tournament scope filters other tournaments', () {
      List<BallEvent> fifty(String p) => [
        for (var i = 0; i < 8; i++) ev(p, 6),
        ev(p, 2),
      ];
      final m1 = fakeMatch('m1', 't1', fifty('a1'));
      final m2 = fakeMatch('m2', 't2', fifty('a1'));
      final f1 = fastestMilestones([m1, m2], tournamentId: 't1');
      expect(f1.fifties.length, 1);
      expect(f1.fifties.first.playerId, 'a1');
      final fall = fastestMilestones([m1, m2]);
      expect(fall.fifties.length, 2);
    });
  });

  group('inningsPowerLeaders', () {
    test('most sixes and fours in a single innings', () {
      final m = mkMatch('m1', tid: 't1');
      final inn = openFirst(m);
      runs(inn, 6);
      runs(inn, 6);
      runs(inn, 6); // a1: 3 sixes
      runs(inn, 1); // a2 on strike
      runs(inn, 4);
      runs(inn, 4); // a2: 2 fours
      m.status = 'completed';
      final p = inningsPowerLeaders([m], tournamentId: 't1');
      expect(p.sixes.first.playerId, 'a1');
      expect(p.sixes.first.count, 3);
      expect(p.fours.first.playerId, 'a2');
      expect(p.fours.first.count, 2);
    });
  });

  group('bestPartnerships', () {
    test('sorted by runs desc', () {
      final m = mkMatch('m1', tid: 't1');
      final inn = openFirst(m);
      runs(inn, 4); // a1
      runs(inn, 1); // a1 -> a2 on strike
      runs(inn, 6); // a2 => partnership 11
      expect(
        applyBall(inn, BallInput(isWicket: true, wicketType: 'bowled')),
        isTrue,
      );
      setNextBatter(inn, 'a3');
      runs(inn, 2); // partnership 2
      m.status = 'completed';
      final list = bestPartnerships([m], tournamentId: 't1');
      expect(list.first.runs, 11);
      expect(list[1].runs, 2);
    });
  });

  group('Match new fields', () {
    test('matchTitle/ballType/season round-trip through JSON', () {
      final m = mkMatch('m1')
        ..matchTitle = 'Final'
        ..ballType = 'Leather Ball'
        ..season = '2025';
      final back = Match.fromJson(m.toJson());
      expect(back.matchTitle, 'Final');
      expect(back.ballType, 'Leather Ball');
      expect(back.season, '2025');
    });

    test('old JSON without new keys gets defaults', () {
      final m = mkMatch('m1');
      final j = m.toJson()
        ..remove('matchTitle')
        ..remove('ballType')
        ..remove('season');
      final back = Match.fromJson(j);
      expect(back.matchTitle, '');
      expect(back.ballType, 'Tennis Ball');
      expect(back.season, '');
    });
  });
}
