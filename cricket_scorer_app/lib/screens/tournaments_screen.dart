// Tournaments list: view all tournaments, add new, edit names, delete.
// Every tournament is user-created data — the app seeds nothing.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../auth_service.dart';
import '../models.dart';
import '../publish_service.dart';
import '../store.dart';
import '../theme.dart';
import 'published_search_screen.dart';
import 'scorer_home_screen.dart';

/// Create/edit tournament dialog (name, venue, optional logo).
///
/// Shared by the Tournaments screen and the New Match setup flow
/// (v1.2.2 "New Tournament" option). Returns the saved tournament, or
/// null when cancelled or the name is empty. Nothing is created until
/// the user taps Save.
Future<Tournament?> showTournamentEditDialog(
  BuildContext context,
  Store store,
  Tournament? existing,
) async {
  final nameCtrl = TextEditingController(text: existing?.name ?? '');
  final venueCtrl = TextEditingController(text: existing?.venue ?? '');
  var logoBase64 = existing?.logoBase64 ?? '';

  Future<void> pickLogo(StateSetter setD) async {
    final picker = ImagePicker();
    final img = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 75,
    );
    if (img != null) {
      final bytes = await img.readAsBytes();
      setD(() => logoBase64 = base64Encode(bytes));
    }
  }

  final saved = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setD) => AlertDialog(
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
              const SizedBox(height: 12),
              // Optional tournament logo (shown on the match summary).
              Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: kPanel2,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: kCyan.withValues(alpha: 0.25),
                      ),
                    ),
                    child: logoBase64.isEmpty
                        ? const Icon(
                            Icons.emoji_events_outlined,
                            color: Colors.white54,
                          )
                        : Image.memory(
                            base64Decode(logoBase64),
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const Icon(
                              Icons.emoji_events_outlined,
                              color: Colors.white54,
                            ),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Tournament logo (optional)',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Row(
                          children: [
                            TextButton(
                              onPressed: () => pickLogo(setD),
                              child: Text(
                                logoBase64.isEmpty ? 'Add' : 'Change',
                              ),
                            ),
                            if (logoBase64.isNotEmpty)
                              TextButton(
                                onPressed: () =>
                                    setD(() => logoBase64 = ''),
                                child: const Text('Remove'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
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
    ),
  );
  if (saved != true || nameCtrl.text.trim().isEmpty) return null;
  if (existing == null) {
    final t = Tournament(
      id: Store.newId('tournament'),
      name: nameCtrl.text.trim(),
      teamIds: [],
      venue: venueCtrl.text.trim(),
      logoBase64: logoBase64,
    );
    await store.upsertTournament(t);
    return t;
  }
  existing.name = nameCtrl.text.trim();
  existing.venue = venueCtrl.text.trim();
  existing.logoBase64 = logoBase64;
  await store.persist();
  return existing;
}

/// One tournament row in the list (extracted so the layout is
/// widget-testable). Layout rule (v1.3.2, bug #R2): the name owns an
/// Expanded column — up to 2 lines with ellipsis — while the
/// Published badge sits ABOVE the compact action buttons in the
/// right-hand column, so badge + actions can never squeeze the name
/// into one letter per line on a narrow phone.
class TournamentCard extends StatelessWidget {
  final Tournament tournament;
  final int teamCount;
  final int matchCount;
  final bool loggedIn;
  final VoidCallback onTap;
  final VoidCallback onTogglePublish;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const TournamentCard({
    super.key,
    required this.tournament,
    required this.teamCount,
    required this.matchCount,
    required this.loggedIn,
    required this.onTap,
    required this.onTogglePublish,
    required this.onEdit,
    required this.onDelete,
  });

  Widget _actionButton({
    required Widget icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: 36,
      height: 36,
      child: IconButton(
        icon: icon,
        tooltip: tooltip,
        iconSize: 20,
        padding: EdgeInsets.zero,
        onPressed: onPressed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = tournament;
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              const CircleAvatar(
                backgroundColor: kPanel2,
                child: Icon(Icons.emoji_events, color: kCyan),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${t.venue.isEmpty ? "No venue" : t.venue} • '
                      '$teamCount teams • $matchCount matches',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (t.published) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: kGreen.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: kGreen.withValues(alpha: 0.5)),
                      ),
                      child: const Text(
                        'Published',
                        style: TextStyle(
                          color: kGreen,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                  ],
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (loggedIn)
                        _actionButton(
                          icon: Icon(
                            t.published ? Icons.public : Icons.public_off,
                            color: t.published ? kGreen : null,
                          ),
                          tooltip: t.published
                              ? 'Unpublish'
                              : 'Publish (public, view-only)',
                          onPressed: onTogglePublish,
                        ),
                      _actionButton(
                        icon: const Icon(Icons.edit),
                        tooltip: 'Rename',
                        onPressed: onEdit,
                      ),
                      _actionButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: kRed,
                        ),
                        tooltip: 'Delete',
                        onPressed: onDelete,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
    AuthService().addListener(_onChanged);
  }

  @override
  void dispose() {
    store.removeListener(_onChanged);
    AuthService().removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _editTournament(Tournament? existing) async {
    final t = await showTournamentEditDialog(context, store, existing);
    if (t != null && mounted) setState(() {});
  }

  /// Publish / unpublish (owner only, login required). Publishing is
  /// always this manual tap — nothing is ever published automatically.
  Future<void> _togglePublish(Tournament t) async {
    final wasPublished = t.published;
    final svc = PublishService();
    final err = wasPublished
        ? await svc.unpublish(store, t)
        : await svc.publish(store, t);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          err ??
              (wasPublished
                  ? 'Unpublished — it no longer appears in Search.'
                  : 'Published — anyone can find it in Search '
                      '(view-only).'),
        ),
      ),
    );
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
      if (t.published) PublishService().deletePublishedDoc(t.id);
      await store.deleteTournament(t.id);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final tournaments = store.tournaments;
    final loggedIn = AuthService().isLoggedIn;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tournaments'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search published tournaments',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const PublishedSearchScreen(),
              ),
            ),
          ),
        ],
      ),
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
                final teamCount = t.teamIds.length;
                final matchCount = store.matches
                    .where((m) => m.tournamentId == t.id)
                    .length;
                return TournamentCard(
                  tournament: t,
                  teamCount: teamCount,
                  matchCount: matchCount,
                  loggedIn: loggedIn,
                  onTogglePublish: () => _togglePublish(t),
                  onEdit: () => _editTournament(t),
                  onDelete: () => _deleteTournament(t),
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
                );
              },
            ),
    );
  }
}
