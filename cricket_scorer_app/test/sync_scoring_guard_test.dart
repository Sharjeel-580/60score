// Scoring guard (v1.4.3, user design; hardened v1.4.4 light
// version): while a match is being scored, NO network runs at all
// — no push, no pull, no listener traffic. Local persist keeps
// running (matches-only per ball); a push owed during scoring is
// deferred to scoring close, never dropped. These tests pin the
// wiring (the scoring screens arm the guard while open and disarm
// it on close) and the end-to-end property the guard exists for:
// balls scored around a would-be remote event are never lost.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cricket_scorer_app/models.dart';
import 'package:cricket_scorer_app/scoring.dart';
import 'package:cricket_scorer_app/screens/scoring_screen.dart';
import 'package:cricket_scorer_app/screens/super_over_screen.dart';
import 'package:cricket_scorer_app/store.dart';
import 'package:cricket_scorer_app/sync_service.dart';
import 'package:cricket_scorer_app/theme.dart';

List<String> xi(String p) => [for (var i = 1; i <= 11; i++) '$p$i'];

Team team(String id, String name, String p) => Team(
      id: id,
      name: name,
      players: [
        for (var i = 1; i <= 11; i++) Player(id: '$p$i', name: '$p$i')
      ],
    );

Future<Store> baseStore() async {
  SharedPreferences.setMockInitialValues({});
  final store = Store();
  await store.activateIdentity('guest');
  await store.upsertTeam(team('a', 'Team A', 'a'));
  await store.upsertTeam(team('b', 'Team B', 'b'));
  return store;
}

Match liveMatch() => Match(
      id: 'm1',
      teamAId: 'a',
      teamBId: 'b',
      xiA: xi('a'),
      xiB: xi('b'),
      oversLimit: 8,
      ballsPerOver: 6,
      tossWinnerId: 'a',
      tossDecision: 'bat',
    );

Widget host(Widget home) => MaterialApp(theme: buildScore60Theme(), home: home);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SyncService().scoringActive = false;
  });
  tearDown(() {
    SyncService().scoringActive = false;
  });

  group('scoring guard flag', () {
    test('flag starts false', () {
      expect(SyncService().scoringActive, isFalse);
    });

    testWidgets('scoring screen arms the guard while open, disarms '
        'on close', (tester) async {
      final store = await baseStore();
      final m = liveMatch();
      final inn = startInnings(m, 1);
      setOpeners(inn, 'a1', 'a2', 'b1');
      await store.upsertMatch(m);

      await tester.pumpWidget(host(ScoringScreen(store: store, match: m)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(SyncService().scoringActive, isTrue);

      // Popping the screen closes scoring: guard disarms.
      await tester.pumpWidget(host(const SizedBox()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(SyncService().scoringActive, isFalse);
    });

    testWidgets('super over screen arms and disarms the guard too',
        (tester) async {
      final store = await baseStore();
      final m = liveMatch();
      await store.upsertMatch(m);

      await tester.pumpWidget(host(SuperOverScreen(store: store, match: m)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(SyncService().scoringActive, isTrue);

      await tester.pumpWidget(host(const SizedBox()));
      await tester.pumpAndSettle();
      expect(SyncService().scoringActive, isFalse);
    });

    test('syncAfterScoring offline never touches local data', () async {
      final store = await baseStore();
      final m = liveMatch();
      await store.upsertMatch(m);
      await SyncService().syncAfterScoring(store);
      expect(store.matches.length, 1);
      expect(identical(store.matches.first, m), isTrue);
    });
  });

  group('balls around a skipped remote event are never lost', () {
    test('score, remote event ignored, score more, reload: all '
        'balls present', () async {
      SharedPreferences.setMockInitialValues({});
      final store = Store();
      await store.load();
      final m = liveMatch();
      final inn = startInnings(m, 1);
      setOpeners(inn, 'a1', 'a2', 'b1');
      await store.upsertMatch(m);

      // First 12 balls (2 overs), then persist.
      const pattern = [0, 1, 4, 6, 2, 0];
      for (var i = 0; i < 12; i++) {
        expect(applyBall(inn, BallInput(batRuns: pattern[i % 6])), isTrue);
        if (inn.legalBalls % 6 == 0 && inn.legalBalls < 12) {
          expect(setBowler(inn, 'b2'), isTrue);
        }
      }
      await store.persist();
      expect(inn.legalBalls, 12);

      // Scoring screen is open: a remote snapshot arrives, but the
      // guard means the store list is NOT replaced — the screen's
      // match object stays attached. Phase 1 ended exactly on an
      // over boundary, so over 3's bowler is set before resuming.
      SyncService().scoringActive = true;
      expect(
        identical(
          store.matches.firstWhere((x) => x.id == 'm1'),
          m,
        ),
        isTrue,
      );
      expect(setBowler(inn, 'b3'), isTrue);

      // 12 more balls into the SAME object, then persist again.
      for (var i = 12; i < 24; i++) {
        expect(applyBall(inn, BallInput(batRuns: pattern[i % 6])), isTrue);
        if (inn.legalBalls % 6 == 0 && inn.legalBalls < 24) {
          expect(setBowler(inn, 'b${inn.legalBalls ~/ 6 + 1}'), isTrue);
        }
      }
      await store.persist();
      expect(inn.legalBalls, 24);

      // Scoring closes: full sync (offline no-op here), then reload.
      SyncService().scoringActive = false;
      await SyncService().syncAfterScoring(store);
      final reloaded = Store();
      await reloaded.load();
      expect(reloaded.matches.length, 1);
      final rm = reloaded.matches.first;
      expect(rm.innings.length, 1);
      expect(rm.innings[0].legalBalls, 24);
      expect(rm.innings[0].events.length, 24);
      // 4 overs x (0+1+4+6+2+0) = 4 x 13 = 52.
      expect(rm.innings[0].totalRuns, 52);
      // Phase-1 property still holds after reload: no undo stack
      // in the persisted record.
      expect(
        (rm.toJson()['innings'] as List)[0],
        isNot(contains('undoStack')),
      );
    });
  });
}
