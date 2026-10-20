// Zero-default-content rule: a fresh install must start COMPLETELY
// empty (no seeded tournament, teams or fixtures), saved user data must
// load back unchanged, and Reset App must leave the app empty.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cricket_scorer_app/models.dart';
import 'package:cricket_scorer_app/store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a fresh Store has zero tournaments, teams and matches', () {
    final s = Store();
    expect(s.tournaments, isEmpty);
    expect(s.teams, isEmpty);
    expect(s.matches, isEmpty);
    expect(s.regPlayers, isEmpty);
    expect(s.drafts, isEmpty);
    expect(s.manualStats, isEmpty);
  });

  test('load() on a fresh install (nothing saved) stays empty', () async {
    SharedPreferences.setMockInitialValues({});
    final s = Store();
    await s.load();
    expect(s.loaded, isTrue);
    expect(s.tournaments, isEmpty);
    expect(s.teams, isEmpty);
    expect(s.matches, isEmpty);
    expect(s.regPlayers, isEmpty);
    expect(s.drafts, isEmpty);
    expect(s.manualStats, isEmpty);
  });

  test('data a user saved loads back unchanged (nothing added)', () async {
    SharedPreferences.setMockInitialValues({});
    final s = Store();
    await s.load();
    await s.upsertTeam(Team(id: 'my_team', name: 'My Team'));
    await s.upsertTournament(
      Tournament(id: 'my_cup', name: 'My Cup', teamIds: const ['my_team']),
    );

    final s2 = Store();
    await s2.load();
    expect(s2.teams.length, 1);
    expect(s2.teams.single.name, 'My Team');
    expect(s2.tournaments.length, 1);
    expect(s2.tournaments.single.name, 'My Cup');
    expect(s2.matches, isEmpty);
  });

  test('resetApp() wipes everything and seeds nothing', () async {
    SharedPreferences.setMockInitialValues({});
    final s = Store();
    s.teams = [Team(id: 'x', name: 'X')];
    s.tournaments = [Tournament(id: 'y', name: 'Y')];
    s.matches = [
      Match(
        id: 'z',
        teamAId: 'x',
        teamBId: 'x',
        xiA: const [],
        xiB: const [],
        tossWinnerId: '',
      ),
    ];
    await s.resetApp();
    expect(s.teams, isEmpty);
    expect(s.tournaments, isEmpty);
    expect(s.matches, isEmpty);
    expect(s.regPlayers, isEmpty);
    expect(s.drafts, isEmpty);
    expect(s.manualStats, isEmpty);
  });
}
