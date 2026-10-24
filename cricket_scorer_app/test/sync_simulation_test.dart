// Sync-approach simulation harness (2026-10-23, research only —
// no production code is changed by this file).
//
// The owner ordered: enumerate every credible sync approach for
// 60Score, TEST each against the failure scenarios proven live on
// 2026-10-23, and recommend the one that actually works. This file
// is that test bench. An in-memory "cloud" and two simulated
// devices per candidate; each candidate's write/merge policy is
// implemented faithfully but minimally:
//
//  A  Status quo — single blob + the REAL SyncService.mergeMatches
//     and SyncService.decidePull imported from lib/sync_service.dart.
//     Two write paths exist in the app and both are modelled:
//     the persist-triggered blind push (_push never reads the doc)
//     and receive-then-push (_handleRemoteData).
//  B  Single blob + hardened merge (per-entity stamps, richness
//     ranking incl. fall-of-wickets, completed freeze) and
//     pull-before-push: a push is always merge(current cloud) first.
//  C  Per-entity documents + the same hardened merge, applied
//     read-modify-write per document. A "naive" variant (overwrite
//     only locally-dirty docs, no merge read) is also run — it is
//     what a minimal per-doc migration would look like.
//  D  Per-entity documents + a simulated server gate: writes that
//     would downgrade a match (lower advancement, or an older
//     entity stamp) are REJECTED, including writes from a legacy
//     blind client. Client merge identical to C.
//  E  Event-sourced: per-match append-only event log in the cloud;
//     state is derived by folding events. Devices upload queued
//     events (deduplicated by event id) and download events they
//     have not seen. There is no whole record to overwrite.
//  F  Off-the-shelf engines (PowerSync / Replicache / Couchbase…)
//     are assessed in SYNC_OPTIONS_TESTED.md only — a vendor
//     engine's semantics cannot be simulated faithfully here, so
//     F is deliberately UNTESTED in this harness.
//
// Simplifications, stated once: tournaments/regPlayers/drafts are
// omitted from the device state (in the real app tournaments are
// plain last-write-wins exactly like teams, so the team results
// stand for them); player photos (separate subcollection in the
// real app) are out of scope; device clocks are small integers.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:cricket_scorer_app/models.dart';
import 'package:cricket_scorer_app/sync_service.dart';

// ---------------------------------------------------------------------
// Fixtures (shared by all candidates)
// ---------------------------------------------------------------------

List<String> xiIds(String p) => [for (var i = 1; i <= 11; i++) '$p$i'];

Team hawksTeam() => Team(
      id: 'hawks',
      name: 'Shazi Hawks',
      players: [
        for (var i = 1; i <= 11; i++) Player(id: 'h$i', name: 'Hawks Player $i')
      ],
    );

Team dolphinsTeam() => Team(
      id: 'dolphins',
      name: 'Adi Dolphins',
      players: [
        for (var i = 1; i <= 11; i++)
          Player(id: 'd$i', name: 'Dolphins Player $i')
      ],
    );

InningsState mkInn(
  String batId,
  String bowlId,
  String batP, {
  required int runs,
  required int wkts,
  required int balls,
  required int events,
  required int fow,
}) {
  final other = batP == 'h' ? 'd' : 'h';
  final inn = InningsState(
    battingTeamId: batId,
    bowlingTeamId: bowlId,
    battingXI: xiIds(batP),
    bowlingXI: xiIds(other),
    oversLimit: 8,
  );
  inn.totalRuns = runs;
  inn.wickets = wkts;
  inn.legalBalls = balls;
  for (var n = 0; n < events; n++) {
    inn.events.add(BallEvent(
      strikerId: '${batP}1',
      nonStrikerId: '${batP}2',
      bowlerId: '${other}1',
      totalRuns: 1,
      legalBall: true,
    ));
  }
  for (var n = 0; n < fow; n++) {
    inn.fallOfWickets.add(FallOfWicket(
        n + 1, (runs * (n + 1) / (fow + 1)).round(), '${n ~/ 6}.${n % 6}',
        '$batP${n + 1}'));
  }
  return inn;
}

/// The completed Match 01. [fow1]/[fow2] are the fall-of-wickets
/// counts — the ONLY difference between the cloud-baked copy
/// (8 and 2) and the stale phone copy (5 and 0). Balls, events,
/// totals and result text are identical, exactly as in the real
/// incident (the bake enriched FoW only).
Match m1({required int fow1, required int fow2}) => Match(
      id: 'm1',
      teamAId: 'hawks',
      teamBId: 'dolphins',
      xiA: xiIds('h'),
      xiB: xiIds('d'),
      tossWinnerId: 'hawks',
      status: 'completed',
      resultText: 'Adi Dolphins won by 8 wickets',
      innings: [
        mkInn('hawks', 'dolphins', 'h',
            runs: 117, wkts: 8, balls: 48, events: 52, fow: fow1),
        mkInn('dolphins', 'hawks', 'd',
            runs: 118, wkts: 2, balls: 40, events: 44, fow: fow2),
      ],
    );

/// Device B's day-old copy of Match 01: still live at 68/5.
Match m1LiveOld() => Match(
      id: 'm1',
      teamAId: 'hawks',
      teamBId: 'dolphins',
      xiA: xiIds('h'),
      xiB: xiIds('d'),
      tossWinnerId: 'hawks',
      status: 'live',
      resultText: '',
      innings: [
        mkInn('hawks', 'dolphins', 'h',
            runs: 68, wkts: 5, balls: 30, events: 34, fow: 3),
      ],
    );

/// The brand-new match scored (offline) in S2/S3.
Match m2() => Match(
      id: 'm2',
      teamAId: 'dolphins',
      teamBId: 'hawks',
      xiA: xiIds('d'),
      xiB: xiIds('h'),
      tossWinnerId: 'dolphins',
      status: 'completed',
      resultText: 'Shazi Hawks won by 6 wickets',
      innings: [
        mkInn('dolphins', 'hawks', 'd',
            runs: 96, wkts: 6, balls: 48, events: 50, fow: 6),
        mkInn('hawks', 'dolphins', 'h',
            runs: 97, wkts: 4, balls: 45, events: 47, fow: 4),
      ],
    );

int fowTotal(Match m) =>
    m.innings.fold(0, (a, i) => a + i.fallOfWickets.length);

Match? matchById(List<Match> ms, String id) {
  for (final m in ms) {
    if (m.id == id) return m;
  }
  return null;
}

Team? teamById(List<Team> ts, String id) {
  for (final t in ts) {
    if (t.id == id) return t;
  }
  return null;
}

String encMatches(List<Match> ms) =>
    jsonEncode(ms.map((m) => m.toJson()).toList());
List<Match> decMatches(String s) => (jsonDecode(s) as List)
    .map((e) => Match.fromJson(e as Map<String, dynamic>))
    .toList();
String encTeams(List<Team> ts) => jsonEncode(ts.map((t) => t.toJson()).toList());
List<Team> decTeams(String s) => (jsonDecode(s) as List)
    .map((e) => Team.fromJson(e as Map<String, dynamic>))
    .toList();

Match cloneMatch(Match m) => Match.fromJson(m.toJson());

// ---------------------------------------------------------------------
// Diagnosis: the ranking blindness behind Failure 1, using the
// REAL production merge code.
// ---------------------------------------------------------------------

void diagnosisTests() {
  group('Diagnosis (real production code)', () {
    test('compareMatchAdvancement cannot see a FoW-only enrichment: '
        'baked copy and stale copy tie exactly', () {
      final baked = m1(fow1: 8, fow2: 2);
      final stale = m1(fow1: 5, fow2: 0);
      expect(SyncService.compareMatchAdvancement(baked, stale), 0);
      expect(SyncService.compareMatchAdvancement(stale, baked), 0);
    });

    test('on a tie mergeMatches keeps the LOCAL copy — so a device '
        'holding the stale copy keeps it, and pushes it back', () {
      final baked = m1(fow1: 8, fow2: 2);
      final stale = m1(fow1: 5, fow2: 0);
      final merged = SyncService.mergeMatches([stale], [baked]);
      expect(fowTotal(merged.single), 5); // the enrichment is lost
    });
  });
}

// ---------------------------------------------------------------------
// Candidate A — status quo (single blob, real merge + decidePull)
// ---------------------------------------------------------------------

class ACloud {
  String teamsJson = '[]';
  String matchesJson = '[]';
  int updatedAt = 0;
}

class ADev {
  List<Team> teams;
  List<Match> matches;
  int lastModified;
  ADev(this.teams, this.matches, this.lastModified);
}

/// The production _push: writes the whole local dataset, never
/// reads the cloud document first.
void aPush(ADev d, ACloud c, int now) {
  c.teamsJson = encTeams(d.teams);
  c.matchesJson = encMatches(d.matches);
  c.updatedAt = now;
  d.lastModified = now;
}

/// The production _handleRemoteData core (teams + matches subset):
/// decidePull arbitrates the dataset; matches always go through
/// mergeMatches; a merged result that differs from the cloud is
/// pushed back up.
void aReceive(ADev d, ACloud c, int now) {
  final rTeams = decTeams(c.teamsJson);
  final rMatches = decMatches(c.matchesJson);
  final decision = SyncService.decidePull(
    localEmpty: d.teams.isEmpty && d.matches.isEmpty,
    remoteEmpty: rTeams.isEmpty && rMatches.isEmpty,
    remoteNewer: c.updatedAt > d.lastModified,
  );
  final merged = SyncService.mergeMatches(d.matches, rMatches);
  final mergedVsLocal = !SyncService.sameMatchContent(merged, d.matches);
  final mergedVsRemote = !SyncService.sameMatchContent(merged, rMatches);
  switch (decision) {
    case PullDecision.keepLocalAndPush:
      aPush(d, c, now);
      return;
    case PullDecision.noImport:
      if (mergedVsLocal) d.matches = merged;
      if (mergedVsRemote) aPush(d, c, now);
      return;
    case PullDecision.importRemote:
      d.teams = rTeams;
      d.matches = merged;
      d.lastModified = c.updatedAt;
      if (mergedVsRemote) aPush(d, c, now);
      return;
  }
}

void candidateA() {
  group('Candidate A — status quo (single blob + v1.3.5 merge)', () {
    test('S1 bake clobber, blind push path: FAILS — cloud FoW '
        'reverts 10 -> 5', () {
      final cloud = ACloud()
        ..teamsJson = encTeams([hawksTeam(), dolphinsTeam()])
        ..matchesJson = encMatches([m1(fow1: 8, fow2: 2)])
        ..updatedAt = 5000;
      final b = ADev([hawksTeam(), dolphinsTeam()],
          [m1(fow1: 5, fow2: 0)], 6000);
      // B adds a player offline; the persist triggers a blind push.
      teamById(b.teams, 'hawks')!.players.add(Player(id: 'h99', name: 'New'));
      aPush(b, cloud, 7000);
      final cloudM1 = matchById(decMatches(cloud.matchesJson), 'm1')!;
      // The new player DID arrive...
      expect(
          teamById(decTeams(cloud.teamsJson), 'hawks')!
              .players
              .any((p) => p.id == 'h99'),
          isTrue);
      // ...but the bake is gone. Scenario criterion (FoW kept) fails.
      expect(fowTotal(cloudM1), 5);
    });

    test('S1 bake clobber, receive path (noImport): FAILS the same '
        'way — the tie keeps local, merged==local is pushed back', () {
      final cloud = ACloud()
        ..teamsJson = encTeams([hawksTeam(), dolphinsTeam()])
        ..matchesJson = encMatches([m1(fow1: 8, fow2: 2)])
        ..updatedAt = 5000;
      final b = ADev([hawksTeam(), dolphinsTeam()],
          [m1(fow1: 5, fow2: 0)], 6000); // local clock ahead -> noImport
      teamById(b.teams, 'hawks')!.players.add(Player(id: 'h99', name: 'New'));
      aReceive(b, cloud, 7000);
      final cloudM1 = matchById(decMatches(cloud.matchesJson), 'm1')!;
      expect(fowTotal(cloudM1), 5);
    });

    test('S1 bake clobber, receive path (importRemote): FAILS worse '
        '— FoW reverts AND the offline-added player is lost', () {
      final cloud = ACloud()
        ..teamsJson = encTeams([hawksTeam(), dolphinsTeam()])
        ..matchesJson = encMatches([m1(fow1: 8, fow2: 2)])
        ..updatedAt = 5000;
      final b = ADev([hawksTeam(), dolphinsTeam()],
          [m1(fow1: 5, fow2: 0)], 4000); // remote newer -> importRemote
      teamById(b.teams, 'hawks')!.players.add(Player(id: 'h99', name: 'New'));
      aReceive(b, cloud, 7000);
      final cloudM1 = matchById(decMatches(cloud.matchesJson), 'm1')!;
      expect(fowTotal(cloudM1), 5);
      // Teams are wholesale-replaced on import: B's player never
      // reaches the cloud at all.
      expect(
          teamById(decTeams(cloud.teamsJson), 'hawks')!
              .players
              .any((p) => p.id == 'h99'),
          isFalse);
    });

    test('S2 full rewind, blind push path: FAILS — completed M1 '
        'becomes live 68/5 in the cloud', () {
      final cloud = ACloud()
        ..teamsJson = encTeams([hawksTeam(), dolphinsTeam()])
        ..matchesJson = encMatches([m1(fow1: 8, fow2: 2)])
        ..updatedAt = 5000;
      // B holds a day-old dataset and scores a new match offline.
      final b = ADev([hawksTeam(), dolphinsTeam()], [m1LiveOld()], 6000);
      b.matches.add(m2());
      aPush(b, cloud, 7000);
      final cloudMatches = decMatches(cloud.matchesJson);
      expect(matchById(cloudMatches, 'm2'), isNotNull); // new match arrived
      final cloudM1 = matchById(cloudMatches, 'm1')!;
      expect(cloudM1.status, 'live'); // ...but M1 was rewound. FAIL.
      expect(cloudM1.innings.first.totalRuns, 68);
    });

    test('S2 variant, receive-first path: PASSES — the merge heals '
        'B before the push (this is the path the incident did NOT '
        'take)', () {
      final cloud = ACloud()
        ..teamsJson = encTeams([hawksTeam(), dolphinsTeam()])
        ..matchesJson = encMatches([m1(fow1: 8, fow2: 2)])
        ..updatedAt = 5000;
      final b = ADev([hawksTeam(), dolphinsTeam()], [m1LiveOld()], 6000);
      b.matches.add(m2());
      aReceive(b, cloud, 7000); // merges: completed M1 beats live copy
      aPush(b, cloud, 7100); // the subsequent persist-push is healed
      final cloudMatches = decMatches(cloud.matchesJson);
      expect(matchById(cloudMatches, 'm1')!.status, 'completed');
      expect(matchById(cloudMatches, 'm2'), isNotNull);
    });

    test('S3 offline scoring: PASSES — the new match lands exactly '
        'once, even when the push is retried', () {
      final cloud = ACloud()
        ..teamsJson = encTeams([hawksTeam(), dolphinsTeam()])
        ..matchesJson = encMatches([m1(fow1: 8, fow2: 2)])
        ..updatedAt = 5000;
      final b = ADev([hawksTeam(), dolphinsTeam()],
          [m1(fow1: 8, fow2: 2)], 5000);
      b.matches.add(m2()); // scored fully offline
      aPush(b, cloud, 7000);
      aPush(b, cloud, 7100); // retry after a failure: idempotent
      final cloudMatches = decMatches(cloud.matchesJson);
      expect(cloudMatches.where((m) => m.id == 'm2'), hasLength(1));
      expect(matchById(cloudMatches, 'm2')!.status, 'completed');
      final ids = decTeams(cloud.teamsJson)
          .expand((t) => t.players.map((p) => p.id))
          .toList();
      expect(ids.toSet(), hasLength(ids.length)); // no duplicate players
    });

    test('S4 concurrent edits: FAILS — teams are never merged; the '
        'offline player add is lost on the import path', () {
      final cloud = ACloud()
        ..teamsJson = encTeams([hawksTeam(), dolphinsTeam()])
        ..matchesJson = encMatches([m1(fow1: 8, fow2: 2)])
        ..updatedAt = 5000;
      final a = ADev([hawksTeam(), dolphinsTeam()],
          [m1(fow1: 8, fow2: 2)], 5000);
      final b = ADev([hawksTeam(), dolphinsTeam()],
          [m1(fow1: 8, fow2: 2)], 6000);
      // A renames a player and syncs.
      teamById(a.teams, 'hawks')!.players.first.name = 'Renamed Captain';
      aPush(a, cloud, 7000);
      // B (offline, older sync stamp) adds a different player, syncs.
      teamById(b.teams, 'hawks')!
          .players
          .add(Player(id: 'h98', name: 'Added By B'));
      aReceive(b, cloud, 8000); // importRemote: teams replaced wholesale
      final cloudHawks = teamById(decTeams(cloud.teamsJson), 'hawks')!;
      expect(cloudHawks.players.first.name, 'Renamed Captain');
      expect(cloudHawks.players.any((p) => p.id == 'h98'), isFalse); // FAIL
    });

    test('S5 fresh pull: PASSES for the receiving device — A ends '
        'with the union (but only because A still held the good '
        'copy locally; the cloud itself was broken until A healed '
        'it)', () {
      // State after the S2 blind-push rewind:
      final cloud = ACloud()
        ..teamsJson = encTeams([hawksTeam(), dolphinsTeam()])
        ..matchesJson = encMatches([m1LiveOld(), m2()])
        ..updatedAt = 7000;
      final a = ADev([hawksTeam(), dolphinsTeam()],
          [m1(fow1: 8, fow2: 2)], 4000);
      aReceive(a, cloud, 8000);
      expect(matchById(a.matches, 'm2'), isNotNull);
      final aM1 = matchById(a.matches, 'm1')!;
      expect(aM1.status, 'completed');
      expect(fowTotal(aM1), 10);
    });
  });
}

void main() {
  diagnosisTests();
  candidateA();
  candidateB();
  candidateC();
  candidateD();
  candidateE();
}

// ---------------------------------------------------------------------
// Shared machinery for candidates B, C, D: entities wrapped with a
// per-entity stamp (and per-player stamps inside a team).
// An "Ent" is {'json': <entity json>, 'stamp': int,
//               'pStamps': {playerId: int}}  (pStamps used by teams).
// ---------------------------------------------------------------------

typedef Ent = Map<String, dynamic>;

Ent deepEnt(Ent e) => jsonDecode(jsonEncode(e)) as Map<String, dynamic>;

Ent mEnt(Match m, int stamp) =>
    {'json': m.toJson(), 'stamp': stamp, 'pStamps': <String, int>{}};

Ent tEnt(Team t, int stamp, [Map<String, int>? pStamps]) => {
      'json': t.toJson(),
      'stamp': stamp,
      'pStamps': pStamps ?? {for (final p in t.players) p.id: stamp},
    };

Match mOf(Ent e) => Match.fromJson(e['json'] as Map<String, dynamic>);
Team tOf(Ent e) => Team.fromJson(e['json'] as Map<String, dynamic>);

int _jsonFow(Map<String, dynamic> j) => (j['innings'] as List)
    .fold(0, (a, i) => a + ((i['fallOfWickets'] as List).length));
int _jsonBalls(Map<String, dynamic> j) => (j['innings'] as List)
    .fold(0, (a, i) => a + ((i['legalBalls'] as num).toInt()));
int _jsonEvents(Map<String, dynamic> j) => (j['innings'] as List)
    .fold(0, (a, i) => a + ((i['events'] as List).length));

/// The HARDENED advancement comparison (candidates B/C/D): status
/// rank first (a completed copy therefore can never be downgraded
/// by a non-completed one — the freeze), then RICHNESS —
/// fall-of-wickets count, legal balls, ball events — then a
/// non-empty result text. Unlike the production ranking, a
/// FoW-only enrichment is fully visible here.
int richCmp(Map<String, dynamic> ja, Map<String, dynamic> jb) {
  final ra = SyncService.matchStatusRank(ja['status'] as String);
  final rb = SyncService.matchStatusRank(jb['status'] as String);
  if (ra != rb) return ra.compareTo(rb);
  final f = _jsonFow(ja).compareTo(_jsonFow(jb));
  if (f != 0) return f;
  final b = _jsonBalls(ja).compareTo(_jsonBalls(jb));
  if (b != 0) return b;
  final e = _jsonEvents(ja).compareTo(_jsonEvents(jb));
  if (e != 0) return e;
  final ta = (ja['resultText'] as String).isNotEmpty ? 1 : 0;
  final tb = (jb['resultText'] as String).isNotEmpty ? 1 : 0;
  return ta.compareTo(tb);
}

/// Merge two copies of one match: the more advanced copy wins
/// WHOLESALE (records are coherent wholes — splicing fields from
/// two copies could pair one copy's FoW with the other's figures).
/// Exact ties go to the newer per-entity stamp.
Ent mergeMEnt(Ent a, Ent b) {
  final c = richCmp(a['json'] as Map<String, dynamic>,
      b['json'] as Map<String, dynamic>);
  if (c > 0) return deepEnt(a);
  if (c < 0) return deepEnt(b);
  return (a['stamp'] as int) >= (b['stamp'] as int)
      ? deepEnt(a)
      : deepEnt(b);
}

/// Merge two copies of one team: union of players by id; each
/// player's record comes from the side with the newer per-player
/// stamp. Team-level fields come from the newer team stamp.
Ent mergeTEnt(Ent a, Ent b) {
  final ta = tOf(a);
  final tb = tOf(b);
  final pa = (a['pStamps'] as Map).cast<String, int>();
  final pb = (b['pStamps'] as Map).cast<String, int>();
  final byIdA = {for (final p in ta.players) p.id: p};
  final byIdB = {for (final p in tb.players) p.id: p};
  final ids = <String>{...byIdA.keys, ...byIdB.keys};
  final players = <Player>[];
  final pStamps = <String, int>{};
  for (final id in ids) {
    final sa = pa[id] ?? -1;
    final sb = pb[id] ?? -1;
    final winner = sa >= sb ? byIdA[id] : byIdB[id];
    players.add(winner ?? byIdA[id] ?? byIdB[id]!);
    pStamps[id] = sa >= sb ? sa : sb;
  }
  final base = (a['stamp'] as int) >= (b['stamp'] as int) ? ta : tb;
  final merged = Team(id: base.id, name: base.name, players: players);
  return tEnt(merged,
      (a['stamp'] as int) > (b['stamp'] as int)
          ? a['stamp'] as int
          : b['stamp'] as int,
      pStamps);
}

/// A world of entities: one device store, one blob, or one set of
/// per-entity documents — the merge does not care which.
class World {
  Map<String, Ent> matches = {};
  Map<String, Ent> teams = {};
  World clone() {
    final w = World();
    matches.forEach((k, v) => w.matches[k] = deepEnt(v));
    teams.forEach((k, v) => w.teams[k] = deepEnt(v));
    return w;
  }
}

World mergeWorlds(World x, World y) {
  final out = World();
  final mIds = <String>{...x.matches.keys, ...y.matches.keys};
  for (final id in mIds) {
    final a = x.matches[id];
    final b = y.matches[id];
    out.matches[id] =
        a == null ? deepEnt(b!) : (b == null ? deepEnt(a) : mergeMEnt(a, b));
  }
  final tIds = <String>{...x.teams.keys, ...y.teams.keys};
  for (final id in tIds) {
    final a = x.teams[id];
    final b = y.teams[id];
    out.teams[id] =
        a == null ? deepEnt(b!) : (b == null ? deepEnt(a) : mergeTEnt(a, b));
  }
  return out;
}

void copyInto(World dst, World src) {
  dst.matches = {
    for (final e in src.matches.entries) e.key: deepEnt(e.value)
  };
  dst.teams = {for (final e in src.teams.entries) e.key: deepEnt(e.value)};
}

World baseWorld() {
  final w = World();
  w.matches['m1'] = mEnt(m1(fow1: 8, fow2: 2), 200); // post-bake copy
  w.teams['hawks'] = tEnt(hawksTeam(), 100);
  w.teams['dolphins'] = tEnt(dolphinsTeam(), 100);
  return w;
}

/// B's stale world: M1 with partial FoW (stamp older than the bake).
World staleWorldB() {
  final w = World();
  w.matches['m1'] = mEnt(m1(fow1: 5, fow2: 0), 90);
  w.teams['hawks'] = tEnt(hawksTeam(), 100);
  w.teams['dolphins'] = tEnt(dolphinsTeam(), 100);
  return w;
}

void addPlayerB(World w, {String id = 'h99', int stamp = 300}) {
  final t = tOf(w.teams['hawks']!);
  t.players.add(Player(id: id, name: 'New Player $id'));
  final ps = (w.teams['hawks']!['pStamps'] as Map).cast<String, int>();
  ps[id] = stamp;
  w.teams['hawks'] = tEnt(t, stamp, ps);
}

// ---------------------------------------------------------------------
// Candidate B — single blob + hardened merge + pull-before-push.
// A sync reads the current cloud blob, merges EVERY entity with
// the hardened rules, writes the merged blob back and keeps it.
// There is no blind write path.
// ---------------------------------------------------------------------

void bSync(World dev, World cloud) {
  final merged = mergeWorlds(dev, cloud);
  copyInto(cloud, merged);
  copyInto(dev, merged);
}

void candidateB() {
  group('Candidate B — blob + hardened merge + pull-before-push', () {
    test('S1 bake clobber: PASSES — richness ranking keeps the '
        'baked FoW, player-union keeps the offline add', () {
      final cloud = baseWorld();
      final b = staleWorldB();
      addPlayerB(b);
      bSync(b, cloud);
      expect(fowTotal(mOf(cloud.matches['m1']!)), 10);
      expect(
          tOf(cloud.teams['hawks']!).players.any((p) => p.id == 'h99'),
          isTrue);
    });

    test('S2 full rewind: PASSES — completed M1 cannot be demoted '
        'by the day-old live copy; the new match lands', () {
      final cloud = baseWorld();
      final b = World()
        ..matches['m1'] = mEnt(m1LiveOld(), 90)
        ..teams['hawks'] = tEnt(hawksTeam(), 100)
        ..teams['dolphins'] = tEnt(dolphinsTeam(), 100);
      b.matches['m2'] = mEnt(m2(), 310);
      bSync(b, cloud);
      expect(mOf(cloud.matches['m1']!).status, 'completed');
      expect(mOf(cloud.matches['m1']!).resultText,
          'Adi Dolphins won by 8 wickets');
      expect(mOf(cloud.matches['m2']!).status, 'completed');
      // B itself is healed too.
      expect(mOf(b.matches['m1']!).status, 'completed');
    });

    test('S3 offline scoring: PASSES — exactly once, even on a '
        'repeated sync', () {
      final cloud = baseWorld();
      final b = baseWorld();
      b.matches['m2'] = mEnt(m2(), 310);
      bSync(b, cloud);
      bSync(b, cloud);
      expect(cloud.matches.keys.where((k) => k == 'm2'), hasLength(1));
      expect(mOf(cloud.matches['m2']!).status, 'completed');
    });

    test('S4 concurrent edits: PASSES — per-player stamps keep '
        'both the rename and the add', () {
      final cloud = baseWorld();
      final a = baseWorld();
      final b = baseWorld();
      // A renames h1 (player stamp 500) and syncs.
      final ta = tOf(a.teams['hawks']!);
      ta.players.first.name = 'Renamed Captain';
      final psa = (a.teams['hawks']!['pStamps'] as Map).cast<String, int>();
      psa['h1'] = 500;
      a.teams['hawks'] = tEnt(ta, 500, psa);
      bSync(a, cloud);
      // B (offline) adds a player (stamp 400) and syncs.
      addPlayerB(b, id: 'h98', stamp: 400);
      bSync(b, cloud);
      final hawks = tOf(cloud.teams['hawks']!);
      expect(hawks.players.first.name, 'Renamed Captain');
      expect(hawks.players.any((p) => p.id == 'h98'), isTrue);
    });

    test('S5 fresh pull: PASSES — A ends with the union', () {
      final cloud = baseWorld();
      final b = staleWorldB();
      b.matches['m2'] = mEnt(m2(), 310);
      bSync(b, cloud);
      final a = staleWorldB(); // A also held a stale M1 copy
      bSync(a, cloud);
      expect(mOf(a.matches['m1']!).status, 'completed');
      expect(fowTotal(mOf(a.matches['m1']!)), 10);
      expect(a.matches.containsKey('m2'), isTrue);
    });
  });
}

// ---------------------------------------------------------------------
// Candidate C — per-entity documents + hardened merge
// (read-modify-write per document). The naive variant overwrites
// only locally-dirty documents without reading them first.
// ---------------------------------------------------------------------

void cSync(World dev, World cloud) {
  // Same end state as B's merge, reached document by document:
  // for every entity id on either side, merge and store the winner
  // in BOTH the cloud doc and the local store.
  final merged = mergeWorlds(dev, cloud);
  copyInto(cloud, merged);
  copyInto(dev, merged);
}

void cNaiveSync(World dev, World cloud, Set<String> dirtyMatchIds,
    Set<String> dirtyTeamIds) {
  for (final id in dirtyMatchIds) {
    cloud.matches[id] = deepEnt(dev.matches[id]!);
  }
  for (final id in dirtyTeamIds) {
    cloud.teams[id] = deepEnt(dev.teams[id]!);
  }
}

void candidateC() {
  group('Candidate C — per-entity docs + hardened merge', () {
    test('S1 bake clobber: PASSES', () {
      final cloud = baseWorld();
      final b = staleWorldB();
      addPlayerB(b);
      cSync(b, cloud);
      expect(fowTotal(mOf(cloud.matches['m1']!)), 10);
      expect(
          tOf(cloud.teams['hawks']!).players.any((p) => p.id == 'h99'),
          isTrue);
    });

    test('S2 full rewind: PASSES', () {
      final cloud = baseWorld();
      final b = World()
        ..matches['m1'] = mEnt(m1LiveOld(), 90)
        ..teams['hawks'] = tEnt(hawksTeam(), 100)
        ..teams['dolphins'] = tEnt(dolphinsTeam(), 100);
      b.matches['m2'] = mEnt(m2(), 310);
      cSync(b, cloud);
      expect(mOf(cloud.matches['m1']!).status, 'completed');
      expect(cloud.matches.containsKey('m2'), isTrue);
    });

    test('S3 offline scoring: PASSES — exactly once', () {
      final cloud = baseWorld();
      final b = baseWorld();
      b.matches['m2'] = mEnt(m2(), 310);
      cSync(b, cloud);
      cSync(b, cloud);
      expect(cloud.matches.keys.where((k) => k == 'm2'), hasLength(1));
    });

    test('S4 concurrent edits: PASSES (merge read-modify-write)', () {
      final cloud = baseWorld();
      final a = baseWorld();
      final b = baseWorld();
      final ta = tOf(a.teams['hawks']!);
      ta.players.first.name = 'Renamed Captain';
      final psa = (a.teams['hawks']!['pStamps'] as Map).cast<String, int>();
      psa['h1'] = 500;
      a.teams['hawks'] = tEnt(ta, 500, psa);
      cSync(a, cloud);
      addPlayerB(b, id: 'h98', stamp: 400);
      cSync(b, cloud);
      final hawks = tOf(cloud.teams['hawks']!);
      expect(hawks.players.first.name, 'Renamed Captain');
      expect(hawks.players.any((p) => p.id == 'h98'), isTrue);
    });

    test('S5 fresh pull: PASSES — A ends with the union', () {
      final cloud = baseWorld();
      final b = staleWorldB();
      b.matches['m2'] = mEnt(m2(), 310);
      cSync(b, cloud);
      final a = staleWorldB();
      cSync(a, cloud);
      expect(fowTotal(mOf(a.matches['m1']!)), 10);
      expect(a.matches.containsKey('m2'), isTrue);
    });
  });

  group('Candidate C-naive — per-entity docs, overwrite dirty docs '
      'only, NO merge read', () {
    test('S1: PASSES — granularity alone saves the bake (B never '
        'touches the match doc)', () {
      final cloud = baseWorld();
      final b = staleWorldB();
      addPlayerB(b);
      cNaiveSync(b, cloud, {}, {'hawks'});
      expect(fowTotal(mOf(cloud.matches['m1']!)), 10);
      expect(
          tOf(cloud.teams['hawks']!).players.any((p) => p.id == 'h99'),
          isTrue);
    });

    test('S2: PASSES — B writes only the new match doc; the '
        'completed M1 doc is never rewritten', () {
      final cloud = baseWorld();
      final b = World()
        ..matches['m1'] = mEnt(m1LiveOld(), 90)
        ..teams['hawks'] = tEnt(hawksTeam(), 100)
        ..teams['dolphins'] = tEnt(dolphinsTeam(), 100);
      b.matches['m2'] = mEnt(m2(), 310);
      cNaiveSync(b, cloud, {'m2'}, {});
      expect(mOf(cloud.matches['m1']!).status, 'completed');
      expect(cloud.matches.containsKey('m2'), isTrue);
    });

    test('S4: FAILS — a dirty team doc written wholesale erases '
        'the concurrent rename', () {
      final cloud = baseWorld();
      final a = baseWorld();
      final ta = tOf(a.teams['hawks']!);
      ta.players.first.name = 'Renamed Captain';
      a.teams['hawks'] = tEnt(ta, 500);
      cNaiveSync(a, cloud, {}, {'hawks'});
      final b = baseWorld();
      addPlayerB(b, id: 'h98', stamp: 400);
      cNaiveSync(b, cloud, {}, {'hawks'});
      final hawks = tOf(cloud.teams['hawks']!);
      expect(hawks.players.any((p) => p.id == 'h98'), isTrue);
      expect(hawks.players.first.name, 'Hawks Player 1'); // rename lost
    });
  });
}

// ---------------------------------------------------------------------
// Candidate D — per-entity documents + server-enforced protection.
// The client merge is C's. The difference is the gate every write
// must pass (modelled atomically, as a Firestore transaction /
// security-rule check would): a match write that would DOWNGRADE
// the stored copy — lower advancement, or an older entity stamp —
// is rejected, whoever sends it, including a legacy client that
// writes blindly. On rejection the client re-reads, re-merges and
// retries once.
// ---------------------------------------------------------------------

bool entEq(Ent a, Ent b) => jsonEncode(a) == jsonEncode(b);

class DServer {
  final World docs = World();
  int rejected = 0;

  bool writeMatch(String id, Ent inc) {
    final cur = docs.matches[id];
    if (cur != null) {
      final c = richCmp(inc['json'] as Map<String, dynamic>,
          cur['json'] as Map<String, dynamic>);
      if (c < 0) {
        rejected++;
        return false; // downgrade attempt
      }
      if ((inc['stamp'] as int) < (cur['stamp'] as int)) {
        rejected++;
        return false; // stale stamp
      }
    }
    docs.matches[id] = deepEnt(inc);
    return true;
  }

  bool writeTeam(String id, Ent inc) {
    final cur = docs.teams[id];
    if (cur != null) {
      final curIds = tOf(cur).players.map((p) => p.id).toSet();
      final incIds = tOf(inc).players.map((p) => p.id).toSet();
      final dropsPlayers = curIds.difference(incIds).isNotEmpty;
      if ((inc['stamp'] as int) < (cur['stamp'] as int)) {
        rejected++;
        return false;
      }
      if (dropsPlayers && (inc['stamp'] as int) <= (cur['stamp'] as int)) {
        rejected++;
        return false; // would silently drop players with no newer stamp
      }
    }
    docs.teams[id] = deepEnt(inc);
    return true;
  }
}

void dSync(World dev, DServer srv) {
  final mIds = <String>{...dev.matches.keys, ...srv.docs.matches.keys};
  for (final id in mIds) {
    final cur = srv.docs.matches[id];
    final mine = dev.matches[id];
    if (cur == null) {
      srv.writeMatch(id, mine!);
    } else if (mine == null) {
      // pull-only
    } else {
      final merged = mergeMEnt(mine, cur);
      if (!entEq(merged, cur) && !srv.writeMatch(id, merged)) {
        final cur2 = srv.docs.matches[id]!;
        final merged2 = mergeMEnt(mine, cur2);
        if (!entEq(merged2, cur2)) srv.writeMatch(id, merged2);
      }
    }
    dev.matches[id] = deepEnt(srv.docs.matches[id]!);
  }
  final tIds = <String>{...dev.teams.keys, ...srv.docs.teams.keys};
  for (final id in tIds) {
    final cur = srv.docs.teams[id];
    final mine = dev.teams[id];
    if (cur == null) {
      srv.writeTeam(id, mine!);
    } else if (mine == null) {
      // pull-only
    } else {
      final merged = mergeTEnt(mine, cur);
      if (!entEq(merged, cur) && !srv.writeTeam(id, merged)) {
        final cur2 = srv.docs.teams[id]!;
        final merged2 = mergeTEnt(mine, cur2);
        if (!entEq(merged2, cur2)) srv.writeTeam(id, merged2);
      }
    }
    dev.teams[id] = deepEnt(srv.docs.teams[id]!);
  }
}

World worldFrom(DServer s) => s.docs.clone();

void candidateD() {
  group('Candidate D — per-entity docs + server gate', () {
    test('S1 bake clobber: PASSES', () {
      final srv = DServer();
      copyInto(srv.docs, baseWorld());
      final b = staleWorldB();
      addPlayerB(b);
      dSync(b, srv);
      expect(fowTotal(mOf(srv.docs.matches['m1']!)), 10);
      expect(
          tOf(srv.docs.teams['hawks']!).players.any((p) => p.id == 'h99'),
          isTrue);
    });

    test('S2 full rewind: PASSES', () {
      final srv = DServer();
      copyInto(srv.docs, baseWorld());
      final b = World()
        ..matches['m1'] = mEnt(m1LiveOld(), 90)
        ..teams['hawks'] = tEnt(hawksTeam(), 100)
        ..teams['dolphins'] = tEnt(dolphinsTeam(), 100);
      b.matches['m2'] = mEnt(m2(), 310);
      dSync(b, srv);
      expect(mOf(srv.docs.matches['m1']!).status, 'completed');
      expect(srv.docs.matches.containsKey('m2'), isTrue);
    });

    test('S3 offline scoring: PASSES — exactly once', () {
      final srv = DServer();
      copyInto(srv.docs, baseWorld());
      final b = baseWorld();
      b.matches['m2'] = mEnt(m2(), 310);
      dSync(b, srv);
      dSync(b, srv);
      expect(srv.docs.matches.keys.where((k) => k == 'm2'), hasLength(1));
    });

    test('S4 concurrent edits: PASSES', () {
      final srv = DServer();
      copyInto(srv.docs, baseWorld());
      final a = baseWorld();
      final ta = tOf(a.teams['hawks']!);
      ta.players.first.name = 'Renamed Captain';
      final psa = (a.teams['hawks']!['pStamps'] as Map).cast<String, int>();
      psa['h1'] = 500;
      a.teams['hawks'] = tEnt(ta, 500, psa);
      dSync(a, srv);
      final b = baseWorld();
      addPlayerB(b, id: 'h98', stamp: 400);
      dSync(b, srv);
      final hawks = tOf(srv.docs.teams['hawks']!);
      expect(hawks.players.first.name, 'Renamed Captain');
      expect(hawks.players.any((p) => p.id == 'h98'), isTrue);
    });

    test('S5 fresh pull: PASSES — A ends with the union', () {
      final srv = DServer();
      copyInto(srv.docs, baseWorld());
      final b = staleWorldB();
      b.matches['m2'] = mEnt(m2(), 310);
      dSync(b, srv);
      final a = staleWorldB();
      dSync(a, srv);
      expect(fowTotal(mOf(a.matches['m1']!)), 10);
      expect(a.matches.containsKey('m2'), isTrue);
    });

    test('ROGUE legacy client (blind whole-record writes, the '
        'v1.3.8 push behaviour): the gate rejects every downgrade '
        '— Failures 1 and 2 cannot recur even from an old app '
        'version', () {
      final srv = DServer();
      copyInto(srv.docs, baseWorld());
      // Failure 1 replay: stale M1 written blindly, honest old stamp.
      expect(srv.writeMatch('m1', mEnt(m1(fow1: 5, fow2: 0), 90)), isFalse);
      // Same write with a FORGED fresh stamp: richness still rejects.
      expect(srv.writeMatch('m1', mEnt(m1(fow1: 5, fow2: 0), 999)), isFalse);
      // Failure 2 replay: day-old live M1 written blindly.
      expect(srv.writeMatch('m1', mEnt(m1LiveOld(), 999)), isFalse);
      expect(fowTotal(mOf(srv.docs.matches['m1']!)), 10);
      expect(mOf(srv.docs.matches['m1']!).status, 'completed');
      // But a legacy client can still ADD a brand-new match.
      expect(srv.writeMatch('m2', mEnt(m2(), 50)), isTrue);
      expect(srv.rejected, greaterThanOrEqualTo(3));
    });
  });
}

// ---------------------------------------------------------------------
// Candidate E — event-sourced. The cloud holds, per entity, an
// append-only log of events with globally unique ids. Match state
// (totals, FoW, status) is DERIVED by folding the log; FoW is a
// count of wicket ball-events, so it cannot be "edited away" — a
// device can only ever hold a PREFIX of the log (incomplete),
// never a contradictory record. Team state folds player events.
// ---------------------------------------------------------------------

class Ev {
  final String id;
  final String entity;
  final String kind; // created | ball | completed | playerAdded | playerRenamed
  final Map<String, dynamic> d;
  final int stamp;
  Ev(this.id, this.entity, this.kind, this.d, this.stamp);
}

class Emitter {
  final String name;
  int _n = 0;
  Emitter(this.name);
  Ev emit(String entity, String kind, Map<String, dynamic> d, int stamp) =>
      Ev('$name-${++_n}', entity, kind, d, stamp);
}

class ECloud {
  final Map<String, List<Ev>> log = {};
  final Set<String> ids = {};
  int append(Iterable<Ev> evs) {
    var added = 0;
    for (final e in evs) {
      if (ids.add(e.id)) {
        (log[e.entity] ??= []).add(e);
        added++;
      }
    }
    return added;
  }
}

class EDev {
  final Emitter em;
  int clock;
  final Map<String, List<Ev>> local = {};
  final Set<String> seen = {};
  final List<Ev> pending = [];
  EDev(String name, this.clock) : em = Emitter(name);

  Ev emit(String entity, String kind, Map<String, dynamic> d) {
    final e = em.emit(entity, kind, d, ++clock);
    (local[entity] ??= []).add(e);
    seen.add(e.id);
    pending.add(e);
    return e;
  }

  void sync(ECloud c) {
    c.append(pending);
    pending.clear();
    c.log.forEach((entity, evs) {
      for (final e in evs) {
        if (seen.add(e.id)) (local[entity] ??= []).add(e);
      }
    });
  }
}

class MSum {
  String status = 'upcoming';
  int r1 = 0, r2 = 0, f1 = 0, f2 = 0, b1 = 0, b2 = 0;
  String result = '';
}

MSum deriveMatch(List<Ev> evs) {
  final s = MSum();
  for (final e in evs) {
    if (e.kind == 'ball') {
      if (s.status != 'completed') s.status = 'live';
      if (e.d['inn'] == 1) {
        s.r1 += e.d['runs'] as int;
        s.b1++;
        if (e.d['wicket'] == true) s.f1++;
      } else {
        s.r2 += e.d['runs'] as int;
        s.b2++;
        if (e.d['wicket'] == true) s.f2++;
      }
    } else if (e.kind == 'completed') {
      s.status = 'completed';
      s.result = e.d['result'] as String;
    }
  }
  return s;
}

Map<String, String> derivePlayers(List<Ev> evs) {
  final names = <String, String>{};
  final stamps = <String, int>{};
  final sorted = [...evs]..sort((a, b) => a.stamp.compareTo(b.stamp));
  for (final e in sorted) {
    if (e.kind == 'playerAdded') {
      names[e.d['pid'] as String] = e.d['name'] as String;
      stamps[e.d['pid'] as String] = e.stamp;
    } else if (e.kind == 'playerRenamed') {
      final pid = e.d['pid'] as String;
      if (e.stamp >= (stamps[pid] ?? -1)) {
        names[pid] = e.d['name'] as String;
        stamps[pid] = e.stamp;
      }
    }
  }
  return names;
}

/// Score a complete match on [dev] as events.
void scoreAsEvents(
  EDev dev,
  String matchId, {
  required int inn1Balls,
  required int inn1Runs,
  required int inn1Wkts,
  required int inn2Balls,
  required int inn2Runs,
  required int inn2Wkts,
  required String result,
}) {
  final entity = 'match:$matchId';
  dev.emit(entity, 'created', {'matchId': matchId});
  void innings(int inn, int balls, int runs, int wkts) {
    var left = runs;
    for (var i = 0; i < balls; i++) {
      final r = i == balls - 1 ? left : (left ~/ (balls - i));
      left -= r;
      dev.emit(entity, 'ball',
          {'inn': inn, 'runs': r, 'wicket': i < wkts});
    }
  }

  innings(1, inn1Balls, inn1Runs, inn1Wkts);
  innings(2, inn2Balls, inn2Runs, inn2Wkts);
  dev.emit(entity, 'completed', {'result': result});
}

void seedCloudMatch01(ECloud cloud) {
  final scorer = EDev('scorer', 100);
  scoreAsEvents(scorer, 'm1',
      inn1Balls: 48,
      inn1Runs: 117,
      inn1Wkts: 8,
      inn2Balls: 40,
      inn2Runs: 118,
      inn2Wkts: 2,
      result: 'Adi Dolphins won by 8 wickets');
  scorer.sync(cloud);
}

void seedCloudTeams(ECloud cloud) {
  final seed = Emitter('seed');
  final evs = <Ev>[];
  for (var i = 1; i <= 11; i++) {
    evs.add(seed.emit('team:hawks', 'playerAdded',
        {'pid': 'h$i', 'name': 'Hawks Player $i'}, 1));
    evs.add(seed.emit('team:dolphins', 'playerAdded',
        {'pid': 'd$i', 'name': 'Dolphins Player $i'}, 1));
  }
  cloud.append(evs);
}

/// Give [dev] a PREFIX of the cloud log for [entity] — the
/// event-world shape of "holding a stale copy": incomplete,
/// never contradictory.
void givePrefix(EDev dev, ECloud cloud, String entity, int count) {
  final evs = cloud.log[entity]!.take(count).toList();
  dev.local[entity] = evs;
  for (final e in evs) {
    dev.seen.add(e.id);
  }
}

void candidateE() {
  group('Candidate E — event-sourced (append-only logs)', () {
    test('S1 bake-clobber analogue: PASSES — B holds only a prefix '
        'of M1; its sync appends a player event and downloads the '
        'rest. Cloud FoW (derived) is untouchable', () {
      final cloud = ECloud();
      seedCloudTeams(cloud);
      seedCloudMatch01(cloud);
      final b = EDev('B', 300);
      givePrefix(b, cloud, 'match:m1', 60); // stale = incomplete
      b.emit('team:hawks', 'playerAdded', {'pid': 'h99', 'name': 'New'});
      b.sync(cloud);
      final s = deriveMatch(cloud.log['match:m1']!);
      expect(s.status, 'completed');
      expect(s.f1, 8);
      expect(s.f2, 2);
      expect(derivePlayers(cloud.log['team:hawks']!).containsKey('h99'),
          isTrue);
      // B healed itself from the same log.
      expect(deriveMatch(b.local['match:m1']!).status, 'completed');
    });

    test('S2 full-rewind analogue: PASSES — appends cannot rewind '
        'M1; the new match arrives as its own stream', () {
      final cloud = ECloud();
      seedCloudTeams(cloud);
      seedCloudMatch01(cloud);
      final b = EDev('B', 300);
      givePrefix(b, cloud, 'match:m1', 31); // day-old live prefix
      final before = deriveMatch(b.local['match:m1']!);
      expect(before.status, 'live');
      expect(before.r1, lessThan(117));
      scoreAsEvents(b, 'm2',
          inn1Balls: 48,
          inn1Runs: 96,
          inn1Wkts: 6,
          inn2Balls: 45,
          inn2Runs: 97,
          inn2Wkts: 4,
          result: 'Shazi Hawks won by 6 wickets');
      b.sync(cloud);
      final m1 = deriveMatch(cloud.log['match:m1']!);
      expect(m1.status, 'completed');
      expect(m1.r1, 117);
      expect(m1.r2, 118);
      final m2s = deriveMatch(cloud.log['match:m2']!);
      expect(m2s.status, 'completed');
      expect(m2s.r2, 97);
    });

    test('S3 offline scoring: PASSES — exactly once, even if the '
        'upload is retried after a crash-before-ack', () {
      final cloud = ECloud();
      seedCloudTeams(cloud);
      final b = EDev('B', 300);
      scoreAsEvents(b, 'm2',
          inn1Balls: 48,
          inn1Runs: 96,
          inn1Wkts: 6,
          inn2Balls: 45,
          inn2Runs: 97,
          inn2Wkts: 4,
          result: 'Shazi Hawks won by 6 wickets');
      final resent = [...b.pending];
      b.sync(cloud);
      final logLen = cloud.log['match:m2']!.length;
      expect(cloud.append(resent), 0); // retry deduped by event id
      expect(cloud.log['match:m2']!.length, logLen);
      expect(
          cloud.log['match:m2']!.where((e) => e.kind == 'created'),
          hasLength(1));
      expect(deriveMatch(cloud.log['match:m2']!).r1, 96);
    });

    test('S4 concurrent edits: PASSES — rename and add are '
        'independent events; the fold keeps both', () {
      final cloud = ECloud();
      seedCloudTeams(cloud);
      final a = EDev('A', 500);
      a.sync(cloud);
      a.emit('team:hawks', 'playerRenamed',
          {'pid': 'h1', 'name': 'Renamed Captain'});
      a.sync(cloud);
      final b = EDev('B', 400); // B's clock is behind A's — fine here
      b.sync(cloud);
      // B had NOT seen the rename when it added its player offline:
      b.local['team:hawks'] = b.local['team:hawks']!
          .where((e) => e.kind != 'playerRenamed')
          .toList();
      b.seen.removeWhere(
          (id) => cloud.log['team:hawks']!.any((e) => e.id == id && e.kind == 'playerRenamed'));
      b.emit('team:hawks', 'playerAdded', {'pid': 'h98', 'name': 'Added'});
      b.sync(cloud);
      final players = derivePlayers(cloud.log['team:hawks']!);
      expect(players['h1'], 'Renamed Captain');
      expect(players.containsKey('h98'), isTrue);
    });

    test('S5 fresh pull: PASSES — A downloads the missing events '
        'and derives the union', () {
      final cloud = ECloud();
      seedCloudTeams(cloud);
      seedCloudMatch01(cloud);
      final a = EDev('A', 500);
      a.sync(cloud); // A current through Match 01
      final b = EDev('B', 300);
      givePrefix(b, cloud, 'match:m1', 31);
      scoreAsEvents(b, 'm2',
          inn1Balls: 48,
          inn1Runs: 96,
          inn1Wkts: 6,
          inn2Balls: 45,
          inn2Runs: 97,
          inn2Wkts: 4,
          result: 'Shazi Hawks won by 6 wickets');
      b.sync(cloud);
      a.sync(cloud);
      expect(deriveMatch(a.local['match:m1']!).status, 'completed');
      expect(deriveMatch(a.local['match:m1']!).f1, 8);
      expect(deriveMatch(a.local['match:m2']!).status, 'completed');
    });
  });
}
