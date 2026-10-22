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
      // A side can never lose more than XI − 1 wickets in standard
      // play (10 with a full XI — the last pair is at the crease and
      // one batter must remain not out). The old setup offered an
      // impossible "11 wickets" option; clamp any explicit setting
      // to the legal maximum so the innings ends all-out at 10 and
      // a chase won with 2 wickets down reads "won by 8 wickets"
      // (10 − 2), never 9 (v1.3.4).
      final cap = inn.battingXI.length - 1;
      inn.maxWickets =
          (cap >= 1 && m.totalWickets > cap) ? cap : m.totalWickets;
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

// ---------------- Crease corrections (v1.3.4) ----------------

/// Move the strike to [playerId] (scoring screen: single tap on a
/// batsman's name). Only the non-striker can take the strike this
/// way — tapping the striker himself, or anyone not at the crease,
/// changes nothing. Returns true when the strike actually changed.
bool setStrikeTo(InningsState s, String playerId) {
  if (playerId.isEmpty) return false;
  if (playerId == s.strikerId) return false;
  if (playerId != s.nonStrikerId) return false;
  if (s.strikerId.isEmpty) return false;
  final tmp = s.strikerId;
  s.strikerId = s.nonStrikerId;
  s.nonStrikerId = tmp;
  return true;
}

/// Players who may replace the batsman [outId] at the crease
/// (scoring screen: double tap on a batsman's name — the user's
/// case: the wrong opener was selected). Only XI members who have
/// not batted yet and are not already at the crease qualify: the
/// incoming player takes over the outgoing player's place at the
/// crease and, if play already started under the wrong name, his
/// recorded figure too (a scorebook name correction).
List<String> replaceBatsmanCandidates(InningsState s, String outId) {
  if (outId != s.strikerId && outId != s.nonStrikerId) return const [];
  final outFig = s.batting[outId];
  if (outFig != null && outFig.out) return const [];
  return s.battingXI.where((id) {
    if (id == s.strikerId || id == s.nonStrikerId) return false;
    final f = s.batting[id];
    if (f != null && (f.batted || f.out)) return false;
    return true;
  }).toList();
}

/// Replace the batsman [outId] at the crease with [inId] (see
/// [replaceBatsmanCandidates]). Any balls already recorded under
/// the wrong name are re-credited to [inId]: the events, the
/// batting figure and the fall-of-wickets list all follow, so the
/// scorecard and the statistics stay consistent. Returns false
/// when the replacement is not a legal candidate.
bool replaceBatsman(InningsState s, String outId, String inId) {
  if (inId == outId) return false;
  if (!replaceBatsmanCandidates(s, outId).contains(inId)) return false;
  if (s.strikerId == outId) {
    s.strikerId = inId;
  } else {
    s.nonStrikerId = inId;
  }
  final fig = s.batting.remove(outId) ?? BatFig();
  fig.batted = true;
  s.batting[inId] = fig;
  for (final ev in s.events) {
    if (ev.strikerId == outId) ev.strikerId = inId;
    if (ev.nonStrikerId == outId) ev.nonStrikerId = inId;
    if (ev.outPlayerId == outId) ev.outPlayerId = inId;
  }
  for (final w in s.fallOfWickets) {
    if (w.playerId == outId) w.playerId = inId;
  }
  return true;
}

// ---------------- Playing XI editing (v1.3.5) ----------------

/// Add [playerId] of [teamId] to the match's playing XI (post-match
/// editor and live scoring both use this). The match XI and every
/// innings' side list gain the player; on the batting side an empty
/// did-not-bat figure row is created so the scorecard's "did not
/// bat" list and the editor show him right away. The default XI is
/// 11 players, but an XI edit never changes the 10-wicket rule —
/// maxWickets is not touched here.
void addToMatchXI(Match m, String teamId, String playerId) {
  if (playerId.isEmpty) return;
  // Lists are replaced rather than mutated in place, so a XI list
  // that happens to be unmodifiable can never throw here.
  if (teamId == m.teamAId) {
    if (!m.xiA.contains(playerId)) m.xiA = [...m.xiA, playerId];
  } else {
    if (!m.xiB.contains(playerId)) m.xiB = [...m.xiB, playerId];
  }
  for (final inn in m.innings) {
    if (inn.battingTeamId == teamId) {
      if (!inn.battingXI.contains(playerId)) {
        inn.battingXI = [...inn.battingXI, playerId];
      }
      inn.batting.putIfAbsent(playerId, () => BatFig());
    }
    if (inn.bowlingTeamId == teamId) {
      if (!inn.bowlingXI.contains(playerId)) {
        inn.bowlingXI = [...inn.bowlingXI, playerId];
      }
    }
  }
}

/// Remove [playerId] of [teamId] from the match's playing XI,
/// together with his batting and bowling figures in this match
/// (post-match editor semantics: the corrected record is the truth,
/// and every derived view recomputes from it). Ball events keep
/// their recorded ids — they are history — but the figure rows, the
/// XI lists and any live crease/bowler references to the player
/// are cleared.
void removeFromMatchXI(Match m, String teamId, String playerId) {
  List<String> without(List<String> xi) =>
      xi.where((id) => id != playerId).toList();
  if (teamId == m.teamAId) {
    m.xiA = without(m.xiA);
  } else {
    m.xiB = without(m.xiB);
  }
  for (final inn in m.innings) {
    if (inn.battingTeamId == teamId) {
      inn.battingXI = without(inn.battingXI);
      inn.batting.remove(playerId);
      if (inn.strikerId == playerId) inn.strikerId = '';
      if (inn.nonStrikerId == playerId) inn.nonStrikerId = '';
    }
    if (inn.bowlingTeamId == teamId) {
      inn.bowlingXI = without(inn.bowlingXI);
      inn.bowling.remove(playerId);
      if (inn.currentBowlerId == playerId) inn.currentBowlerId = '';
      if (inn.lastBowlerId == playerId) inn.lastBowlerId = '';
    }
  }
}

/// Why [playerId] may not be removed from the XI of a LIVE match
/// (null = removal allowed): the two batters at the crease and the
/// current bowler are locked, and a player who has already batted
/// or bowled in this match has figures that are part of the record.
String? liveXiRemovalBlock(Match m, InningsState inn, String playerId) {
  if (playerId == inn.strikerId) {
    return 'The striker cannot be removed from the Playing XI.';
  }
  if (playerId == inn.nonStrikerId) {
    return 'The non-striker cannot be removed from the Playing XI.';
  }
  if (playerId == inn.currentBowlerId) {
    return 'The current bowler cannot be removed from the Playing XI.';
  }
  for (final i in m.innings) {
    final bf = i.batting[playerId];
    if (bf != null && bf.batted) {
      return 'This player has already batted in this match.';
    }
    final bw = i.bowling[playerId];
    if (bw != null && bw.legalBalls > 0) {
      return 'This player has already bowled in this match.';
    }
  }
  return null;
}

// ---------------- Post-match scorecard editing (v1.3.4) ----------------

/// Recompute an innings' headline numbers from its stored figures
/// after a post-match edit: total = batting runs + extras, wickets
/// = batters marked out, legal balls = the bowlers' legal balls
/// (wide/no-ball delivery counters follow the bowler figures too).
/// Everything downstream — result text, points table, NRR, career
/// statistics — is computed from these stored numbers at read time,
/// so one corrected figure propagates everywhere on its own.
void recomputeInningsTotals(InningsState inn) {
  var batRuns = 0;
  var wkts = 0;
  for (final f in inn.batting.values) {
    if (!f.batted) continue;
    batRuns += f.runs;
    if (f.out) wkts++;
  }
  inn.totalRuns = batRuns + inn.extrasTotal;
  inn.wickets = wkts;
  var legal = 0;
  var wides = 0;
  var noBalls = 0;
  for (final f in inn.bowling.values) {
    legal += f.legalBalls;
    wides += f.wides;
    noBalls += f.noBalls;
  }
  inn.legalBalls = legal;
  inn.wideCount = wides;
  inn.noBallCount = noBalls;
}

/// Rewrite player ids in an innings' ball events (and the related
/// state) through [map] in a single pass, so a swap (A→B, B→A)
/// cannot collide. [battingSide] selects which id fields belong
/// to the side being corrected.
void _remapEventIds(
  InningsState inn,
  Map<String, String> map, {
  required bool battingSide,
}) {
  String r(String id) => map[id] ?? id;
  for (final ev in inn.events) {
    if (battingSide) {
      ev.strikerId = r(ev.strikerId);
      ev.nonStrikerId = r(ev.nonStrikerId);
      ev.outPlayerId = r(ev.outPlayerId);
    } else {
      ev.bowlerId = r(ev.bowlerId);
      ev.fielderId = r(ev.fielderId);
    }
  }
  if (battingSide) {
    for (final w in inn.fallOfWickets) {
      w.playerId = r(w.playerId);
    }
    inn.strikerId = r(inn.strikerId);
    inn.nonStrikerId = r(inn.nonStrikerId);
  } else {
    inn.currentBowlerId = r(inn.currentBowlerId);
    inn.lastBowlerId = r(inn.lastBowlerId);
    // Dismissal texts credit the bowler/fielder by id token.
    for (final f in inn.batting.values) {
      if (f.howOut.isNotEmpty) f.howOut = _remapHowOut(f.howOut, map);
    }
  }
}

/// Rewrite the id tokens inside a dismissal text (`'c <id> b <id>'`,
/// `'run out (<id>)'`) through [map].
String _remapHowOut(String howOut, Map<String, String> map) {
  final parts = howOut.split(' ');
  for (var i = 0; i < parts.length; i++) {
    final p = parts[i];
    if (p.startsWith('(') && p.endsWith(')')) {
      final inner = p.substring(1, p.length - 1);
      final mapped = map[inner];
      if (mapped != null) parts[i] = '($mapped)';
    } else if (map.containsKey(p)) {
      parts[i] = map[p]!;
    }
  }
  return parts.join(' ');
}

/// Post-match name correction (batting): move [fromId]'s batting
/// figure in this innings to [toId] — or swap the two figures when
/// both players batted — re-crediting the ball events with it, so
/// the scorecard, career stats and milestones all follow the name.
/// [toId] must belong to the innings' batting XI. Returns false
/// when there is no batted figure to move.
bool remapBattingFigure(InningsState inn, String fromId, String toId) {
  if (fromId == toId) return false;
  if (!inn.battingXI.contains(toId)) return false;
  final fromFig = inn.batting[fromId];
  if (fromFig == null || !fromFig.batted) return false;
  final toFig = inn.batting[toId];
  if (toFig != null && toFig.batted) {
    inn.batting[toId] = fromFig;
    inn.batting[fromId] = toFig;
    _remapEventIds(inn, {fromId: toId, toId: fromId},
        battingSide: true);
  } else {
    inn.batting.remove(fromId);
    inn.batting[toId] = fromFig;
    _remapEventIds(inn, {fromId: toId}, battingSide: true);
  }
  return true;
}

/// Post-match name correction (bowling): move or swap [fromId]'s
/// bowling figure in this innings, re-crediting the ball events
/// and the dismissal texts that name the bowler/fielder. [toId]
/// must belong to the innings' bowling XI.
bool remapBowlingFigure(InningsState inn, String fromId, String toId) {
  if (fromId == toId) return false;
  if (!inn.bowlingXI.contains(toId)) return false;
  final fromFig = inn.bowling[fromId];
  if (fromFig == null) return false;
  final toFig = inn.bowling[toId];
  if (toFig != null) {
    inn.bowling[toId] = fromFig;
    inn.bowling[fromId] = toFig;
    _remapEventIds(inn, {fromId: toId, toId: fromId},
        battingSide: false);
  } else {
    inn.bowling.remove(fromId);
    inn.bowling[toId] = fromFig;
    _remapEventIds(inn, {fromId: toId}, battingSide: false);
  }
  return true;
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
      // Dismissals the ball events do not cover (v1.3.5): figure-only
      // records (e.g. a scorecard rebuilt from its figures) carry the
      // dismissal in the batting figure's howOut text instead of in
      // deliveries. Credit the fielder from the stored token form so
      // Most Catches / Most Stumpings are never empty while catches
      // exist in the record. Dismissals already credited above (the
      // out player appears as a wicket event's outPlayerId) are
      // skipped, so a dismissal is never counted twice.
      final coveredOut = <String>{
        for (final ev in inn.events)
          if (ev.isWicket && ev.outPlayerId.isNotEmpty) ev.outPlayerId,
      };
      inn.batting.forEach((pid, fig) {
        if (!fig.out || coveredOut.contains(pid)) return;
        final credit = fielderCreditFromHowOut(fig.howOut);
        if (credit == null) return;
        final c = get(credit.$2);
        switch (credit.$1) {
          case 'caught':
            c.catches++;
          case 'stumped':
            c.stumpings++;
          case 'runOut':
            c.runOuts++;
        }
      });
    }
  }
  return map;
}

/// Fielder credit parsed from a stored dismissal text (v1.3.5):
/// returns (kind, fielderId) for the token forms written by
/// [howOutText] — `'c <id> b <id>'`, `'st <id> b <id>'` and
/// `'run out (<id>)'` — or null when the text carries no creditable
/// fielder. Only tokens that look like stored player ids count:
/// a dismissal retyped with plain names ("c Ahmed b Bilal") has no
/// id to credit, and guessing would create phantom players.
(String, String)? fielderCreditFromHowOut(String howOut) {
  final t = howOut.trim();
  if (t.isEmpty) return null;
  if (t.startsWith('run out (')) {
    final end = t.indexOf(')', 9);
    if (end > 9) {
      final id = t.substring(9, end);
      if (_looksLikePlayerId(id)) return ('runOut', id);
    }
    return null;
  }
  final parts = t.split(' ');
  if (parts.length >= 4 && parts[2] == 'b') {
    if (parts[0] == 'c' && _looksLikePlayerId(parts[1])) {
      return ('caught', parts[1]);
    }
    if (parts[0] == 'st' && _looksLikePlayerId(parts[1])) {
      return ('stumped', parts[1]);
    }
  }
  return null;
}

/// Stored player ids are machine-generated (`prefix_<digits>_...`):
/// long and digit-bearing. A bare name token never qualifies.
bool _looksLikePlayerId(String token) =>
    token.length >= 8 && token.contains(RegExp(r'[0-9]'));

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

/// All shots in an innings across every batter — for the "Whole Team"
/// wagon wheel view.
List<ShotPlot> wagonWheelShotsTeam(InningsState inn) {
  final list = <ShotPlot>[];
  for (final ev in inn.events) {
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
  if (inn.events.isNotEmpty) {
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
  // Figure-only records (v1.3.5): no deliveries were stored, so the
  // stands are rebuilt from the fall-of-wicket scores and the
  // batting order in the figures — a match-winning stand must show
  // in Best Partnerships even when its balls were never recorded.
  return _partnershipsFromFallOfWickets(inn);
}

/// Partnership derivation for innings without ball events: each
/// fall of wickets closes a stand (runs = team score at the fall
/// minus the score at the previous fall; balls = legal balls bowled
/// by then, read from the fall's over text), the surviving batter
/// continues with the next player in batting order, and the final
/// unbroken stand runs to the innings total.
List<Partnership> _partnershipsFromFallOfWickets(InningsState inn) {
  final order = <String>[
    for (final e in inn.batting.entries)
      if (e.value.batted) e.key,
  ];
  if (order.length < 2) return const [];
  int legalAt(String overText) {
    final parts = overText.split('.');
    final o = int.tryParse(parts.first) ?? 0;
    final b = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return o * inn.ballsPerOver + b;
  }

  final falls = [...inn.fallOfWickets]
    ..sort((a, b) => a.wicketNo.compareTo(b.wicketNo));
  final out = <Partnership>[];
  var pair = Partnership(order[0], order[1]);
  var nextIdx = 2;
  var prevRuns = 0;
  var prevBalls = 0;
  final dismissed = <String>{};
  for (final f in falls) {
    final balls = legalAt(f.overText);
    final r = f.runs - prevRuns;
    final b = balls - prevBalls;
    pair.runs = r < 0 ? 0 : r;
    pair.balls = b < 0 ? 0 : b;
    out.add(pair);
    dismissed.add(f.playerId);
    prevRuns = f.runs;
    prevBalls = balls;
    final survivor =
        pair.batter1Id == f.playerId ? pair.batter2Id : pair.batter1Id;
    String? next;
    while (nextIdx < order.length) {
      final cand = order[nextIdx++];
      if (cand != survivor && !dismissed.contains(cand)) {
        next = cand;
        break;
      }
    }
    if (next == null) {
      pair = Partnership('', '');
      break;
    }
    pair = Partnership(survivor, next);
  }
  if (pair.batter1Id.isNotEmpty) {
    final runs = inn.totalRuns - prevRuns;
    final balls = inn.legalBalls - prevBalls;
    if (runs > 0 || balls > 0) {
      pair.runs = runs < 0 ? 0 : runs;
      pair.balls = balls < 0 ? 0 : balls;
      pair.unbroken = true;
      out.add(pair);
    }
  }
  return out;
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
      // Figure fallback (v1.3.5): an innings whose deliveries were
      // never stored (or were lost) still proves its milestones
      // through the batting figures — a 50/100 must appear in
      // Fastest Fifty / Hundred with the figure's balls faced
      // instead of the card sitting empty. The delivery-derived
      // entry, when one exists, stays the more precise one.
      inn.batting.forEach((pid, fig) {
        if (!fig.batted) return;
        if (fig.runs >= 50 && !fiftyDone.contains(pid)) {
          fifties.add(Milestone(pid, fig.balls, fig.runs));
        }
        if (fig.runs >= 100 && !hundredDone.contains(pid)) {
          hundreds.add(Milestone(pid, fig.balls, fig.runs));
        }
      });
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
  // Longest partnership on top (v1.3.5): most runs first; for equal
  // runs the stand that lasted more balls ranks higher.
  out.sort((a, b) {
    final r = b.runs.compareTo(a.runs);
    if (r != 0) return r;
    return b.balls.compareTo(a.balls);
  });
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
