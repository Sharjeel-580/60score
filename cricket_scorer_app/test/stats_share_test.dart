// v1.1.7: Top-5 share-stats categories — real data only, no fabricated rows.
// Pure in-memory logic; no SharedPreferences I/O.
import 'package:flutter_test/flutter_test.dart';
import 'package:cricket_scorer_app/models.dart';
import 'package:cricket_scorer_app/stats_share.dart';
import 'package:cricket_scorer_app/store.dart';

Store _store() => Store();

/// A completed match where each entry maps playerId -> {runs, balls, out}.
Match _completedMatch(
    String id, String tid, Map<String, Map<String, int>> batters) {
  final pids = batters.keys.toList();
  final m = Match(
    id: id,
    tournamentId: tid,
    teamAId: 'ta',
    teamBId: 'tb',
    xiA: pids,
    xiB: const ['x1'],
    oversLimit: 20,
    ballsPerOver: 6,
    tossWinnerId: 'ta',
    tossDecision: 'bat',
    status: 'completed',
  );
  final inn = InningsState(
    battingTeamId: 'ta',
    bowlingTeamId: 'tb',
    battingXI: pids,
    bowlingXI: const ['x1'],
    oversLimit: 20,
  );
  for (final e in batters.entries) {
    inn.batting[e.key] = BatFig()
      ..batted = true
      ..runs = e.value['runs']!
      ..balls = e.value['balls']!
      ..fours = e.value['fours'] ?? 0
      ..sixes = e.value['sixes'] ?? 0
      ..out = (e.value['out'] ?? 1) == 1;
  }
  m.innings.add(inn);
  return m;
}

void main() {
  group('buildStatCategories (shareable Top-5 stats)', () {
    test('ranks Top Run Scorers from real completed-match data', () {
      final s = _store();
      s.matches = [
        _completedMatch('m1', 't1', {
          'p1': {'runs': 45, 'balls': 30},
          'p2': {'runs': 72, 'balls': 50},
          'p3': {'runs': 12, 'balls': 10},
        }),
      ];
      final cats = buildStatCategories(s, 't1');
      final top = cats.firstWhere((c) => c.label == 'Top Run Scorers');
      expect(top.entries.length, 3);
      expect(top.entries[0].value, '72');
      expect(top.entries[1].value, '45');
      expect(top.entries[2].value, '12');
    });

    test('skips categories with no eligible players (no fake rows)', () {
      final s = _store();
      s.matches = [
        _completedMatch('m1', 't1', {
          'p1': {'runs': 20, 'balls': 15},
        }),
      ];
      final cats = buildStatCategories(s, 't1');
      final labels = cats.map((c) => c.label).toSet();
      // No bowling/fielding happened, so those categories must be absent.
      expect(labels.contains('Top Wicket Takers'), isFalse);
      expect(labels.contains('Most Catches'), isFalse);
      expect(labels.contains('Most Stumpings'), isFalse);
      // Batting categories with data are present.
      expect(labels.contains('Top Run Scorers'), isTrue);
    });

    test('caps each category at 5 entries', () {
      final s = _store();
      s.matches = [
        _completedMatch('m1', 't1', {
          for (var i = 1; i <= 8; i++)
            'p$i': {'runs': i * 10, 'balls': i * 8},
        }),
      ];
      final cats = buildStatCategories(s, 't1');
      for (final c in cats) {
        expect(c.entries.length, lessThanOrEqualTo(5),
            reason: '${c.label} exceeds 5');
      }
      final top = cats.firstWhere((c) => c.label == 'Top Run Scorers');
      expect(top.entries.length, 5);
      expect(top.entries[0].value, '80');
    });

    test('tournament filter scopes the categories', () {
      final s = _store();
      s.matches = [
        _completedMatch('m1', 't1', {
          'p1': {'runs': 50, 'balls': 40},
        }),
      ];
      expect(buildStatCategories(s, 'other'), isEmpty);
      expect(buildStatCategories(s, 't1'), isNotEmpty);
    });

    test('empty store yields no categories', () {
      final s = _store();
      expect(buildStatCategories(s, null), isEmpty);
    });
  });
}
