// Innings-end option (v1.4.5): the scorer can end the current
// innings early from the scoring ⋮ menu. The flag only makes the
// innings read complete — the existing break card (Start 2nd
// innings / match finish) takes over from there, so no new
// completion path was invented. Totals are never faked.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cricket_scorer_app/models.dart';
import 'package:cricket_scorer_app/scoring.dart';
import 'package:cricket_scorer_app/screens/scoring_screen.dart';
import 'package:cricket_scorer_app/store.dart';

String _name(String id) => id == 'ta' ? 'Team A' : 'Team B';

Match _makeMatch() => Match(
      id: 'm1',
      teamAId: 'ta',
      teamBId: 'tb',
      xiA: [for (var i = 1; i <= 4; i++) 'a$i'],
      xiB: [for (var i = 1; i <= 4; i++) 'b$i'],
      oversLimit: 2,
      ballsPerOver: 6,
      tossWinnerId: 'ta',
      tossDecision: 'bat',
      status: 'live',
    );

InningsState _openFirst(Match m) {
  final inn = startInnings(m, 1);
  setOpeners(inn, inn.battingXI[0], inn.battingXI[1], inn.bowlingXI[0]);
  return inn;
}

void _ball(InningsState s, int runs) {
  expect(applyBall(s, BallInput(batRuns: runs)), isTrue);
}

void main() {
  test('ending 1st innings marks it complete, match stays live, '
      '2nd starts with target = total + 1', () {
    final m = _makeMatch();
    final inn1 = _openFirst(m);
    _ball(inn1, 4);
    _ball(inn1, 1); // total 5
    inn1.endedEarly = true;
    expect(inn1.isComplete, isTrue);
    expect(computeResult(m, _name), '');
    expect(m.status, 'live');
    final inn2 = startInnings(m, 2);
    expect(inn2.target, 6);
    expect(inn2.battingTeamId, 'tb');
  });

  test('ending last innings completes the match with the correct '
      'result', () {
    final m = _makeMatch();
    final inn1 = _openFirst(m);
    _ball(inn1, 4);
    _ball(inn1, 4);
    _ball(inn1, 4);
    _ball(inn1, 4); // 16
    final inn2 = startInnings(m, 2);
    setOpeners(inn2, inn2.battingXI[0], inn2.battingXI[1], inn2.bowlingXI[0]);
    _ball(inn2, 4);
    _ball(inn2, 4); // 8
    inn2.endedEarly = true;
    expect(inn2.isComplete, isTrue);
    expect(computeResult(m, _name), 'Team A won by 8 runs');
    expect(m.status, 'completed');
    expect(m.resultText, 'Team A won by 8 runs');
  });

  test('an ended innings refuses further balls', () {
    final m = _makeMatch();
    final inn = _openFirst(m);
    _ball(inn, 4);
    inn.endedEarly = true;
    expect(applyBall(inn, BallInput(batRuns: 1)), isFalse);
    expect(inn.events.length, 1);
    expect(inn.totalRuns, 4);
  });

  test('old JSON without endedEarly loads as not ended; round-trip '
      'preserves true', () {
    final m = _makeMatch();
    final inn = _openFirst(m);
    _ball(inn, 4);
    final old = inn.toJson()..remove('endedEarly');
    final loaded = InningsState.fromJson(old);
    expect(loaded.endedEarly, isFalse);
    expect(loaded.isComplete, isFalse);
    inn.endedEarly = true;
    final roundTripped = InningsState.fromJson(inn.toJson());
    expect(roundTripped.endedEarly, isTrue);
    expect(roundTripped.isComplete, isTrue);
    expect(roundTripped.totalRuns, 4);
  });

  group('scoring menu', () {
    List<String> xi(String p) => [for (var i = 1; i <= 11; i++) '$p$i'];

    Team team(String id, String name, String p) => Team(
          id: id,
          name: name,
          players: [
            for (var i = 1; i <= 11; i++) Player(id: '$p$i', name: 'P $p$i')
          ],
        );

    Future<(Store, Match)> pumpScoring(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = Store();
      await store.activateIdentity('guest');
      await store.upsertTeam(team('a', 'Team A', 'a'));
      await store.upsertTeam(team('b', 'Team B', 'b'));
      final m = Match(
        id: 'm1',
        teamAId: 'a',
        teamBId: 'b',
        xiA: xi('a'),
        xiB: xi('b'),
        oversLimit: 8,
        tossWinnerId: 'a',
        tossDecision: 'bat',
        status: 'live',
      );
      await tester.pumpWidget(
          MaterialApp(home: ScoringScreen(store: store, match: m)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      return (store, m);
    }

    Future<void> openEndDialog(WidgetTester tester) async {
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('End innings'));
      await tester.pumpAndSettle();
      expect(find.text('End innings?'), findsOneWidget);
    }

    testWidgets('menu Cancel leaves state untouched', (tester) async {
      final (_, m) = await pumpScoring(tester);
      await openEndDialog(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(m.innings.last.endedEarly, isFalse);
      expect(m.innings.last.isComplete, isFalse);
    });

    testWidgets('menu Confirm ends the innings and shows the break card',
        (tester) async {
      final (_, m) = await pumpScoring(tester);
      await openEndDialog(tester);
      await tester.tap(find.text('End innings').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(m.innings.last.endedEarly, isTrue);
      expect(find.text('Innings break'), findsOneWidget);
    });
  });
}
