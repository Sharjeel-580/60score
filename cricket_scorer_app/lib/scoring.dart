// Pure-Dart scoring engine + statistics for CricScore Offline.
// No Flutter imports: everything here is unit-testable.
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

/// Push one undo reverse step, keeping the in-memory history bounded
/// to the last 50 steps (v1.4.4 light version). The step is the
/// innings state BEFORE the action about to run: scalars, copies of
/// the batting/bowling figure maps, and the pre-action event / fall
/// lengths. It never serializes the innings and never stores the
/// event list, so a step's size is bounded by squad size and stays
/// constant no matter how long the innings runs — the old full
/// snapshot string stack (which grew with every ball) is gone.
/// The stack is never persisted (see InningsState.toJson), so undo
/// still works within a session; only restart-persistent undo is
/// lost (unchanged from v1.4.3).
void _pushUndo(InningsState s) {
  s.undoStack.add(UndoStep(
    totalRuns: s.totalRuns,
    wickets: s.wickets,
    legalBalls: s.legalBalls,
    strikerId: s.strikerId,
    nonStrikerId: s.nonStrikerId,
    currentBowlerId: s.currentBowlerId,
    lastBowlerId: s.lastBowlerId,
    awaitingBatter: s.awaitingBatter,
    awaitingBowler: s.awaitingBowler,
    batting: {for (final e in s.batting.entries) e.key: e.value.copy()},
    bowling: {for (final e in s.bowling.entries) e.key: e.value.copy()},
    widesRuns: s.widesRuns,
    noBallRuns: s.noBallRuns,
    byeRuns: s.byeRuns,
    legByeRuns: s.legByeRuns,
    noBallCount: s.noBallCount,
    wideCount: s.wideCount,
    eventsLength: s.events.length,
    fallOfWicketsLength: s.fallOfWickets.length,
    currentOverBowlerRuns: s.currentOverBowlerRuns,
    currentOverTeamRuns: s.currentOverTeamRuns,
    target: s.target,
    maxWickets: s.maxWickets,
    widePenalty: s.widePenalty,
    noBallPenalty: s.noBallPenalty,
  ));
  if (s.undoStack.length > 50) {
    s.undoStack.removeRange(0, s.undoStack.length - 50);
  }
}

/// Apply a stored reverse step: restore the pre-action scalars and
/// figure maps, and truncate the event / fall lists back to their
/// pre-action lengths. The step is consumed (it was already removed
/// from the stack), so its maps become the live maps — no aliasing
/// survives into another step.
void _restoreStep(InningsState s, UndoStep step) {
  s.totalRuns = step.totalRuns;
  s.wickets = step.wickets;
  s.legalBalls = step.legalBalls;
  s.strikerId = step.strikerId;
  s.nonStrikerId = step.nonStrikerId;
  s.currentBowlerId = step.currentBowlerId;
  s.lastBowlerId = step.lastBowlerId;
  s.awaitingBatter = step.awaitingBatter;
  s.awaitingBowler = step.awaitingBowler;
  s.batting = step.batting;
  s.bowling = step.bowling;
  s.widesRuns = step.widesRuns;
  s.noBallRuns = step.noBallRuns;
  s.byeRuns = step.byeRuns;
  s.legByeRuns = step.legByeRuns;
  s.noBallCount = step.noBallCount;
  s.wideCount = step.wideCount;
  if (s.events.length > step.eventsLength) {
    s.events.removeRange(step.eventsLength, s.events.length);
  }
  if (s.fallOfWickets.length > step.fallOfWicketsLength) {
    s.fallOfWickets.removeRange(
        step.fallOfWicketsLength, s.fallOfWickets.length);
  }
  s.currentOverBowlerRuns = step.currentOverBowlerRuns;
  s.currentOverTeamRuns = step.currentOverTeamRuns;
  s.maxWickets = step.maxWickets;
  s.widePenalty = step.widePenalty;
  s.noBallPenalty = step.noBallPenalty;
  s.target = step.target;
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
  final fig = s.batting.putIfAbsent(playerId, () => BatFig());
  fig.batted = true;
  // A batsman who retired hurt and now resumes: the retired-hurt
  // marker is cleared so a later dismissal (or the innings ending)
  // reads correctly; his figure keeps accumulating in the same row.
  if (!fig.out && fig.howOut == 'retired hurt') fig.howOut = '';
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
  // No-ball law (v1.4.5): on a no-ball the batter can only be out
  // run out (plus retired out / obstructing the field, which the
  // code already supports as dismissals). Any other dismissal on a
  // no-ball is rejected outright — the ball is not recorded and no
  // undo step is pushed. The main UI only ever offers Run Out on a
  // no-ball; this guards every other entry path the same way.
  if (input.extraType == 'noBall' &&
      input.isWicket &&
      input.wicketType != 'runOut' &&
      input.wicketType != 'retiredOut' &&
      input.wicketType != 'obstructing') {
    return false;
  }
  _pushUndo(s);

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

  // Mankad: the bowler himself effects the run-out, so he is the
  // fielder of record regardless of what the dialog passed.
  final effectiveFielderId = (input.isWicket && input.wicketType == 'mankad')
      ? bowlerId
      : input.fielderId;
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
    fielderId: effectiveFielderId,
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
    // Bowler credit ONLY for bowled / caught / lbw / stumped /
    // hitWicket. Run out, mankad, retired out, obstructing the
    // field, hit the ball twice and timed out are team wickets
    // with no bowler credit (full dismissal set).
    if (bowlerGetsWicketCredit(input.wicketType)) bowl.wickets++;
    final outId = ev.outPlayerId;
    final outFig = s.batting.putIfAbsent(outId, () => BatFig());
    outFig.batted = true;
    outFig.out = true;
    outFig.howOut =
        howOutText(input.wicketType, bowlerId, effectiveFielderId);
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
  final step = s.undoStack.removeLast();
  _restoreStep(s, step);
  return true;
}

/// Per-ball edit replay (v1.4.5, M4b): rebuilds an innings from a
/// ball list by re-applying every ball through [applyBall], forcing
/// each ball's recorded striker / non-striker / bowler context
/// first (so wickets, strike rotation and over changes replay
/// exactly as scored — [applyBall] never refuses on awaiting
/// flags, it only needs the context set).
///
/// Returns a NEW innings on success, or null (leaving the original
/// untouched) when any ball is rejected: an illegal dismissal on a
/// no-ball, or an edited sequence that completes the innings before
/// the last recorded ball (target / wickets reached early — the
/// edit contradicts the recorded history, so it is refused rather
/// than silently dropping balls).
///
/// Preserved across replay: XIs, limits, penalties, target,
/// [endedEarly], and retired-hurt markers (those are not ball
/// events, so they are carried over from the original figures).
/// Wagon-wheel points are carried back onto the regenerated events
/// in order (replay regenerates events, so zone/shotX/shotY would
/// otherwise be lost). The undo stack is cleared — the edit
/// invalidates pre-edit undo steps, same rule as scorecard edits.
InningsState? replayInningsBalls(InningsState inn, List<BallEvent> events) {
  final out = InningsState(
    battingTeamId: inn.battingTeamId,
    bowlingTeamId: inn.bowlingTeamId,
    battingXI: List.of(inn.battingXI),
    bowlingXI: List.of(inn.bowlingXI),
    oversLimit: inn.oversLimit,
    ballsPerOver: inn.ballsPerOver,
  );
  out.target = inn.target;
  out.maxWickets = inn.maxWickets;
  out.widePenalty = inn.widePenalty;
  out.noBallPenalty = inn.noBallPenalty;
  out.endedEarly = inn.endedEarly;
  for (final e in events) {
    out.strikerId = e.strikerId;
    out.nonStrikerId = e.nonStrikerId;
    out.currentBowlerId = e.bowlerId;
    final ok = applyBall(
      out,
      BallInput(
        extraType: e.extraType,
        batRuns: e.batRuns,
        extraRuns: e.extraRuns,
        isWicket: e.isWicket,
        wicketType: e.wicketType,
        outPlayerId: e.outPlayerId,
        fielderId: e.fielderId,
        zone: e.zone,
        shotX: e.shotX,
        shotY: e.shotY,
      ),
    );
    if (!ok) return null;
  }
  if (out.events.length == events.length) {
    for (var i = 0; i < events.length; i++) {
      out.events[i].zone = events[i].zone;
      out.events[i].shotX = events[i].shotX;
      out.events[i].shotY = events[i].shotY;
    }
  }
  // Retired-hurt markers are not ball events: carry them over from
  // the original figures (only onto figures that replayed not-out;
  // a retired-hurt batter who never faced a ball in the replayed
  // sequence still gets his marker figure, as in the original).
  for (final entry in inn.batting.entries) {
    if (entry.value.howOut == 'retired hurt') {
      final fig = out.batting.putIfAbsent(entry.key, () => BatFig());
      if (!fig.out) {
        fig.batted = true;
        fig.howOut = 'retired hurt';
      }
    }
  }
  out.undoStack = [];
  return out;
}

// ---------------- Full dismissal set: non-ball actions ----------------

/// Retire a batsman HURT (not a dismissal): he leaves the crease,
/// his figure stays NOT out with the marker howOut = 'retired hurt',
/// no wicket falls and no ball is recorded. He may resume later —
/// [setNextBatter] clears the marker when he comes back in, and his
/// runs keep accumulating in the same figure. If the innings ends
/// while he is retired hurt he simply counts as not out.
/// Only a batsman currently at the crease can retire hurt.
/// Pushes an undo reverse step, so Undo reverses the retirement.
bool retireBatsmanHurt(InningsState s, String playerId) {
  if (s.isComplete) return false;
  if (playerId.isEmpty) return false;
  if (playerId != s.strikerId && playerId != s.nonStrikerId) return false;
  final fig = s.batting[playerId];
  if (fig == null || fig.out) return false;
  _pushUndo(s);
  fig.batted = true;
  fig.out = false;
  fig.howOut = 'retired hurt';
  if (s.strikerId == playerId) s.strikerId = '';
  if (s.nonStrikerId == playerId) s.nonStrikerId = '';
  s.awaitingBatter = true;
  return true;
}

/// Dismiss a batsman WITHOUT a ball being bowled (between balls):
/// - 'timedOut': [playerId] has not come in yet (an XI member who
///   has not batted). He is marked batted, out, 0 balls.
/// - 'retiredOut': [playerId] is at the crease and retires out;
///   unlike retired hurt he cannot return in this innings.
/// In both cases the team loses a wicket, no bowler is credited,
/// legalBalls is unchanged, and a FallOfWicket entry IS added at
/// the current score / over so the scorecard's FoW list stays
/// consistent with the wicket count (the partnerships derivation
/// tolerates it: event-based partnerships are unaffected because
/// no ball event is added, and the FoW-based fallback treats it
/// like any other fall). Pushes an undo reverse step.
bool dismissBatsmanWithoutBall(
  InningsState s,
  String playerId,
  String wicketType,
) {
  if (wicketType != 'timedOut' && wicketType != 'retiredOut') return false;
  if (s.isComplete) return false;
  if (playerId.isEmpty) return false;
  if (!s.battingXI.contains(playerId)) return false;
  final existing = s.batting[playerId];
  if (existing != null && existing.out) return false;
  final atCrease = playerId == s.strikerId || playerId == s.nonStrikerId;
  if (wicketType == 'timedOut') {
    // Timed out applies to a batsman who has not come in yet.
    if (atCrease) return false;
    if (existing != null && existing.batted) return false;
  } else {
    // Retired out applies to a batsman at the crease.
    if (!atCrease) return false;
  }
  _pushUndo(s);
  s.wickets++;
  final fig = s.batting.putIfAbsent(playerId, () => BatFig());
  fig.batted = true;
  fig.out = true;
  fig.howOut = howOutText(wicketType, '', '');
  s.fallOfWickets.add(
    FallOfWicket(
      s.wickets,
      s.totalRuns,
      oversText(s.legalBalls, s.ballsPerOver),
      playerId,
    ),
  );
  if (atCrease) {
    if (s.strikerId == playerId) s.strikerId = '';
    if (s.nonStrikerId == playerId) s.nonStrikerId = '';
  }
  if (s.wickets >= s.effectiveMaxWickets || s.isComplete) {
    s.awaitingBatter = false;
  } else if (atCrease) {
    s.awaitingBatter = true;
  }
  return true;
}

/// Wicket types for which the bowler is credited with the wicket.
/// Every other dismissal (runOut, mankad, retiredOut, obstructing,
/// hitTwice, timedOut) counts against the team but not the bowler.
bool bowlerGetsWicketCredit(String wicketType) =>
    const {'bowled', 'caught', 'lbw', 'stumped', 'hitWicket'}
        .contains(wicketType);

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
    case 'mankad':
      // Distinct from a plain run out on the scorecard:
      // 'Mankad (<bowlerId>)'. The bowler effects the dismissal,
      // so the fielder token is the bowler (fielderId falls back
      // to bowlerId when the dialog did not supply one).
      final fid = fielderId.isNotEmpty ? fielderId : bowlerId;
      return fid.isEmpty ? 'Mankad' : 'Mankad ($fid)';
    case 'retiredOut':
      return 'retired out';
    case 'obstructing':
      return 'obstructing the field';
    case 'hitTwice':
      return 'hit the ball twice';
    case 'timedOut':
      return 'timed out';
    default:
      return type;
  }
}

/// The dismissal / status text for a batting figure on a scorecard:
/// the resolved dismissal when out, 'retired hurt' for a not-out
/// figure carrying that marker, otherwise 'not out'.
String batFigStatusText(
  BatFig f,
  String Function(String id) nameOf,
) {
  if (f.out) return resolveHowOut(f.howOut, nameOf);
  if (f.howOut == 'retired hurt') return 'retired hurt';
  return 'not out';
}

/// Human-readable dismissal by resolving ids via [nameOf].
String resolveHowOut(String howOut, String Function(String id) nameOf) {
  if (howOut == '') return '';
  var out = howOut;
  // Replace whole-word id tokens. Plain dismissal words (including
  // the full-dismissal-set texts: 'obstructing the field', 'hit the
  // ball twice', 'retired out / hurt', 'timed out', 'Mankad') are
  // never player ids and must pass through untouched — a nameOf
  // fallback could otherwise rewrite a long word (e.g. a store
  // lookup turns an unknown long token into 'Player').
  const plainWords = {
    'bowled',
    'wicket',
    'retired',
    'obstructing',
    'field',
    'twice',
    'timed',
    'mankad',
    'hurt',
  };
  final parts = out.split(' ');
  for (var i = 0; i < parts.length; i++) {
    final p = parts[i];
    final clean = p.replaceAll('(', '').replaceAll(')', '');
    if (clean.length > 6 && !plainWords.contains(clean.toLowerCase())) {
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
      // (10 − 2), never 9 (v1.3.4). v1.3.7: the cap itself is also
      // never above 10, so an over-long stored XI cannot push it
      // back to 11.
      var cap = inn.battingXI.length - 1;
      if (cap > 10) cap = 10;
      inn.maxWickets =
          (cap >= 1 && m.totalWickets > cap) ? cap : m.totalWickets;
    } else if (m.lastManStands) {
      // Simplified last-man-stands: innings can lose every batter
      // (final wicket ends it); the last pair bats on together.
      inn.maxWickets = m.xiFor(battingId).length;
    } else if (inn.battingXI.length > 11) {
      // v1.3.7: Auto (no explicit setting) derives wickets from the
      // XI — XI − 1 — but an over-long stored XI must not resurrect
      // the 11-wicket bug: pin the auto value at 10.
      inn.maxWickets = 10;
    }
    if (m.innings.length == 1 && m.innings.isNotEmpty) {
      inn.target = m.innings[0].totalRuns + 1;
    }
    m.innings.add(inn);
  }
  return m.innings[n - 1];
}

// ---------------- Super Over (Feature 5) ----------------

/// True when the main match is tied: two innings, both complete
/// (or the match already marked completed), with equal totals.
/// Super-over innings are NOT consulted here — a match whose main
/// innings are tied stays "tied" at this level even after a super
/// over decides it (the decision lives in [superOverWinnerId]).
bool matchIsTied(Match m) {
  if (m.innings.length < 2) return false;
  final i1 = m.innings[0];
  final i2 = m.innings[1];
  if (i1.totalRuns != i2.totalRuns) return false;
  return (i1.isComplete && i2.isComplete) || m.status == 'completed';
}

/// Start (or fetch in-progress) super-over innings [n] (1-based)
/// of a tied match. Super-over innings live in
/// [Match.superOverInnings], outside [Match.innings], so NRR,
/// career stats and the main scorecard — all of which iterate
/// `m.innings` only — are untouched by them.
///
/// Format: 1 over ([Match.ballsPerOver] balls), innings ends at
/// 2 wickets ([InningsState.maxWickets] = 2); wide / no-ball
/// penalties are copied from the match settings. The batting XI is
/// the side's full match XI ([Match.xiFor]), and because the
/// innings state is fresh, players dismissed in the main match CAN
/// bat again here. Known simplification: a batsman dismissed in
/// super-over round 1 is NOT barred from round 2 (real rules bar
/// him); rounds share the full XI like round 1 does.
///
/// Batting order: rounds alternate. Round 1 is batted first by the
/// team that batted SECOND in the main match (standard practice);
/// each later round is batted first by the side that batted second
/// in the previous round — i.e. the first-batting side swaps every
/// round. The second innings of a round chases the first innings'
/// total + 1.
InningsState startSuperOverInnings(Match m, int n) {
  while (m.superOverInnings.length < n) {
    final idx = m.superOverInnings.length; // 0-based index being created
    final isFirstOfRound = idx % 2 == 0;
    final String battingId;
    if (isFirstOfRound) {
      // Round number (1-based): odd rounds start with the main
      // match's second-batting side, even rounds with its
      // first-batting side (alternation, see doc above).
      final round = idx ~/ 2 + 1;
      battingId = round % 2 == 1 ? m.battingSecondId : m.battingFirstId;
    } else {
      // Second innings of the round: the other side chases.
      battingId = m.superOverInnings[idx - 1].battingTeamId == m.teamAId
          ? m.teamBId
          : m.teamAId;
    }
    final bowlingId = battingId == m.teamAId ? m.teamBId : m.teamAId;
    final inn = InningsState(
      battingTeamId: battingId,
      bowlingTeamId: bowlingId,
      battingXI: m.xiFor(battingId),
      bowlingXI: m.xiFor(bowlingId),
      oversLimit: 1,
      ballsPerOver: m.ballsPerOver,
    );
    inn.widePenalty = m.widePenalty;
    inn.noBallPenalty = m.noBallPenalty;
    inn.maxWickets = 2;
    if (!isFirstOfRound) {
      inn.target = m.superOverInnings[idx - 1].totalRuns + 1;
    }
    m.superOverInnings.add(inn);
  }
  return m.superOverInnings[n - 1];
}

/// The team that won the super over, or null when no completed
/// round has decided it yet. Rounds are evaluated pairwise
/// (innings 0v1, 2v3, ...): a round decides when its 2nd innings
/// [InningsState.isComplete] — the higher total wins, and a chase
/// that passed its target mid-over is already complete via the
/// target rule. A round whose 2nd innings completes with EQUAL
/// totals is tied and decides nothing. Returns the winner of the
/// LATEST completed round (earlier rounds were tied by
/// construction — play only continues past a tied round).
String? superOverWinnerId(Match m) {
  String? winner;
  for (var r = 0; r + 1 < m.superOverInnings.length; r += 2) {
    final first = m.superOverInnings[r];
    final second = m.superOverInnings[r + 1];
    if (!second.isComplete) continue;
    if (second.totalRuns > first.totalRuns) {
      winner = second.battingTeamId;
    } else if (first.totalRuns > second.totalRuns) {
      winner = first.battingTeamId;
    } else {
      winner = null; // this round tied
    }
  }
  return winner;
}

/// True when at least one full super-over round has been played,
/// every completed round was tied and there is no winner yet —
/// i.e. the tiebreak needs another round. There is no manual
/// override: tied rounds are simply replayed until one decides.
bool superOverNeedsAnotherRound(Match m) {
  if (m.superOverInnings.length < 2) return false;
  if (superOverWinnerId(m) != null) return false;
  var anyCompletedRound = false;
  for (var r = 0; r + 1 < m.superOverInnings.length; r += 2) {
    final first = m.superOverInnings[r];
    final second = m.superOverInnings[r + 1];
    if (!second.isComplete) continue;
    // A completed round with unequal totals would have produced a
    // winner above, so any completed round here was tied.
    if (first.totalRuns != second.totalRuns) return false;
    anyCompletedRound = true;
  }
  return anyCompletedRound;
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
    // Equal totals: a decided super over overrides the plain tie.
    final soWinner = superOverWinnerId(m);
    if (soWinner != null) {
      text = '${teamName(soWinner)} won the Super Over';
    } else if (m.superOverInnings.isNotEmpty) {
      text = 'Match tied (Super Over tied)';
    } else {
      text = 'Match tied';
    }
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
/// Adds [playerId] to the match XI of [teamId] (and to any innings
/// already created for that side). Returns false — changing nothing —
/// when the player is already in the XI or the XI is full: a Playing
/// XI holds at most 11 players (v1.3.7; an over-long XI would push
/// the auto wickets derivation, XI − 1, back to the impossible 11).
bool addToMatchXI(Match m, String teamId, String playerId) {
  if (playerId.isEmpty) return false;
  final current = m.xiFor(teamId);
  if (current.contains(playerId)) return false;
  if (current.length >= 11) return false;
  // Lists are replaced rather than mutated in place, so a XI list
  // that happens to be unmodifiable can never throw here.
  if (teamId == m.teamAId) {
    m.xiA = [...m.xiA, playerId];
  } else {
    m.xiB = [...m.xiB, playerId];
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
  return true;
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

/// Apply fixture-detail edits to an UPCOMING match (v1.3.7 fixture
/// edit): date/time (as one local ISO string), venue, teams, overs,
/// balls per over, title, stage (round), ball type and season.
///
/// Guard rails: this is for fixtures that have not started — the
/// caller only offers it while the match is 'upcoming', so there is
/// no scoring data to corrupt. Changing a team clears that side's
/// saved Playing XI (those players belong to the old team) and a
/// toss recorded against a team that is no longer in the match is
/// cleared too, so the fixture simply goes back through the normal
/// "Do Scoring" setup checks afterwards.
void applyFixtureEdit(
  Match m, {
  required String teamAId,
  required String teamBId,
  required String dateIso,
  required String venue,
  required int oversLimit,
  required int ballsPerOver,
  required String matchTitle,
  required String stage,
  required String ballType,
  required String season,
}) {
  if (teamAId != m.teamAId) {
    m.teamAId = teamAId;
    m.xiA = [];
  }
  if (teamBId != m.teamBId) {
    m.teamBId = teamBId;
    m.xiB = [];
  }
  if (m.tossWinnerId.isNotEmpty &&
      m.tossWinnerId != m.teamAId &&
      m.tossWinnerId != m.teamBId) {
    m.tossWinnerId = '';
  }
  m.dateIso = dateIso;
  m.venue = venue;
  m.oversLimit = oversLimit;
  m.ballsPerOver = ballsPerOver;
  m.matchTitle = matchTitle;
  m.stage = stage;
  m.ballType = ballType;
  m.season = season;
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
  /// Manual NRR override (v1.4.4): when set, [nrr] returns this value
  /// instead of the computed ICC figure. Set only by a row override.
  double? nrrOverride;
  PointsRow(this.teamId);

  /// ICC net run rate (per over): aggregate runs per over scored minus
  /// aggregate runs per over conceded, over the whole tournament.
  double get nrr {
    if (nrrOverride != null) return nrrOverride!;
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

/// Duplicate-fixture safety net (display/computation level only —
/// records on disk are never deleted or merged).
///
/// EXACT RULE: two records are the same fixture when they share
/// (tournamentId, both team ids in any order, dateIso). Records
/// without a tournament or without a date are never collapsed: a
/// dateless or standalone record cannot be proven to be the same
/// fixture, and collapsing those would hide genuinely different
/// friendlies. From each duplicate group exactly ONE record counts:
/// a completed record beats live, noResult and upcoming ones (the
/// codebase's standing status rank: completed > noResult > live >
/// upcoming); when two completed records collide, the one with more
/// legal balls recorded wins, then the one with more ball events,
/// then the first seen (deterministic). Points, NRR and player
/// stats all read through this, so a manual cloud repair plus a
/// phone re-push of the same fixture can never double-count.
List<Match> dedupeMatches(List<Match> matches) {
  int statusRank(String status) {
    switch (status) {
      case 'completed':
        return 5;
      case 'noResult':
        return 4;
      case 'live':
        return 3;
      default:
        return 1;
    }
  }

  int ballsOf(Match m) =>
      m.innings.fold(0, (sum, inn) => sum + inn.legalBalls);
  int eventsOf(Match m) =>
      m.innings.fold(0, (sum, inn) => sum + inn.events.length);

  bool beats(Match a, Match b) {
    final ra = statusRank(a.status);
    final rb = statusRank(b.status);
    if (ra != rb) return ra > rb;
    final ba = ballsOf(a);
    final bb = ballsOf(b);
    if (ba != bb) return ba > bb;
    final ea = eventsOf(a);
    final eb = eventsOf(b);
    if (ea != eb) return ea > eb;
    return false;
  }

  final groups = <String, Match>{};
  final order = <String>[];
  for (final m in matches) {
    final tid = m.tournamentId ?? '';
    if (tid.isEmpty || m.dateIso.isEmpty) {
      // Not provably one fixture: keep as its own entry.
      final key = 'single:${m.id}';
      if (!groups.containsKey(key)) order.add(key);
      groups[key] = m;
      continue;
    }
    final teams = [m.teamAId, m.teamBId]..sort();
    final key = 'fixture:$tid|${teams[0]}|${teams[1]}|${m.dateIso}';
    final prev = groups[key];
    if (prev == null) {
      groups[key] = m;
      order.add(key);
    } else if (beats(m, prev)) {
      groups[key] = m;
    }
  }
  return [for (final key in order) groups[key]!];
}

List<PointsRow> computePointsTable(
  String tournamentId,
  List<String> teamIds,
  List<Match> matches, {
  Map<String, int> pointsAdjustments = const {},
  Map<String, PointsTableOverride> pointsTableOverrides = const {},
}) {
  final rows = {for (final id in teamIds) id: PointsRow(id)};
  for (final m in dedupeMatches(matches)) {
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
    // NRR accounting. A poisoned innings (batting/bowling team id
    // outside this tournament's team ids, or empty) is skipped
    // instead of throwing: one bad record must not kill the whole
    // table.
    void account(InningsState inn) {
      final batRow = rows[inn.battingTeamId];
      final bowlRow = rows[inn.bowlingTeamId];
      if (batRow == null || bowlRow == null) return;
      final balls = _adjustedBalls(inn);
      batRow.runsFor += inn.totalRuns;
      batRow.ballsFor += balls;
      bowlRow.runsAgainst += inn.totalRuns;
      bowlRow.ballsAgainst += balls;
    }

    account(i1);
    account(i2);
    if (i1.totalRuns == i2.totalRuns) {
      // A decided super over turns the tie into a win/loss for
      // points purposes (2 pts, no tied point). NRR accounting
      // above is unchanged: account() only ever reads innings[0..1],
      // so super-over runs never enter NRR.
      final soWinner = superOverWinnerId(m);
      if (soWinner != null) {
        final loserId = soWinner == m.teamAId ? m.teamBId : m.teamAId;
        // Same poisoned-id guard as account(): a winner id outside
        // the table cannot be attributed to either side, so neither
        // side gets the win/loss (the match still counts as played
        // above). Never fall back to a tie here — the super over
        // did decide it, just unattributably.
        final wRow = rows[soWinner];
        final lRow = rows[loserId];
        if (wRow != null && lRow != null) {
          wRow.won++;
          wRow.points += 2;
          lRow.lost++;
        }
      } else {
        a.tied++;
        b.tied++;
        a.points += 1;
        b.points += 1;
      }
    } else {
      final winnerId = i1.totalRuns > i2.totalRuns
          ? i1.battingTeamId
          : i2.battingTeamId;
      final loserId = winnerId == m.teamAId ? m.teamBId : m.teamAId;
      // Same poisoned-id guard: when the winning innings' team id
      // is unknown, neither side can be attributed the result.
      final wRow = rows[winnerId];
      final lRow = rows[loserId];
      if (wRow != null && lRow != null) {
        wRow.won++;
        wRow.points += 2;
        lRow.lost++;
      }
    }
  }
  pointsAdjustments.forEach((teamId, extra) {
    rows[teamId]?.points += extra;
  });
  // Manual row overrides (v1.4.4, delta semantics since v1.4.7):
  // applied AFTER normal computation (pointsAdjustments included),
  // so an edited row is computed + delta — the hand correction is
  // preserved AND later matches keep flowing in. Overrides for
  // unknown team ids are ignored. Sorting below then runs on the
  // adjusted values as usual.
  for (final row in rows.values) {
    final o = pointsTableOverrides[row.teamId];
    if (o == null) continue;
    row.played += o.played;
    row.won += o.won;
    row.lost += o.lost;
    row.tied += o.tied;
    row.noResult += o.noResult;
    row.points += o.points;
    // nrrOverride holds the DISPLAYED NRR (computed + delta); the
    // getter returns it verbatim, so setting it here is what makes
    // the adjusted NRR visible. A zero delta leaves it unchanged.
    row.nrrOverride = row.nrr + o.nrr;
  }
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

  for (final m in dedupeMatches(matches)) {
    if (tournamentId != null && m.tournamentId != tournamentId) continue;
    // Player figures count from completed AND no-result matches: a
    // player who scored runs or took wickets in a washed-out match
    // keeps them in his stats. (Points table and NRR are untouched
    // by this: computePointsTable still gives a no-result match
    // only played+1 / NR+1 / points+1 and no NRR effect, per ICC.)
    if (m.status != 'completed' && m.status != 'noResult') continue;
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
        // Mankad is a run-out effected by the bowler: the event's
        // fielderId is the bowler (set in applyBall), credited as
        // a run-out — never as a bowler wicket.
        if (ev.wicketType == 'mankad') c.runOuts++;
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
  // Full dismissal set, plain texts with no creditable fielder:
  // 'retired out', 'timed out', 'obstructing the field' (kept
  // simple: no fielder credit even though a run-out can be involved
  // in reality), 'hit the ball twice' and 'retired hurt' (not a
  // dismissal at all) never credit anyone.
  final lower = t.toLowerCase();
  if (lower == 'retired out' ||
      lower == 'timed out' ||
      lower == 'obstructing the field' ||
      lower == 'hit the ball twice' ||
      lower == 'retired hurt' ||
      lower == 'retired') {
    return null;
  }
  // Mankad: stored as 'Mankad (<bowlerId>)' — a run-out credit for
  // the bowler named in the token, when it looks like a player id.
  if (lower.startsWith('mankad (')) {
    final end = t.indexOf(')', 8);
    if (end > 8) {
      final id = t.substring(8, end);
      if (_looksLikePlayerId(id)) return ('runOut', id);
    }
    return null;
  }
  if (lower == 'mankad') return null;
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

/// Applies per-player stats overrides (v1.4.5, delta semantics since
/// v1.4.7): additive base counters are ADDED to the computed row, so
/// a hand correction survives AND later matches keep flowing in.
/// MAX-type fields ([highScore], [bestWickets], [bestRuns]) are NOT
/// deltas — a "best" is not a sum, so the displayed value is
/// max(computed, stored): a manual best is never lost, but a newer
/// computed best can overtake it. Derived values (average, strike
/// rate, economy, best figures, MVP) are NOT stored — they recompute
/// from these counters via [CareerStats] getters. Overrides for
/// unknown playerIds are skipped: an override only ever targets a
/// row that exists. The input map is mutated in place (its objects
/// are freshly computed per view, same as [applyManualStats]).
///
/// Sentinel guard: a computed row with no wickets carries
/// bestRuns = 1 << 30, which must never leak into a max() — it is
/// treated as 0 here. A stored manual best is only meaningful
/// alongside its wickets; when neither side has wickets the
/// displayed bestRuns stays 0 (bestFigures shows '-' anyway).
void applyPlayerStatsOverrides(
  Map<String, CareerStats> stats,
  Map<String, PlayerStatsOverride> overrides,
) {
  for (final e in overrides.entries) {
    final c = stats[e.key];
    if (c == null) continue;
    final o = e.value;
    c.matches += o.matches;
    c.inningsBatted += o.inningsBatted;
    c.notOuts += o.notOuts;
    c.runs += o.runs;
    c.ballsFaced += o.ballsFaced;
    c.hundreds += o.hundreds;
    c.fifties += o.fifties;
    c.fours += o.fours;
    c.sixes += o.sixes;
    c.ballsBowled += o.ballsBowled;
    c.runsConceded += o.runsConceded;
    c.wickets += o.wickets;
    c.catches += o.catches;
    c.stumpings += o.stumpings;
    c.runOuts += o.runOuts;
    // MAX-type fields: absolute floors, never deltas (see doc above).
    // Capture the computed bestRuns effectiveness BEFORE mutating
    // bestWickets, or the sentinel guard below would read the
    // already-adjusted wickets.
    final computedBestRuns = c.bestWickets > 0 ? c.bestRuns : 0;
    if (o.highScore > c.highScore) c.highScore = o.highScore;
    if (o.bestWickets > c.bestWickets) c.bestWickets = o.bestWickets;
    if (o.bestRuns > computedBestRuns) c.bestRuns = o.bestRuns;
  }
}

/// Converts a stored wholesale (pre-v1.4.7) points-table override —
/// absolute values as the user typed them — into a v1.4.7 delta
/// against [computed], the row computed WITHOUT overrides but WITH
/// pointsAdjustments (exactly what [computePointsTable] produces
/// with an empty overrides map). Displayed values are exactly
/// unchanged: computed + delta == the old absolute values.
PointsTableOverride pointsOverrideToDelta(
  PointsTableOverride old,
  PointsRow computed,
) {
  return PointsTableOverride(
    played: old.played - computed.played,
    won: old.won - computed.won,
    lost: old.lost - computed.lost,
    tied: old.tied - computed.tied,
    noResult: old.noResult - computed.noResult,
    points: old.points - computed.points,
    nrr: old.nrr - computed.nrr,
  );
}

/// Converts a stored wholesale (pre-v1.4.7) player-stats override
/// into a v1.4.7 delta against [computed], the row computed WITHOUT
/// overrides (including manual stats, matching the display order:
/// compute, then manual stats, then overrides). Additive counters
/// become old − computed, so displayed values are exactly
/// unchanged. MAX-type fields are already absolute floors under the
/// new semantics and pass through untouched — with one honest
/// exception: if computed already overtook the manual best, the
/// displayed best rises to computed (that IS the new rule: a newer
/// computed best can overtake), so exact preservation holds for
/// max fields only when the manual best was still ahead.
PlayerStatsOverride playerStatsOverrideToDelta(
  PlayerStatsOverride old,
  CareerStats computed,
) {
  return PlayerStatsOverride(
    matches: old.matches - computed.matches,
    inningsBatted: old.inningsBatted - computed.inningsBatted,
    notOuts: old.notOuts - computed.notOuts,
    runs: old.runs - computed.runs,
    ballsFaced: old.ballsFaced - computed.ballsFaced,
    highScore: old.highScore,
    hundreds: old.hundreds - computed.hundreds,
    fifties: old.fifties - computed.fifties,
    fours: old.fours - computed.fours,
    sixes: old.sixes - computed.sixes,
    ballsBowled: old.ballsBowled - computed.ballsBowled,
    runsConceded: old.runsConceded - computed.runsConceded,
    wickets: old.wickets - computed.wickets,
    bestWickets: old.bestWickets,
    bestRuns: old.bestRuns,
    catches: old.catches - computed.catches,
    stumpings: old.stumpings - computed.stumpings,
    runOuts: old.runOuts - computed.runOuts,
  );
}

/// Copies every base counter from [src] to [dst] (derived getters
/// follow automatically). Used to refresh a displayed row object
/// after a stats reset, when its fresh computed values are known.
void copyBaseCounters(CareerStats dst, CareerStats src) {
  dst.matches = src.matches;
  dst.inningsBatted = src.inningsBatted;
  dst.notOuts = src.notOuts;
  dst.runs = src.runs;
  dst.ballsFaced = src.ballsFaced;
  dst.highScore = src.highScore;
  dst.hundreds = src.hundreds;
  dst.fifties = src.fifties;
  dst.fours = src.fours;
  dst.sixes = src.sixes;
  dst.ballsBowled = src.ballsBowled;
  dst.runsConceded = src.runsConceded;
  dst.wickets = src.wickets;
  dst.bestWickets = src.bestWickets;
  dst.bestRuns = src.bestRuns;
  dst.catches = src.catches;
  dst.stumpings = src.stumpings;
  dst.runOuts = src.runOuts;
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
      // Super-over override, mirroring computePointsTable: a
      // decided super over is a win/loss here too, never a tie.
      final soWinner = superOverWinnerId(m);
      if (soWinner != null) {
        final loserId = soWinner == m.teamAId ? m.teamBId : m.teamAId;
        get(soWinner).won++;
        get(loserId).lost++;
        if (soWinner == i1.battingTeamId) first.wonBattingFirst++;
        if (soWinner == i2.battingTeamId) second.wonChasing++;
      } else {
        a.tied++;
        b.tied++;
      }
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
      // Super-over override, mirroring computePointsTable.
      final soWinner = superOverWinnerId(m);
      if (soWinner != null) {
        if (soWinner == teamA) {
          h.aWins++;
        } else {
          h.bWins++;
        }
      } else {
        h.tied++;
      }
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
      // Delivery-derived milestones: the ball on which each batter
      // crossed 50 / 100 (balls faced, wides excluded).
      final ballsMap = <String, int>{};
      final runsMap = <String, int>{};
      final fiftyBalls = <String, int>{};
      final hundredBalls = <String, int>{};
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
        if (runs >= 50) fiftyBalls.putIfAbsent(s, () => balls);
        if (runs >= 100) hundredBalls.putIfAbsent(s, () => balls);
      }
      // The innings' FINAL score for a batter: the batting figure is
      // the source of truth (the v1.3.5 cascade rule), the delivery
      // tally is the fallback when no figure was stored.
      int finalRuns(String pid) {
        final fig = inn.batting[pid];
        if (fig != null && fig.batted) return fig.runs;
        return runsMap[pid] ?? 0;
      }

      // Fastest Fifty lists ONLY innings that END on 50–99 (v1.3.7):
      // a batter who goes on to 100+ belongs to Fastest Hundred
      // alone — reaching fifty on the way to a hundred is not a
      // "fastest fifty" entry.
      fiftyBalls.forEach((pid, balls) {
        final fr = finalRuns(pid);
        if (fr >= 50 && fr < 100) fifties.add(Milestone(pid, balls, fr));
      });
      hundredBalls.forEach((pid, balls) {
        final fr = finalRuns(pid);
        if (fr >= 100) hundreds.add(Milestone(pid, balls, fr));
      });
      // Figure fallback (v1.3.5): an innings whose deliveries were
      // never stored (or were lost) still proves its milestones
      // through the batting figures — a 50/100 must appear in
      // Fastest Fifty / Hundred with the figure's balls faced
      // instead of the card sitting empty. The delivery-derived
      // entry, when one exists, stays the more precise one. The
      // same 50–99 / 100+ split applies here (v1.3.7).
      inn.batting.forEach((pid, fig) {
        if (!fig.batted) return;
        if (fig.runs >= 50 &&
            fig.runs < 100 &&
            !fiftyBalls.containsKey(pid)) {
          fifties.add(Milestone(pid, fig.balls, fig.runs));
        }
        if (fig.runs >= 100 && !hundredBalls.containsKey(pid)) {
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
      final how = batFigStatusText(f, nameOf);
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
