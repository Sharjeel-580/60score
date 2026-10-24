// Sync Fix "D", Phase D prep — tests for the GATED WRITE PATH:
// the policy (planGatedUpsert in lib/entity_sync.dart) that both
// the Firestore transactions (writeMatchGated / writeTeamGated in
// lib/entity_firestore.dart) and the in-memory gated store run.
//
// The transaction wrapper itself needs a live Firestore, so it is
// compile-checked only; everything it DECIDES is decided by
// planGatedUpsert, and that is what is pinned here — through the
// pure planner and end-to-end through GatedInMemoryEntityDocStore,
// the in-memory twin of the Firestore store's applyDiff.
//
// The rogue-writer shape matters most: a writer that bypasses the
// client merge entirely (a stale phone, a legacy code path) and
// pushes a diff straight at the store. The merge never gets a
// chance to protect the cloud — the gate has to.
import 'package:flutter_test/flutter_test.dart';

import 'package:cricket_scorer_app/entity_sync.dart';
import 'package:cricket_scorer_app/models.dart';

// ---------------- fixtures (mirroring sync_v2_test) --------------

List<String> xiIds(String p) => [for (var i = 1; i <= 11; i++) '$p$i'];

Team hawksTeam({int players = 11, String name = 'Shazi Hawks'}) => Team(
      id: 'hawks',
      name: name,
      players: [
        for (var i = 1; i <= players; i++)
          Player(id: 'h$i', name: 'Hawks Player $i')
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

StampedRecord mRec(Match m, int stamp, {bool restored = false}) =>
    StampedRecord(m.toJson(), stamp: stamp, restored: restored);

StampedRecord tRec(Team t, int stamp) => StampedRecord(t.toJson(),
    stamp: stamp,
    playerStamps: {for (final p in t.players) p.id: stamp});

int fowTotal(Match m) =>
    m.innings.fold(0, (a, i) => a + i.fallOfWickets.length);

EntityDiff upsertDiff(String kind, StampedRecord r) {
  final d = EntityDiff();
  (d.upserts[kind] ??= {})[r.id] = r;
  return d;
}

EntitySet setWith({
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

Match? matchIn(EntitySet s, String id) {
  final r = s[EntityKind.matches]?[id];
  return r == null ? null : Match.fromJson(r.json);
}

Team? teamIn(EntitySet s, String id) {
  final r = s[EntityKind.teams]?[id];
  return r == null ? null : Team.fromJson(r.json);
}

// ---------------- the planner ------------------------------------

void main() {
  group('planGatedUpsert — the shared Phase D write policy', () {
    test('an honest write to an empty slot is accepted as-is', () {
      final incoming = mRec(m1(fow1: 8, fow2: 2), 200);
      final plan = planGatedUpsert(
          kind: EntityKind.matches, incoming: incoming);
      expect(plan.verdict, GateVerdict.accept);
      expect(plan.toWrite, same(incoming));
      expect(plan.spendTombstone, isFalse);
    });

    test('a downgrade is refused: the stored winner already '
        'stands, so the plan converges instead of writing', () {
      final stored = mRec(m1(fow1: 8, fow2: 2), 200);
      final plan = planGatedUpsert(
        kind: EntityKind.matches,
        incoming: mRec(m1(fow1: 5, fow2: 0), 90),
        stored: stored,
      );
      expect(plan.verdict, GateVerdict.rejectDowngrade);
      expect(plan.toWrite, isNull);
      expect(plan.converged, isTrue);
    });

    test('a FORGED fresh stamp does not talk a downgrade past '
        'the gate', () {
      final stored = mRec(m1(fow1: 8, fow2: 2), 200);
      final plan = planGatedUpsert(
        kind: EntityKind.matches,
        incoming: mRec(m1(fow1: 5, fow2: 0), 999),
        stored: stored,
      );
      expect(plan.verdict, GateVerdict.rejectDowngrade);
      expect(plan.toWrite, isNull);
      expect(plan.converged, isTrue);
    });

    test('a richer copy carrying an older stamp is rescued by '
        'the re-merge: written, with its stamp floored', () {
      final stored = mRec(m1(fow1: 5, fow2: 0), 200);
      final plan = planGatedUpsert(
        kind: EntityKind.matches,
        incoming: mRec(m1(fow1: 8, fow2: 2), 150),
        stored: stored,
      );
      expect(plan.verdict, GateVerdict.rejectStaleStamp);
      expect(plan.toWrite, isNotNull);
      expect(fowTotal(Match.fromJson(plan.toWrite!.json)), 10);
      expect(plan.toWrite!.stamp, 200,
          reason: 'the converged record stops being stale');
    });

    test('a tombstoned write is refused outright — no merge '
        'can negotiate it back', () {
      final tomb =
          Tombstone(kind: EntityKind.matches, id: 'm1', deletedAt: 300);
      final plan = planGatedUpsert(
        kind: EntityKind.matches,
        incoming: mRec(m1(fow1: 8, fow2: 2), 999),
        tombstone: tomb,
      );
      expect(plan.verdict, GateVerdict.rejectTombstoned);
      expect(plan.toWrite, isNull);
      expect(plan.converged, isFalse);
    });

    test('the flagged restore is accepted and spends the '
        'tombstone', () {
      final tomb =
          Tombstone(kind: EntityKind.matches, id: 'm1', deletedAt: 300);
      final plan = planGatedUpsert(
        kind: EntityKind.matches,
        incoming: mRec(m1(fow1: 8, fow2: 2), 1000, restored: true),
        tombstone: tomb,
      );
      expect(plan.verdict, GateVerdict.accept);
      expect(plan.toWrite, isNotNull);
      expect(plan.spendTombstone, isTrue);
    });

    test('a team player-drop at the same stamp is refused; the '
        'union the re-merge computes IS the stored squad, so '
        'nothing is written', () {
      final stored = tRec(hawksTeam(), 200);
      final plan = planGatedUpsert(
        kind: EntityKind.teams,
        incoming: tRec(hawksTeam(players: 10), 200),
        stored: stored,
      );
      expect(plan.verdict, GateVerdict.rejectDowngrade);
      expect(plan.toWrite, isNull);
      expect(plan.converged, isTrue);
    });

    test('a drop attempt that also carries a genuinely new '
        'player is rescued by the re-merge: the union is '
        'written, nobody is dropped', () {
      final stored = tRec(hawksTeam(), 200);
      final withNew = hawksTeam(players: 10);
      withNew.players.add(Player(id: 'h99', name: 'New Recruit'));
      final plan = planGatedUpsert(
        kind: EntityKind.teams,
        incoming: tRec(withNew, 200),
        stored: stored,
      );
      expect(plan.verdict, GateVerdict.rejectDowngrade);
      expect(plan.toWrite, isNotNull);
      final ids =
          Team.fromJson(plan.toWrite!.json).players.map((p) => p.id);
      expect(ids, containsAll(['h11', 'h99']));
      expect(ids.length, 12);
    });
  });

  // ---------------- the store-level write path -------------------

  group('GatedInMemoryEntityDocStore — writes that bypass the '
      'client merge', () {
    test('honest writes land: a new match, then a richer update',
        () async {
      final cloud = GatedInMemoryEntityDocStore(setWith());
      await cloud.applyDiff(upsertDiff(
          EntityKind.matches, mRec(m1(fow1: 5, fow2: 0), 90)));
      expect(fowTotal(matchIn(await cloud.readAll(), 'm1')!), 5);
      await cloud.applyDiff(upsertDiff(
          EntityKind.matches, mRec(m1(fow1: 8, fow2: 2), 200)));
      expect(fowTotal(matchIn(await cloud.readAll(), 'm1')!), 10);
    });

    test('a rogue downgrade write cannot touch the stored '
        'record — honest stamp or forged stamp', () async {
      final cloud = GatedInMemoryEntityDocStore(setWith(
        matches: [mRec(m1(fow1: 8, fow2: 2), 200)],
      ));
      await cloud.applyDiff(upsertDiff(
          EntityKind.matches, mRec(m1(fow1: 5, fow2: 0), 90)));
      await cloud.applyDiff(upsertDiff(
          EntityKind.matches, mRec(m1(fow1: 5, fow2: 0), 999)));
      await cloud.applyDiff(upsertDiff(
          EntityKind.matches, mRec(m1LiveOld(), 999)));
      final after = await cloud.readAll();
      final m = matchIn(after, 'm1')!;
      expect(m.status, 'completed');
      expect(fowTotal(m), 10);
      expect(after[EntityKind.matches]!['m1']!.stamp, 200);
    });

    test('a stale upcoming copy cannot un-mark a no-result '
        '(S7 at the gate)', () async {
      final cloud = GatedInMemoryEntityDocStore(setWith(
        matches: [mRec(m2WithStatus('noResult', 'No result'), 200)],
      ));
      await cloud.applyDiff(upsertDiff(EntityKind.matches,
          mRec(m2WithStatus('upcoming', ''), 999)));
      final m = matchIn(await cloud.readAll(), 'm2')!;
      expect(m.status, 'noResult');
      expect(m.resultText, 'No result');
    });

    test('a tombstoned record write is rejected; the tombstone '
        'and the absence both survive', () async {
      final tomb =
          Tombstone(kind: EntityKind.matches, id: 'm1', deletedAt: 300);
      final cloud =
          GatedInMemoryEntityDocStore(setWith(tombs: [tomb]));
      await cloud.applyDiff(upsertDiff(
          EntityKind.matches, mRec(m1(fow1: 8, fow2: 2), 999)));
      final after = await cloud.readAll();
      expect(matchIn(after, 'm1'), isNull);
      expect(
          tombstoneFor(tombstonesOf(after), EntityKind.matches, 'm1'),
          isNotNull);
    });

    test('the flagged restore lands and spends the tombstone',
        () async {
      final tomb =
          Tombstone(kind: EntityKind.matches, id: 'm1', deletedAt: 300);
      final cloud =
          GatedInMemoryEntityDocStore(setWith(tombs: [tomb]));
      await cloud.applyDiff(upsertDiff(EntityKind.matches,
          mRec(m1(fow1: 8, fow2: 2), 1000, restored: true)));
      final after = await cloud.readAll();
      expect(matchIn(after, 'm1'), isNotNull);
      expect(
          tombstoneFor(tombstonesOf(after), EntityKind.matches, 'm1'),
          isNull);
    });

    test('team writes: a stale player-drop leaves the squad '
        'intact; an intentional newer drop lands', () async {
      final cloud = GatedInMemoryEntityDocStore(setWith(
        teams: [tRec(hawksTeam(), 200)],
      ));
      // Stale copy missing a player: rejected — squad intact,
      // and the stale rename in the same copy does not land.
      await cloud.applyDiff(upsertDiff(EntityKind.teams,
          tRec(hawksTeam(players: 10, name: 'Renamed'), 150)));
      var team = teamIn(await cloud.readAll(), 'hawks')!;
      expect(team.players.length, 11);
      expect(team.name, 'Shazi Hawks');
      // A strictly newer decision may reduce the squad.
      await cloud.applyDiff(upsertDiff(
          EntityKind.teams, tRec(hawksTeam(players: 10), 300)));
      team = teamIn(await cloud.readAll(), 'hawks')!;
      expect(team.players.length, 10);
    });

    test('through a full sync round, a stale device converges '
        'to the gated cloud copy instead of overwriting it',
        () async {
      final cloud = GatedInMemoryEntityDocStore(setWith(
        matches: [mRec(m1(fow1: 8, fow2: 2), 200)],
        teams: [tRec(hawksTeam(), 100)],
      ));
      final stale = InMemoryEntityDocStore(setWith(
        matches: [mRec(m1(fow1: 5, fow2: 0), 90)],
        teams: [tRec(hawksTeam(), 100)],
      ));
      await synchronizeEntityStores(stale, cloud);
      expect(fowTotal(matchIn(await cloud.readAll(), 'm1')!), 10);
      expect(fowTotal(matchIn(await stale.readAll(), 'm1')!), 10);
    });
  });
}
