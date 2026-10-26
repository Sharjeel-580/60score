// Tournaments-only persist (v1.4.5, stability): tournament edits
// (points-table row overrides, points adjustments) must save through
// the tournaments key ONLY — never a full _saveAll that re-encodes
// the teams key with inline player photos (megabytes), which is the
// prime suspect for the silent closes after points-table edits on
// 1.4.4 (no Dart error recorded -> OS-level kill).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cricket_scorer_app/models.dart';
import 'package:cricket_scorer_app/store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('tournament edit saves, reloads, and leaves teams/matches bytes '
      'untouched', () async {
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.load();

    // A team with a large inline photo: the old full-save path would
    // re-encode this on every tournament edit.
    final bigPhoto = 'x' * 200000;
    store.teams = [
      Team(id: 't1', name: 'Team A', players: [
        Player(id: 'p1', name: 'P1', photoBase64: bigPhoto),
      ]),
    ];
    final tournament = Tournament(
      id: 'tour1',
      name: 'League',
      teamIds: ['t1'],
    );
    store.tournaments = [tournament];
    store.matches = [
      Match(
        id: 'm1',
        teamAId: 't1',
        teamBId: 't1',
        xiA: ['p1'],
        xiB: ['p1'],
        oversLimit: 8,
        ballsPerOver: 6,
        tossWinnerId: 't1',
        tossDecision: 'bat',
      ),
    ];

    // Baseline: full persist writes every key.
    await store.persist();
    final prefs = await SharedPreferences.getInstance();
    final teamsBefore = prefs.getString('cricscore_teams_v1__guest');
    final matchesBefore = prefs.getString('cricscore_matches_v1__guest');
    final tournBefore =
        prefs.getString('cricscore_tournaments_v1__guest');
    expect(teamsBefore, isNotNull);
    expect(matchesBefore, isNotNull);
    expect(tournBefore, isNotNull);

    // A points-table row edit + an adjustment, saved tournaments-only.
    tournament.pointsTableOverrides['t1'] = PointsTableOverride(
      played: 2,
      won: 1,
      lost: 0,
      tied: 0,
      noResult: 1,
      points: 3,
      nrr: 1.5,
    );
    tournament.pointsAdjustments['t1'] = 1;
    await store.persistTournamentsOnly();

    // Teams and matches bytes are byte-identical: never re-encoded.
    expect(prefs.getString('cricscore_teams_v1__guest'), teamsBefore);
    expect(prefs.getString('cricscore_matches_v1__guest'), matchesBefore);
    // Tournaments bytes changed and carry the edit.
    final tournAfter =
        prefs.getString('cricscore_tournaments_v1__guest')!;
    expect(tournAfter, isNot(equals(tournBefore)));
    final tournJson =
        jsonDecode(tournAfter) as List;
    final tourMap = tournJson.first as Map<String, dynamic>;
    final row = (tourMap['pointsTableOverrides'] as Map)['t1']
        as Map<String, dynamic>;
    expect(row['points'], 3);
    expect(row['nrr'], 1.5);
    expect((tourMap['pointsAdjustments'] as Map)['t1'], 1);

    // Reload: the edit survives, teams photos and matches intact.
    final reloaded = Store();
    await reloaded.load();
    expect(reloaded.teams.length, 1);
    expect(reloaded.teams[0].players[0].photoBase64.length, 200000);
    expect(reloaded.matches.length, 1);
    expect(reloaded.tournaments.length, 1);
    final reTour = reloaded.tournaments[0];
    expect(reTour.pointsTableOverrides['t1']!.points, 3);
    expect(reTour.pointsTableOverrides['t1']!.nrr, 1.5);
    expect(reTour.pointsAdjustments['t1'], 1);
  });

  test('persistTournamentsOnly on an empty store does not throw', () async {
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.load();
    await store.persistTournamentsOnly();
    final reloaded = Store();
    await reloaded.load();
    expect(reloaded.tournaments, isEmpty);
  });

  test('reset-removal survives reload, listeners fire, lastModified '
      'advances', () async {
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.load();
    store.tournaments = [
      Tournament(id: 'tour1', name: 'League', teamIds: ['t1']),
    ];
    final tournament = store.tournaments[0];
    // Seed an override + adjustment, as the points-table edit does.
    tournament.pointsTableOverrides['t1'] = PointsTableOverride(
      played: 2,
      won: 1,
      lost: 0,
      tied: 0,
      noResult: 1,
      points: 3,
      nrr: 1.5,
    );
    tournament.pointsAdjustments['t1'] = 1;
    await store.persistTournamentsOnly();

    // Pin lastModified to a fixed old value so the advance check is
    // deterministic (two saves in the same millisecond could tie).
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('score60_last_modified_v1__guest', 1000);
    var notified = 0;
    store.addListener(() => notified++);
    // Reset path (as _editPointsRow reset does): remove both entries
    // and save tournaments-only.
    tournament.pointsTableOverrides.remove('t1');
    tournament.pointsAdjustments.remove('t1');
    await store.persistTournamentsOnly();
    expect(notified, 1);
    expect(await store.getLastModified(), greaterThan(1000));

    // Reload: the reset survived — both entries are gone.
    final reloaded = Store();
    await reloaded.load();
    expect(reloaded.tournaments.length, 1);
    expect(
        reloaded.tournaments[0].pointsTableOverrides.containsKey('t1'),
        isFalse);
    expect(
        reloaded.tournaments[0].pointsAdjustments.containsKey('t1'),
        isFalse);
  });
}
