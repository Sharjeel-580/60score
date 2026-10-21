// Tournament publishing (v1.3.0): the `published` flag on the model and
// the public snapshot slice that viewers decode.
import 'package:flutter_test/flutter_test.dart';
import 'package:cricket_scorer_app/models.dart';
import 'package:cricket_scorer_app/publish_service.dart';
import 'package:cricket_scorer_app/store.dart';

void main() {
  group('Tournament published flag', () {
    test('published survives a JSON round-trip', () {
      final t = Tournament(
        id: 't1',
        name: 'Super Sixty League Season 2K26',
        teamIds: const ['a', 'b'],
        venue: '75 LOKRI CLUB',
        published: true,
      );
      final back = Tournament.fromJson(t.toJson());
      expect(back.published, isTrue);
      expect(back.name, t.name);
      expect(back.teamIds, t.teamIds);
    });

    test('legacy JSON without a published field loads as unpublished', () {
      final back = Tournament.fromJson({
        'id': 't2',
        'name': 'Old League',
        'teamIds': <String>[],
        'venue': '',
        'logoBase64': '',
        'pointsAdjustments': <String, int>{},
        'qualifiedTeamIds': <String>[],
        'qualificationFinalized': false,
      });
      expect(back.published, isFalse);
    });

    test('a new tournament is unpublished by default', () {
      final t = Tournament(id: 't3', name: 'Friendly Cup');
      expect(t.published, isFalse);
      expect(t.toJson()['published'], isFalse);
    });
  });

  group('Published snapshot slice', () {
    Store buildStore() {
      final s = Store();
      s.teams = [
        Team(id: 'ta', name: 'Alpha', players: [
          Player(id: 'p1', name: 'Player One'),
          Player(id: 'p2', name: 'Player Two'),
        ]),
        Team(id: 'tb', name: 'Beta', players: [
          Player(id: 'p3', name: 'Player Three'),
        ]),
        Team(id: 'tz', name: 'Outsiders', players: [
          Player(id: 'p9', name: 'Player Nine'),
        ]),
      ];
      s.tournaments = [
        Tournament(
          id: 'cup',
          name: 'City Cup',
          teamIds: const ['ta', 'tb'],
          venue: 'City Ground',
          published: true,
        ),
        Tournament(id: 'other', name: 'Other Cup', teamIds: const ['tz']),
      ];
      Match mk(String id, String? tid) => Match(
            id: id,
            tournamentId: tid,
            teamAId: 'ta',
            teamBId: 'tb',
            xiA: const [],
            xiB: const [],
            tossWinnerId: 'ta',
            status: 'completed',
            resultText: 'Alpha won',
          );
      s.matches = [mk('m1', 'cup'), mk('m2', 'other'), mk('m3', null)];
      s.regPlayers = [
        RegPlayer(id: 'p1', name: 'Player One'),
        RegPlayer(id: 'p3', name: 'Player Three'),
        RegPlayer(id: 'outsider', name: 'Not In Any Squad'),
      ];
      return s;
    }

    test('buildSlice carries ONLY the tournament slice', () {
      final s = buildStore();
      final slice =
          PublishService.buildSlice(s, s.tournamentById('cup')!);
      expect(slice.tournament.id, 'cup');
      expect(slice.teams.map((t) => t.id), ['ta', 'tb']);
      expect(slice.matches.map((m) => m.id), ['m1']);
      // Registered players of the slice's squads only: p1 + p3, never
      // the unrelated registration or the other tournament's player.
      expect(slice.regPlayers.map((r) => r.id), ['p1', 'p3']);
    });

    test('snapshot encode/decode round-trips into model objects', () {
      final s = buildStore();
      final slice =
          PublishService.buildSlice(s, s.tournamentById('cup')!);
      final encoded = PublishService.encodeSlice(slice);
      final back = PublishService.decodeSlice(encoded);
      expect(back, isNotNull);
      expect(back!.tournament.name, 'City Cup');
      expect(back.tournament.published, isTrue);
      expect(back.teams.map((t) => t.name), ['Alpha', 'Beta']);
      expect(back.teams.first.players.map((p) => p.id), ['p1', 'p2']);
      expect(back.matches.single.id, 'm1');
      expect(back.matches.single.resultText, 'Alpha won');
      expect(back.regPlayers.map((r) => r.id), ['p1', 'p3']);
    });

    test('fromDoc builds a viewer bundle and skips corrupt payloads', () {
      final s = buildStore();
      final slice =
          PublishService.buildSlice(s, s.tournamentById('cup')!);
      final pub = PublishService.fromDoc('cup', {
        'ownerUid': 'owner-1',
        'name': 'City Cup',
        'venue': 'City Ground',
        'logoBase64': '',
        'updatedAt': 1700000000000,
        'data': PublishService.encodeSlice(slice),
      });
      expect(pub, isNotNull);
      expect(pub!.ownerUid, 'owner-1');
      expect(pub.teamName('tb'), 'Beta');
      expect(pub.matches.single.tournamentId, 'cup');

      expect(PublishService.fromDoc('x', {'data': 'not json'}), isNull);
      expect(PublishService.fromDoc('x', {'data': ''}), isNull);
      expect(PublishService.fromDoc('x', const {}), isNull);
      expect(PublishService.decodeSlice(''), isNull);
      expect(PublishService.decodeSlice('{"teams": []}'), isNull);
    });
  });

  group('Published slice photo stripping (v1.3.2)', () {
    test('encodeSlice strips player photos like the backup push', () {
      final s = Store();
      s.teams = [
        Team(id: 'ta', name: 'Alpha', players: [
          Player(id: 'p1', name: 'Player One', photoBase64: 'TEAM_PHOTO'),
        ]),
      ];
      s.tournaments = [
        Tournament(
          id: 'cup',
          name: 'City Cup',
          teamIds: const ['ta'],
          published: true,
        ),
      ];
      s.regPlayers = [
        RegPlayer(id: 'p1', name: 'Player One', photoBase64: 'REG_PHOTO'),
      ];
      final slice = PublishService.buildSlice(s, s.tournaments.single);
      final encoded = PublishService.encodeSlice(slice);
      // No photo payloads anywhere in the public document — photos
      // travel via the owner's private photos subcollection, so a
      // photo-heavy tournament cannot blow the 1 MiB document limit.
      expect(encoded.contains('TEAM_PHOTO'), isFalse);
      expect(encoded.contains('REG_PHOTO'), isFalse);
      // …but the players themselves survive the round-trip intact.
      final back = PublishService.decodeSlice(encoded);
      expect(back, isNotNull);
      expect(back!.teams.single.players.single.name, 'Player One');
      expect(back.teams.single.players.single.photoBase64, '');
      expect(back.regPlayers.single.photoBase64, '');
    });

    test('hasPublished reflects the local flags', () {
      final s = Store();
      expect(PublishService.hasPublished(s), isFalse);
      s.tournaments = [Tournament(id: 'a', name: 'Draft Cup')];
      expect(PublishService.hasPublished(s), isFalse);
      s.tournaments = [
        Tournament(id: 'b', name: 'Live Cup', published: true),
      ];
      expect(PublishService.hasPublished(s), isTrue);
    });
  });
}
