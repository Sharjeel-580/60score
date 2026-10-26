// Phase-2 load/stress tests (v1.4.3, user ordered "test
// everything, all possible ways"): full rapid matches, legacy
// payloads, load guards, double-tap, foreground returns, points /
// stats over mixed records, the debug screen, and the headline
// measurement — a 96-ball match against the REAL dataset shape
// (78 players with inline photos) proving per-ball persist size
// and time stay flat and low after the matches-only persist.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cricket_scorer_app/debug_info.dart';
import 'package:cricket_scorer_app/models.dart';
import 'package:cricket_scorer_app/scoring.dart';
import 'package:cricket_scorer_app/screens/debug_info_screen.dart';
import 'package:cricket_scorer_app/store.dart';
import 'package:cricket_scorer_app/sync_service.dart';

List<String> xi(String p) => [for (var i = 1; i <= 11; i++) '$p$i'];

Match makeMatch({
  int xiN = 11,
  int overs = 8,
}) =>
    Match(
      id: 'm1',
      teamAId: 'ta',
      teamBId: 'tb',
      xiA: [for (var i = 1; i <= xiN; i++) 'a$i'],
      xiB: [for (var i = 1; i <= xiN; i++) 'b$i'],
      oversLimit: overs,
      ballsPerOver: 6,
      tossWinnerId: 'ta',
      tossDecision: 'bat',
    );

InningsState openInnings(Match m, {int n = 1}) {
  final inn = startInnings(m, n);
  setOpeners(inn, inn.battingXI[0], inn.battingXI[1], inn.bowlingXI[0]);
  return inn;
}

void ball(InningsState s, BallInput input) {
  expect(applyBall(s, input), isTrue,
      reason: 'ball should apply: ${input.extraType} ${input.batRuns}');
}

void runs(InningsState s, int r) => ball(s, BallInput(batRuns: r));

/// Scores one 8-over innings rapidly (no awaits between balls) and
/// returns the persisted-JSON size after each over.
List<int> scoreInnings(
  Match m,
  InningsState inn, {
  required List<String> bowlers,
  required List<String> nextBatters,
  required List<int> pattern,
  List<int> wicketBalls = const [11, 23, 35],
}) {
  const overBalls = 6;
  final sizes = <int>[];
  var expectedRuns = 0;
  var wicketIdx = 0;
  var ballIndex = 0;
  for (var over = 0; over < 8; over++) {
    for (var b = 0; b < overBalls; b++) {
      final isWicket =
          wicketBalls.contains(ballIndex) && ballIndex < 47;
      final r = isWicket ? 0 : pattern[ballIndex % pattern.length];
      ball(
        inn,
        BallInput(
          batRuns: r,
          isWicket: isWicket,
          wicketType: isWicket ? 'bowled' : '',
        ),
      );
      expectedRuns += r;
      if (isWicket) {
        expect(inn.awaitingBatter, isTrue);
        setNextBatter(inn, nextBatters[wicketIdx++]);
      }
      ballIndex++;
    }
    sizes.add(jsonEncode(m.toJson()).length);
    if (over < 7) {
      expect(inn.awaitingBowler, isTrue);
      expect(setBowler(inn, bowlers[over + 1]), isTrue);
    }
  }
  expect(inn.legalBalls, 48);
  expect(inn.isComplete, isTrue);
  expect(inn.totalRuns, expectedRuns);
  return sizes;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('rapid full match stays bounded (no quadratic growth)', () {
    test('8 overs ball-by-ball: size grows linearly, no throw', () {
      final m = makeMatch();
      final inn = openInnings(m);
      final sizes = scoreInnings(
        m,
        inn,
        bowlers: [for (var i = 1; i <= 8; i++) 'b$i'],
        nextBatters: ['a3', 'a4', 'a5'],
        pattern: const [0, 1, 2, 4, 6, 0, 1, 3],
      );
      expect(sizes.length, 8);
      // Linear growth (v1.4.5 recalibration): each ball adds one
      // event plus one BOUNDED delta undo step, so the second half
      // adds roughly one first-half total — more than the old
      // zero-stack bound, but still linear. A quadratic history
      // (one full-innings snapshot per ball, as pre-1.4.3) would
      // make the second half add ~3x the first half's total, so
      // the <2x bound plus the <3x total bound below still guard
      // exactly against that blowup.
      expect(sizes[7] > sizes[3], isTrue);
      expect(sizes[7] - sizes[3], lessThan(2 * sizes[3]));
      expect(sizes[7], lessThan(3 * sizes[3]));
    });
  });

  group('legacy payloads', () {
    test('huge persisted undo stack decodes and re-persists clean',
        () {
      final m = Match(
        id: 'm1',
        teamAId: 'ta',
        teamBId: 'tb',
        xiA: xi('a').sublist(0, 4),
        xiB: xi('b').sublist(0, 4),
        oversLimit: 2,
        ballsPerOver: 6,
        tossWinnerId: 'ta',
        tossDecision: 'bat',
      );
      final inn = startInnings(m, 1);
      setOpeners(inn, 'a1', 'a2', 'b1');
      runs(inn, 4);
      runs(inn, 1);
      runs(inn, 0);
      final events = inn.events.length;
      final total = inn.totalRuns;

      final json =
          jsonDecode(jsonEncode(m.toJson())) as Map<String, dynamic>;
      final innJson = (json['innings'] as List)[0] as Map<String, dynamic>;
      // Realistic legacy stack: each entry is a full innings
      // snapshot string (what the pre-1.4.3 app persisted per ball).
      innJson['undoStack'] =
          List.generate(200, (_) => jsonEncode(inn.toJson()));
      final hugeSize = jsonEncode(json).length;
      expect(hugeSize, greaterThan(10000));

      final restored = Match.fromJson(json);
      expect(restored.innings.length, 1);
      expect(restored.innings[0].events.length, events);
      expect(restored.innings[0].totalRuns, total);

      final re = restored.toJson();
      // v1.4.5: the re-persisted record DOES carry 'undoStack' —
      // but as an empty list, because the legacy string stack was
      // dropped on load. The huge snapshot payload is gone.
      expect(
        ((re['innings'] as List)[0] as Map)['undoStack'],
        isEmpty,
      );
      expect(jsonEncode(re).length, lessThan(hugeSize ~/ 10));

      // v1.4.5: the legacy string stack is DROPPED on load, so the
      // restored stack is empty — not 200. One more ball then
      // starts a fresh 1-entry step stack, still capped at 50.
      expect(restored.innings[0].undoStack.length, 0);
      expect(
        applyBall(restored.innings[0], BallInput(batRuns: 1)),
        isTrue,
      );
      expect(restored.innings[0].undoStack.length, lessThanOrEqualTo(50));
    });

    test('one malformed innings entry skips only that entry', () {
      final good = (() {
        final mm = Match(
          id: 'tmp',
          teamAId: 'ta',
          teamBId: 'tb',
          xiA: xi('a').sublist(0, 4),
          xiB: xi('b').sublist(0, 4),
          oversLimit: 2,
          ballsPerOver: 6,
          tossWinnerId: 'ta',
          tossDecision: 'bat',
        );
        final ii = startInnings(mm, 1);
        setOpeners(ii, 'a1', 'a2', 'b1');
        runs(ii, 4);
        return ii.toJson();
      })();
      final payload = <String, dynamic>{
        'id': 'mg',
        'teamAId': 'ta',
        'teamBId': 'tb',
        'xiA': ['a1', 'a2', 'a3', 'a4'],
        'xiB': ['b1', 'b2', 'b3', 'b4'],
        'oversLimit': 2,
        'ballsPerOver': 6,
        'tossWinnerId': 'ta',
        'tossDecision': 'bat',
        'status': 'live',
        'innings': [
          good,
          'not-a-map',
          42,
          {'batting': 'broken'},
          good,
        ],
        'superOverInnings': ['junk', good],
      };
      final restored = Match.fromJson(payload);
      expect(restored.innings.length, 2);
      expect(restored.innings[0].totalRuns, 4);
      expect(restored.innings[1].totalRuns, 4);
      expect(restored.superOverInnings.length, 1);
    });
  });

  group('scoring edge paths', () {
    test('rapid double-tap records exactly two deliveries, no '
        'throw', () {
      final m = makeMatch(xiN: 4, overs: 2);
      final inn = openInnings(m);
      // Two identical taps with nothing awaited between them.
      expect(applyBall(inn, BallInput(batRuns: 4)), isTrue);
      expect(applyBall(inn, BallInput(batRuns: 4)), isTrue);
      expect(inn.legalBalls, 2);
      expect(inn.totalRuns, 8);
      expect(inn.events.length, 2);
    });

    test('background/foreground mid-match never touches local '
        'state (offline)', () async {
      SharedPreferences.setMockInitialValues({});
      final store = Store();
      await store.load();
      final m = makeMatch();
      store.matches = [m];
      SyncService().scoringActive = true;
      await SyncService().onAppResumed(store);
      expect(store.matches.length, 1);
      expect(identical(store.matches.first, m), isTrue);
      SyncService().scoringActive = false;
      await SyncService().onAppResumed(store);
      expect(store.matches.length, 1);
      expect(identical(store.matches.first, m), isTrue);
    });
  });

  group('points and stats over mixed records', () {
    InningsState totInn(
      String bat,
      String bowl,
      int runs,
      int balls, {
      int wickets = 3,
    }) {
      final inn = InningsState(
        battingTeamId: bat,
        bowlingTeamId: bowl,
        battingXI: xi(bat),
        bowlingXI: xi(bowl),
        oversLimit: 8,
        ballsPerOver: 6,
      );
      inn.totalRuns = runs;
      inn.legalBalls = balls;
      inn.wickets = wickets;
      return inn;
    }

    Match mk(
      String id,
      String a,
      String b,
      String status,
      String dateIso,
      List<InningsState> inns,
    ) {
      final m = Match(
        id: id,
        tournamentId: 't1',
        teamAId: a,
        teamBId: b,
        xiA: xi(a),
        xiB: xi(b),
        oversLimit: 8,
        ballsPerOver: 6,
        tossWinnerId: a,
        tossDecision: 'bat',
        dateIso: dateIso,
        status: status,
      );
      m.innings = inns;
      return m;
    }

    test('completed + live + totals-only + noResult', () {
      // (a) completed: ta 120/5 (48b) vs tb 121/3 (40b) -> tb wins.
      final ma = mk('a', 'ta', 'tb', 'completed', '2026-10-22', [
        totInn('ta', 'tb', 120, 48, wickets: 5),
        totInn('tb', 'ta', 121, 40, wickets: 3),
      ]);
      ma.innings[0].batting['p1'] = BatFig()
        ..runs = 50
        ..balls = 20
        ..fours = 4
        ..sixes = 2
        ..batted = true;
      ma.innings[0].bowling['q1'] = BowlFig()
        ..legalBalls = 12
        ..runs = 20
        ..wickets = 2;
      // (b) live: tc 30/1 (18b), must NOT count.
      final mb = mk('b', 'tc', 'td', 'live', '2026-10-23', [
        totInn('tc', 'td', 30, 18, wickets: 1),
      ]);
      mb.xiA.add('liveOnly1');
      // (c) totals-only completed (empty events/figures):
      // ta 130/4 (48b) vs tc 131/4 (46b) -> tc wins.
      final mc = mk('c', 'ta', 'tc', 'completed', '2026-10-24', [
        totInn('ta', 'tc', 130, 48, wickets: 4),
        totInn('tc', 'ta', 131, 46, wickets: 4),
      ]);
      // (d) noResult: tb vs td.
      final md = mk('d', 'tb', 'td', 'noResult', '2026-10-25', [
        totInn('tb', 'td', 40, 30, wickets: 2),
      ]);
      final matches = [ma, mb, mc, md];

      final table = computePointsTable('t1', ['ta', 'tb', 'tc', 'td'], matches);
      PointsRow row(String id) => table.firstWhere((r) => r.teamId == id);
      expect(row('tb').played, 2);
      expect(row('tb').won, 1);
      expect(row('tb').noResult, 1);
      expect(row('tb').points, 3);
      expect(row('tc').played, 1);
      expect(row('tc').won, 1);
      expect(row('tc').points, 2);
      expect(row('td').played, 1);
      expect(row('td').noResult, 1);
      expect(row('td').points, 1);
      expect(row('ta').played, 2);
      expect(row('ta').lost, 2);
      expect(row('ta').points, 0);
      expect(table.map((r) => r.teamId),
          ['tb', 'tc', 'td', 'ta']);
      for (final r in table) {
        expect(r.nrr.isFinite, isTrue);
      }

      final stats = computeCareerStats(matches);
      expect(stats['p1']!.runs, 50);
      expect(stats['p1']!.fifties, 1);
      expect(stats['p1']!.ballsFaced, 20);
      expect(stats['q1']!.wickets, 2);
      expect(stats['q1']!.ballsBowled, 12);
      // The live-only player never appears.
      expect(stats.containsKey('liveOnly1'), isFalse);
    });
  });

  group('debug info screen', () {
    tearDown(() {
      DebugInfo.lastError = null;
      DebugInfo.lastErrorAt = null;
    });

    testWidgets('renders recorded facts', (tester) async {
      SharedPreferences.setMockInitialValues({});
      DebugInfo.lastError = 'test boom error';
      final store = Store();
      await tester.pumpWidget(
        MaterialApp(
          home: DebugInfoScreen(store: store),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('test boom error'), findsOneWidget);
      expect(find.text(kAppVersion), findsOneWidget);
      expect(find.text('Matches stored'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('real dataset shape: 78 players with photos', () {
    test('96-ball match: full persist per ball is heavy, '
        'matches-only persist per ball is flat and low', () async {
      SharedPreferences.setMockInitialValues({});
      // 6 teams x 13 players = 78, each with a 64 KB inline photo
      // (~5 MB of teams JSON, matching the sweep's 4-8 MB measure).
      const photo = 'A';
      String photo64k() => List.filled(65536, photo).join();
      final photoStr = photo64k();
      Team photoTeam(String id, String p) => Team(
            id: id,
            name: 'Team $p',
            players: [
              for (var i = 1; i <= 13; i++)
                Player(id: '$p$i', name: 'Player $p$i', photoBase64: photoStr),
            ],
          );
      final store = Store();
      await store.load();
      store.teams = [
        photoTeam('ta', 'a'),
        photoTeam('tb', 'b'),
        photoTeam('tc', 'c'),
        photoTeam('td', 'd'),
        photoTeam('te', 'e'),
        photoTeam('tf', 'f'),
      ];
      final teamsJsonLen =
          jsonEncode(store.teams.map((t) => t.toJson()).toList()).length;
      expect(teamsJsonLen, greaterThan(4000000));

      // 19 upcoming skeletons + the scored match (realistic list).
      final skeleton = <Match>[];
      for (var i = 0; i < 19; i++) {
        skeleton.add(Match(
          id: 'up$i',
          teamAId: 'ta',
          teamBId: 'tb',
          xiA: xi('a'),
          xiB: xi('b'),
          oversLimit: 8,
          ballsPerOver: 6,
          tossWinnerId: 'ta',
          tossDecision: 'bat',
          dateIso: '2026-11-${10 + i}',
          status: 'upcoming',
        ));
      }
      final m = Match(
        id: 'photo_match',
        teamAId: 'ta',
        teamBId: 'tb',
        xiA: xi('a'),
        xiB: xi('b'),
        oversLimit: 8,
        ballsPerOver: 6,
        tossWinnerId: 'ta',
        tossDecision: 'bat',
        dateIso: '2026-10-25',
        status: 'live',
      );
      store.matches = [...skeleton, m];
      await store.persist();
      Future<String> teamsPrefsValue() async {
        final prefs = await SharedPreferences.getInstance();
        final key =
            prefs.getKeys().firstWhere((k) => k.contains('teams'));
        return prefs.getString(key) ?? '';
      }

      int matchesJsonLen() =>
          jsonEncode(store.matches.map((x) => x.toJson()).toList()).length;

      // Phase 1 (old path): innings 1, full persist per ball.
      final inn1 = openInnings(m);
      final beforeBytes = <int>[];
      final beforeMs = <int>[];
      const pattern = [0, 1, 2, 4, 6, 0, 1, 3];
      var wicketIdx = 0;
      var ballIndex = 0;
      final sw = Stopwatch();
      for (var over = 0; over < 8; over++) {
        for (var b = 0; b < 6; b++) {
          final isWicket = ballIndex % 12 == 11 && ballIndex < 47;
          final r = isWicket ? 0 : pattern[ballIndex % pattern.length];
          expect(
            applyBall(
              inn1,
              BallInput(
                batRuns: r,
                isWicket: isWicket,
                wicketType: isWicket ? 'bowled' : '',
              ),
            ),
            isTrue,
          );
          if (isWicket) {
            setNextBatter(inn1, ['a3', 'a4', 'a5'][wicketIdx++]);
          }
          sw
            ..reset()
            ..start();
          await store.persist();
          sw.stop();
          beforeMs.add(sw.elapsedMilliseconds);
          beforeBytes.add(teamsJsonLen + matchesJsonLen());
          ballIndex++;
        }
        if (over < 7) setBowler(inn1, 'b${over + 2}');
      }
      expect(inn1.legalBalls, 48);
      final beforeMedian = _median(beforeMs);
      final beforeFirst = beforeBytes.first;
      final beforeLast = beforeBytes.last;
      // The photo payload dominates every ball of the old path.
      expect(beforeFirst, greaterThan(4000000));
      expect(beforeLast, greaterThan(4000000));

      // Phase 2 (new path): innings 2, matches-only persist per ball.
      final teamsBeforePhase2 = await teamsPrefsValue();
      final inn2 = startInnings(m, 2);
      setOpeners(inn2, 'b1', 'b2', 'a1');
      final afterBytes = <int>[];
      final afterMs = <int>[];
      wicketIdx = 0;
      ballIndex = 0;
      for (var over = 0; over < 8; over++) {
        for (var b = 0; b < 6; b++) {
          final isWicket = ballIndex % 12 == 11 && ballIndex < 47;
          final r = isWicket ? 0 : ballIndex % 2;
          expect(
            applyBall(
              inn2,
              BallInput(
                batRuns: r,
                isWicket: isWicket,
                wicketType: isWicket ? 'bowled' : '',
              ),
            ),
            isTrue,
          );
          if (isWicket) {
            setNextBatter(inn2, ['b3', 'b4', 'b5'][wicketIdx++]);
          }
          sw
            ..reset()
            ..start();
          await store.persistMatchesOnly();
          sw.stop();
          afterMs.add(sw.elapsedMilliseconds);
          afterBytes.add(matchesJsonLen());
          ballIndex++;
        }
        if (over < 7) setBowler(inn2, 'a${over + 2}');
      }
      expect(inn2.legalBalls, 48);
      // Innings 2 stays far below the low-pattern target, so all 48
      // balls apply; innings 1 total (~91) is never reached.
      expect(inn2.totalRuns, lessThan(inn1.totalRuns));

      // The teams key is NEVER rewritten on the new path.
      expect(await teamsPrefsValue(), teamsBeforePhase2);
      // Flat and low: matches-only bytes stay in KBs and grow only
      // by the new events (last < 2x first); time collapses
      // versus the old path.
      expect(afterBytes.first, lessThan(500000));
      expect(afterBytes.last, lessThan(500000));
      expect(afterBytes.last, lessThan(2 * afterBytes.first));
      expect(afterBytes.last, lessThan(beforeLast ~/ 5));
      final afterMedian = _median(afterMs);
      expect(afterMedian, lessThanOrEqualTo(beforeMedian ~/ 5 + 2));
    });
  });
}

int _median(List<int> values) {
  final sorted = [...values]..sort();
  return sorted[sorted.length ~/ 2];
}
