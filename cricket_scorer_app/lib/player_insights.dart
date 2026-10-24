// Player Insights aggregation — pure Dart (no Flutter imports).
//
// Aggregates one player's batting-position, dismissal, runs-bucket
// and bowling breakdowns from a list of matches, for the Player
// Insights charts. Like `computeCareerStats` in scoring.dart, only
// **completed** matches count, batting/bowling totals read from the
// stored figures (BatFig / BowlFig — the source of truth), and ball
// events are preferred where they exist with a figure-based
// fallback where they do not:
//
// * Batting position: per innings, the order in which batters are
//   first seen in the ball events (striker / non-striker first
//   sighting). When an innings has no events, the batting map's
//   insertion order of batted players is used (the same fallback
//   philosophy as the figure-only derivations in scoring.dart).
//   Batted players missing from the event-derived order (truncated
//   event lists) are appended in batting-map order.
// * Dismissal types: from BallEvents where outPlayerId == player,
//   keyed by BallEvent.wicketType. A dismissal not covered by any
//   event (figure-only record) is recovered by parsing the BatFig
//   howOut prefix — see [dismissalTypeFromHowOut].
// * Bowling wicket types: from BallEvents where bowlerId == player
//   and isWicket, keyed by wicketType — EXCLUDING 'runOut' and
//   'mankad'. Neither is a bowler wicket: a run-out is credited to
//   the fielder, and a mankad, while recorded as a dismissal by
//   the bowler as fielder, is likewise not credited as a bowler
//   wicket in this breakdown. Mankad events are counted separately
//   in [BowlingInsights.mankads] so the information is not lost.
//   (BowlFig.wickets — and therefore [BowlingInsights.totalWickets]
//   — follows scoring.dart's applyBall rule, which counts every
//   non-runOut dismissal, so the two totals can differ by the
//   mankad count.)

import 'models.dart';

/// Runs-bucket labels, in order. Per-innings runs (batted only)
/// fall into exactly one bucket.
const List<String> kRunsBucketLabels = [
  '0',
  '1-9',
  '10-29',
  '30-49',
  '50-99',
  '100+',
];

/// Bucket label for one innings' [runs].
String runsBucketLabel(int runs) {
  if (runs <= 0) return '0';
  if (runs < 10) return '1-9';
  if (runs < 30) return '10-29';
  if (runs < 50) return '30-49';
  if (runs < 100) return '50-99';
  return '100+';
}

/// Dismissal type parsed from a stored BatFig.howOut text, in the
/// token forms written by scoring.dart's howOutText:
/// `'b <id>'` → bowled, `'c <id> b <id>'` → caught,
/// `'lbw b <id>'` → lbw, `'run out (<id>)'` → runOut,
/// `'st <id> b <id>'` → stumped, `'hit wicket b <id>'` → hitWicket.
/// Any other text (newer dismissal types are stored verbatim,
/// e.g. 'mankad', 'retiredOut', 'timedOut') returns its first
/// token. Returns null for empty text.
String? dismissalTypeFromHowOut(String howOut) {
  final t = howOut.trim();
  if (t.isEmpty) return null;
  if (t.startsWith('run out')) return 'runOut';
  if (t.startsWith('hit wicket')) return 'hitWicket';
  if (t.startsWith('lbw')) return 'lbw';
  if (t.startsWith('st ')) return 'stumped';
  if (t.startsWith('c ')) return 'caught';
  if (t.startsWith('b ')) return 'bowled';
  // Verbatim stored type, or free text: take the first token.
  return t.split(' ').first;
}

/// Batting figures at one batting-order position (1-based).
class PositionBattingStat {
  int innings;
  int runs;
  PositionBattingStat({this.innings = 0, this.runs = 0});

  @override
  String toString() => 'PositionBattingStat(innings: $innings, runs: $runs)';
}

class BattingInsights {
  /// Innings in which the player batted.
  int innings = 0;

  /// Innings ending not out.
  int notOuts = 0;

  /// Total runs across those innings (from BatFig).
  int totalRuns = 0;

  /// Position (1-based) → innings batted there and runs scored
  /// there. Empty when the player never batted.
  final Map<int, PositionBattingStat> runsByPosition = {};

  /// Dismissal type (BallEvent.wicketType vocabulary, e.g.
  /// 'bowled', 'caught', 'runOut') → count. Empty when the player
  /// was never dismissed in the data.
  final Map<String, int> dismissalTypeCounts = {};

  /// Runs-bucket label (see [kRunsBucketLabels]) → innings count.
  /// All six labels are always present (0 when unused) so charts
  /// can read the map directly.
  final Map<String, int> runsBuckets = {
    for (final label in kRunsBucketLabels) label: 0,
  };

  bool get isEmpty => innings == 0;
}

/// One innings' bowling figure, for per-match economy.
class BowlingMatchFigure {
  final String matchId;

  /// 1-based innings number within the match.
  final int inningsNo;
  final int balls;
  final int runsConceded;
  final int wickets;
  final int ballsPerOver;

  const BowlingMatchFigure({
    required this.matchId,
    required this.inningsNo,
    required this.balls,
    required this.runsConceded,
    required this.wickets,
    this.ballsPerOver = 6,
  });

  /// Runs per over for this figure (0 when no balls were bowled).
  double get economy =>
      balls == 0 ? 0.0 : runsConceded * ballsPerOver / balls;

  @override
  String toString() =>
      'BowlingMatchFigure($matchId inn$inningsNo, $balls balls, '
      '$runsConceded runs, $wickets wkts, econ $economy)';
}

class BowlingInsights {
  /// Bowler-credited wicket type → count, from ball events.
  /// 'runOut' and 'mankad' are excluded (see file header).
  final Map<String, int> wicketsByType = {};

  /// Mankad dismissals effected by this player as bowler/fielder,
  /// counted separately because they are not bowler wickets.
  int mankads = 0;

  /// One entry per innings in which the player has a bowling
  /// figure (including 0-ball figures only when a figure row
  /// exists — in practice applyBall creates one on first ball).
  final List<BowlingMatchFigure> perMatchEconomy = [];

  int totalBalls = 0;
  int totalRunsConceded = 0;

  /// Total wickets from the bowling figures (BowlFig.wickets,
  /// applyBall rule: every dismissal except run-out).
  int totalWickets = 0;

  /// Overall economy: total runs conceded per over, weighting each
  /// innings by its own balls-per-over. 0 when no balls bowled.
  double get overallEconomy {
    var overs = 0.0;
    for (final f in perMatchEconomy) {
      if (f.ballsPerOver > 0) overs += f.balls / f.ballsPerOver;
    }
    if (overs == 0) return 0.0;
    return totalRunsConceded / overs;
  }

  bool get isEmpty => perMatchEconomy.isEmpty && wicketsByType.isEmpty;
}

class PlayerInsights {
  final String playerId;
  final BattingInsights batting;
  final BowlingInsights bowling;
  PlayerInsights(this.playerId, this.batting, this.bowling);

  bool get isEmpty => batting.isEmpty && bowling.isEmpty;
}

/// Batting-order position (1-based) of every batted player in one
/// innings: event first-appearance order, with any batted player
/// the events never show appended in batting-map insertion order;
/// batting-map insertion order alone when there are no events.
Map<String, int> _battingPositions(InningsState inn) {
  final order = <String>[];
  final seen = <String>{};
  void add(String id) {
    if (id.isEmpty || seen.contains(id)) return;
    seen.add(id);
    order.add(id);
  }

  if (inn.events.isNotEmpty) {
    for (final ev in inn.events) {
      add(ev.strikerId);
      add(ev.nonStrikerId);
    }
  }
  // Fallback / completion: batting-map insertion order.
  for (final e in inn.batting.entries) {
    if (e.value.batted) add(e.key);
  }
  return {for (var i = 0; i < order.length; i++) order[i]: i + 1};
}

/// Aggregate [playerId]'s insights from [matches] (completed
/// matches only). Returns honest empties — zero counts, empty
/// maps/lists (runsBuckets keeps its six zeroed labels) — when the
/// player has no data.
PlayerInsights buildPlayerInsights(List<Match> matches, String playerId) {
  final batting = BattingInsights();
  final bowling = BowlingInsights();

  for (final m in matches) {
    if (m.status != 'completed') continue;
    for (var idx = 0; idx < m.innings.length; idx++) {
      final inn = m.innings[idx];

      // ---- Batting ----
      final fig = inn.batting[playerId];
      if (fig != null && fig.batted) {
        batting.innings++;
        if (!fig.out) batting.notOuts++;
        batting.totalRuns += fig.runs;
        final label = runsBucketLabel(fig.runs);
        batting.runsBuckets[label] = (batting.runsBuckets[label] ?? 0) + 1;
        final pos = _battingPositions(inn)[playerId];
        if (pos != null) {
          final stat = batting.runsByPosition.putIfAbsent(
            pos,
            () => PositionBattingStat(),
          );
          stat.innings++;
          stat.runs += fig.runs;
        }
      }

      // Dismissal type: events first.
      var dismissalCounted = false;
      for (final ev in inn.events) {
        if (ev.isWicket && ev.outPlayerId == playerId) {
          final type = ev.wicketType.isEmpty ? 'out' : ev.wicketType;
          batting.dismissalTypeCounts[type] =
              (batting.dismissalTypeCounts[type] ?? 0) + 1;
          dismissalCounted = true;
        }
      }
      // Figure fallback: a dismissal the events do not cover.
      if (!dismissalCounted && fig != null && fig.batted && fig.out) {
        final type = dismissalTypeFromHowOut(fig.howOut);
        if (type != null && type.isNotEmpty) {
          batting.dismissalTypeCounts[type] =
              (batting.dismissalTypeCounts[type] ?? 0) + 1;
        }
      }

      // ---- Bowling ----
      final bowlFig = inn.bowling[playerId];
      if (bowlFig != null) {
        final entry = BowlingMatchFigure(
          matchId: m.id,
          inningsNo: idx + 1,
          balls: bowlFig.legalBalls,
          runsConceded: bowlFig.runs,
          wickets: bowlFig.wickets,
          ballsPerOver: inn.ballsPerOver,
        );
        bowling.perMatchEconomy.add(entry);
        bowling.totalBalls += bowlFig.legalBalls;
        bowling.totalRunsConceded += bowlFig.runs;
        bowling.totalWickets += bowlFig.wickets;
      }
      for (final ev in inn.events) {
        if (!ev.isWicket || ev.bowlerId != playerId) continue;
        if (ev.wicketType == 'runOut') continue;
        if (ev.wicketType == 'mankad') {
          bowling.mankads++;
          continue;
        }
        final type = ev.wicketType.isEmpty ? 'out' : ev.wicketType;
        bowling.wicketsByType[type] =
            (bowling.wicketsByType[type] ?? 0) + 1;
      }
    }
  }
  return PlayerInsights(playerId, batting, bowling);
}
