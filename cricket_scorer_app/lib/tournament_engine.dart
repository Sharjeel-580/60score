// 60Score tournament engine — automatic points table, NRR-based ranking,
// top-4 playoff qualification, semifinal seeding and grand-final assignment.
//
// Built on top of computePointsTable() in scoring.dart (ICC aggregate NRR,
// legal-ball overs, all-out = full quota, chase = actual balls faced).
// This file owns *qualification decisions*; it never invents results.
import 'models.dart';
import 'scoring.dart';

/// Minimal store surface the playoff engine needs. [Store] satisfies this
/// interface implicitly (Dart structural interfaces), so call sites keep
/// passing the real Store while tests use a fake.
abstract class PlayoffStore {
  Tournament? tournamentById(String? id);
  String teamName(String id);
  List<Match> get matches;
  Future<void> persist();
}

/// Outcome of a playoff recalculation pass.
class PlayoffUpdate {
  /// True if any persisted state (seeds, finalists, qualification) changed.
  final bool changed;

  /// True when a consequential correction needs the user's explicit
  /// confirmation before it is applied (never applied silently).
  final bool needsConfirmation;

  /// Human-readable summary for logs / confirmation dialogs.
  final String message;

  /// Final (locked) qualifiers in rank order, empty if not finalized.
  final List<String> finalQualifiers;

  /// Provisionally guaranteed qualifiers (mathematical certainty only),
  /// empty when the stage is finalized.
  final List<String> provisionalQualifiers;

  const PlayoffUpdate({
    this.changed = false,
    this.needsConfirmation = false,
    this.message = '',
    this.finalQualifiers = const [],
    this.provisionalQualifiers = const [],
  });
}

/// League-stage fixtures of a tournament (excludes semifinals / final).
List<Match> leagueMatchesOf(String tournamentId, List<Match> all) => all
    .where((m) => m.tournamentId == tournamentId && m.stage == 'league')
    .toList();

/// Playoff fixtures of a tournament, ordered SF1, SF2, Final.
List<Match> playoffMatchesOf(String tournamentId, List<Match> all) {
  const order = ['semifinal1', 'semifinal2', 'final'];
  final list = all
      .where((m) => m.tournamentId == tournamentId && m.stage != 'league')
      .toList();
  list.sort(
    (a, b) => order
        .indexOf(a.stage)
        .compareTo(order.indexOf(b.stage)),
  );
  return list;
}

/// A league fixture is finalized when it can no longer change the table:
/// completed, no-result, or cancelled.
bool _fixtureFinalized(Match m) =>
    m.status == 'completed' ||
    m.status == 'noResult' ||
    m.status == 'cancelled';

/// True when every league fixture is finalized.
bool leagueStageFinalized(String tournamentId, List<Match> all) {
  final league = leagueMatchesOf(tournamentId, all);
  if (league.isEmpty) return false;
  return league.every(_fixtureFinalized);
}

/// Winner's team ID for a completed match, or null for ties / no-results /
/// unfinished matches. Never guesses from a live score.
String? matchWinnerId(Match m) {
  if (m.status != 'completed') return null;
  if (m.innings.length < 2) return null;
  final i1 = m.innings[0];
  final i2 = m.innings[1];
  if (i1.totalRuns == i2.totalRuns) return null; // tie — no winner
  return i1.totalRuns > i2.totalRuns ? i1.battingTeamId : i2.battingTeamId;
}

/// Teams mathematically guaranteed a top-4 finish on points alone.
/// Conservative: a team qualifies provisionally only if fewer than four
/// *other* teams could still finish with strictly more points. NRR is
/// ignored here on purpose — this direction is always safe.
List<String> guaranteedQualifiers(
  List<PointsRow> table,
  List<Match> leagueMatches,
) {
  final remaining = <String, int>{};
  for (final m in leagueMatches) {
    if (_fixtureFinalized(m)) continue;
    remaining[m.teamAId] = (remaining[m.teamAId] ?? 0) + 1;
    remaining[m.teamBId] = (remaining[m.teamBId] ?? 0) + 1;
  }
  final guaranteed = <String>[];
  for (final row in table) {
    var canExceed = 0;
    for (final other in table) {
      if (other.teamId == row.teamId) continue;
      final maxOther = other.points + 2 * (remaining[other.teamId] ?? 0);
      if (maxOther > row.points) canExceed++;
    }
    if (canExceed < 4) guaranteed.add(row.teamId);
  }
  return guaranteed;
}

/// Points table for the LEAGUE stage only (playoff matches never pollute it).
List<PointsRow> leaguePointsTable(
  Tournament t,
  List<Match> allMatches,
) => computePointsTable(
  t.id,
  t.teamIds,
  allMatches.where((m) => m.stage == 'league').toList(),
  pointsAdjustments: t.pointsAdjustments,
  pointsTableOverrides: t.pointsTableOverrides,
);

/// Recompute qualification and playoff assignments for [tournamentId].
///
/// Safe-recalculation contract:
/// - Idempotent: repeated calls with unchanged data change nothing.
/// - Never reseeds a playoff fixture that has started (live/completed).
/// - Never assigns a finalist from an unfinished match.
/// - Corrections after finalization need [force] = true (UI confirms first).
Future<PlayoffUpdate> applyPlayoffUpdate(
  PlayoffStore store,
  String tournamentId, {
  bool force = false,
}) async {
  final t = store.tournamentById(tournamentId);
  if (t == null) return const PlayoffUpdate(message: 'Tournament not found');
  final all = store.matches;
  final table = leaguePointsTable(t, all);
  if (table.isEmpty) return const PlayoffUpdate(message: 'No teams');

  final finalized = leagueStageFinalized(tournamentId, all);
  var changed = false;
  final notes = <String>[];

  Match? playoffByStage(String stage) {
    for (final m in all) {
      if (m.tournamentId == tournamentId && m.stage == stage) return m;
    }
    return null;
  }

  bool playoffStarted(Match? m) =>
      m != null && (m.status == 'live' || m.status == 'completed');

  final sf1 = playoffByStage('semifinal1');
  final sf2 = playoffByStage('semifinal2');
  final fin = playoffByStage('final');
  final anyPlayoffStarted =
      playoffStarted(sf1) || playoffStarted(sf2) || playoffStarted(fin);

  // ---------- Final qualification ----------
  List<String> finalQ = [];
  if (finalized) {
    finalQ = table.take(4).map((r) => r.teamId).toList();
    final previouslyFinalized = t.qualificationFinalized;
    final storedQ = t.qualifiedTeamIds;
    final qChanged =
        storedQ.length != finalQ.length ||
        !Iterable.generate(finalQ.length)
            .every((i) => storedQ[i] == finalQ[i]);

    if (!previouslyFinalized || (qChanged && !anyPlayoffStarted)) {
      final needsConfirm = previouslyFinalized && qChanged && !force;
      if (needsConfirm) {
        return PlayoffUpdate(
          needsConfirmation: true,
          message:
              'League results changed after qualification was locked. '
              'Confirm to reseed the semifinals with the corrected standings.',
          finalQualifiers: finalQ,
        );
      }
      t.qualifiedTeamIds = finalQ;
      t.qualificationFinalized = true;
      changed = true;
      notes.add('Top 4 qualified: ${finalQ.map(store.teamName).join(', ')}');
    } else if (qChanged && anyPlayoffStarted) {
      // Playoffs already underway — never silently reseed.
      return PlayoffUpdate(
        needsConfirmation: true,
        message:
            'League standings changed but the playoffs have already started. '
            'Reseeding is blocked to protect completed playoff matches.',
        finalQualifiers: storedQ,
      );
    }

    // ---------- Semifinal seeding (1v4, 2v3) ----------
    void seedSemi(Match? semi, String a, String b, String label) {
      if (semi == null || playoffStarted(semi)) return;
      if (semi.teamAId != a || semi.teamBId != b) {
        semi.teamAId = a;
        semi.teamBId = b;
        changed = true;
        notes.add(
          '$label: ${store.teamName(a)} vs ${store.teamName(b)}',
        );
      }
    }

    if (finalQ.length == 4) {
      seedSemi(sf1, finalQ[0], finalQ[3], 'Semi Final 1');
      seedSemi(sf2, finalQ[1], finalQ[2], 'Semi Final 2');
    }
  }

  // ---------- Grand-final assignment (only from finalized semifinals) ----------
  void assignFinalist(Match? semi, bool toTeamA) {
    if (semi == null || fin == null) return;
    if (playoffStarted(fin)) return; // final already underway — hands off
    final winner = matchWinnerId(semi);
    if (winner == null) return; // tie / unfinished / no-result: slot stays TBD
    if (toTeamA && fin.teamAId != winner) {
      fin.teamAId = winner;
      changed = true;
      notes.add('Grand Final Team A: ${store.teamName(winner)}');
    }
    if (!toTeamA && fin.teamBId != winner) {
      fin.teamBId = winner;
      changed = true;
      notes.add('Grand Final Team B: ${store.teamName(winner)}');
    }
  }

  assignFinalist(sf1, true);
  assignFinalist(sf2, false);

  // ---------- Provisional qualifiers (league not finalized) ----------
  List<String> provisional = [];
  if (!finalized) {
    provisional = guaranteedQualifiers(
      table,
      leagueMatchesOf(tournamentId, all),
    );
  }

  if (changed) await store.persist();
  return PlayoffUpdate(
    changed: changed,
    message: notes.isEmpty ? 'No playoff changes' : notes.join(' · '),
    finalQualifiers: t.qualificationFinalized ? t.qualifiedTeamIds : const [],
    provisionalQualifiers: provisional,
  );
}
