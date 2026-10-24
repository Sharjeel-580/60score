// Wiring for the per-entity sync engine (Sync Fix "D", Phase C1) —
// see ~/workspace/60score-app/SYNC_FIX_D_PLAN.md §6–§8 and
// lib/entity_sync.dart for the pure merge/gate rules.
//
// This file holds everything SyncService needs to run on the
// entity engine behind its existing public API:
//
// - [entitySetFromBlobData]: explodes a legacy backup document
//   (the exact field map of users/{uid}/backup/app_data) into an
//   [EntitySet], stamping every record with the blob's updatedAt —
//   its honest age (plan §6 step 2). Decoding mirrors the legacy
//   pull's tolerance: a field that fails to decode contributes no
//   records for its kind instead of failing the whole read.
// - [BlobSource]: where the legacy blob comes from (Firestore in
//   production, in-memory in tests).
// - [StoreEntityDocStore]: the LOCAL side as an [EntityDocStore]
//   over the app [Store], so the coordinator — and its tests —
//   treat the phone exactly like any other doc store. Per-entity
//   stamps (plan §3.4) live here: a record's stamp bumps to
//   max(now, previous + 1) when its content actually changes, and
//   is otherwise stable, so an unchanged record never churns the
//   delta push. Stamp state persists in SharedPreferences under
//   one additive, per-identity key.
// - [EntitySyncCoordinator]: one sync round (dual-read: entity
//   docs ∪ legacy blob, merged with the local set; the converged
//   set is written back as DELTA diffs to both sides — never a
//   whole-dataset rewrite) plus the migration runner (plan §6):
//   the first round that finds a legacy blob explodes it into the
//   entity collections and verifies counts + spot figures before
//   calling the migration done. The blob itself is NEVER written
//   or deleted here — it stays as the read-only fallback until
//   Phase E.
//
// Nothing in this file knows about Firestore security rules or
// the Phase-D gate: gated writes are a later, separately approved
// step. If the entity collections are unreachable (e.g. the live
// rules predate them), the coordinator's futures throw and
// SyncService falls back to the legacy blob path unchanged.
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'account_profile.dart';
import 'entity_firestore.dart';
import 'entity_sync.dart';
import 'models.dart';
import 'photo_sync.dart';
import 'store.dart';

/// A decoded legacy backup document, exploded into per-entity
/// records. Every record's stamp is the blob's own updatedAt.
class BlobSnapshot {
  final EntitySet entities;
  final int updatedAt;
  const BlobSnapshot(this.entities, this.updatedAt);
}

List<T>? _decodeBlobList<T>(
    Object? raw, T Function(Map<String, dynamic>) fromJson) {
  if (raw is! String || raw.isEmpty) return [];
  try {
    final list = jsonDecode(raw) as List;
    return list.map((e) => fromJson(e as Map<String, dynamic>)).toList();
  } catch (_) {
    return null;
  }
}

/// Explodes one legacy backup document's field map into an
/// [EntitySet]. Pure and static so the conversion is unit-testable
/// against a hand-built blob map — no Firestore needed.
BlobSnapshot entitySetFromBlobData(Map<String, dynamic> data) {
  final updatedAt = (data['updatedAt'] as num?)?.toInt() ?? 0;
  final set = emptyEntitySet();

  void addAll<T>(String kind, List<T>? items,
      Map<String, dynamic> Function(T) toJson) {
    if (items == null) return;
    for (final item in items) {
      final json = toJson(item);
      final rec = StampedRecord(json, stamp: updatedAt);
      if (kind == EntityKind.teams) {
        // Every player was current as of the blob's write, which
        // is the honest per-player stamp for an exploded record.
        final players = json['players'];
        if (players is List) {
          rec.playerStamps = {
            for (final p in players)
              if (p is Map && p['id'] is String)
                p['id'] as String: updatedAt,
          };
        }
      }
      set[kind]![rec.id] = rec;
    }
  }

  addAll(EntityKind.teams, _decodeBlobList(data['teams'], Team.fromJson),
      (t) => PhotoSync.stripPhotos(t.toJson()));
  addAll(
      EntityKind.tournaments,
      _decodeBlobList(data['tournaments'], Tournament.fromJson),
      (t) => t.toJson());
  addAll(EntityKind.matches, _decodeBlobList(data['matches'], Match.fromJson),
      (m) => m.toJson());
  addAll(
      EntityKind.regPlayers,
      _decodeBlobList(data['regPlayers'], RegPlayer.fromJson),
      (r) => PhotoSync.stripPhotos(r.toJson()));
  addAll(EntityKind.drafts, _decodeBlobList(data['drafts'], Draft.fromJson),
      (d) => d.toJson());
  addAll(
      EntityKind.manualStats,
      _decodeBlobList(data['manualStats'], ManualStatEntry.fromJson),
      (e) => e.toJson());

  // The profile is a singleton: the blob carries '' when there is
  // none, and a corrupt value simply contributes no record (the
  // legacy pull keeps the local profile in that case too).
  final rawProfile = data['profile'];
  if (rawProfile is String && rawProfile.isNotEmpty) {
    try {
      final profile =
          AccountProfile.fromJson(jsonDecode(rawProfile) as Map<String, dynamic>);
      set[EntityKind.profile]![FirestoreEntityDocStore.profileDocId] =
          StampedRecord(profile.toJson(), stamp: updatedAt);
    } catch (_) {
      // Corrupt profile field: no record, exactly as the legacy
      // decoder treats it.
    }
  }

  // Seeded tombstones (plan §6 step 5): deletions recorded in the
  // blob's additive tombstone field become tombstone records.
  final rawTombs = data['tombstones'];
  if (rawTombs is String && rawTombs.isNotEmpty) {
    try {
      final list = jsonDecode(rawTombs) as List;
      for (final e in list) {
        final t = Tombstone.fromJson(e as Map<String, dynamic>);
        if (t.kind.isEmpty || t.id.isEmpty) continue;
        set[EntityKind.tombstones]![t.docId] = tombstoneToRecord(t);
      }
    } catch (_) {
      // Corrupt tombstone field: no seeded tombstones.
    }
  }

  return BlobSnapshot(set, updatedAt);
}

/// Where the legacy backup document comes from. Implementations
/// return null when the account has no blob document at all.
abstract class BlobSource {
  Future<BlobSnapshot?> read();
}

/// In-memory [BlobSource] (tests).
class InMemoryBlobSource implements BlobSource {
  BlobSnapshot? snapshot;
  InMemoryBlobSource(this.snapshot);

  @override
  Future<BlobSnapshot?> read() async => snapshot;
}

/// Production [BlobSource]: the legacy backup document, read
/// exactly as the legacy pull reads it — and only ever READ. The
/// new engine never writes or deletes the blob (plan §6).
class FirestoreBlobSource implements BlobSource {
  final FirebaseFirestore firestore;
  final String uid;
  FirestoreBlobSource(this.firestore, this.uid);

  @override
  Future<BlobSnapshot?> read() async {
    final snap = await firestore
        .collection('users')
        .doc(uid)
        .collection('backup')
        .doc('app_data')
        .get();
    if (!snap.exists) return null;
    final data = snap.data();
    if (data == null) return null;
    return entitySetFromBlobData(data);
  }
}

// ---------------------------------------------------------------------
// The local side: the app Store as an EntityDocStore.
// ---------------------------------------------------------------------

class _StampEntry {
  int hash;
  int stamp;
  _StampEntry(this.hash, this.stamp);

  Map<String, dynamic> toJson() => {'h': hash, 's': stamp};

  factory _StampEntry.fromJson(Map<String, dynamic> j) => _StampEntry(
      (j['h'] as num?)?.toInt() ?? 0, (j['s'] as num?)?.toInt() ?? 0);
}

/// FNV-1a (64-bit) over the encoded payload — change detection
/// only. A collision would merely skip a stamp bump; content
/// richness outranks stamps in the match merge, so correctness
/// never rests on this hash.
int _hashPayload(String s) {
  var h = 0xcbf29ce484222325;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
  }
  return h;
}

/// Adapts the app [Store] to [EntityDocStore] (Sync Fix "D",
/// Phase C1). readAll snapshots the store's lists as stamped
/// records — payloads byte-identical to what the blob carried
/// (photos stripped for teams/regPlayers; photos themselves keep
/// travelling via PhotoSync) — and applyDiff writes a converged
/// diff back into the lists, in place where a record already
/// exists so list order is stable (the legacy merge's behaviour).
///
/// The adapter never persists: SyncService owns the persist (and
/// the photo refill) after a round that changed the local side,
/// exactly as the legacy _applyRemote did.
class StoreEntityDocStore implements EntityDocStore {
  final Store store;
  final int Function() _nowMs;

  final Map<String, _StampEntry> _stamps = {};
  final Map<String, Map<String, _StampEntry>> _playerStamps = {};
  bool _stateLoaded = false;
  bool _stateDirty = false;

  StoreEntityDocStore(this.store, {int Function()? nowMs})
      : _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  String get _prefsKey => 'score60_entity_sync_v1__${store.identityId}';

  Future<void> _loadState() async {
    if (_stateLoaded) return;
    _stateLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final stamps = decoded['stamps'] as Map? ?? const {};
      stamps.forEach((k, v) {
        _stamps['$k'] =
            _StampEntry.fromJson((v as Map).cast<String, dynamic>());
      });
      final players = decoded['playerStamps'] as Map? ?? const {};
      players.forEach((teamId, perPlayer) {
        _playerStamps['$teamId'] = {
          for (final e in (perPlayer as Map).entries)
            '${e.key}':
                _StampEntry.fromJson((e.value as Map).cast<String, dynamic>()),
        };
      });
    } catch (_) {
      // Corrupt stamp state: start fresh. Every record re-stamps
      // at the current time once — harmless, stamps are advisory.
      _stamps.clear();
      _playerStamps.clear();
    }
  }

  Future<void> _saveState() async {
    if (!_stateDirty) return;
    _stateDirty = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        jsonEncode({
          'stamps': {
            for (final e in _stamps.entries) e.key: e.value.toJson(),
          },
          'playerStamps': {
            for (final t in _playerStamps.entries)
              t.key: {
                for (final p in t.value.entries) p.key: p.value.toJson(),
              },
          },
        }),
      );
    } catch (_) {
      // Losing stamp state is safe (see _loadState); never let it
      // fail a sync round.
    }
  }

  /// The stamp for one record whose payload is [payload]: the
  /// persisted stamp while the content is unchanged; a fresh
  /// monotonic stamp — max(now, previous + 1) — when it changed
  /// (plan §3.4). [floor] forces the result above a value (a
  /// re-added record must out-stamp its own tombstone, or the
  /// admin-restore survival rule would kill it again).
  int _stampFor(String kind, String id, Map<String, dynamic> payload,
      {int? floor}) {
    final key = '$kind|$id';
    final hash = _hashPayload(jsonEncode(payload));
    final prev = _stamps[key];
    int stamp;
    if (prev == null) {
      stamp = _nowMs();
    } else if (prev.hash != hash) {
      final now = _nowMs();
      stamp = now > prev.stamp ? now : prev.stamp + 1;
    } else {
      stamp = prev.stamp;
    }
    if (floor != null && stamp <= floor) stamp = floor + 1;
    if (prev == null || prev.hash != hash || prev.stamp != stamp) {
      _stamps[key] = _StampEntry(hash, stamp);
      _stateDirty = true;
    }
    return stamp;
  }

  /// Per-player stamps for one team's (already photo-stripped)
  /// payload, maintained the same way as [_stampFor].
  Map<String, int> _playerStampsFor(
      String teamId, Map<String, dynamic> payload, int teamStamp) {
    final state = _playerStamps[teamId] ??= <String, _StampEntry>{};
    final out = <String, int>{};
    final players = payload['players'];
    final seen = <String>{};
    if (players is List) {
      for (final p in players) {
        if (p is! Map) continue;
        final pid = p['id'] as String?;
        if (pid == null || pid.isEmpty) continue;
        seen.add(pid);
        final hash = _hashPayload(jsonEncode(p));
        final prev = state[pid];
        var stamp = prev?.stamp ?? teamStamp;
        if (prev == null) {
          stamp = teamStamp;
        } else if (prev.hash != hash) {
          final now = _nowMs();
          stamp = now > prev.stamp ? now : prev.stamp + 1;
        }
        if (prev == null || prev.hash != hash || prev.stamp != stamp) {
          state[pid] = _StampEntry(hash, stamp);
          _stateDirty = true;
        }
        out[pid] = stamp;
      }
    }
    // Players no longer on the team lose their stamp entries (the
    // union merge may still keep the player record itself from the
    // other side — plan §3.2's scope note).
    final removed = state.keys.where((id) => !seen.contains(id)).toList();
    if (removed.isNotEmpty) {
      for (final id in removed) {
        state.remove(id);
      }
      _stateDirty = true;
    }
    return out;
  }

  Tombstone? _tombstoneFor(String kind, String id) {
    for (final t in store.tombstones) {
      if (t.kind == kind && t.id == id) return t;
    }
    return null;
  }

  @override
  Future<EntitySet> readAll() async {
    await _loadState();
    final set = emptyEntitySet();

    // The floor a record's stamp must beat: its local tombstone's
    // deletedAt, or — after an explicit restore has cleared that
    // tombstone locally — the Store's restored marker remembering
    // the deletedAt (the cloud may still hold the tombstone, and
    // the record must arrive flagged `restored` with a stamp above
    // it or the merge/gate will kill the restore; Feature 1
    // follow-up).
    int? restoreFloor(String kind, String id, Tombstone? tomb) {
      var floor = tomb?.deletedAt;
      final marker = store.restoredMarkerFor(kind, id);
      if (marker != null && (floor == null || marker > floor)) {
        floor = marker;
      }
      return floor;
    }

    void add(String kind, String id, Map<String, dynamic> payload,
        {Map<String, int>? playerStamps}) {
      // A record that exists locally ALONGSIDE its own tombstone
      // can only be there because it was explicitly re-added
      // after the delete (Store upserts clear the tombstone, pulls
      // filter tombstoned records out) — that is the admin-restore
      // shape, and the record's stamp must out-rank the deletion
      // for the restore to survive the merge.
      final tomb = _tombstoneFor(kind, id);
      final stamp =
          _stampFor(kind, id, payload, floor: restoreFloor(kind, id, tomb));
      set[kind]![id] = StampedRecord(
        payload,
        stamp: stamp,
        restored: tomb != null || store.restoredMarkerFor(kind, id) != null,
        playerStamps: playerStamps,
      );
    }

    for (final t in store.teams) {
      final payload = PhotoSync.stripPhotos(t.toJson());
      // The team stamp is computed first: fresh players inherit it.
      final tomb = _tombstoneFor(EntityKind.teams, t.id);
      final teamStamp = _stampFor(EntityKind.teams, t.id, payload,
          floor: restoreFloor(EntityKind.teams, t.id, tomb));
      set[EntityKind.teams]![t.id] = StampedRecord(
        payload,
        stamp: teamStamp,
        restored: tomb != null ||
            store.restoredMarkerFor(EntityKind.teams, t.id) != null,
        playerStamps: _playerStampsFor(t.id, payload, teamStamp),
      );
    }
    for (final t in store.tournaments) {
      add(EntityKind.tournaments, t.id, t.toJson());
    }
    for (final m in store.matches) {
      add(EntityKind.matches, m.id, m.toJson());
    }
    for (final r in store.regPlayers) {
      add(EntityKind.regPlayers, r.id, PhotoSync.stripPhotos(r.toJson()));
    }
    for (final d in store.drafts) {
      add(EntityKind.drafts, d.id, d.toJson());
    }
    for (final e in store.manualStats) {
      add(EntityKind.manualStats, e.id, e.toJson());
    }
    final profile = store.profile;
    if (profile != null) {
      add(EntityKind.profile, FirestoreEntityDocStore.profileDocId,
          profile.toJson());
    }
    for (final t in store.tombstones) {
      set[EntityKind.tombstones]![t.docId] = tombstoneToRecord(t);
    }

    await _saveState();
    return set;
  }

  /// Adopts a merged record's stamp into the local stamp state,
  /// so the next readAll reports the same stamp instead of
  /// re-bumping (which would make every round look like a change).
  void _adoptStamp(String kind, String id, StampedRecord r) {
    _stamps['$kind|$id'] =
        _StampEntry(_hashPayload(jsonEncode(r.json)), r.stamp);
    if (kind == EntityKind.teams) {
      final players = r.json['players'];
      final perPlayer = <String, _StampEntry>{};
      if (players is List) {
        for (final p in players) {
          if (p is! Map) continue;
          final pid = p['id'] as String?;
          if (pid == null) continue;
          perPlayer[pid] = _StampEntry(
              _hashPayload(jsonEncode(p)), r.playerStamps[pid] ?? r.stamp);
        }
      }
      _playerStamps[id] = perPlayer;
    }
    _stateDirty = true;
  }

  /// Refills photoBase64 on an incoming record from the photos
  /// this device already holds, so applying a (photo-stripped)
  /// merged record never blanks a photo locally. PhotoSync's pull
  /// remains the authoritative refill after a round; this keeps
  /// the adapter safe when used on its own.
  Map<String, dynamic> _refillTeamPhotos(Map<String, dynamic> json) {
    final local = store.teamById(json['id'] as String? ?? '');
    if (local == null) return json;
    final photos = <String, String>{
      for (final p in local.players)
        if (p.photoBase64.isNotEmpty) p.id: p.photoBase64,
    };
    if (photos.isEmpty) return json;
    final copy = jsonDecode(jsonEncode(json)) as Map<String, dynamic>;
    final players = copy['players'];
    if (players is List) {
      for (final p in players) {
        if (p is Map &&
            (p['photoBase64'] as String? ?? '').isEmpty &&
            photos.containsKey(p['id'])) {
          p['photoBase64'] = photos[p['id']];
        }
      }
    }
    return copy;
  }

  Map<String, dynamic> _refillRegPhoto(Map<String, dynamic> json) {
    if ((json['photoBase64'] as String? ?? '').isNotEmpty) return json;
    final local = store.regById(json['id'] as String? ?? '');
    if (local == null || local.photoBase64.isEmpty) return json;
    return {...json, 'photoBase64': local.photoBase64};
  }

  @override
  Future<void> applyDiff(EntityDiff diff) async {
    await _loadState();

    void upsert<T>(
      String kind,
      List<T> list,
      T Function(Map<String, dynamic>) fromJson,
      String Function(T) idOf, {
      Map<String, dynamic> Function(Map<String, dynamic>)? prepare,
    }) {
      final records = diff.upserts[kind];
      if (records == null) return;
      for (final e in records.entries) {
        var json = e.value.json;
        if (prepare != null) json = prepare(json);
        final item = fromJson(json);
        final i = list.indexWhere((x) => idOf(x) == e.key);
        if (i >= 0) {
          list[i] = item;
        } else {
          list.add(item);
        }
        _adoptStamp(kind, e.key, e.value);
      }
    }

    void remove<T>(String kind, List<T> list, String Function(T) idOf) {
      final ids = diff.deletes[kind];
      if (ids == null || ids.isEmpty) return;
      list.removeWhere((x) => ids.contains(idOf(x)));
      for (final id in ids) {
        _stamps.remove('$kind|$id');
        if (kind == EntityKind.teams) _playerStamps.remove(id);
      }
      _stateDirty = true;
    }

    upsert<Team>(EntityKind.teams, store.teams, Team.fromJson, (t) => t.id,
        prepare: _refillTeamPhotos);
    remove<Team>(EntityKind.teams, store.teams, (t) => t.id);
    upsert<Tournament>(EntityKind.tournaments, store.tournaments,
        Tournament.fromJson, (t) => t.id);
    remove<Tournament>(
        EntityKind.tournaments, store.tournaments, (t) => t.id);
    upsert<Match>(EntityKind.matches, store.matches, Match.fromJson,
        (m) => m.id);
    remove<Match>(EntityKind.matches, store.matches, (m) => m.id);
    upsert<RegPlayer>(EntityKind.regPlayers, store.regPlayers,
        RegPlayer.fromJson, (r) => r.id,
        prepare: _refillRegPhoto);
    remove<RegPlayer>(EntityKind.regPlayers, store.regPlayers, (r) => r.id);
    upsert<Draft>(
        EntityKind.drafts, store.drafts, Draft.fromJson, (d) => d.id);
    remove<Draft>(EntityKind.drafts, store.drafts, (d) => d.id);
    upsert<ManualStatEntry>(EntityKind.manualStats, store.manualStats,
        ManualStatEntry.fromJson, (e) => e.id);
    remove<ManualStatEntry>(
        EntityKind.manualStats, store.manualStats, (e) => e.id);

    // Profile singleton.
    final profileUpserts = diff.upserts[EntityKind.profile];
    if (profileUpserts != null) {
      for (final e in profileUpserts.entries) {
        store.profile = AccountProfile.fromJson(e.value.json);
        _adoptStamp(EntityKind.profile, e.key, e.value);
      }
    }
    if ((diff.deletes[EntityKind.profile] ?? const <String>{}).isNotEmpty) {
      store.profile = null;
      _stamps.remove(
          '${EntityKind.profile}|${FirestoreEntityDocStore.profileDocId}');
      _stateDirty = true;
    }

    // Tombstones: upserts union into the store's set (newest
    // deletion wins, the Store.absorbTombstones rule); deletes —
    // a tombstone spent by an explicit restore — remove it.
    final tombUpserts = diff.upserts[EntityKind.tombstones];
    if (tombUpserts != null) {
      for (final e in tombUpserts.entries) {
        final t = Tombstone.fromJson(e.value.json);
        if (t.kind.isEmpty || t.id.isEmpty) continue;
        final i = store.tombstones
            .indexWhere((x) => x.kind == t.kind && x.id == t.id);
        if (i < 0) {
          store.tombstones.add(t);
        } else if (t.deletedAt > store.tombstones[i].deletedAt) {
          store.tombstones[i] = t;
        }
        _adoptStamp(EntityKind.tombstones, e.key, e.value);
      }
    }
    final tombDeletes = diff.deletes[EntityKind.tombstones];
    if (tombDeletes != null) {
      for (final docId in tombDeletes) {
        final sep = docId.indexOf('__');
        if (sep <= 0) continue;
        final kind = docId.substring(0, sep);
        final id = docId.substring(sep + 2);
        store.tombstones.removeWhere((x) => x.kind == kind && x.id == id);
        _stamps.remove('${EntityKind.tombstones}|$docId');
        // The tombstone is spent: a restored record no longer needs
        // its marker (Feature 1 follow-up).
        store.clearRestoredMarker(kind, id);
      }
      _stateDirty = true;
    }

    await _saveState();
  }
}

// ---------------------------------------------------------------------
// The coordinator: sync rounds + the migration runner.
// ---------------------------------------------------------------------

/// The outcome of one [EntitySyncCoordinator.syncRound].
class SyncRoundResult {
  /// The local side changed (SyncService persists + refills
  /// photos when this is true — the legacy "applied").
  final bool localChanged;

  /// The cloud entity collections changed (a delta push landed).
  final bool cloudChanged;

  /// A remote existed at all: a blob document, or any entity /
  /// tombstone document (the push guard's "docSeen").
  final bool remoteSeen;

  /// The remote held actual entity records (the push guard's
  /// remoteNonEmpty).
  final bool remoteNonEmpty;

  /// The converged set both sides now hold.
  final EntitySet merged;

  const SyncRoundResult({
    required this.localChanged,
    required this.cloudChanged,
    required this.remoteSeen,
    required this.remoteNonEmpty,
    required this.merged,
  });
}

/// The outcome of [EntitySyncCoordinator.runMigrationIfNeeded].
class MigrationResult {
  /// A migration round actually ran (false when already done or
  /// when there was nothing to migrate).
  final bool ran;

  /// Verification passed. When false the legacy blob remains the
  /// fallback of record and the migration retries on a later run.
  final bool ok;

  /// Per-kind record counts of the converged entity set.
  final Map<String, int> counts;

  final String detail;

  const MigrationResult({
    required this.ran,
    required this.ok,
    required this.counts,
    required this.detail,
  });
}

class EntitySyncCoordinator {
  final EntityDocStore local;
  final EntityDocStore cloud;
  final BlobSource? blobSource;
  final Future<bool> Function()? migrationDone;
  final Future<void> Function()? markMigrationDone;

  EntitySyncCoordinator({
    required this.local,
    required this.cloud,
    this.blobSource,
    this.migrationDone,
    this.markMigrationDone,
  });

  static bool _setHasRecords(EntitySet set) =>
      EntityKind.all.any((k) => (set[k] ?? const {}).isNotEmpty);

  static bool _setHasAnything(EntitySet set) =>
      _setHasRecords(set) ||
      (set[EntityKind.tombstones] ?? const {}).isNotEmpty;

  static Map<String, int> countsOf(EntitySet set) => {
        for (final k in [...EntityKind.all, EntityKind.tombstones])
          k: (set[k] ?? const {}).length,
      };

  /// One full sync round: read local + remote (dual-read — the
  /// entity collections UNIONED with the legacy blob when one
  /// exists; the blob only ever contributes through the merge, it
  /// can never overwrite the entity set directly: the entity
  /// collections are the system of record, and the converged
  /// result is what gets written back to them), merge,
  /// and write the converged set back to BOTH sides as delta
  /// diffs only — the records that actually changed, never the
  /// whole dataset (plan §7, Phase C1).
  Future<SyncRoundResult> syncRound() async {
    final localSet = await local.readAll();
    final cloudSet = await cloud.readAll();
    var remote = cloudSet;
    var remoteSeen = _setHasAnything(cloudSet);
    final source = blobSource;
    if (source != null) {
      final blob = await source.read();
      if (blob != null) {
        remoteSeen = true;
        remote = mergeEntitySets(cloudSet, blob.entities);
      }
    }
    final merged = mergeEntitySets(localSet, remote);
    final localDiff = diffEntitySets(localSet, merged);
    final cloudDiff = diffEntitySets(cloudSet, merged);
    if (!localDiff.isEmpty) await local.applyDiff(localDiff);
    if (!cloudDiff.isEmpty) await cloud.applyDiff(cloudDiff);
    // Restored-marker reconciliation (Feature 1 follow-up): once a
    // round has converged and the merged set no longer holds a
    // tombstone for a restored record, its marker has done its job
    // (the tombstone was spent, or the record itself is gone) —
    // clear it so later rounds stop flagging the record as a
    // restore. The local applyDiff path cannot see this moment:
    // the local tombstone was already cleared at restore time, so
    // no tombstone-delete ever appears in the local diff.
    final localAdapter = local;
    if (localAdapter is StoreEntityDocStore) {
      final mergedTombs = tombstonesOf(merged);
      for (final (kind, id) in localAdapter.store.restoredMarkerRecords) {
        if (tombstoneFor(mergedTombs, kind, id) == null) {
          localAdapter.store.clearRestoredMarker(kind, id);
        }
      }
    }
    return SyncRoundResult(
      localChanged: !localDiff.isEmpty,
      cloudChanged: !cloudDiff.isEmpty,
      remoteSeen: remoteSeen,
      remoteNonEmpty: _setHasRecords(remote),
      merged: merged,
    );
  }

  /// The migration runner (plan §6). On the first run under the
  /// new engine, the current blob dataset is converted into
  /// per-entity documents. The conversion is itself a sync round
  /// between the blob and whatever entity documents already exist
  /// (another device may have migrated first), so running it twice
  /// — or on two devices — converges to the same state instead of
  /// duplicating: the second run's diff is empty.
  ///
  /// Verification, before the migration is allowed to call itself
  /// done: per-kind record counts of the re-read cloud set equal
  /// the converged set's, and spot figures (the richest completed
  /// match's innings totals/FoW; the largest team's player count)
  /// match the source exactly. A failure leaves the flag unset —
  /// dual-read keeps the untouched blob as the fallback.
  ///
  /// The legacy blob is never written or deleted here.
  Future<MigrationResult> runMigrationIfNeeded() async {
    if (migrationDone != null && await migrationDone!()) {
      return const MigrationResult(
          ran: false, ok: true, counts: {}, detail: 'already migrated');
    }
    final source = blobSource;
    if (source == null) {
      await markMigrationDone?.call();
      return const MigrationResult(
          ran: false, ok: true, counts: {}, detail: 'no blob source');
    }
    final blob = await source.read();
    if (blob == null) {
      // No legacy document: nothing to convert. Whatever entity
      // documents exist are already the system of record.
      await markMigrationDone?.call();
      return const MigrationResult(
          ran: false, ok: true, counts: {}, detail: 'no legacy blob');
    }
    final cloudSet = await cloud.readAll();
    final expected = mergeEntitySets(blob.entities, cloudSet);
    final diff = diffEntitySets(cloudSet, expected);
    if (!diff.isEmpty) await cloud.applyDiff(diff);
    final after = await cloud.readAll();
    final verdict = verifyMigration(expected: expected, actual: after);
    if (!verdict.ok) {
      return MigrationResult(
        ran: true,
        ok: false,
        counts: countsOf(after),
        detail: verdict.detail,
      );
    }
    await markMigrationDone?.call();
    return MigrationResult(
      ran: true,
      ok: true,
      counts: countsOf(expected),
      detail: 'verified: ${verdict.detail}',
    );
  }

  /// The migration's verification (plan §6 step 4), pure so it is
  /// directly unit-testable: per-kind counts equal, plus spot
  /// figures — the richest completed match (most legal balls,
  /// falling back to any match) must carry identical innings
  /// totals and FoW count, and the largest team an identical
  /// player count.
  static ({bool ok, String detail}) verifyMigration({
    required EntitySet expected,
    required EntitySet actual,
  }) {
    for (final kind in [...EntityKind.all, EntityKind.tombstones]) {
      final e = (expected[kind] ?? const {}).length;
      final a = (actual[kind] ?? const {}).length;
      if (e != a) {
        return (ok: false, detail: 'count mismatch in $kind: $e != $a');
      }
      for (final id in (expected[kind] ?? const {}).keys) {
        if (!(actual[kind] ?? const {}).containsKey(id)) {
          return (ok: false, detail: 'missing $kind/$id after migration');
        }
      }
    }

    // Spot figure 1: the richest match's innings.
    final matches = (expected[EntityKind.matches] ?? const {}).values;
    if (matches.isNotEmpty) {
      StampedRecord? richest;
      Match? richestMatch;
      for (final r in matches) {
        final m = Match.fromJson(r.json);
        if (richestMatch == null ||
            matchLegalBalls(m) > matchLegalBalls(richestMatch)) {
          richest = r;
          richestMatch = m;
        }
      }
      final actualRec = actual[EntityKind.matches]![richest!.id];
      if (actualRec == null) {
        return (ok: false, detail: 'spot match ${richest.id} missing');
      }
      final am = Match.fromJson(actualRec.json);
      final em = richestMatch!;
      if (am.innings.length != em.innings.length) {
        return (
          ok: false,
          detail: 'spot match ${em.id}: innings count differs'
        );
      }
      for (var i = 0; i < em.innings.length; i++) {
        final ei = em.innings[i];
        final ai = am.innings[i];
        if (ai.totalRuns != ei.totalRuns ||
            ai.wickets != ei.wickets ||
            ai.legalBalls != ei.legalBalls ||
            ai.fallOfWickets.length != ei.fallOfWickets.length) {
          return (
            ok: false,
            detail: 'spot match ${em.id}: innings ${i + 1} figures differ'
          );
        }
      }
    }

    // Spot figure 2: the largest team's player count.
    final teams = (expected[EntityKind.teams] ?? const {}).values;
    if (teams.isNotEmpty) {
      StampedRecord? largest;
      Team? largestTeam;
      for (final r in teams) {
        final t = Team.fromJson(r.json);
        if (largestTeam == null || t.players.length > largestTeam.players.length) {
          largest = r;
          largestTeam = t;
        }
      }
      final actualRec = actual[EntityKind.teams]![largest!.id];
      if (actualRec == null) {
        return (ok: false, detail: 'spot team ${largest.id} missing');
      }
      final at = Team.fromJson(actualRec.json);
      if (at.players.length != largestTeam!.players.length) {
        return (
          ok: false,
          detail:
              'spot team ${largestTeam.id}: player count ${at.players.length} != ${largestTeam.players.length}'
        );
      }
    }

    return (ok: true, detail: 'counts + spot figures match');
  }
}
