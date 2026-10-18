// v1.1.6: shared player-photo lookup — one player record, one photo
// everywhere (Registered Players, Team Management, squads, POTM, Summary,
// fixture cards). Pure in-memory logic; no SharedPreferences I/O.
import 'package:flutter_test/flutter_test.dart';
import 'package:cricket_scorer_app/models.dart';
import 'package:cricket_scorer_app/store.dart';

Store _store() => Store();

void main() {
  group('photoForPlayer (shared photo lookup)', () {
    test('prefers the Registered Players photo over the team copy', () {
      final s = _store();
      s.regPlayers = [
        RegPlayer(id: 'p1', name: 'Ali', photoBase64: 'regphoto'),
      ];
      s.teams = [
        Team(
          id: 't1',
          name: 'Team A',
          players: [Player(id: 'p1', name: 'Ali', photoBase64: 'teamphoto')],
        ),
      ];
      expect(s.photoForPlayer('p1'), 'regphoto');
    });

    test('falls back to the team-squad copy when no registered photo', () {
      final s = _store();
      s.regPlayers = [RegPlayer(id: 'p2', name: 'Bilal')];
      s.teams = [
        Team(
          id: 't1',
          name: 'Team A',
          players: [Player(id: 'p2', name: 'Bilal', photoBase64: 'teamphoto')],
        ),
      ];
      expect(s.photoForPlayer('p2'), 'teamphoto');
    });

    test('returns empty string when no photo exists anywhere', () {
      final s = _store();
      s.regPlayers = [RegPlayer(id: 'p3', name: 'Usman')];
      s.teams = [
        Team(
          id: 't1',
          name: 'Team A',
          players: [Player(id: 'p3', name: 'Usman')],
        ),
      ];
      expect(s.photoForPlayer('p3'), '');
    });

    test('returns empty string for an unknown player id', () {
      final s = _store();
      expect(s.photoForPlayer('nope'), '');
    });
  });
}
