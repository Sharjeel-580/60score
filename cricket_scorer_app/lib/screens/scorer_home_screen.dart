import 'package:flutter/material.dart';

import '../models.dart';
import '../scoring.dart';
import '../store.dart';
import '../theme.dart';
import 'match_setup_screen.dart';
import 'scorecard_screen.dart';
import 'scoring_screen.dart';
import 'teams_screen.dart';
import 'tournament_stats.dart';

class ScorerHomeScreen extends StatelessWidget {
  final Store store;
  const ScorerHomeScreen({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    final live = store.matches.where((m) => m.status == 'live').toList();
    final done = store.matches.where((m) => m.status != 'live').toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scorer'),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => TeamsScreen(store: store)),
            ),
            icon: const Icon(Icons.groups, color: kCyan),
            label: const Text('Teams', style: TextStyle(color: kCyan)),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => MatchSetupScreen(store: store)),
        ),
        icon: const Icon(Icons.sports_cricket),
        label: const Text('New match'),
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          _brandHeader(context),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: _statsRow(live.length, done.length),
          ),
          const SizedBox(height: 14),
          _sectionTitle(context, 'Tournaments', Icons.emoji_events),
          if (store.tournaments.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'No tournaments yet.',
                style: TextStyle(color: Colors.white54),
              ),
            ),
          for (final t in store.tournaments)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: const Icon(Icons.emoji_events, color: kCopper),
                  title: Text(t.name),
                  subtitle: Text('${t.teamIds.length} teams'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          TournamentDetailScreen(store: store, tournament: t),
                    ),
                  ),
                ),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 4),
              child: TextButton.icon(
                onPressed: () => _createTournament(context),
                icon: const Icon(Icons.add),
                label: const Text('Create tournament'),
              ),
            ),
          ),
          const Divider(height: 16),
          _sectionTitle(context, 'Live matches', Icons.play_circle,
              badge: live.isNotEmpty ? '${live.length}' : null),
          if (live.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text(
                'No live matches.',
                style: TextStyle(color: Colors.white54),
              ),
            ),
          for (final m in live)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: _matchTile(context, m, live: true),
            ),
          const SizedBox(height: 10),
          _sectionTitle(context, 'Completed', Icons.check_circle),
          if (done.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text(
                'No completed matches yet.',
                style: TextStyle(color: Colors.white54),
              ),
            ),
          for (final m in done)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: _matchTile(context, m, live: false),
            ),
          const SizedBox(height: 90),
        ],
      ),
    );
  }

  /// Branded professional header: 60Score logo lockup + offline badge.
  Widget _brandHeader(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0A1F2C), Color(0xFF030A10)],
        ),
        border: Border(bottom: BorderSide(color: kTealDark, width: 1)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 18),
      child: Column(
        children: [
          Image.asset('assets/app_logo.png', fit: BoxFit.contain, height: 170),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: kTeal.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: kTeal, width: 1),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.wifi_off, size: 14, color: kCyan),
                SizedBox(width: 6),
                Text(
                  '100% Offline • Your data stays on this phone',
                  style: TextStyle(color: kCyan, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Quick stats strip.
  Widget _statsRow(int liveCount, int doneCount) {
    return Row(
      children: [
        _statChip(
          Icons.emoji_events,
          '${store.tournaments.length}',
          'Tournaments',
          kCopper,
        ),
        const SizedBox(width: 8),
        _statChip(
          Icons.play_circle,
          '$liveCount',
          'Live now',
          kCyan,
        ),
        const SizedBox(width: 8),
        _statChip(
          Icons.sports_cricket,
          '${liveCount + doneCount}',
          'Matches',
          Colors.white70,
        ),
      ],
    );
  }

  Widget _statChip(IconData icon, String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: kPanel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kTealDark, width: 1),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(
    BuildContext context,
    String title,
    IconData icon, {
    String? badge,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Row(
        children: [
          Container(width: 4, height: 20, color: kCyan),
          const SizedBox(width: 8),
          Icon(icon, size: 18, color: kCyan),
          const SizedBox(width: 6),
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          if (badge != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: kCyan,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                badge,
                style: const TextStyle(
                  color: Color(0xFF03222B),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _matchTile(BuildContext context, Match m, {required bool live}) {
    final summary = m.innings.isEmpty
        ? 'Not started'
        : m.innings
              .map(
                (i) =>
                    '${store.teamName(i.battingTeamId)} ${i.totalRuns}/${i.wickets} (${oversText(i.legalBalls, i.ballsPerOver)})',
              )
              .join('  •  ');
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: live
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red.shade700,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'LIVE',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            : const Icon(Icons.check_circle, color: Colors.white54),
        title: Text(
          '${store.teamName(m.teamAId)} vs ${store.teamName(m.teamBId)}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(m.resultText.isNotEmpty ? m.resultText : summary),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => live
                ? ScoringScreen(store: store, match: m)
                : ScorecardScreen(store: store, match: m),
          ),
        ),
      ),
    );
  }

  Future<void> _createTournament(BuildContext context) async {
    final nameCtrl = TextEditingController();
    final selected = <String>{};
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('Create tournament'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Tournament name',
                  ),
                ),
                const SizedBox(height: 8),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Teams',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                for (final t in store.teams)
                  CheckboxListTile(
                    dense: true,
                    value: selected.contains(t.id),
                    title: Text(t.name),
                    onChanged: (v) => setD(() {
                      if (v == true) {
                        selected.add(t.id);
                      } else {
                        selected.remove(t.id);
                      }
                    }),
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
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    if (ok == true && nameCtrl.text.trim().isNotEmpty) {
      await store.upsertTournament(
        Tournament(
          id: Store.newId('tournament'),
          name: nameCtrl.text.trim(),
          teamIds: selected.toList(),
        ),
      );
    }
  }
}

class TournamentDetailScreen extends StatefulWidget {
  final Store store;
  final Tournament tournament;
  const TournamentDetailScreen({
    super.key,
    required this.store,
    required this.tournament,
  });

  @override
  State<TournamentDetailScreen> createState() => _TournamentDetailScreenState();
}

class _TournamentDetailScreenState extends State<TournamentDetailScreen> {
  Store get store => widget.store;
  Tournament get tournament => widget.tournament;

  @override
  Widget build(BuildContext context) {
    final rows = computePointsTable(
      tournament.id,
      tournament.teamIds,
      store.matches,
      pointsAdjustments: tournament.pointsAdjustments,
    );
    final fixtures = store.matches
        .where((m) => m.tournamentId == tournament.id)
        .toList();
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(tournament.name),
          actions: [
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                await store.deleteTournament(tournament.id);
                if (context.mounted) Navigator.pop(context);
              },
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Points Table'),
              Tab(text: 'Fixtures'),
              Tab(text: 'Stats'),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  MatchSetupScreen(store: store, tournamentId: tournament.id),
            ),
          ).then((_) => setState(() {})),
          icon: const Icon(Icons.add),
          label: const Text('New fixture'),
        ),
        body: TabBarView(
          children: [
            // Points table (ICC NRR)
            ListView(
              padding: const EdgeInsets.all(10),
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columnSpacing: 12,
                    columns: const [
                      DataColumn(label: Text('Team')),
                      DataColumn(label: Text('P')),
                      DataColumn(label: Text('W')),
                      DataColumn(label: Text('L')),
                      DataColumn(label: Text('T')),
                      DataColumn(label: Text('NR')),
                      DataColumn(label: Text('Pts')),
                      DataColumn(label: Text('NRR')),
                      DataColumn(label: Text('Adj')),
                    ],
                    rows: [
                      for (final r in rows)
                        DataRow(
                          cells: [
                            DataCell(Text(store.teamName(r.teamId))),
                            DataCell(Text('${r.played}')),
                            DataCell(Text('${r.won}')),
                            DataCell(Text('${r.lost}')),
                            DataCell(Text('${r.tied}')),
                            DataCell(Text('${r.noResult}')),
                            DataCell(
                              Text(
                                '${r.points}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: kCyan,
                                ),
                              ),
                            ),
                            DataCell(Text(r.nrr.toStringAsFixed(3))),
                            DataCell(
                              IconButton(
                                icon: const Icon(Icons.edit, size: 18),
                                tooltip: 'Custom points adjustment',
                                onPressed: () =>
                                    _editAdjustment(context, r.teamId),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'NRR uses the ICC rule: aggregate runs per over scored minus conceded across the tournament; a team bowled out is deemed to have faced its full overs quota.',
                    style: TextStyle(fontSize: 11, color: Colors.white38),
                  ),
                ),
              ],
            ),
            // Fixtures
            ListView(
              padding: const EdgeInsets.all(10),
              children: [
                if (fixtures.isEmpty) const Text('No fixtures yet.'),
                for (final m in fixtures)
                  Card(
                    child: ListTile(
                      title: Text(
                        '${store.teamName(m.teamAId)} vs ${store.teamName(m.teamBId)}',
                      ),
                      subtitle: Text(
                        m.resultText.isNotEmpty
                            ? m.resultText
                            : (m.status == 'live' ? 'Live' : m.status),
                      ),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => m.status == 'live'
                              ? ScoringScreen(store: store, match: m)
                              : ScorecardScreen(store: store, match: m),
                        ),
                      ).then((_) => setState(() {})),
                    ),
                  ),
                const SizedBox(height: 70),
              ],
            ),
            // Tournament stats (Stumps-style leaderboards)
            TournamentStatsTab(store: store, tournament: tournament),
          ],
        ),
      ),
    );
  }

  Future<void> _editAdjustment(BuildContext context, String teamId) async {
    final ctrl = TextEditingController(
      text: '${tournament.pointsAdjustments[teamId] ?? 0}',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Custom points — ${store.teamName(teamId)}'),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(signed: true),
          decoration: const InputDecoration(
            labelText: 'Adjustment (added to earned points)',
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
    if (ok == true) {
      final v = int.tryParse(ctrl.text) ?? 0;
      if (v == 0) {
        tournament.pointsAdjustments.remove(teamId);
      } else {
        tournament.pointsAdjustments[teamId] = v;
      }
      await store.persist();
      if (mounted) setState(() {});
    }
  }
}
