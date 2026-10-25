// Qualification chances analysis (v1.4.5) — pure computation, no Flutter,
// no store writes. The UI (QualificationChancesScreen) only reads the
// current league points table + remaining league fixtures and renders
// what this returns.
//
// Model (user-confirmed, 2026-10-26):
// - Every remaining league fixture has 3 outcomes: team A win (2-0
//   points), team B win (0-2), no-result (1-1 points, zero NRR effect).
//   A tied match is also 1-1 on points, so the no-result outcome covers
//   the 1-1 points case; ties are NOT enumerated separately.
// - Points: Win = 2, Tie = 1 each, No result = 1 each — the same values
//   the points-table engine uses (scoring.dart).
// - Each combination's final table is ranked by points desc, then the
//   teams' CURRENT NRR desc. Future match margins are unknown and cannot
//   be enumerated, so current NRR is the tiebreaker by definition — the
//   UI must label this honestly.
// - Exact enumeration while total combinations <= 100,000; beyond that,
//   seeded Monte Carlo (10,000 samples, fixed seed so results are
//   reproducible) labelled "approx". The UI never blocks on this.
import 'dart:math';

/// One remaining fixture's outcome, from the points view.
enum QualOutcome { teamAWin, teamBWin, noResult }

/// A team's current standing feeding the analysis.
class QualTeamInput {
  final String teamId;
  final int points;
  final double nrr;
  const QualTeamInput({
    required this.teamId,
    required this.points,
    required this.nrr,
  });
}

/// A remaining league fixture (both teams known; the caller filters).
class QualFixtureInput {
  final String teamAId;
  final String teamBId;
  const QualFixtureInput({required this.teamAId, required this.teamBId});
}

/// Per-team result of one analysis run.
class TeamQualification {
  final String teamId;
  final int currentPoints;
  final double currentNrr;
  final int remainingMatches;

  /// Share of combinations where the team finishes top 4 after ranking
  /// by points desc, then current NRR desc. 0..1.
  final double qualifyProbability;

  /// Share of combinations where the team was tied on points at the
  /// 4th-place cutoff — i.e. its qualification in that combination was
  /// decided by NRR, not by points alone. 0..1.
  final double nrrSensitivity;

  /// Best rank over combinations where the team wins all its remaining
  /// matches (1 = first). Worst rank likewise for losing them all.
  /// Under a what-if conditioning, "all" means all UNFIXED remaining
  /// matches; fixed ones stay as fixed.
  final int bestRank;
  final int worstRank;

  /// Fewest wins (then fewest no-results) from the team's remaining
  /// matches that still allow qualification in some combination.
  /// Null when the team cannot qualify even by winning all remaining.
  final int? minWins;
  final int? minNoResults;

  /// At the minimum above, true when the team qualifies only in SOME
  /// combinations with that (wins, no-results) record — other results
  /// matter. False when it qualifies in ALL of them.
  final bool minNeedsOtherResults;

  bool get canQualify => minWins != null;

  const TeamQualification({
    required this.teamId,
    required this.currentPoints,
    required this.currentNrr,
    required this.remainingMatches,
    required this.qualifyProbability,
    required this.nrrSensitivity,
    required this.bestRank,
    required this.worstRank,
    required this.minWins,
    required this.minNoResults,
    required this.minNeedsOtherResults,
  });
}

/// One analysis run over a fixture list.
class QualificationAnalysis {
  /// Same order as the inputs.
  final List<TeamQualification> teams;
  final List<QualFixtureInput> remainingFixtures;

  /// True when the numbers come from Monte Carlo sampling instead of
  /// exact enumeration.
  final bool isApproximate;

  /// Exact combination count, or the sample count when approximate.
  final int combinations;

  const QualificationAnalysis({
    required this.teams,
    required this.remainingFixtures,
    required this.isApproximate,
    required this.combinations,
  });
}

/// Exact enumeration while total combinations stay at or under this.
const int kQualificationExactLimit = 100000;

/// Monte Carlo sample count once the exact space exceeds the limit.
const int kQualificationMonteCarloSamples = 10000;

/// Fixed seed so Monte Carlo results are reproducible run to run.
const int kQualificationMonteCarloSeed = 20261026;

/// Runs the qualification analysis.
///
/// [teams] is the current league table (points + current NRR per team).
/// [fixtures] is the remaining league fixtures in a stable order; [fixed]
/// optionally pins some of them (keys are indices into [fixtures]) for
/// what-if runs — pinned fixtures do not vary.
QualificationAnalysis analyzeQualification({
  required List<QualTeamInput> teams,
  required List<QualFixtureInput> fixtures,
  Map<int, QualOutcome> fixed = const {},
}) {
  final n = teams.length;
  final indexOf = <String, int>{};
  for (var i = 0; i < n; i++) {
    indexOf[teams[i].teamId] = i;
  }
  // Remaining matches per team (fixed + unfixed).
  final remainingPerTeam = List<int>.filled(n, 0);
  for (final f in fixtures) {
    final a = indexOf[f.teamAId];
    final b = indexOf[f.teamBId];
    if (a != null) remainingPerTeam[a]++;
    if (b != null) remainingPerTeam[b]++;
  }

  final unfixed = <int>[];
  for (var j = 0; j < fixtures.length; j++) {
    if (!fixed.containsKey(j)) unfixed.add(j);
  }

  // Total exact combinations, capped: stop as soon as we exceed the limit.
  var exactTotal = 1;
  for (var k = 0; k < unfixed.length; k++) {
    exactTotal *= 3;
    if (exactTotal > kQualificationExactLimit) break;
  }
  final approximate = exactTotal > kQualificationExactLimit;
  final total = approximate ? kQualificationMonteCarloSamples : exactTotal;

  final qualCount = List<int>.filled(n, 0);
  final sensCount = List<int>.filled(n, 0);
  final bestRank = List<int>.filled(n, 1 << 30);
  final worstRank = List<int>.filled(n, 0);
  // Per team: (wins,noResults) record -> [seen, qualifiedSeen, allQualify].
  final groups = List.generate(
    n,
    (_) => <String, List<bool>>{},
  );

  final rand = Random(kQualificationMonteCarloSeed);
  // One assignment buffer, reused: outcome per fixture index.
  final assignment = List<QualOutcome>.filled(fixtures.length, QualOutcome.noResult);
  for (final entry in fixed.entries) {
    assignment[entry.key] = entry.value;
  }

  for (var combo = 0; combo < total; combo++) {
    if (approximate) {
      for (final j in unfixed) {
        assignment[j] = QualOutcome.values[rand.nextInt(3)];
      }
    } else {
      // Base-3 counting over the unfixed fixtures.
      var code = combo;
      for (final j in unfixed) {
        assignment[j] = QualOutcome.values[code % 3];
        code ~/= 3;
      }
    }

    final points = [for (final t in teams) t.points];
    final wins = List<int>.filled(n, 0);
    final nrs = List<int>.filled(n, 0);
    for (var j = 0; j < fixtures.length; j++) {
      final a = indexOf[fixtures[j].teamAId];
      final b = indexOf[fixtures[j].teamBId];
      if (a == null || b == null) continue;
      switch (assignment[j]) {
        case QualOutcome.teamAWin:
          points[a] += 2;
          wins[a]++;
        case QualOutcome.teamBWin:
          points[b] += 2;
          wins[b]++;
        case QualOutcome.noResult:
          points[a] += 1;
          points[b] += 1;
          nrs[a]++;
          nrs[b]++;
      }
    }

    // Rank: points desc, then current NRR desc, then input order
    // (stable fallback for an exact points+NRR tie).
    final order = List<int>.generate(n, (i) => i);
    order.sort((a, b) {
      final pc = points[b].compareTo(points[a]);
      if (pc != 0) return pc;
      final nc = teams[b].nrr.compareTo(teams[a].nrr);
      if (nc != 0) return nc;
      return a.compareTo(b);
    });
    final rankOf = List<int>.filled(n, 0);
    for (var k = 0; k < n; k++) {
      rankOf[order[k]] = k + 1;
    }
    // Points tie straddling the 4th-place cutoff: the tie group spans
    // the cut exactly when the 4th- and 5th-ranked points are equal.
    int? cutoffPoints;
    if (n >= 5) {
      final p4 = points[order[3]];
      final p5 = points[order[4]];
      if (p4 == p5) cutoffPoints = p4;
    }

    for (var i = 0; i < n; i++) {
      final qualifies = rankOf[i] <= 4;
      if (qualifies) qualCount[i]++;
      if (cutoffPoints != null && points[i] == cutoffPoints) {
        sensCount[i]++;
      }
      // Best case: the team wins all its UNFIXED remaining matches.
      var bestCase = true;
      var worstCase = true;
      for (var j = 0; j < fixtures.length; j++) {
        if (fixed.containsKey(j)) continue;
        final a = indexOf[fixtures[j].teamAId];
        final b = indexOf[fixtures[j].teamBId];
        if (a == i) {
          if (assignment[j] != QualOutcome.teamAWin) bestCase = false;
          if (assignment[j] != QualOutcome.teamBWin) worstCase = false;
        } else if (b == i) {
          if (assignment[j] != QualOutcome.teamBWin) bestCase = false;
          if (assignment[j] != QualOutcome.teamAWin) worstCase = false;
        }
      }
      if (bestCase && rankOf[i] < bestRank[i]) bestRank[i] = rankOf[i];
      if (worstCase && rankOf[i] > worstRank[i]) worstRank[i] = rankOf[i];
      // Minimal-requirement grouping by this team's (wins, no-results).
      final key = '${wins[i]},${nrs[i]}';
      final g = groups[i].putIfAbsent(key, () => [false, false, true]);
      g[0] = true;
      if (qualifies) g[1] = true;
      if (!qualifies) g[2] = false;
    }
  }

  final out = <TeamQualification>[];
  for (var i = 0; i < n; i++) {
    int? minWins;
    int? minNrs;
    var minNeedsOthers = false;
    final rt = remainingPerTeam[i];
    outer:
    for (var w = 0; w <= rt; w++) {
      for (var nr = 0; nr <= rt - w; nr++) {
        final g = groups[i]['$w,$nr'];
        if (g != null && g[1]) {
          minWins = w;
          minNrs = nr;
          minNeedsOthers = !g[2];
          break outer;
        }
      }
    }
    out.add(
      TeamQualification(
        teamId: teams[i].teamId,
        currentPoints: teams[i].points,
        currentNrr: teams[i].nrr,
        remainingMatches: rt,
        qualifyProbability: total == 0 ? 0 : qualCount[i] / total,
        nrrSensitivity: total == 0 ? 0 : sensCount[i] / total,
        bestRank: bestRank[i] == (1 << 30) ? 0 : bestRank[i],
        worstRank: worstRank[i],
        minWins: minWins,
        minNoResults: minNrs,
        minNeedsOtherResults: minNeedsOthers,
      ),
    );
  }

  return QualificationAnalysis(
    teams: out,
    remainingFixtures: fixtures,
    isApproximate: approximate,
    combinations: total,
  );
}
