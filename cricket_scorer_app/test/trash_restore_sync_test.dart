// Feature 1 follow-up (D batch): a Trash restore must survive the
// per-entity sync even though the CLOUD still holds the deletion
// tombstone. Regression test for the gap found in review: upsert
// clears the LOCAL tombstone at restore time, so without the
// Store's restored marker the restored record reached the merge
// un-flagged and the cloud tombstone killed it again.
//
// Harness mirrors test/sync_c1_test.dart (v): a real Store behind
// the production StoreEntityDocStore adapter, syncing against an
// in-memory cloud via EntitySyncCoordinator.syncRound.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cricket_scorer_app/entity_sync.dart';
import 'package:cricket_scorer_app/entity_sync_coordinator.dart';
import 'package:cricket_scorer_app/models.dart';
import 'package:cricket_scorer_app/store.dart';

List<String> xiIds(String p) => [for (var i = 1; i <= 11; i++) '$p$i'];

Team teamOf(String id, String name, String p) => Team(
      id: id,
      name: name,
      players: [
        for (var i = 1; i <= 11; i++) Player(id: '$p$i', name: '$name Player $i')
      ],
    );

Match matchM1() {
  InningsState inn(String bat, String bowl, String p, int runs) {
    final s = InningsState(
      battingTeamId: bat,
      bowlingTeamId: bowl,
      battingXI: xiIds(p),
      bowlingXI: xiIds(p == 'h' ? 'd' : 'h'),
      oversLimit: 8,
    );
    s.totalRuns = runs;
    s.wickets = 8;
    s.legalBalls = 48;
    return s;
  }

  return Match(
    id: 'm1',
    teamAId: 'hawks',
    teamBId: 'dolphins',
    xiA: xiIds('h'),
    xiB: xiIds('d'),
    tossWinnerId: 'hawks',
    status: 'completed',
    innings: [
      inn('hawks', 'dolphins', 'h', 117),
      inn('dolphins', 'hawks', 'd', 118),
    ],
  );
}

StampedRecord? matchIn(EntitySet set, String id) =>
    set[EntityKind.matches]![id];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('trash restore survives a sync round against the cloud '
      'tombstone, and the tombstone is spent', () async {
    SharedPreferences.setMockInitialValues({});
    final storeA = Store();
    await storeA.activateIdentity('uid-restore');
    await storeA.upsertTeam(teamOf('hawks', 'Shazi Hawks', 'h'));
    await storeA.upsertTeam(teamOf('dolphins', 'Adi Dolphins', 'd'));
    await storeA.upsertMatch(matchM1());

    var tick = 200000;
    int clock() => tick += 7;
    final cloud = InMemoryEntityDocStore();
    final coordA = EntitySyncCoordinator(
      local: StoreEntityDocStore(storeA, nowMs: clock),
      cloud: cloud,
    );
    await coordA.syncRound();
    expect(matchIn(await cloud.readAll(), 'm1'), isNotNull);

    // Delete: record gone locally, tombstone in the cloud.
    await storeA.deleteMatch('m1');
    final deletedAt =
        tombstoneFor(storeA.tombstones, EntityKind.matches, 'm1')!.deletedAt;
    await coordA.syncRound();
    var cloudSet = await cloud.readAll();
    expect(matchIn(cloudSet, 'm1'), isNull);
    expect(tombstoneFor(tombstonesOf(cloudSet), EntityKind.matches, 'm1'),
        isNotNull);

    // Restore from Trash: record back, local tombstone cleared —
    // and the restored marker remembers what it must out-rank.
    await storeA.restoreFromTrash(EntityKind.matches, 'm1');
    expect(storeA.matchById('m1'), isNotNull);
    expect(
        tombstoneFor(storeA.tombstones, EntityKind.matches, 'm1'), isNull);
    expect(storeA.restoredMarkerFor(EntityKind.matches, 'm1'), deletedAt);

    // The local adapter must now emit the record flagged restored
    // with a stamp above the (cloud-only) tombstone.
    final localSet =
        await StoreEntityDocStore(storeA, nowMs: clock).readAll();
    final rec = matchIn(localSet, 'm1')!;
    expect(rec.restored, isTrue);
    expect(rec.stamp, greaterThan(deletedAt));

    // The sync round: the restore lands in the cloud and the
    // cloud tombstone is spent; the marker is cleared afterwards.
    await coordA.syncRound();
    cloudSet = await cloud.readAll();
    expect(matchIn(cloudSet, 'm1'), isNotNull);
    expect(tombstoneFor(tombstonesOf(cloudSet), EntityKind.matches, 'm1'),
        isNull);
    expect(storeA.restoredMarkerFor(EntityKind.matches, 'm1'), isNull);

    // A second device pulling now receives the restored match.
    final storeB = Store();
    await storeB.activateIdentity('uid-restore');
    final coordB = EntitySyncCoordinator(
      local: StoreEntityDocStore(storeB, nowMs: clock),
      cloud: cloud,
    );
    await coordB.syncRound();
    expect(storeB.matchById('m1'), isNotNull);
    expect(storeB.matchById('m1')!.innings[0].totalRuns, 117);
  });

  test('restored marker persists across a Store reload', () async {
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.activateIdentity('uid-marker');
    await store.upsertMatch(matchM1());
    await store.deleteMatch('m1');
    final deletedAt =
        tombstoneFor(store.tombstones, EntityKind.matches, 'm1')!.deletedAt;
    await store.restoreFromTrash(EntityKind.matches, 'm1');
    expect(store.restoredMarkerFor(EntityKind.matches, 'm1'), deletedAt);

    // Fresh instance over the same prefs: marker still there while
    // the restored record exists.
    final reloaded = Store();
    await reloaded.activateIdentity('uid-marker');
    expect(reloaded.matchById('m1'), isNotNull);
    expect(reloaded.restoredMarkerFor(EntityKind.matches, 'm1'), deletedAt);

    // Deleting the record again supersedes the restore: a new
    // tombstone is recorded and the marker is gone.
    await reloaded.deleteMatch('m1');
    expect(reloaded.restoredMarkerFor(EntityKind.matches, 'm1'), isNull);
    expect(
        tombstoneFor(reloaded.tombstones, EntityKind.matches, 'm1'),
        isNotNull);
  });
}
