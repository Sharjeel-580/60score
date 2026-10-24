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
// - Push: debounced ~1s after any Store.persist(), only when logged
//   in (v1.3.4: was 5s). A push that fails (offline) stays "dirty"
//   and retries automatically — when the Firestore listener reports
//   the server is reachable again, on a periodic timer, and when
//   the app returns to the foreground.
// - Pull: after login and on app start (if logged in). Non-match
//   collections are last-write-wins by timestamp (see decidePull).
//   MATCHES are merged per record instead (v1.3.5): the whole-dataset
//   timestamp rule provably lost data both ways (2026-10-22/23 — a
//   device rejected newer remote matches, then pushed its stale
//   copy over them), so a match can never again be un-completed or
//   erased by a staler copy: see mergeMatches.
// - Live receive (v1.3.4): while a user is logged in, a Firestore
//   snapshot listener on the backup document applies newer data
//   written by other devices through the very same decision path
//   as a pull (decidePull), so a match scored on one phone shows
//   up on the others on its own — no manual step. This device's
//   own writes are recognised by their updatedAt stamp and skipped
//   (echo suppression).
// - Per-entity engine (Sync Fix "D", Phase C1): pulls and pushes
//   now run through the entity coordinator (see
//   entity_sync_coordinator.dart) behind this same public API —
//   dual-read of the per-entity collections and the legacy blob,
//   the hardened V2 merge, tombstones, and DELTA pushes of only
//   the changed records instead of the whole-dataset rewrite. The
//   legacy blob is read but never written by the new engine; it
//   stays as the fallback copy, and ANY failure of the entity path
//   (notably: the live Firestore rules predate the entity
//   collections — publishing their rules is the separately
//   approved Phase D) falls back to the legacy blob behaviour
//   below, unchanged, so sync is never worse than before C1.
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
import 'package:shared_preferences/shared_preferences.dart';

import 'account_profile.dart';
import 'auth_service.dart';
import 'entity_firestore.dart';
import 'entity_sync.dart';
import 'entity_sync_coordinator.dart';
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

  /// Whether this activation's first pull has settled yet.
  bool get pullSettled => _pullSettled;

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

  /// How long after a local change its push fires (v1.3.4: ~1s —
  /// the old 5s debounce made "auto" sync feel manual).
  static const Duration pushDebounce = Duration(seconds: 1);

  /// Cadence of the background retry while a push is owed to the
  /// cloud (the listener's reconnect signal and the app-resume hook
  /// usually beat it to the retry).
  static const Duration retryInterval = Duration(seconds: 20);

  Timer? _pushTimer;
  Timer? _retryTimer;
  bool _applyingRemote = false;
  DateTime? _lastSyncAt;
  String? _lastError;

  /// Local changes exist that no successful push has carried yet
  /// (v1.3.4 offline→online retry state).
  bool _pushDirty = false;

  /// Bumped by every push request; a finishing push only clears
  /// [_pushDirty] when no newer change arrived while it ran.
  int _pushGen = 0;

  /// The updatedAt stamp of this device's last successful push —
  /// the live listener skips snapshots carrying it (echo), and
  /// [_lastAppliedRemoteAt] is the newest remote stamp this device
  /// has already applied or deliberately passed on.
  int _lastPushedAt = 0;
  int _lastAppliedRemoteAt = 0;

  /// Live-receive listener (v1.3.4) and the uid it belongs to.
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _liveSub;
  String? _liveUid;

  /// Live-receive listeners for the per-entity collections
  /// (Phase C1) and the uid they belong to. Any change in any
  /// collection schedules one debounced entity sync round.
  final List<StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
      _entitySubs = [];
  String? _entityUid;
  Timer? _entityDebounce;

  /// Serializes entity sync rounds: a pull, a push and a live
  /// event can all ask for a round at once, and a round reads and
  /// writes the store — two racing would interleave their diffs.
  Future<void> _roundChain = Future<void>.value();

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

  // ---------------- Per-match merge (v1.3.5) ----------------

  /// How "advanced" a match status is for the merge: a completed
  /// match outranks everything, terminal administrative states
  /// (noResult / cancelled) outrank a live copy, and a live copy
  /// outranks a fixture that has not started.
  static int matchStatusRank(String status) {
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

  static int _matchLegalBalls(Match m) =>
      m.innings.fold(0, (acc, inn) => acc + inn.legalBalls);

  static int _matchBallEvents(Match m) =>
      m.innings.fold(0, (acc, inn) => acc + inn.events.length);

  /// The wicket ceiling a chase margin is measured against for
  /// [inn]: the innings' stored maxWickets, else the match's
  /// totalWickets, else XI − 1, else 10 (v1.3.6).
  static int _inningsMaxWickets(Match m, InningsState inn) {
    if (inn.maxWickets > 0) return inn.maxWickets;
    if (m.totalWickets > 0) return m.totalWickets;
    final xi = inn.battingXI.length - 1;
    return xi >= 1 ? xi : 10;
  }

  static final _tieRe = RegExp(r'\btie(?:d|s)?\b');
  static final _wicketsRe = RegExp(r'won by (\d+) wicket');
  static final _runsRe = RegExp(r'won by (\d+) run');

  /// Compact signature of a result text: `tie`, `w<n>` (won by n
  /// wickets) or `r<n>` (won by n runs); null when the text carries
  /// no parseable margin and no tie wording (v1.3.6).
  static String? _resultSignature(String raw) {
    final text = raw.trim().toLowerCase();
    if (text.isEmpty) return null;
    if (_tieRe.hasMatch(text)) return 'tie';
    final wk = _wicketsRe.firstMatch(text);
    if (wk != null) return 'w${wk.group(1)}';
    final rn = _runsRe.firstMatch(text);
    if (rn != null) return 'r${rn.group(1)}';
    return null;
  }

  /// Whether [m]'s stored result text agrees with the result its
  /// own innings figures imply (the same math as computeResult in
  /// scoring.dart): true/false when the check can judge, null when
  /// it cannot — fewer than two innings, or an unparseable result
  /// text (v1.3.6).
  static bool? _resultConsistency(Match m) {
    if (m.innings.length < 2) return null;
    final sig = _resultSignature(m.resultText);
    if (sig == null) return null;
    final i1 = m.innings[0];
    final i2 = m.innings[1];
    final String expected;
    if (i2.totalRuns > i1.totalRuns) {
      expected = 'w${_inningsMaxWickets(m, i2) - i2.wickets}';
    } else if (i1.totalRuns > i2.totalRuns) {
      expected = 'r${i1.totalRuns - i2.totalRuns}';
    } else {
      expected = 'tie';
    }
    return sig == expected;
  }

  /// Positive when [a] is the more advanced copy of a match:
  /// status rank first, then completeness — total legal balls,
  /// then (v1.3.6, completed copies only) result consistency,
  /// then ball-events count and a non-empty result text, in that
  /// order.
  static int compareMatchAdvancement(Match a, Match b) {
    final rank =
        matchStatusRank(a.status).compareTo(matchStatusRank(b.status));
    if (rank != 0) return rank;
    final balls = _matchLegalBalls(a).compareTo(_matchLegalBalls(b));
    if (balls != 0) return balls;
    // v1.3.6: a completed copy whose result text contradicts its
    // own figures must not beat the self-consistent copy just
    // because it holds more ball events — a real record read
    // "won by 9 wickets" for a chase that ended 2 down (true
    // margin 8), and letting the corrupt-but-richer copy win
    // would resurrect its wrong player credits. When exactly one
    // side is consistent it wins here; both-consistent,
    // both-inconsistent and unparseable cases fall through to
    // the ball-events step below, unchanged.
    if (a.status == 'completed' && b.status == 'completed') {
      final ca = _resultConsistency(a);
      final cb = _resultConsistency(b);
      if (ca != null && cb != null && ca != cb) return ca ? 1 : -1;
    }
    final events = _matchBallEvents(a).compareTo(_matchBallEvents(b));
    if (events != 0) return events;
    final ra = a.resultText.isNotEmpty ? 1 : 0;
    final rb = b.resultText.isNotEmpty ? 1 : 0;
    return ra.compareTo(rb);
  }

  /// The per-match merge at the heart of v1.3.5 sync: the union of
  /// both sides' match ids, keeping for each id the more advanced
  /// record (see [compareMatchAdvancement]). A match present on
  /// only one side is always kept; a completed record can never be
  /// replaced by a non-completed one. Local order is preserved,
  /// remote-only records are appended — so the merge is stable and
  /// both devices converge on the same list.
  static List<Match> mergeMatches(List<Match> local, List<Match> remote) {
    final byId = <String, Match>{};
    final order = <String>[];
    for (final m in local) {
      if (!byId.containsKey(m.id)) order.add(m.id);
      byId[m.id] = m;
    }
    for (final m in remote) {
      final cur = byId[m.id];
      if (cur == null) {
        order.add(m.id);
        byId[m.id] = m;
      } else if (compareMatchAdvancement(m, cur) > 0) {
        byId[m.id] = m;
      }
    }
    return [for (final id in order) byId[id]!];
  }

  /// Content equality for match lists (order-sensitive), via the
  /// same JSON the backup stores.
  static bool sameMatchContent(List<Match> a, List<Match> b) {
    if (a.length != b.length) return false;
    return jsonEncode(a.map((m) => m.toJson()).toList()) ==
        jsonEncode(b.map((m) => m.toJson()).toList());
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
    _pushDirty = true;
    _pushGen++;
    _pushTimer?.cancel();
    _pushTimer = Timer(pushDebounce, () => _attemptPush(store));
  }

  /// One push attempt for the CURRENT identity, with every guard
  /// applied. Used by the debounce timer and by the offline-retry
  /// paths (listener reconnect signal, periodic timer, app resume).
  void _attemptPush(Store store) {
    final ref = _docRef();
    if (ref == null) return;
    final uid = AuthService().currentUser!.uid;
    // The identity may have changed since the push was scheduled
    // (log-out, account switch): never write one identity's data
    // into another account's backup document.
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
      // Suppression is a decision, not a debt: this dataset must
      // never go up in this activation, so it is not "dirty".
      _pushDirty = false;
      return;
    }
    _pushCurrent(store);
  }

  /// Cancels a pending debounced push (identity switches, log-out).
  /// Also stops the live listener and the retry timer, clears the
  /// per-identity stamps, and restarts the push guard: the next
  /// identity's first push waits for its own first pull, and no
  /// listener event can leak one account's data into another's
  /// scope.
  void cancelPending() {
    _pushTimer?.cancel();
    _pushTimer = null;
    stopLiveSync();
    _stopRetryTimer();
    _pushDirty = false;
    _lastPushedAt = 0;
    _lastAppliedRemoteAt = 0;
    _guard.reset();
  }

  void _startRetryTimer(Store store) {
    if (_retryTimer != null) return;
    _retryTimer = Timer.periodic(retryInterval, (_) {
      if (!_pushDirty || _docRef() == null) {
        _stopRetryTimer();
        return;
      }
      _attemptPush(store);
    });
  }

  void _stopRetryTimer() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  Future<void> _push(
      DocumentReference<Map<String, dynamic>> ref, Store store) async {
    // Last line of defence (v1.3.3): whatever path led here, a
    // suppressed all-empty push never reaches Firestore.
    final emptyDataset = SyncPushGuard.datasetIsEmpty(store);
    if (emptyDataset && _guard.emptyPushSuppressed(true)) return;
    final gen = _pushGen;
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
        // Deletion tombstones ride along as one additive field
        // (Sync Fix "D", Phase C0 — the blob bridge of
        // SYNC_FIX_D_PLAN.md §4): older builds ignore the unknown
        // field on read, and merge:true pushes from older builds
        // leave it in place, while builds with this code union it
        // into their tombstone set and filter dead records out of
        // every merge — so a delete now sticks instead of being
        // resurrected by the union merge.
        'tombstones':
            jsonEncode(store.tombstones.map((t) => t.toJson()).toList()),
        'updatedAt': now,
        'appVersion': '1.2.0',
      }, SetOptions(merge: true));
      // Stamp of this device's own write: the live listener uses
      // it to recognise (and skip) the echo of this push.
      _lastPushedAt = now;
      await store.setLastModified(now);
      _guard.notePushed(emptyDataset: emptyDataset);
      final photos = _photosRef();
      if (photos != null) await PhotoSync.pushPhotos(photos, store);
      _lastSyncAt = DateTime.now();
      _lastError = null;
      // The debt is paid only when no newer change arrived while
      // this push was in flight; that change's own debounce timer
      // (or the retry paths) carries it otherwise.
      if (_pushGen == gen) {
        _pushDirty = false;
        _stopRetryTimer();
      }
    } catch (e) {
      _lastError = e.toString();
      // Offline (or a transient failure): the change still owes
      // the cloud a push. It retries when connectivity returns —
      // the live listener's reconnect signal, the periodic retry
      // timer, or the next app resume (v1.3.4).
      _pushDirty = true;
      _startRetryTimer(store);
      debugPrint('Sync push failed: $e');
    }
  }

  // ---------------- Per-entity engine (Phase C1) ----------------

  /// Runs [op] after every previously queued entity round has
  /// finished. Errors propagate to the caller; the chain itself
  /// never stays failed. A call made from WITHIN a round (the
  /// settle flush pushing through [_pushCurrent]) runs directly —
  /// queueing it behind the round that is waiting for it would
  /// deadlock.
  bool _inRound = false;

  Future<T> _serialized<T>(Future<T> Function() op) {
    if (_inRound) return op();
    final result = _roundChain.then((_) async {
      _inRound = true;
      try {
        return await op();
      } finally {
        _inRound = false;
      }
    });
    _roundChain = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  /// Builds the entity-engine coordinator for the CURRENT
  /// identity, or null when sync is unavailable (logged out /
  /// Firebase not ready / the store holds another identity's
  /// scope). The migration flag is per-account and lives in
  /// SharedPreferences next to the data it describes.
  EntitySyncCoordinator? _buildCoordinator(Store store) {
    final auth = AuthService();
    if (!auth.firebaseReady || !auth.isLoggedIn) return null;
    final uid = auth.currentUser!.uid;
    if (store.identityId != uid) return null;
    final fs = FirebaseFirestore.instance;
    final flagKey = 'score60_entity_migrated_v1__$uid';
    return EntitySyncCoordinator(
      local: StoreEntityDocStore(store),
      cloud: FirestoreEntityDocStore(firestore: fs, uid: uid),
      blobSource: FirestoreBlobSource(fs, uid),
      migrationDone: () async {
        final prefs = await SharedPreferences.getInstance();
        return prefs.getBool(flagKey) ?? false;
      },
      markMigrationDone: () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(flagKey, true);
      },
    );
  }

  /// One entity sync round with all of this service's follow-ups,
  /// mirroring what the legacy pull/push paths do around their
  /// transfer: the migration runs first (its failure to verify
  /// does not block the round — dual-read still unions the
  /// untouched blob); when the round changed the local side,
  /// photos are refilled from the photos subcollection and the
  /// store is persisted without re-arming a push; the push guard
  /// is settled for an activation's real pulls; and an applied
  /// round arms the re-publish, exactly as a legacy import does.
  Future<bool> _runEntitySync(
    Store store,
    EntitySyncCoordinator coordinator, {
    required bool settleGuard,
    bool pushPhotosAfter = false,
  }) async {
    final uid = AuthService().currentUser!.uid;
    if (store.identityId != uid) return false;
    final migration = await coordinator.runMigrationIfNeeded();
    if (!migration.ok) {
      debugPrint('Sync migration not verified: ${migration.detail}');
    }
    final result = await coordinator.syncRound();
    final applied = result.localChanged;
    if (applied) {
      _applyingRemote = true;
      try {
        final photos = _photosRef();
        if (photos != null) await PhotoSync.pullPhotos(photos, store);
        await store.persist(skipSync: true);
      } finally {
        _applyingRemote = false;
      }
      _lastSyncAt = DateTime.now();
      _lastError = null;
    }
    if (pushPhotosAfter) {
      final photos = _photosRef();
      if (photos != null) await PhotoSync.pushPhotos(photos, store);
      await store.setLastModified(DateTime.now().millisecondsSinceEpoch);
      _guard.notePushed(emptyDataset: SyncPushGuard.datasetIsEmpty(store));
      _lastSyncAt = DateTime.now();
      _lastError = null;
    }
    if (settleGuard) {
      _settleAfterPull(store, uid,
          imported: applied,
          docSeen: result.remoteSeen,
          remoteNonEmpty: result.remoteNonEmpty);
    } else if (applied &&
        shouldArmRepublishAfterPull(
          applied: true,
          hasPublished: PublishService.hasPublished(store),
        )) {
      PublishService().scheduleRepublish(store);
    }
    return applied;
  }

  /// One push of the current state through the CURRENT engine:
  /// an entity round (delta writes of the changed records only)
  /// when the engine is available; the legacy blob write when it
  /// is not, and whenever the entity path fails — a push must
  /// never be lost to the migration. The push-debt bookkeeping
  /// mirrors the legacy [_push]: the debt clears only when no
  /// newer change arrived while the round ran.
  Future<void> _pushCurrent(Store store) async {
    final coordinator = _buildCoordinator(store);
    if (coordinator != null) {
      final gen = _pushGen;
      try {
        await _serialized(() => _runEntitySync(store, coordinator,
            settleGuard: false, pushPhotosAfter: true));
        if (_pushGen == gen) {
          _pushDirty = false;
          _stopRetryTimer();
        }
        return;
      } catch (e) {
        _lastError = e.toString();
        debugPrint('Sync entity push failed, blob fallback: $e');
      }
    }
    final ref = _docRef();
    if (ref != null) await _push(ref, store);
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
    // Phase C1: the entity engine runs the pull (dual-read,
    // hardened merge, delta write-backs). ANY failure of the
    // entity path — including the live Firestore rules not yet
    // covering the entity collections — falls back to the legacy
    // blob pull below, unchanged.
    final coordinator = _buildCoordinator(store);
    if (coordinator != null) {
      try {
        return await _serialized(
            () => _runEntitySync(store, coordinator, settleGuard: true));
      } catch (e) {
        _lastError = e.toString();
        debugPrint('Sync entity pull failed, blob fallback: $e');
      }
    }
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
      return await _handleRemoteData(store, uid, snap.data()!,
          settleGuard: true);
    } catch (e) {
      _lastError = e.toString();
      debugPrint('Sync pull failed: $e');
      return false;
    }
  }

  /// The shared decision core of [pull] and the live listener:
  /// decode the remote document, decide via [decidePull] (emptiness
  /// outranks timestamps — the v1.3.3 rules govern live receives
  /// exactly as they govern pulls), and apply the outcome. Returns
  /// true when remote data was applied.
  ///
  /// [settleGuard] is true for an activation's real pulls (login /
  /// app start / "Sync now") and for a listener event that lands
  /// before any pull settled; later listener events must NOT
  /// re-settle, because settle rewrites the guard's imported/remote
  /// bookkeeping for the whole activation.
  Future<bool> _handleRemoteData(
    Store store,
    String uid,
    Map<String, dynamic> data, {
    required bool settleGuard,
  }) async {
    final ref = _docRef();
    if (ref == null) return false;
    final remoteAt = (data['updatedAt'] as num?)?.toInt() ?? 0;
    final localAt = await store.getLastModified();
    // Decode the remote collections BEFORE deciding anything —
    // the import decision needs to know whether each side is
    // completely empty, and emptiness outranks the clocks (see
    // [decidePull]). A field that fails to decode counts as empty
    // here; per-field fallbacks below still keep the local copy
    // of a corrupt field whenever an import does happen.
    final rTeams = _decode(data['teams'], Team.fromJson);
    final rTournaments = _decode(data['tournaments'], Tournament.fromJson);
    final rMatchesRaw = _decode(data['matches'], Match.fromJson);
    final rRegPlayers = _decode(data['regPlayers'], RegPlayer.fromJson);
    final rDrafts = _decode(data['drafts'], Draft.fromJson);
    final rManualStats =
        _decode(data['manualStats'], ManualStatEntry.fromJson);
    // Tombstone bridge (Sync Fix "D", Phase C0): union any
    // tombstones the remote carries into the local set, then hold
    // BOTH sides' match lists to them for the rest of this handler
    // — a tombstoned match is dead no matter which copy shows up
    // (the delete-resurrection fix). Absent/corrupt field → no
    // remote tombstones; the local set is never reduced by a pull.
    final tombstonesChanged =
        store.absorbTombstones(_decodeTombstones(data['tombstones']));
    final deadMatchIds = store.tombstonedMatchIds;
    final rMatches = (rMatchesRaw == null || deadMatchIds.isEmpty)
        ? rMatchesRaw
        : rMatchesRaw
            .where((m) => !deadMatchIds.contains(m.id))
            .toList();
    final localMatches = deadMatchIds.isEmpty
        ? store.matches
        : store.matches
            .where((m) => !deadMatchIds.contains(m.id))
            .toList();
    final remoteEmpty = (rTournaments?.isEmpty ?? true) &&
        (rTeams?.isEmpty ?? true) &&
        (rMatches?.isEmpty ?? true);
    final decision = decidePull(
      localEmpty: SyncPushGuard.datasetIsEmpty(store),
      remoteEmpty: remoteEmpty,
      remoteNewer: remoteAt > localAt,
    );
    if (remoteAt > _lastAppliedRemoteAt) {
      _lastAppliedRemoteAt = remoteAt;
    }

    // Per-match merge (v1.3.5): whichever way [decision] goes for
    // the dataset as a whole, MATCHES are never last-write-wins —
    // the merged list (union of ids, most advanced record per id)
    // is what this device keeps, and when it carries records the
    // cloud lacks (or richer copies of them), the merged dataset is
    // pushed back up so both sides converge on it. A remote field
    // that failed to decode (null) cannot be merged; the local
    // matches then stand as they are.
    final mergedMatches = rMatches == null
        ? localMatches
        : mergeMatches(localMatches, rMatches);
    final mergedDiffersFromLocal =
        !sameMatchContent(mergedMatches, store.matches);
    // Compared against the RAW remote list on purpose: when the
    // cloud blob still carries a tombstoned record, the merged
    // (cleaned) list differs from it and the push-back below
    // scrubs the blob too.
    final mergedDiffersFromRemote = rMatchesRaw != null &&
        !sameMatchContent(mergedMatches, rMatchesRaw);

    if (decision == PullDecision.keepLocalAndPush) {
      // The backup is empty but this device holds the data: never
      // import the empty copy — push the local data up instead,
      // so the backup is healed for every other device too. Any
      // locally-held copy of a tombstoned match is scrubbed first
      // so the healing push cannot carry the zombie back up.
      if (tombstonesChanged ||
          !sameMatchContent(localMatches, store.matches)) {
        store.matches = localMatches;
        await store.persist(skipSync: true);
      }
      await _push(ref, store);
      if (settleGuard) {
        _settleAfterPull(store, uid,
            imported: false, docSeen: true, remoteNonEmpty: true);
      }
      return false;
    }
    if (decision == PullDecision.noImport) {
      // The dataset clocks say local is current — but the merge can
      // still bring in match records this device lacks (or richer
      // copies) from the remote, and this device can hold records
      // the cloud lacks. Apply the merge locally, then push the
      // converged dataset up when the cloud's copy differs from it.
      var applied = false;
      if (mergedDiffersFromLocal) {
        store.matches = mergedMatches;
        applied = true;
      }
      // Photos may still be missing (e.g. a photo upload succeeded
      // after this device's last full pull).
      final photos = _photosRef();
      var photosChanged = false;
      if (photos != null) {
        photosChanged = await PhotoSync.pullPhotos(photos, store);
      }
      if (applied || photosChanged || tombstonesChanged) {
        await store.persist(skipSync: true);
        _lastSyncAt = DateTime.now();
      }
      if (mergedDiffersFromRemote) {
        await _push(ref, store);
      }
      if (settleGuard) {
        _settleAfterPull(store, uid,
            imported: applied,
            docSeen: true,
            remoteNonEmpty: !remoteEmpty);
      } else if (applied &&
          shouldArmRepublishAfterPull(
            applied: true,
            hasPublished: PublishService.hasPublished(store),
          )) {
        PublishService().scheduleRepublish(store);
      }
      return applied;
    }

    // importRemote — the classic last-write-wins case for the
    // non-match collections, or a completely empty local scope
    // taking the non-empty backup regardless of what the clocks
    // say (v1.3.3). Matches still go through the per-match merge:
    // a richer local copy of a match survives the import, and the
    // converged dataset is pushed back up so the cloud holds it
    // too instead of re-sending its older copies next time.
    await _applyRemote(
      store,
      teams: rTeams,
      tournaments: rTournaments,
      matches: mergedMatches,
      regPlayers: rRegPlayers,
      drafts: rDrafts,
      manualStats: rManualStats,
      profile: _decodeProfile(data['profile']),
      remoteAt: remoteAt,
    );
    _lastSyncAt = DateTime.now();
    _lastError = null;
    if (mergedDiffersFromRemote) {
      await _push(ref, store);
    }
    if (settleGuard) {
      _settleAfterPull(store, uid,
          imported: true, docSeen: true, remoteNonEmpty: !remoteEmpty);
    } else if (shouldArmRepublishAfterPull(
      applied: true,
      hasPublished: PublishService.hasPublished(store),
    )) {
      // A live-applied import carries the same re-publish duty as
      // a pull's (published tournaments must reach the public
      // collection), it just must not re-settle the guard.
      PublishService().scheduleRepublish(store);
    }
    return true;
  }

  // ---------------- Live receive + retry (v1.3.4) ----------------

  /// Whether a live snapshot is worth processing at all: skip this
  /// device's own writes (their updatedAt is the stamp recorded at
  /// push time — the echo) and anything at or below the newest
  /// remote stamp already applied or passed on. [decidePull] still
  /// arbitrates every snapshot that passes this gate.
  static bool shouldApplyLiveSnapshot({
    required int remoteAt,
    required int lastPushedAt,
    required int lastAppliedRemoteAt,
  }) =>
      remoteAt > 0 &&
      remoteAt != lastPushedAt &&
      remoteAt > lastAppliedRemoteAt;

  /// Start listening for other devices' writes to this account's
  /// backup document. No-op for guests / logged-out state (stops
  /// any running listener instead). Safe to call repeatedly for
  /// the same account.
  void startLiveSync(Store store) {
    final ref = _docRef();
    if (ref == null) {
      stopLiveSync();
      return;
    }
    final uid = AuthService().currentUser!.uid;
    if (_liveSub != null && _liveUid == uid) {
      _startEntityListeners(store, uid);
      return;
    }
    stopLiveSync();
    _liveUid = uid;
    _liveSub = ref.snapshots(includeMetadataChanges: true).listen(
      (snap) => _onLiveSnapshot(store, uid, snap),
      onError: (Object e) {
        _lastError = e.toString();
        debugPrint('Sync live listener failed: $e');
      },
    );
    _startEntityListeners(store, uid);
  }

  /// Live-receive for the per-entity collections (Phase C1): any
  /// change — another device's scored match landing as an entity
  /// document, a tombstone arriving — schedules a debounced
  /// entity sync round, so arrivals show up on their own just as
  /// blob writes did. The blob listener above stays as the
  /// fallback for writes made by builds that predate the entity
  /// engine, whose blob changes the rounds absorb via dual-read.
  ///
  /// Until the Phase-D rules are published these collections may
  /// be unreadable; those listener errors are recorded exactly
  /// like the blob listener's, and sync keeps working via the
  /// blob path meanwhile.
  void _startEntityListeners(Store store, String uid) {
    if (_entitySubs.isNotEmpty && _entityUid == uid) return;
    _stopEntityListeners();
    _entityUid = uid;
    final user = FirebaseFirestore.instance.collection('users').doc(uid);
    final collections = <CollectionReference<Map<String, dynamic>>>[
      for (final kind in EntityKind.all)
        kind == EntityKind.profile
            ? user.collection('meta')
            : user.collection(kind),
      user.collection(EntityKind.tombstones),
    ];
    for (final col in collections) {
      _entitySubs.add(col.snapshots().listen(
        (_) => _onEntityActivity(store, uid),
        onError: (Object e) {
          _lastError = e.toString();
          debugPrint('Sync entity listener failed: $e');
        },
      ));
    }
  }

  void _stopEntityListeners() {
    for (final sub in _entitySubs) {
      sub.cancel();
    }
    _entitySubs.clear();
    _entityUid = null;
    _entityDebounce?.cancel();
    _entityDebounce = null;
  }

  void _onEntityActivity(Store store, String uid) {
    // A stale listener (or a store that has since switched scope)
    // must never touch another identity's data — the same checks
    // the blob listener runs.
    if (_entityUid != uid) return;
    if (AuthService().currentUser?.uid != uid) return;
    if (store.identityId != uid) return;
    if (_applyingRemote) return;
    _entityDebounce?.cancel();
    _entityDebounce = Timer(const Duration(milliseconds: 400), () async {
      final coordinator = _buildCoordinator(store);
      if (coordinator == null) return;
      try {
        await _serialized(() => _runEntitySync(store, coordinator,
            settleGuard: !_guard.pullSettled));
      } catch (e) {
        _lastError = e.toString();
        debugPrint('Sync entity live round failed: $e');
      }
    });
  }

  /// Stop the live listener (identity switches, log-out).
  void stopLiveSync() {
    _liveSub?.cancel();
    _liveSub = null;
    _liveUid = null;
    _stopEntityListeners();
  }

  Future<void> _onLiveSnapshot(
    Store store,
    String uid,
    DocumentSnapshot<Map<String, dynamic>> snap,
  ) async {
    // A stale listener (or a store that has since switched scope)
    // must never touch another identity's data.
    if (_liveUid != uid) return;
    if (AuthService().currentUser?.uid != uid) return;
    if (store.identityId != uid) return;
    if (_applyingRemote) return;
    // An event served from the SERVER (not the local cache) proves
    // connectivity is back: a push that failed while offline
    // retries right now instead of waiting for the periodic timer.
    if (!snap.metadata.isFromCache && _pushDirty) {
      _attemptPush(store);
    }
    if (!snap.exists) return;
    final data = snap.data();
    if (data == null) return;
    final remoteAt = (data['updatedAt'] as num?)?.toInt() ?? 0;
    if (!shouldApplyLiveSnapshot(
      remoteAt: remoteAt,
      lastPushedAt: _lastPushedAt,
      lastAppliedRemoteAt: _lastAppliedRemoteAt,
    )) {
      return;
    }
    try {
      await _handleRemoteData(store, uid, data,
          settleGuard: !_guard.pullSettled);
    } catch (e) {
      _lastError = e.toString();
      debugPrint('Sync live apply failed: $e');
    }
  }

  /// App returned to the foreground: when this device holds changes
  /// that never reached the cloud (scored offline), push them
  /// first; otherwise pull — so a match finished on another device
  /// shows up here on its own, with no manual step (v1.3.4). The
  /// push-first order protects unsynced local work from the
  /// last-write-wins import.
  Future<void> onAppResumed(Store store) async {
    if (_docRef() == null) return;
    if (_pushDirty) {
      _attemptPush(store);
    } else {
      await pull(store);
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
      _pushCurrent(store);
    }
  }

  /// Decodes the blob's additive tombstone field. Returns an
  /// empty list when the field is absent (older backups) or
  /// corrupt — a bad tombstone field must never wipe the local
  /// set; [Store.absorbTombstones] only ever adds to it.
  List<Tombstone> _decodeTombstones(Object? raw) {
    if (raw is! String || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => Tombstone.fromJson(e as Map<String, dynamic>))
          .where((t) => t.kind.isNotEmpty && t.id.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
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
