// Tournament logo (v1.2.2): optional logoBase64 on the Tournament model.
import 'package:flutter_test/flutter_test.dart';
import 'package:cricket_scorer_app/models.dart';

void main() {
  group('Tournament logoBase64', () {
    test('logo survives a JSON round-trip', () {
      final t = Tournament(
        id: 't1',
        name: 'Super Sixty League Season 2K26',
        teamIds: const ['a', 'b'],
        venue: '75 LOKRI CLUB',
        logoBase64: 'aGVsbG8td29ybGQ=',
      );
      final back = Tournament.fromJson(t.toJson());
      expect(back.logoBase64, 'aGVsbG8td29ybGQ=');
      expect(back.name, t.name);
      expect(back.teamIds, t.teamIds);
      expect(back.venue, t.venue);
    });

    test('legacy JSON without a logo field loads with an empty logo', () {
      final back = Tournament.fromJson({
        'id': 't2',
        'name': 'Old League',
        'teamIds': <String>[],
        'venue': '',
        'pointsAdjustments': <String, int>{},
        'qualifiedTeamIds': <String>[],
        'qualificationFinalized': false,
      });
      expect(back.logoBase64, '');
    });

    test('default tournament has no logo', () {
      final t = Tournament(id: 't3', name: 'Friendly Cup');
      expect(t.logoBase64, '');
      expect(t.toJson()['logoBase64'], '');
    });
  });
}
