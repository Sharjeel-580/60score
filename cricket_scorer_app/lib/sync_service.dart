// 60Score cloud sync engine — Firestore backup/sync per account.
// Offline-first: local SharedPreferences data is the source of truth.
// When logged in, the whole app state is mirrored to Firestore so a
// second device (same account) can pull it.
//
// Design (v1, simple + safe):
// - One Firestore document: users/{uid}/backup/app_data
// - Fields: teams, tournaments, matches, regPlayers, drafts, manualStats
//   (each a JSON string, same format as local), updatedAt (ms epoch),
//   device (device model for the "last synced from" note).
// - Player photos travel separately, one document per player in
//   users/{uid}/photos/{playerId} (see photo_sync.dart) — photoBase64
//   is stripped from the backup JSON so this document stays small.
// - Push: debounced 5s after any Store.persist(), only when logged in.
// - Pull: after login and on app start (if logged in). Last-write-wins
//   by timestamp — the newer side (local or cloud) wins, never merged.
// - All operations are fire-and-forget safe: failures are swallowed and
//   the app keeps working offline.
//
// Firestore console setup (one-time, by the app owner):
//   1. Firebase console > Build > Firestore Database > Create database
//      (production mode, any region).
//   2. Rules tab — paste:
//        rules_version = '2';
//        service cloud.firestore {
//          match /databases/{database}/documents {
//            match /users/{uid}/backup/{doc} {
//              allow read, write: if request.auth != null
//                  && request.auth.uid == uid;
//            }
//            match /users/{uid}/photos/{photoId} {
//              allow read, write: if request.auth != null
//                  && request.auth.uid == uid;
//            }
//          }
//        }
//   3. Publish.
import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'account_profile.dart';
import 'auth_service.dart';
import 'models.dart';
import 'photo_sync.dart';
import 'publish_service.dart';
import 'store.dart';

/// Push guard for ONE account activation (v1.3.2, bug #R1).
///
/// The race this closes: right after login the account's scope is
/// activated and local edits (or the profile ensure) schedule a
/// debounced push — if that push lands BEFORE the activation's first
/// pull has read the cloud backup, it overwrites the backup with
/// whatever the local scope happens to hold (on a fresh device: a
/// completely empty dataset), and the next pull then "restores" the
/// empty copy over the real data. So:
///
/// - No push for an identity may run until that identity's first
///   pull has settled (completed). Pushes requested earlier are
///   deferred and flushed once, when the pull settles — but only if
///   the flush itself is safe:
/// - An all-empty dataset is NEVER flushed over a remote backup in
///   an activation whose first pull imported nothing (the exact
///   shape of the #R1 data loss).
///
/// The guard tracks one uid at a time; a different uid (or an
/// explicit reset on identity switch) starts a fresh guarded window.
class SyncPushGuard {
  String? _uid;
  bool _pullSettled = false;
  bool _pullImported = false;
  bool _remoteDocSeen = false;
  bool _deferred = false;

  /// Whether [s] carries no user data at all.
  static bool datasetIsEmpty(Store s) =>
      s.tournaments.isEmpty && s.teams.isEmpty && s.matches.isEmpty;

  /// Starts a fresh guarded window (identity switches, log-out).
  void reset() {
    _uid = null;
    _pullSettled = false;
    _pullImported = false;
    _remoteDocSeen = false;
    _deferred = false;
  }

  void _track(String uid) {
    if (_uid != uid) {
      reset();
      _uid = uid;
    }
  }

  /// A push for [uid] may run only once this activation's first pull
  /// has settled.
  bool allowsPush(String uid) {
    _track(uid);
    return _pullSettled;
  }

  /// Records that a push for [uid] was requested while the gate was
  /// closed.
  void defer(String uid) {
    _track(uid);
    _deferred = true;
  }

  /// Whether an all-empty push must be suppressed right now: the
  /// dataset is empty, a remote backup exists, and this activation's
  /// first pull brought nothing in.
  bool emptyPushSuppressed(bool emptyDataset) =>
      emptyDataset && !_pullImported && _remoteDocSeen;

  /// Settles the guard with the first pull's outcome for [uid].
  /// Returns true when a deferred push should be flushed now.
  bool settle(
    String uid, {
    required bool imported,
    required bool docSeen,
    required bool emptyDataset,
  }) {
    _track(uid);
    _pullSettled = true;
    _pullImported = imported;
    _remoteDocSeen = docSeen;
    if (!_deferred) return false;
    _deferred = false;
    return !emptyPushSuppressed(emptyDataset);
  }
}

class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  Timer? _pushTimer;
  bool _applyingRemote = false;
  DateTime? _lastSyncAt;
  String? _lastError;

  /// First-pull push guard for the current activation (bug #R1).
  final SyncPushGuard _guard = SyncPushGuard();

  DateTime? get lastSyncAt => _lastSyncAt;
  String? get lastError => _lastError;

  /// After a pull applied remote data, published tournaments in the
  /// imported data must reach the public collection: the import
  /// persist runs with skipSync (which also skips the republish
  /// arming), so pull arms the re-publish itself (v1.3.2, bug #R1).
  static bool shouldArmRepublishAfterPull({
    required bool applied,
    required bool hasPublished,
  }) =>
      applied && hasPublished;

  static const _kDoc = 'app_data';

  DocumentReference<Map<String, dynamic>>? _docRef() {
    final auth = AuthService();
    if (!auth.firebaseReady || !auth.isLoggedIn) return null;
    final uid = auth.currentUser!.uid;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('backup')
        .doc(_kDoc);
  }

  CollectionReference<Map<String, dynamic>>? _photosRef() {
    final auth = AuthService();
    if (!auth.firebaseReady || !auth.isLoggedIn) return null;
    final uid = auth.currentUser!.uid;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('photos');
  }

  /// Called from Store.persist(). Debounced push — safe to call often.
  void schedulePush(Store store) {
    if (_applyingRemote) return;
    final ref = _docRef();
    if (ref == null) return;
    final uid = AuthService().currentUser!.uid;
    _pushTimer?.cancel();
    _pushTimer = Timer(const Duration(seconds: 5), () {
      // The identity may have changed while this timer was pending
      // (log-out, account switch): never write one identity's data
      // into another account's backup document.
      if (AuthService().currentUser?.uid != uid) return;
      if (store.identityId != uid) return;
      // Push guard (v1.3.2): until this activation's first pull has
      // settled, a push could overwrite the cloud backup with a
      // not-yet-pulled local scope. Defer — pull() flushes the push
      // when it settles.
      if (!_guard.allowsPush(uid)) {
        _guard.defer(uid);
        return;
      }
      _push(ref, store);
    });
  }

  /// Cancels a pending debounced push (identity switches, log-out).
  /// Also restarts the push guard: the next identity's first push
  /// waits for its own first pull.
  void cancelPending() {
    _pushTimer?.cancel();
    _pushTimer = null;
    _guard.reset();
  }

  Future<void> _push(
      DocumentReference<Map<String, dynamic>> ref, Store store) async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      await ref.set({
        // Photos are stripped here — they sync via the photos
        // subcollection (PhotoSync) so this document stays small.
        'teams': jsonEncode(store.teams
            .map((t) => PhotoSync.stripPhotos(t.toJson()))
            .toList()),
        'tournaments':
            jsonEncode(store.tournaments.map((t) => t.toJson()).toList()),
        'matches': jsonEncode(store.matches.map((m) => m.toJson()).toList()),
        'regPlayers': jsonEncode(store.regPlayers
            .map((r) => PhotoSync.stripPhotos(r.toJson()))
            .toList()),
        'drafts': jsonEncode(store.drafts.map((d) => d.toJson()).toList()),
        'manualStats':
            jsonEncode(store.manualStats.map((e) => e.toJson()).toList()),
        // The account profile rides in this same document (no new
        // Firestore path — rules already cover backup/*).
        'profile': store.profile == null
            ? ''
            : jsonEncode(store.profile!.toJson()),
        'updatedAt': now,
        'appVersion': '1.2.0',
      }, SetOptions(merge: true));
      await store.setLastModified(now);
      final photos = _photosRef();
      if (photos != null) await PhotoSync.pushPhotos(photos, store);
      _lastSyncAt = DateTime.now();
      _lastError = null;
    } catch (e) {
      _lastError = e.toString();
      debugPrint('Sync push failed: $e');
    }
  }

  /// Pull remote state into [store] when the cloud copy is newer.
  /// Returns true when remote data was applied.
  ///
  /// Every completed pull SETTLES the push guard for this activation
  /// (see [SyncPushGuard]): pushes deferred during the guarded
  /// window are flushed once, and when remote data was applied, a
  /// re-publish is armed so published tournaments restored by the
  /// pull actually reach the public collection (bug #R1). A pull
  /// that FAILS leaves the guard closed — pushes stay deferred until
  /// a pull completes (next app start or "Sync now").
  Future<bool> pull(Store store) async {
    final ref = _docRef();
    if (ref == null) return false;
    final uid = AuthService().currentUser!.uid;
    try {
      final snap = await ref.get();
      if (!snap.exists) {
        // First login on this account: push local state up as the
        // baseline — unless the local dataset is completely empty
        // (nothing worth backing up yet; the first real change will
        // push). The pull has completed either way.
        if (!SyncPushGuard.datasetIsEmpty(store)) {
          await _push(ref, store);
        }
        _settleAfterPull(store, uid, imported: false, docSeen: false);
        return false;
      }
      final data = snap.data()!;
      final remoteAt = (data['updatedAt'] as num?)?.toInt() ?? 0;
      final localAt = await store.getLastModified();
      if (remoteAt <= localAt) {
        // Main state is current, but photos may still be missing (e.g.
        // a photo upload succeeded after this device's last full pull).
        final photos = _photosRef();
        if (photos != null && await PhotoSync.pullPhotos(photos, store)) {
          await store.persist(skipSync: true);
          _lastSyncAt = DateTime.now();
        }
        _settleAfterPull(store, uid, imported: false, docSeen: true);
        return false;
      }

      _applyingRemote = true;
      try {
        store.teams =
            _decode(data['teams'], Team.fromJson) ?? store.teams;
        store.tournaments =
            _decode(data['tournaments'], Tournament.fromJson) ??
                store.tournaments;
        store.matches =
            _decode(data['matches'], Match.fromJson) ?? store.matches;
        store.regPlayers =
            _decode(data['regPlayers'], RegPlayer.fromJson) ??
                store.regPlayers;
        store.drafts =
            _decode(data['drafts'], Draft.fromJson) ?? store.drafts;
        store.manualStats =
            _decode(data['manualStats'], ManualStatEntry.fromJson) ??
                store.manualStats;
        store.profile =
            _decodeProfile(data['profile']) ?? store.profile;
        // The backup JSON carries no photos (stripped on push); fill
        // them in from the photos subcollection before persisting, so
        // one persist saves the complete state. Backups written by
        // older builds may still carry photos inline — those survive,
        // and any newer cloud photo below simply overwrites them.
        final photos = _photosRef();
        if (photos != null) await PhotoSync.pullPhotos(photos, store);
        await store.setLastModified(remoteAt);
        await store.persist(skipSync: true);
      } finally {
        _applyingRemote = false;
      }
      _lastSyncAt = DateTime.now();
      _lastError = null;
      _settleAfterPull(store, uid, imported: true, docSeen: true);
      return true;
    } catch (e) {
      _lastError = e.toString();
      debugPrint('Sync pull failed: $e');
      return false;
    }
  }

  /// Settles the push guard after a completed pull and runs the two
  /// follow-ups the pull owes: arm a re-publish when the imported
  /// data carries published tournaments, and flush a push that was
  /// deferred during the guarded window (the guard itself refuses
  /// the flush when it would send an all-empty dataset over a remote
  /// backup the pull did not import).
  void _settleAfterPull(
    Store store,
    String uid, {
    required bool imported,
    required bool docSeen,
  }) {
    final flush = _guard.settle(
      uid,
      imported: imported,
      docSeen: docSeen,
      emptyDataset: SyncPushGuard.datasetIsEmpty(store),
    );
    if (shouldArmRepublishAfterPull(
      applied: imported,
      hasPublished: PublishService.hasPublished(store),
    )) {
      PublishService().scheduleRepublish(store);
    }
    if (flush && store.identityId == uid) {
      final ref = _docRef();
      if (ref != null) _push(ref, store);
    }
  }

  AccountProfile? _decodeProfile(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    try {
      return AccountProfile.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  List<T>? _decode<T>(
      Object? raw, T Function(Map<String, dynamic>) fromJson) {
    if (raw is! String || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return null;
    }
  }
}
