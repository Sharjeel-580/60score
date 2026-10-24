// Firestore adapter for the per-entity sync engine (Sync Fix "D")
// — see ~/workspace/60score-app/SYNC_FIX_D_PLAN.md and
// lib/entity_sync.dart for the pure merge/gate rules this adapter
// transports.
//
// STATUS: Phase C1 wired this store into SyncService behind its
// existing public API (dual-read, delta pushes, migration).
// Phase D prep (this pass): [applyDiff] now routes match and team
// upserts through the gated transactions ([writeMatchGated] /
// [writeTeamGated]) instead of the plain batch, so a downgrade
// cannot land even if a diff was computed against a stale read.
// The matching security rules are written and approved
// (~/workspace/60score-app/FIRESTORE_RULES_PHASE_D.rules) but NOT
// yet published — until they are, the entity collections are
// unreadable in production, every call here throws, and
// SyncService falls back to the legacy blob path exactly as C1
// designed. Sync is never worse than v1.3.8.
//
// Layout (mirrors the existing photos subcollection):
//   users/{uid}/matches/{matchId}
//   users/{uid}/teams/{teamId}
//   users/{uid}/tournaments/{tournamentId}
//   users/{uid}/regPlayers/{playerId}
//   users/{uid}/drafts/{draftId}
//   users/{uid}/manualStats/{entryId}
//   users/{uid}/meta/profile            (singleton)
//   users/{uid}/tombstones/{kind}__{id}
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'entity_sync.dart';
import 'models.dart';

class FirestoreEntityDocStore implements EntityDocStore {
  final FirebaseFirestore firestore;
  final String uid;

  FirestoreEntityDocStore({required this.firestore, required this.uid});

  /// The collection holding one [kind]. The profile is a singleton
  /// and lives under meta/ to keep the top level entity-shaped.
  CollectionReference<Map<String, dynamic>> _collection(String kind) {
    final user = firestore.collection('users').doc(uid);
    if (kind == EntityKind.profile) return user.collection('meta');
    return user.collection(kind);
  }

  static const String profileDocId = 'profile';

  String _docId(String kind, String id) =>
      kind == EntityKind.profile ? profileDocId : id;

  // ---------------- Document codec ----------------
  // Pure and static so the encoding is unit-testable without a
  // Firestore instance. The payload is the entity's JSON string —
  // byte-identical to the fields the legacy blob carries — while
  // stamps and (for matches) the structured guard fields sit
  // OUTSIDE the string, where transactions and security rules can
  // read them.

  static Map<String, dynamic> docFieldsFor(
      String kind, String id, StampedRecord r) {
    final fields = <String, dynamic>{
      'payload': jsonEncode(r.json),
      'entityUpdatedAt': r.stamp,
      'restored': r.restored,
    };
    if (kind == EntityKind.teams && r.playerStamps.isNotEmpty) {
      fields['playerStamps'] = r.playerStamps;
    }
    if (kind == EntityKind.matches) {
      final m = Match.fromJson(r.json);
      fields['status'] = m.status;
      fields['fowCount'] = matchFowCount(m);
      fields['legalBalls'] = matchLegalBalls(m);
      fields['eventCount'] = matchBallEvents(m);
    }
    return fields;
  }

  static StampedRecord recordFromDoc(Map<String, dynamic> data) {
    final raw = data['payload'];
    final json = raw is String && raw.isNotEmpty
        ? (jsonDecode(raw) as Map).cast<String, dynamic>()
        : <String, dynamic>{};
    return StampedRecord(
      json,
      stamp: (data['entityUpdatedAt'] as num?)?.toInt() ?? 0,
      restored: data['restored'] as bool? ?? false,
      playerStamps: ((data['playerStamps'] as Map?) ?? const {})
          .map((k, v) => MapEntry('$k', (v as num).toInt())),
    );
  }

  // ---------------- EntityDocStore ----------------

  @override
  Future<EntitySet> readAll() async {
    final out = emptyEntitySet();
    for (final kind in [...EntityKind.all, EntityKind.tombstones]) {
      final snap = await _collection(kind).get();
      for (final doc in snap.docs) {
        final record = recordFromDoc(doc.data());
        // Tombstone records are keyed by docId in the entity set;
        // entity records by their own id (== doc id, except the
        // profile singleton whose json may predate the field).
        final key = kind == EntityKind.tombstones
            ? doc.id
            : (kind == EntityKind.profile ? profileDocId : doc.id);
        out[kind]![key] = record;
      }
    }
    return out;
  }

  @override
  Future<void> applyDiff(EntityDiff diff) async {
    // Phase D: match and team upserts go through the GATED
    // transactions FIRST, one document at a time — the gate
    // re-reads the stored doc inside the transaction, so a diff
    // computed against a read that has since been overtaken
    // cannot downgrade the cloud. If a gated write throws (e.g.
    // the Phase D rules are not published yet and the collection
    // is unreadable), nothing else in this diff has been written
    // and the caller falls back to the legacy blob path.
    for (final kind in const [EntityKind.matches, EntityKind.teams]) {
      final upserts = diff.upserts[kind];
      if (upserts == null) continue;
      for (final r in upserts.entries) {
        if (kind == EntityKind.matches) {
          await writeMatchGated(r.key, r.value);
        } else {
          await writeTeamGated(r.key, r.value);
        }
      }
    }

    // Everything else — the remaining kinds' upserts, tombstone
    // upserts, and ALL deletes (a delete in a converged diff is a
    // tombstone kill or a spent restore, never a data decision) —
    // keeps the batched path. At this app's scale (a handful of
    // changed docs per sync round) the 500-write batch limit is
    // never approached; the migration round is the only bulk
    // case, so the batch is flushed and recreated every 450 ops
    // (a committed batch cannot be reused).
    var batch = firestore.batch();
    var ops = 0;
    Future<void> flush() async {
      if (ops == 0) return;
      final b = batch;
      batch = firestore.batch();
      ops = 0;
      await b.commit();
    }

    for (final e in diff.upserts.entries) {
      if (e.key == EntityKind.matches || e.key == EntityKind.teams) {
        continue; // handled by the gated transactions above
      }
      for (final r in e.value.entries) {
        batch.set(
          _collection(e.key).doc(_docId(e.key, r.key)),
          docFieldsFor(e.key, r.key, r.value),
        );
        ops++;
        if (ops >= 450) await flush();
      }
    }
    for (final e in diff.deletes.entries) {
      for (final id in e.value) {
        batch.delete(_collection(e.key).doc(_docId(e.key, id)));
        ops++;
        if (ops >= 450) await flush();
      }
    }
    await flush();
  }

  // ---------------- Phase D: gated writes ----------------

  /// The transactional gated write for one match (Phase D). Reads
  /// the stored doc and its tombstone inside a transaction and
  /// applies [planGatedUpsert] — the same write policy the tests
  /// exercise against the in-memory gated store:
  /// - gate accepts → the incoming record is written;
  /// - downgrade / stale-stamp → the incoming copy is re-merged
  ///   with the stored one INSIDE the transaction and the
  ///   converged record is written instead (the harness's dSync
  ///   re-read → re-merge → retry-once, made atomic); when the
  ///   stored copy already is the converged winner, nothing is
  ///   written and the verdict is accept — the richer copy
  ///   surviving untouched is the gate working, not a failure;
  /// - tombstoned → nothing is written, verdict rejectTombstoned.
  /// An accepted explicit restore spends its tombstone in the
  /// same transaction. Even a legacy client code path routed
  /// through here cannot downgrade a richer stored copy, whatever
  /// stamp it claims.
  Future<GateVerdict> writeMatchGated(String id, StampedRecord incoming) =>
      _writeGated(EntityKind.matches, id, incoming);

  /// The transactional gated write for one team (Phase D), running
  /// the same [planGatedUpsert] policy with [gateTeamWrite].
  Future<GateVerdict> writeTeamGated(String id, StampedRecord incoming) =>
      _writeGated(EntityKind.teams, id, incoming);

  Future<GateVerdict> _writeGated(
      String kind, String id, StampedRecord incoming) async {
    final ref = _collection(kind).doc(id);
    final tombRef =
        _collection(EntityKind.tombstones).doc('${kind}__$id');
    return firestore.runTransaction<GateVerdict>((tx) async {
      final snap = await tx.get(ref);
      final tombSnap = await tx.get(tombRef);
      final stored = snap.exists ? recordFromDoc(snap.data()!) : null;
      final tombstone = tombSnap.exists
          ? Tombstone.fromJson(recordFromDoc(tombSnap.data()!).json)
          : null;
      final plan = planGatedUpsert(
          kind: kind,
          incoming: incoming,
          stored: stored,
          tombstone: tombstone);
      final write = plan.toWrite;
      if (write != null) {
        tx.set(ref, docFieldsFor(kind, id, write));
        // An accepted explicit restore spends its tombstone.
        if (plan.spendTombstone) tx.delete(tombRef);
        return GateVerdict.accept;
      }
      return plan.converged ? GateVerdict.accept : plan.verdict;
    });
  }
}
