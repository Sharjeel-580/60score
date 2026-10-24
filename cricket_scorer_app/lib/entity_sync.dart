// Per-entity sync engine (Sync Fix "D", Phase C0) — see
// ~/workspace/60score-app/SYNC_FIX_D_PLAN.md.
//
// This file is the pure core of the new sync design: per-entity
// stamps, the hardened match merge (status → fall-of-wickets →
// legal balls → ball events → result text), the team player-union
// merge, tombstones (deletes that stay deleted), the server-gate
// decision functions, and the sync planner that converges two
// entity sets. It deliberately imports NOTHING from Firestore or
// the sync service, so every rule here is unit-testable and the
// exact same functions can run on the pull path, the push path
// and inside the Phase-D transaction gate.
//
// Status: Phase C1 wired this engine into SyncService behind its
// existing public API (dual-read, delta pushes, migration), with
// any failure falling back to the legacy blob path; Phase D adds
// the gated write policy below ([planGatedUpsert]) on the match
// and team write paths. The legacy compareMatchAdvancement /
// mergeMatches are intentionally left untouched; V2 lives
// alongside them.
import 'dart:convert';

import 'models.dart';

/// The entity collections that sync per-record. [tombstones] is a
/// pseudo-kind: its records are [Tombstone]s, synced like any other
/// entity so a deletion made anywhere reaches everywhere.
class EntityKind {
  static const String matches = 'matches';
  static const String teams = 'teams';
  static const String tournaments = 'tournaments';
  static const String regPlayers = 'regPlayers';
  static const String drafts = 'drafts';
  static const String manualStats = 'manualStats';
  static const String profile = 'profile';
  static const String tombstones = 'tombstones';

  /// All real (non-pseudo) kinds, in sync order.
  static const List<String> all = [
    matches,
    teams,
    tournaments,
    regPlayers,
    drafts,
    manualStats,
    profile,
  ];
}

/// A deletion record. A tombstone kills every copy of the entity —
/// any status, any richness, any stamp — with exactly one
/// exception: an explicit admin restore (a record written with
/// `restored: true` and a stamp newer than [deletedAt]). See the
/// plan, §4.
class Tombstone {
  final String kind;
  final String id;
  final int deletedAt;
  final String deviceId;

  const Tombstone({
    required this.kind,
    required this.id,
    required this.deletedAt,
    this.deviceId = '',
  });

  /// The document id under which this tombstone syncs: kind and
  /// entity id joined so one flat collection can hold all kinds.
  String get docId => '${kind}__$id';

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'id': id,
        'deletedAt': deletedAt,
        'deviceId': deviceId,
      };

  factory Tombstone.fromJson(Map<String, dynamic> j) => Tombstone(
        kind: j['kind'] as String? ?? '',
        id: j['id'] as String? ?? '',
        deletedAt: (j['deletedAt'] as num?)?.toInt() ?? 0,
        deviceId: j['deviceId'] as String? ?? '',
      );

  @override
  String toString() => 'Tombstone($kind/$id @ $deletedAt)';
}

/// One entity record plus its sync metadata. The entity itself is
/// kept as its decoded-JSON map — the exact map its `toJson()`
/// produces — so payload encodings never change shape; stamps and
/// flags travel OUTSIDE the entity JSON.
class StampedRecord {
  Map<String, dynamic> json;
  int stamp;
  bool restored;

  /// Per-player stamps (teams only): playerId → stamp.
  Map<String, int> playerStamps;

  StampedRecord(
    this.json, {
    this.stamp = 0,
    this.restored = false,
    Map<String, int>? playerStamps,
  }) : playerStamps = playerStamps ?? <String, int>{};

  String get id => json['id'] as String? ?? '';

  StampedRecord deepCopy() => StampedRecord(
        jsonDecode(jsonEncode(json)) as Map<String, dynamic>,
        stamp: stamp,
        restored: restored,
        playerStamps: Map<String, int>.of(playerStamps),
      );

  /// Content equality over everything the sync cares about.
  bool sameContent(StampedRecord other) =>
      stamp == other.stamp &&
      restored == other.restored &&
      jsonEncode(playerStamps) == jsonEncode(other.playerStamps) &&
      jsonEncode(json) == jsonEncode(other.json);

  Map<String, dynamic> toWrapperJson() => {
        'json': json,
        'stamp': stamp,
        'restored': restored,
        'playerStamps': playerStamps,
      };

  factory StampedRecord.fromWrapperJson(Map<String, dynamic> j) =>
      StampedRecord(
        (j['json'] as Map).cast<String, dynamic>(),
        stamp: (j['stamp'] as num?)?.toInt() ?? 0,
        restored: j['restored'] as bool? ?? false,
        playerStamps: ((j['playerStamps'] as Map?) ?? const {})
            .map((k, v) => MapEntry('$k', (v as num).toInt())),
      );
}

// ---------------------------------------------------------------------
// Match richness — the signals the hardened ranking reads.
// ---------------------------------------------------------------------

int matchFowCount(Match m) =>
    m.innings.fold(0, (acc, inn) => acc + inn.fallOfWickets.length);

int matchLegalBalls(Match m) =>
    m.innings.fold(0, (acc, inn) => acc + inn.legalBalls);

int matchBallEvents(Match m) =>
    m.innings.fold(0, (acc, inn) => acc + inn.events.length);

/// Status rank table for the V2 engine. Identical values to
/// SyncService.matchStatusRank (the legacy function is pinned by
/// its own tests and left untouched); a unit test asserts the two
/// tables agree for every known status so they can never drift.
int entityMatchStatusRank(String status) {
  switch (status) {
    case 'completed':
      return 5;
    case 'noResult':
    case 'cancelled':
      return 4;
    case 'live':
      return 3;
    case 'upcoming':
    case 'scheduled':
      return 1;
    default:
      return 0;
  }
}

/// The HARDENED advancement comparison (the harness-validated
/// ranking): status rank first — so a completed copy can never be
/// demoted by a non-completed one — then RICHNESS: fall-of-wickets
/// count, legal balls, ball events, then a non-empty result text.
/// Unlike the legacy ranking, a FoW-only enrichment is fully
/// visible here (its absence caused Failure 1, 2026-10-23).
int compareMatchAdvancementV2(Match a, Match b) {
  final rank =
      entityMatchStatusRank(a.status).compareTo(entityMatchStatusRank(b.status));
  if (rank != 0) return rank;
  final fow = matchFowCount(a).compareTo(matchFowCount(b));
  if (fow != 0) return fow;
  final balls = matchLegalBalls(a).compareTo(matchLegalBalls(b));
  if (balls != 0) return balls;
  final events = matchBallEvents(a).compareTo(matchBallEvents(b));
  if (events != 0) return events;
  final ra = a.resultText.isNotEmpty ? 1 : 0;
  final rb = b.resultText.isNotEmpty ? 1 : 0;
  return ra.compareTo(rb);
}

/// Deterministic final tie-break: the lexicographically larger
/// encoding wins, so merge(a, b) == merge(b, a) on every device.
int _jsonTieBreak(Map<String, dynamic> a, Map<String, dynamic> b) =>
    jsonEncode(a).compareTo(jsonEncode(b));

/// Merges two stamped copies of one match: the more advanced copy
/// (see [compareMatchAdvancementV2]) wins WHOLESALE — records are
/// coherent wholes; splicing fields from two copies could pair one
/// copy's FoW with the other's figures. Exact content ties go to
/// the newer stamp, then to the deterministic JSON tie-break.
StampedRecord mergeMatchRecords(StampedRecord a, StampedRecord b) {
  final ma = Match.fromJson(a.json);
  final mb = Match.fromJson(b.json);
  final c = compareMatchAdvancementV2(ma, mb);
  if (c > 0) return a.deepCopy();
  if (c < 0) return b.deepCopy();
  if (a.stamp != b.stamp) return (a.stamp > b.stamp ? a : b).deepCopy();
  return (_jsonTieBreak(a.json, b.json) >= 0 ? a : b).deepCopy();
}

/// Merges two stamped copies of one team: union of players by id;
/// each player's record comes from the side with the newer
/// per-player stamp (player-stamp ties go to the deterministic
/// JSON tie-break). Team-level fields come from the newer team
/// stamp. A player present on only one side is always kept — a
/// concurrent add and a concurrent rename both survive (S4).
StampedRecord mergeTeamRecords(StampedRecord a, StampedRecord b) {
  final ta = Team.fromJson(a.json);
  final tb = Team.fromJson(b.json);
  final byIdA = {for (final p in ta.players) p.id: p};
  final byIdB = {for (final p in tb.players) p.id: p};
  final ids = <String>{...byIdA.keys, ...byIdB.keys};
  final players = <Player>[];
  final pStamps = <String, int>{};
  for (final id in ids) {
    final sa = a.playerStamps[id] ?? -1;
    final sb = b.playerStamps[id] ?? -1;
    final Player winner;
    if (sa != sb) {
      winner = (sa > sb ? byIdA[id] : byIdB[id])!;
    } else {
      final pa = byIdA[id];
      final pb = byIdB[id];
      if (pa == null) {
        winner = pb!;
      } else if (pb == null) {
        winner = pa;
      } else {
        winner =
            _jsonTieBreak(pa.toJson(), pb.toJson()) >= 0 ? pa : pb;
      }
    }
    players.add(winner);
    pStamps[id] = sa >= sb ? sa : sb;
  }
  final Team base;
  if (a.stamp != b.stamp) {
    base = a.stamp > b.stamp ? ta : tb;
  } else {
    base = _jsonTieBreak(a.json, b.json) >= 0 ? ta : tb;
  }
  final merged = Team.fromJson(base.toJson());
  merged.players = players;
  return StampedRecord(
    merged.toJson(),
    stamp: a.stamp >= b.stamp ? a.stamp : b.stamp,
    restored: a.restored || b.restored,
    playerStamps: pStamps,
  );
}

/// Merge for the kinds with no cross-field invariants to protect
/// (tournaments, regPlayers, drafts, manualStats, profile):
/// per-entity last-write-wins by stamp, deterministic tie-break.
StampedRecord mergeGenericRecords(StampedRecord a, StampedRecord b) {
  if (a.stamp != b.stamp) return (a.stamp > b.stamp ? a : b).deepCopy();
  return (_jsonTieBreak(a.json, b.json) >= 0 ? a : b).deepCopy();
}

/// The per-kind merge dispatch used by the planner.
StampedRecord mergeRecordsForKind(
    String kind, StampedRecord a, StampedRecord b) {
  switch (kind) {
    case EntityKind.matches:
      return mergeMatchRecords(a, b);
    case EntityKind.teams:
      return mergeTeamRecords(a, b);
    default:
      return mergeGenericRecords(a, b);
  }
}

// ---------------------------------------------------------------------
// Tombstones
// ---------------------------------------------------------------------

/// Union of two tombstone lists; per (kind, id) the newest
/// deletedAt wins.
List<Tombstone> mergeTombstoneSets(
    Iterable<Tombstone> a, Iterable<Tombstone> b) {
  final byKey = <String, Tombstone>{};
  for (final t in [...a, ...b]) {
    if (t.kind.isEmpty || t.id.isEmpty) continue;
    final key = '${t.kind} ${t.id}';
    final cur = byKey[key];
    if (cur == null || t.deletedAt > cur.deletedAt) byKey[key] = t;
  }
  return byKey.values.toList();
}

Tombstone? tombstoneFor(List<Tombstone> set, String kind, String id) {
  for (final t in set) {
    if (t.kind == kind && t.id == id) return t;
  }
  return null;
}

/// Whether [record] survives [tombstone] (null = no tombstone =
/// survives). The ONLY survival path is an explicit admin restore:
/// the record carries the restored flag AND a stamp newer than
/// the deletion. A merely-held, merely-edited or forged copy never
/// survives — that is the delete-resurrection fix.
bool recordSurvivesTombstone(StampedRecord record, Tombstone? tombstone) {
  if (tombstone == null) return true;
  return record.restored && record.stamp > tombstone.deletedAt;
}

// ---------------------------------------------------------------------
// The server gate (Phase D specification, as pure functions).
// The Firestore transaction write path runs exactly these checks;
// the security rules approximate the status/stamp/tombstone parts.
// ---------------------------------------------------------------------

enum GateVerdict {
  accept,
  rejectDowngrade,
  rejectStaleStamp,
  rejectTombstoned,
}

/// Whether a match write may land over [stored] (null = no stored
/// doc). Mirrors the harness's DServer.writeMatch, plus tombstones:
/// - a tombstone-killed write is rejected (unless it is an explicit
///   restore, which is then judged on its merits);
/// - a copy the hardened ranking calls POORER than the stored one
///   is rejected REGARDLESS of its stamp — a forged fresh stamp
///   cannot talk its way past the gate;
/// - a copy with an older stamp than the stored one is rejected.
GateVerdict gateMatchWrite({
  required StampedRecord incoming,
  StampedRecord? stored,
  Tombstone? tombstone,
}) {
  if (!recordSurvivesTombstone(incoming, tombstone)) {
    return GateVerdict.rejectTombstoned;
  }
  if (stored != null) {
    final c = compareMatchAdvancementV2(
        Match.fromJson(incoming.json), Match.fromJson(stored.json));
    if (c < 0) return GateVerdict.rejectDowngrade;
    if (incoming.stamp < stored.stamp) return GateVerdict.rejectStaleStamp;
  }
  return GateVerdict.accept;
}

/// Whether a team write may land over [stored]. Mirrors the
/// harness's DServer.writeTeam: older stamps are rejected, and a
/// write that would silently DROP players is rejected unless it
/// carries a strictly newer stamp (an intentional squad reduction
/// is a newer decision; an accidental stale overwrite is not).
GateVerdict gateTeamWrite({
  required StampedRecord incoming,
  StampedRecord? stored,
  Tombstone? tombstone,
}) {
  if (!recordSurvivesTombstone(incoming, tombstone)) {
    return GateVerdict.rejectTombstoned;
  }
  if (stored != null) {
    if (incoming.stamp < stored.stamp) return GateVerdict.rejectStaleStamp;
    final curIds =
        Team.fromJson(stored.json).players.map((p) => p.id).toSet();
    final incIds =
        Team.fromJson(incoming.json).players.map((p) => p.id).toSet();
    if (curIds.difference(incIds).isNotEmpty &&
        incoming.stamp <= stored.stamp) {
      return GateVerdict.rejectDowngrade;
    }
  }
  return GateVerdict.accept;
}

/// The gate dispatch for one kind: matches and teams run their
/// full gate functions; the remaining kinds have no richness to
/// protect, so their gate is exactly the tombstone rule plus the
/// stamp floor (per-entity last-write-wins, plan §3.3).
GateVerdict gateWriteForKind({
  required String kind,
  required StampedRecord incoming,
  StampedRecord? stored,
  Tombstone? tombstone,
}) {
  switch (kind) {
    case EntityKind.matches:
      return gateMatchWrite(
          incoming: incoming, stored: stored, tombstone: tombstone);
    case EntityKind.teams:
      return gateTeamWrite(
          incoming: incoming, stored: stored, tombstone: tombstone);
    default:
      if (!recordSurvivesTombstone(incoming, tombstone)) {
        return GateVerdict.rejectTombstoned;
      }
      if (stored != null && incoming.stamp < stored.stamp) {
        return GateVerdict.rejectStaleStamp;
      }
      return GateVerdict.accept;
  }
}

/// The outcome of planning one gated upsert (Phase D): what — if
/// anything — may be written over the stored document.
class GatedUpsertPlan {
  /// The FIRST gate verdict for the incoming record as presented.
  /// When [toWrite] is non-null the write lands (possibly with the
  /// re-merged record rather than the presented one); when
  /// [converged] is true nothing needed writing at all.
  final GateVerdict verdict;

  /// The record to write, or null to write nothing.
  final StampedRecord? toWrite;

  /// The write is an accepted explicit restore: its tombstone
  /// must be deleted in the same operation.
  final bool spendTombstone;

  /// The stored document already holds the converged winner —
  /// the upsert was a no-op, not a loss.
  final bool converged;

  const GatedUpsertPlan({
    required this.verdict,
    this.toWrite,
    this.spendTombstone = false,
    this.converged = false,
  });
}

/// Plans one gated upsert — the write policy shared VERBATIM by
/// the Firestore transaction path (lib/entity_firestore.dart) and
/// the in-memory gated store the tests run against, so both make
/// identical decisions:
///
/// - Gate accepts → write the incoming record as presented.
/// - Tombstone rejects → write nothing, ever: a killed record is
///   not negotiable through merging (a merged copy carries no
///   restore flag the original lacked).
/// - Downgrade / stale-stamp rejects (a stored doc exists) → the
///   harness's dSync pattern: re-merge the incoming copy with the
///   stored one and retry ONCE with the converged record, its
///   stamp floored at the stored stamp (content richness decides
///   the winner; the stamp only has to stop being stale). If the
///   converged record IS the stored one, the upsert is a no-op
///   ([GatedUpsertPlan.converged]) — the richer copy survives
///   untouched, which is the gate doing its job.
GatedUpsertPlan planGatedUpsert({
  required String kind,
  required StampedRecord incoming,
  StampedRecord? stored,
  Tombstone? tombstone,
}) {
  final verdict = gateWriteForKind(
      kind: kind, incoming: incoming, stored: stored, tombstone: tombstone);
  if (verdict == GateVerdict.accept) {
    return GatedUpsertPlan(
      verdict: verdict,
      toWrite: incoming,
      spendTombstone: incoming.restored && tombstone != null,
    );
  }
  if (verdict == GateVerdict.rejectTombstoned || stored == null) {
    return GatedUpsertPlan(verdict: verdict);
  }
  final merged = mergeRecordsForKind(kind, incoming, stored);
  if (!recordSurvivesTombstone(merged, tombstone)) {
    return GatedUpsertPlan(verdict: verdict);
  }
  final candidate = merged.deepCopy();
  if (candidate.stamp < stored.stamp) candidate.stamp = stored.stamp;
  if (candidate.sameContent(stored)) {
    return GatedUpsertPlan(verdict: verdict, converged: true);
  }
  final retry = gateWriteForKind(
      kind: kind, incoming: candidate, stored: stored, tombstone: tombstone);
  if (retry != GateVerdict.accept) {
    return GatedUpsertPlan(verdict: verdict);
  }
  return GatedUpsertPlan(
    verdict: verdict,
    toWrite: candidate,
    spendTombstone: candidate.restored && tombstone != null,
  );
}

// ---------------------------------------------------------------------
// The sync planner: converge two entity sets.
// A "set" is kind → id → record. Tombstones travel inside the set
// under EntityKind.tombstones, keyed by Tombstone.docId, their
// record json being the tombstone JSON and their stamp = deletedAt.
// ---------------------------------------------------------------------

typedef EntitySet = Map<String, Map<String, StampedRecord>>;

EntitySet emptyEntitySet() => {
      for (final k in [...EntityKind.all, EntityKind.tombstones])
        k: <String, StampedRecord>{},
    };

StampedRecord tombstoneToRecord(Tombstone t) => StampedRecord(
      t.toJson(),
      stamp: t.deletedAt,
    );

Tombstone recordToTombstone(StampedRecord r) =>
    Tombstone.fromJson(r.json);

List<Tombstone> tombstonesOf(EntitySet set) => [
      for (final r
          in (set[EntityKind.tombstones] ?? const {}).values)
        recordToTombstone(r),
    ];

/// The converged set both sides should hold after a sync round:
/// tombstones unioned first, then per kind/id the merged record —
/// dropped when a tombstone kills it. A record that survives via
/// an explicit restore REMOVES its tombstone from the converged
/// set, so the deletion cannot strike again later.
EntitySet mergeEntitySets(EntitySet local, EntitySet remote) {
  final out = emptyEntitySet();
  var tombstones = mergeTombstoneSets(
      tombstonesOf(local), tombstonesOf(remote));
  for (final kind in EntityKind.all) {
    final l = local[kind] ?? const <String, StampedRecord>{};
    final r = remote[kind] ?? const <String, StampedRecord>{};
    final ids = <String>{...l.keys, ...r.keys};
    for (final id in ids) {
      final a = l[id];
      final b = r[id];
      final merged = a == null
          ? b!.deepCopy()
          : (b == null ? a.deepCopy() : mergeRecordsForKind(kind, a, b));
      final t = tombstoneFor(tombstones, kind, id);
      if (!recordSurvivesTombstone(merged, t)) {
        continue; // killed: absent from the converged set
      }
      if (t != null) {
        // Survived via explicit restore: the tombstone is spent.
        tombstones = [
          for (final x in tombstones)
            if (!(x.kind == kind && x.id == id)) x,
        ];
      }
      out[kind]![id] = merged;
    }
  }
  for (final t in tombstones) {
    out[EntityKind.tombstones]![t.docId] = tombstoneToRecord(t);
  }
  return out;
}

/// The writes/deletes that turn [current] into [target].
class EntityDiff {
  final Map<String, Map<String, StampedRecord>> upserts = {};
  final Map<String, Set<String>> deletes = {};

  bool get isEmpty => upserts.isEmpty && deletes.isEmpty;
}

EntityDiff diffEntitySets(EntitySet current, EntitySet target) {
  final diff = EntityDiff();
  final kinds = <String>{...current.keys, ...target.keys};
  for (final kind in kinds) {
    final c = current[kind] ?? const <String, StampedRecord>{};
    final t = target[kind] ?? const <String, StampedRecord>{};
    for (final id in t.keys) {
      final cur = c[id];
      if (cur == null || !cur.sameContent(t[id]!)) {
        (diff.upserts[kind] ??= {})[id] = t[id]!.deepCopy();
      }
    }
    for (final id in c.keys) {
      if (!t.containsKey(id)) {
        (diff.deletes[kind] ??= {}).add(id);
      }
    }
  }
  return diff;
}

/// A store of entity documents — the local store and the cloud are
/// both just implementations of this. The Firestore implementation
/// lives in entity_firestore.dart; tests use [InMemoryEntityDocStore].
abstract class EntityDocStore {
  Future<EntitySet> readAll();
  Future<void> applyDiff(EntityDiff diff);
}

/// In-memory [EntityDocStore] (tests; also the reference for what
/// applyDiff must mean).
class InMemoryEntityDocStore implements EntityDocStore {
  EntitySet sets;

  InMemoryEntityDocStore([EntitySet? initial])
      : sets = initial ?? emptyEntitySet();

  @override
  Future<EntitySet> readAll() async => {
        for (final e in sets.entries)
          e.key: {
            for (final r in e.value.entries) r.key: r.value.deepCopy(),
          },
      };

  @override
  Future<void> applyDiff(EntityDiff diff) async {
    diff.upserts.forEach((kind, records) {
      final bucket = sets[kind] ??= <String, StampedRecord>{};
      records.forEach((id, r) => bucket[id] = r.deepCopy());
    });
    diff.deletes.forEach((kind, ids) {
      final bucket = sets[kind];
      if (bucket == null) return;
      for (final id in ids) {
        bucket.remove(id);
      }
    });
  }
}

/// One full sync round between two stores: read both, merge, and
/// write the converged set back to BOTH. Returns the converged set.
/// This is candidate C's read-modify-write expressed once, against
/// an interface — the algorithm the harness validated, now running
/// on production merge functions.
Future<EntitySet> synchronizeEntityStores(
    EntityDocStore a, EntityDocStore b) async {
  final sa = await a.readAll();
  final sb = await b.readAll();
  final merged = mergeEntitySets(sa, sb);
  await a.applyDiff(diffEntitySets(sa, merged));
  await b.applyDiff(diffEntitySets(sb, merged));
  return merged;
}

/// An [InMemoryEntityDocStore] whose match/team upserts pass
/// through the Phase-D gate — the in-memory twin of the Firestore
/// store's transactional gated writes (lib/entity_firestore.dart),
/// running the very same [planGatedUpsert] policy. Tests use it as
/// "the cloud" to prove a rogue writer that bypasses the client
/// merge (a stale or legacy build writing directly) cannot
/// downgrade, back-date or resurrect a record, while honest
/// writes land. Deletes and the other kinds keep the plain
/// in-memory behaviour.
class GatedInMemoryEntityDocStore extends InMemoryEntityDocStore {
  GatedInMemoryEntityDocStore([super.initial]);

  @override
  Future<void> applyDiff(EntityDiff diff) async {
    // Gated kinds first, one record at a time — like one
    // transaction per document on the Firestore side.
    for (final kind in const [EntityKind.matches, EntityKind.teams]) {
      final upserts = diff.upserts[kind];
      if (upserts == null) continue;
      for (final e in upserts.entries) {
        _applyGatedUpsert(kind, e.key, e.value);
      }
    }
    final rest = EntityDiff();
    diff.upserts.forEach((kind, records) {
      if (kind == EntityKind.matches || kind == EntityKind.teams) return;
      rest.upserts[kind] = records;
    });
    rest.deletes.addAll(diff.deletes);
    if (!rest.isEmpty) await super.applyDiff(rest);
  }

  void _applyGatedUpsert(String kind, String id, StampedRecord incoming) {
    final stored = sets[kind]?[id];
    final tomb = tombstoneFor(tombstonesOf(sets), kind, id);
    final plan = planGatedUpsert(
        kind: kind, incoming: incoming, stored: stored, tombstone: tomb);
    final write = plan.toWrite;
    if (write == null) return;
    (sets[kind] ??= <String, StampedRecord>{})[id] = write.deepCopy();
    if (plan.spendTombstone && tomb != null) {
      sets[EntityKind.tombstones]?.remove(tomb.docId);
    }
  }
}
