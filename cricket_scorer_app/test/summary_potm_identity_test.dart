// v1.4.8: POTM identity-robust bowling (screenshot case: M08, POTM
// Hamza 360's batting under his squad id, his 2/22 bowling under a
// duplicate fresh id with the same display name), the squad-name
// dedupe guard, and long-name share-image layout.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cricket_scorer_app/models.dart';
import 'package:cricket_scorer_app/scoring.dart';
import 'package:cricket_scorer_app/store.dart';
import 'package:cricket_scorer_app/summary_share.dart';

Player _p(String id, String name) => Player(id: id, name: name);

BatFig _bat(int runs, int balls, int fours, int sixes,
    {required bool out}) {
  return BatFig()
    ..batted = true
    ..runs = runs
    ..balls = balls
    ..fours = fours
    ..sixes = sixes
    ..out = out;
}

BowlFig _bowl(int balls, int runs, int wickets) {
  return BowlFig()
    ..legalBalls = balls
    ..runs = runs
    ..wickets = wickets;
}

/// M08-shaped store: Hamza 360 exists under TWO ids with the same
/// display name (squad id + a fresh mid-match "Add new player" id),
/// plus a case-variant id for the tolerance test.
Store _m08Store() {
  final s = Store();
  s.teams = [
    Team(id: 'shazi', name: 'Shazi Hawks', players: [
      _p('hamza_squad', 'Hamza 360'),
      _p('hamza_fresh', 'Hamza 360'),
      _p('hamza_third', 'Hamza 360'),
      _p('hamza_caps', 'HAMZA 360'),
      _p('shahzad', 'Shahzad'),
    ]),
    Team(id: 'ab', name: 'AB Knights', players: [
      _p('naeem', 'Naeem'),
      _p('bilal', 'Malik Bilal'),
    ]),
  ];
  s.tournaments = [
    Tournament(id: 'ssl', name: 'Super Sixty League', venue: '75 Lokri Club'),
  ];
  return s;
}

/// M08 shape: innings 1 Shazi batting (Hamza 35 under the squad id),
/// innings 2 AB batting (Hamza's 2/22 bowling under the fresh id).
Match _m08Match({String manOfMatchId = 'hamza_squad'}) {
  final m = Match(
    id: 'ssl2_m08',
    tournamentId: 'ssl',
    teamAId: 'shazi',
    teamBId: 'ab',
    xiA: const ['hamza_squad', 'shahzad'],
    xiB: const ['naeem', 'bilal'],
    oversLimit: 8,
    ballsPerOver: 6,
    venue: '75 Lokri Club',
    dateIso: '2026-10-29',
    tossWinnerId: 'shazi',
    status: 'completed',
    resultText: 'Shazi Hawks won by 30 runs',
    manOfMatchId: manOfMatchId,
  );
  final inn1 = InningsState(
    battingTeamId: 'shazi',
    bowlingTeamId: 'ab',
    battingXI: m.xiA,
    bowlingXI: m.xiB,
    oversLimit: 8,
    ballsPerOver: 6,
  )
    ..totalRuns = 134
    ..wickets = 3
    ..legalBalls = 48;
  inn1.batting['hamza_squad'] = _bat(35, 19, 3, 3, out: true);
  inn1.batting['shahzad'] = _bat(36, 15, 2, 4, out: true);
  final inn2 = InningsState(
    battingTeamId: 'ab',
    bowlingTeamId: 'shazi',
    battingXI: m.xiB,
    bowlingXI: m.xiA,
    oversLimit: 8,
    ballsPerOver: 6,
  )
    ..totalRuns = 104
    ..wickets = 5
    ..legalBalls = 48;
  inn2.batting['naeem'] = _bat(23, 10, 0, 3, out: true);
  // Screenshot case: the bowling sits under the FRESH id, not the
  // squad id the 1.4.7 panel looked up.
  inn2.bowling['hamza_fresh'] = _bowl(12, 22, 2);
  m.innings.addAll([inn1, inn2]);
  return m;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('aggregatePotmBowling — duplicate-identity fallback', () {
    test('screenshot case: bowling under a same-name id is found', () {
      final s = _m08Store();
      final r = aggregatePotmBowling(
          _m08Match().innings, 'hamza_squad', s.playerName);
      expect(r.bowled, isTrue);
      expect(r.wickets, 2);
      expect(r.balls, 12);
      expect(r.runs, 22);
    });

    test('exact-id bowling wins; same-name figures are not added', () {
      final s = _m08Store();
      final m = _m08Match();
      m.innings[1].bowling['hamza_squad'] = _bowl(6, 15, 1);
      final r =
          aggregatePotmBowling(m.innings, 'hamza_squad', s.playerName);
      expect(r.bowled, isTrue);
      expect(r.wickets, 1);
      expect(r.balls, 6);
      expect(r.runs, 15);
    });

    test('pure batter: no bowling anywhere', () {
      final s = _m08Store();
      final r =
          aggregatePotmBowling(_m08Match().innings, 'shahzad', s.playerName);
      expect(r.bowled, isFalse);
      expect(r.wickets, 0);
      expect(r.balls, 0);
      expect(r.runs, 0);
    });

    test('several same-name pids are all summed', () {
      final s = _m08Store();
      final m = _m08Match();
      m.innings[1].bowling['hamza_third'] = _bowl(6, 10, 1);
      final r =
          aggregatePotmBowling(m.innings, 'hamza_squad', s.playerName);
      expect(r.bowled, isTrue);
      expect(r.wickets, 3);
      expect(r.balls, 18);
      expect(r.runs, 32);
    });

    test('placeholder names never match (unknown ids stay unknown)', () {
      final s = _m08Store();
      final m = _m08Match();
      m.innings[1].bowling['player_1792580865575803_88'] = _bowl(12, 22, 2);
      final r = aggregatePotmBowling(
          m.innings, 'player_1792580865575803_99', s.playerName);
      expect(r.bowled, isFalse);
    });

    test('wides-only bowling under the same name does not count', () {
      final s = _m08Store();
      final m = _m08Match();
      m.innings[1].bowling['hamza_fresh'] = BowlFig()
        ..legalBalls = 0
        ..runs = 5
        ..wickets = 0;
      final r =
          aggregatePotmBowling(m.innings, 'hamza_squad', s.playerName);
      expect(r.bowled, isFalse);
    });

    test('name match is trimmed and case-insensitive', () {
      final s = _m08Store();
      final m = _m08Match();
      m.innings[1].bowling.clear();
      m.innings[1].bowling['hamza_caps'] = _bowl(12, 22, 2);
      final r =
          aggregatePotmBowling(m.innings, 'hamza_squad', s.playerName);
      expect(r.bowled, isTrue);
      expect(r.wickets, 2);
    });
  });

  group('uniqueSquadPlayerByName — dedupe guard', () {
    test('unique match, case-insensitive and trimmed', () {
      final t = Team(id: 't', name: 'T', players: [
        _p('a', 'Hamza 360'),
        _p('b', 'Shahzad'),
      ]);
      expect(uniqueSquadPlayerByName(t, '  hamza 360 ')!.id, 'a');
    });

    test('no match returns null', () {
      final t = Team(id: 't', name: 'T', players: [_p('a', 'Shahzad')]);
      expect(uniqueSquadPlayerByName(t, 'Hamza 360'), isNull);
    });

    test('ambiguous name returns null, never guesses', () {
      final t = Team(id: 't', name: 'T', players: [
        _p('a', 'Hamza 360'),
        _p('b', 'Hamza 360'),
      ]);
      expect(uniqueSquadPlayerByName(t, 'Hamza 360'), isNull);
    });
  });

  testWidgets('long names render without overflow in the share card',
      (tester) async {
    final s = Store();
    s.teams = [
      Team(id: 'long_a', name: 'A Very Long Team Name That Keeps Going',
          players: [
            _p('p1', 'A Very Long Player Name Indeed'),
            _p('p2', 'Another Extremely Long Player Name Here'),
          ]),
      Team(id: 'long_b', name: 'Yet Another Very Long Team Name Here',
          players: [
            _p('p3', 'A Third Very Long Player Name Indeed'),
          ]),
    ];
    s.tournaments = [
      Tournament(id: 'ssl', name: 'Super Sixty League',
          venue: '75 Lokri Club'),
    ];
    final m = Match(
      id: 'm-long',
      tournamentId: 'ssl',
      teamAId: 'long_a',
      teamBId: 'long_b',
      xiA: const ['p1', 'p2'],
      xiB: const ['p3'],
      oversLimit: 8,
      ballsPerOver: 6,
      venue: '75 Lokri Club',
      dateIso: '2026-10-29',
      tossWinnerId: 'long_a',
      status: 'completed',
      resultText: 'A Very Long Team Name That Keeps Going won by 10 runs',
      manOfMatchId: 'p1',
    );
    final inn1 = InningsState(
      battingTeamId: 'long_a',
      bowlingTeamId: 'long_b',
      battingXI: m.xiA,
      bowlingXI: m.xiB,
      oversLimit: 8,
      ballsPerOver: 6,
    )
      ..totalRuns = 100
      ..wickets = 2
      ..legalBalls = 48;
    inn1.batting['p1'] = _bat(50, 20, 2, 3, out: true);
    inn1.batting['p2'] = _bat(30, 15, 1, 2, out: true);
    inn1.bowling['p3'] = _bowl(12, 40, 2);
    final inn2 = InningsState(
      battingTeamId: 'long_b',
      bowlingTeamId: 'long_a',
      battingXI: m.xiB,
      bowlingXI: m.xiA,
      oversLimit: 8,
      ballsPerOver: 6,
    )
      ..totalRuns = 90
      ..wickets = 3
      ..legalBalls = 48;
    inn2.batting['p3'] = _bat(40, 20, 1, 2, out: true);
    inn2.bowling['p1'] = _bowl(12, 30, 2);
    inn2.bowling['p2'] = _bowl(12, 35, 1);
    m.innings.addAll([inn1, inn2]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SummaryShareCard(store: s, match: m),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Very Long Player'), findsWidgets);
    expect(find.textContaining('VERY LONG TEAM NAME'), findsWidgets);
  });
}
