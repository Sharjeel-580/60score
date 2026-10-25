// Fully local (v1.4.5): no network call is reachable from any UI
// entry — Sync now removed, scoring close local-only, sign-in pull
// disabled, publish/viewer paths no-ops. Tests run with NO Firebase
// initialized, so any reachable Firestore access would throw; every
// entry below completing offline with correct local prefs is the
// test-environment proof. The structural proof is the code itself:
// no UI entry references pull/syncNow/publish writes anymore
// (verified by grep over lib/ at build time).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cricket_scorer_app/models.dart';
import 'package:cricket_scorer_app/publish_service.dart';
import 'package:cricket_scorer_app/scoring.dart';
import 'package:cricket_scorer_app/screens/profile_screen.dart';
import 'package:cricket_scorer_app/store.dart';
import 'package:cricket_scorer_app/sync_service.dart';

Future<Store> _guestStore() async {
  SharedPreferences.setMockInitialValues({});
  final store = Store();
  await store.activateIdentity('guest');
  return store;
}

InningsState _innings() {
  final s = InningsState(
    battingTeamId: 'ta',
    bowlingTeamId: 'tb',
    battingXI: ['a1', 'a2', 'a3', 'a4'],
    bowlingXI: ['b1', 'b2'],
    oversLimit: 8,
  );
  setOpeners(s, 'a1', 'a2', 'b1');
  return s;
}

Match _liveMatch(InningsState inn) => Match(
      id: 'm1',
      teamAId: 'ta',
      teamBId: 'tb',
      xiA: ['a1', 'a2', 'a3', 'a4'],
      xiB: ['b1', 'b2'],
      oversLimit: 8,
      tossWinnerId: 'ta',
      tossDecision: 'bat',
      status: 'live',
      innings: [inn],
    );

Future<Store> _reloaded() async {
  final store = Store();
  await store.activateIdentity('guest');
  return store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('guest Profile has no Sync now tile', (tester) async {
    final store = await _guestStore();
    await tester.pumpWidget(
      MaterialApp(home: ProfileScreen(store: store)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sync now'), findsNothing);
    // Sanity: the screen itself rendered.
    expect(find.text('Debug info'), findsOneWidget);
  });

  test('ball entry saves matches-only offline and reloads', () async {
    final store = await _guestStore();
    final inn = _innings();
    store.matches = [_liveMatch(inn)];
    expect(applyBall(inn, BallInput(batRuns: 4)), isTrue);
    expect(await store.persistMatchesOnly(), isTrue);
    final reloaded = await _reloaded();
    final rInn = reloaded.matches.single.innings.single;
    expect(rInn.totalRuns, 4);
    expect(rInn.batting['a1']!.runs, 4);
  });

  test('points edit saves tournaments-only offline and reloads',
      () async {
    final store = await _guestStore();
    final t = Tournament(id: 'tour1', name: 'League', teamIds: ['ta']);
    store.tournaments = [t];
    t.pointsTableOverrides['ta'] = PointsTableOverride(
      played: 2,
      won: 1,
      lost: 0,
      tied: 0,
      noResult: 1,
      points: 3,
      nrr: 1.5,
    );
    expect(await store.persistTournamentsOnly(), isTrue);
    final reloaded = await _reloaded();
    final o = reloaded.tournaments.single.pointsTableOverrides['ta']!;
    expect(o.points, 3);
    expect(o.nrr, 1.5);
  });

  test('stats edit saves tournaments-only offline and reloads', () async {
    final store = await _guestStore();
    final t = Tournament(id: 'tour1', name: 'League', teamIds: ['ta']);
    store.tournaments = [t];
    t.playerStatsOverrides['p1'] = PlayerStatsOverride(runs: 120);
    expect(await store.persistTournamentsOnly(), isTrue);
    final reloaded = await _reloaded();
    expect(
      reloaded.tournaments.single.playerStatsOverrides['p1']!.runs,
      120,
    );
  });

  test('scorecard figure save reloads offline', () async {
    final store = await _guestStore();
    final inn = _innings();
    store.matches = [_liveMatch(inn)];
    final fig = BatFig()
      ..runs = 45
      ..balls = 20
      ..fours = 5
      ..sixes = 2;
    inn.batting['a1'] = fig;
    inn.totalRuns = 45;
    expect(await store.persistMatchesOnly(), isTrue);
    final reloaded = await _reloaded();
    expect(reloaded.matches.single.innings.single.batting['a1']!.runs, 45);
    expect(reloaded.matches.single.innings.single.totalRuns, 45);
  });

  test('scoring close saves locally offline, no error', () async {
    final store = await _guestStore();
    final inn = _innings();
    final m = _liveMatch(inn);
    store.matches = [m];
    await store.persistMatchesOnly();
    m.resultText = 'Team A won by 10 runs';
    m.status = 'completed';
    await SyncService().syncAfterScoring(store);
    final reloaded = await _reloaded();
    expect(reloaded.matches.single.resultText, 'Team A won by 10 runs');
    expect(reloaded.matches.single.status, 'completed');
  });

  test('sign-in scope switch completes offline with no pull', () async {
    final store = await _guestStore();
    await store.activateAccount(
      'uid-x',
      email: 'a@b.c',
      displayName: 'Tester',
    );
    expect(store.identityId, 'uid-x');
  });

  test('publish/unpublish/viewer paths are no-ops offline', () async {
    final store = await _guestStore();
    final t = Tournament(id: 'tour1', name: 'League', teamIds: ['ta']);
    t.published = true;
    store.tournaments = [t];
    final svc = PublishService();
    // Publish/unpublish report "off" and change NOTHING — no false
    // flag, no Firestore delete, no persist.
    expect(await svc.publish(store, t), contains('off'));
    expect(t.published, isTrue);
    expect(await svc.unpublish(store, t), contains('off'));
    expect(t.published, isTrue);
    expect(await svc.fetchPublished(), isEmpty);
    expect(await svc.watchPublished().first, isEmpty);
    expect(await svc.watchOne('tour1').first, isNull);
    svc.scheduleRepublish(store);
    svc.deletePublishedDoc('tour1');
  });
}
