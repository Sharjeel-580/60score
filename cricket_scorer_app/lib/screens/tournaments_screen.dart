// Tournaments list: view all tournaments, add new, edit names, delete.
// The default tournament (Super Sixty League) stays, but users can manage
// their own tournaments freely.
import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import 'scorer_home_screen.dart';

class TournamentsScreen extends StatefulWidget {
  final Store store;
  const TournamentsScreen({super.key, required this.store});

  @override
  State<TournamentsScreen> createState() => _TournamentsScreenState();
}

class _TournamentsScreenState extends State<TournamentsScreen> {
  Store get store => widget.store;

  @override
  void initState() {
    super.initState();
    store.addListener(_onChanged);
  }

  @override
  void dispose() {
    store.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _editTournament(Tournament? existing) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final venueCtrl = TextEditingController(text: existing?.venue ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(existing == null ? 'New tournament' : 'Edit tournament'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Tournament name *',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: venueCtrl,
                decoration: const InputDecoration(
                  labelText: 'Venue (optional)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved == true && nameCtrl.text.trim().isNotEmpty) {
      if (existing == null) {
        final t = Tournament(
          id: Store.newId('tournament'),
          name: nameCtrl.text.trim(),
          teamIds: [],
          venue: venueCtrl.text.trim(),
        );
        await store.upsertTournament(t);
      } else {
        existing.name = nameCtrl.text.trim();
        existing.venue = venueCtrl.text.trim();
        await store.persist();
      }
      if (mounted) setState(() {});
    }
  }

  Future<void> _deleteTournament(Tournament t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete tournament?'),
        content: Text(
          'Delete "${t.name}"? Its fixtures and matches will remain, '
          'but will no longer be linked to a tournament.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kRed),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await store.deleteTournament(t.id);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final tournaments = store.tournaments;
    return Scaffold(
      appBar: AppBar(title: const Text('Tournaments')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editTournament(null),
        icon: const Icon(Icons.add),
        label: const Text('New tournament'),
      ),
      body: tournaments.isEmpty
          ? const Center(
              child: Text(
                'No tournaments yet.\nTap + to create one.',
                textAlign: TextAlign.center,
              ),
            )
          : ListView.builder(
              itemCount: tournaments.length,
              itemBuilder: (context, i) {
                final t = tournaments[i];
                final isDefault = t.id == Store.defaultTournamentId;
                final teamCount = t.teamIds.length;
                final matchCount = store.matches
                    .where((m) => m.tournamentId == t.id)
                    .length;
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor:
                          isDefault ? kGold.withOpacity(0.25) : kPanel2,
                      child: Icon(
                        Icons.emoji_events,
                        color: isDefault ? kGold : kCyan,
                      ),
                    ),
                    title: Row(
                      children: [
                        Expanded(child: Text(t.name)),
                        if (isDefault)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: kGold.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text(
                              'DEFAULT',
                              style: TextStyle(
                                fontSize: 10,
                                color: kGold,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    subtitle: Text(
                      '${t.venue.isEmpty ? "No venue" : t.venue} • '
                      '$teamCount teams • $matchCount matches',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, size: 20),
                          tooltip: 'Rename',
                          onPressed: () => _editTournament(t),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            size: 20,
                            color: kRed,
                          ),
                          tooltip: 'Delete',
                          onPressed: () => _deleteTournament(t),
                        ),
                      ],
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TournamentDetailScreen(
                          store: store,
                          tournament: t,
                        ),
                      ),
                    ).then((_) {
                      if (mounted) setState(() {});
                    }),
                  ),
                );
              },
            ),
    );
  }
}
