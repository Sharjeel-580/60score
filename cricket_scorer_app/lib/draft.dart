// Pure-Dart draft logic for 60Score (offline manual-pick draft).
// No Flutter imports: unit-testable.
import 'models.dart';

class DraftTurn {
  final int round; // 1-based
  final int pickNo; // 1-based overall
  final String teamId;
  const DraftTurn(this.round, this.pickNo, this.teamId);
}

/// Effective pick order for [round] (1-based):
///  1. per-round manual order ([Draft.manualRoundPicks]) wins — it is used
///     exactly as entered (snake does not apply to it);
///  2. otherwise the custom [Draft.manualPickOrder] when non-empty;
///  3. otherwise [Draft.teamIds].
/// Snake order reverses even rounds of the base (non-manual-round) order.
List<String> orderForRound(Draft d, int round) {
  final manual = d.manualRoundPicks['$round'];
  if (manual != null && manual.isNotEmpty) return List<String>.of(manual);
  final base = d.manualPickOrder.isNotEmpty ? d.manualPickOrder : d.teamIds;
  if (d.snakeOrder && round % 2 == 0) return base.reversed.toList();
  return base;
}

/// Whose turn is it for the next pick? Returns null when the draft is
/// complete. Simple rounds: linear repeating order; when [Draft.snakeOrder]
/// is on, even rounds run in reverse team order.
DraftTurn? nextTurn(Draft d) {
  if (d.teamIds.isEmpty) return null;
  final idx = d.picks.length;
  if (idx >= d.totalPicks) return null;
  final round = idx ~/ d.teamIds.length + 1;
  final order = orderForRound(d, round);
  if (order.isEmpty) return null;
  return DraftTurn(round, idx + 1, order[idx % order.length]);
}

/// The next [count] turns without mutating the draft (for "Upcoming picks").
List<DraftTurn> upcomingTurns(Draft d, int count) {
  final out = <DraftTurn>[];
  var idx = d.picks.length;
  while (out.length < count && idx < d.totalPicks) {
    final round = idx ~/ d.teamIds.length + 1;
    final order = orderForRound(d, round);
    if (order.isEmpty) break;
    out.add(DraftTurn(round, idx + 1, order[idx % order.length]));
    idx++;
  }
  return out;
}

Set<String> draftedPlayerIds(Draft d) => d.picks.map((p) => p.playerId).toSet();

int squadCount(Draft d, String teamId) =>
    d.picks.where((p) => p.teamId == teamId).length;

/// Assign [player] to the team whose turn it is. Returns false when the
/// draft is complete, the player is already drafted, or that squad is
/// already full.
bool applyPick(Draft d, RegPlayer player) {
  final turn = nextTurn(d);
  if (turn == null) return false;
  if (draftedPlayerIds(d).contains(player.id)) return false;
  if (squadCount(d, turn.teamId) >= d.squadSize) return false;
  d.picks.add(
    DraftPick(
      round: turn.round,
      pickNo: turn.pickNo,
      teamId: turn.teamId,
      playerId: player.id,
      playerName: player.name,
    ),
  );
  if (d.isComplete) d.status = 'completed';
  return true;
}

bool undoPick(Draft d) {
  if (d.picks.isEmpty) return false;
  d.picks.removeLast();
  d.status = 'active';
  d.appliedToTeams = false;
  return true;
}

/// Skip the current team's turn without assigning a player. The turn is
/// forfeited: a placeholder pick is recorded so the round order stays
/// consistent and [nextTurn] keeps working. Never auto-picks a player.
bool skipTurn(Draft d) {
  final turn = nextTurn(d);
  if (turn == null) return false;
  d.picks.add(
    DraftPick(
      round: turn.round,
      pickNo: turn.pickNo,
      teamId: turn.teamId,
      playerId: '',
      playerName: '— Skipped —',
    ),
  );
  if (d.isComplete) d.status = 'completed';
  return true;
}

/// Remove exactly [pick] (identity match), then re-derive round / pickNo /
/// teamId for the remaining picks so the draft order stays fair and
/// [nextTurn] keeps working. Used by Draft History's delete-pick.
bool removePick(Draft d, DraftPick pick) {
  if (!d.picks.remove(pick)) return false;
  reindexPicks(d);
  return true;
}

/// Re-derive round/pickNo/teamId for all picks from their position.
/// Keeps the draft consistent after settings or history edits.
void reindexPicks(Draft d) {
  if (d.teamIds.isEmpty) return;
  for (var i = 0; i < d.picks.length; i++) {
    final round = i ~/ d.teamIds.length + 1;
    final order = orderForRound(d, round);
    d.picks[i].round = round;
    d.picks[i].pickNo = i + 1;
    d.picks[i].teamId = order.isEmpty ? '' : order[i % order.length];
  }
  d.status = d.isComplete ? 'completed' : 'active';
  if (d.status == 'active') d.appliedToTeams = false;
}

/// Picks grouped by team, in pick order.
Map<String, List<DraftPick>> draftSquads(Draft d) {
  final map = {for (final t in d.teamIds) t: <DraftPick>[]};
  for (final p in d.picks) {
    map.putIfAbsent(p.teamId, () => []).add(p);
  }
  return map;
}

double draftProgress(Draft d) =>
    d.totalPicks == 0 ? 0 : d.picks.length / d.totalPicks;
