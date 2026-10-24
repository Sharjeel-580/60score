// Sync Fix "D", Phase C1 — tests for the WIRED entity sync:
// the coordinator (lib/entity_sync_coordinator.dart) that
// SyncService now runs behind its existing public API.
//
// Coverage, per the plan's Phase C1 list:
//   (i)   migration from a blob-shaped dataset produces
//         identical entity sets (per-kind counts + spot
//         figures), tombstones seeded, blob left untouched;
//   (ii)  migration is idempotent — a second run writes nothing;
//   (iii) dual-read prefers the entity documents over a stale
//         blob, while still absorbing blob-only records (an old
//         build's fresh data) into both sides;
//   (iv)  a delta push touches only the changed entity;
//   (v)   S6 (delete resurrection) and S7 (no-result mark)
//         through the SyncService-level path: a real Store behind
//         the production StoreEntityDocStore adapter, syncing
//         against an in-memory cloud.
// Legacy suites keep pinning the legacy code; nothing here
// touches it.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cricket_scorer_app/account_profile.dart';
import 'package:cricket_scorer_app/entity_sync.dart';
import 'package:cricket_scorer_app/entity_sync_coordinator.dart';
import 'package:cricket_scorer_app/models.dart';
import 'package:cricket_scorer_app/photo_sync.dart';
import 'package:cricket_scorer_app/store.dart';

// ---------------- fixtures -------------------------------------

List<String> xiIds(String p) => [for (var i = 1; i <= 11; i++) '$p$i'];

Team hawksTeam({String name = 'Shazi Hawks'}) => Team(
      id: 'hawks',
      name: name,
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
  for (var n = 0; n < fow; n++) {
    inn.fallOfWickets.add(FallOfWicket(
        n + 1, (runs * (n + 1) / (fow + 1)).round(), '${n ~/ 6}.${n % 6}',
        '$batP${n + 1}'));
  }
  return inn;
}

/// The completed Match 01; FoW counts are the only difference
/// between the rich (cloud-baked) and stale copies.
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
            runs: 117, wkts: 8, balls: 48, fow: fow1),
        mkInn('dolphins', 'hawks', 'd',
            runs: 118, wkts: 2, balls: 40, fow: fow2),
      ],
    );

Match m3() => Match(
      id: 'm3',
      teamAId: 'dolphins',
      teamBId: 'hawks',
      xiA: xiIds('d'),
      xiB: xiIds('h'),
      tossWinnerId: 'dolphins',
      status: 'completed',
      resultText: 'Shazi Hawks won by 6 wickets',
      innings: [
        mkInn('dolphins', 'hawks', 'd',
            runs: 96, wkts: 6, balls: 48, fow: 6),
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

StampedRecord mRec(Match m, int stamp) =>
    StampedRecord(m.toJson(), stamp: stamp);

StampedRecord tRec(Team t, int stamp) => StampedRecord(
      PhotoSync.stripPhotos(t.toJson()),
      stamp: stamp,
      playerStamps: {for (final p in t.players) p.id: stamp},
    );

Match? matchIn(EntitySet s, String id) {
  final r = s[EntityKind.matches]?[id];
  return r == null ? null : Match.fromJson(r.json);
}

Team? teamIn(EntitySet s, String id) {
  final r = s[EntityKind.teams]?[id];
  return r == null ? null : Team.fromJson(r.json);
}

/// An EntityDocStore that remembers every diff it was asked to
/// apply — the witness for "delta push" and idempotency claims.
class RecordingEntityDocStore extends InMemoryEntityDocStore {
  final List<EntityDiff> applied = [];
  RecordingEntityDocStore([super.initial]);

  @override
  Future<void> applyDiff(EntityDiff diff) async {
    applied.add(diff);
    await super.applyDiff(diff);
  }
}

/// A legacy backup document as a raw field map — JSON strings,
/// exactly as Firestore returns them — holding a full little
/// dataset, one tombstone, and updatedAt 5000.
Map<String, dynamic> blobData({
  List<Match>? matches,
  String hawksName = 'Shazi Hawks',
}) {
  return {
    'teams': jsonEncode([
      PhotoSync.stripPhotos(hawksTeam(name: hawksName).toJson()),
      PhotoSync.stripPhotos(dolphinsTeam().toJson()),
    ]),
    'tournaments': jsonEncode([
      Tournament(
        id: 't1',
        name: 'Super Sixty League',
        teamIds: const ['hawks', 'dolphins'],
      ).toJson(),
    ]),
    'matches': jsonEncode((matches ?? [m1(fow1: 8, fow2: 2)])
        .map((m) => m.toJson())
        .toList()),
    'regPlayers': jsonEncode([
      RegPlayer(id: 'rp1', name: 'Reg One').toJson(),
    ]),
    'drafts': jsonEncode([
      Draft(id: 'dr1', name: 'Draft 1', teamIds: const ['hawks'],
              squadSize: 11)
          .toJson(),
    ]),
    'manualStats': jsonEncode([
      ManualStatEntry(
              id: 'ms1', playerId: 'h1', playerName: 'Hawks Player 1',
              runs: 55)
          .toJson(),
    ]),
    'profile': jsonEncode(
        AccountProfile.create(uid: 'uid-blob', displayName: 'Owner')
            .toJson()),
    'tombstones': jsonEncode([
      Tombstone(kind: EntityKind.matches, id: 'm-dead', deletedAt: 4000)
          .toJson(),
    ]),
    'updatedAt': 5000,
    'appVersion': '1.2.0',
  };
}

void main() {
  group('Phase C1 migration (plan §6)', () {
    test('(i) a blob-shaped dataset converts to identical entity '
        'sets — counts and spot figures', () async {
      final cloud = RecordingEntityDocStore();
      var migrated = false;
      final coord = EntitySyncCoordinator(
        local: InMemoryEntityDocStore(),
        cloud: cloud,
        blobSource: InMemoryBlobSource(entitySetFromBlobData(blobData())),
        migrationDone: () async => migrated,
        markMigrationDone: () async => migrated = true,
      );

      final result = await coord.runMigrationIfNeeded();
      expect(result.ran, isTrue);
      expect(result.ok, isTrue, reason: result.detail);
      expect(migrated, isTrue);
      expect(result.counts[EntityKind.matches], 1);
      expect(result.counts[EntityKind.teams], 2);
      expect(result.counts[EntityKind.tournaments], 1);
      expect(result.counts[EntityKind.regPlayers], 1);
      expect(result.counts[EntityKind.drafts], 1);
      expect(result.counts[EntityKind.manualStats], 1);
      expect(result.counts[EntityKind.profile], 1);
      expect(result.counts[EntityKind.tombstones], 1);

      final set = await cloud.readAll();
      // Spot figures: Match 01's innings and FoW, exactly.
      final match = matchIn(set, 'm1')!;
      expect(match.innings[0].totalRuns, 117);
      expect(match.innings[0].wickets, 8);
      expect(match.innings[0].legalBalls, 48);
      expect(match.innings[1].totalRuns, 118);
      expect(match.innings[1].wickets, 2);
      expect(match.innings[1].legalBalls, 40);
      expect(fowTotal(match), 10);
      // Spot figure: the largest team's player count.
      expect(teamIn(set, 'hawks')!.players, hasLength(11));
      // The profile rode along as the singleton record.
      final profile = set[EntityKind.profile]!['profile']!;
      expect(profile.json['displayName'], 'Owner');
      // The blob's tombstone was seeded as a tombstone document.
      expect(
          tombstoneFor(tombstonesOf(set), EntityKind.matches, 'm-dead'),
          isNotNull);
      // Every exploded record carries the blob's stamp (its age).
      expect(set[EntityKind.matches]!['m1']!.stamp, 5000);
      // The migration wrote exactly one non-empty diff.
      expect(cloud.applied.where((d) => !d.isEmpty), hasLength(1));
    });

    test('(ii) migration is idempotent: a second run changes '
        'nothing and writes nothing', () async {
      final cloud = RecordingEntityDocStore();
      EntitySyncCoordinator freshCoord() => EntitySyncCoordinator(
            local: InMemoryEntityDocStore(),
            cloud: cloud,
            blobSource:
                InMemoryBlobSource(entitySetFromBlobData(blobData())),
            // The flag is deliberately NOT shared: even if the
            // "already migrated" marker were lost, re-running the
            // migration must converge instead of duplicating.
            migrationDone: () async => false,
            markMigrationDone: () async {},
          );

      final first = await freshCoord().runMigrationIfNeeded();
      expect(first.ok, isTrue, reason: first.detail);
      final afterFirst = await cloud.readAll();
      cloud.applied.clear();

      final second = await freshCoord().runMigrationIfNeeded();
      expect(second.ok, isTrue, reason: second.detail);
      // No write reached the cloud at all, and the set is
      // byte-identical to the first run's result.
      expect(cloud.applied.where((d) => !d.isEmpty), isEmpty);
      final afterSecond = await cloud.readAll();
      for (final kind in [...EntityKind.all, EntityKind.tombstones]) {
        expect(afterSecond[kind]!.keys, afterFirst[kind]!.keys,
            reason: '$kind keys');
        for (final id in afterFirst[kind]!.keys) {
          expect(afterSecond[kind]![id]!.sameContent(afterFirst[kind]![id]!),
              isTrue,
              reason: '$kind/$id changed on re-run');
        }
      }
    });

    test('migration merges with entity documents that already '
        'exist (another device migrated first)', () async {
      final cloud = RecordingEntityDocStore(emptyEntitySet()
        ..[EntityKind.matches]!['m1'] = mRec(m1(fow1: 8, fow2: 2), 9000));
      final coord = EntitySyncCoordinator(
        local: InMemoryEntityDocStore(),
        cloud: cloud,
        blobSource: InMemoryBlobSource(
            entitySetFromBlobData(blobData(matches: [
          m1(fow1: 5, fow2: 0), // the stale blob copy must NOT win
        ]))),
        migrationDone: () async => false,
        markMigrationDone: () async {},
      );
      final result = await coord.runMigrationIfNeeded();
      expect(result.ok, isTrue, reason: result.detail);
      final set = await cloud.readAll();
      expect(fowTotal(matchIn(set, 'm1')!), 10);
      expect(set[EntityKind.matches]!['m1']!.stamp, 9000);
    });

    test('a count mismatch fails verification instead of '
        'declaring the migration done', () async {
      final expected = entitySetFromBlobData(blobData()).entities;
      final actual = entitySetFromBlobData(blobData()).entities;
      actual[EntityKind.teams]!.remove('dolphins');
      final verdict =
          EntitySyncCoordinator.verifyMigration(expected: expected, actual: actual);
      expect(verdict.ok, isFalse);
      expect(verdict.detail, contains('teams'));
    });
  });

  group('Phase C1 dual-read + delta push', () {
    test('(iii) dual-read prefers entity documents over a stale '
        'blob, and absorbs blob-only records into both sides',
        () async {
      // The entity collections hold the GOOD data (stamp 9000);
      // the blob is stale (updatedAt 100) but carries one record
      // the entity side has never seen (an old build's match).
      final cloud = InMemoryEntityDocStore(emptyEntitySet()
        ..[EntityKind.matches]!['m1'] = mRec(m1(fow1: 8, fow2: 2), 9000)
        ..[EntityKind.teams]!['hawks'] =
            tRec(hawksTeam(name: 'Entity Hawks'), 9000));
      final blob = entitySetFromBlobData(blobData(
        matches: [m1(fow1: 5, fow2: 0), m3()],
        hawksName: 'Blob Hawks',
      ));
      // Rewind the blob snapshot's stamps to its true (old) age —
      // blobData() stamps 5000; this scenario wants a stale blob.
      final staleBlob = BlobSnapshot(
        {
          for (final e in blob.entities.entries)
            e.key: {
              for (final r in e.value.entries)
                r.key: StampedRecord(r.value.json,
                    stamp: 100,
                    restored: r.value.restored,
                    playerStamps: {
                      for (final p in r.value.playerStamps.entries)
                        p.key: 100,
                    }),
            },
        },
        100,
      );
      final local = InMemoryEntityDocStore();
      final coord = EntitySyncCoordinator(
        local: local,
        cloud: cloud,
        blobSource: InMemoryBlobSource(staleBlob),
      );

      final round = await coord.syncRound();
      expect(round.localChanged, isTrue);
      expect(round.remoteSeen, isTrue);
      expect(round.remoteNonEmpty, isTrue);

      final localSet = await local.readAll();
      // Entity documents won over the stale blob:
      expect(fowTotal(matchIn(localSet, 'm1')!), 10);
      expect(teamIn(localSet, 'hawks')!.name, 'Entity Hawks');
      // The blob-only record was absorbed locally...
      expect(matchIn(localSet, 'm3'), isNotNull);
      // ...and pushed UP into the entity collections:
      final cloudSet = await cloud.readAll();
      expect(matchIn(cloudSet, 'm3'), isNotNull);
      expect(fowTotal(matchIn(cloudSet, 'm1')!), 10);
    });

    test('(iv) a delta push touches only the changed entity',
        () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      final store = Store();
      await store.activateIdentity('uid-c1');
      await store.upsertTeam(hawksTeam());
      await store.upsertTeam(dolphinsTeam());
      await store.upsertMatch(m1(fow1: 8, fow2: 2));

      var tick = 100000;
      int clock() => tick += 7;
      final adapter = StoreEntityDocStore(store, nowMs: clock);
      final cloud = RecordingEntityDocStore();
      final coord =
          EntitySyncCoordinator(local: adapter, cloud: cloud);

      final first = await coord.syncRound();
      expect(first.cloudChanged, isTrue);
      expect(matchIn(await cloud.readAll(), 'm1'), isNotNull);
      cloud.applied.clear();

      // One local change: the result text of the one match.
      store.matches
          .firstWhere((m) => m.id == 'm1')
          .resultText = 'Adi Dolphins won by 8 wickets (revised)';

      final second = await coord.syncRound();
      expect(second.cloudChanged, isTrue);
      expect(second.localChanged, isFalse,
          reason: 'the merge converged on the local copy itself');
      expect(cloud.applied, hasLength(1));
      final diff = cloud.applied.single;
      expect(diff.upserts.keys, ['matches']);
      expect(diff.upserts[EntityKind.matches]!.keys, ['m1']);
      expect(diff.deletes, isEmpty);
      expect(matchIn(await cloud.readAll(), 'm1')!.resultText,
          'Adi Dolphins won by 8 wickets (revised)');
    });
  });

  group('Phase C1 wired path — S6/S7 through a real Store', () {
    test('(v) S6: a match deleted on the Store never resurrects '
        'through the wired sync', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      final storeA = Store();
      await storeA.activateIdentity('uid-s6');
      await storeA.upsertTeam(hawksTeam());
      await storeA.upsertMatch(m1(fow1: 8, fow2: 2));

      var tick = 200000;
      int clock() => tick += 7;
      final cloud = InMemoryEntityDocStore();
      final coordA = EntitySyncCoordinator(
        local: StoreEntityDocStore(storeA, nowMs: clock),
        cloud: cloud,
      );
      await coordA.syncRound();
      expect(matchIn(await cloud.readAll(), 'm1'), isNotNull);

      // The real delete path: record removed + tombstone written.
      await storeA.deleteMatch('m1');
      expect(storeA.tombstonedMatchIds, contains('m1'));
      await coordA.syncRound();
      var cloudSet = await cloud.readAll();
      expect(matchIn(cloudSet, 'm1'), isNull);
      expect(
          tombstoneFor(tombstonesOf(cloudSet), EntityKind.matches, 'm1'),
          isNotNull);

      // A stale device still holding the pre-delete copy syncs:
      // it must LOSE the match, not resurrect it.
      final devB = InMemoryEntityDocStore(emptyEntitySet()
        ..[EntityKind.matches]!['m1'] = mRec(m1(fow1: 8, fow2: 2), 300));
      await EntitySyncCoordinator(local: devB, cloud: cloud).syncRound();
      expect(matchIn(await devB.readAll(), 'm1'), isNull);
      cloudSet = await cloud.readAll();
      expect(matchIn(cloudSet, 'm1'), isNull);
    });

    test('(v) S7: the no-result mark made on the Store survives '
        'a concurrent stale upcoming copy', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      // Cloud already holds the fixture as 'upcoming'.
      final cloud = InMemoryEntityDocStore(emptyEntitySet()
        ..[EntityKind.matches]!['m2'] = mRec(m2WithStatus('upcoming', ''), 100));
      // Device A (the scoring phone) marks it No result — the
      // exact record shape Store persists for that action.
      final storeA = Store();
      await storeA.activateIdentity('uid-s7');
      await storeA.upsertMatch(m2WithStatus('noResult', 'No result'));

      var tick = 300000;
      int clock() => tick += 7;
      final coordA = EntitySyncCoordinator(
        local: StoreEntityDocStore(storeA, nowMs: clock),
        cloud: cloud,
      );
      await coordA.syncRound();
      var cloudSet = await cloud.readAll();
      expect(matchIn(cloudSet, 'm2')!.status, 'noResult');
      expect(matchIn(cloudSet, 'm2')!.resultText, 'No result');

      // Device B still holds the stale 'upcoming' copy and syncs
      // afterwards (the 2026-10-23 Match 02 shape):
      final devB = InMemoryEntityDocStore(emptyEntitySet()
        ..[EntityKind.matches]!['m2'] =
            mRec(m2WithStatus('upcoming', ''), 100));
      await EntitySyncCoordinator(local: devB, cloud: cloud).syncRound();
      cloudSet = await cloud.readAll();
      expect(matchIn(cloudSet, 'm2')!.status, 'noResult');
      expect(matchIn(await devB.readAll(), 'm2')!.status, 'noResult');
    });
  });
}
