// Pure-Dart scoring engine + statistics for CricScore Offline.
// No Flutter imports: everything here is unit-testable.
import 'dart:convert';

import 'models.dart';

class BallInput {
  String extraType; // none / wide / noBall / bye / legBye
  int batRuns;
  int extraRuns; // additional runs on a wide (beyond the 1-run penalty)
  bool isWicket;
  String wicketType;
  String outPlayerId; // defaults to striker
  String fielderId;
  int? zone; // legacy, kept for API compat
  double? shotX; // wagon-wheel shot point, normalized -1..1
  double? shotY;

  BallInput({
    this.extraType = 'none',
    this.batRuns = 0,
    this.extraRuns = 0,
    this.isWicket = false,
    this.wicketType = '',
    this.outPlayerId = '',
    this.fielderId = '',
    this.zone,
    this.shotX,
    this.shotY,
  });
}

String _snapshot(InningsState s) {
  final j = s.toJson()..remove('undoStack');
  return jsonEncode(j);
}

void _restore(InningsState s, String snap) {
  final j = jsonDecode(snap) as Map<String, dynamic>;
  final t = InningsState.fromJson(j);
  s.totalRuns = t.totalRuns;
  s.wickets = t.wickets;
  s.legalBalls = t.legalBalls;
  s.strikerId = t.strikerId;
  s.nonStrikerId = t.nonStrikerId;
  s.currentBowlerId = t.currentBowlerId;
  s.lastBowlerId = t.lastBowlerId;
  s.awaitingBatter = t.awaitingBatter;
  s.awaitingBowler = t.awaitingBowler;
  s.batting = t.batting;
  s.bowling = t.bowling;
  s.widesRuns = t.widesRuns;
  s.noBallRuns = t.noBallRuns;
  s.byeRuns = t.byeRuns;
  s.legByeRuns = t.legByeRuns;
  s.noBallCount = t.noBallCount;
  s.wideCount = t.wideCount;
  s.events = t.events;
  s.fallOfWickets = t.fallOfWickets;
  s.currentOverBowlerRuns = t.currentOverBowlerRuns;
  s.currentOverTeamRuns = t.currentOverTeamRuns;
  s.maxWickets = t.maxWickets;
  s.widePenalty = t.widePenalty;
  s.noBallPenalty = t.noBallPenalty;
  s.target = t.target;
}

/// Set the two openers and first bowler for a fresh innings.
void setOpeners(
  InningsState s,
  String striker,
  String nonStriker,
  String bowler,
) {
  s.strikerId = striker;
  s.nonStrikerId = nonStriker;
  s.currentBowlerId = bowler;
  for (final id in [striker, nonStriker]) {
    s.batting.putIfAbsent(id, () => BatFig()).batted = true;
  }
  s.bowling.putIfAbsent(bowler, () => BowlFig());
}

/// Choose the next batter after a wicket (fills the vacant end).
void setNextBatter(InningsState s, String playerId) {
  if (s.strikerId == '') {
    s.strikerId = playerId;
  } else if (s.nonStrikerId == '') {
    s.nonStrikerId = playerId;
  }
  s.batting.putIfAbsent(playerId, () => BatFig()).batted = true;
  s.awaitingBatter = false;
}

/// Choose the bowler for the next over. A bowler may not bowl two
/// consecutive overs.
bool setBowler(InningsState s, String playerId) {
  if (playerId == s.lastBowlerId && s.legalBalls > 0) return false;
  s.currentBowlerId = playerId;
  s.bowling.putIfAbsent(playerId, () => BowlFig());
  s.awaitingBowler = false;
  return true;
}

/// Apply one delivery to the innings. Returns false if the ball could not
/// be applied (innings complete, or players not selected yet).
bool applyBall(InningsState s, BallInput input) {
  if (s.isComplete) return false;
  if (s.strikerId == '' || s.nonStrikerId == '' || s.currentBowlerId == '') {
    return false;
  }
  s.undoStack.add(_snapshot(s));

  final strikerAtBall = s.strikerId;
  final nonStrikerAtBall = s.nonStrikerId;
  final bowlerId = s.currentBowlerId;
  final bat = s.batting.putIfAbsent(strikerAtBall, () => BatFig());
  bat.batted = true;
  final bowl = s.bowling.putIfAbsent(bowlerId, () => BowlFig());

  var total = 0;
  var legal = false;
  var bowlerRuns = 0; // runs conceded to bowler
  var rotationRuns = 0; // runs that may swap strike

  switch (input.extraType) {
    case 'wide':
      total = (s.widePenalty ? 1 : 0) + input.extraRuns;
      s.widesRuns += total;
      s.wideCount++;
      bowlerRuns = total;
      bowl.wides++;
      rotationRuns = input.extraRuns;
      break;
    case 'noBall':
      total = (s.noBallPenalty ? 1 : 0) + input.batRuns;
      s.noBallRuns += s.noBallPenalty ? 1 : 0;
      s.noBallCount++;
      bowlerRuns = total;
      bowl.noBalls++;
      bat.runs += input.batRuns;
      bat.balls += 1;
      if (input.batRuns == 4) bat.fours++;
      if (input.batRuns == 6) bat.sixes++;
      rotationRuns = input.batRuns;
      break;
    case 'bye':
      total = input.batRuns;
      legal = true;
      s.byeRuns += total;
      bat.balls += 1;
      rotationRuns = input.batRuns;
      break;
    case 'legBye':
      total = input.batRuns;
      legal = true;
      s.legByeRuns += total;
      bat.balls += 1;
      rotationRuns = input.batRuns;
      break;
    default: // none
      total = input.batRuns;
      legal = true;
      bat.runs += input.batRuns;
      bat.balls += 1;
      if (input.batRuns == 4) bat.fours++;
      if (input.batRuns == 6) bat.sixes++;
      bowlerRuns = input.batRuns;
      rotationRuns = input.batRuns;
  }

  if (legal) {
    s.legalBalls++;
    bowl.legalBalls++;
  }
  bowl.runs += bowlerRuns;
  s.currentOverBowlerRuns += bowlerRuns;
  s.currentOverTeamRuns += total;
  s.totalRuns += total;

  final ev = BallEvent(
    strikerId: strikerAtBall,
    nonStrikerId: nonStrikerAtBall,
    bowlerId: bowlerId,
    extraType: input.extraType,
    batRuns: input.extraType == 'wide' ? 0 : input.batRuns,
    extraRuns: input.extraType == 'wide' ? input.extraRuns : 0,
    isWicket: input.isWicket,
    wicketType: input.isWicket ? input.wicketType : '',
    outPlayerId: input.isWicket
        ? (input.outPlayerId == '' ? strikerAtBall : input.outPlayerId)
        : '',
    fielderId: input.fielderId,
    zone: input.zone,
    shotX: input.shotX,
    shotY: input.shotY,
    totalRuns: total,
    legalBall: legal,
  );
  s.events.add(ev);

  // Strike rotation for runs run.
  if (rotationRuns % 2 == 1) {
    final tmp = s.strikerId;
    s.strikerId = s.nonStrikerId;
    s.nonStrikerId = tmp;
  }

  // Wicket handling (after any crossing on a run-out).
  if (input.isWicket) {
    s.wickets++;
    if (input.wicketType != 'runOut') bowl.wickets++;
    final outId = ev.outPlayerId;
    final outFig = s.batting.putIfAbsent(outId, () => BatFig());
    outFig.batted = true;
    outFig.out = true;
    outFig.howOut = howOutText(input.wicketType, bowlerId, input.fielderId);
    s.fallOfWickets.add(
      FallOfWicket(
        s.wickets,
        s.totalRuns,
        oversText(s.legalBalls, s.ballsPerOver),
        outId,
      ),
    );
    if (s.wickets < s.effectiveMaxWickets) {
      if (s.strikerId == outId) s.strikerId = '';
      if (s.nonStrikerId == outId) s.nonStrikerId = '';
      s.awaitingBatter = true;
    } else {
      s.awaitingBatter = false;
    }
  }

  // Over completion.
  if (legal && s.legalBalls % s.ballsPerOver == 0) {
    if (s.currentOverTeamRuns == 0) bowl.maidens++;
    s.currentOverBowlerRuns = 0;
    s.currentOverTeamRuns = 0;
    // swap ends
    final tmp = s.strikerId;
    s.strikerId = s.nonStrikerId;
    s.nonStrikerId = tmp;
    s.lastBowlerId = bowlerId;
    s.currentBowlerId = '';
    s.awaitingBowler = !s.isComplete;
  }
  if (s.isComplete) {
    s.awaitingBowler = false;
    if (s.wickets >= s.effectiveMaxWickets) s.awaitingBatter = false;
  }
  return true;
}

bool undoLastBall(InningsState s) {
  if (s.undoStack.isEmpty) return false;
  final snap = s.undoStack.removeLast();
  _restore(s, snap);
  return true;
}

/// Dismissal text using raw ids; the UI replaces ids with names.
/// Format tokens: type|bowlerId|fielderId
String howOutText(String type, String bowlerId, String fielderId) {
  switch (type) {
    case 'bowled':
      return 'b $bowlerId';
    case 'caught':
      return 'c $fielderId b $bowlerId';
    case 'lbw':
      return 'lbw b $bowlerId';
    case 'runOut':
      return 'run out ($fielderId)';
    case 'stumped':
      return 'st $fielderId b $bowlerId';
    case 'hitWicket':
      return 'hit wicket b $bowlerId';
    default:
      return type;
  }
}

/// Human-readable dismissal by resolving ids via [nameOf].
String resolveHowOut(String howOut, String Function(String id) nameOf) {
  if (howOut == '') return '';
  var out = howOut;
  // Replace whole-word id tokens.
  final parts = out.split(' ');
  for (var i = 0; i < parts.length; i++) {
    final p = parts[i];
    final clean = p.replaceAll('(', '').replaceAll(')', '');
    if (clean.length > 6 && !['bowled', 'wicket'].contains(clean)) {
      final n = nameOf(clean);
      if (n != clean) {
        parts[i] = p.replaceAll(clean, n);
      }
    }
  }
  out = parts.join(' ');
  return out;
}

/// Start (or fetch in-progress) innings [n] (1-based) of a match.
InningsState startInnings(Match m, int n) {
  while (m.innings.length < n) {
    final battingId = m.innings.isEmpty ? m.battingFirstId : m.battingSecondId;
    final bowlingId = battingId == m.teamAId ? m.teamBId : m.teamAId;
    final inn = InningsState(
      battingTeamId: battingId,
      bowlingTeamId: bowlingId,
      battingXI: m.xiFor(battingId),
      bowlingXI: m.xiFor(bowlingId),
      oversLimit: m.oversLimit,
      ballsPerOver: m.ballsPerOver,
    );
    inn.widePenalty = m.widePenalty;
    inn.noBallPenalty = m.noBallPenalty;
    if (m.totalWickets > 0) {
      inn.maxWickets = m.totalWickets;
    } else if (m.lastManStands) {
      // Simplified last-man-stands: innings can lose every batter
      // (final wicket ends it); the last pair bats on together.
      inn.maxWickets = m.xiFor(battingId).length;
    }
    if (m.innings.length == 1 && m.innings.isNotEmpty) {
      inn.target = m.innings[0].totalRuns + 1;
    }
    m.innings.add(inn);
  }
  return m.innings[n - 1];
}

/// Compute the result text once a match finishes. Also updates m.status
/// and m.resultText when the 2nd innings is complete.
String computeResult(Match m, String Function(String teamId) teamName) {
  if (m.status == 'noResult') return 'No result';
  if (m.innings.length < 2) return '';
  final i1 = m.innings[0];
  final i2 = m.innings[1];
  if (!i2.isComplete && m.status != 'completed') return '';
  final maxWkts = i2.effectiveMaxWickets;
  String text;
  if (i2.totalRuns > i1.totalRuns) {
    final wktsLeft = maxWkts - i2.wickets;
    final ballsUsed = i2.legalBalls;
    final ballsLeft = i2.oversLimit * i2.ballsPerOver - ballsUsed;
    text =
        '${teamName(i2.battingTeamId)} won by $wktsLeft wicket${wktsLeft == 1 ? '' : 's'}'
        '${ballsLeft > 0 ? ' ($ballsLeft ball${ballsLeft == 1 ? '' : 's'} left)' : ''}';
  } else if (i1.totalRuns > i2.totalRuns) {
    final margin = i1.totalRuns - i2.totalRuns;
    text =
        '${teamName(i1.battingTeamId)} won by $margin run${margin == 1 ? '' : 's'}';
  } else {
    text = 'Match tied';
  }
  if (i2.isComplete) {
    m.status = 'completed';
    m.resultText = text;
  }
  return text;
}

// ---------------- Points table ----------------

class PointsRow {
  String teamId;
  int played = 0, won = 0, lost = 0, tied = 0, noResult = 0, points = 0;
  int runsFor = 0, ballsFor = 0, runsAgainst = 0, ballsAgainst = 0;
  int ballsPerOver = 6;
  PointsRow(this.teamId);

  /// ICC net run rate (per over): aggregate runs per over scored minus
  /// aggregate runs per over conceded, over the whole tournament.
  double get nrr {
    if (ballsFor == 0 || ballsAgainst == 0) return 0;
    final oversFor = ballsFor / ballsPerOver;
    final oversAgainst = ballsAgainst / ballsPerOver;
    return (runsFor / oversFor) - (runsAgainst / oversAgainst);
  }
}

int _adjustedBalls(InningsState inn) {
  final quota = inn.oversLimit * inn.ballsPerOver;
  // ICC rule: a side bowled out before its full quota is deemed to have
  // faced the full quota of overs.
  if (inn.wickets >= inn.effectiveMaxWickets) return quota; // all out
  return inn.legalBalls;
}

List<PointsRow> computePointsTable(
  String tournamentId,
  List<String> teamIds,
  List<Match> matches, {
  Map<String, int> pointsAdjustments = const {},
}) {
  final rows = {for (final id in teamIds) id: PointsRow(id)};
  for (final m in matches) {
    if (m.tournamentId != tournamentId) continue;
    if (m.status != 'completed' && m.status != 'noResult') continue;
    final a = rows[m.teamAId];
    final b = rows[m.teamBId];
    if (a == null || b == null) continue;
    a.ballsPerOver = m.ballsPerOver;
    b.ballsPerOver = m.ballsPerOver;
    a.played++;
    b.played++;
    if (m.status == 'noResult' || m.innings.length < 2) {
      a.noResult++;
      b.noResult++;
      a.points += 1;
      b.points += 1;
      continue;
    }
    final i1 = m.innings[0];
    final i2 = m.innings[1];
    // NRR accounting
    void account(InningsState inn) {
      final batRow = rows[inn.battingTeamId]!;
      final bowlRow = rows[inn.bowlingTeamId]!;
      final balls = _adjustedBalls(inn);
      batRow.runsFor += inn.totalRuns;
      batRow.ballsFor += balls;
      bowlRow.runsAgainst += inn.totalRuns;
      bowlRow.ballsAgainst += balls;
    }

    account(i1);
    account(i2);
    if (i1.totalRuns == i2.totalRuns) {
      a.tied++;
      b.tied++;
      a.points += 1;
      b.points += 1;
    } else {
      final winnerId = i1.totalRuns > i2.totalRuns
          ? i1.battingTeamId
          : i2.battingTeamId;
      final loserId = winnerId == m.teamAId ? m.teamBId : m.teamAId;
      rows[winnerId]!.won++;
      rows[winnerId]!.points += 2;
      rows[loserId]!.lost++;
    }
  }
  pointsAdjustments.forEach((teamId, extra) {
    rows[teamId]?.points += extra;
  });
  final list = rows.values.toList();
  list.sort((x, y) {
    if (y.points != x.points) return y.points.compareTo(x.points);
    return y.nrr.compareTo(x.nrr);
  });
  return list;
}

// ---------------- Career stats ----------------

class CareerStats {
  String playerId;
  int matches = 0;
  int inningsBatted = 0;
  int notOuts = 0;
  int runs = 0;
  int ballsFaced = 0;
  int highScore = 0;
  int hundreds = 0;
  int fifties = 0;
  int fours = 0;
  int sixes = 0;
  int ballsBowled = 0;
  int runsConceded = 0;
  int wickets = 0;
  int bestWickets = 0;
  int bestRuns = 1 << 30;
  int catches = 0;
  int stumpings = 0;
  int runOuts = 0;

  CareerStats(this.playerId);

  int get dismissals => inningsBatted - notOuts;
  double get battingAverage =>
      dismissals == 0 ? runs.toDouble() : runs / dismissals;
  double get battingSR => ballsFaced == 0 ? 0 : runs * 100 / ballsFaced;
  double get bowlingAverage => wickets == 0 ? 0 : runsConceded / wickets;
  double get economy => ballsBowled == 0 ? 0 : runsConceded * 6 / ballsBowled;
  double get bowlingSR => wickets == 0 ? 0 : ballsBowled / wickets;
  String get bestFigures => wickets == 0 ? '-' : '$bestWickets/$bestRuns';
  double get mvpPoints =>
      runs + 20.0 * wickets + 10.0 * (catches + stumpings) + 5.0 * runOuts;
}

Map<String, CareerStats> computeCareerStats(
  List<Match> matches, {
  String? tournamentId,
}) {
  final map = <String, CareerStats>{};
  CareerStats get(String id) => map.putIfAbsent(id, () => CareerStats(id));

  for (final m in matches) {
    if (tournamentId != null && m.tournamentId != tournamentId) continue;
    // Career stats are conventionally from completed matches only.
    if (m.status != 'completed') continue;
    final xi = {...m.xiA, ...m.xiB};
    for (final pid in xi) {
      get(pid).matches++;
    }
    for (final inn in m.innings) {
      inn.batting.forEach((pid, fig) {
        if (!fig.batted) return;
        final c = get(pid);
        c.inningsBatted++;
        if (!fig.out) c.notOuts++;
        c.runs += fig.runs;
        c.ballsFaced += fig.balls;
        c.fours += fig.fours;
        c.sixes += fig.sixes;
        if (fig.runs > c.highScore) c.highScore = fig.runs;
        if (fig.runs >= 100) {
          c.hundreds++;
        } else if (fig.runs >= 50) {
          c.fifties++;
        }
      });
      inn.bowling.forEach((pid, fig) {
        final c = get(pid);
        c.ballsBowled += fig.legalBalls;
        c.runsConceded += fig.runs;
        c.wickets += fig.wickets;
        if (fig.wickets > c.bestWickets ||
            (fig.wickets == c.bestWickets &&
                fig.wickets > 0 &&
                fig.runs < c.bestRuns)) {
          c.bestWickets = fig.wickets;
          c.bestRuns = fig.runs;
        }
      });
      for (final ev in inn.events) {
        if (ev.fielderId == '') continue;
        final c = get(ev.fielderId);
        if (ev.wicketType == 'caught') c.catches++;
        if (ev.wicketType == 'stumped') c.stumpings++;
        if (ev.wicketType == 'runOut') c.runOuts++;
      }
    }
  }
  return map;
}

/// Fold manually-entered past scores into career totals.
void applyManualStats(
  Map<String, CareerStats> map,
  List<ManualStatEntry> entries,
) {
  for (final e in entries) {
    final c = map.putIfAbsent(e.playerId, () => CareerStats(e.playerId));
    c.matches++;
    if (e.balls > 0 || e.runs > 0) {
      c.inningsBatted++;
      if (e.notOut) c.notOuts++;
      c.runs += e.runs;
      c.ballsFaced += e.balls;
      c.fours += e.fours;
      c.sixes += e.sixes;
      if (e.runs > c.highScore) c.highScore = e.runs;
      if (e.runs >= 100) {
        c.hundreds++;
      } else if (e.runs >= 50) {
        c.fifties++;
      }
    }
    if (e.ballsBowled > 0 || e.wickets > 0) {
      c.ballsBowled += e.ballsBowled;
      c.runsConceded += e.runsConceded;
      c.wickets += e.wickets;
      if (e.wickets > c.bestWickets ||
          (e.wickets == c.bestWickets &&
              e.wickets > 0 &&
              e.runsConceded < c.bestRuns)) {
        c.bestWickets = e.wickets;
        c.bestRuns = e.runsConceded;
      }
    }
    c.catches += e.catches;
    c.stumpings += e.stumpings;
  }
}

class TeamStats {
  String teamId;
  int played = 0, won = 0, lost = 0, tied = 0, noResult = 0;
  int battedFirst = 0, wonBattingFirst = 0, chased = 0, wonChasing = 0;
  int tossWon = 0;
  TeamStats(this.teamId);
  double get winPct {
    final decided = won + lost;
    return decided == 0 ? 0 : won * 100 / decided;
  }
}

Map<String, TeamStats> computeTeamStats(List<Match> matches) {
  final map = <String, TeamStats>{};
  TeamStats get(String id) => map.putIfAbsent(id, () => TeamStats(id));
  for (final m in matches) {
    if (m.status != 'completed' && m.status != 'noResult') continue;
    final a = get(m.teamAId);
    final b = get(m.teamBId);
    a.played++;
    b.played++;
    if (m.status == 'noResult' || m.innings.length < 2) {
      a.noResult++;
      b.noResult++;
      continue;
    }
    final i1 = m.innings[0];
    final i2 = m.innings[1];
    get(m.tossWinnerId).tossWon++;
    final first = get(i1.battingTeamId);
    final second = get(i2.battingTeamId);
    first.battedFirst++;
    second.chased++;
    if (i1.totalRuns == i2.totalRuns) {
      a.tied++;
      b.tied++;
    } else {
      final winnerId = i1.totalRuns > i2.totalRuns
          ? i1.battingTeamId
          : i2.battingTeamId;
      final loserId = winnerId == m.teamAId ? m.teamBId : m.teamAId;
      get(winnerId).won++;
      get(loserId).lost++;
      if (winnerId == i1.battingTeamId) first.wonBattingFirst++;
      if (winnerId == i2.battingTeamId) second.wonChasing++;
    }
  }
  return map;
}

class HeadToHead {
  int played = 0, aWins = 0, bWins = 0, tied = 0, noResult = 0;
}

HeadToHead headToHead(List<Match> matches, String teamA, String teamB) {
  final h = HeadToHead();
  for (final m in matches) {
    final pair = {m.teamAId, m.teamBId};
    if (!pair.contains(teamA) || !pair.contains(teamB)) continue;
    if (m.status != 'completed' && m.status != 'noResult') continue;
    h.played++;
    if (m.status == 'noResult' || m.innings.length < 2) {
      h.noResult++;
      continue;
    }
    final i1 = m.innings[0];
    final i2 = m.innings[1];
    if (i1.totalRuns == i2.totalRuns) {
      h.tied++;
    } else {
      final winnerId = i1.totalRuns > i2.totalRuns
          ? i1.battingTeamId
          : i2.battingTeamId;
      if (winnerId == teamA) {
        h.aWins++;
      } else {
        h.bWins++;
      }
    }
  }
  return h;
}

// ---------------- Charts data ----------------

/// Cumulative runs at the end of each over (worm). Includes a final
/// partial-over point if the innings ended mid-over.
List<int> wormData(InningsState inn) {
  final out = <int>[];
  var cum = 0;
  var legalInOver = 0;
  for (final ev in inn.events) {
    cum += ev.totalRuns;
    if (ev.legalBall) {
      legalInOver++;
      if (legalInOver == inn.ballsPerOver) {
        out.add(cum);
        legalInOver = 0;
      }
    }
  }
  if (legalInOver > 0 || out.isEmpty) out.add(cum);
  return out;
}

/// Runs scored in each over (Manhattan).
List<int> manhattanData(InningsState inn) {
  final out = <int>[];
  var runs = 0;
  var legalInOver = 0;
  var started = false;
  for (final ev in inn.events) {
    started = true;
    runs += ev.totalRuns;
    if (ev.legalBall) {
      legalInOver++;
      if (legalInOver == inn.ballsPerOver) {
        out.add(runs);
        runs = 0;
        legalInOver = 0;
        started = false;
      }
    }
  }
  if (started || out.isEmpty) out.add(runs);
  return out;
}

/// One plotted shot on the wagon wheel.
class ShotPlot {
  double x; // normalized -1..1 (boundary = 1.0), screen orientation
  double y;
  int runs; // bat runs off the shot
  bool isWicket;
  ShotPlot(this.x, this.y, this.runs, this.isWicket);
}

/// Wagon-wheel shots for one batter in one innings: every plotted ball.
List<ShotPlot> wagonWheelShots(InningsState inn, String playerId) {
  final list = <ShotPlot>[];
  for (final ev in inn.events) {
    if (ev.strikerId != playerId) continue;
    if (ev.extraType == 'wide') continue;
    final x = ev.shotX;
    final y = ev.shotY;
    if (x == null || y == null) continue;
    list.add(ShotPlot(x, y, ev.batRuns, ev.isWicket));
  }
  return list;
}

// ---------------- Partnerships ----------------

class Partnership {
  String batter1Id;
  String batter2Id;
  int runs = 0;
  int balls = 0; // deliveries excluding wides
  bool unbroken = false;
  Partnership(this.batter1Id, this.batter2Id);
}

List<Partnership> partnerships(InningsState inn) {
  final list = <Partnership>[];
  Partnership? cur;
  for (final ev in inn.events) {
    cur ??= Partnership(ev.strikerId, ev.nonStrikerId);
    cur.runs += ev.totalRuns;
    if (ev.extraType != 'wide') cur.balls++;
    if (ev.isWicket) {
      list.add(cur);
      cur = null;
    }
  }
  if (cur != null && (cur.runs > 0 || cur.balls > 0)) {
    cur.unbroken = true;
    list.add(cur);
  }
  return list;
}

/// Fastest fifties / hundreds (balls taken to reach the milestone) in a
/// set of matches, optionally scoped to one tournament.
class Milestone {
  String playerId;
  int balls;
  int runs; // final runs in that innings
  Milestone(this.playerId, this.balls, this.runs);
}

class FastestResult {
  List<Milestone> fifties;
  List<Milestone> hundreds;
  FastestResult(this.fifties, this.hundreds);
}

FastestResult fastestMilestones(List<Match> matches, {String? tournamentId}) {
  final fifties = <Milestone>[];
  final hundreds = <Milestone>[];
  for (final m in matches) {
    if (tournamentId != null && m.tournamentId != tournamentId) continue;
    if (m.status != 'completed') continue;
    for (final inn in m.innings) {
      final ballsMap = <String, int>{};
      final runsMap = <String, int>{};
      final fiftyDone = <String>{};
      final hundredDone = <String>{};
      for (final ev in inn.events) {
        final s = ev.strikerId;
        if (ev.extraType == 'wide') continue;
        ballsMap[s] = (ballsMap[s] ?? 0) + 1;
        // Only runs off the bat count toward milestones (not byes/leg-byes).
        final r = (ev.extraType == 'bye' || ev.extraType == 'legBye')
            ? 0
            : ev.batRuns;
        runsMap[s] = (runsMap[s] ?? 0) + r;
        final runs = runsMap[s]!;
        final balls = ballsMap[s]!;
        if (runs >= 50 && fiftyDone.add(s)) {
          fifties.add(Milestone(s, balls, runs));
        }
        if (runs >= 100 && hundredDone.add(s)) {
          hundreds.add(Milestone(s, balls, runs));
        }
      }
    }
  }
  fifties.sort((a, b) => a.balls.compareTo(b.balls));
  hundreds.sort((a, b) => a.balls.compareTo(b.balls));
  return FastestResult(fifties, hundreds);
}

/// Most sixes / most fours in a single innings (one row per innings).
class InningsBest {
  String playerId;
  int count;
  int runs;
  InningsBest(this.playerId, this.count, this.runs);
}

class InningsPowerLeaders {
  List<InningsBest> sixes;
  List<InningsBest> fours;
  InningsPowerLeaders(this.sixes, this.fours);
}

InningsPowerLeaders inningsPowerLeaders(
  List<Match> matches, {
  String? tournamentId,
}) {
  final sixes = <InningsBest>[];
  final fours = <InningsBest>[];
  for (final m in matches) {
    if (tournamentId != null && m.tournamentId != tournamentId) continue;
    if (m.status != 'completed') continue;
    for (final inn in m.innings) {
      inn.batting.forEach((pid, fig) {
        if (!fig.batted) return;
        if (fig.sixes > 0) sixes.add(InningsBest(pid, fig.sixes, fig.runs));
        if (fig.fours > 0) fours.add(InningsBest(pid, fig.fours, fig.runs));
      });
    }
  }
  sixes.sort((a, b) => b.count.compareTo(a.count));
  fours.sort((a, b) => b.count.compareTo(a.count));
  return InningsPowerLeaders(sixes, fours);
}

/// Best partnerships in a set of matches (one row per partnership).
class PartnershipBest {
  String batter1Id;
  String batter2Id;
  int runs;
  int balls;
  PartnershipBest(this.batter1Id, this.batter2Id, this.runs, this.balls);
}

List<PartnershipBest> bestPartnerships(
  List<Match> matches, {
  String? tournamentId,
}) {
  final out = <PartnershipBest>[];
  for (final m in matches) {
    if (tournamentId != null && m.tournamentId != tournamentId) continue;
    if (m.status != 'completed') continue;
    for (final inn in m.innings) {
      for (final p in partnerships(inn)) {
        out.add(PartnershipBest(p.batter1Id, p.batter2Id, p.runs, p.balls));
      }
    }
  }
  out.sort((a, b) => b.runs.compareTo(a.runs));
  return out;
}

/// Plain-text scorecard summary (for clipboard export).
String scorecardText(
  Match m,
  String Function(String id) nameOf,
  String Function(String teamId) teamName,
) {
  final buf = StringBuffer();
  buf.writeln(
    '${teamName(m.teamAId)} vs ${teamName(m.teamBId)} — ${m.oversLimit} overs',
  );
  if (m.venue.isNotEmpty) buf.writeln('Venue: ${m.venue}');
  if (m.dateIso.isNotEmpty) buf.writeln('Date: ${m.dateIso}');
  buf.writeln(
    'Toss: ${teamName(m.tossWinnerId)} chose to ${m.tossDecision} first',
  );
  for (var idx = 0; idx < m.innings.length; idx++) {
    final inn = m.innings[idx];
    buf.writeln('');
    buf.writeln(
      '${teamName(inn.battingTeamId)} innings: ${inn.totalRuns}/${inn.wickets} '
      '(${oversText(inn.legalBalls, inn.ballsPerOver)} ov)',
    );
    final batters = inn.battingXI.where(
      (id) => inn.batting[id]?.batted ?? false,
    );
    for (final pid in batters) {
      final f = inn.batting[pid]!;
      final how = f.out ? resolveHowOut(f.howOut, nameOf) : 'not out';
      buf.writeln(
        '  ${nameOf(pid)}  $how  ${f.runs} (${f.balls}b, ${f.fours}x4, ${f.sixes}x6)',
      );
    }
    final dnb = inn.battingXI
        .where((id) => !(inn.batting[id]?.batted ?? false))
        .map(nameOf)
        .toList();
    if (dnb.isNotEmpty) buf.writeln('  Did not bat: ${dnb.join(', ')}');
    buf.writeln(
      '  Extras: ${inn.extrasTotal} (wd ${inn.widesRuns}, nb ${inn.noBallRuns}, b ${inn.byeRuns}, lb ${inn.legByeRuns})',
    );
    for (final pid in inn.bowling.keys) {
      final f = inn.bowling[pid]!;
      if (f.legalBalls == 0 && f.wides == 0 && f.noBalls == 0) continue;
      buf.writeln(
        '  Bowling: ${nameOf(pid)}  ${oversText(f.legalBalls, inn.ballsPerOver)}-${f.maidens}-${f.runs}-${f.wickets}',
      );
    }
    if (inn.fallOfWickets.isNotEmpty) {
      buf.writeln(
        '  FoW: ${inn.fallOfWickets.map((w) => '${w.runs}-${w.wicketNo} (${nameOf(w.playerId)}, ${w.overText})').join(', ')}',
      );
    }
  }
  if (m.resultText.isNotEmpty) {
    buf.writeln('');
    buf.writeln('Result: ${m.resultText}');
  }
  return buf.toString();
}
