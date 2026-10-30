// "Import backup file" (v1.4.8) — the Backup & Restore screen's list
// only shows the app-private auto_backups dir, so a backup transferred
// from another phone (Downloads) could never be restored until the
// import button existed. The restore itself is the existing
// restoreBackup (merge: same-id replaced, new added, nothing deleted,
// atomic on failure) — these tests pin that flow end to end through a
// real exported backup file, plus the screen showing the button.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cricket_scorer_app/backup_service.dart';
import 'package:cricket_scorer_app/models.dart';
import 'package:cricket_scorer_app/screens/backup_screen.dart';
import 'package:cricket_scorer_app/store.dart';

Store _sourceStore() {
  final s = Store();
  s.teams = [
    Team(id: 't1', name: 'Team One', players: [
      Player(id: 'a1', name: 'A One', role: 'Batter'),
    ]),
    Team(id: 't2', name: 'Team Two', players: []),
  ];
  s.tournaments = [
    Tournament(id: 'tour1', name: 'League', teamIds: ['t1', 't2']),
  ];
  s.matches = [
    Match(
      id: 'm1',
      tournamentId: 'tour1',
      teamAId: 't1',
      teamBId: 't2',
      xiA: const ['a1'],
      xiB: const [],
      oversLimit: 8,
      tossWinnerId: 't1',
      status: 'completed',
    ),
  ];
  return s;
}

Future<File> _writeBackup(Map<String, dynamic> json) async {
  final dir = await Directory.systemTemp.createTemp('backup_import_');
  final file = File('${dir.path}/60score_backup_test.json');
  await file.writeAsString(jsonEncode(json));
  return file;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('restoreBackup merges an exported backup: replace, add, delete nothing',
      () async {
    SharedPreferences.setMockInitialValues({});
    final file = await _writeBackup(_sourceStore().exportJson());

    final target = Store();
    target.teams = [
      Team(id: 't1', name: 'Team One OLD', players: []),
      Team(id: 't3', name: 'Team Three', players: []),
    ];
    target.tournaments = [
      Tournament(id: 'tourX', name: 'Other', teamIds: ['t3']),
    ];
    target.matches = [
      Match(
        id: 'm1',
        tournamentId: 'tour1',
        teamAId: 't1',
        teamBId: 't2',
        xiA: const ['a1'],
        xiB: const [],
        oversLimit: 6,
        tossWinnerId: 't2',
        status: 'live',
      ),
    ];

    final result = await restoreBackup(target, file.path);
    expect(result.error, isNull);
    expect(result.counts['teams'], 2); // t1 replaced + t2 added
    expect(result.counts['tournaments'], 1); // tour1 added
    expect(result.counts['matches'], 1); // m1 replaced

    // Same-id record replaced by the backup's version.
    final t1 = target.teams.firstWhere((t) => t.id == 't1');
    expect(t1.name, 'Team One');
    expect(t1.players.map((p) => p.id), ['a1']);
    // New records added.
    expect(target.teams.any((t) => t.id == 't2'), isTrue);
    expect(target.tournaments.any((t) => t.id == 'tour1'), isTrue);
    // Nothing deleted: pre-existing records the backup lacks survive.
    expect(target.teams.any((t) => t.id == 't3'), isTrue);
    expect(target.tournaments.any((t) => t.id == 'tourX'), isTrue);
    // Same-id match replaced (overs + toss + status from the backup).
    final m1 = target.matches.firstWhere((m) => m.id == 'm1');
    expect(m1.oversLimit, 8);
    expect(m1.tossWinnerId, 't1');
    expect(m1.status, 'completed');
  });

  test('restoreBackup rejects a non-60Score file and changes nothing',
      () async {
    SharedPreferences.setMockInitialValues({});
    final file = await _writeBackup({
      'app': 'SomethingElse',
      'teams': [],
      'tournaments': [],
      'matches': [],
    });

    final target = Store();
    target.teams = [
      Team(id: 't9', name: 'Kept', players: []),
    ];

    final result = await restoreBackup(target, file.path);
    expect(result.error, 'Not a 60Score backup file.');
    expect(result.counts, isEmpty);
    expect(target.teams.map((t) => t.id), ['t9']);
    expect(target.tournaments, isEmpty);
    expect(target.matches, isEmpty);
  });

  testWidgets('Backup & Restore screen shows the Import backup file button',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(MaterialApp(
      home: BackupScreen(store: Store()),
    ));
    // No pumpAndSettle: the automatic-backup list future (path_provider)
    // never resolves in the test env, so the loading indicator spins
    // forever. The button lives in the static "Backup now" card above
    // that list, so plain pumps render it.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Import backup file'), findsOneWidget);
    expect(find.text('Create backup'), findsOneWidget);
    expect(find.text('Export to Downloads'), findsOneWidget);
  });
}
