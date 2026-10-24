// Duckworth–Lewis revised targets — Standard Edition (pure Dart).
//
// Edition & source
// ----------------
// This module embeds the resource-percentage table of the
// Duckworth–Lewis **Standard Edition** — the published table for use
// when the Professional Edition (computer program) is not available,
// as reproduced in the D/L booklet "The Duckworth–Lewis method of
// re-calculating the target score in an interrupted match — Standard
// Edition" (table of resource percentages remaining, over by over)
// and summarised (abbreviated rows) on Wikipedia / in the ICC Playing
// Handbook extract. Values below are that published over-by-over
// table: resource % remaining for every whole over remaining from
// 50 down to 0, by wickets lost 0–9.
//
//   G50 = 245
//
// G50 is the Standard Edition constant: the average score expected
// in a 50-over innings. It is used only in the branch where Team 2
// has MORE resources than Team 1 had (R2 > R1) — typically because
// Team 1's innings was terminated early — to uplift the target.
//
// Note on editions: an older (1998) abbreviated extract of the
// Standard Edition quotes 68.7% for 25 overs / 0 wickets. The later
// published over-by-over Standard Edition table embedded here —
// the one whose abbreviated rows (50ov: 100.0/85.1/62.7/34.9/11.9
// for 0/2/4/6/8 wickets lost) match the current Wikipedia / handbook
// summary — quotes **66.5%** for 25 overs / 0 wickets, 56.6% for
// 20 overs / 0 wickets and 32.1% for 10 overs / 0 wickets. Targets
// computed from the two extracts can differ by a few runs; this
// module is internally consistent with the table below.
//
// Interpolation
// -------------
// The published table is per whole over. For in-between values
// (e.g. balls remaining expressed as fractional overs, 25 overs
// 3 balls = 25.5 overs) this module interpolates **linearly**
// between the two neighbouring whole-over rows, for the given
// wickets-lost column. Wickets are never interpolated (they are a
// count). Inputs are clamped: overs to 0–50, wickets to 0–9; a side
// that has lost all 10 wickets has 0% resources remaining, as does
// any side with 0 overs remaining.
//
// Typical UI flows
// ----------------
// * Team 2 starts shortened: R2 = [dlResourcePct] at the overs
//   Team 2 will receive, 0 wickets; R1 = 100 if Team 1 had a full
//   50 overs (or [resourcesAtInningsStart] of Team 1's allocation).
// * Team 1 terminated early: R1 = [resourcesForTerminatedInnings].
// * Interruption during Team 2's innings: R2 = start resource
//   minus [resourceLost] for the interruption (sum over multiple
//   interruptions) — see [resourcesAfterInterruptions].
// Then call [dlsTarget] with Team 1's score and R1 / R2.

/// Standard Edition G50 constant (average 50-over score).
const double kDlG50 = 245.0;

/// Resource % remaining by overs remaining (index = whole overs,
/// 0–50) × wickets lost (inner index 0–9). Standard Edition
/// published over-by-over table — see file header.
const List<List<double>> _resourceTable = [
  // overs 0
  [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
  // overs 1
  [3.6, 3.6, 3.6, 3.6, 3.6, 3.5, 3.5, 3.4, 3.2, 2.5],
  // overs 2
  [7.2, 7.1, 7.1, 7.0, 7.0, 6.8, 6.6, 6.2, 5.5, 3.7],
  // overs 3
  [10.6, 10.5, 10.4, 10.3, 10.2, 9.9, 9.5, 8.7, 7.2, 4.2],
  // overs 4
  [13.9, 13.8, 13.7, 13.5, 13.2, 12.7, 12.0, 10.7, 8.4, 4.5],
  // overs 5
  [17.2, 17.0, 16.8, 16.5, 16.1, 15.4, 14.3, 12.5, 9.4, 4.6],
  // overs 6
  [20.3, 20.1, 19.8, 19.4, 18.8, 17.8, 16.4, 13.9, 10.1, 4.6],
  // overs 7
  [23.4, 23.1, 22.7, 22.2, 21.4, 20.1, 18.2, 15.2, 10.5, 4.7],
  // overs 8
  [26.4, 26.0, 25.5, 24.8, 23.8, 22.3, 19.9, 16.2, 10.9, 4.7],
  // overs 9
  [29.3, 28.9, 28.2, 27.4, 26.1, 24.2, 21.4, 17.1, 11.2, 4.7],
  // overs 10
  [32.1, 31.6, 30.8, 29.8, 28.3, 26.1, 22.8, 17.9, 11.4, 4.7],
  // overs 11
  [34.9, 34.2, 33.4, 32.1, 30.4, 27.8, 24.0, 18.5, 11.5, 4.7],
  // overs 12
  [37.6, 36.8, 35.8, 34.3, 32.3, 29.4, 25.1, 19.0, 11.6, 4.7],
  // overs 13
  [40.2, 39.3, 38.1, 36.5, 34.2, 30.8, 26.1, 19.5, 11.7, 4.7],
  // overs 14
  [42.7, 41.7, 40.4, 38.5, 35.9, 32.2, 27.0, 19.9, 11.8, 4.7],
  // overs 15
  [45.2, 44.1, 42.6, 40.5, 37.6, 33.5, 27.8, 20.2, 11.8, 4.7],
  // overs 16
  [47.6, 46.3, 44.7, 42.3, 39.1, 34.7, 28.5, 20.5, 11.8, 4.7],
  // overs 17
  [49.9, 48.5, 46.7, 44.1, 40.6, 35.8, 29.2, 20.7, 11.9, 4.7],
  // overs 18
  [52.2, 50.7, 48.6, 45.9, 42.0, 36.8, 29.8, 20.9, 11.9, 4.7],
  // overs 19
  [54.4, 52.8, 50.5, 47.5, 43.4, 37.7, 30.3, 21.1, 11.9, 4.7],
  // overs 20
  [56.6, 54.8, 52.4, 49.1, 44.6, 38.6, 30.8, 21.2, 11.9, 4.7],
  // overs 21
  [58.7, 56.7, 54.1, 50.6, 45.8, 39.4, 31.2, 21.3, 11.9, 4.7],
  // overs 22
  [60.7, 58.6, 55.8, 52.0, 47.0, 40.2, 31.6, 21.4, 11.9, 4.7],
  // overs 23
  [62.7, 60.4, 57.4, 53.4, 48.0, 40.9, 32.0, 21.5, 11.9, 4.7],
  // overs 24
  [64.6, 62.2, 59.0, 54.7, 49.0, 41.6, 32.3, 21.6, 11.9, 4.7],
  // overs 25
  [66.5, 63.9, 60.5, 56.0, 50.0, 42.2, 32.6, 21.6, 11.9, 4.7],
  // overs 26
  [68.3, 65.6, 62.0, 57.2, 50.9, 42.8, 32.8, 21.7, 11.9, 4.7],
  // overs 27
  [70.1, 67.2, 63.4, 58.4, 51.8, 43.3, 33.0, 21.7, 11.9, 4.7],
  // overs 28
  [71.8, 68.8, 64.8, 59.5, 52.6, 43.8, 33.2, 21.8, 11.9, 4.7],
  // overs 29
  [73.5, 70.3, 66.1, 60.5, 53.4, 44.2, 33.4, 21.8, 11.9, 4.7],
  // overs 30
  [75.1, 71.8, 67.3, 61.6, 54.1, 44.7, 33.6, 21.8, 11.9, 4.7],
  // overs 31
  [76.7, 73.2, 68.6, 62.5, 54.8, 45.1, 33.7, 21.9, 11.9, 4.7],
  // overs 32
  [78.3, 74.6, 69.7, 63.5, 55.4, 45.4, 33.9, 21.9, 11.9, 4.7],
  // overs 33
  [79.8, 75.9, 70.9, 64.4, 56.0, 45.8, 34.0, 21.9, 11.9, 4.7],
  // overs 34
  [81.3, 77.2, 72.0, 65.2, 56.6, 46.1, 34.1, 21.9, 11.9, 4.7],
  // overs 35
  [82.7, 78.5, 73.0, 66.0, 57.2, 46.4, 34.2, 21.9, 11.9, 4.7],
  // overs 36
  [84.1, 79.7, 74.1, 66.8, 57.7, 46.6, 34.3, 21.9, 11.9, 4.7],
  // overs 37
  [85.4, 80.9, 75.0, 67.6, 58.2, 46.9, 34.4, 21.9, 11.9, 4.7],
  // overs 38
  [86.7, 82.0, 76.0, 68.3, 58.7, 47.1, 34.5, 21.9, 11.9, 4.7],
  // overs 39
  [88.0, 83.1, 76.9, 69.0, 59.1, 47.4, 34.5, 22.0, 11.9, 4.7],
  // overs 40
  [89.3, 84.2, 77.8, 69.6, 59.5, 47.6, 34.6, 22.0, 11.9, 4.7],
  // overs 41
  [90.5, 85.3, 78.7, 70.3, 59.9, 47.8, 34.6, 22.0, 11.9, 4.7],
  // overs 42
  [91.7, 86.3, 79.5, 70.9, 60.3, 47.9, 34.7, 22.0, 11.9, 4.7],
  // overs 43
  [92.8, 87.3, 80.3, 71.4, 60.7, 48.1, 34.7, 22.0, 11.9, 4.7],
  // overs 44
  [93.9, 88.2, 81.0, 72.0, 61.0, 48.3, 34.8, 22.0, 11.9, 4.7],
  // overs 45
  [95.0, 89.1, 81.8, 72.5, 61.3, 48.4, 34.8, 22.0, 11.9, 4.7],
  // overs 46
  [96.1, 90.0, 82.5, 73.0, 61.6, 48.5, 34.8, 22.0, 11.9, 4.7],
  // overs 47
  [97.1, 90.9, 83.2, 73.5, 61.9, 48.6, 34.9, 22.0, 11.9, 4.7],
  // overs 48
  [98.1, 91.7, 83.8, 74.0, 62.2, 48.8, 34.9, 22.0, 11.9, 4.7],
  // overs 49
  [99.1, 92.6, 84.5, 74.4, 62.5, 48.9, 34.9, 22.0, 11.9, 4.7],
  // overs 50
  [100.0, 93.4, 85.1, 74.9, 62.7, 49.0, 34.9, 22.0, 11.9, 4.7],
];

/// Resource percentage remaining for a side with [oversRemaining]
/// overs left (fractional overs allowed, e.g. 25.5 for 25 overs
/// 3 balls with 6 balls per over — the caller converts balls to a
/// fraction) and [wicketsLost] wickets down (0–9).
///
/// Clamps inputs: overs below 0 read as 0 (→ 0%), overs above 50
/// read as 50, wickets below 0 read as 0, and 10 wickets lost
/// (all out) reads as 0% at any overs value.
double dlResourcePct({
  required double oversRemaining,
  required int wicketsLost,
}) {
  if (wicketsLost >= 10) return 0.0;
  final w = wicketsLost < 0 ? 0 : wicketsLost;
  if (oversRemaining <= 0) return 0.0;
  final overs = oversRemaining > 50 ? 50.0 : oversRemaining;
  final lo = overs.floor();
  final hi = overs.ceil();
  if (lo == hi) return _resourceTable[lo][w];
  final frac = overs - lo;
  final a = _resourceTable[lo][w];
  final b = _resourceTable[hi][w];
  return a + (b - a) * frac;
}

/// Resource available to an innings at its start: the resource %
/// for [oversAtStart] overs with no wicket lost.
///
/// (Named `resourcesUsedAtInningsStart` in the original brief —
/// the value is the resource the innings *starts with*, i.e. the
/// total resource available to it before any interruption.)
double resourcesUsedAtInningsStart(double oversAtStart) =>
    dlResourcePct(oversRemaining: oversAtStart, wicketsLost: 0);

/// Clearer alias for [resourcesUsedAtInningsStart].
double resourcesAtInningsStart(double oversAtStart) =>
    resourcesUsedAtInningsStart(oversAtStart);

/// Resource lost to one interruption: play stops with
/// [oversAtInterruption] overs remaining and [wickets] wickets
/// down, and resumes with only [oversAtResumption] overs remaining
/// (same wickets down). Lost = resource at stop − resource at
/// resumption. Returns 0 when the "resumption" value is not
/// smaller (no overs were actually lost).
double resourceLost({
  required double oversAtInterruption,
  required int wickets,
  required double oversAtResumption,
}) {
  final atStop = dlResourcePct(
    oversRemaining: oversAtInterruption,
    wicketsLost: wickets,
  );
  final atResume = dlResourcePct(
    oversRemaining: oversAtResumption,
    wicketsLost: wickets,
  );
  final lost = atStop - atResume;
  return lost < 0 ? 0.0 : lost;
}

/// Total resource (R) of an innings that was terminated early —
/// e.g. Team 1's innings is cut short by rain and never resumes:
/// R = resource at the innings start − resource that was still
/// remaining when it was terminated.
double resourcesForTerminatedInnings({
  required double oversAtStart,
  required double oversRemainingAtTermination,
  required int wicketsLostAtTermination,
}) {
  final start = resourcesAtInningsStart(oversAtStart);
  final remaining = dlResourcePct(
    oversRemaining: oversRemainingAtTermination,
    wicketsLost: wicketsLostAtTermination,
  );
  final r = start - remaining;
  return r < 0 ? 0.0 : r;
}

/// Total resource (R) of an innings after one or more
/// interruptions: start resource minus the resource lost to each
/// interruption. Each entry of [interruptions] is a record with
/// the overs remaining when play stopped, the wickets down at
/// that point, and the overs remaining when play resumed.
double resourcesAfterInterruptions({
  required double oversAtStart,
  required List<
      ({double oversAtInterruption, int wickets, double oversAtResumption})>
      interruptions,
}) {
  var r = resourcesAtInningsStart(oversAtStart);
  for (final i in interruptions) {
    r -= resourceLost(
      oversAtInterruption: i.oversAtInterruption,
      wickets: i.wickets,
      oversAtResumption: i.oversAtResumption,
    );
  }
  return r < 0 ? 0.0 : r;
}

/// Result of a D/L Standard Edition target calculation.
class DlsResult {
  /// Resource % Team 1 actually had available (R1).
  final double team1ResourcePct;

  /// Resource % available to Team 2 (R2).
  final double team2ResourcePct;

  /// Team 2's par score: the score that ties the match. Team 2
  /// wins by scoring more than par, i.e. at least [target].
  final double parScore;

  /// Score Team 2 needs to win: floor(par) + 1.
  final int target;

  const DlsResult({
    required this.team1ResourcePct,
    required this.team2ResourcePct,
    required this.parScore,
    required this.target,
  });

  @override
  String toString() =>
      'DlsResult(R1: $team1ResourcePct, R2: $team2ResourcePct, '
      'par: $parScore, target: $target)';
}

/// D/L Standard Edition target for Team 2.
///
/// * R2 < R1: par = team1Score × R2 / R1.
/// * R2 == R1: par = team1Score.
/// * R2 > R1 (Team 2 has more resources — e.g. Team 1's innings
///   was terminated early, so R1 is the reduced resource Team 1
///   actually had): par = team1Score + G50 × (R2 − R1) / 100,
///   the G50 uplift with G50 = 245 ([kDlG50]).
///
/// In every branch target = floor(par) + 1.
DlsResult dlsTarget({
  required int team1Score,
  required double team1ResourcePct,
  required double team2ResourcePct,
}) {
  final r1 = team1ResourcePct;
  final r2 = team2ResourcePct;
  double par;
  if (r2 > r1) {
    par = team1Score + kDlG50 * (r2 - r1) / 100.0;
  } else if (r1 <= 0) {
    // Degenerate input (Team 1 had no resources): no meaningful
    // ratio exists; par is Team 1's score itself.
    par = team1Score.toDouble();
  } else {
    par = team1Score * r2 / r1;
  }
  return DlsResult(
    team1ResourcePct: r1,
    team2ResourcePct: r2,
    parScore: par,
    target: par.floor() + 1,
  );
}
