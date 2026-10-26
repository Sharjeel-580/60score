// Tests for the v1.4.5 qualification-chances computation (3 outcomes per
// remaining fixture, current-NRR tiebreak, Monte Carlo beyond 100k).
import 'package:cricket_scorer_app/qualification_analysis.dart';
import 'package:flutter_test/flutter_test.dart';

QualTeamInput _t(String id, int points, double nrr) =>
    QualTeamInput(teamId: id, points: points, nrr: nrr);

QualFixtureInput _f(String a, String b) =>
    QualFixtureInput(teamAId: a, teamBId: b);

TeamQualification _row(QualificationAnalysis a, String id) =>
    a.teams.firstWhere((t) => t.teamId == id);

void main() {
  group('qualification analysis', () {
    test('probabilities sum to 4 qualifiers; cutoff tie is NRR-sensitive',
        () {
      final a = analyzeQualification(
        teams: [
          _t('t0', 10, 2.0),
          _t('t1', 8, 1.0),
          _t('t2', 6, 0.5),
          _t('t3', 4, 0.0),
          _t('t4', 2, -0.5),
          _t('t5', 0, -1.0),
        ],
        fixtures: [_f('t4', 't5')],
      );
      expect(a.isApproximate, isFalse);
      expect(a.combinations, 3);
      // Every combination has exactly 4 qualifiers.
      final sum = a.teams.fold<double>(
        0,
        (s, t) => s + t.qualifyProbability,
      );
      expect(sum, closeTo(4.0, 1e-9));
      expect(_row(a, 't0').qualifyProbability, 1.0);
      expect(_row(a, 't4').qualifyProbability, 0.0);
      expect(_row(a, 't5').qualifyProbability, 0.0);
      // Only the A-win combination ties 4th/5th on 4 points (t3 vs t4).
      expect(_row(a, 't3').nrrSensitivity, closeTo(1 / 3, 1e-9));
      expect(_row(a, 't4').nrrSensitivity, closeTo(1 / 3, 1e-9));
      expect(_row(a, 't0').nrrSensitivity, 0.0);
      expect(_row(a, 't4').remainingMatches, 1);
      expect(_row(a, 't0').remainingMatches, 0);
    });

    test('NRR tiebreak by current NRR at the cutoff, no fixtures left', () {
      final a = analyzeQualification(
        teams: [
          _t('a', 6, 2.0),
          _t('b', 6, 1.0),
          _t('c', 4, 0.5),
          _t('d', 4, 0.0),
          _t('e', 4, -1.0),
        ],
        fixtures: const [],
      );
      expect(a.combinations, 1);
      expect(_row(a, 'a').qualifyProbability, 1.0);
      expect(_row(a, 'b').qualifyProbability, 1.0);
      expect(_row(a, 'c').qualifyProbability, 1.0);
      expect(_row(a, 'd').qualifyProbability, 1.0);
      expect(_row(a, 'e').qualifyProbability, 0.0);
      // 4th and 5th both on 4 points: the whole tie group is sensitive.
      expect(_row(a, 'c').nrrSensitivity, 1.0);
      expect(_row(a, 'd').nrrSensitivity, 1.0);
      expect(_row(a, 'e').nrrSensitivity, 1.0);
      expect(_row(a, 'a').nrrSensitivity, 0.0);
    });

    test('NR points + NRR tiebreak + min-wins with NR + best/worst', () {
      final teams = [
        _t('t1', 10, 3.0),
        _t('t2', 8, 2.0),
        _t('t3', 6, 0.5),
        _t('t4', 5, -2.0),
        _t('x', 4, 2.0),
        _t('t6', 0, -3.0),
      ];
      final fixtures = [_f('x', 't6')];
      final a = analyzeQualification(teams: teams, fixtures: fixtures);
      final x = _row(a, 'x');
      // Win -> 6 pts (3rd), NR -> 5 pts tied with t4, won on NRR (4th),
      // loss -> 4 pts (5th). So 2 of 3 outcomes qualify.
      expect(x.qualifyProbability, closeTo(2 / 3, 1e-9));
      expect(x.nrrSensitivity, closeTo(1 / 3, 1e-9));
      expect(x.bestRank, 3);
      expect(x.worstRank, 5);
      // 0 wins + 1 no-result qualifies; 0 + 0 does not. The (0,1) group
      // holds only the NR combination, so no other results are needed.
      expect(x.minWins, 0);
      expect(x.minNoResults, 1);
      expect(x.minNeedsOtherResults, isFalse);
      expect(x.canQualify, isTrue);
      // t6 cannot qualify even by winning its only remaining match.
      final t6 = _row(a, 't6');
      expect(t6.canQualify, isFalse);
      expect(t6.minWins, isNull);
    });

    test('best/worst across two remaining matches', () {
      final a = analyzeQualification(
        teams: [
          _t('o1', 10, 1.0),
          _t('o2', 8, 0.5),
          _t('o3', 8, 0.0),
          _t('o4', 4, 0.0),
          _t('o5', 4, -1.0),
          _t('y', 6, -5.0),
        ],
        fixtures: [_f('y', 'o4'), _f('y', 'o5')],
      );
      expect(a.combinations, 9);
      final y = _row(a, 'y');
      expect(y.remainingMatches, 2);
      // Win both -> 10 pts, tied with o1, loses the NRR tie -> 2nd.
      expect(y.bestRank, 2);
      // Lose both -> 6 pts, tied with o4/o5, loses both NRR ties -> 6th.
      expect(y.worstRank, 6);
    });

    test('what-if: fixing a match to win, loss or no-result', () {
      final teams = [
        _t('t1', 10, 3.0),
        _t('t2', 8, 2.0),
        _t('t3', 6, 0.5),
        _t('t4', 5, -2.0),
        _t('x', 4, 2.0),
        _t('t6', 0, -3.0),
      ];
      final fixtures = [_f('x', 't6')];
      final asWin = analyzeQualification(
        teams: teams,
        fixtures: fixtures,
        fixed: const {0: QualOutcome.teamAWin},
      );
      expect(_row(asWin, 'x').qualifyProbability, 1.0);
      final asNr = analyzeQualification(
        teams: teams,
        fixtures: fixtures,
        fixed: const {0: QualOutcome.noResult},
      );
      expect(_row(asNr, 'x').qualifyProbability, 1.0);
      final asLoss = analyzeQualification(
        teams: teams,
        fixtures: fixtures,
        fixed: const {0: QualOutcome.teamBWin},
      );
      expect(_row(asLoss, 'x').qualifyProbability, 0.0);
    });

    test('exact up to 100,000 combinations; Monte Carlo beyond', () {
      final teams = [
        for (var i = 0; i < 6; i++) _t('t$i', 0, (6 - i).toDouble()),
      ];
      final ten = analyzeQualification(
        teams: teams,
        fixtures: List.generate(10, (_) => _f('t0', 't1')),
      );
      expect(ten.isApproximate, isFalse);
      expect(ten.combinations, 59049); // 3^10
      final twelve = analyzeQualification(
        teams: teams,
        fixtures: List.generate(12, (_) => _f('t0', 't1')),
      );
      expect(twelve.isApproximate, isTrue);
      expect(twelve.combinations, kQualificationMonteCarloSamples);
      for (final row in twelve.teams) {
        expect(row.qualifyProbability, inInclusiveRange(0.0, 1.0));
        expect(row.nrrSensitivity, inInclusiveRange(0.0, 1.0));
      }
      // Monte Carlo noise on the 4-qualifier sum is tiny at 10k samples.
      final sum = twelve.teams.fold<double>(
        0,
        (s, t) => s + t.qualifyProbability,
      );
      expect(sum, closeTo(4.0, 0.2));
      // Fixed seed: repeated runs agree exactly.
      final again = analyzeQualification(
        teams: teams,
        fixtures: List.generate(12, (_) => _f('t0', 't1')),
      );
      for (var i = 0; i < 6; i++) {
        expect(
          again.teams[i].qualifyProbability,
          twelve.teams[i].qualifyProbability,
        );
      }
    });
  });
}
