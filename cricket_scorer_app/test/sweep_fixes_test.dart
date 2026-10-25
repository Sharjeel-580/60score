// Sweep fixes (v1.4.3): points-table poisoned-record guard and
// DebugInfo recording. The _afterChange try/catch wrap and the
// auth-stream onError are code-verified only (the wrapped paths
// are private screen methods / need Firebase) — see the report.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cricket_scorer_app/debug_info.dart';
import 'package:cricket_scorer_app/models.dart';
import 'package:cricket_scorer_app/scoring.dart';

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

/// Completed ta-vs-tb match whose innings carry the given batting
/// team ids (poisoned when an id is outside [ta, tb]).
Match poisonedMatch({
  required String bat1,
  required String bat2,
  required int runs1,
  required int runs2,
  required String dateIso,
}) {
  final m = Match(
    id: 'pm_$dateIso',
    tournamentId: 't1',
    teamAId: 'ta',
    teamBId: 'tb',
    xiA: xi('a'),
    xiB: xi('b'),
    oversLimit: 8,
    ballsPerOver: 6,
    tossWinnerId: 'ta',
    tossDecision: 'bat',
    dateIso: dateIso,
    status: 'completed',
  );
  m.innings = [
    totInn(bat1, 'tb', runs1, 48),
    totInn(bat2, 'ta', runs2, 40),
  ];
  return m;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('computePointsTable poisoned-record guard', () {
    test('poisoned LOSING innings: no throw, winner still counted, '
        'poisoned NRR skipped', () {
      final table = computePointsTable(
        't1',
        ['ta', 'tb'],
        [
          poisonedMatch(
            bat1: 'ghost',
            bat2: 'tb',
            runs1: 100,
            runs2: 120,
            dateIso: '2026-10-22',
          ),
        ],
      );
      final ta = table.firstWhere((r) => r.teamId == 'ta');
      final tb = table.firstWhere((r) => r.teamId == 'tb');
      expect(ta.played, 1);
      expect(tb.played, 1);
      expect(tb.won, 1);
      expect(tb.points, 2);
      expect(ta.lost, 1);
      expect(ta.points, 0);
      // The ghost innings contributed no NRR: ta conceded only
      // the valid innings' runs, tb scored only its own.
      expect(tb.runsFor, 120);
      expect(ta.runsAgainst, 120);
      expect(ta.runsFor, 0);
      expect(tb.nrr.isFinite, isTrue);
    });

    test('poisoned WINNING innings: no throw, result unattributed',
        () {
      final table = computePointsTable(
        't1',
        ['ta', 'tb'],
        [
          poisonedMatch(
            bat1: 'ghost',
            bat2: 'tb',
            runs1: 130,
            runs2: 110,
            dateIso: '2026-10-23',
          ),
        ],
      );
      final ta = table.firstWhere((r) => r.teamId == 'ta');
      final tb = table.firstWhere((r) => r.teamId == 'tb');
      expect(ta.played, 1);
      expect(tb.played, 1);
      // Winner id is unknown: neither side gets the win/loss.
      expect(tb.won, 0);
      expect(ta.lost, 0);
      expect(tb.points, 0);
      expect(ta.points, 0);
    });

    test('both innings poisoned: no throw, played counts only', () {
      final table = computePointsTable(
        't1',
        ['ta', 'tb'],
        [
          poisonedMatch(
            bat1: 'ghost',
            bat2: 'ghost2',
            runs1: 100,
            runs2: 90,
            dateIso: '2026-10-24',
          ),
        ],
      );
      final ta = table.firstWhere((r) => r.teamId == 'ta');
      final tb = table.firstWhere((r) => r.teamId == 'tb');
      expect(ta.played, 1);
      expect(tb.played, 1);
      expect(ta.points, 0);
      expect(tb.points, 0);
      expect(ta.nrr, 0);
      expect(tb.nrr, 0);
    });

    test('empty battingTeamId: no throw', () {
      final table = computePointsTable(
        't1',
        ['ta', 'tb'],
        [
          poisonedMatch(
            bat1: '',
            bat2: 'tb',
            runs1: 100,
            runs2: 90,
            dateIso: '2026-10-25',
          ),
        ],
      );
      expect(table.length, 2);
      for (final r in table) {
        expect(r.nrr.isFinite, isTrue);
      }
    });
  });

  group('DebugInfo recording', () {
    tearDown(() {
      DebugInfo.lastError = null;
      DebugInfo.lastErrorAt = null;
    });

    test('record keeps the latest error in memory and it survives '
        'a persist/load round trip', () async {
      SharedPreferences.setMockInitialValues({});
      DebugInfo.record('test boom error');
      expect(DebugInfo.lastError, contains('test boom error'));
      expect(DebugInfo.lastErrorAt, isNotNull);
      // Let the fire-and-forget prefs write land.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      // Simulate a restart: clear memory, load from prefs.
      DebugInfo.lastError = null;
      DebugInfo.lastErrorAt = null;
      await DebugInfo.loadPersisted();
      expect(DebugInfo.lastError, contains('test boom error'));
      expect(DebugInfo.lastErrorAt, isNotNull);
      // A live error wins over the persisted one.
      DebugInfo.record('live error wins');
      await DebugInfo.loadPersisted();
      expect(DebugInfo.lastError, contains('live error wins'));
    });
  });
}
