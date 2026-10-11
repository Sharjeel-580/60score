// Pure-Dart draft logic for 60Score (offline manual-pick draft).
// No Flutter imports: unit-testable.
import 'models.dart';

class DraftTurn {
  final int round; // 1-based
  final int pickNo; // 1-based overall
  final String teamId;
  const DraftTurn(this.round, this.pickNo, this.teamId);
}

/// Whose turn is it for the next pick? Returns null when the draft is
/// complete. Simple rounds: linear repeating order; when [Draft.snakeOrder]
/// is on, even rounds run in reverse team order.
DraftTurn? nextTurn(Draft d) {
  if (d.teamIds.isEmpty) return null;
  final idx = d.picks.length;
  if (idx >= d.totalPicks) return null;
  final round = idx ~/ d.teamIds.length + 1;
  final pos = idx % d.teamIds.length;
  final order = (d.snakeOrder && round % 2 == 0)
      ? d.teamIds.reversed.toList()
      : d.teamIds;
  return DraftTurn(round, idx + 1, order[pos]);
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
