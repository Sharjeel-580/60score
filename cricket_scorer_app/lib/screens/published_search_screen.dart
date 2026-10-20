// Search Tournaments (v1.3.0) — find published tournaments by name,
// follow them, and open a read-only live view. Public read: guests can
// search, view and follow without an account. The list streams from
// Firestore, so followed tournaments update live while this screen is
// open.
import 'package:flutter/material.dart';

import '../auth_service.dart';
import '../publish_service.dart';
import '../theme.dart';
import 'published_tournament_screen.dart';

class PublishedSearchScreen extends StatefulWidget {
  const PublishedSearchScreen({super.key});

  @override
  State<PublishedSearchScreen> createState() =>
      _PublishedSearchScreenState();
}

class _PublishedSearchScreenState extends State<PublishedSearchScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  List<String> _followIds = [];

  @override
  void initState() {
    super.initState();
    _loadFollows();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadFollows() async {
    final ids = await FollowStore.load();
    if (!mounted) return;
    setState(() => _followIds = ids);
  }

  Future<void> _toggleFollow(String id) async {
    final ids = [..._followIds];
    if (ids.contains(id)) {
      ids.remove(id);
    } else {
      ids.add(id);
    }
    await FollowStore.save(ids);
    if (!mounted) return;
    setState(() => _followIds = ids);
  }

  bool _matchesQuery(PublishedTournament p) {
    final q = _query.trim().toLowerCase();
    return q.isEmpty || p.name.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Search Tournaments')),
      body: AnimatedBuilder(
        animation: AuthService(),
        builder: (context, _) {
          if (!AuthService().firebaseReady) {
            return const EmptyState(
              icon: Icons.cloud_off,
              title: 'Search unavailable',
              subtitle:
                  'Published tournaments live in the cloud. Check your '
                  'connection, or try again once the app has connected.',
            );
          }
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: 'Search published tournaments…',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _query = '');
                            },
                          ),
                  ),
                ),
              ),
              Expanded(child: _results()),
            ],
          );
        },
      ),
    );
  }

  Widget _results() {
    return StreamBuilder<List<PublishedTournament>>(
      stream: PublishService().watchPublished(),
      builder: (context, snap) {
        if (snap.hasError) {
          return const EmptyState(
            icon: Icons.cloud_off,
            title: 'Could not load tournaments',
            subtitle:
                'Check your internet connection and try again.',
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final all = snap.data!;
        if (all.isEmpty) {
          return const EmptyState(
            icon: Icons.emoji_events_outlined,
            title: 'No published tournaments yet',
            subtitle:
                'When an organizer publishes a tournament, it shows '
                'up here.',
          );
        }
        final following = all
            .where((p) => _followIds.contains(p.id) && _matchesQuery(p))
            .toList();
        final others = all
            .where((p) => !_followIds.contains(p.id) && _matchesQuery(p))
            .toList();
        if (following.isEmpty && others.isEmpty) {
          return const EmptyState(
            icon: Icons.search_off,
            title: 'No matches',
            subtitle:
                'No published tournament matches your search.',
          );
        }
        return ListView(
          padding: const EdgeInsets.only(bottom: 12),
          children: [
            if (following.isNotEmpty) ...[
              const SectionHeader('Following'),
              for (final p in following) _row(p),
            ],
            if (others.isNotEmpty) ...[
              SectionHeader(
                following.isEmpty
                    ? 'All published tournaments'
                    : 'More tournaments',
              ),
              for (final p in others) _row(p),
            ],
          ],
        );
      },
    );
  }

  Widget _row(PublishedTournament p) {
    final followed = _followIds.contains(p.id);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        leading: PublishedLogo(logoBase64: p.logoBase64, size: 44),
        title: Text(p.name),
        subtitle: Text(p.venue.isEmpty ? 'Venue TBD' : p.venue),
        trailing: IconButton(
          icon: Icon(
            followed ? Icons.bookmark : Icons.bookmark_border,
            color: followed ? kGold : null,
          ),
          tooltip: followed
              ? 'Following — tap to unfollow'
              : 'Follow for live updates',
          onPressed: () => _toggleFollow(p.id),
        ),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PublishedTournamentScreen(
                tournamentId: p.id,
                initial: p,
              ),
            ),
          );
          // The follow state may have changed inside the view.
          await _loadFollows();
        },
      ),
    );
  }
}
