// UI fit audit (D batch, owner instruction 2026-10-24): every
// new screen of the 7 features must follow the existing design
// system AND all text must fit its box at a normal phone width.
// These tests pump each new/changed screen at 360dp logical
// width with deliberately LONG names/labels and fail on any
// framework exception (RenderFlex overflow throws in tests).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cricket_scorer_app/models.dart';
import 'package:cricket_scorer_app/scoring.dart';
import 'package:cricket_scorer_app/screens/nrr_calculator_screen.dart';
import 'package:cricket_scorer_app/screens/scoring_screen.dart';
import 'package:cricket_scorer_app/screens/stats_screen.dart';
import 'package:cricket_scorer_app/screens/super_over_screen.dart';
import 'package:cricket_scorer_app/screens/trash_screen.dart';
import 'package:cricket_scorer_app/store.dart';
import 'package:cricket_scorer_app/theme.dart';

const longTeamA = 'M.A. Kings Super Sixty Champions XI';
const longTeamB = 'Adi Dolphins International Cricket Club';

List<String> xi(String p) => [for (var i = 1; i <= 11; i++) '$p$i'];

Team team(String id, String name, String p) => Team(
      id: id,
      name: name,
      players: [
        for (var i = 1; i <= 11; i++)
          Player(id: '$p$i', name: 'Muhammad $p$i Longname Player')
      ],
    );

void at360(WidgetTester tester) {
  tester.view.physicalSize = const Size(720, 1280);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

Widget host(Widget home) => MaterialApp(theme: buildScore60Theme(), home: home);

Future<Store> baseStore() async {
  SharedPreferences.setMockInitialValues({});
  final store = Store();
  await store.activateIdentity('guest');
  await store.upsertTeam(team('a', longTeamA, 'a'));
  await store.upsertTeam(team('b', longTeamB, 'b'));
  return store;
}

Match liveMatch() => Match(
      id: 'm1',
      teamAId: 'a',
      teamBId: 'b',
      xiA: xi('a'),
      xiB: xi('b'),
      oversLimit: 8,
      tossWinnerId: 'a',
      status: 'live',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Trash screen fits at 360dp with long names', (tester) async {
    at360(tester);
    final store = await baseStore();
    await store.upsertTournament(Tournament(
      id: 't1',
      name: 'Super Sixty League Season 2K26 Championship Trophy',
      teamIds: ['a', 'b'],
    ));
    final m = liveMatch()..matchTitle = 'Grand Final — the longest match title';
    await store.upsertMatch(m);
    await store.deleteMatch('m1');
    await store.deleteTeam('b');
    await store.deleteTournament('t1');

    await tester.pumpWidget(host(TrashScreen(store: store)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Grand Final — the longest match title'), findsWidgets);

    // Permanent-delete confirm dialog must also fit.
    await tester.tap(find.byIcon(Icons.delete_forever).first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Permanently delete?'), findsOneWidget);
  });

  testWidgets('NRR Calculator fits at 360dp, incl. the verdict card',
      (tester) async {
    at360(tester);
    final store = await baseStore();
    await store.upsertTournament(Tournament(
      id: 't1',
      name: 'Super Sixty League Season 2K26 Championship Trophy',
      teamIds: ['a', 'b'],
      oversLimit: 8,
    ));
    await tester.pumpWidget(host(NrrCalculatorScreen(store: store)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Score field: the second text field (quota is first).
    await tester.enterText(find.byType(TextField).at(1), '150');
    // Reveal-by-drag (ListView builds lazily; scrollUntilVisible
    // trips over the focused field's inner Scrollable here).
    Future<void> reveal(Finder f) async {
      for (var i = 0; i < 8 && f.evaluate().isEmpty; i++) {
        await tester.drag(find.byType(ListView), const Offset(0, -250));
        await tester.pumpAndSettle();
      }
    }

    await reveal(find.byType(GoldButton));
    await tester.tap(find.byType(GoldButton));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // A verdict (possible or not) rendered with the long team names.
    await reveal(find.textContaining('ka NRR'));
    expect(find.textContaining('ka NRR'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Super Over screen fits at 360dp with a long over of chips',
      (tester) async {
    at360(tester);
    final store = await baseStore();
    final m = liveMatch()..status = 'completed';
    // Two tied main innings.
    for (final (bat, bowl, p) in [('a', 'b', 'a'), ('b', 'a', 'b')]) {
      final inn = InningsState(
        battingTeamId: bat,
        bowlingTeamId: bowl,
        battingXI: xi(p),
        bowlingXI: xi(p == 'a' ? 'b' : 'a'),
        oversLimit: 8,
      );
      inn.totalRuns = 100;
      inn.wickets = 5;
      inn.legalBalls = 48;
      m.innings.add(inn);
    }
    await store.upsertMatch(m);
    // Super over innings 1 with a long "this over": 5 legal balls
    // + 5 wides = 10 chips.
    final so = startSuperOverInnings(m, 1);
    so.strikerId = 'b1';
    so.nonStrikerId = 'b2';
    so.currentBowlerId = 'a1';
    for (var i = 0; i < 5; i++) {
      applyBall(so, BallInput(extraType: 'wide', extraRuns: 1));
      applyBall(so, BallInput(batRuns: 1));
    }
    expect(so.events.length, 10);

    await tester.pumpWidget(host(SuperOverScreen(store: store, match: m)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('This over: '), findsOneWidget);
  });

  testWidgets('Player Profile insights fit at 360dp', (tester) async {
    at360(tester);
    final store = await baseStore();
    // Completed match: a1 bats (scores, then out obstructing),
    // bowls too — enough events for every insights chart.
    final m = liveMatch()..status = 'completed';
    final inn1 = startInnings(m, 1);
    inn1.strikerId = 'a1';
    inn1.nonStrikerId = 'a2';
    inn1.currentBowlerId = 'b1';
    applyBall(inn1, BallInput(batRuns: 4));
    applyBall(inn1, BallInput(batRuns: 6));
    applyBall(inn1, BallInput(batRuns: 2));
    applyBall(inn1,
        BallInput(isWicket: true, wicketType: 'obstructing'));
    inn1.strikerId = 'a3';
    applyBall(inn1, BallInput(batRuns: 1));
    final inn2 = startInnings(m, 2);
    inn2.strikerId = 'b1';
    inn2.nonStrikerId = 'b2';
    inn2.currentBowlerId = 'a1';
    applyBall(inn2,
        BallInput(isWicket: true, wicketType: 'bowled'));
    applyBall(inn2, BallInput(batRuns: 3));
    computeResult(m, store.teamName);
    await store.upsertMatch(m);

    await tester.pumpWidget(
        host(PlayerProfileScreen(store: store, playerId: 'a1')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // Insights section is below the fold — scroll it into view;
    // every chart row must lay out cleanly on the way.
    await tester.scrollUntilVisible(find.text('Insights'), 300);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('Economy by match'), 300);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Scoring wicket dialog fits at 360dp with the longest '
      'dismissal names', (tester) async {
    at360(tester);
    final store = await baseStore();
    final m = liveMatch();
    final inn = startInnings(m, 1);
    inn.strikerId = 'a1';
    inn.nonStrikerId = 'a2';
    inn.currentBowlerId = 'b1';
    applyBall(inn, BallInput(batRuns: 1));
    await store.upsertMatch(m);

    await tester.pumpWidget(host(ScoringScreen(store: store, match: m)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(find.text('Wicket'), 300);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wicket'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // Open the dismissal dropdown and pick the longest label.
    await tester.tap(find.text('No wicket'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Obstructing the Field').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Obstructing the Field'), findsWidgets);
  });

  testWidgets('DLS dialog fits at 360dp with every field shown',
      (tester) async {
    at360(tester);
    final store = await baseStore();
    final m = liveMatch();
    await store.upsertMatch(m);
    await tester.pumpWidget(host(ScoringScreen(store: store, match: m)));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Revised target (DLS)'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Toggle via the Switch widgets themselves (robust inside
    // the scrollable dialog), scrolling each into view first.
    await tester.ensureVisible(find.byType(Switch).at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch).at(0));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(Switch).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch).at(1));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final fields = find.byType(TextField);
    // Order: score, innings-1 overs left, innings-1 wickets,
    // innings-2 start overs, stoppage overs, stoppage wickets,
    // resumption overs.
    const values = ['120', '2.0', '3', '6.0', '3.0', '2', '1.0'];
    for (var i = 0; i < values.length; i++) {
      await tester.ensureVisible(fields.at(i));
      await tester.pumpAndSettle();
      await tester.enterText(fields.at(i), values[i]);
    }
    await tester.ensureVisible(find.text('Calculate'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Calculate'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Revised target:'), findsOneWidget);
  });
}
