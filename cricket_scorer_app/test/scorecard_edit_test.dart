// Full scorecard edit (v1.4.5): the editor already covered batting
// figures, bowling figures, extras runs and the team total. The
// gap was the extras COUNTS (wide / no-ball deliveries), which are
// normally derived from the bowling figures on save — they are now
// directly editable (typed count wins over the derived one, same
// override pattern as the team total), and the total + counts parse
// leniently (bad input coerces to 0, never refuses the save).
// Byes / leg-byes have no separate count in the model (runs only),
// so runs are all they get.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cricket_scorer_app/models.dart';
import 'package:cricket_scorer_app/scoring.dart';
import 'package:cricket_scorer_app/screens/scorecard_edit_screen.dart';
import 'package:cricket_scorer_app/store.dart';

Team _team(String id, String p) => Team(
      id: id,
      name: 'Team $p',
      players: [for (var i = 1; i <= 4; i++) Player(id: '$p$i', name: 'P $p$i')],
    );

Future<(Store, Match)> _setup(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final store = Store();
  await store.activateIdentity('guest');
  await store.upsertTeam(_team('a', 'a'));
  await store.upsertTeam(_team('b', 'b'));
  final m = Match(
    id: 'm1',
    teamAId: 'a',
    teamBId: 'b',
    xiA: ['a1', 'a2', 'a3', 'a4'],
    xiB: ['b1', 'b2', 'b3', 'b4'],
    oversLimit: 2,
    ballsPerOver: 6,
    tossWinnerId: 'a',
    tossDecision: 'bat',
    status: 'completed',
  );
  final inn = startInnings(m, 1);
  setOpeners(inn, 'a1', 'a2', 'b1');
  expect(applyBall(inn, BallInput(batRuns: 4)), isTrue);
  expect(applyBall(inn, BallInput(batRuns: 1)), isTrue);
  expect(applyBall(inn, BallInput(extraType: 'wide', extraRuns: 1)), isTrue);
  expect(applyBall(inn, BallInput(extraType: 'noBall', batRuns: 2)), isTrue);
  // a1: 7 runs off 3 balls; wides 2 runs / 1 ball; no-balls 1 run /
  // 1 ball; total 10; wideCount 1, noBallCount 1.
  expect(inn.totalRuns, 10);
  expect(inn.wideCount, 1);
  expect(inn.noBallCount, 1);
  await store.upsertMatch(m);
  return (store, m);
}

Finder _field(String label) => find.ancestor(
      of: find.text(label),
      matching: find.byType(TextField),
    );

Future<void> _pumpEditor(
    WidgetTester tester, Store store, Match m) async {
  await tester.pumpWidget(
      MaterialApp(home: ScorecardEditScreen(store: store, match: m)));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> _save(WidgetTester tester) async {
  // The bottom 'Save corrections' button is lazily off-screen in
  // the ListView; the AppBar check button (same tooltip) is always
  // built and runs the same _save.
  final save = find.byTooltip('Save corrections');
  await tester.tap(save);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets('extras counts round-trip through save + reload',
      (tester) async {
    final (store, m) = await _setup(tester);
    await _pumpEditor(tester, store, m);
    final wideCount = _field('Wide count');
    final noBallCount = _field('No-ball count');
    await tester.ensureVisible(wideCount);
    await tester.enterText(wideCount, '3');
    await tester.enterText(noBallCount, '2');
    await _save(tester);
    expect(m.innings[0].wideCount, 3);
    expect(m.innings[0].noBallCount, 2);
    // Save + reload keeps the counts.
    final reloaded = Match.fromJson(m.toJson());
    expect(reloaded.innings[0].wideCount, 3);
    expect(reloaded.innings[0].noBallCount, 2);
  });

  testWidgets('bad total and counts coerce to 0, save still succeeds',
      (tester) async {
    final (store, m) = await _setup(tester);
    await _pumpEditor(tester, store, m);
    await tester.ensureVisible(_field('Total'));
    await tester.enterText(_field('Total'), 'abc');
    await tester.enterText(_field('Wide count'), 'xx');
    await tester.enterText(_field('No-ball count'), '-5');
    await _save(tester);
    expect(m.innings[0].totalRuns, 0);
    expect(m.innings[0].wideCount, 0);
    expect(m.innings[0].noBallCount, 0);
  });

  testWidgets('edited total wins over the figure sum (no forced equality)',
      (tester) async {
    final (store, m) = await _setup(tester);
    await _pumpEditor(tester, store, m);
    await tester.ensureVisible(_field('Total'));
    await tester.enterText(_field('Total'), '25');
    await _save(tester);
    // Figures still sum to 10, but the displayed total is the
    // typed 25 — the editor never forces them to agree.
    expect(m.innings[0].batting['a1']!.runs, 7);
    expect(m.innings[0].totalRuns, 25);
  });

  testWidgets('old scorecard without counts opens and saves fine',
      (tester) async {
    final (store, m) = await _setup(tester);
    final oldJson = m.toJson();
    final oldInn = (oldJson['innings'] as List).first as Map<String, dynamic>;
    oldInn.remove('wideCount');
    oldInn.remove('noBallCount');
    final oldMatch = Match.fromJson(oldJson);
    expect(oldMatch.innings[0].wideCount, 0);
    expect(oldMatch.innings[0].noBallCount, 0);
    await store.upsertMatch(oldMatch);
    await _pumpEditor(tester, store, oldMatch);
    await _save(tester);
    expect(oldMatch.innings[0].wideCount, 0);
    expect(oldMatch.innings[0].noBallCount, 0);
  });

  test('old innings JSON without counts loads as 0', () {
    final m = Match(
      id: 'm1',
      teamAId: 'ta',
      teamBId: 'tb',
      xiA: ['a1', 'a2'],
      xiB: ['b1', 'b2'],
      oversLimit: 2,
      ballsPerOver: 6,
      tossWinnerId: 'ta',
      tossDecision: 'bat',
    );
    final inn = startInnings(m, 1);
    final json = inn.toJson()
      ..remove('wideCount')
      ..remove('noBallCount');
    final loaded = InningsState.fromJson(json);
    expect(loaded.wideCount, 0);
    expect(loaded.noBallCount, 0);
  });

  testWidgets(
      'M4a: figure edits change figures/totals, never events, and '
      'clear the undo stack', (tester) async {
    final (store, m) = await _setup(tester);
    final inn = m.innings.single;
    // Pre-edit state: 4 balls applied, so events exist and the undo
    // stack is non-empty.
    expect(inn.events.length, 4);
    expect(inn.undoStack, isNotEmpty);
    expect(inn.batting['a1']!.runs, 7);
    String eventSig(BallEvent e) => '${e.strikerId}|${e.nonStrikerId}|'
        '${e.bowlerId}|${e.extraType}|${e.batRuns}|${e.extraRuns}|'
        '${e.isWicket}|${e.wicketType}';
    final eventsBefore = inn.events.map(eventSig).toList();
    await _pumpEditor(tester, store, m);
    // The edit screen carries the M4a note.
    expect(
      find.textContaining('ball-by-ball events stay as scored'),
      findsOneWidget,
    );
    // Change a1's Runs (first 'Runs' field = first batting row) and
    // the pinned total, then save.
    final runsField = find.ancestor(
      of: find.text('Runs').first,
      matching: find.byType(TextField),
    );
    await tester.ensureVisible(runsField);
    await tester.enterText(runsField, '20');
    await tester.ensureVisible(_field('Total'));
    await tester.enterText(_field('Total'), '25');
    await _save(tester);
    // Figures + totals changed...
    expect(m.innings.single.batting['a1']!.runs, 20);
    expect(m.innings.single.totalRuns, 25);
    // ...events byte-identical, undo stack cleared.
    expect(m.innings.single.events.map(eventSig).toList(), eventsBefore);
    expect(m.innings.single.undoStack, isEmpty);
    // Reload: the saved record agrees.
    final reloaded = Store();
    await reloaded.activateIdentity('guest');
    final rInn = reloaded.matches.single.innings.single;
    expect(rInn.batting['a1']!.runs, 20);
    expect(rInn.totalRuns, 25);
    expect(rInn.events.map(eventSig).toList(), eventsBefore);
    expect(rInn.undoStack, isEmpty);
  });
}
