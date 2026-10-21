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
//   Exception (v1.3.3): a completely empty side never wins — an empty
//   local scope always imports a non-empty backup (its "last modified"
//   clock is unreliable right after activation), and an empty backup
//   is never imported over local data (local is pushed up to heal it
//   instead). See SyncService.decidePull and SyncPushGuard.
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

/// Push guard for ONE account activation (v1.3.2, bug #R1;
/// empty-push rules completed in v1.3.3).
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
/// - An all-empty dataset is NEVER pushed over a non-empty remote
///   backup by an activation whose pull imported nothing and whose
///   local dataset was never non-empty — not just at settle time
///   (the v1.3.2 flush check) but on ANY push path, for the whole
///   activation (v1.3.3: the first ordinary persist after settle
///   used to slip an empty push past the guard and destroy the
///   backup the pull had just declined to import). An empty push
///   becomes permissible once the user actually had data in this
///   activation — imported it, or held/created it locally — because
///   deleting everything after that is an explicit user action,
///   not a fresh scope racing its first pull.
///
/// The guard tracks one uid at a time; a different uid (or an
/// explicit reset on identity switch) starts a fresh guarded window.
class SyncPushGuard {
  String? _uid;
  bool _pullSettled = false;
  bool _pullImported = false;
  bool _remoteNonEmpty = false;
  bool _localNonEmptySeen = false;
  bool _deferred = false;

  /// Whether [s] carries no user data at all.
  static bool datasetIsEmpty(Store s) =>
      s.tournaments.isEmpty && s.teams.isEmpty && s.matches.isEmpty;

  /// Starts a fresh guarded window (identity switches, log-out).
  void reset() {
    _uid = null;
    _pullSettled = false;
    _pullImported = false;
    _remoteNonEmpty = false;
    _localNonEmptySeen = false;
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

  /// Whether a push of an all-empty dataset must be suppressed
  /// right now: the remote backup is known to hold data, this
  /// activation's pull imported none of it, and the local dataset
  /// was never non-empty in this activation — the exact shape of
  /// the #R1 data loss (a fresh/never-imported empty scope).
  bool emptyPushSuppressed(bool emptyDataset) =>
      emptyDataset &&
      _remoteNonEmpty &&
      !_pullImported &&
      !_localNonEmptySeen;

  /// The push-path check used AFTER the gate has settled (the
  /// settle-time flush has its own decision in [settle]). Records
  /// the observation that the local dataset is non-empty — once
  /// seen, a later empty dataset is treated as the result of
  /// explicit user deletions, whose sync is legitimate.
  bool pushPermitted({required bool emptyDataset}) {
    if (!emptyDataset) _localNonEmptySeen = true;
    if (!_pullSettled) return false;
    return !emptyPushSuppressed(emptyDataset);
  }

  /// Records a completed push: afterwards the remote backup mirrors
  /// what was sent, so an empty push that WAS permitted (explicit
  /// delete-all) also lifts the suppression for what follows.
  void notePushed({required bool emptyDataset}) {
    _remoteNonEmpty = !emptyDataset;
    if (!emptyDataset) _localNonEmptySeen = true;
  }

  /// Settles the guard with the first pull's outcome for [uid].
  /// Returns true when a deferred push should be flushed now.
  /// [remoteNonEmpty] is the pull's own reading of the backup;
  /// when omitted it falls back to [docSeen] (a seen backup is
  /// assumed to hold data — the conservative choice).
  bool settle(
    String uid, {
    required bool imported,
    required bool docSeen,
    required bool emptyDataset,
    bool? remoteNonEmpty,
  }) {
    _track(uid);
    _pullSettled = true;
    _pullImported = imported;
    _remoteNonEmpty = remoteNonEmpty ?? docSeen;
    if (!emptyDataset) _localNonEmptySeen = true;
    if (!_deferred) return false;
    _deferred = false;
    return !emptyPushSuppressed(emptyDataset);
  }
}

/// What a pull should do with the remote backup (v1.3.3).
enum PullDecision {
  /// Apply the remote dataset to the local store.
  importRemote,

  /// Keep the local dataset and push it up, healing the backup.
  keepLocalAndPush,

  /// Apply nothing (local copy is current; photos may still sync).
  noImport,
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

  /// The import decision for one pull (v1.3.3, bug #R1 follow-up).
  ///
  /// Timestamps alone cannot decide this: a fresh scope's local
  /// "last modified" clock is stamped with the CURRENT time by the
  /// activation-time persists (profile ensure) that run before the
  /// first pull, so a perfectly good older backup looks "stale"
  /// next to a completely empty local dataset — and on 2026-10-21
  /// exactly that made a new device skip its import, after which
  /// its empty pushes destroyed the backup for every device. So
  /// emptiness outranks timestamps:
  ///
  /// - Local empty + remote non-empty → ALWAYS import: there is
  ///   nothing local to protect, whatever the clocks say.
  /// - Local non-empty + remote empty → NEVER import the empty
  ///   copy: keep local and push it up to heal the backup.
  /// - Otherwise (both sides hold data, or neither does) the
  ///   classic last-write-wins timestamp rule decides.
  static PullDecision decidePull({
    required bool localEmpty,
    required bool remoteEmpty,
    required bool remoteNewer,
  }) {
    if (localEmpty && !remoteEmpty) return PullDecision.importRemote;
    if (!localEmpty && remoteEmpty) return PullDecision.keepLocalAndPush;
    return remoteNewer ? PullDecision.importRemote : PullDecision.noImport;
  }

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
      // Empty-push suppression (v1.3.3): the settle-time check alone
      // was not enough — the first ordinary persist AFTER settle
      // still pushed a fresh scope's empty dataset over the real
      // backup. The guard therefore vets every push, all activation
      // long: an all-empty push from a never-imported, never-had-data
      // scope never runs while the backup is known to hold data.
      if (!_guard.pushPermitted(
          emptyDataset: SyncPushGuard.datasetIsEmpty(store))) {
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
    // Last line of defence (v1.3.3): whatever path led here, a
    // suppressed all-empty push never reaches Firestore.
    final emptyDataset = SyncPushGuard.datasetIsEmpty(store);
    if (emptyDataset && _guard.emptyPushSuppressed(true)) return;
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
      _guard.notePushed(emptyDataset: emptyDataset);
      final photos = _photosRef();
      if (photos != null) await PhotoSync.pushPhotos(photos, store);
      _lastSyncAt = DateTime.now();
      _lastError = null;
    } catch (e) {
      _lastError = e.toString();
      debugPrint('Sync push failed: $e');
    }
  }

  /// Pull remote state into [store]. Returns true when remote data
  /// was applied.
  ///
  /// The decision is [decidePull]'s: a completely empty side never
  /// wins over a non-empty one — an empty local scope imports the
  /// non-empty backup regardless of timestamps, and an empty backup
  /// is never imported over local data (the local data is pushed up
  /// to heal it instead). When both sides hold data, last-write-wins
  /// by timestamp applies, as before.
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
        _settleAfterPull(store, uid,
            imported: false,
            docSeen: false,
            remoteNonEmpty: !SyncPushGuard.datasetIsEmpty(store));
        return false;
      }
      final data = snap.data()!;
      final remoteAt = (data['updatedAt'] as num?)?.toInt() ?? 0;
      final localAt = await store.getLastModified();
      // Decode the remote collections BEFORE deciding anything —
      // the import decision needs to know whether each side is
      // completely empty, and emptiness outranks the clocks (see
      // [decidePull]). A field that fails to decode counts as empty
      // here; per-field fallbacks below still keep the local copy
      // of a corrupt field whenever an import does happen.
      final rTeams = _decode(data['teams'], Team.fromJson);
      final rTournaments =
          _decode(data['tournaments'], Tournament.fromJson);
      final rMatches = _decode(data['matches'], Match.fromJson);
      final rRegPlayers = _decode(data['regPlayers'], RegPlayer.fromJson);
      final rDrafts = _decode(data['drafts'], Draft.fromJson);
      final rManualStats =
          _decode(data['manualStats'], ManualStatEntry.fromJson);
      final remoteEmpty = (rTournaments?.isEmpty ?? true) &&
          (rTeams?.isEmpty ?? true) &&
          (rMatches?.isEmpty ?? true);
      final decision = decidePull(
        localEmpty: SyncPushGuard.datasetIsEmpty(store),
        remoteEmpty: remoteEmpty,
        remoteNewer: remoteAt > localAt,
      );

      if (decision == PullDecision.keepLocalAndPush) {
        // The backup is empty but this device holds the data: never
        // import the empty copy — push the local data up instead,
        // so the backup is healed for every other device too.
        await _push(ref, store);
        _settleAfterPull(store, uid,
            imported: false, docSeen: true, remoteNonEmpty: true);
        return false;
      }
      if (decision == PullDecision.noImport) {
        // Local state is current, but photos may still be missing
        // (e.g. a photo upload succeeded after this device's last
        // full pull).
        final photos = _photosRef();
        if (photos != null && await PhotoSync.pullPhotos(photos, store)) {
          await store.persist(skipSync: true);
          _lastSyncAt = DateTime.now();
        }
        _settleAfterPull(store, uid,
            imported: false,
            docSeen: true,
            remoteNonEmpty: !remoteEmpty);
        return false;
      }

      // importRemote — the classic last-write-wins case, or a
      // completely empty local scope taking the non-empty backup
      // regardless of what the clocks say (v1.3.3).
      await _applyRemote(
        store,
        teams: rTeams,
        tournaments: rTournaments,
        matches: rMatches,
        regPlayers: rRegPlayers,
        drafts: rDrafts,
        manualStats: rManualStats,
        profile: _decodeProfile(data['profile']),
        remoteAt: remoteAt,
      );
      _lastSyncAt = DateTime.now();
      _lastError = null;
      _settleAfterPull(store, uid,
          imported: true,
          docSeen: true,
          remoteNonEmpty: !remoteEmpty);
      return true;
    } catch (e) {
      _lastError = e.toString();
      debugPrint('Sync pull failed: $e');
      return false;
    }
  }

  /// Applies already-decoded remote collections to [store] and
  /// persists the result without triggering a push (the pull's own
  /// follow-ups run through [_settleAfterPull]).
  Future<void> _applyRemote(
    Store store, {
    required List<Team>? teams,
    required List<Tournament>? tournaments,
    required List<Match>? matches,
    required List<RegPlayer>? regPlayers,
    required List<Draft>? drafts,
    required List<ManualStatEntry>? manualStats,
    required AccountProfile? profile,
    required int remoteAt,
  }) async {
    _applyingRemote = true;
    try {
      store.teams = teams ?? store.teams;
      store.tournaments = tournaments ?? store.tournaments;
      store.matches = matches ?? store.matches;
      store.regPlayers = regPlayers ?? store.regPlayers;
      store.drafts = drafts ?? store.drafts;
      store.manualStats = manualStats ?? store.manualStats;
      store.profile = profile ?? store.profile;
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
    required bool remoteNonEmpty,
  }) {
    final flush = _guard.settle(
      uid,
      imported: imported,
      docSeen: docSeen,
      emptyDataset: SyncPushGuard.datasetIsEmpty(store),
      remoteNonEmpty: remoteNonEmpty,
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
