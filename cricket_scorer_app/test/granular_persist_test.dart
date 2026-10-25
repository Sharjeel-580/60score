// Granular persists (v1.4.5, M1): teams/drafts/reg-players edits
// must save through their own key ONLY — mirroring the
// tournaments-only proof. Each test seeds a heavy teams key (inline
// photo) plus the other collections, saves the edited collection
// granularly, and asserts every other prefs key is byte-identical
// while the edited key changed and reload restores the edit.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cricket_scorer_app/models.dart';
import 'package:cricket_scorer_app/store.dart';

const _teamsKey = 'cricscore_teams_v1__guest';
const _tournKey = 'cricscore_tournaments_v1__guest';
const _matchesKey = 'cricscore_matches_v1__guest';
const _regKey = 'score60_regplayers_v1__guest';
const _draftsKey = 'score60_drafts_v1__guest';

Future<Store> _seeded() async {
  SharedPreferences.setMockInitialValues({});
  final store = Store();
  await store.activateIdentity('guest');
  store.teams = [
    Team(id: 't1', name: 'Team A', players: [
      Player(id: 'p1', name: 'P1', photoBase64: 'x' * 200000),
    ]),
  ];
  store.tournaments = [
    Tournament(id: 'tour1', name: 'League', teamIds: ['t1']),
  ];
  store.matches = [
    Match(
      id: 'm1',
      teamAId: 't1',
      teamBId: 't1',
      xiA: ['p1'],
      xiB: ['p1'],
      oversLimit: 8,
      tossWinnerId: 't1',
      tossDecision: 'bat',
    ),
  ];
  store.regPlayers = [RegPlayer(id: 'r1', name: 'Reg One')];
  store.drafts = [Draft(id: 'd1', name: 'Draft One', teamIds: ['t1'])];
  await store.persist();
  return store;
}

Future<Map<String, String?>> _bytes() async {
  final prefs = await SharedPreferences.getInstance();
  return {
    'teams': prefs.getString(_teamsKey),
    'tourn': prefs.getString(_tournKey),
    'matches': prefs.getString(_matchesKey),
    'reg': prefs.getString(_regKey),
    'drafts': prefs.getString(_draftsKey),
  };
}

Future<Store> _reloaded() async {
  final store = Store();
  await store.activateIdentity('guest');
  return store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('team edit saves teams-only, other keys byte-identical',
      () async {
    final store = await _seeded();
    final before = await _bytes();
    store.teams.single.name = 'Team A Renamed';
    expect(await store.persistTeamsOnly(), isTrue);
    final after = await _bytes();
    expect(after['tourn'], before['tourn']);
    expect(after['matches'], before['matches']);
    expect(after['reg'], before['reg']);
    expect(after['drafts'], before['drafts']);
    expect(after['teams'], isNot(before['teams']));
    expect((await _reloaded()).teams.single.name, 'Team A Renamed');
  });

  test('draft edit saves drafts-only, other keys byte-identical',
      () async {
    final store = await _seeded();
    final before = await _bytes();
    store.drafts.single.name = 'Draft One Renamed';
    expect(await store.persistDraftsOnly(), isTrue);
    final after = await _bytes();
    expect(after['teams'], before['teams']);
    expect(after['tourn'], before['tourn']);
    expect(after['matches'], before['matches']);
    expect(after['reg'], before['reg']);
    expect(after['drafts'], isNot(before['drafts']));
    expect((await _reloaded()).drafts.single.name, 'Draft One Renamed');
  });

  test('reg-player edit saves reg-only, other keys byte-identical',
      () async {
    final store = await _seeded();
    final before = await _bytes();
    store.regPlayers.single.name = 'Reg One Renamed';
    expect(await store.persistRegPlayersOnly(), isTrue);
    final after = await _bytes();
    expect(after['teams'], before['teams']);
    expect(after['tourn'], before['tourn']);
    expect(after['matches'], before['matches']);
    expect(after['drafts'], before['drafts']);
    expect(after['reg'], isNot(before['reg']));
    expect((await _reloaded()).regPlayers.single.name, 'Reg One Renamed');
  });
}
