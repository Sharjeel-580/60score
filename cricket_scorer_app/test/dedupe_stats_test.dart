import 'package:cricket_scorer_app/models.dart';
import 'package:cricket_scorer_app/player_insights.dart';
import 'package:cricket_scorer_app/scoring.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a match with the given totals, directly on the innings
/// figures (points/NRR/career-stats reads only need these).
Match _totalsMatch({
  required String id,
  String? tournamentId,
  required String dateIso,
  required String status,
  required int runsA,
  required int runsB,
  int ballsA = 48,
  int ballsB = 48,
  int eventsA = 0,
  int eventsB = 0,
}) {
  final m = Match(
    id: id,
    tournamentId: tournamentId,
    teamAId: 'ta',
    teamBId: 'tb',
    xiA: const ['a1', 'a2'],
    xiB: const ['b1', 'b2'],
    oversLimit: 8,
    ballsPerOver: 6,
    dateIso: dateIso,
    tossWinnerId: 'ta',
    tossDecision: 'bat',
    status: status,
  );
  final i1 = InningsState(
    battingTeamId: 'ta',
    bowlingTeamId: 'tb',
    battingXI: const ['a1', 'a2'],
    bowlingXI: const ['b1', 'b2'],
    oversLimit: 8,
    ballsPerOver: 6,
  )
    ..totalRuns = runsA
    ..legalBalls = ballsA
    ..events = List.generate(
      eventsA,
      (_) => BallEvent(strikerId: 'a1', nonStrikerId: 'a2', bowlerId: 'b1'),
    );
  final i2 = InningsState(
    battingTeamId: 'tb',
    bowlingTeamId: 'ta',
    battingXI: const ['b1', 'b2'],
    bowlingXI: const ['a1', 'a2'],
    oversLimit: 8,
    ballsPerOver: 6,
  )
    ..totalRuns = runsB
    ..legalBalls = ballsB
    ..events = List.generate(
      eventsB,
      (_) => BallEvent(strikerId: 'b1', nonStrikerId: 'b2', bowlerId: 'a1'),
    );
  m.innings = [i1, i2];
  return m;
}

void main() {
  group('dedupeMatches (duplicate-fixture safety net)', () {
    test('completed repair beats a live re-push of the same fixture', () {
      final live = _totalsMatch(
        id: 'live-1',
        tournamentId: 't1',
        dateIso: '2026-10-24',
        status: 'live',
        runsA: 58,
        runsB: 0,
        ballsA: 25,
        ballsB: 0,
      );
      final completed = _totalsMatch(
        id: 'repair-1',
        tournamentId: 't1',
        dateIso: '2026-10-24',
        status: 'completed',
        runsA: 130,
        runsB: 131,
      );
      final rows = computePointsTable('t1', ['ta', 'tb'], [live, completed]);
      final a = rows.firstWhere((r) => r.teamId == 'ta');
      final b = rows.firstWhere((r) => r.teamId == 'tb');
      // Counted exactly once, from the completed record.
      expect(a.played, 1);
      expect(b.played, 1);
      expect(b.won, 1);
      expect(b.points, 2);
      expect(a.points, 0);
      expect(b.runsFor, 131);
    });

    test('two completed records: the fuller one (more legal balls) wins',
      () {
      final partial = _totalsMatch(
        id: 'partial',
        tournamentId: 't1',
        dateIso: '2026-10-24',
        status: 'completed',
        runsA: 50,
        runsB: 40,
        ballsA: 12,
        ballsB: 12,
      );
      final full = _totalsMatch(
        id: 'full',
        tournamentId: 't1',
        dateIso: '2026-10-24',
        status: 'completed',
        runsA: 100,
        runsB: 90,
        ballsA: 48,
        ballsB: 48,
      );
      final kept = dedupeMatches([partial, full]);
      expect(kept.length, 1);
      expect(kept.first.id, 'full');
    });

    test('different dates are different fixtures: both count', () {
      final m1 = _totalsMatch(
        id: 'd1',
        tournamentId: 't1',
        dateIso: '2026-10-24',
        status: 'completed',
        runsA: 100,
        runsB: 90,
      );
      final m2 = _totalsMatch(
        id: 'd2',
        tournamentId: 't1',
        dateIso: '2026-10-25',
        status: 'completed',
        runsA: 80,
        runsB: 70,
      );
      final rows = computePointsTable('t1', ['ta', 'tb'], [m1, m2]);
      expect(rows.firstWhere((r) => r.teamId == 'ta').played, 2);
    });

    test('dateless / standalone records are never collapsed', () {
      final m1 = _totalsMatch(
        id: 's1',
        dateIso: '',
        status: 'completed',
        runsA: 100,
        runsB: 90,
      );
      final m2 = _totalsMatch(
        id: 's2',
        dateIso: '',
        status: 'completed',
        runsA: 80,
        runsB: 70,
      );
      expect(dedupeMatches([m1, m2]).length, 2);
    });
  });

  group('no-result matches in player stats', () {
    test('NR match figures count in career stats, not in NRR', () {
      final m = Match(
        id: 'nr1',
        tournamentId: 't1',
        teamAId: 'ta',
        teamBId: 'tb',
        xiA: const ['a1', 'a2'],
        xiB: const ['b1', 'b2'],
        oversLimit: 8,
        ballsPerOver: 6,
        dateIso: '2026-10-23',
        tossWinnerId: 'ta',
        tossDecision: 'bat',
        status: 'noResult',
      );
      final i1 = startInnings(m, 1);
      setOpeners(i1, 'a1', 'a2', 'b1');
      applyBall(i1, BallInput(batRuns: 4));
      applyBall(i1, BallInput(batRuns: 6));
      applyBall(
        i1,
        BallInput(isWicket: true, wicketType: 'bowled'),
      );
      final stats = computeCareerStats([m]);
      expect(stats['a1']!.runs, 10);
      expect(stats['a1']!.ballsFaced, 3);
      expect(stats['b1']!.wickets, 1);
      // Points table: NR gives 1 point each, zero NRR effect.
      final rows = computePointsTable('t1', ['ta', 'tb'], [m]);
      final a = rows.firstWhere((r) => r.teamId == 'ta');
      final b = rows.firstWhere((r) => r.teamId == 'tb');
      expect(a.noResult, 1);
      expect(a.points, 1);
      expect(b.points, 1);
      expect(a.runsFor, 0);
      expect(a.nrr, 0);
      // Player insights follow the same rule.
      final insights = buildPlayerInsights([m], 'a1');
      expect(insights.batting.totalRuns, 10);
    });
  });
}
