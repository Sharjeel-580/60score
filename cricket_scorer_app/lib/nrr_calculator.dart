// NRR Possibilities Calculator (Feature 3, D batch).
//
// Pure Dart (no Flutter imports): given the CURRENT points-table rows
// (already computed by [computePointsTable] in scoring.dart) for a team
// and a rival it wants to overtake, work out what the team must do in
// ONE hypothetical next match to finish ahead of the rival:
//
//  * Defend: the team bats first and posts a score — how few runs may
//    the opponent be allowed so the team's new NRR beats the rival's?
//  * Chase: the team chases a target — by which ball, at the latest,
//    must the chase be completed so the new NRR beats the rival's?
//
// This is a MANUAL calculator: it reads rows and returns a verdict.
// It never touches fixtures, matches or the stored table.
//
// Semantics (kept identical to computePointsTable / _adjustedBalls):
//  * A win is worth 2 points. The RIVAL does not play this match, so
//    the rival's row is unchanged.
//  * Points gate, checked first:
//      team.points + 2 <  rival.points -> impossible on points alone.
//      team.points + 2 >  rival.points -> ANY win puts the team ahead
//                                          (NRR never consulted).
//      team.points + 2 == rival.points -> the win only counts if the
//                                          team's NEW NRR is STRICTLY
//                                          greater than the rival's
//                                          current NRR.
//  * "Strictly greater" is tested with a tiny epsilon: the new NRR
//    must exceed the rival's NRR by more than [kNrrEpsilon] (1e-9),
//    so an exact tie on NRR never counts as overtaking — mirroring
//    the table sort, where equal points + equal NRR does not put a
//    team ahead.
//  * ICC all-out rule (same as _adjustedBalls): a side bowled out
//    before its quota is deemed to have faced the FULL quota. A side
//    that loses without being bowled out has used its full quota by
//    definition, so in the defend case the opponent's innings always
//    accounts for the full quota of balls against the team.

import 'scoring.dart';

/// Tolerance for the strict NRR comparison (see file header).
const double kNrrEpsilon = 1e-9;

/// Outcome of one calculator scenario.
class NrrScenarioResult {
  /// True when some legal win in this scenario puts the team ahead
  /// of the rival (on points, or on points + NRR).
  final bool possible;

  /// Plain-words explanation of the outcome (points block, NRR block,
  /// or why the shown margin is the answer).
  final String verdict;

  /// Defend only: the most runs the opponent may score while the team
  /// still overtakes the rival. Null for chase / impossible results.
  final int? maxOpponentRuns;

  /// Defend only: the smallest winning margin (teamScore − opponent
  /// runs) that overtakes the rival. Null for chase / impossible.
  final int? minMargin;

  /// Chase only: the latest legal ball by which the chase must be
  /// finished (legal balls bowled in the chase). Null otherwise.
  final int? latestChaseBalls;

  /// The team's NRR after the boundary case (at [maxOpponentRuns] /
  /// [latestChaseBalls]); for impossible-by-NRR results, the best NRR
  /// the team could reach in this scenario. Null when no NRR was
  /// computed (points verdicts / invalid input).
  final double? resultingNrr;

  const NrrScenarioResult({
    required this.possible,
    required this.verdict,
    this.maxOpponentRuns,
    this.minMargin,
    this.latestChaseBalls,
    this.resultingNrr,
  });
}

/// Deep-copy a [PointsRow] so hypothetical innings can be added
/// without mutating the table the caller passed in.
PointsRow _cloneRow(PointsRow r) {
  final c = PointsRow(r.teamId);
  c.played = r.played;
  c.won = r.won;
  c.lost = r.lost;
  c.tied = r.tied;
  c.noResult = r.noResult;
  c.points = r.points;
  c.runsFor = r.runsFor;
  c.ballsFor = r.ballsFor;
  c.runsAgainst = r.runsAgainst;
  c.ballsAgainst = r.ballsAgainst;
  c.ballsPerOver = r.ballsPerOver;
  return c;
}

/// Does [newTeam] (after its hypothetical win) finish ahead of the
/// unchanged [rival]? Points first; on level points the new NRR must
/// be strictly greater than the rival's (see [kNrrEpsilon]).
bool _overtakes(PointsRow newTeam, PointsRow rival) {
  if (newTeam.points != rival.points) return newTeam.points > rival.points;
  return newTeam.nrr > rival.nrr + kNrrEpsilon;
}

/// Shared points gate. Returns a finished [NrrScenarioResult] when
/// points alone decide the scenario, or null when the win leaves the
/// teams level on points and NRR must decide. [anyWinResult] builds
/// the "any win is enough" answer for the caller's scenario.
NrrScenarioResult? _pointsGate(
  PointsRow team,
  PointsRow rival,
  NrrScenarioResult Function() anyWinResult,
) {
  if (team.points + 2 < rival.points) {
    return const NrrScenarioResult(
      possible: false,
      verdict:
          'Points se hi nahi hoga: ek jeet ke baad bhi team ke points '
          'rival se kam rahenge.',
    );
  }
  if (team.points + 2 > rival.points) return anyWinResult();
  return null;
}

/// DEFEND case: [team] bats first and scores [teamScore].
///
/// [oversQuotaBalls] is the innings quota in legal balls
/// (oversLimit × ballsPerOver). [ballsFacedTeam] is how many legal
/// balls the team actually faced; when omitted the team is assumed
/// to have used its full quota. When [teamAllOut] is true the ICC
/// rule applies and the team's innings counts as the full quota
/// whatever [ballsFacedTeam] says — exactly like _adjustedBalls.
///
/// The opponent (a third side, or the rival themselves — the rival's
/// TABLE row is unchanged either way in this calculator) must be kept
/// below [teamScore] for a win, and a losing innings always accounts
/// for the full quota of balls against the team (all out = deemed
/// full quota; not all out = full quota actually batted).
NrrScenarioResult runsMarginNeeded({
  required PointsRow team,
  required PointsRow rival,
  required int teamScore,
  required int oversQuotaBalls,
  required int ballsPerOver,
  int? ballsFacedTeam,
  bool teamAllOut = false,
}) {
  if (teamScore <= 0 || oversQuotaBalls <= 0 || ballsPerOver <= 0) {
    return const NrrScenarioResult(
      possible: false,
      verdict: 'Score aur overs quota durust darj karen.',
    );
  }
  final teamBalls = teamAllOut
      ? oversQuotaBalls
      : (ballsFacedTeam ?? oversQuotaBalls);

  PointsRow afterWin(int oppRuns) {
    final t = _cloneRow(team);
    t.ballsPerOver = ballsPerOver;
    t.played++;
    t.won++;
    t.points += 2;
    t.runsFor += teamScore;
    t.ballsFor += teamBalls;
    t.runsAgainst += oppRuns;
    t.ballsAgainst += oversQuotaBalls; // losing innings = full quota
    return t;
  }

  final gated = _pointsGate(team, rival, () {
    final t = afterWin(teamScore - 1);
    return NrrScenarioResult(
      possible: true,
      verdict:
          'Koi bhi jeet kafi hai: points par hi team rival se aage '
          'nikal jayegi, NRR ki zaroorat nahi.',
      maxOpponentRuns: teamScore - 1,
      minMargin: 1,
      resultingNrr: t.nrr,
    );
  });
  if (gated != null) return gated;

  // Level on points after the win: NRR decides. The new NRR falls as
  // the opponent scores more, so scanning down from the biggest
  // losing total finds the maximum the opponent may be allowed.
  for (var oppRuns = teamScore - 1; oppRuns >= 0; oppRuns--) {
    final t = afterWin(oppRuns);
    if (_overtakes(t, rival)) {
      return NrrScenarioResult(
        possible: true,
        verdict:
            'NRR par faisla hoga: opponent ko itne runs tak rokna '
            'hoga ke team ka NRR rival se oopar rahe.',
        maxOpponentRuns: oppRuns,
        minMargin: teamScore - oppRuns,
        resultingNrr: t.nrr,
      );
    }
  }
  final best = afterWin(0);
  return NrrScenarioResult(
    possible: false,
    verdict:
        'Is score par mumkin nahi: opponent ko 0 par out karne par '
        'bhi team ka NRR rival se oopar nahi jata.',
    resultingNrr: best.nrr,
  );
}

/// CHASE case: [team] chases [target] runs (target = opponent's
/// score + 1) and wins by reaching it.
///
/// The opponent's first innings is accounted from [oppScore] and
/// [oppBallsFaced]; when [oppAllOut] is true the ICC rule deems the
/// opponent to have faced the full [oversQuotaBalls]. The team's own
/// chase counts exactly [target] runs off the balls used (a side
/// that is bowled out has LOST, so all-out chases are not considered).
NrrScenarioResult chaseLatestBalls({
  required PointsRow team,
  required PointsRow rival,
  required int target,
  required int oversQuotaBalls,
  required int ballsPerOver,
  required int oppScore,
  required int oppBallsFaced,
  bool oppAllOut = false,
}) {
  if (target <= 0 || oversQuotaBalls <= 0 || ballsPerOver <= 0) {
    return const NrrScenarioResult(
      possible: false,
      verdict: 'Target aur overs quota durust darj karen.',
    );
  }
  final oppBalls = oppAllOut ? oversQuotaBalls : oppBallsFaced;

  PointsRow afterWin(int chaseBalls) {
    final t = _cloneRow(team);
    t.ballsPerOver = ballsPerOver;
    t.played++;
    t.won++;
    t.points += 2;
    t.runsAgainst += oppScore;
    t.ballsAgainst += oppBalls;
    t.runsFor += target;
    t.ballsFor += chaseBalls;
    return t;
  }

  final gated = _pointsGate(team, rival, () {
    final t = afterWin(oversQuotaBalls);
    return NrrScenarioResult(
      possible: true,
      verdict:
          'Koi bhi jeet kafi hai: points par hi team rival se aage '
          'nikal jayegi, chase kitni bhi dair mein mukammal ho.',
      latestChaseBalls: oversQuotaBalls,
      resultingNrr: t.nrr,
    );
  });
  if (gated != null) return gated;

  // Level on points after the win: NRR decides. The new NRR falls as
  // the chase takes longer, so scanning down from the full quota
  // finds the LATEST ball that still overtakes the rival.
  for (var balls = oversQuotaBalls; balls >= 1; balls--) {
    final t = afterWin(balls);
    if (_overtakes(t, rival)) {
      return NrrScenarioResult(
        possible: true,
        verdict:
            'NRR par faisla hoga: chase is ball tak mukammal karna '
            'hoga, warna team ka NRR rival se neeche reh jayega.',
        latestChaseBalls: balls,
        resultingNrr: t.nrr,
      );
    }
  }
  final best = afterWin(1);
  return NrrScenarioResult(
    possible: false,
    verdict:
        'Is target par mumkin nahi: pehli ball par chase mukammal '
        'karne par bhi team ka NRR rival se oopar nahi jata.',
    resultingNrr: best.nrr,
  );
}

/// Parse cricket overs text ("8", "8.0", "7.3") into legal balls.
/// Returns null for malformed input or a ball digit that is not
/// legal for [ballsPerOver] (e.g. "7.6" in a 6-ball over).
int? ballsFromOversText(String text, int ballsPerOver) {
  final s = text.trim();
  if (s.isEmpty || ballsPerOver <= 0) return null;
  final parts = s.split('.');
  if (parts.length > 2) return null;
  final overs = int.tryParse(parts[0]);
  if (overs == null || overs < 0) return null;
  var balls = 0;
  if (parts.length == 2) {
    if (parts[1].length != 1) return null;
    final b = int.tryParse(parts[1]);
    if (b == null || b < 0 || b >= ballsPerOver) return null;
    balls = b;
  }
  return overs * ballsPerOver + balls;
}
