// Light version (v1.4.4): undo is a small reverse step (not a snapshot
// stack), and sync has no automatic triggers — only scoring-close and
// manual sync remain. These tests pin the undo behavior and the
// unit-testable sync gates. The app-lifecycle unwiring itself (no boot
// pull, no resume sync, no live listener) is verified by code
// location — main.dart boot, login_screen.dart sign-in — not faked
// as a unit test, because widget-boot wiring has no pure-Dart seam.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cricket_scorer_app/models.dart';
import 'package:cricket_scorer_app/scoring.dart';
import 'package:cricket_scorer_app/store.dart';
import 'package:cricket_scorer_app/sync_service.dart';

Match makeMatch({int xi = 4, int overs = 2}) {
  return Match(
    id: 'm1',
    teamAId: 'ta',
    teamBId: 'tb',
    xiA: [for (var i = 1; i <= xi; i++) 'a$i'],
    xiB: [for (var i = 1; i <= xi; i++) 'b$i'],
    oversLimit: overs,
    ballsPerOver: 6,
    tossWinnerId: 'ta',
    tossDecision: 'bat',
  );
}

InningsState openInnings(Match m) {
  final inn = startInnings(m, 1);
  setOpeners(inn, inn.battingXI[0], inn.battingXI[1], inn.bowlingXI[0]);
  return inn;
}

void ball(InningsState s, BallInput input) {
  expect(applyBall(s, input), isTrue,
      reason: 'ball should apply: ${input.extraType} ${input.batRuns}');
}

void runs(InningsState s, int r) => ball(s, BallInput(batRuns: r));

/// Bowls [n] dot balls, picking the next bowler at each over end
/// (alternating b2/b1, never the bowler of the over just bowled).
/// setBowler pushes no undo step, so the stack holds ball steps only.
void dots(InningsState inn, int n) {
  var useB2 = true;
  for (var i = 0; i < n; i++) {
    if (inn.awaitingBowler) {
      expect(setBowler(inn, useB2 ? 'b2' : 'b1'), isTrue);
      useB2 = !useB2;
    }
    ball(inn, BallInput(batRuns: 0));
  }
}

Future<Store> guestStore() async {
  SharedPreferences.setMockInitialValues({});
  final store = Store();
  await store.activateIdentity('guest');
  return store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SyncService().scoringActive = false;
  });
  tearDown(() {
    SyncService().scoringActive = false;
  });

  group('undo reverse step', () {
    test('one undo restores totals, figures, striker and events', () {
      final inn = openInnings(makeMatch());
      runs(inn, 4);
      runs(inn, 1);
      expect(inn.totalRuns, 5);
      expect(inn.events.length, 2);
      expect(undoLastBall(inn), isTrue);
      expect(inn.totalRuns, 4);
      expect(inn.batting['a1']!.runs, 4);
      expect(inn.strikerId, 'a1');
      expect(inn.events.length, 1);
      expect(undoLastBall(inn), isTrue);
      expect(inn.totalRuns, 0);
      expect(inn.events.length, 0);
      expect(inn.legalBalls, 0);
      expect(undoLastBall(inn), isFalse);
    });

    test('multiple undos walk the innings back ball by ball', () {
      final inn = openInnings(makeMatch());
      runs(inn, 1);
      runs(inn, 2);
      runs(inn, 4);
      runs(inn, 6);
      expect(inn.totalRuns, 13);
      for (final expected in [7, 3, 1, 0]) {
        expect(undoLastBall(inn), isTrue);
        expect(inn.totalRuns, expected);
      }
      expect(inn.events, isEmpty);
      expect(inn.batting['a1']!.runs, 0);
      expect(inn.batting['a1']!.balls, 0);
      expect(undoLastBall(inn), isFalse);
    });

    test('undo on an empty stack is a no-op', () {
      final inn = openInnings(makeMatch());
      expect(undoLastBall(inn), isFalse);
      expect(inn.totalRuns, 0);
      expect(inn.events, isEmpty);
      expect(inn.strikerId, 'a1');
    });

    test('undo after a wicket restores batter, fall and figures', () {
      final inn = openInnings(makeMatch());
      runs(inn, 1); // a1 1 run, strike to a2
      ball(inn, BallInput(isWicket: true, wicketType: 'bowled'));
      expect(inn.wickets, 1);
      expect(inn.fallOfWickets.length, 1);
      expect(inn.batting['a2']!.out, isTrue);
      expect(inn.awaitingBatter, isTrue);
      // The next batter is picked before the undo (the real UI flow).
      setNextBatter(inn, 'a3');
      expect(inn.strikerId, 'a3');
      expect(undoLastBall(inn), isTrue);
      expect(inn.wickets, 0);
      expect(inn.fallOfWickets, isEmpty);
      expect(inn.batting['a2']!.out, isFalse);
      expect(inn.strikerId, 'a2');
      expect(inn.awaitingBatter, isFalse);
      // The picked batter's figure (created by setNextBatter) is gone:
      // the restored figure map predates the pick.
      expect(inn.batting.containsKey('a3'), isFalse);
      expect(inn.events.length, 1);
    });

    test('undo after over completion restores ends and bowler state', () {
      final inn = openInnings(makeMatch());
      dots(inn, 6);
      expect(inn.legalBalls, 6);
      expect(inn.awaitingBowler, isTrue);
      expect(inn.lastBowlerId, 'b1');
      expect(undoLastBall(inn), isTrue);
      expect(inn.legalBalls, 5);
      expect(inn.awaitingBowler, isFalse);
      expect(inn.currentBowlerId, 'b1');
      expect(inn.lastBowlerId, '');
    });

    test('undo after a wide restores extras and bowler figures', () {
      final inn = openInnings(makeMatch());
      ball(inn, BallInput(extraType: 'wide', extraRuns: 2));
      expect(inn.totalRuns, 3);
      expect(inn.widesRuns, 3);
      expect(inn.wideCount, 1);
      expect(inn.bowling['b1']!.wides, 1);
      expect(inn.bowling['b1']!.runs, 3);
      expect(inn.legalBalls, 0);
      expect(undoLastBall(inn), isTrue);
      expect(inn.totalRuns, 0);
      expect(inn.widesRuns, 0);
      expect(inn.wideCount, 0);
      expect(inn.bowling['b1']!.wides, 0);
      expect(inn.bowling['b1']!.runs, 0);
    });

    test('retire hurt and between-balls dismissal undo exactly', () {
      final inn = openInnings(makeMatch());
      expect(retireBatsmanHurt(inn, 'a1'), isTrue);
      expect(inn.strikerId, '');
      expect(inn.batting['a1']!.howOut, 'retired hurt');
      expect(undoLastBall(inn), isTrue);
      expect(inn.strikerId, 'a1');
      expect(inn.batting['a1']!.howOut, '');
      expect(inn.awaitingBatter, isFalse);

      expect(
          dismissBatsmanWithoutBall(inn, 'a3', 'timedOut'), isTrue);
      expect(inn.wickets, 1);
      expect(inn.fallOfWickets.length, 1);
      expect(inn.batting['a3']!.out, isTrue);
      expect(undoLastBall(inn), isTrue);
      expect(inn.wickets, 0);
      expect(inn.fallOfWickets, isEmpty);
      expect(inn.batting.containsKey('a3'), isFalse);
    });

    test('stack holds reverse steps, not snapshots, and stays small', () {
      final inn = openInnings(makeMatch(xi: 11, overs: 20));
      dots(inn, 5);
      final early = inn.undoStack.last;
      expect(early, isA<UndoStep>());
      // Steps store PRE-action lengths: the 5th ball's step predates
      // it, so its length is 4 while the innings holds 5 events.
      expect(early.eventsLength, 4);
      expect(inn.events.length, 5);
      // A step carries figure maps bounded by squad size — never the
      // event list, so it cannot grow with the innings.
      expect(early.batting.length, lessThanOrEqualTo(11));
      expect(early.bowling.length, lessThanOrEqualTo(11));

      dots(inn, 55); // 60 balls total, across 10 overs
      expect(inn.events.length, 60);
      final late = inn.undoStack.last;
      expect(late, isA<UndoStep>());
      expect(late.eventsLength, 59); // pre-action length, as above
      expect(late.batting.length, lessThanOrEqualTo(11));
      expect(late.bowling.length, lessThanOrEqualTo(11));
      // The 50-step cap survives the representation change.
      expect(inn.undoStack.length, 50);
      // Undoing from the capped stack still walks back correctly.
      expect(undoLastBall(inn), isTrue);
      expect(inn.events.length, 59);
    });
  });

  group('sync gates (light version)', () {
    test('pull while scoring returns false before any network', () async {
      final store = await guestStore();
      SyncService().scoringActive = true;
      // The scoring gate sits before _docRef(), so this needs no
      // Firebase state at all — it proves the entry gate, not a
      // network round-trip.
      expect(await SyncService().pull(store), isFalse);
    });

    test('syncNow while scoring reports the scoring guard', () async {
      final store = await guestStore();
      SyncService().scoringActive = true;
      final result = await SyncService().syncNow(store);
      expect(result.ok, isFalse);
      expect(result.error, 'scoring');
    });

    test('syncNow logged out reports login', () async {
      final store = await guestStore();
      final result = await SyncService().syncNow(store);
      expect(result.ok, isFalse);
      expect(result.error, 'login');
    });

    test('onAppResumed is a no-op', () async {
      final store = await guestStore();
      SyncService().scoringActive = true;
      await SyncService().onAppResumed(store);
      // Nothing changed: no push, no pull, guard untouched.
      expect(SyncService().scoringActive, isTrue);
      expect(SyncService().lastSyncAt, isNull);
      SyncService().scoringActive = false;
      await SyncService().onAppResumed(store);
      expect(SyncService().lastSyncAt, isNull);
    });
  });
}
