// Completed matches archive (v1.3.5).
//
// Home's "Recent Matches" opens THIS list — every completed match,
// newest first — never the general Matches screen (whose first
// section is Upcoming fixtures). From here the user opens whichever
// match they want (→ its scorecard) or deletes one on its own.
import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/player_avatar.dart';
import 'scorecard_screen.dart';

class CompletedMatchesScreen extends StatefulWidget {
  final Store store;
  const CompletedMatchesScreen({super.key, required this.store});

  @override
  State<CompletedMatchesScreen> createState() =>
      _CompletedMatchesScreenState();
}

class _CompletedMatchesScreenState extends State<CompletedMatchesScreen> {
  Store get store => widget.store;

  @override
  void initState() {
    super.initState();
    store.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    store.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  // v1.4.5: no-result matches are finished matches too — they belong
  // in the Completed view alongside completed ones. Live/scheduled
  // matches stay excluded. The status itself is untouched.
  List<Match> get _completed {
    final list = store.matches
        .where((m) => m.status == 'completed' || m.status == 'noResult')
        .toList();
    list.sort((a, b) => b.dateIso.compareTo(a.dateIso));
    return list;
  }

  Future<void> _confirmDelete(Match m) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete match?'),
        content: Text(
          'Delete ${store.teamName(m.teamAId)} vs '
          '${store.teamName(m.teamBId)} and its scorecard? '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await store.deleteMatch(m.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final matches = _completed;
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(title: const Text('Completed Matches')),
      body: matches.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(20),
              child: EmptyState(
                icon: Icons.scoreboard_outlined,
                title: 'No completed matches yet',
                subtitle:
                    'Finished matches will appear here with full scorecards.',
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: matches.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _card(matches[i]),
            ),
    );
  }

  Widget _card(Match m) {
    final a = store.teamName(m.teamAId);
    final b = store.teamName(m.teamBId);
    return ScoreCard(
      padding: const EdgeInsets.all(12),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ScorecardScreen(store: store, match: m),
        ),
      ),
      child: Row(
        children: [
          CaptainAvatar(store: store, teamId: m.teamAId, radius: 18),
          const SizedBox(width: 4),
          CaptainAvatar(store: store, teamId: m.teamBId, radius: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$a vs $b',
                  style: const TextStyle(
                    color: kWhite,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                for (final inn in m.innings.take(2))
                  Text(
                    '${store.teamName(inn.battingTeamId)} '
                    '${inn.totalRuns}/${inn.wickets} '
                    '(${inn.legalBalls ~/ inn.ballsPerOver}.${inn.legalBalls % inn.ballsPerOver} ov)',
                    style: const TextStyle(color: kSilver, fontSize: 12),
                  ),
                if (m.resultText.isNotEmpty)
                  Text(
                    m.resultText,
                    style: const TextStyle(
                      color: kCyan,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (m.dateIso.isNotEmpty)
                  Text(
                    m.dateIso.split('T').first,
                    style: const TextStyle(color: kSilver, fontSize: 11),
                  ),
              ],
            ),
          ),
          StatusPill(m.status),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            color: kSilver,
            tooltip: 'Delete match',
            onPressed: () => _confirmDelete(m),
          ),
        ],
      ),
    );
  }
}
