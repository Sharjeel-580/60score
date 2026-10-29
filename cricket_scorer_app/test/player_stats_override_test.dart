// Per-player stats overrides (v1.4.5, delta semantics since
// v1.4.7): additive counters display as computed + delta, so later
// matches keep updating an edited row; highScore/bestWickets/
// bestRuns display as max(computed, manual floor). Derived values
// recompute from the displayed counters via CareerStats getters.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cricket_scorer_app/models.dart';
import 'package:cricket_scorer_app/scoring.dart';
import 'package:cricket_scorer_app/store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('override adjusts computed row (delta) and derived values recompute',
      () {
    final c = CareerStats('p1')
      ..matches = 4
      ..inningsBatted = 4
      ..notOuts = 0
      ..runs = 100
      ..ballsFaced = 50
      ..ballsBowled = 60
      ..runsConceded = 60
      ..wickets = 2
      ..bestWickets = 2
      ..bestRuns = 20;
    final map = {'p1': c};
    // Deltas chosen so additive counters land on the old wholesale
    // values: computed runs 100 + delta 200 = 300, matches 4 + 6
    // = 10, and so on.
    applyPlayerStatsOverrides(map, {
      'p1': PlayerStatsOverride(
        matches: 6,
        inningsBatted: 4,
        notOuts: 2,
        runs: 200,
        ballsFaced: 100,
        highScore: 120,
        hundreds: 1,
        fifties: 2,
        fours: 30,
        sixes: 10,
        ballsBowled: 60,
        runsConceded: 30,
        wickets: 4,
        bestWickets: 4,
        bestRuns: 15,
        catches: 3,
        stumpings: 1,
        runOuts: 2,
      ),
    });
    // Base counters adjusted by the deltas.
    expect(c.matches, 10);
    expect(c.runs, 300);
    expect(c.ballsFaced, 150);
    expect(c.wickets, 6);
    // Derived values recompute from the displayed counters.
    expect(c.dismissals, 6);
    expect(c.battingAverage, 50);
    expect(c.battingSR, 200);
    expect(c.economy, 4.5);
    expect(c.bowlingAverage, 15);
    // MAX fields: bestWickets floor 4 beats computed 2, but the
    // bestRuns floor 15 does NOT beat computed 20 — the displayed
    // best figure is 4/20, not 4/15.
    expect(c.bestFigures, '4/20');
    expect(c.highScore, 120);
  });

  test('override for an unknown player is skipped', () {
    final c = CareerStats('p1')..runs = 50;
    final map = {'p1': c};
    applyPlayerStatsOverrides(map, {
      'ghost': PlayerStatsOverride(runs: 999),
    });
    expect(map.length, 1);
    expect(c.runs, 50);
  });

  test('tournament round-trip, old JSON, and one bad entry', () {
    final t = Tournament(id: 'tour1', name: 'League', teamIds: ['t1']);
    t.playerStatsOverrides['p1'] = PlayerStatsOverride(runs: 250);
    final back =
        Tournament.fromJson(jsonDecode(jsonEncode(t.toJson())));
    expect(back.playerStatsOverrides['p1']!.runs, 250);

    // Old JSON without the key loads with empty overrides.
    final oldJson = Map<String, dynamic>.from(t.toJson())
      ..remove('playerStatsOverrides');
    final old = Tournament.fromJson(oldJson);
    expect(old.playerStatsOverrides, isEmpty);

    // One bad entry never kills the tournament; good entries survive.
    final mixed = Map<String, dynamic>.from(t.toJson());
    mixed['playerStatsOverrides'] = {
      'p1': {'runs': 250},
      'bad': 'not-a-map',
    };
    final mixedBack = Tournament.fromJson(mixed);
    expect(mixedBack.playerStatsOverrides['p1']!.runs, 250);
    expect(mixedBack.playerStatsOverrides.containsKey('bad'), isFalse);
  });

  test('override persists tournaments-only and reset survives reload',
      () async {
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.load();
    final tournament =
        Tournament(id: 'tour1', name: 'League', teamIds: ['t1']);
    store.tournaments = [tournament];
    tournament.playerStatsOverrides['p1'] =
        PlayerStatsOverride(runs: 250, matches: 5);
    await store.persistTournamentsOnly();

    var reloaded = Store();
    await reloaded.load();
    expect(
        reloaded.tournaments[0].playerStatsOverrides['p1']!.runs, 250);
    expect(
        reloaded.tournaments[0].playerStatsOverrides['p1']!.matches, 5);

    // Reset path: remove and save again — reload shows it gone.
    tournament.playerStatsOverrides.remove('p1');
    await store.persistTournamentsOnly();
    reloaded = Store();
    await reloaded.load();
    expect(
        reloaded.tournaments[0].playerStatsOverrides.containsKey('p1'),
        isFalse);
  });
}
