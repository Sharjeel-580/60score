// Fully local (v1.4.5): local saves never push on their own, and
// there is no sync point left that moves data to the cloud —
// scoring close is local-only, manual Sync now is removed, and the
// sign-in pull is disabled. A save only marks the push debt
// (SyncService.hasUnpushedChanges), which is bookkeeping only in
// this version: nothing consumes it. Tests run offline with no
// Firebase. What these tests pin offline: debt is marked by every
// save path, the local-only close completes without error and
// keeps the debt, and skipSync saves do not mark debt.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cricket_scorer_app/models.dart';
import 'package:cricket_scorer_app/scoring.dart';
import 'package:cricket_scorer_app/store.dart';
import 'package:cricket_scorer_app/sync_service.dart';

Future<Store> _store() async {
  SharedPreferences.setMockInitialValues({});
  final store = Store();
  await store.activateIdentity('guest');
  return store;
}

void main() {
  setUp(() {
    SyncService().scoringActive = false;
    SyncService().cancelPending();
  });
  tearDown(() {
    SyncService().scoringActive = false;
    SyncService().cancelPending();
  });

  test('a full persist marks push debt but pushes nothing', () async {
    final store = await _store();
    await store.upsertTeam(Team(id: 'ta', name: 'Team A', players: []));
    SyncService().cancelPending();
    expect(SyncService().hasUnpushedChanges, isFalse);
    await store.persist();
    expect(SyncService().hasUnpushedChanges, isTrue);
  });

  test('a ball save (matches-only) marks push debt', () async {
    final store = await _store();
    final m = Match(
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
    final inn = startInnings(m, 1);
    setOpeners(inn, inn.battingXI[0], inn.battingXI[1], inn.bowlingXI[0]);
    expect(applyBall(inn, BallInput(batRuns: 4)), isTrue);
    await store.upsertMatch(m);
    SyncService().cancelPending();
    expect(SyncService().hasUnpushedChanges, isFalse);
    await store.persistMatchesOnly();
    expect(SyncService().hasUnpushedChanges, isTrue);
  });

  test('a points-table edit and an adjustment edit mark push debt',
      () async {
    final store = await _store();
    final t = Tournament(id: 't1', name: 'League', teamIds: ['ta', 'tb']);
    t.pointsTableOverrides['ta'] = PointsTableOverride(played: 2, won: 1);
    t.pointsAdjustments['tb'] = 1;
    await store.upsertTournament(t);
    SyncService().cancelPending();
    expect(SyncService().hasUnpushedChanges, isFalse);
    await store.persistTournamentsOnly();
    expect(SyncService().hasUnpushedChanges, isTrue);
  });

  test('debt survives time passing with no auto push', () async {
    final store = await _store();
    await store.persist();
    expect(SyncService().hasUnpushedChanges, isTrue);
    // Past the old ~1s debounce and the old 20s retry cadence:
    // nothing consumes the debt without a sync point.
    await Future.delayed(const Duration(seconds: 2));
    expect(SyncService().hasUnpushedChanges, isTrue);
  });

  test('scoring close is local-only: no error, debt kept', () async {
    final store = await _store();
    await store.persist();
    expect(SyncService().hasUnpushedChanges, isTrue);
    // The fully-local close only saves locally — it must not throw
    // offline and must not consume the debt (nothing pushes).
    await SyncService().syncAfterScoring(store);
    expect(SyncService().hasUnpushedChanges, isTrue);
  });

  test('scoring close saves locally even while scoringActive is set',
      () async {
    final store = await _store();
    await store.persist();
    SyncService().scoringActive = true;
    // The close save does not depend on the flag (callers clear it
    // first in production); it still completes without error.
    await SyncService().syncAfterScoring(store);
    expect(SyncService().hasUnpushedChanges, isTrue);
  });

  test('skipSync saves do not mark debt (pull-apply path)', () async {
    final store = await _store();
    await store.upsertTeam(Team(id: 'ta', name: 'Team A', players: []));
    // The upsert's own internal persist marks debt; clear it to
    // isolate the skipSync save itself.
    SyncService().cancelPending();
    await store.persist(skipSync: true);
    expect(SyncService().hasUnpushedChanges, isFalse);
  });

  test('cancelPending clears the debt (identity-switch safety)',
      () async {
    final store = await _store();
    await store.persist();
    expect(SyncService().hasUnpushedChanges, isTrue);
    SyncService().cancelPending();
    expect(SyncService().hasUnpushedChanges, isFalse);
  });
}
