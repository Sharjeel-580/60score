// v1.3.7 requirements: fixture edit/delete, wickets auto-derivation,
// tournament overs default, manual-stat edit.
//
// Owner reports behind these tests:
//  * an upcoming fixture could not be edited or deleted at all;
//  * stored fixtures carried 10 overs while the league plays 8 —
//    the tournament now owns the overs setting and setup defaults
//    come from it;
//  * wickets could still surface as 11 (legacy stored setting, or
//    an over-long XI feeding the XI − 1 derivation) — max wickets
//    must auto-derive as XI − 1 and never exceed 10;
//  * manual past-score entries could be added and deleted but not
//    edited.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cricket_scorer_app/models.dart';
import 'package:cricket_scorer_app/scoring.dart';
import 'package:cricket_scorer_app/store.dart';

List<String> xi(String prefix, int n) =>
    List.generate(n, (i) => '$prefix${i + 1}');

Match fixture({
  String id = 'fx1',
  String teamAId = 'ta',
  String teamBId = 'tb',
  List<String>? xiA,
  List<String>? xiB,
  String tossWinnerId = '',
  int totalWickets = 0,
  bool lastManStands = false,
  int oversLimit = 10,
  String? tournamentId,
}) {
  return Match(
    id: id,
    tournamentId: tournamentId,
    teamAId: teamAId,
    teamBId: teamBId,
    xiA: xiA ?? xi('a', 11),
    xiB: xiB ?? xi('b', 11),
    oversLimit: oversLimit,
    ballsPerOver: 6,
    venue: 'Old Venue',
    dateIso: '2026-10-24T14:00:00',
    tossWinnerId: tossWinnerId,
    status: 'upcoming',
    stage: 'league',
    matchTitle: 'Match 02',
    ballType: 'Tennis Ball',
    season: '2K26',
    totalWickets: totalWickets,
    lastManStands: lastManStands,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('applyFixtureEdit', () {
    test('updates every fixture field', () {
      final m = fixture();
      applyFixtureEdit(
        m,
        teamAId: 'ta',
        teamBId: 'tb',
        dateIso: '2026-10-25T15:15:00',
        venue: 'New Venue',
        oversLimit: 8,
        ballsPerOver: 6,
        matchTitle: 'Match 02 (revised)',
        stage: 'league',
        ballType: 'Leather Ball',
        season: '2K26',
      );
      expect(m.dateIso, '2026-10-25T15:15:00');
      expect(m.venue, 'New Venue');
      expect(m.oversLimit, 8);
      expect(m.matchTitle, 'Match 02 (revised)');
      expect(m.ballType, 'Leather Ball');
    });

    test('changing a team clears only that side\'s XI and an '
        'orphaned toss', () {
      final m = fixture(tossWinnerId: 'tb');
      applyFixtureEdit(
        m,
        teamAId: 'ta',
        teamBId: 'tc', // team B replaced
        dateIso: m.dateIso,
        venue: m.venue,
        oversLimit: 8,
        ballsPerOver: 6,
        matchTitle: m.matchTitle,
        stage: m.stage,
        ballType: m.ballType,
        season: m.season,
      );
      expect(m.teamBId, 'tc');
      expect(m.xiB, isEmpty); // old team's XI is gone
      expect(m.xiA, hasLength(11)); // untouched side keeps its XI
      expect(m.tossWinnerId, ''); // toss was for the replaced team
    });

    test('keeping both teams keeps XIs and the toss', () {
      final m = fixture(tossWinnerId: 'ta');
      applyFixtureEdit(
        m,
        teamAId: 'ta',
        teamBId: 'tb',
        dateIso: '2026-10-26T14:00:00',
        venue: 'Elsewhere',
        oversLimit: 8,
        ballsPerOver: 6,
        matchTitle: m.matchTitle,
        stage: m.stage,
        ballType: m.ballType,
        season: m.season,
      );
      expect(m.xiA, hasLength(11));
      expect(m.xiB, hasLength(11));
      expect(m.tossWinnerId, 'ta');
    });

    test('an edited fixture survives a store save + reload', () async {
      SharedPreferences.setMockInitialValues({});
      final s = Store();
      await s.activateIdentity('guest');
      final m = fixture();
      await s.upsertMatch(m);
      applyFixtureEdit(
        m,
        teamAId: 'ta',
        teamBId: 'tb',
        dateIso: '2026-10-25T15:15:00',
        venue: 'New Venue',
        oversLimit: 8,
        ballsPerOver: 6,
        matchTitle: 'Match 02 (revised)',
        stage: m.stage,
        ballType: m.ballType,
        season: m.season,
      );
      await s.upsertMatch(m);

      final s2 = Store();
      await s2.activateIdentity('guest');
      final back = s2.matchById('fx1');
      expect(back, isNotNull);
      expect(back!.oversLimit, 8);
      expect(back.venue, 'New Venue');
      expect(back.dateIso, '2026-10-25T15:15:00');
      expect(back.matchTitle, 'Match 02 (revised)');
    });

    test('deleting an upcoming fixture removes it for good', () async {
      SharedPreferences.setMockInitialValues({});
      final s = Store();
      await s.activateIdentity('guest');
      await s.upsertMatch(fixture());
      expect(s.matchById('fx1'), isNotNull);
      await s.deleteMatch('fx1');
      expect(s.matchById('fx1'), isNull);

      final s2 = Store();
      await s2.activateIdentity('guest');
      expect(s2.matchById('fx1'), isNull);
    });
  });

  group('wickets auto-derivation (v1.3.7)', () {
    test('a default 11-player setup yields maxWickets 10 with no '
        'manual step', () {
      final m = fixture()..status = 'live';
      final inn = startInnings(m, 1);
      expect(inn.maxWickets, 0); // still "auto"…
      expect(inn.effectiveMaxWickets, 10); // …deriving XI − 1
    });

    test('a legacy stored totalWickets of 11 clamps to 10', () {
      final m = fixture(totalWickets: 11)..status = 'live';
      final inn = startInnings(m, 1);
      expect(inn.effectiveMaxWickets, 10);
    });

    test('an over-long stored XI (12) cannot resurrect 11 wickets', () {
      final m = fixture(xiA: xi('a', 12), xiB: xi('b', 12))
        ..status = 'live';
      final inn = startInnings(m, 1);
      expect(inn.maxWickets, 10);
      expect(inn.effectiveMaxWickets, 10);
    });

    test('an over-long XI with a legacy 11 setting still caps at 10',
        () {
      final m = fixture(
        xiA: xi('a', 12),
        xiB: xi('b', 12),
        totalWickets: 11,
      )..status = 'live';
      final inn = startInnings(m, 1);
      expect(inn.effectiveMaxWickets, 10);
    });

    test('an explicit smaller setting is respected', () {
      final m = fixture(totalWickets: 8)..status = 'live';
      final inn = startInnings(m, 1);
      expect(inn.maxWickets, 8);
      expect(inn.effectiveMaxWickets, 8);
    });

    test('last-man-stands is untouched: every batter can fall', () {
      final m = fixture(lastManStands: true)..status = 'live';
      final inn = startInnings(m, 1);
      expect(inn.maxWickets, 11);
      expect(inn.effectiveMaxWickets, 11);
    });

    test('a stored 11-wicket innings with a 12-man XI loads as 10',
        () {
      final inn = InningsState(
        battingTeamId: 'ta',
        bowlingTeamId: 'tb',
        battingXI: xi('a', 12),
        bowlingXI: xi('b', 12),
        oversLimit: 8,
        ballsPerOver: 6,
      )..maxWickets = 11;
      final m = fixture()..innings.add(inn);
      final back = Match.fromJson(m.toJson());
      expect(back.innings.single.maxWickets, 10);
    });

    test('addToMatchXI refuses a 12th player', () {
      final m = fixture();
      expect(m.xiA, hasLength(11));
      expect(addToMatchXI(m, 'ta', 'a99'), isFalse);
      expect(m.xiA, hasLength(11));
      m.xiA = xi('a', 10);
      expect(addToMatchXI(m, 'ta', 'a99'), isTrue);
      expect(m.xiA, hasLength(11));
    });
  });

  group('tournament overs (v1.3.7)', () {
    test('a legacy tournament record without overs reads as 8', () {
      final t = Tournament.fromJson({'id': 't1', 'name': 'Legacy Cup'});
      expect(t.oversLimit, 8);
    });

    test('oversLimit round-trips through JSON', () {
      final t = Tournament(id: 't1', name: 'Cup', oversLimit: 12);
      final back = Tournament.fromJson(t.toJson());
      expect(back.oversLimit, 12);
    });
  });

  group('manual stat edit (v1.3.7)', () {
    ManualStatEntry entry(String id, int runs) => ManualStatEntry(
          id: id,
          playerId: 'p1',
          playerName: 'Player One',
          matchLabel: 'Past match',
          runs: runs,
          balls: 10,
        );

    test('upsertManualStat replaces in place, order stable', () async {
      SharedPreferences.setMockInitialValues({});
      final s = Store();
      await s.activateIdentity('guest');
      await s.addManualStat(entry('e1', 40));
      await s.addManualStat(entry('e2', 55));
      // Adds insert at the top: [e2, e1].
      expect(s.manualStats.map((e) => e.id), ['e2', 'e1']);
      await s.upsertManualStat(entry('e1', 42));
      expect(s.manualStats.map((e) => e.id), ['e2', 'e1']);
      expect(s.manualStats.last.runs, 42);
      // An unknown id behaves like an add.
      await s.upsertManualStat(entry('e3', 7));
      expect(s.manualStats.map((e) => e.id), ['e3', 'e2', 'e1']);
    });
  });
}
