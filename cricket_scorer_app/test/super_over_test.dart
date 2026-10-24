import 'package:flutter_test/flutter_test.dart';
import 'package:cricket_scorer_app/models.dart';
import 'package:cricket_scorer_app/scoring.dart';

String teamName(String id) => id == 'ta' ? 'Team A' : 'Team B';

/// A 1-over match, XI of 4, Team A bats first (won toss, chose bat)
/// and both sides score exactly 6 — a completed tie.
Match tiedMatch({String id = 'm1'}) {
  final m = Match(
    id: id,
    tournamentId: 't1',
    teamAId: 'ta',
    teamBId: 'tb',
    xiA: const ['a1', 'a2', 'a3', 'a4'],
    xiB: const ['b1', 'b2', 'b3', 'b4'],
    oversLimit: 1,
    ballsPerOver: 6,
    tossWinnerId: 'ta',
    tossDecision: 'bat',
  );
  for (var n = 1; n <= 2; n++) {
    final inn = startInnings(m, n);
    setOpeners(inn, inn.battingXI[0], inn.battingXI[1], inn.bowlingXI[0]);
    for (var i = 0; i < 6; i++) {
      ball(inn, BallInput(batRuns: 1));
    }
    expect(inn.totalRuns, 6);
    expect(inn.isComplete, isTrue);
  }
  computeResult(m, teamName);
  expect(m.status, 'completed');
  expect(m.resultText, 'Match tied');
  expect(matchIsTied(m), isTrue);
  return m;
}

void ball(InningsState s, BallInput input) {
  final ok = applyBall(s, input);
  expect(ok, isTrue,
      reason: 'ball should apply: ${input.extraType} ${input.batRuns}');
}

void playRuns(InningsState inn, List<int> runsList) {
  setOpeners(inn, inn.battingXI[0], inn.battingXI[1], inn.bowlingXI[0]);
  for (final r in runsList) {
    ball(inn, BallInput(batRuns: r));
  }
}

/// Plays a full deciding super over on [m]: Team B (batted second
/// in the main match) makes 10 batting first, Team A makes 6 in the
/// chase. Returns the match for chaining.
Match decidedSuperOver(Match m) {
  final so1 = startSuperOverInnings(m, 1);
  playRuns(so1, [6, 1, 1, 1, 1, 0]); // 10
  expect(so1.isComplete, isTrue);
  final so2 = startSuperOverInnings(m, 2);
  playRuns(so2, [1, 1, 1, 1, 1, 1]); // 6
  expect(so2.isComplete, isTrue);
  return m;
}

void main() {
  group('storage', () {
    test('JSON round-trip preserves superOverInnings', () {
      final m = decidedSuperOver(tiedMatch());
      final json = m.toJson();
      expect(json.containsKey('superOverInnings'), isTrue);
      final loaded = Match.fromJson(json);
      expect(loaded.superOverInnings.length, 2);
      expect(loaded.superOverInnings[0].totalRuns, 10);
      expect(loaded.superOverInnings[0].battingTeamId, 'tb');
      expect(loaded.superOverInnings[0].maxWickets, 2);
      expect(loaded.superOverInnings[0].oversLimit, 1);
      expect(loaded.superOverInnings[1].totalRuns, 6);
      expect(loaded.superOverInnings[1].target, 11);
      expect(superOverWinnerId(loaded), 'tb');
      // Main innings untouched by the round-trip either.
      expect(loaded.innings.length, 2);
    });

    test('an old record without the key loads with no super overs', () {
      final json = tiedMatch().toJson()..remove('superOverInnings');
      final loaded = Match.fromJson(json);
      expect(loaded.superOverInnings, isEmpty);
      expect(superOverWinnerId(loaded), isNull);
      expect(superOverNeedsAnotherRound(loaded), isFalse);
    });
  });

  group('startSuperOverInnings', () {
    test('round 1: main-match second-batting team bats first; '
        '1 over, 2 wickets, full XI, penalties copied', () {
      final m = tiedMatch();
      m.widePenalty = false;
      m.noBallPenalty = false;
      final so1 = startSuperOverInnings(m, 1);
      expect(so1.battingTeamId, 'tb'); // batted second in main match
      expect(so1.bowlingTeamId, 'ta');
      expect(so1.oversLimit, 1);
      expect(so1.ballsPerOver, 6);
      expect(so1.maxWickets, 2);
      expect(so1.effectiveMaxWickets, 2);
      expect(so1.target, 0);
      expect(so1.battingXI, m.xiB);
      expect(so1.bowlingXI, m.xiA);
      expect(so1.widePenalty, isFalse);
      expect(so1.noBallPenalty, isFalse);
      // Fetching the same innings again does not duplicate it.
      expect(identical(startSuperOverInnings(m, 1), so1), isTrue);
      expect(m.superOverInnings.length, 1);
      // Super overs never touch the main innings list.
      expect(m.innings.length, 2);
    });

    test('second innings of the round swaps sides and sets target', () {
      final m = tiedMatch();
      final so1 = startSuperOverInnings(m, 1);
      playRuns(so1, [2, 2, 2, 2, 0, 0]); // 8
      final so2 = startSuperOverInnings(m, 2);
      expect(so2.battingTeamId, 'ta');
      expect(so2.bowlingTeamId, 'tb');
      expect(so2.target, 9);
      expect(so2.battingXI, m.xiA);
    });

    test('two wickets end a super-over innings early', () {
      final m = tiedMatch();
      final so1 = startSuperOverInnings(m, 1);
      setOpeners(so1, 'b1', 'b2', 'a1');
      ball(so1, BallInput(isWicket: true, wicketType: 'bowled'));
      setNextBatter(so1, 'b3');
      ball(so1, BallInput(isWicket: true, wicketType: 'bowled'));
      expect(so1.wickets, 2);
      expect(so1.legalBalls, 2);
      expect(so1.isComplete, isTrue);
    });
  });

  group('result integration', () {
    test('decided super over: winner id, result text, status', () {
      final m = decidedSuperOver(tiedMatch());
      expect(superOverWinnerId(m), 'tb');
      expect(superOverNeedsAnotherRound(m), isFalse);
      final text = computeResult(m, teamName);
      expect(text, 'Team B won the Super Over');
      expect(m.resultText, 'Team B won the Super Over');
      expect(m.status, 'completed');
      // The main match itself is still a tie at innings level.
      expect(matchIsTied(m), isTrue);
    });

    test('chase reaching the target mid-over decides the winner', () {
      final m = tiedMatch();
      final so1 = startSuperOverInnings(m, 1);
      playRuns(so1, [1, 1, 1, 1, 1, 0]); // 5
      final so2 = startSuperOverInnings(m, 2);
      expect(so2.target, 6);
      playRuns(so2, [4, 2]); // 6 off 2 balls — target reached
      expect(so2.legalBalls, 2);
      expect(so2.isComplete, isTrue);
      expect(superOverWinnerId(m), 'ta');
      expect(computeResult(m, teamName), 'Team A won the Super Over');
    });

    test('plain tie without a super over stays "Match tied"', () {
      final m = tiedMatch();
      expect(superOverWinnerId(m), isNull);
      expect(computeResult(m, teamName), 'Match tied');
    });
  });

  group('second round', () {
    test('round 1 tied -> no winner, another round needed, '
        'result text notes the tied super over; round 2 alternates '
        'the batting order and decides', () {
      final m = tiedMatch();
      final so1 = startSuperOverInnings(m, 1);
      playRuns(so1, [1, 1, 1, 1, 1, 1]); // 6
      final so2 = startSuperOverInnings(m, 2);
      playRuns(so2, [1, 1, 1, 1, 1, 1]); // 6 — round tied
      expect(superOverWinnerId(m), isNull);
      expect(superOverNeedsAnotherRound(m), isTrue);
      expect(computeResult(m, teamName), 'Match tied (Super Over tied)');
      expect(m.resultText, 'Match tied (Super Over tied)');

      // Round 2: the side that batted second in round 1's chase
      // (Team A) now bats first — the order alternates.
      final so3 = startSuperOverInnings(m, 3);
      expect(so3.battingTeamId, 'ta');
      playRuns(so3, [1, 1, 1, 1, 1, 0]); // 5
      final so4 = startSuperOverInnings(m, 4);
      expect(so4.battingTeamId, 'tb');
      expect(so4.target, 6);
      playRuns(so4, [6]); // chase done in one ball
      expect(so4.isComplete, isTrue);
      expect(superOverWinnerId(m), 'tb');
      expect(superOverNeedsAnotherRound(m), isFalse);
      expect(computeResult(m, teamName), 'Team B won the Super Over');
    });
  });

  group('points table, team stats & head-to-head', () {
    test('super-over winner gets 2 pts / a win, loser a loss, '
        'and NRR figures are identical to the plain tie', () {
      final plain = tiedMatch(id: 'plain');
      final withSo = decidedSuperOver(tiedMatch(id: 'withso'));

      final plainRows = computePointsTable('t1', ['ta', 'tb'], [plain]);
      final plainA = plainRows.firstWhere((r) => r.teamId == 'ta');
      final plainB = plainRows.firstWhere((r) => r.teamId == 'tb');
      expect(plainA.tied, 1);
      expect(plainA.points, 1);
      expect(plainB.tied, 1);
      expect(plainB.points, 1);

      final rows = computePointsTable('t1', ['ta', 'tb'], [withSo]);
      final a = rows.firstWhere((r) => r.teamId == 'ta');
      final b = rows.firstWhere((r) => r.teamId == 'tb');
      expect(b.won, 1);
      expect(b.points, 2);
      expect(b.tied, 0);
      expect(b.lost, 0);
      expect(a.lost, 1);
      expect(a.points, 0);
      expect(a.tied, 0);
      expect(a.won, 0);
      expect(rows.first.teamId, 'tb');

      // NRR exclusion proof: super-over runs/balls never enter the
      // accounting — every NRR input matches the plain tied match.
      for (final (withRow, plainRow) in [(a, plainA), (b, plainB)]) {
        expect(withRow.runsFor, plainRow.runsFor);
        expect(withRow.ballsFor, plainRow.ballsFor);
        expect(withRow.runsAgainst, plainRow.runsAgainst);
        expect(withRow.ballsAgainst, plainRow.ballsAgainst);
        expect(withRow.nrr, closeTo(plainRow.nrr, 1e-12));
      }
    });

    test('team stats and head-to-head agree with the table', () {
      final withSo = decidedSuperOver(tiedMatch());
      final ts = computeTeamStats([withSo]);
      expect(ts['tb']!.won, 1);
      expect(ts['tb']!.tied, 0);
      expect(ts['tb']!.wonChasing, 1); // batted second in main match
      expect(ts['ta']!.lost, 1);
      expect(ts['ta']!.tied, 0);

      final h = headToHead([withSo], 'ta', 'tb');
      expect(h.bWins, 1);
      expect(h.aWins, 0);
      expect(h.tied, 0);

      final plainH = headToHead([tiedMatch()], 'ta', 'tb');
      expect(plainH.tied, 1);
    });
  });

  group('career stats exclusion', () {
    test('super-over runs and wickets never enter career stats', () {
      final m = tiedMatch();
      Map<String, List<int>> snapshot() => {
            for (final e in computeCareerStats([m]).entries)
              e.key: [
                e.value.runs,
                e.value.ballsFaced,
                e.value.wickets,
                e.value.ballsBowled,
                e.value.inningsBatted,
              ],
          };
      final before = snapshot();
      decidedSuperOver(m);
      computeResult(m, teamName);
      final after = snapshot();
      expect(after.keys.toSet(), before.keys.toSet());
      for (final pid in before.keys) {
        expect(after[pid], before[pid],
            reason: 'career figures for $pid must ignore the super over');
      }
    });
  });
}
