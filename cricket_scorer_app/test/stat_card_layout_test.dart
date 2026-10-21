// Layout smoke tests for the redesigned compact stat cards and the
// profile screen: pump at a narrow phone width and assert no layout
// exception (the old complaint was giant mostly-empty stat boxes).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cricket_scorer_app/models.dart';
import 'package:cricket_scorer_app/screens/profile_screen.dart';
import 'package:cricket_scorer_app/screens/tournament_stats.dart';
import 'package:cricket_scorer_app/store.dart';

Match _matchWithFigures() {
  final m = Match(
    id: 'm1',
    tournamentId: 't1',
    teamAId: 'ta',
    teamBId: 'tb',
    xiA: const ['a1', 'a2', 'a3'],
    xiB: const ['b1', 'b2', 'b3'],
    oversLimit: 8,
    tossWinnerId: 'ta',
    status: 'completed',
  );
  final inn = InningsState(
    battingTeamId: 'ta',
    bowlingTeamId: 'tb',
    battingXI: const ['a1', 'a2', 'a3'],
    bowlingXI: const ['b1', 'b2', 'b3'],
    oversLimit: 8,
  );
  inn.batting['a1'] = BatFig()
    ..batted = true
    ..runs = 87
    ..balls = 40
    ..fours = 8
    ..sixes = 3;
  inn.bowling['b1'] = BowlFig()
    ..legalBalls = 24
    ..runs = 30
    ..wickets = 3;
  inn.totalRuns = 120;
  inn.wickets = 2;
  inn.legalBalls = 48;
  m.innings.add(inn);
  return m;
}

Future<Store> _storeWithData() async {
  SharedPreferences.setMockInitialValues({});
  final s = Store();
  s.teams = [
    Team(id: 'ta', name: 'Long Named Team Alpha', players: [
      Player(id: 'a1', name: 'A Very Long Player Name', role: 'Batter'),
      Player(id: 'a2', name: 'A2', role: 'Batter'),
      Player(id: 'a3', name: 'A3', role: 'Batter'),
    ]),
    Team(id: 'tb', name: 'Team Beta', players: [
      Player(id: 'b1', name: 'B One', role: 'Bowler'),
      Player(id: 'b2', name: 'B2', role: 'Bowler'),
      Player(id: 'b3', name: 'B3', role: 'Bowler'),
    ]),
  ];
  s.tournaments = [
    Tournament(id: 't1', name: 'Super Sixty League', teamIds: ['ta', 'tb']),
  ];
  s.matches = [_matchWithFigures()];
  return s;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void narrowView(WidgetTester tester) {
    tester.view.devicePixelRatio = 3.0;
    tester.view.physicalSize = const Size(1080, 2220); // 360x740 logical
    addTearDown(tester.view.reset);
  }

  testWidgets('tournament stats grid: data cards fit a narrow phone',
      (tester) async {
    narrowView(tester);
    final s = await _storeWithData();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TournamentStatsTab(store: s, tournament: s.tournaments.first),
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Most Runs'), findsOneWidget);
    expect(find.text('87'), findsWidgets);
  });

  testWidgets('tournament stats grid: empty state fits a narrow phone',
      (tester) async {
    narrowView(tester);
    SharedPreferences.setMockInitialValues({});
    final s = Store();
    final t = Tournament(id: 't0', name: 'Empty Cup');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: TournamentStatsTab(store: s, tournament: t)),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('No data yet'), findsWidgets);
  });

  testWidgets('profile screen shows the guest prompt when logged out',
      (tester) async {
    narrowView(tester);
    SharedPreferences.setMockInitialValues({});
    final s = Store();
    await tester.pumpWidget(MaterialApp(home: ProfileScreen(store: s)));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('My Profile'), findsOneWidget);
    expect(find.text('Log in / Sign up'), findsWidgets);
  });
}
