// Player of the Match shortlist: ranks eligible players of a completed
// match by their actual statistics (transparent, deterministic).
//
// Impact formula (documented for the user):
//   batting  = runs + fours*2 + sixes*4
//   bowling  = wickets*22 + (wickets>=3 ? 12 : 0)
//   bonuses  = (runs>=30 ? 12 : 0) + (runs>=50 ? 12 : 0)
//            + (bowlBalls>=12 && econ<=7.5 ? 8 : 0)
//            + (runs>=10 && wickets>=1 ? 6 : 0)   // all-round
// Only players who actually participated (batted or bowled) are eligible.
import 'models.dart';
import 'store.dart';

/// One POTM candidate with aggregated match figures.
class PotmCandidate {
  final String playerId;
  final String name;
  final String teamId;
  final String teamName;
  final String role;
  final String photoBase64;
  final int runs;
  final int balls;
  final int fours;
  final int sixes;
  final int wickets;
  final int bowlRuns;
  final int bowlBalls;
  final double impact;

  const PotmCandidate({
    required this.playerId,
    required this.name,
    required this.teamId,
    required this.teamName,
    required this.role,
    required this.photoBase64,
    required this.runs,
    required this.balls,
    required this.fours,
    required this.sixes,
    required this.wickets,
    required this.bowlRuns,
    required this.bowlBalls,
    required this.impact,
  });

  double get strikeRate => balls > 0 ? runs * 100.0 / balls : 0.0;
  double get economy => bowlBalls > 0 ? bowlRuns * 6.0 / bowlBalls : 0.0;

  /// Short human-readable line, e.g. "26* (8) • 2/19".
  String get figureLine {
    final parts = <String>[];
    if (balls > 0) {
      parts.add('$runs (${balls}b)');
    }
    if (bowlBalls > 0) {
      parts.add('$wickets/$bowlRuns');
    }
    return parts.join(' • ');
  }
}

double _impactOf({
  required int runs,
  required int fours,
  required int sixes,
  required int wickets,
  required int bowlRuns,
  required int bowlBalls,
}) {
  var score = runs.toDouble() + fours * 2.0 + sixes * 4.0;
  score += wickets * 22.0;
  if (wickets >= 3) score += 12;
  if (runs >= 30) score += 12;
  if (runs >= 50) score += 12;
  if (bowlBalls >= 12 && bowlRuns * 6.0 / bowlBalls <= 7.5) score += 8;
  if (runs >= 10 && wickets >= 1) score += 6; // all-round bonus
  return score;
}

/// Returns up to [maxCount] candidates, best impact first.
List<PotmCandidate> potmShortlist(Match m, Store store, {int maxCount = 3}) {
  final agg = <String, _Fig>{};
  for (final inn in m.innings) {
    inn.batting.forEach((pid, bf) {
      if (!bf.batted) return;
      final f = agg.putIfAbsent(pid, () => _Fig());
      f.runs += bf.runs;
      f.balls += bf.balls;
      f.fours += bf.fours;
      f.sixes += bf.sixes;
    });
    inn.bowling.forEach((pid, wf) {
      if (wf.legalBalls <= 0) return;
      final f = agg.putIfAbsent(pid, () => _Fig());
      f.wickets += wf.wickets;
      f.bowlRuns += wf.runs;
      f.bowlBalls += wf.legalBalls;
    });
  }
  final out = <PotmCandidate>[];
  for (final e in agg.entries) {
    final pid = e.key;
    final f = e.value;
    final pl = store.findPlayer(pid);
    // Team: resolve from the playing XIs (Player carries no teamId).
    var teamId = '';
    if (m.xiA.contains(pid)) {
      teamId = m.teamAId;
    } else if (m.xiB.contains(pid)) {
      teamId = m.teamBId;
    }
    final teamName = teamId.isEmpty ? '' : store.teamName(teamId);
    out.add(PotmCandidate(
      playerId: pid,
      name: pl != null && pl.name.isNotEmpty ? pl.name : store.playerName(pid),
      teamId: teamId,
      teamName: teamName,
      role: pl?.role ?? 'Batter',
      // v1.1.6: photo via the shared player record (a photo added in
      // Registered Players / Team Management shows up in the picker).
      photoBase64: store.photoForPlayer(pid),
      runs: f.runs,
      balls: f.balls,
      fours: f.fours,
      sixes: f.sixes,
      wickets: f.wickets,
      bowlRuns: f.bowlRuns,
      bowlBalls: f.bowlBalls,
      impact: _impactOf(
        runs: f.runs,
        fours: f.fours,
        sixes: f.sixes,
        wickets: f.wickets,
        bowlRuns: f.bowlRuns,
        bowlBalls: f.bowlBalls,
      ),
    ));
  }
  out.sort((a, b) {
    final c = b.impact.compareTo(a.impact);
    if (c != 0) return c;
    return a.name.compareTo(b.name);
  });
  return out.take(maxCount).toList();
}

class _Fig {
  int runs = 0;
  int balls = 0;
  int fours = 0;
  int sixes = 0;
  int wickets = 0;
  int bowlRuns = 0;
  int bowlBalls = 0;
}
