// Regression + layout tests for the stats leaderboard rows (1.4.6 fix):
// - In single-tournament view (editable rows: edit icon + gold marker),
//   the row must still show the player name: the old 4-column row plus
//   the edit affordances overflowed a 360dp phone, collapsing the name
//   column to zero width so name/team vanished entirely.
// - Every leaderboard row on the Stats screen shows ONLY its headline
//   stat (batters: Runs, bowlers: Wkts); full detail lives on the
//   player profile opened by tapping the row.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cricket_scorer_app/models.dart';
import 'package:cricket_scorer_app/screens/stats_screen.dart';
import 'package:cricket_scorer_app/store.dart';
import 'package:cricket_scorer_app/theme.dart';

Store _storeWithData({bool withOverride = false}) {
  SharedPreferences.setMockInitialValues({});
  final s = Store();
  s.teams = [
    Team(id: 'ta', name: 'Team Alpha', players: [
      Player(id: 'a1', name: 'Nazakat', role: 'Batter'),
      Player(id: 'a2', name: 'A2', role: 'Batter'),
    ]),
    Team(id: 'tb', name: 'Team Beta', players: [
      Player(id: 'b1', name: 'Waqas', role: 'Bowler'),
      Player(id: 'b2', name: 'B2', role: 'Bowler'),
    ]),
  ];
  final t = Tournament(id: 't1', name: 'Super Sixty', teamIds: ['ta', 'tb']);
  if (withOverride) {
    // Single-tournament override (by design it only applies in this
    // view): since v1.4.7 stored values are DELTAS, so the row
    // shows computed 62 + delta (-3) = 59, with the gold marker.
    t.playerStatsOverrides['a1'] = PlayerStatsOverride(runs: -3);
  }
  s.tournaments = [t];
  final m = Match(
    id: 'm1',
    tournamentId: 't1',
    teamAId: 'ta',
    teamBId: 'tb',
    xiA: const ['a1', 'a2'],
    xiB: const ['b1', 'b2'],
    oversLimit: 8,
    tossWinnerId: 'ta',
    status: 'completed',
  );
  final inn = InningsState(
    battingTeamId: 'ta',
    bowlingTeamId: 'tb',
    battingXI: const ['a1', 'a2'],
    bowlingXI: const ['b1', 'b2'],
    oversLimit: 8,
  );
  inn.batting['a1'] = BatFig()
    ..batted = true
    ..runs = 62
    ..balls = 30
    ..fours = 5
    ..sixes = 3;
  inn.bowling['b1'] = BowlFig()
    ..legalBalls = 24
    ..runs = 30
    ..wickets = 4;
  inn.totalRuns = 120;
  inn.wickets = 2;
  inn.legalBalls = 48;
  m.innings.add(inn);
  s.matches = [m];
  return s;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void narrowView(WidgetTester tester) {
    tester.view.devicePixelRatio = 3.0;
    tester.view.physicalSize = const Size(1080, 2220); // 360x740 logical
    addTearDown(tester.view.reset);
  }

  Future<void> pumpStats(WidgetTester tester, Store s) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatsScreen(store: s, onOpenDrawer: () {}),
      ),
    ));
    await tester.pump();
  }

  testWidgets(
      'single-tournament rows show the name and only the headline stat',
      (tester) async {
    narrowView(tester);
    final s = _storeWithData();
    await pumpStats(tester, s);
    // No RenderFlex overflow: the old 4-column row + edit icons
    // overflowed 360dp and collapsed the name column to zero width.
    expect(tester.takeException(), isNull);
    // Name actually renders with width (not a zero-width column).
    final nameFinder = find.text('Nazakat');
    expect(nameFinder, findsWidgets);
    expect(tester.getSize(nameFinder.first).width, greaterThan(0));
    expect(find.text('Waqas'), findsWidgets);
    // Headline stats only on the main list.
    expect(find.text('Runs'), findsWidgets);
    expect(find.text('Wkts'), findsWidgets);
    expect(find.text('Overs'), findsNothing);
    expect(find.text('Econ'), findsNothing);
    expect(find.text('Avg'), findsNothing);
    expect(find.text('Inns'), findsNothing);
    expect(find.text('SR'), findsNothing);
    // Edit affordance still reachable in single-tournament view.
    expect(find.byTooltip('Edit player stats'), findsWidgets);
    // Tapping a row opens the full detail with ALL stats.
    await tester.ensureVisible(nameFinder.first);
    await tester.tap(nameFinder.first);
    await tester.pumpAndSettle();
    expect(find.text('Strike rate'), findsWidgets);
    expect(find.text('Best figures'), findsWidgets);
    expect(find.text('Economy'), findsWidgets);
    expect(find.text('50s / 100s'), findsWidgets);
    // Fielding section sits below the fold in the profile ListView.
    await tester.scrollUntilVisible(find.text('Dismissals'), 300);
    expect(find.text('Dismissals'), findsWidgets);
    expect(find.text('MVP points'), findsWidgets);
  });

  testWidgets('gold-pencil marker shows for overridden rows',
      (tester) async {
    narrowView(tester);
    final s = _storeWithData(withOverride: true);
    await pumpStats(tester, s);
    expect(tester.takeException(), isNull);
    // Overridden value in single-tournament view (by design).
    expect(find.text('59'), findsWidgets);
    expect(
      find.byWidgetPredicate(
        (w) => w is Icon && w.icon == Icons.edit && w.color == kGold,
      ),
      findsWidgets,
    );
  });
}
