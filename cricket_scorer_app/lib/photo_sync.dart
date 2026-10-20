// Player-photo cloud transport for 60Score.
//
// Player photos live on the player record itself as `photoBase64`
// (a base64 JPEG, already picked at max 512px / quality 75 in the UI).
// The canonical record is the Registered Player ([RegPlayer]); team
// squad copies share the same player id and are kept in sync by the
// app (see Store.photoForPlayer / applyDraftToTeams).
//
// Photos do NOT travel inside the main backup document
// (users/{uid}/backup/app_data): a dozen photos would push that single
// document past Firestore's 1 MiB limit and break the whole backup.
// Instead each photo is its own document:
//
//   users/{uid}/photos/{playerId}
//     data:      base64 string of the compressed JPEG
//     updatedAt: int, ms epoch of the upload
//
// Push (after the main backup push): every registered player whose
// photo changed since it was last uploaded gets its photo doc written.
// Change detection uses a per-player FNV-1a hash of the local photo
// bytes, remembered in SharedPreferences (score60_photo_sync_v1) —
// photos are never re-uploaded when nothing changed. If the user
// removed a photo in the app, the cloud copy is deleted so a fresh
// device does not resurrect it; nothing on any device is ever deleted.
//
// Pull (after the main backup pull): photo docs newer than the version
// this device last applied are written onto the registered record and
// its team-squad copies. Local data is never removed by a pull.
//
// Firestore rules need (in addition to the backup rule):
//   match /users/{uid}/photos/{photoId} {
//     allow read, write: if request.auth != null
//         && request.auth.uid == uid;
//   }
//
// Everything here is fire-and-forget safe: failures are swallowed and
// the app keeps working offline, exactly like SyncService.
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import 'store.dart';

class PhotoSync {
  PhotoSync._();

  /// Longest side (px) of an uploaded photo.
  static const int maxDimension = 512;

  /// JPEG quality used when re-encoding a photo for upload.
  static const int jpegQuality = 80;

  /// Largest raw byte size uploaded. ~700 KB keeps the base64 document
  /// field comfortably under Firestore's 1 MiB document limit.
  static const int maxUploadBytes = 700000;

  /// SharedPreferences key holding the per-player sync tracker:
  /// { playerId: { 'h': hashHex, 'at': cloudUpdatedAtMs } }.
  static const String trackerKey = 'score60_photo_sync_v1';

  // ---------- pure helpers (unit tested) ----------

  /// FNV-1a 64-bit hash of [bytes], as 16 lowercase hex characters.
  /// Only used to notice that a photo changed — not for security.
  static String hashBytes(List<int> bytes) {
    var hash = 0xcbf29ce484222325;
    for (final b in bytes) {
      hash ^= b;
      hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    // Format as two masked 32-bit halves: int.toUnsigned(64) is not
    // reliable for the sign bit in every Dart runtime.
    final hi = (hash >> 32) & 0xFFFFFFFF;
    final lo = hash & 0xFFFFFFFF;
    return '${hi.toRadixString(16).padLeft(8, '0')}'
        '${lo.toRadixString(16).padLeft(8, '0')}';
  }

  /// Decodes [bytes], shrinks the image so its longest side is at most
  /// [maxDimension], and re-encodes it as JPEG at [jpegQuality].
  /// Returns null when [bytes] are not a decodable image.
  static Uint8List? compressPhoto(List<int> bytes) {
    try {
      final decoded = img.decodeImage(Uint8List.fromList(bytes));
      if (decoded == null) return null;
      var out = decoded;
      final longest =
          decoded.width > decoded.height ? decoded.width : decoded.height;
      if (longest > maxDimension) {
        out = decoded.width >= decoded.height
            ? img.copyResize(decoded, width: maxDimension)
            : img.copyResize(decoded, height: maxDimension);
      }
      return img.encodeJpg(out, quality: jpegQuality);
    } catch (_) {
      return null;
    }
  }

  /// Returns a copy of a team/registered-player JSON map with every
  /// `photoBase64` blanked (including nested team `players`), so the
  /// main backup document carries no photo payloads. The input map is
  /// not mutated.
  static Map<String, dynamic> stripPhotos(Map<String, dynamic> json) {
    final copy = Map<String, dynamic>.from(json);
    if (copy.containsKey('photoBase64')) copy['photoBase64'] = '';
    final players = copy['players'];
    if (players is List) {
      copy['players'] = players.map((p) {
        if (p is Map) {
          final pc = Map<String, dynamic>.from(p);
          if (pc.containsKey('photoBase64')) pc['photoBase64'] = '';
          return pc;
        }
        return p;
      }).toList();
    }
    return copy;
  }

  // ---------- tracker (SharedPreferences) ----------

  static Future<Map<String, Map<String, dynamic>>> _loadTracker() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(trackerKey);
      if (raw == null || raw.isEmpty) return {};
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map(
        (k, v) => MapEntry(k, Map<String, dynamic>.from(v as Map)),
      );
    } catch (_) {
      return {};
    }
  }

  static Future<void> _saveTracker(
      Map<String, Map<String, dynamic>> tracker) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(trackerKey, jsonEncode(tracker));
    } catch (_) {
      // Tracker persistence is best-effort; a lost tracker only means
      // photos get compared (and possibly re-uploaded) next time.
    }
  }

  // ---------- push ----------

  /// Uploads every registered player's photo that changed since it was
  /// last uploaded, and removes cloud copies of photos the user removed
  /// in the app. Never throws.
  static Future<void> pushPhotos(
      CollectionReference<Map<String, dynamic>> photos, Store store) async {
    try {
      final tracker = await _loadTracker();
      var trackerDirty = false;
      for (final reg in store.regPlayers) {
        final local = reg.photoBase64;
        if (local.isEmpty) {
          // The user removed this photo in the app: drop the cloud copy
          // so it cannot reappear on a fresh device. Local data on any
          // device is left alone.
          if (tracker.containsKey(reg.id)) {
            try {
              await photos.doc(reg.id).delete();
            } catch (_) {
              // A failed delete just leaves a stale cloud copy behind.
            }
            tracker.remove(reg.id);
            trackerDirty = true;
          }
          continue;
        }
        final List<int> bytes;
        try {
          bytes = base64Decode(local);
        } catch (_) {
          continue; // corrupt local value — leave sync state untouched
        }
        final hash = hashBytes(bytes);
        if (tracker[reg.id]?['h'] == hash) continue; // already uploaded
        final compressed = compressPhoto(bytes);
        // Undecodable bytes are sent as-is when small enough; anything
        // too large for one Firestore document is skipped, not fatal.
        final upload = compressed ?? bytes;
        if (upload.length > maxUploadBytes) {
          debugPrint('PhotoSync: oversized photo skipped for ${reg.id}');
          continue;
        }
        try {
          final now = DateTime.now().millisecondsSinceEpoch;
          await photos.doc(reg.id).set({
            'data': base64Encode(upload),
            'updatedAt': now,
          });
          tracker[reg.id] = {'h': hash, 'at': now};
          trackerDirty = true;
        } catch (e) {
          debugPrint('PhotoSync: upload failed for ${reg.id}: $e');
        }
      }
      if (trackerDirty) await _saveTracker(tracker);
    } catch (e) {
      debugPrint('PhotoSync push failed: $e');
    }
  }

  // ---------- pull ----------

  /// Applies cloud photos that are newer than the version this device
  /// last saw, onto the registered record and its team-squad copies.
  /// Returns true when at least one photo was applied. Local photos are
  /// never removed. Never throws.
  static Future<bool> pullPhotos(
      CollectionReference<Map<String, dynamic>> photos, Store store) async {
    var applied = false;
    try {
      final snap = await photos.get();
      if (snap.docs.isEmpty) return false;
      final tracker = await _loadTracker();
      var trackerDirty = false;
      for (final doc in snap.docs) {
        // Only sync photos of players present in the registered list.
        final reg = store.regById(doc.id);
        if (reg == null) continue;
        final data = doc.data();
        final b64 = data['data'] as String?;
        final at = (data['updatedAt'] as num?)?.toInt() ?? 0;
        if (b64 == null || b64.isEmpty || at <= 0) continue;
        final knownAt = (tracker[doc.id]?['at'] as num?)?.toInt() ?? 0;
        if (at <= knownAt) continue; // this cloud version already applied
        final List<int> bytes;
        try {
          bytes = base64Decode(b64);
        } catch (_) {
          continue;
        }
        reg.photoBase64 = b64;
        for (final team in store.teams) {
          for (final p in team.players) {
            if (p.id == doc.id) p.photoBase64 = b64;
          }
        }
        tracker[doc.id] = {'h': hashBytes(bytes), 'at': at};
        trackerDirty = true;
        applied = true;
      }
      if (trackerDirty) await _saveTracker(tracker);
    } catch (e) {
      debugPrint('PhotoSync pull failed: $e');
    }
    return applied;
  }
}
