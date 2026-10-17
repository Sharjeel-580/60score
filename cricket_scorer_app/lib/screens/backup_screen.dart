// Backup & Restore screen (§31). Manual backups, export to Downloads,
// automatic-backup listing, and merge-style restore.
import 'package:flutter/material.dart';

import '../backup_service.dart';
import '../store.dart';
import '../theme.dart';

class _BackupRow {
  final String path;
  final String name;
  final DateTime modified;
  final int size;
  _BackupRow({
    required this.path,
    required this.name,
    required this.modified,
    required this.size,
  });
}

String _fmtSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String _fmtDate(DateTime t) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  String p2(int v) => v.toString().padLeft(2, '0');
  return '${t.day} ${months[t.month - 1]} ${t.year}, ${p2(t.hour)}:${p2(t.minute)}';
}

class BackupScreen extends StatefulWidget {
  final Store store;
  const BackupScreen({super.key, required this.store});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  Future<List<_BackupRow>>? _rowsFuture;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _rowsFuture = _loadRows();
  }

  Future<List<_BackupRow>> _loadRows() async {
    final entities = await listBackups();
    final rows = <_BackupRow>[];
    for (final e in entities) {
      try {
        final st = await e.stat();
        rows.add(
          _BackupRow(
            path: e.path,
            name: e.path.split('/').last,
            modified: st.modified,
            size: st.size,
          ),
        );
      } catch (_) {}
    }
    return rows;
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  Future<void> _doManualBackup() async {
    setState(() => _busy = true);
    final path = await manualBackup(widget.store);
    setState(() {
      _busy = false;
      _reload();
    });
    if (path.isEmpty) {
      _snack('Backup failed — storage unavailable');
    } else {
      _snack('Backup saved: $path');
    }
  }

  Future<void> _doExportDownloads() async {
    setState(() => _busy = true);
    final path = await exportToDownloads(widget.store);
    setState(() => _busy = false);
    if (path == null) {
      _snack('Downloads not available on this device');
    } else {
      _snack('Exported to Downloads: $path');
    }
  }

  Future<void> _confirmRestore(_BackupRow row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Restore this backup?'),
        content: const Text(
          'Restore merges with current data — nothing is deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted) return;
    setState(() => _busy = true);
    final counts = await restoreBackup(widget.store, row.path);
    setState(() {
      _busy = false;
      _reload();
    });
    if (counts.isEmpty) {
      _snack('Restore failed — invalid backup file');
    } else {
      final summary = counts.entries
          .map((e) => '${e.value} ${e.key}')
          .join(', ');
      _snack('Restored: $summary');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & Restore')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          const SectionHeader('Backup now'),
          ScoreCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ScoreButton(
                  label: 'Create backup',
                  icon: Icons.backup,
                  onPressed: _busy ? null : _doManualBackup,
                ),
                const SizedBox(height: 10),
                ScoreButton(
                  label: 'Export to Downloads',
                  icon: Icons.download,
                  kind: ScoreButtonKind.ghost,
                  onPressed: _busy ? null : _doExportDownloads,
                ),
              ],
            ),
          ),
          const SectionHeader('Automatic backups'),
          const Text(
            'Daily, keeps last 14.',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 8),
          FutureBuilder<List<_BackupRow>>(
            future: _rowsFuture,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final rows = snap.data ?? [];
              if (rows.isEmpty) {
                return const EmptyState(
                  icon: Icons.cloud_off,
                  title: 'No backups yet',
                  subtitle: 'Create your first backup with the button above.',
                );
              }
              return ScoreCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < rows.length; i++) ...[
                      ListTile(
                        leading: const Icon(
                          Icons.archive,
                          color: kTeal,
                        ),
                        title: Text(
                          rows[i].name,
                          style: const TextStyle(
                            color: kWhite,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          '${_fmtDate(rows[i].modified)} · ${_fmtSize(rows[i].size)}',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                        trailing: const Icon(
                          Icons.restore,
                          color: kCyan,
                        ),
                        onTap: () => _confirmRestore(rows[i]),
                      ),
                      if (i < rows.length - 1) const Divider(height: 1),
                    ],
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          const Text(
            'Restore merges — nothing is deleted.',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
