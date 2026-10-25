// Points-table row overrides (v1.4.4): a hand-edited row replaces the
// computed row, sorts on the overridden values, and Reset (removing
// the override) restores computed values. The override map lives on
// the tournament and must round-trip through JSON; old tournament
// JSON without the field must still load.
import 'package:flutter_test/flutter_test.dart';

import 'package:cricket_scorer_app/models.dart';
import 'package:cricket_scorer_app/scoring.dart';
import 'package:cricket_scorer_app/tournament_engine.dart';

List<String> xi(String p) => [for (var i = 1; i <= 11; i++) '$p$i'];

InningsState totInn(
  String bat,
  String bowl,
  int runs,
  int balls, {
  int wickets = 3,
}) {
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
  inn.wickets = wickets;
  return inn;
}

/// Completed ta-vs-tb match: first innings [runs1] by [bat1],
/// second innings [runs2] by [bat2].
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
    totInn(bat1, teamB, runs1, 48),
    totInn(bat2, teamA, runs2, 48),
  ];
  return m;
}

Tournament tourn(List<String> teamIds) => Tournament(
  id: 't1',
  name: 'T1',
  teamIds: teamIds,
);

void main() {
  // Computed baseline: ta beats tb, tc beats ta.
  // ta P2 W1 L1 Pts 2; tb P1 L1 Pts 0; tc P1 W1 Pts 2.
  final matches = [
    completedMatch(
      id: 'm1',
      teamA: 'ta',
      teamB: 'tb',
      bat1: 'ta',
      bat2: 'tb',
      runs1: 150,
      runs2: 100,
      dateIso: '2026-10-20',
    ),
    completedMatch(
      id: 'm2',
      teamA: 'ta',
      teamB: 'tc',
      bat1: 'ta',
      bat2: 'tc',
      runs1: 90,
      runs2: 120,
      dateIso: '2026-10-21',
    ),
  ];

  PointsRow rowOf(List<PointsRow> rows, String teamId) =>
      rows.firstWhere((r) => r.teamId == teamId);

  test('override replaces a row and sorts on overridden values', () {
    final t = tourn(['ta', 'tb', 'tc']);
    final base = leaguePointsTable(t, matches);
    expect(rowOf(base, 'tb').points, 0);
    expect(rowOf(base, 'tb').played, 1);

    t.pointsTableOverrides['tb'] = PointsTableOverride(
      played: 5,
      won: 5,
      lost: 0,
      tied: 0,
      noResult: 0,
      points: 10,
      nrr: 2.5,
    );
    final edited = leaguePointsTable(t, matches);
    final tb = rowOf(edited, 'tb');
    expect(tb.played, 5);
    expect(tb.won, 5);
    expect(tb.lost, 0);
    expect(tb.points, 10);
    expect(tb.nrr, 2.5);
    // Highest overridden points sorts first.
    expect(edited.first.teamId, 'tb');
    // Other teams are untouched.
    expect(rowOf(edited, 'ta').points, 2);
    expect(rowOf(edited, 'ta').played, 2);
    expect(rowOf(edited, 'tc').points, 2);
  });

  test('override wins over a points adjustment', () {
    final t = tourn(['ta', 'tb', 'tc']);
    t.pointsAdjustments['tb'] = 1;
    t.pointsTableOverrides['tb'] = PointsTableOverride(
      played: 1,
      won: 0,
      lost: 1,
      tied: 0,
      noResult: 0,
      points: 7,
      nrr: -1.25,
    );
    final rows = leaguePointsTable(t, matches);
    // Adjustment (+1) would give 1; the override replaces it with 7.
    expect(rowOf(rows, 'tb').points, 7);
    expect(rowOf(rows, 'tb').nrr, -1.25);
  });

  test('reset (removing the override) restores computed values', () {
    final t = tourn(['ta', 'tb', 'tc']);
    t.pointsTableOverrides['tb'] = PointsTableOverride(
      played: 9,
      won: 9,
      lost: 0,
      tied: 0,
      noResult: 0,
      points: 18,
      nrr: 9.999,
    );
    expect(rowOf(leaguePointsTable(t, matches), 'tb').points, 18);
    t.pointsTableOverrides.remove('tb');
    final restored = leaguePointsTable(t, matches);
    expect(rowOf(restored, 'tb').points, 0);
    expect(rowOf(restored, 'tb').played, 1);
    expect(rowOf(restored, 'tb').won, 0);
    // Computed NRR is back (negative here: tb lost 150-100).
    expect(rowOf(restored, 'tb').nrr < 0, isTrue);
  });

  test('override for an unknown team is ignored', () {
    final t = tourn(['ta', 'tb', 'tc']);
    t.pointsTableOverrides['ghost'] = PointsTableOverride(points: 99);
    final rows = leaguePointsTable(t, matches);
    expect(rows.length, 3);
    expect(rows.any((r) => r.teamId == 'ghost'), isFalse);
  });

  test('tournament toJson/fromJson round-trips overrides', () {
    final t = tourn(['ta', 'tb']);
    t.pointsTableOverrides['ta'] = PointsTableOverride(
      played: 3,
      won: 2,
      lost: 1,
      tied: 0,
      noResult: 0,
      points: 4,
      nrr: 0.75,
    );
    final back = Tournament.fromJson(t.toJson());
    final o = back.pointsTableOverrides['ta']!;
    expect(o.played, 3);
    expect(o.won, 2);
    expect(o.lost, 1);
    expect(o.points, 4);
    expect(o.nrr, 0.75);
    expect(back.pointsTableOverrides.containsKey('tb'), isFalse);
  });

  test('old tournament JSON without the field loads with empty overrides',
      () {
    final json = tourn(['ta']).toJson()..remove('pointsTableOverrides');
    final back = Tournament.fromJson(json);
    expect(back.pointsTableOverrides, isEmpty);
    // And the table still computes normally.
    final rows = leaguePointsTable(back, matches);
    expect(rows.map((r) => r.teamId), contains('ta'));
  });

  test('partial override JSON defaults missing keys to 0', () {
    final o = PointsTableOverride.fromJson({'points': 5});
    expect(o.points, 5);
    expect(o.played, 0);
    expect(o.nrr, 0);
  });
}
