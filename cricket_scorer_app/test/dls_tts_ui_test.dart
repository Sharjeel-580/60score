// Features 2 + 7 (D batch) — UI smoke tests for the scoring
// screen wiring: the DLS revised-target dialog calculates from
// the Standard Edition module and the voice-commentary toggle
// reflects + persists the TTS setting (default OFF).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cricket_scorer_app/models.dart';
import 'package:cricket_scorer_app/screens/scoring_screen.dart';
import 'package:cricket_scorer_app/store.dart';
import 'package:cricket_scorer_app/tts_service.dart';

List<String> xi(String p) => [for (var i = 1; i <= 11; i++) '$p$i'];

Team team(String id, String name, String p) => Team(
      id: id,
      name: name,
      players: [
        for (var i = 1; i <= 11; i++) Player(id: '$p$i', name: '$name $i')
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Store> liveStore(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.activateIdentity('guest');
    await store.upsertTeam(team('hawks', 'Hawks', 'h'));
    await store.upsertTeam(team('dolphins', 'Dolphins', 'd'));
    final match = Match(
      id: 'm1',
      teamAId: 'hawks',
      teamBId: 'dolphins',
      xiA: xi('h'),
      xiB: xi('d'),
      oversLimit: 8,
      tossWinnerId: 'hawks',
      status: 'live',
    );
    await store.upsertMatch(match);
    return store;
  }

  testWidgets('DLS dialog: equal resources → target is score + 1',
      (tester) async {
    final store = await liveStore(tester);
    final match = store.matchById('m1')!;
    await tester.pumpWidget(MaterialApp(
      home: ScoringScreen(store: store, match: match),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Revised target (DLS)'));
    await tester.pumpAndSettle();
    expect(find.text('Revised target (DLS)'), findsWidgets);

    // Team 1 score field is the first text field in the dialog.
    await tester.enterText(find.byType(TextField).first, '100');
    await tester.tap(find.text('Calculate'));
    await tester.pumpAndSettle();
    // 8 overs vs 8 overs → R1 == R2 → target = 100 + 1.
    expect(find.textContaining('Revised target: 101'), findsOneWidget);
    expect(find.textContaining('Par score: 100.0'), findsOneWidget);
  });

  testWidgets('TTS toggle: default OFF, tap turns it ON and persists',
      (tester) async {
    final store = await liveStore(tester);
    final match = store.matchById('m1')!;
    await tester.pumpWidget(MaterialApp(
      home: ScoringScreen(store: store, match: match),
    ));
    await tester.pumpAndSettle();

    expect(TtsService.instance.enabled, isFalse);
    expect(find.byIcon(Icons.volume_off), findsOneWidget);
    await tester.tap(find.byIcon(Icons.volume_off));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.volume_up), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(kTtsEnabledPrefsKey), isTrue);
    // Leave the shared singleton OFF for other tests.
    await TtsService.instance.setEnabled(false);
  });
}
