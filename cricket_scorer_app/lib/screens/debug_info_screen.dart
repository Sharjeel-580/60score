// Debug info screen (v1.4.3): read-only facts for reporting a
// crash — app version, last captured error, data size, sync
// status. It changes nothing; it only shows.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../debug_info.dart';
import '../store.dart';
import '../sync_service.dart';

class DebugInfoScreen extends StatefulWidget {
  final Store store;
  const DebugInfoScreen({super.key, required this.store});

  @override
  State<DebugInfoScreen> createState() => _DebugInfoScreenState();
}

class _DebugInfoScreenState extends State<DebugInfoScreen> {
  late final int _matchesJsonBytes;
  String? _error;
  DateTime? _errorAt;

  @override
  void initState() {
    super.initState();
    // Stored-size snapshot: the same JSON the backup stores.
    _matchesJsonBytes = jsonEncode(
      widget.store.matches.map((m) => m.toJson()).toList(),
    ).length;
    _error = DebugInfo.lastError;
    _errorAt = DebugInfo.lastErrorAt;
    // A crash in a previous launch left its error in prefs; show
    // it when this launch has not recorded one yet.
    unawaited(DebugInfo.loadPersisted().then((_) {
      if (!mounted) return;
      setState(() {
        _error = DebugInfo.lastError;
        _errorAt = DebugInfo.lastErrorAt;
      });
    }));
  }

  String _kb(int bytes) => '${(bytes / 1024).toStringAsFixed(1)} KB';

  @override
  Widget build(BuildContext context) {
    final sync = SyncService();
    final lastSync = sync.lastSyncAt;
    final syncError = sync.lastError;
    return Scaffold(
      appBar: AppBar(title: const Text('Debug info')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('App version'),
            subtitle: Text(kAppVersion),
          ),
          ListTile(
            leading: const Icon(Icons.sports_cricket),
            title: const Text('Matches stored'),
            subtitle: Text('${widget.store.matches.length}'),
          ),
          ListTile(
            leading: const Icon(Icons.storage_outlined),
            title: const Text('Stored matches size'),
            subtitle: Text(
              '${_kb(_matchesJsonBytes)} '
              '($_matchesJsonBytes bytes)',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.sync),
            title: const Text('Last sync'),
            subtitle: Text(
              lastSync == null
                  ? 'Never'
                  : lastSync.toString(),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.sync_problem_outlined),
            title: const Text('Sync status'),
            subtitle: Text(syncError ?? 'OK'),
          ),
          const Divider(),
          const ListTile(
            leading: Icon(Icons.bug_report_outlined),
            title: Text('Last captured error'),
            subtitle: Text(
              'Long-press to copy it when reporting a crash.',
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                _error == null
                    ? 'No error recorded.'
                    : (_errorAt == null
                        ? _error!
                        : '$_errorAt\n$_error'),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Ye screen sirf maloomat dikhati hai — kuch badalti nahi.',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
