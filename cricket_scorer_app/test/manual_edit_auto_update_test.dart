// Manual-edit auto-update (v1.4.7): a hand-edited points-table row
// or player-stats row must keep updating when later matches
// complete — the correction stays AND the new match flows in.
// Additive fields are stored as deltas (displayed = computed +
// delta); MAX fields (highScore, bestWickets/bestRuns) are absolute
// floors (displayed = max(computed, manual)). Old wholesale
// overrides migrate to deltas on first load with displayed values
// exactly unchanged (except a MAX field the computed value already
// overtook, which is the new rule). Reset removes the override.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cricket_scorer_app/models.dart';
import 'package:cricket_scorer_app/scoring.dart';
import 'package:cricket_scorer_app/store.dart';
import 'package:cricket_scorer_app/tournament_engine.dart';

List<String> xi(String p) => [for (var i = 1; i <= 11; i++) '$p$i'];

InningsState totInn(String bat, String bowl, int runs, int balls) {
  final inn = InningsState(
    battingTeamId: bat,
    bowlingTeamId: bowl,
    battingXI: xi(bat),
    bowlingXI: xi(bowl),
    oversLimit: 8,
    ballsPerOver: 6,
  );
  inn.totalRuns = runs;
  inn.legalBalls = balls;
  inn.wickets = 3;
  return inn;
}

/// Completed match: first innings [runs1] by [bat1], second innings
/// [runs2] by [bat2]. 8 overs a side, so NRR is runs/8 each way.
Match completedMatch({
  required String id,
  required String teamA,
  required String teamB,
  required String bat1,
  required String bat2,
  required int runs1,
  required int runs2,
  required String dateIso,
}) {
  final m = Match(
    id: id,
    tournamentId: 't1',
    teamAId: teamA,
    teamBId: teamB,
    xiA: xi('a'),
    xiB: xi('b'),
    oversLimit: 8,
    ballsPerOver: 6,
    tossWinnerId: teamA,
    tossDecision: 'bat',
    dateIso: dateIso,
    status: 'completed',
  );
  m.innings = [
    // Bowling side is the team NOT batting in that innings (the
    // caller may put either team first).
    totInn(bat1, bat1 == teamA ? teamB : teamA, runs1, 48),
    totInn(bat2, bat2 == teamA ? teamB : teamA, runs2, 48),
  ];
  return m;
}

Tournament tourn(List<String> teamIds) =>
    Tournament(id: 't1', name: 'League', teamIds: teamIds);

PointsRow rowOf(List<PointsRow> rows, String id) =>
    rows.firstWhere((r) => r.teamId == id);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('points table', () {
    // m1: ta 150 beats tb 100. tb computed: played 1, lost 1,
    // points 0, NRR -6.25. m2: tb 120 beats ta 90. After both,
    // tb computed: played 2, won 1, lost 1, points 2, NRR -1.25.
    final m1 = completedMatch(
      id: 'm1',
      teamA: 'ta',
      teamB: 'tb',
      bat1: 'ta',
      bat2: 'tb',
      runs1: 150,
      runs2: 100,
      dateIso: '2026-10-28T15:00:00',
    );
    final m2 = completedMatch(
      id: 'm2',
      teamA: 'ta',
      teamB: 'tb',
      bat1: 'tb',
      bat2: 'ta',
      runs1: 120,
      runs2: 90,
      dateIso: '2026-10-29T15:00:00',
    );

    test('edit a row, then a new match completes: correction kept, '
        'new match flows in', () {
      final t = tourn(['ta', 'tb']);
      // Baseline: tb computed after m1 only.
      var rows = leaguePointsTable(t, [m1]);
      expect(rowOf(rows, 'tb').played, 1);
      expect(rowOf(rows, 'tb').points, 0);
      expect(rowOf(rows, 'tb').nrr, closeTo(-6.25, 1e-9));
      // "Edit" as the dialog does it: the user sees displayed
      // values and types new ones; the stored delta is typed
      // minus computed. Displayed played 3, points 5, NRR -1.25.
      t.pointsTableOverrides['tb'] = PointsTableOverride(
        played: 3 - 1,
        won: 0,
        lost: 0,
        tied: 0,
        noResult: 0,
        points: 5 - 0,
        nrr: -1.25 - (-6.25),
      );
      rows = leaguePointsTable(t, [m1]);
      expect(rowOf(rows, 'tb').played, 3);
      expect(rowOf(rows, 'tb').points, 5);
      expect(rowOf(rows, 'tb').nrr, closeTo(-1.25, 1e-9));
      // m2 completes: tb computed becomes played 2, won 1,
      // points 2, NRR -1.25. Displayed = computed + delta.
      rows = leaguePointsTable(t, [m1, m2]);
      final tb = rowOf(rows, 'tb');
      expect(tb.played, 4);
      expect(tb.won, 1);
      expect(tb.lost, 1);
      expect(tb.points, 7);
      expect(tb.nrr, closeTo(3.75, 1e-9));
    });

    test('migration preserves displayed values at migration moment',
        () {
      final t = tourn(['ta', 'tb']);
      // Old wholesale override: the row USED to display these.
      final old = PointsTableOverride(
        played: 5,
        won: 5,
        lost: 0,
        tied: 0,
        noResult: 0,
        points: 10,
        nrr: 2.5,
      );
      final computed = rowOf(leaguePointsTable(t, [m1]), 'tb');
      final delta = pointsOverrideToDelta(old, computed);
      t.pointsTableOverrides['tb'] = delta;
      final displayed = rowOf(leaguePointsTable(t, [m1]), 'tb');
      expect(displayed.played, 5);
      expect(displayed.won, 5);
      expect(displayed.lost, 0);
      expect(displayed.points, 10);
      expect(displayed.nrr, closeTo(2.5, 1e-9));
    });

    test('store migration flips the flag once and is then a no-op',
        () {
      SharedPreferences.setMockInitialValues({});
      final t = tourn(['ta', 'tb']);
      t.pointsTableOverrides['tb'] = PointsTableOverride(
        played: 5,
        won: 5,
        lost: 0,
        tied: 0,
        noResult: 0,
        points: 10,
        nrr: 2.5,
      );
      // Simulate an old on-disk tournament: no flag key.
      final oldJson = t.toJson()..remove('overridesDeltaMigrated');
      final loaded = Tournament.fromJson(oldJson);
      expect(loaded.overridesDeltaMigrated, isFalse);
      final store = Store();
      store.tournaments = [loaded];
      store.matches = [m1];
      expect(store.migrateOverridesToDeltas(), isTrue);
      expect(loaded.overridesDeltaMigrated, isTrue);
      final displayed =
          rowOf(leaguePointsTable(loaded, [m1]), 'tb');
      expect(displayed.played, 5);
      expect(displayed.points, 10);
      expect(displayed.nrr, closeTo(2.5, 1e-9));
      // Second run: nothing changes — a delta is never re-derived.
      final stored = loaded.pointsTableOverrides['tb']!;
      expect(store.migrateOverridesToDeltas(), isFalse);
      expect(loaded.pointsTableOverrides['tb']!.points, stored.points);
      expect(loaded.pointsTableOverrides['tb']!.nrr, stored.nrr);
    });

    test('reset still removes the override entirely', () {
      final t = tourn(['ta', 'tb']);
      t.pointsTableOverrides['tb'] = PointsTableOverride(
        played: 2,
        points: 5,
        nrr: 5.0,
      );
      var rows = leaguePointsTable(t, [m1, m2]);
      expect(rowOf(rows, 'tb').points, 7);
      t.pointsTableOverrides.remove('tb');
      rows = leaguePointsTable(t, [m1, m2]);
      final tb = rowOf(rows, 'tb');
      expect(tb.played, 2);
      expect(tb.won, 1);
      expect(tb.points, 2);
      expect(tb.nrr, closeTo(-1.25, 1e-9));
    });

    test('edit-save round-trip: typing the displayed value again '
        'keeps the same delta', () {
      final t = tourn(['ta', 'tb']);
      // Existing delta gives displayed points 5, played 3.
      t.pointsTableOverrides['tb'] = PointsTableOverride(
        played: 2,
        points: 5,
        nrr: 5.0,
      );
      var rows = leaguePointsTable(t, [m1]);
      expect(rowOf(rows, 'tb').points, 5);
      // User re-opens the dialog (sees 5) and saves 5 unchanged:
      // new delta = typed - computed = 5 - 0, same as before.
      final computed = rowOf(
        leaguePointsTable(
          tourn(['ta', 'tb']),
          [m1],
        ),
        'tb',
      );
      t.pointsTableOverrides['tb'] = PointsTableOverride(
        played: 3 - computed.played,
        points: 5 - computed.points,
        nrr: -1.25 - computed.nrr,
      );
      rows = leaguePointsTable(t, [m1]);
      expect(rowOf(rows, 'tb').played, 3);
      expect(rowOf(rows, 'tb').points, 5);
      expect(rowOf(rows, 'tb').nrr, closeTo(-1.25, 1e-9));
    });
  });

  group('player stats', () {
    CareerStats computedBase() => CareerStats('p1')
      ..matches = 4
      ..inningsBatted = 4
      ..notOuts = 0
      ..runs = 100
      ..ballsFaced = 60
      ..ballsBowled = 60
      ..runsConceded = 60
      ..wickets = 2
      ..fifties = 1
      ..highScore = 60
      ..bestWickets = 2
      ..bestRuns = 20;

    // The correction used by the edit/new-match tests: displayed
    // runs +30, wickets +3, fifties +1; highScore floor 80,
    // bestWickets floor 3, bestRuns floor 15.
    PlayerStatsOverride correction() => PlayerStatsOverride(
          runs: 30,
          wickets: 3,
          fifties: 1,
          highScore: 80,
          bestWickets: 3,
          bestRuns: 15,
        );

    test('edit a row, then a new match completes: correction kept, '
        'new match flows in, MAX fields hold or overtake', () {
      final c1 = computedBase();
      applyPlayerStatsOverrides({'p1': c1}, {'p1': correction()});
      expect(c1.runs, 130);
      expect(c1.wickets, 5);
      expect(c1.fifties, 2);
      expect(c1.highScore, 80);
      expect(c1.bestFigures, '3/20');
      // New match: +50 runs, +1 wicket, highScore 70, best 3/25.
      final c2 = computedBase()
        ..matches = 5
        ..inningsBatted = 5
        ..runs = 150
        ..ballsFaced = 90
        ..ballsBowled = 90
        ..runsConceded = 90
        ..wickets = 3
        ..highScore = 70
        ..bestWickets = 3
        ..bestRuns = 25;
      applyPlayerStatsOverrides({'p1': c2}, {'p1': correction()});
      expect(c2.runs, 180);
      expect(c2.wickets, 6);
      expect(c2.fifties, 2);
      // Floor 80 still beats computed 70.
      expect(c2.highScore, 80);
      // Computed bestRuns 25 overtakes the floor 15.
      expect(c2.bestFigures, '3/25');
    });

    test('migration preserves displayed values at migration moment',
        () {
      final computed = computedBase();
      final old = PlayerStatsOverride(
        matches: 5,
        runs: 130,
        wickets: 5,
        fifties: 2,
        highScore: 80,
        bestWickets: 3,
        bestRuns: 25,
      );
      final delta = playerStatsOverrideToDelta(old, computed);
      final displayed = computedBase();
      applyPlayerStatsOverrides(
          {'p1': displayed}, {'p1': delta});
      expect(displayed.matches, 5);
      expect(displayed.runs, 130);
      expect(displayed.wickets, 5);
      expect(displayed.fifties, 2);
      expect(displayed.highScore, 80);
      expect(displayed.bestFigures, '3/25');
    });

    test('migration MAX exception: a computed best that already '
        'overtook the manual best stays at computed', () {
      final computed = computedBase(); // bestRuns 20.
      final old = PlayerStatsOverride(bestRuns: 15);
      final delta = playerStatsOverrideToDelta(old, computed);
      final displayed = computedBase();
      applyPlayerStatsOverrides(
          {'p1': displayed}, {'p1': delta});
      // The manual 15 is preserved as a floor, but it is below
      // the computed 20, so the displayed best stays 20.
      expect(displayed.bestRuns, 20);
    });

    test('reset still removes the override entirely', () {
      final overrides = {'p1': correction()};
      final c = computedBase();
      applyPlayerStatsOverrides({'p1': c}, overrides);
      expect(c.runs, 130);
      overrides.remove('p1');
      final fresh = computedBase();
      applyPlayerStatsOverrides({'p1': fresh}, overrides);
      expect(fresh.runs, 100);
      expect(fresh.wickets, 2);
      expect(fresh.highScore, 60);
    });

    test('edit-save round-trip: typing the displayed value again '
        'keeps the same delta', () {
      final computed = computedBase(); // runs 100.
      // Existing delta +30 shows 130; user types 130 again.
      final again = PlayerStatsOverride(runs: 130 - computed.runs);
      final displayed = computedBase();
      applyPlayerStatsOverrides({'p1': displayed}, {'p1': again});
      expect(displayed.runs, 130);
      // User raises the displayed value to 140: new delta +40.
      final raised = PlayerStatsOverride(runs: 140 - computed.runs);
      final displayed2 = computedBase();
      applyPlayerStatsOverrides({'p1': displayed2}, {'p1': raised});
      expect(displayed2.runs, 140);
    });

    test('store migration with real matches: displayed exact, then '
        'a new match flows in', () {
      SharedPreferences.setMockInitialValues({});
      final t = tourn(['ta', 'tb']);
      // Old wholesale override for a1: shows runs 100, matches 3.
      t.playerStatsOverrides['a1'] = PlayerStatsOverride(
        matches: 3,
        runs: 100,
        highScore: 70,
      );
      final oldJson = t.toJson()..remove('overridesDeltaMigrated');
      final loaded = Tournament.fromJson(oldJson);
      expect(loaded.overridesDeltaMigrated, isFalse);

      Match matchWithScore(String id, int runs) {
        final m = Match(
          id: id,
          tournamentId: 't1',
          teamAId: 'ta',
          teamBId: 'tb',
          xiA: const ['a1', 'a2'],
          xiB: const ['b1', 'b2'],
          oversLimit: 8,
          ballsPerOver: 6,
          tossWinnerId: 'ta',
          status: 'completed',
        );
        final inn = InningsState(
          battingTeamId: 'ta',
          bowlingTeamId: 'tb',
          battingXI: const ['a1', 'a2'],
          bowlingXI: const ['b1', 'b2'],
          oversLimit: 8,
          ballsPerOver: 6,
        );
        inn.batting['a1'] = BatFig()
          ..batted = true
          ..runs = runs
          ..balls = 30;
        inn.totalRuns = 120;
        inn.legalBalls = 48;
        inn.wickets = 2;
        m.innings = [inn];
        return m;
      }

      final store = Store();
      store.tournaments = [loaded];
      store.matches = [matchWithScore('m1', 62)];
      expect(store.migrateOverridesToDeltas(), isTrue);
      // Computed after m1: matches 1, runs 62, highScore 62.
      // Displayed must equal the old wholesale values exactly.
      var map = computeCareerStats(store.matches, tournamentId: 't1');
      applyManualStats(map, store.manualStats);
      applyPlayerStatsOverrides(
          map, loaded.playerStatsOverrides);
      expect(map['a1']!.matches, 3);
      expect(map['a1']!.runs, 100);
      expect(map['a1']!.highScore, 70);
      // A new match (a1 scores 30) flows in on top of the delta.
      store.matches.add(matchWithScore('m2', 30));
      map = computeCareerStats(store.matches, tournamentId: 't1');
      applyManualStats(map, store.manualStats);
      applyPlayerStatsOverrides(
          map, loaded.playerStatsOverrides);
      expect(map['a1']!.matches, 4);
      expect(map['a1']!.runs, 130);
      expect(map['a1']!.highScore, 70);
    });
  });
}
