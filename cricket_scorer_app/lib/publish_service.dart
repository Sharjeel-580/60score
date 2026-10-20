// 60Score tournament publishing — public, view-only tournament sharing.
// The owner manually publishes one of their tournaments; anyone (guest
// or logged in) can then find it in Search, view fixtures / results /
// points table, and follow it for live updates. Only the owner can
// publish, update or unpublish — viewers never get edit controls.
//
// Backend shape (fixed):
// - Collection: published_tournaments/{tournamentId}
// - Fields: ownerUid (string), name, venue, logoBase64 (string, may be
//   ''), updatedAt (server timestamp), data (string: JSON snapshot of
//   ONLY that tournament's slice — the Tournament, its Teams, its
//   Matches and the registered players belonging to its teams, encoded
//   with the same model serializers as local storage / cloud backup).
// - While a tournament is published, its snapshot is re-pushed
//   (debounced, same pattern as SyncService) whenever the owner's data
//   changes, so followers see live scores. All writes are
//   fire-and-forget safe: failures never block scoring or offline use.
//
// Firestore rules (one-time console setup, matching this shape):
//   match /published_tournaments/{tournamentId} {
//     allow read: if true;
//     allow create, update: if request.auth != null
//         && request.auth.uid == request.resource.data.ownerUid;
//     allow delete: if request.auth != null
//         && request.auth.uid == resource.data.ownerUid;
//   }
import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';
import 'models.dart';
import 'store.dart';

/// The decoded slice of one tournament — exactly what a published
/// snapshot carries, nothing more.
class TournamentSlice {
  final Tournament tournament;
  final List<Team> teams;
  final List<Match> matches;
  final List<RegPlayer> regPlayers;

  const TournamentSlice({
    required this.tournament,
    required this.teams,
    required this.matches,
    required this.regPlayers,
  });
}

/// One published tournament as seen by a viewer: the public document's
/// display fields plus its decoded slice.
class PublishedTournament {
  final String id;
  final String ownerUid;
  final String name;
  final String venue;
  final String logoBase64;
  final int updatedAtMs;
  final TournamentSlice slice;

  const PublishedTournament({
    required this.id,
    required this.ownerUid,
    required this.name,
    required this.venue,
    required this.logoBase64,
    required this.updatedAtMs,
    required this.slice,
  });

  Tournament get tournament => slice.tournament;
  List<Team> get teams => slice.teams;
  List<Match> get matches => slice.matches;

  String teamName(String id) {
    if (id.isEmpty) return 'TBD';
    for (final t in slice.teams) {
      if (t.id == id) return t.name;
    }
    return 'Unknown team';
  }
}

/// Followed (bookmarked) published tournament ids, kept on-device.
class FollowStore {
  static const _kFollows = 'score60_followed_tournaments_v1';

  static Future<List<String>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(_kFollows) ?? [];
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<String> ids) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_kFollows, ids);
    } catch (_) {}
  }
}

class PublishService {
  static final PublishService _instance = PublishService._internal();
  factory PublishService() => _instance;
  PublishService._internal();

  Timer? _republishTimer;
  String? _lastError;
  String? get lastError => _lastError;

  static const _kCollection = 'published_tournaments';

  CollectionReference<Map<String, dynamic>>? _collection() {
    if (!AuthService().firebaseReady) return null;
    return FirebaseFirestore.instance.collection(_kCollection);
  }

  // ---------- Snapshot slice (pure — unit-testable) ----------

  /// Builds the snapshot slice for [t] from the owner's local store:
  /// the tournament, its teams, its matches, and the registered
  /// players who belong to those teams' squads.
  static TournamentSlice buildSlice(Store store, Tournament t) {
    final teams = store.teams.where((x) => t.teamIds.contains(x.id)).toList();
    final matches =
        store.matches.where((m) => m.tournamentId == t.id).toList();
    final squadIds = <String>{
      for (final team in teams)
        for (final p in team.players) p.id,
    };
    final regPlayers =
        store.regPlayers.where((r) => squadIds.contains(r.id)).toList();
    return TournamentSlice(
      tournament: t,
      teams: teams,
      matches: matches,
      regPlayers: regPlayers,
    );
  }

  static String encodeSlice(TournamentSlice slice) => jsonEncode({
        'tournament': slice.tournament.toJson(),
        'teams': slice.teams.map((t) => t.toJson()).toList(),
        'matches': slice.matches.map((m) => m.toJson()).toList(),
        'regPlayers': slice.regPlayers.map((r) => r.toJson()).toList(),
      });

  /// Decodes a snapshot string back into model objects; null when the
  /// payload is missing or corrupt (viewers simply skip such docs).
  static TournamentSlice? decodeSlice(String data) {
    if (data.isEmpty) return null;
    try {
      final j = jsonDecode(data) as Map<String, dynamic>;
      final rawTournament = j['tournament'];
      if (rawTournament is! Map<String, dynamic>) return null;
      List<T> dec<T>(String key, T Function(Map<String, dynamic>) f) {
        final raw = j[key] as List?;
        if (raw == null) return [];
        return raw.map((e) => f(e as Map<String, dynamic>)).toList();
      }

      return TournamentSlice(
        tournament: Tournament.fromJson(rawTournament),
        teams: dec('teams', Team.fromJson),
        matches: dec('matches', Match.fromJson),
        regPlayers: dec('regPlayers', RegPlayer.fromJson),
      );
    } catch (_) {
      return null;
    }
  }

  /// Builds a viewer-side [PublishedTournament] from a Firestore
  /// document; null when the document carries no readable snapshot.
  static PublishedTournament? fromDoc(String id, Map<String, dynamic> d) {
    final raw = d['data'];
    if (raw is! String) return null;
    final slice = decodeSlice(raw);
    if (slice == null) return null;
    final ts = d['updatedAt'];
    final updatedAtMs = ts is Timestamp
        ? ts.millisecondsSinceEpoch
        : (ts as num?)?.toInt() ?? 0;
    return PublishedTournament(
      id: id,
      ownerUid: d['ownerUid'] as String? ?? '',
      name: d['name'] as String? ?? slice.tournament.name,
      venue: d['venue'] as String? ?? slice.tournament.venue,
      logoBase64: d['logoBase64'] as String? ?? slice.tournament.logoBase64,
      updatedAtMs: updatedAtMs,
      slice: slice,
    );
  }

  // ---------- Owner actions ----------

  Future<String?> _writeDoc(Store store, Tournament t, String uid) async {
    final col = _collection();
    if (col == null) return 'Cloud is not available right now.';
    try {
      await col.doc(t.id).set({
        'ownerUid': uid,
        'name': t.name,
        'venue': t.venue,
        'logoBase64': t.logoBase64,
        'updatedAt': FieldValue.serverTimestamp(),
        'data': encodeSlice(buildSlice(store, t)),
      });
      _lastError = null;
      return null;
    } catch (e) {
      _lastError = e.toString();
      debugPrint('Publish write failed: $e');
      return 'Could not reach the cloud — check your internet connection.';
    }
  }

  /// Publishes [t] publicly. Returns null on success, otherwise a
  /// user-readable error. Publishing is a manual owner action and
  /// requires login — guests and logged-out users get a clear message.
  Future<String?> publish(Store store, Tournament t) async {
    final auth = AuthService();
    if (!auth.firebaseReady) {
      return 'Cloud account is not set up yet. Publishing needs the cloud.';
    }
    if (!auth.isLoggedIn) {
      return 'Log in to publish a tournament.';
    }
    final err = await _writeDoc(store, t, auth.currentUser!.uid);
    if (err != null) return err;
    t.published = true;
    await store.persist();
    return null;
  }

  /// Unpublishes [t]: deletes the public document and clears the flag.
  Future<String?> unpublish(Store store, Tournament t) async {
    String? err;
    final col = _collection();
    if (col != null && AuthService().isLoggedIn) {
      try {
        await col.doc(t.id).delete();
        _lastError = null;
      } catch (e) {
        _lastError = e.toString();
        debugPrint('Unpublish failed: $e');
        err = 'The public copy could not be removed (no internet?). '
            'It may stay visible until you unpublish again while online.';
      }
    }
    t.published = false;
    await store.persist();
    return err;
  }

  /// Fire-and-forget removal of the public document when its
  /// tournament is deleted locally, so no orphan stays searchable.
  void deletePublishedDoc(String tournamentId) {
    final col = _collection();
    if (col == null || !AuthService().isLoggedIn) return;
    col.doc(tournamentId).delete().catchError((Object e) {
      debugPrint('Published doc cleanup failed: $e');
      return null;
    });
  }

  /// Called from Store.persist(). While any of the owner's tournaments
  /// is published, its snapshot is re-pushed debounced — the same
  /// pattern as cloud sync. No-op for guests / logged-out users.
  void scheduleRepublish(Store store) {
    final auth = AuthService();
    if (!auth.firebaseReady || !auth.isLoggedIn) return;
    if (!store.tournaments.any((t) => t.published)) return;
    _republishTimer?.cancel();
    _republishTimer =
        Timer(const Duration(seconds: 5), () => _republishAll(store));
  }

  Future<void> _republishAll(Store store) async {
    final auth = AuthService();
    if (!auth.isLoggedIn) return;
    final uid = auth.currentUser!.uid;
    for (final t in store.tournaments.where((t) => t.published)) {
      await _writeDoc(store, t, uid);
    }
  }

  // ---------- Viewer reads (public — guests included) ----------

  List<PublishedTournament> _decodeSnap(
      QuerySnapshot<Map<String, dynamic>> snap) {
    final out = <PublishedTournament>[];
    for (final d in snap.docs) {
      final p = fromDoc(d.id, d.data());
      if (p != null) out.add(p);
    }
    out.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  /// One-shot fetch of every published tournament.
  Future<List<PublishedTournament>> fetchPublished() async {
    final col = _collection();
    if (col == null) return [];
    return _decodeSnap(await col.get());
  }

  /// Live list of published tournaments (updates as owners re-push).
  Stream<List<PublishedTournament>> watchPublished() {
    final col = _collection();
    if (col == null) return Stream.value(const []);
    return col.snapshots().map(_decodeSnap);
  }

  /// Live view of one published tournament (live scores while open).
  Stream<PublishedTournament?> watchOne(String tournamentId) {
    final col = _collection();
    if (col == null) return Stream.value(null);
    return col.doc(tournamentId).snapshots().map((snap) {
      final data = snap.data();
      if (!snap.exists || data == null) return null;
      return fromDoc(snap.id, data);
    });
  }
}
