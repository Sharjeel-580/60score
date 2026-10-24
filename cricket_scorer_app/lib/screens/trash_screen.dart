// Trash screen (Feature 1 — Trash + Restore): soft-deleted
// matches, teams and tournaments, grouped by kind, with Restore
// and Permanent Delete per item.
//
// Restore re-inserts the snapshot through the Store's upsert path
// (admin restore — the tombstone is cleared). Permanent Delete
// drops only the snapshot; the tombstone recorded at delete time
// stays, so the record stays deleted everywhere.
//
// Records deleted before this feature existed have no snapshot
// and cannot be restored — they simply never appear here.
import 'package:flutter/material.dart';

import '../entity_sync.dart';
import '../store.dart';
import '../theme.dart';

String _fmtDeleted(DateTime t) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  String p2(int v) => v.toString().padLeft(2, '0');
  return '${t.day} ${months[t.month - 1]} ${t.year}, '
      '${p2(t.hour)}:${p2(t.minute)}';
}

class TrashScreen extends StatefulWidget {
  final Store store;
  const TrashScreen({super.key, required this.store});

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  Future<void> _restore(TrashEntry entry) async {
    await widget.store.restoreFromTrash(entry.kind, entry.id);
    _snack('Restored: ${entry.name}');
  }

  Future<void> _confirmPermanentDelete(TrashEntry entry) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Permanently delete?'),
        content: Text(
          '"${entry.name}" will be removed from Trash forever. '
          'This cannot be undone — the record cannot be restored '
          'after this.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            style: FilledButton.styleFrom(backgroundColor: kRed),
            child: const Text('Delete forever'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await widget.store.permanentlyDeleteFromTrash(entry.kind, entry.id);
    _snack('Permanently deleted: ${entry.name}');
  }

  Widget _group(String title, IconData icon, List<TrashEntry> entries) {
    if (entries.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(icon: icon, title: title),
        ScoreCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < entries.length; i++) ...[
                ListTile(
                  leading: Icon(icon, color: kCyan),
                  title: Text(
                    entries[i].name,
                    style: const TextStyle(color: kWhite),
                  ),
                  subtitle: Text(
                    'Deleted ${_fmtDeleted(DateTime.fromMillisecondsSinceEpoch(entries[i].deletedAt))}',
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Restore',
                        icon: const Icon(Icons.restore, color: kGreen),
                        onPressed: () => _restore(entries[i]),
                      ),
                      IconButton(
                        tooltip: 'Delete permanently',
                        icon:
                            const Icon(Icons.delete_forever, color: kRed),
                        onPressed: () =>
                            _confirmPermanentDelete(entries[i]),
                      ),
                    ],
                  ),
                ),
                if (i < entries.length - 1) const Divider(height: 1),
              ],
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trash')),
      body: AnimatedBuilder(
        animation: widget.store,
        builder: (context, _) {
          final entries = widget.store.trashEntries;
          if (entries.isEmpty) {
            return const Center(
              child: EmptyState(
                icon: Icons.delete_sweep_outlined,
                title: 'Trash is empty',
                subtitle:
                    'Deleted matches, teams and tournaments will appear here.',
              ),
            );
          }
          final matches = entries
              .where((e) => e.kind == EntityKind.matches)
              .toList();
          final teams =
              entries.where((e) => e.kind == EntityKind.teams).toList();
          final tournaments = entries
              .where((e) => e.kind == EntityKind.tournaments)
              .toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 8, 4, 2),
                child: Text(
                  'Restore brings a record back exactly as it was. '
                  'Permanent delete removes the saved copy forever — '
                  'the record itself stays deleted.',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ),
              _group('Matches', Icons.sports_cricket, matches),
              _group('Teams', Icons.groups_outlined, teams),
              _group('Tournaments', Icons.emoji_events_outlined,
                  tournaments),
            ],
          );
        },
      ),
    );
  }
}
