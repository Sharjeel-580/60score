// Feature 1 — Trash + Restore (soft delete): deleting a match,
// team or tournament snapshots the full record into Trash BEFORE
// removal (tombstone behaviour unchanged); restoring re-inserts it
// through the upsert path (tombstone cleared — admin restore);
// permanent delete drops only the snapshot (tombstone MUST stay).
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cricket_scorer_app/entity_sync.dart';
import 'package:cricket_scorer_app/models.dart';
import 'package:cricket_scorer_app/store.dart';

List<String> xiIds(String p) => [for (var i = 1; i <= 11; i++) '$p$i'];

Team hawks() => Team(
      id: 'hawks',
      name: 'Shazi Hawks',
      players: [
        for (var i = 1; i <= 11; i++) Player(id: 'h$i', name: 'Hawks $i')
      ],
    );

Team dolphins() => Team(
      id: 'dolphins',
      name: 'Adi Dolphins',
      players: [
        for (var i = 1; i <= 11; i++)
          Player(id: 'd$i', name: 'Dolphins $i')
      ],
    );

Match richMatch() {
  final inn1 = InningsState(
    battingTeamId: 'hawks',
    bowlingTeamId: 'dolphins',
    battingXI: xiIds('h'),
    bowlingXI: xiIds('d'),
    oversLimit: 8,
  );
  inn1.totalRuns = 117;
  inn1.wickets = 8;
  inn1.legalBalls = 48;
  inn1.fallOfWickets.add(FallOfWicket(1, 20, '2.3', 'h1'));
  inn1.fallOfWickets.add(FallOfWicket(2, 45, '5.1', 'h2'));
  final inn2 = InningsState(
    battingTeamId: 'dolphins',
    bowlingTeamId: 'hawks',
    battingXI: xiIds('d'),
    bowlingXI: xiIds('h'),
    oversLimit: 8,
  );
  inn2.totalRuns = 118;
  inn2.wickets = 2;
  inn2.legalBalls = 40;
  inn2.fallOfWickets.add(FallOfWicket(1, 60, '4.0', 'd1'));
  return Match(
    id: 'm1',
    teamAId: 'hawks',
    teamBId: 'dolphins',
    xiA: xiIds('h'),
    xiB: xiIds('d'),
    tossWinnerId: 'hawks',
    status: 'completed',
    resultText: 'Adi Dolphins won by 8 wickets',
    innings: [inn1, inn2],
  );
}

bool hasTombstone(Store s, String kind, String id) =>
    s.tombstones.any((t) => t.kind == kind && t.id == id);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Trash — matches', () {
    test('(a) delete a match: gone, in trash with full payload, '
        'tombstone present', () async {
      SharedPreferences.setMockInitialValues({});
      final s = Store();
      await s.activateIdentity('guest');
      await s.upsertTeam(hawks());
      await s.upsertTeam(dolphins());
      await s.upsertMatch(richMatch());
      expect(s.matches, hasLength(1));
      expect(s.trashEntries, isEmpty);

      await s.deleteMatch('m1');

      expect(s.matches, isEmpty);
      expect(hasTombstone(s, EntityKind.matches, 'm1'), isTrue);
      expect(s.trashEntries, hasLength(1));
      final entry = s.trashEntries.single;
      expect(entry.kind, EntityKind.matches);
      expect(entry.id, 'm1');
      expect(entry.name, 'Shazi Hawks vs Adi Dolphins');
      expect(entry.deletedAt, greaterThan(0));
      // Full payload: innings data intact.
      final innings = entry.payload['innings'] as List;
      expect(innings, hasLength(2));
      final inn1 = innings[0] as Map<String, dynamic>;
      expect(inn1['totalRuns'], 117);
      expect(inn1['wickets'], 8);
      expect(inn1['legalBalls'], 48);
      expect((inn1['fallOfWickets'] as List), hasLength(2));
      final inn2 = innings[1] as Map<String, dynamic>;
      expect(inn2['totalRuns'], 118);
      expect(entry.payload['resultText'],
          'Adi Dolphins won by 8 wickets');
    });

    test('(b) restore: match back with identical data, tombstone '
        'cleared, trash entry gone', () async {
      SharedPreferences.setMockInitialValues({});
      final s = Store();
      await s.activateIdentity('guest');
      await s.upsertTeam(hawks());
      await s.upsertTeam(dolphins());
      final original = richMatch();
      await s.upsertMatch(original);
      await s.deleteMatch('m1');
      expect(s.trashEntries, hasLength(1));

      await s.restoreFromTrash(EntityKind.matches, 'm1');

      expect(s.trashEntries, isEmpty);
      expect(hasTombstone(s, EntityKind.matches, 'm1'), isFalse);
      expect(s.tombstonedMatchIds, isNot(contains('m1')));
      expect(s.matches, hasLength(1));
      final restored = s.matches.single;
      expect(restored.id, 'm1');
      expect(restored.status, 'completed');
      expect(restored.resultText, 'Adi Dolphins won by 8 wickets');
      expect(restored.innings, hasLength(2));
      expect(restored.innings[0].totalRuns, 117);
      expect(restored.innings[0].wickets, 8);
      expect(restored.innings[0].legalBalls, 48);
      expect(restored.innings[0].fallOfWickets, hasLength(2));
      expect(restored.innings[1].totalRuns, 118);
      expect(restored.innings[1].wickets, 2);
    });

    test('(c) permanent delete: trash entry gone, match still '
        'absent, tombstone STILL present', () async {
      SharedPreferences.setMockInitialValues({});
      final s = Store();
      await s.activateIdentity('guest');
      await s.upsertMatch(richMatch());
      await s.deleteMatch('m1');
      expect(s.trashEntries, hasLength(1));

      await s.permanentlyDeleteFromTrash(EntityKind.matches, 'm1');

      expect(s.trashEntries, isEmpty);
      expect(s.matches, isEmpty);
      expect(hasTombstone(s, EntityKind.matches, 'm1'), isTrue);
      expect(s.tombstonedMatchIds, contains('m1'));
    });
  });

  group('Trash — teams and tournaments', () {
    test('(d) team: delete goes to trash, restore brings it back '
        'with players and clears tombstone', () async {
      SharedPreferences.setMockInitialValues({});
      final s = Store();
      await s.activateIdentity('guest');
      await s.upsertTeam(hawks());

      await s.deleteTeam('hawks');
      expect(s.teams, isEmpty);
      expect(hasTombstone(s, EntityKind.teams, 'hawks'), isTrue);
      expect(s.trashEntries, hasLength(1));
      final entry = s.trashEntries.single;
      expect(entry.kind, EntityKind.teams);
      expect(entry.name, 'Shazi Hawks');
      expect((entry.payload['players'] as List), hasLength(11));

      await s.restoreFromTrash(EntityKind.teams, 'hawks');
      expect(s.trashEntries, isEmpty);
      expect(hasTombstone(s, EntityKind.teams, 'hawks'), isFalse);
      expect(s.teams, hasLength(1));
      expect(s.teams.single.name, 'Shazi Hawks');
      expect(s.teams.single.players, hasLength(11));
    });

    test('(d) tournament: delete goes to trash, permanent delete '
        'keeps tombstone; restore works on a second tournament',
        () async {
      SharedPreferences.setMockInitialValues({});
      final s = Store();
      await s.activateIdentity('guest');
      await s.upsertTournament(Tournament(
        id: 't1',
        name: 'Super Sixty League',
        teamIds: ['hawks', 'dolphins'],
      ));
      await s.upsertTournament(Tournament(id: 't2', name: 'Winter Cup'));

      await s.deleteTournament('t1');
      expect(s.tournaments.map((t) => t.id), ['t2']);
      expect(hasTombstone(s, EntityKind.tournaments, 't1'), isTrue);
      var entry =
          s.trashEntries.firstWhere((e) => e.id == 't1');
      expect(entry.kind, EntityKind.tournaments);
      expect(entry.name, 'Super Sixty League');
      expect(entry.payload['teamIds'], ['hawks', 'dolphins']);

      // Restore path for tournaments.
      await s.restoreFromTrash(EntityKind.tournaments, 't1');
      expect(s.tournaments.map((t) => t.id), contains('t1'));
      expect(hasTombstone(s, EntityKind.tournaments, 't1'), isFalse);
      expect(s.trashEntries.where((e) => e.id == 't1'), isEmpty);

      // Permanent-delete path for tournaments.
      await s.deleteTournament('t2');
      expect(s.trashEntries.where((e) => e.id == 't2'), hasLength(1));
      await s.permanentlyDeleteFromTrash(EntityKind.tournaments, 't2');
      expect(s.trashEntries.where((e) => e.id == 't2'), isEmpty);
      expect(s.tournaments.map((t) => t.id), isNot(contains('t2')));
      expect(hasTombstone(s, EntityKind.tournaments, 't2'), isTrue);
    });

    test('deleting a team still removes it from tournaments '
        '(existing behaviour unchanged)', () async {
      SharedPreferences.setMockInitialValues({});
      final s = Store();
      await s.activateIdentity('guest');
      await s.upsertTeam(hawks());
      await s.upsertTournament(Tournament(
        id: 't1',
        name: 'League',
        teamIds: ['hawks', 'dolphins'],
      ));
      await s.deleteTeam('hawks');
      expect(s.tournaments.single.teamIds, ['dolphins']);
      expect(s.trashEntries.single.kind, EntityKind.teams);
    });
  });

  group('Trash — persistence and ordering', () {
    test('(e) trash persists across a Store reload', () async {
      SharedPreferences.setMockInitialValues({});
      final s = Store();
      await s.activateIdentity('guest');
      await s.upsertTeam(hawks());
      await s.upsertTeam(dolphins());
      await s.upsertMatch(richMatch());
      await s.deleteMatch('m1');
      expect(s.trashEntries, hasLength(1));

      // A fresh Store over the same prefs sees the trash entry,
      // the absence of the match, and the tombstone.
      final s2 = Store();
      await s2.activateIdentity('guest');
      expect(s2.matches, isEmpty);
      expect(hasTombstone(s2, EntityKind.matches, 'm1'), isTrue);
      expect(s2.trashEntries, hasLength(1));
      final entry = s2.trashEntries.single;
      expect(entry.kind, EntityKind.matches);
      expect(entry.id, 'm1');
      expect(entry.name, 'Shazi Hawks vs Adi Dolphins');
      expect((entry.payload['innings'] as List), hasLength(2));

      // And the reloaded entry is restorable.
      await s2.restoreFromTrash(EntityKind.matches, 'm1');
      expect(s2.matches, hasLength(1));
      expect(s2.trashEntries, isEmpty);
    });

    test('trash is per-identity, like all other data', () async {
      SharedPreferences.setMockInitialValues({});
      final s = Store();
      await s.activateIdentity('guest');
      await s.upsertMatch(richMatch());
      await s.deleteMatch('m1');
      expect(s.trashEntries, hasLength(1));
      await s.activateIdentity('uid-other');
      expect(s.trashEntries, isEmpty);
      await s.activateIdentity('guest');
      expect(s.trashEntries, hasLength(1));
    });

    test('trashEntries are newest first; re-deleting replaces the '
        'older snapshot', () async {
      SharedPreferences.setMockInitialValues({});
      final s = Store();
      await s.activateIdentity('guest');
      await s.upsertMatch(richMatch());
      await s.upsertTournament(Tournament(id: 't1', name: 'League'));
      await s.deleteMatch('m1');
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await s.deleteTournament('t1');
      expect(s.trashEntries.map((e) => e.id), ['t1', 'm1']);

      // Restore then delete again: still exactly one entry for m1,
      // holding the latest snapshot.
      await s.restoreFromTrash(EntityKind.matches, 'm1');
      s.matches.single.resultText = 'Revised result';
      await s.deleteMatch('m1');
      final m1Entries =
          s.trashEntries.where((e) => e.id == 'm1').toList();
      expect(m1Entries, hasLength(1));
      expect(m1Entries.single.payload['resultText'], 'Revised result');
    });

    test('a record that exists locally drops its trash entry '
        '(self-heal on re-add and on load)', () async {
      SharedPreferences.setMockInitialValues({});
      final s = Store();
      await s.activateIdentity('guest');
      await s.upsertMatch(richMatch());
      await s.deleteMatch('m1');
      expect(s.trashEntries, hasLength(1));
      // Re-adding the same id (admin restore by another path)
      // drops the trash entry immediately…
      await s.upsertMatch(richMatch());
      expect(s.matches, hasLength(1));
      expect(s.trashEntries.where((e) => e.id == 'm1'), isEmpty);
      // …and a reload keeps it gone.
      final s2 = Store();
      await s2.activateIdentity('guest');
      expect(s2.matches, hasLength(1));
      expect(s2.trashEntries.where((e) => e.id == 'm1'), isEmpty);
    });
  });
}
