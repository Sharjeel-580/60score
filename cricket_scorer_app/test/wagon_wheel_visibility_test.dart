// v1.2.2 (item 7): the live wagon wheel on the scoring screen must
// start CLOSED — it opens only when the scorer taps it — and no wheel
// card exists before the first ball.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cricket_scorer_app/models.dart';
import 'package:cricket_scorer_app/scoring.dart';
import 'package:cricket_scorer_app/screens/scoring_screen.dart';
import 'package:cricket_scorer_app/store.dart';

Match _liveMatch({required bool withBall}) {
  final m = Match(
    id: 'm1',
    teamAId: 'ta',
    teamBId: 'tb',
    xiA: const ['b1', 'b2'],
    xiB: const ['p1', 'p2'],
    oversLimit: 8,
    tossWinnerId: 'ta',
  );
  m.status = 'live';
  final inn = startInnings(m, 1);
  setOpeners(inn, 'b1', 'b2', 'p1');
  if (withBall) {
    expect(applyBall(inn, BallInput(batRuns: 0)), isTrue);
  }
  return m;
}

Store _storeWith(Match m) {
  final s = Store();
  s.teams = [
    Team(
      id: 'ta',
      name: 'Team A',
      players: [
        Player(id: 'b1', name: 'Bat One'),
        Player(id: 'b2', name: 'Bat Two'),
      ],
    ),
    Team(
      id: 'tb',
      name: 'Team B',
      players: [
        Player(id: 'p1', name: 'Bowl One'),
        Player(id: 'p2', name: 'Bowl Two'),
      ],
    ),
  ];
  s.matches = [m];
  return s;
}

void main() {
  testWidgets('no wagon wheel card before the first ball', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final m = _liveMatch(withBall: false);
    await tester.pumpWidget(
      MaterialApp(home: ScoringScreen(store: _storeWith(m), match: m)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ExpansionTile), findsNothing);
  });

  testWidgets('live wagon wheel starts closed and opens on tap',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final m = _liveMatch(withBall: true);
    await tester.pumpWidget(
      MaterialApp(home: ScoringScreen(store: _storeWith(m), match: m)),
    );
    await tester.pumpAndSettle();

    final tile = find.byType(ExpansionTile);
    expect(tile, findsOneWidget);
    expect(tester.widget<ExpansionTile>(tile).initiallyExpanded, isFalse);
    // Collapsed: only the title row is laid out (wheel is 240 tall).
    expect(tester.getSize(tile).height, lessThan(90));

    await tester.tap(find.textContaining('Wagon wheel - live'));
    await tester.pumpAndSettle();
    expect(tester.getSize(tile).height, greaterThan(240));
  });
}
