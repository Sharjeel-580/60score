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

import 'auth_service.dart';
import 'models.dart';
import 'photo_sync.dart';
import 'store.dart';

class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  Timer? _pushTimer;
  bool _applyingRemote = false;
  DateTime? _lastSyncAt;
  String? _lastError;

  DateTime? get lastSyncAt => _lastSyncAt;
  String? get lastError => _lastError;

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
      _push(ref, store);
    });
  }

  /// Cancels a pending debounced push (identity switches, log-out).
  void cancelPending() {
    _pushTimer?.cancel();
    _pushTimer = null;
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
  Future<bool> pull(Store store) async {
    final ref = _docRef();
    if (ref == null) return false;
    try {
      final snap = await ref.get();
      if (!snap.exists) {
        // First login on this account: push local state up as the baseline.
        await _push(ref, store);
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
      return true;
    } catch (e) {
      _lastError = e.toString();
      debugPrint('Sync pull failed: $e');
      return false;
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
