// Backup service for 60Score (§31).
// Pure backup logic — no widgets. Every IO call is guarded; nothing here
// throws to the UI. Backups are versioned JSON snapshots of Store.exportJson().
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'store.dart';

/// Max automatic backups kept on device (§31: keep the last 14).
const kMaxAutoBackups = 14;

/// Minimum gap between automatic backups (§31: daily).
const kAutoBackupInterval = Duration(hours: 20);

String _stamp(DateTime t) {
  String p2(int v) => v.toString().padLeft(2, '0');
  return '${t.year}${p2(t.month)}${p2(t.day)}_${p2(t.hour)}${p2(t.minute)}${p2(t.second)}';
}

Future<Directory?> _autoDir() async {
  try {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/auto_backups');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  } catch (_) {
    return null;
  }
}

DateTime _mtime(FileSystemEntity e) {
  try {
    return e.statSync().modified;
  } catch (_) {
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
}

List<File> _jsonFiles(Directory dir) {
  try {
    return dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.json'))
        .toList();
  } catch (_) {
    return [];
  }
}

/// Runs the daily automatic backup (§31). Keeps the last 14 auto-backups.
/// Skips when a backup was already made in the last 20 hours.
Future<void> runDailyAutoBackup(Store store) async {
  try {
    final dir = await _autoDir();
    if (dir == null) return;
    final files = _jsonFiles(dir);
    files.sort((a, b) => _mtime(b).compareTo(_mtime(a)));
    if (files.isNotEmpty &&
        DateTime.now().difference(_mtime(files.first)) <
            kAutoBackupInterval) {
      return; // already backed up recently
    }
    final path = '${dir.path}/60score_auto_${_stamp(DateTime.now())}.json';
    await File(path).writeAsString(jsonEncode(store.exportJson()));
    final all = _jsonFiles(dir);
    all.sort((a, b) => _mtime(b).compareTo(_mtime(a)));
    for (var i = kMaxAutoBackups; i < all.length; i++) {
      try {
        await all[i].delete();
      } catch (_) {}
    }
  } catch (_) {}
}

/// Writes one timestamped backup file. Returns its path, or '' on failure.
Future<String> manualBackup(Store store) async {
  try {
    final dir = await _autoDir();
    if (dir == null) return '';
    final path = '${dir.path}/60score_manual_${_stamp(DateTime.now())}.json';
    await File(path).writeAsString(jsonEncode(store.exportJson()));
    return path;
  } catch (_) {
    return '';
  }
}

/// Lists backup files, newest first. Empty list when unavailable.
Future<List<FileSystemEntity>> listBackups() async {
  try {
    final dir = await _autoDir();
    if (dir == null) return [];
    final files = _jsonFiles(dir).cast<FileSystemEntity>();
    files.sort((a, b) => _mtime(b).compareTo(_mtime(a)));
    return files;
  } catch (_) {
    return [];
  }
}

/// Restores a backup file by MERGING (§31): same-id records are replaced,
/// new records are added, nothing is deleted. Returns per-entity counts.
Future<Map<String, int>> restoreBackup(Store store, String path) async {
  try {
    final raw = await File(path).readAsString();
    final data = jsonDecode(raw) as Map<String, dynamic>;
    if (data['app'] != '60Score') return {};
    return await store.importJson(data, merge: true);
  } catch (_) {
    return {};
  }
}

/// Copies a backup into the device Downloads folder.
/// Returns the file path, or null when Downloads is unavailable.
Future<String?> exportToDownloads(Store store) async {
  try {
    final dir = await getDownloadsDirectory();
    if (dir == null) return null;
    final path = '${dir.path}/60score_backup_${_stamp(DateTime.now())}.json';
    await File(path).writeAsString(jsonEncode(store.exportJson()));
    return path;
  } catch (_) {
    return null;
  }
}
