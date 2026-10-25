// Completed view filter (v1.4.5): no-result matches appear alongside
// completed ones; live and scheduled matches stay excluded. Statuses
// themselves are untouched — this only tests what the view lists.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cricket_scorer_app/models.dart';
import 'package:cricket_scorer_app/screens/completed_matches_screen.dart';
import 'package:cricket_scorer_app/store.dart';
import 'package:cricket_scorer_app/theme.dart';

Team _team(String id, String name) => Team(id: id, name: name);

Match _match(
  String id,
  String a,
  String b,
  String status,
  String resultText,
) =>
    Match(
      id: id,
      teamAId: a,
      teamBId: b,
      xiA: const [],
      xiB: const [],
      oversLimit: 8,
      tossWinnerId: a,
      status: status,
      resultText: resultText,
      dateIso: '2026-10-25',
    );

void main() {
  testWidgets(
    'noResult appears under Completed; live and scheduled do not',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = Store();
      await store.activateIdentity('guest');
      await store.upsertTeam(_team('a', 'Alpha XI'));
      await store.upsertTeam(_team('b', 'Beta XI'));
      await store.upsertTeam(_team('c', 'Gamma XI'));
      await store.upsertTeam(_team('d', 'Delta XI'));
      await store.upsertTeam(_team('e', 'Epsilon XI'));
      await store.upsertTeam(_team('f', 'Zeta XI'));
      await store.upsertTeam(_team('g', 'Eta XI'));
      await store.upsertTeam(_team('h', 'Theta XI'));

      await store.upsertMatch(
        _match('m1', 'a', 'b', 'completed', 'Alpha XI won by 5 wickets'),
      );
      // The reported case: Match 02, AB vs Ali, noResult.
      await store.upsertMatch(_match('m2', 'c', 'd', 'noResult', 'No result'));
      await store.upsertMatch(_match('m3', 'e', 'f', 'live', ''));
      await store.upsertMatch(_match('m4', 'g', 'h', 'scheduled', ''));

      await tester.pumpWidget(
        MaterialApp(
          theme: buildScore60Theme(),
          home: CompletedMatchesScreen(store: store),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Alpha XI vs Beta XI'), findsOneWidget);
      expect(find.text('Gamma XI vs Delta XI'), findsOneWidget);
      expect(find.text('No result'), findsOneWidget);
      expect(find.text('COMPLETED'), findsOneWidget);
      expect(find.text('Epsilon XI vs Zeta XI'), findsNothing);
      expect(find.text('Eta XI vs Theta XI'), findsNothing);
    },
  );
}
