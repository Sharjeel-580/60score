// 60Score restore payload generator — "Super Sixty League" seed dataset.
//
// Until commit 9dcc4e3 ("Remove ALL seeded/default content") the app
// seeded this dataset on every fresh install (Store._seedFreshInstall
// + Store.buildDefaultFixtures, last present in v1.2.2 / commit
// 151053f). The app owner's on-device copy was lost (uninstall) and
// the cloud backups are empty, so this program rebuilds the exact
// seed dataset with the CURRENT model classes/serializers and writes
// the two payloads needed for a server-side restore:
//
//   restore/app_data_fields.json
//     Field name -> exact string value for the Firestore document
//     users/{uid}/backup/app_data, encoded byte-for-byte the way
//     SyncService._push encodes it (JSON strings per collection,
//     photos stripped the same way). `profile` and `updatedAt` are
//     intentionally NOT included — they are handled separately.
//
//   restore/published_doc.json
//     The published_tournaments/{tournamentId} document exactly as
//     PublishService._writeDoc composes it. FieldValue.serverTimestamp()
//     cannot be represented in JSON, so `updatedAt` carries the
//     placeholder '__SERVER_TIMESTAMP__'.
//
// The seeded tournament is restored with published = true (it was the
// owner's published league), keeping its stable seed IDs everywhere
// so every link (teamIds, fixture team ids) lines up.
//
// This file lives in tool/ (excluded from analysis) and imports
// Flutter libraries, so it is executed through the flutter tester:
//   flutter test test/zz_restore_driver_test.dart   (temporary driver)
// The driver calls [generateRestoreFiles].
import 'dart:convert';
import 'dart:io';

import 'package:cricket_scorer_app/models.dart';
import 'package:cricket_scorer_app/photo_sync.dart';
import 'package:cricket_scorer_app/publish_service.dart';
import 'package:cricket_scorer_app/store.dart';

/// Stable seed identity (verbatim from the removed seed code).
const kSeedTournamentId = 'seed_tournament_ssl2';
const kSeedTournamentName = 'Super Sixty League Season 2K26';
const kSeedVenue = '75 LOKRI CLUB';

/// Spec team order. IDs are stable: seed_team_0..5.
const kSeedTeamNames = [
  'AB Knights',
  'Shazi Hawks',
  'MA Kings',
  'Ali Panthers',
  'Adi Dolphins',
  'US Lions',
];

/// The app owner's account uid — owner of the restored backup and of
/// the published document.
const kOwnerUid = 'ZWbPNOWBY2hYO3yLkKZrj9lcssw2';

/// Placeholder for FieldValue.serverTimestamp() in published_doc.json.
const kServerTimestampPlaceholder = '__SERVER_TIMESTAMP__';

/// Builds the 15 league + 3 playoff fixtures of the seed tournament.
/// Ported verbatim from the removed Store.buildDefaultFixtures
/// (the idempotence `existing` check is dropped: the restore always
/// starts from an empty match list, so every fixture is created).
List<Match> buildSeedFixtures() {
  final out = <Match>[];
  String tid(String name) {
    final i = kSeedTeamNames.indexOf(name);
    return 'seed_team_$i';
  }

  // (matchNo, date yyyy-MM-dd, time HH:mm 24h, teamA, teamB)
  const league = [
    ['01', '2026-10-22', '14:00', 'Shazi Hawks', 'Adi Dolphins'],
    ['02', '2026-10-23', '15:00', 'AB Knights', 'Ali Panthers'],
    ['03', '2026-10-24', '14:00', 'Shazi Hawks', 'MA Kings'],
    ['04', '2026-10-25', '14:00', 'AB Knights', 'US Lions'],
    ['05', '2026-10-26', '14:00', 'MA Kings', 'Adi Dolphins'],
    ['06', '2026-10-27', '14:00', 'Shazi Hawks', 'Ali Panthers'],
    ['07', '2026-10-28', '14:00', 'MA Kings', 'US Lions'],
    ['08', '2026-10-29', '14:00', 'AB Knights', 'Shazi Hawks'],
    ['09', '2026-10-30', '15:00', 'MA Kings', 'Ali Panthers'],
    ['10', '2026-10-31', '14:00', 'Adi Dolphins', 'US Lions'],
    ['11', '2026-11-01', '14:00', 'AB Knights', 'MA Kings'],
    ['12', '2026-11-02', '14:00', 'Ali Panthers', 'Adi Dolphins'],
    ['13', '2026-11-03', '14:00', 'Shazi Hawks', 'US Lions'],
    ['14', '2026-11-04', '14:00', 'AB Knights', 'Adi Dolphins'],
    ['15', '2026-11-05', '14:00', 'Ali Panthers', 'US Lions'],
  ];
  for (final f in league) {
    out.add(
      Match(
        id: 'ssl2_m${f[0]}',
        tournamentId: kSeedTournamentId,
        teamAId: tid(f[3]),
        teamBId: tid(f[4]),
        xiA: const [],
        xiB: const [],
        tossWinnerId: '',
        status: 'upcoming',
        stage: 'league',
        oversLimit: 8,
        ballsPerOver: 6,
        venue: kSeedVenue,
        // Local match time as a plain string — never parsed as UTC,
        // so dates cannot shift across timezones.
        dateIso: '${f[1]}T${f[2]}:00',
        matchTitle: 'Match ${f[0]}',
        season: '2K26',
      ),
    );
  }
  // Playoff fixtures — teams stay TBD until qualification seeds them.
  const playoffs = [
    // id, stage, title, date, time
    ['ssl2_sf1', 'semifinal1', 'Semi Final 1', '2026-11-06', '15:00'],
    ['ssl2_sf2', 'semifinal2', 'Semi Final 2', '2026-11-07', '14:00'],
    ['ssl2_final', 'final', 'Grand Final', '2026-11-08', '14:00'],
  ];
  for (final p in playoffs) {
    out.add(
      Match(
        id: p[0],
        tournamentId: kSeedTournamentId,
        teamAId: '',
        teamBId: '',
        xiA: const [],
        xiB: const [],
        tossWinnerId: '',
        status: 'upcoming',
        stage: p[1],
        oversLimit: 8,
        ballsPerOver: 6,
        venue: kSeedVenue,
        dateIso: '${p[3]}T${p[4]}:00',
        matchTitle: p[2],
        season: '2K26',
      ),
    );
  }
  return out;
}

/// Builds a [Store] holding exactly the seed dataset — the port of the
/// removed Store._seedFreshInstall — with ONE deliberate difference:
/// the tournament carries published = true, because this restore is
/// for the owner's account whose league was published.
Store buildSeedStore() {
  final store = Store();
  store.teams = [
    for (var i = 0; i < kSeedTeamNames.length; i++)
      Team(id: 'seed_team_$i', name: kSeedTeamNames[i]),
  ];
  store.tournaments = [
    Tournament(
      id: kSeedTournamentId,
      name: kSeedTournamentName,
      teamIds: store.teams.map((t) => t.id).toList(),
      venue: kSeedVenue,
      published: true,
    ),
  ];
  store.matches = buildSeedFixtures();
  store.regPlayers = [];
  store.drafts = [];
  store.manualStats = [];
  return store;
}

/// The users/{uid}/backup/app_data field values, encoded EXACTLY as
/// SyncService._push writes them (same serializers, same photo
/// stripping, same hardcoded appVersion literal). Excludes `profile`
/// and `updatedAt` by design.
Map<String, String> appDataFields(Store store) => {
      'teams': jsonEncode(
          store.teams.map((t) => PhotoSync.stripPhotos(t.toJson())).toList()),
      'tournaments':
          jsonEncode(store.tournaments.map((t) => t.toJson()).toList()),
      'matches': jsonEncode(store.matches.map((m) => m.toJson()).toList()),
      'regPlayers': jsonEncode(store.regPlayers
          .map((r) => PhotoSync.stripPhotos(r.toJson()))
          .toList()),
      'drafts': jsonEncode(store.drafts.map((d) => d.toJson()).toList()),
      'manualStats':
          jsonEncode(store.manualStats.map((e) => e.toJson()).toList()),
      // Literal written by SyncService._push.
      'appVersion': '1.2.0',
    };

/// The published_tournaments/{seed id} document, composed EXACTLY as
/// PublishService._writeDoc composes it — the slice comes from the
/// service's own pure helpers. `updatedAt` is the server-timestamp
/// placeholder (see file header).
Map<String, dynamic> publishedDoc(Store store, {String ownerUid = kOwnerUid}) {
  final t = store.tournamentById(kSeedTournamentId)!;
  return {
    'ownerUid': ownerUid,
    'name': t.name,
    'venue': t.venue,
    'logoBase64': t.logoBase64,
    'updatedAt': kServerTimestampPlaceholder,
    'data': PublishService.encodeSlice(PublishService.buildSlice(store, t)),
  };
}

/// Writes both restore payloads into [outDir] (created if needed) and
/// returns the written files.
Future<List<File>> generateRestoreFiles(Directory outDir) async {
  final store = buildSeedStore();
  await outDir.create(recursive: true);
  const encoder = JsonEncoder.withIndent('  ');
  final appData = File('${outDir.path}/app_data_fields.json');
  await appData.writeAsString('${encoder.convert(appDataFields(store))}\n');
  final published = File('${outDir.path}/published_doc.json');
  await published.writeAsString('${encoder.convert(publishedDoc(store))}\n');
  return [appData, published];
}

/// Entry point when run from the package root under the flutter
/// tester: writes to ../restore (the repo-root restore/ folder).
Future<void> main() async {
  final outDir = Directory('${Directory.current.path}/../restore');
  final files = await generateRestoreFiles(outDir);
  for (final f in files) {
    stdout.writeln('wrote ${f.path} (${await f.length()} bytes)');
  }
}
