// Poster-style Match Summary (v1.3.8): data shaping over the match
// figures (top-4 batting / top-3 bowling selection, POTM resolution
// and chip derivation), the team-logo mapping, and a layout smoke
// test of the 540x675 card (1080x1350 at pixelRatio 2).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cricket_scorer_app/models.dart';
import 'package:cricket_scorer_app/poster_summary.dart';
import 'package:cricket_scorer_app/store.dart';

Player _p(String id, String name) => Player(id: id, name: name);

Store _leagueStore() {
  final s = Store();
  s.teams = [
    Team(id: 'th', name: 'Shazi Hawks', players: [
      _p('saqib', 'Saqib 17'),
      _p('zohaib', 'Zohaib 31'),
      _p('afroz', 'Afroz'),
      _p('zaheer', 'Raja Zaheer'),
      _p('hamza', 'Hamza'),
    ]),
    Team(id: 'td', name: 'Adi Dolphins', players: [
      _p('nazakat', 'Nazakat 16'),
      _p('sarfaraz', 'Sarfaraz 83'),
      _p('bilal', 'Bilal Choki'),
      _p('irtaza', 'Irtaza Lallani'),
      _p('shuja', 'Shuja Haider'),
      _p('extra', 'Extra Bowler'),
    ]),
  ];
  s.tournaments = [
    Tournament(id: 'ssl', name: 'Super Sixty League', venue: '75 Lokri Club'),
  ];
  return s;
}

BatFig _bat(int runs, int balls, int fours, int sixes, {required bool out}) {
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

/// Match 01 of the Super Sixty League (the approved sample's data).
Match _match01({String manOfMatchId = 'nazakat'}) {
  final m = Match(
    id: 'ssl2_m01',
    tournamentId: 'ssl',
    teamAId: 'th',
    teamBId: 'td',
    xiA: const ['saqib', 'zohaib', 'afroz', 'zaheer', 'hamza'],
    xiB: const ['nazakat', 'sarfaraz', 'bilal', 'irtaza', 'shuja', 'extra'],
    oversLimit: 8,
    ballsPerOver: 6,
    venue: '75 Lokri Club',
    dateIso: '2026-10-22',
    season: '2K26',
    tossWinnerId: 'th',
    status: 'completed',
    resultText: 'Adi Dolphins won by 8 wickets',
    manOfMatchId: manOfMatchId,
  );
  final inn1 = InningsState(
    battingTeamId: 'th',
    bowlingTeamId: 'td',
    battingXI: m.xiA,
    bowlingXI: m.xiB,
    oversLimit: 8,
  )
    ..totalRuns = 117
    ..wickets = 8
    ..legalBalls = 48;
  inn1.batting['saqib'] = _bat(35, 12, 3, 3, out: false);
  inn1.batting['zohaib'] = _bat(21, 7, 2, 2, out: true);
  inn1.batting['afroz'] = _bat(18, 8, 1, 2, out: true);
  inn1.batting['zaheer'] = _bat(11, 9, 1, 1, out: true);
  inn1.batting['hamza'] = _bat(6, 5, 0, 0, out: true); // 5th: cut off
  inn1.bowling['bilal'] = _bowl(12, 25, 3);
  inn1.bowling['nazakat'] = _bowl(12, 27, 2);
  inn1.bowling['shuja'] = _bowl(6, 10, 1);
  // Same wickets as Shuja but a worse economy: must rank below him.
  inn1.bowling['extra'] = _bowl(6, 30, 1);
  final inn2 = InningsState(
    battingTeamId: 'td',
    bowlingTeamId: 'th',
    battingXI: m.xiB,
    bowlingXI: m.xiA,
    oversLimit: 8,
  )
    ..totalRuns = 118
    ..wickets = 2
    ..legalBalls = 48;
  inn2.batting['nazakat'] = _bat(102, 38, 7, 11, out: false);
  inn2.batting['sarfaraz'] = _bat(5, 10, 0, 0, out: false);
  inn2.batting['bilal'] = _bat(1, 2, 0, 0, out: true);
  inn2.batting['irtaza'] = _bat(0, 1, 0, 0, out: true);
  inn2.bowling['zaheer'] = _bowl(12, 10, 1);
  inn2.bowling['saqib'] = _bowl(12, 42, 1);
  inn2.bowling['afroz'] = _bowl(12, 18, 0);
  m.innings.addAll([inn1, inn2]);
  return m;
}

void main() {
  group('buildPosterSummaryData — Match 01 (approved sample data)', () {
    final data = buildPosterSummaryData(_leagueStore(), _match01())!;

    test('header / footer fields', () {
      expect(data.tournamentName, 'Super Sixty League');
      expect(data.seasonLabel, 'SEASON 2K26');
      expect(data.venue, '75 Lokri Club');
      expect(data.dateLabel, '22 OCT 2026');
      expect(data.resultText, 'Adi Dolphins won by 8 wickets');
    });

    test('teams in innings order with score panels', () {
      expect(data.teams, hasLength(2));
      expect(data.teams[0].name, 'Shazi Hawks');
      expect(data.teams[0].scoreText, '117-8');
      expect(data.teams[0].oversText, '8.0');
      expect(data.teams[1].name, 'Adi Dolphins');
      expect(data.teams[1].scoreText, '118-2');
      expect(data.teams[1].oversText, '8.0');
    });

    test('top batting: top 4 by runs, not-out star, 5th man cut', () {
      final bat = data.teams[0].batting;
      expect(bat.map((l) => l.name),
          ['Saqib 17 *', 'Zohaib 31', 'Afroz', 'Raja Zaheer']);
      expect(bat.first.runs, 35);
      expect(bat.first.balls, 12);
      expect(bat.first.strikeRateText, '291.7');
      final dolphins = data.teams[1].batting;
      expect(dolphins.first.name, 'Nazakat 16 *');
      expect(dolphins.first.runs, 102);
      expect(dolphins.first.strikeRateText, '268.4');
    });

    test('top bowling: top 3 by wickets, economy breaks the tie', () {
      final bowl = data.teams[0].bowling;
      expect(bowl.map((l) => l.name),
          ['Bilal Choki', 'Nazakat 16', 'Shuja Haider']);
      expect(bowl.first.wickets, 3);
      expect(bowl.first.oversText, '2.0');
      expect(bowl.first.economyText, '12.5');
    });

    test('POTM from manOfMatchId with batting chips', () {
      expect(data.potm.playerId, 'nazakat');
      expect(data.potm.name, 'Nazakat 16');
      expect(
        data.potm.chips.map((c) => '${c.value}|${c.label}'),
        [
          '102|RUNS',
          '38|BALLS',
          '7|FOURS',
          '11|SIXES',
          '268.4|STRIKE RATE',
        ],
      );
    });
  });

  group('POTM resolution', () {
    test('falls back to the top run-scorer when no award is stored', () {
      final data =
          buildPosterSummaryData(_leagueStore(), _match01(manOfMatchId: ''))!;
      expect(data.potm.playerId, 'nazakat');
      expect(data.potm.chips.first.value, '102');
    });

    test('bowling-led POTM (never batted) gets bowling chips', () {
      final s = Store();
      s.teams = [
        Team(id: 'ta', name: 'Team A', players: [
          _p('a1', 'Opener'),
          _p('b1', 'Star Bowler'),
        ]),
        Team(id: 'tb', name: 'Team B', players: [_p('x1', 'Other')]),
      ];
      final m = Match(
        id: 'm2',
        teamAId: 'ta',
        teamBId: 'tb',
        xiA: const ['a1', 'b1'],
        xiB: const ['x1'],
        oversLimit: 8,
        tossWinnerId: 'ta',
        status: 'completed',
        manOfMatchId: 'b1',
      );
      final inn = InningsState(
        battingTeamId: 'tb',
        bowlingTeamId: 'ta',
        battingXI: const ['x1'],
        bowlingXI: const ['a1', 'b1'],
        oversLimit: 8,
      )
        ..totalRuns = 60
        ..wickets = 6
        ..legalBalls = 48;
      inn.batting['x1'] = _bat(20, 15, 2, 0, out: true);
      inn.bowling['b1'] = _bowl(24, 20, 4);
      m.innings.add(inn);
      final data = buildPosterSummaryData(s, m)!;
      expect(data.potm.playerId, 'b1');
      expect(
        data.potm.chips.map((c) => '${c.value}|${c.label}'),
        ['4|WICKETS', '4.0|OVERS', '20|RUNS', '5.0|ECONOMY'],
      );
    });

    test('a duck with wickets is bowling-led too', () {
      final s = Store();
      s.teams = [
        Team(id: 'ta', name: 'Team A', players: [
          _p('p1', 'All Rounder'),
          _p('p2', 'Mate'),
        ]),
        Team(id: 'tb', name: 'Team B', players: [_p('x1', 'Other')]),
      ];
      final m = Match(
        id: 'm3',
        teamAId: 'ta',
        teamBId: 'tb',
        xiA: const ['p1', 'p2'],
        xiB: const ['x1'],
        oversLimit: 8,
        tossWinnerId: 'ta',
        status: 'completed',
        manOfMatchId: 'p1',
      );
      final inn1 = InningsState(
        battingTeamId: 'ta',
        bowlingTeamId: 'tb',
        battingXI: const ['p1', 'p2'],
        bowlingXI: const ['x1'],
        oversLimit: 8,
      )
        ..totalRuns = 90
        ..wickets = 4
        ..legalBalls = 48;
      inn1.batting['p1'] = _bat(0, 3, 0, 0, out: true);
      inn1.batting['p2'] = _bat(50, 30, 4, 1, out: false);
      final inn2 = InningsState(
        battingTeamId: 'tb',
        bowlingTeamId: 'ta',
        battingXI: const ['x1'],
        bowlingXI: const ['p1', 'p2'],
        oversLimit: 8,
      )
        ..totalRuns = 80
        ..wickets = 8
        ..legalBalls = 48;
      inn2.batting['x1'] = _bat(30, 20, 2, 0, out: true);
      inn2.bowling['p1'] = _bowl(18, 15, 3);
      m.innings.addAll([inn1, inn2]);
      final data = buildPosterSummaryData(s, m)!;
      expect(data.potm.playerId, 'p1');
      expect(
        data.potm.chips.map((c) => '${c.value}|${c.label}'),
        ['3|WICKETS', '3.0|OVERS', '15|RUNS', '5.0|ECONOMY'],
      );
    });
  });

  group('no figures -> no poster', () {
    test('empty match record', () {
      final m = Match(
        id: 'm0',
        teamAId: 'th',
        teamBId: 'td',
        xiA: const [],
        xiB: const [],
        tossWinnerId: 'th',
        status: 'completed',
      );
      expect(matchHasPosterFigures(m), isFalse);
      expect(buildPosterSummaryData(_leagueStore(), m), isNull);
    });

    test('innings present but nobody batted or bowled', () {
      final m = Match(
        id: 'm0b',
        teamAId: 'th',
        teamBId: 'td',
        xiA: const ['saqib'],
        xiB: const ['nazakat'],
        tossWinnerId: 'th',
        status: 'completed',
      );
      m.innings.add(InningsState(
        battingTeamId: 'th',
        bowlingTeamId: 'td',
        battingXI: const ['saqib'],
        bowlingXI: const ['nazakat'],
        oversLimit: 8,
      ));
      expect(matchHasPosterFigures(m), isFalse);
      expect(buildPosterSummaryData(_leagueStore(), m), isNull);
    });
  });

  group('team logo mapping + monogram', () {
    test('the six league teams resolve to bundled assets', () {
      expect(teamLogoAssetFor('Shazi Hawks'),
          'assets/team_logos/shazi-hawks.png');
      expect(teamLogoAssetFor('Adi Dolphins'),
          'assets/team_logos/adi-dolphins.png');
      expect(
          teamLogoAssetFor('US Lions'), 'assets/team_logos/us-lions.png');
      expect(teamLogoAssetFor('MA Kings'), 'assets/team_logos/ma-kings.png');
      expect(teamLogoAssetFor('Ali Panthers'),
          'assets/team_logos/ali-panthers.png');
      expect(teamLogoAssetFor('AB Knights'),
          'assets/team_logos/ab-knights.png');
    });

    test('dotted / spaced variants resolve to the same team', () {
      expect(teamLogoAssetFor('M.A. Kings'), 'assets/team_logos/ma-kings.png');
      expect(
          teamLogoAssetFor('U.S. Lions'), 'assets/team_logos/us-lions.png');
      expect(teamLogoAssetFor('A.B. Knights'),
          'assets/team_logos/ab-knights.png');
      expect(teamLogoAssetFor('  shazi   hawks '),
          'assets/team_logos/shazi-hawks.png');
    });

    test('any other team falls back (null asset)', () {
      expect(teamLogoAssetFor('Random XI'), isNull);
      expect(teamLogoAssetFor(''), isNull);
    });

    test('monogram initials', () {
      expect(teamMonogram('Shazi Hawks'), 'SH');
      expect(teamMonogram('Adi Dolphins'), 'AD');
      expect(teamMonogram('Kings'), 'KI');
      expect(teamMonogram(''), '?');
    });
  });

  group('posterDateLabel', () {
    test('ISO date becomes the sample format', () {
      expect(posterDateLabel('2026-10-22'), '22 OCT 2026');
      expect(posterDateLabel('2026-11-05'), '5 NOV 2026');
    });

    test('unparsable values pass through upper-cased', () {
      expect(posterDateLabel(''), '');
      expect(posterDateLabel('TBD'), 'TBD');
    });
  });

  testWidgets('poster card lays out at exactly 540x675 with no overflow',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final data = buildPosterSummaryData(_leagueStore(), _match01())!;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: MatchPosterCard(data: data)),
        ),
      ),
    );
    // Let the bundled logo assets decode.
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(MatchPosterCard)),
      const Size(540, 675),
    );
  });

  testWidgets('poster card lays out for generic teams (monogram badges)',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final s = Store();
    s.teams = [
      Team(id: 'ta', name: 'Long Named Team Alpha', players: [
        _p('a1', 'A Very Long Player Name'),
      ]),
      Team(id: 'tb', name: 'Team Beta', players: [_p('b1', 'B One')]),
    ];
    final m = Match(
      id: 'mg',
      teamAId: 'ta',
      teamBId: 'tb',
      xiA: const ['a1'],
      xiB: const ['b1'],
      oversLimit: 8,
      tossWinnerId: 'ta',
      status: 'completed',
      resultText: 'Team Beta won by 3 wickets',
      manOfMatchId: 'b1',
    );
    final inn = InningsState(
      battingTeamId: 'tb',
      bowlingTeamId: 'ta',
      battingXI: const ['b1'],
      bowlingXI: const ['a1'],
      oversLimit: 8,
    )
      ..totalRuns = 55
      ..wickets = 7
      ..legalBalls = 48;
    inn.batting['b1'] = _bat(33, 20, 3, 1, out: false);
    inn.bowling['a1'] = _bowl(24, 30, 2);
    m.innings.add(inn);
    final data = buildPosterSummaryData(s, m)!;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: MatchPosterCard(data: data)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(find.text('LN'), findsOneWidget); // monogram of team A
  });
}
