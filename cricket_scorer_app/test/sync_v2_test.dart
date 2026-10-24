// Sync Fix "D", Phase C0 — tests for the NEW per-entity sync
// engine (lib/entity_sync.dart) and its Store/Firestore plumbing.
//
// The scenario numbering continues sync_simulation_test.dart:
// S1 bake clobber, S2 full rewind, S3 offline scoring exactly
// once, S4 concurrent edits, S5 fresh pull — re-run here against
// the PRODUCTION engine (the harness ran them against models of
// it) — plus the two scenarios the 2026-10-23 defects demand:
//   S6 delete resurrection: a deleted match must never come back;
//   S7 a no-result mark must survive a concurrent stale
//      'upcoming' copy.
// No production legacy code is touched by these tests' subject:
// compareMatchAdvancement / mergeMatches keep their own suites.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cricket_scorer_app/entity_firestore.dart';
import 'package:cricket_scorer_app/entity_sync.dart';
import 'package:cricket_scorer_app/models.dart';
import 'package:cricket_scorer_app/store.dart';
import 'package:cricket_scorer_app/sync_service.dart';

// ---------------- fixtures (mirroring the research harness) --------

List<String> xiIds(String p) => [for (var i = 1; i <= 11; i++) '$p$i'];

Team hawksTeam() => Team(
      id: 'hawks',
      name: 'Shazi Hawks',
      players: [
        for (var i = 1; i <= 11; i++) Player(id: 'h$i', name: 'Hawks Player $i')
      ],
    );

Team dolphinsTeam() => Team(
      id: 'dolphins',
      name: 'Adi Dolphins',
      players: [
        for (var i = 1; i <= 11; i++)
          Player(id: 'd$i', name: 'Dolphins Player $i')
      ],
    );

InningsState mkInn(
  String batId,
  String bowlId,
  String batP, {
  required int runs,
  required int wkts,
  required int balls,
  required int events,
  required int fow,
}) {
  final other = batP == 'h' ? 'd' : 'h';
  final inn = InningsState(
    battingTeamId: batId,
    bowlingTeamId: bowlId,
    battingXI: xiIds(batP),
    bowlingXI: xiIds(other),
    oversLimit: 8,
  );
  inn.totalRuns = runs;
  inn.wickets = wkts;
  inn.legalBalls = balls;
  for (var n = 0; n < events; n++) {
    inn.events.add(BallEvent(
      strikerId: '${batP}1',
      nonStrikerId: '${batP}2',
      bowlerId: '${other}1',
      totalRuns: 1,
      legalBall: true,
    ));
  }
  for (var n = 0; n < fow; n++) {
    inn.fallOfWickets.add(FallOfWicket(
        n + 1, (runs * (n + 1) / (fow + 1)).round(), '${n ~/ 6}.${n % 6}',
        '$batP${n + 1}'));
  }
  return inn;
}

/// The completed Match 01; fow counts are the ONLY difference
/// between the cloud-baked copy (8/2) and the stale copy (5/0).
Match m1({required int fow1, required int fow2}) => Match(
      id: 'm1',
      teamAId: 'hawks',
      teamBId: 'dolphins',
      xiA: xiIds('h'),
      xiB: xiIds('d'),
      tossWinnerId: 'hawks',
      status: 'completed',
      resultText: 'Adi Dolphins won by 8 wickets',
      innings: [
        mkInn('hawks', 'dolphins', 'h',
            runs: 117, wkts: 8, balls: 48, events: 52, fow: fow1),
        mkInn('dolphins', 'hawks', 'd',
            runs: 118, wkts: 2, balls: 40, events: 44, fow: fow2),
      ],
    );

Match m1LiveOld() => Match(
      id: 'm1',
      teamAId: 'hawks',
      teamBId: 'dolphins',
      xiA: xiIds('h'),
      xiB: xiIds('d'),
      tossWinnerId: 'hawks',
      status: 'live',
      resultText: '',
      innings: [
        mkInn('hawks', 'dolphins', 'h',
            runs: 68, wkts: 5, balls: 30, events: 34, fow: 3),
      ],
    );

Match m2() => Match(
      id: 'm2',
      teamAId: 'dolphins',
      teamBId: 'hawks',
      xiA: xiIds('d'),
      xiB: xiIds('h'),
      tossWinnerId: 'dolphins',
      status: 'completed',
      resultText: 'Shazi Hawks won by 6 wickets',
      innings: [
        mkInn('dolphins', 'hawks', 'd',
            runs: 96, wkts: 6, balls: 48, events: 50, fow: 6),
        mkInn('hawks', 'dolphins', 'h',
            runs: 97, wkts: 4, balls: 45, events: 47, fow: 4),
      ],
    );

Match m2WithStatus(String status, String resultText) => Match(
      id: 'm2',
      teamAId: 'dolphins',
      teamBId: 'hawks',
      xiA: xiIds('d'),
      xiB: xiIds('h'),
      tossWinnerId: '',
      status: status,
      resultText: resultText,
      innings: [],
    );

int fowTotal(Match m) =>
    m.innings.fold(0, (a, i) => a + i.fallOfWickets.length);

// ---------------- engine helpers -----------------------------------

StampedRecord mRec(Match m, int stamp, {bool restored = false}) =>
    StampedRecord(m.toJson(), stamp: stamp, restored: restored);

StampedRecord tRec(Team t, int stamp, [Map<String, int>? pStamps]) =>
    StampedRecord(t.toJson(),
        stamp: stamp,
        playerStamps:
            pStamps ?? {for (final p in t.players) p.id: stamp});

EntitySet mkSet({
  List<StampedRecord> matches = const [],
  List<StampedRecord> teams = const [],
  List<Tombstone> tombs = const [],
}) {
  final s = emptyEntitySet();
  for (final r in matches) {
    s[EntityKind.matches]![r.id] = r;
  }
  for (final r in teams) {
    s[EntityKind.teams]![r.id] = r;
  }
  for (final t in tombs) {
    s[EntityKind.tombstones]![t.docId] = tombstoneToRecord(t);
  }
  return s;
}

EntitySet baseSet() => mkSet(
      matches: [mRec(m1(fow1: 8, fow2: 2), 200)],
      teams: [tRec(hawksTeam(), 100), tRec(dolphinsTeam(), 100)],
    );

EntitySet staleSetB() => mkSet(
      matches: [mRec(m1(fow1: 5, fow2: 0), 90)],
      teams: [tRec(hawksTeam(), 100), tRec(dolphinsTeam(), 100)],
    );

Match? matchIn(EntitySet s, String id) {
  final r = s[EntityKind.matches]?[id];
  return r == null ? null : Match.fromJson(r.json);
}

Team? teamIn(EntitySet s, String id) {
  final r = s[EntityKind.teams]?[id];
  return r == null ? null : Team.fromJson(r.json);
}

bool hasTombstone(EntitySet s, String kind, String id) =>
    tombstoneFor(tombstonesOf(s), kind, id) != null;

void main() {
  group('V2 ranking (lib/entity_sync.dart)', () {
    test('status rank table agrees with the legacy production table',
        () {
      for (final s in [
        'completed',
        'noResult',
        'cancelled',
        'live',
        'upcoming',
        'scheduled',
        'something-else',
      ]) {
        expect(entityMatchStatusRank(s), SyncService.matchStatusRank(s),
            reason: 'status $s');
      }
    });

    test('a FoW-only enrichment is VISIBLE to V2 (the exact case '
        'the legacy ranking ties at 0)', () {
      final baked = m1(fow1: 8, fow2: 2);
      final stale = m1(fow1: 5, fow2: 0);
      // Legacy blindness, pinned by the research harness:
      expect(SyncService.compareMatchAdvancement(baked, stale), 0);
      // V2 sees it:
      expect(compareMatchAdvancementV2(baked, stale), greaterThan(0));
      expect(compareMatchAdvancementV2(stale, baked), lessThan(0));
    });

    test('merge is order-independent (convergence)', () {
      final a = mRec(m1(fow1: 8, fow2: 2), 200);
      final b = mRec(m1(fow1: 5, fow2: 0), 90);
      final ab = mergeMatchRecords(a, b);
      final ba = mergeMatchRecords(b, a);
      expect(jsonEncode(ab.json), jsonEncode(ba.json));
      expect(fowTotal(Match.fromJson(ab.json)), 10);
    });
  });

  group('Scenarios S1–S5 on the production engine '
      '(per-entity docs, read-modify-write)', () {
    test('S1 bake clobber: PASSES — baked FoW kept, offline-added '
        'player kept', () async {
      final cloud = InMemoryEntityDocStore(baseSet());
      final bSet = staleSetB();
      // B adds a player offline (team stamp 300, player stamp 300).
      final hawks = teamIn(bSet, 'hawks')!;
      hawks.players.add(Player(id: 'h99', name: 'New Player h99'));
      final ps = {
        for (final p in hawksTeam().players) p.id: 100,
        'h99': 300,
      };
      bSet[EntityKind.teams]!['hawks'] = tRec(hawks, 300, ps);
      final devB = InMemoryEntityDocStore(bSet);

      await synchronizeEntityStores(devB, cloud);
      final cloudSet = await cloud.readAll();
      expect(fowTotal(matchIn(cloudSet, 'm1')!), 10);
      expect(
          teamIn(cloudSet, 'hawks')!
              .players
              .any((p) => p.id == 'h99'),
          isTrue);
      // And B converged to the same state.
      final bAfter = await devB.readAll();
      expect(fowTotal(matchIn(bAfter, 'm1')!), 10);
    });

    test('S2 full rewind: PASSES — day-old live copy cannot un-complete '
        'M1; the new match still lands', () async {
      final cloud = InMemoryEntityDocStore(baseSet());
      final bSet = mkSet(
        matches: [mRec(m1LiveOld(), 90), mRec(m2(), 310)],
        teams: [tRec(hawksTeam(), 100), tRec(dolphinsTeam(), 100)],
      );
      final devB = InMemoryEntityDocStore(bSet);
      await synchronizeEntityStores(devB, cloud);
      final cloudSet = await cloud.readAll();
      expect(matchIn(cloudSet, 'm1')!.status, 'completed');
      expect(fowTotal(matchIn(cloudSet, 'm1')!), 10);
      expect(matchIn(cloudSet, 'm2'), isNotNull);
    });

    test('S3 offline scoring: PASSES — lands exactly once', () async {
      final cloud = InMemoryEntityDocStore(baseSet());
      final bSet = baseSet();
      bSet[EntityKind.matches]!['m2'] = mRec(m2(), 310);
      final devB = InMemoryEntityDocStore(bSet);
      await synchronizeEntityStores(devB, cloud);
      await synchronizeEntityStores(devB, cloud);
      final cloudSet = await cloud.readAll();
      expect(cloudSet[EntityKind.matches]!.keys.where((k) => k == 'm2'),
          hasLength(1));
      expect(cloudSet[EntityKind.matches]!.length, 2);
    });

    test('S4 concurrent edits: PASSES — rename and add both survive',
        () async {
      final cloud = InMemoryEntityDocStore(baseSet());
      // A renames the captain (player stamp 500).
      final aSet = baseSet();
      final ha = teamIn(aSet, 'hawks')!;
      ha.players.first.name = 'Renamed Captain';
      aSet[EntityKind.teams]!['hawks'] = tRec(ha, 500, {
        for (final p in hawksTeam().players) p.id: 100,
        'h1': 500,
      });
      final devA = InMemoryEntityDocStore(aSet);
      await synchronizeEntityStores(devA, cloud);
      // B (working from the pre-rename copy) adds a player.
      final bSet = baseSet();
      final hb = teamIn(bSet, 'hawks')!;
      hb.players.add(Player(id: 'h98', name: 'New Player h98'));
      bSet[EntityKind.teams]!['hawks'] = tRec(hb, 400, {
        for (final p in hawksTeam().players) p.id: 100,
        'h98': 400,
      });
      final devB = InMemoryEntityDocStore(bSet);
      await synchronizeEntityStores(devB, cloud);
      final cloudSet = await cloud.readAll();
      final hawks = teamIn(cloudSet, 'hawks')!;
      expect(hawks.players.first.name, 'Renamed Captain');
      expect(hawks.players.any((p) => p.id == 'h98'), isTrue);
    });

    test('S5 fresh pull: PASSES — a stale device ends with the union',
        () async {
      final cloud = InMemoryEntityDocStore(baseSet());
      final bSet = staleSetB();
      bSet[EntityKind.matches]!['m2'] = mRec(m2(), 310);
      await synchronizeEntityStores(InMemoryEntityDocStore(bSet), cloud);
      final devA = InMemoryEntityDocStore(staleSetB());
      await synchronizeEntityStores(devA, cloud);
      final aSet = await devA.readAll();
      expect(fowTotal(matchIn(aSet, 'm1')!), 10);
      expect(matchIn(aSet, 'm2'), isNotNull);
    });
  });

  group('S6 — delete resurrection (the 2026-10-23 defect)', () {
    test('a deleted match never comes back: not from a stale '
        'device, not from a blind re-add', () async {
      final cloud = InMemoryEntityDocStore(baseSet());
      final devA = InMemoryEntityDocStore(baseSet());
      final devB = InMemoryEntityDocStore(baseSet());
      await synchronizeEntityStores(devA, cloud);
      await synchronizeEntityStores(devB, cloud);

      // A deletes the match: record gone locally, tombstone written.
      final aSet = await devA.readAll();
      aSet[EntityKind.matches]!.remove('m1');
      final tomb = Tombstone(
          kind: EntityKind.matches, id: 'm1', deletedAt: 300);
      aSet[EntityKind.tombstones]![tomb.docId] = tombstoneToRecord(tomb);
      devA.sets = aSet;
      await synchronizeEntityStores(devA, cloud);
      var cloudSet = await cloud.readAll();
      expect(matchIn(cloudSet, 'm1'), isNull);
      expect(hasTombstone(cloudSet, EntityKind.matches, 'm1'), isTrue);

      // B still holds the pre-delete copy and syncs: it must LOSE
      // the match, not resurrect it.
      await synchronizeEntityStores(devB, cloud);
      final bSetAfter = await devB.readAll();
      expect(matchIn(bSetAfter, 'm1'), isNull);
      cloudSet = await cloud.readAll();
      expect(matchIn(cloudSet, 'm1'), isNull);

      // A legacy blind writer re-adds the record directly to the
      // cloud docs (no tombstone awareness — the old build's push
      // behaviour). The next new-build sync kills it again.
      await cloud.applyDiff(EntityDiff()
        ..upserts[EntityKind.matches] = {
          'm1': mRec(m1(fow1: 8, fow2: 2), 200),
        });
      expect(matchIn(await cloud.readAll(), 'm1'), isNotNull);
      await synchronizeEntityStores(devA, cloud);
      cloudSet = await cloud.readAll();
      expect(matchIn(cloudSet, 'm1'), isNull);
      expect(hasTombstone(cloudSet, EntityKind.matches, 'm1'), isTrue);
    });

    test('the ONLY way back is an explicit admin restore: restored '
        'flag + a stamp newer than the deletion', () async {
      final cloud = InMemoryEntityDocStore(baseSet());
      final devA = InMemoryEntityDocStore(baseSet());
      await synchronizeEntityStores(devA, cloud);
      final aSet = await devA.readAll();
      aSet[EntityKind.matches]!.remove('m1');
      final tomb = Tombstone(
          kind: EntityKind.matches, id: 'm1', deletedAt: 300);
      aSet[EntityKind.tombstones]![tomb.docId] = tombstoneToRecord(tomb);
      devA.sets = aSet;
      await synchronizeEntityStores(devA, cloud);
      expect(matchIn(await cloud.readAll(), 'm1'), isNull);

      // A plain newer-stamp copy (NOT flagged restored) stays dead:
      final sneaky = await devA.readAll();
      sneaky[EntityKind.matches]!['m1'] =
          mRec(m1(fow1: 8, fow2: 2), 999);
      devA.sets = sneaky;
      await synchronizeEntityStores(devA, cloud);
      expect(matchIn(await cloud.readAll(), 'm1'), isNull);

      // The explicit restore revives it and spends the tombstone
      // on both sides.
      final restored = await devA.readAll();
      restored[EntityKind.matches]!['m1'] =
          mRec(m1(fow1: 8, fow2: 2), 1000, restored: true);
      devA.sets = restored;
      await synchronizeEntityStores(devA, cloud);
      final cloudSet = await cloud.readAll();
      expect(matchIn(cloudSet, 'm1'), isNotNull);
      expect(hasTombstone(cloudSet, EntityKind.matches, 'm1'), isFalse);
      final aAfter = await devA.readAll();
      expect(hasTombstone(aAfter, EntityKind.matches, 'm1'), isFalse);
    });
  });

  group('S7 — no-result mark vs concurrent stale upcoming copy', () {
    test('the noResult mark survives, in both sync orders', () async {
      for (final aFirst in [true, false]) {
        final cloud = InMemoryEntityDocStore(mkSet(matches: [
          mRec(m2WithStatus('upcoming', ''), 100),
        ]));
        final devA = InMemoryEntityDocStore(mkSet(matches: [
          mRec(m2WithStatus('noResult', 'No result'), 200),
        ]));
        final devB = InMemoryEntityDocStore(mkSet(matches: [
          mRec(m2WithStatus('upcoming', ''), 100),
        ]));
        if (aFirst) {
          await synchronizeEntityStores(devA, cloud);
          await synchronizeEntityStores(devB, cloud);
        } else {
          await synchronizeEntityStores(devB, cloud);
          await synchronizeEntityStores(devA, cloud);
          // B syncs once more, still holding its stale copy:
          await synchronizeEntityStores(devB, cloud);
        }
        final cloudSet = await cloud.readAll();
        expect(matchIn(cloudSet, 'm2')!.status, 'noResult',
            reason: 'aFirst=$aFirst');
        expect(matchIn(cloudSet, 'm2')!.resultText, 'No result');
        final bSet = await devB.readAll();
        expect(matchIn(bSet, 'm2')!.status, 'noResult',
            reason: 'aFirst=$aFirst');
      }
    });

    test('the gate rejects the stale upcoming write outright', () {
      expect(
        gateMatchWrite(
          incoming: mRec(m2WithStatus('upcoming', ''), 100),
          stored: mRec(m2WithStatus('noResult', 'No result'), 200),
        ),
        GateVerdict.rejectDowngrade,
      );
    });
  });

  group('Server gate (Phase D spec)', () {
    test('rogue legacy writer: every downgrade rejected — honest '
        'stamp, forged stamp, day-old live copy — while a genuinely '
        'new match is accepted', () {
      final stored = mRec(m1(fow1: 8, fow2: 2), 200);
      expect(
          gateMatchWrite(
              incoming: mRec(m1(fow1: 5, fow2: 0), 90), stored: stored),
          GateVerdict.rejectDowngrade);
      expect(
          gateMatchWrite(
              incoming: mRec(m1(fow1: 5, fow2: 0), 999), stored: stored),
          GateVerdict.rejectDowngrade,
          reason: 'a forged fresh stamp must not help');
      expect(
          gateMatchWrite(incoming: mRec(m1LiveOld(), 999), stored: stored),
          GateVerdict.rejectDowngrade);
      expect(gateMatchWrite(incoming: mRec(m2(), 50)),
          GateVerdict.accept);
    });

    test('equal content with an older stamp is rejected as stale', () {
      expect(
        gateMatchWrite(
          incoming: mRec(m1(fow1: 8, fow2: 2), 150),
          stored: mRec(m1(fow1: 8, fow2: 2), 200),
        ),
        GateVerdict.rejectStaleStamp,
      );
    });

    test('a tombstoned write is rejected; the restored write is not',
        () {
      final tomb = Tombstone(
          kind: EntityKind.matches, id: 'm1', deletedAt: 300);
      expect(
        gateMatchWrite(
            incoming: mRec(m1(fow1: 8, fow2: 2), 999), tombstone: tomb),
        GateVerdict.rejectTombstoned,
      );
      expect(
        gateMatchWrite(
            incoming: mRec(m1(fow1: 8, fow2: 2), 1000, restored: true),
            tombstone: tomb),
        GateVerdict.accept,
      );
    });
  });

  group('Tombstone + Firestore codec plumbing', () {
    test('tombstone JSON round-trips; set merge keeps the newest '
        'deletion', () {
      final t = Tombstone(
          kind: EntityKind.matches,
          id: 'm1',
          deletedAt: 300,
          deviceId: 'dev-a');
      final back = Tombstone.fromJson(
          jsonDecode(jsonEncode(t.toJson())) as Map<String, dynamic>);
      expect(back.kind, 'matches');
      expect(back.id, 'm1');
      expect(back.deletedAt, 300);
      expect(back.docId, 'matches__m1');
      final merged = mergeTombstoneSets([t], [
        Tombstone(kind: EntityKind.matches, id: 'm1', deletedAt: 250),
      ]);
      expect(merged.single.deletedAt, 300);
    });

    test('match doc fields carry the structured guard values', () {
      final fields = FirestoreEntityDocStore.docFieldsFor(
          EntityKind.matches, 'm1', mRec(m1(fow1: 8, fow2: 2), 200));
      expect(fields['status'], 'completed');
      expect(fields['fowCount'], 10);
      expect(fields['legalBalls'], 88);
      expect(fields['eventCount'], 96);
      expect(fields['entityUpdatedAt'], 200);
      final back = FirestoreEntityDocStore.recordFromDoc(fields);
      expect(back.stamp, 200);
      expect(Match.fromJson(back.json).id, 'm1');
    });

    test('team doc fields round-trip per-player stamps', () {
      final rec = tRec(hawksTeam(), 100, {'h1': 500, 'h2': 100});
      final fields = FirestoreEntityDocStore.docFieldsFor(
          EntityKind.teams, 'hawks', rec);
      final back = FirestoreEntityDocStore.recordFromDoc(fields);
      expect(back.playerStamps['h1'], 500);
      expect(back.playerStamps['h2'], 100);
    });
  });

  group('Store tombstones (local recording + blob bridge state)',
      () {
    TestWidgetsFlutterBinding.ensureInitialized();

    Match bareMatch(String id) => Match(
          id: id,
          teamAId: 'a',
          teamBId: 'b',
          xiA: const [],
          xiB: const [],
          tossWinnerId: '',
          status: 'completed',
          resultText: '',
          innings: const [],
        );

    test('deleteMatch records a tombstone that survives a reload; '
        're-adding the match clears it (admin restore)', () async {
      SharedPreferences.setMockInitialValues({});
      final s = Store();
      await s.activateIdentity('guest');
      await s.upsertMatch(bareMatch('m-del'));
      expect(s.tombstones, isEmpty);
      await s.deleteMatch('m-del');
      expect(s.matches, isEmpty);
      expect(s.tombstonedMatchIds, contains('m-del'));

      // A fresh Store over the same prefs sees the tombstone:
      // the deletion is durable local state, not a memory.
      final s2 = Store();
      await s2.activateIdentity('guest');
      expect(s2.matches, isEmpty);
      expect(s2.tombstonedMatchIds, contains('m-del'));

      await s2.upsertMatch(bareMatch('m-del'));
      expect(s2.tombstonedMatchIds, isNot(contains('m-del')));
      expect(s2.matches.map((m) => m.id), contains('m-del'));
    });

    test('tombstones are per-identity, like all other data', () async {
      SharedPreferences.setMockInitialValues({});
      final s = Store();
      await s.activateIdentity('uid-a');
      await s.upsertMatch(bareMatch('m-a'));
      await s.deleteMatch('m-a');
      expect(s.tombstonedMatchIds, contains('m-a'));
      await s.activateIdentity('guest');
      expect(s.tombstonedMatchIds, isEmpty);
      await s.activateIdentity('uid-a');
      expect(s.tombstonedMatchIds, contains('m-a'));
    });

    test('absorbTombstones unions and never shrinks the local set',
        () async {
      SharedPreferences.setMockInitialValues({});
      final s = Store();
      await s.activateIdentity('guest');
      await s.upsertMatch(bareMatch('m-x'));
      await s.deleteMatch('m-x');
      final localDeletedAt = s.tombstones.single.deletedAt;
      final changed = s.absorbTombstones([
        Tombstone(
            kind: EntityKind.matches, id: 'm-y', deletedAt: 12345),
        Tombstone(
            kind: EntityKind.matches,
            id: 'm-x',
            deletedAt: localDeletedAt - 1000),
      ]);
      expect(changed, isTrue);
      expect(s.tombstonedMatchIds, containsAll(['m-x', 'm-y']));
      // The older remote copy of m-x's tombstone did not rewind it:
      expect(
          s.tombstones
              .firstWhere((t) => t.id == 'm-x')
              .deletedAt,
          localDeletedAt);
    });

    test('restoring from a backup import clears the tombstone',
        () async {
      SharedPreferences.setMockInitialValues({});
      final s = Store();
      await s.activateIdentity('guest');
      await s.upsertMatch(bareMatch('m-r'));
      await s.deleteMatch('m-r');
      expect(s.tombstonedMatchIds, contains('m-r'));
      await s.importJson({
        'matches': [bareMatch('m-r').toJson()],
      });
      expect(s.matches.map((m) => m.id), contains('m-r'));
      expect(s.tombstonedMatchIds, isNot(contains('m-r')));
    });
  });
}
