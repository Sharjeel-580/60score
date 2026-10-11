import 'package:flutter/material.dart';
import '../models.dart';
import '../scoring.dart';
import '../store.dart';
import '../theme.dart';
import 'match_setup_screen.dart';
import 'scorecard_screen.dart';
import 'scoring_screen.dart';
import 'teams_screen.dart';

class ScorerHomeScreen extends StatelessWidget {
  final Store store;
  const ScorerHomeScreen({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    final live = store.matches.where((m) => m.status == 'live').toList();
    final done =
        store.matches.where((m) => m.status != 'live').toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scorer'),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => TeamsScreen(store: store))),
            icon: const Icon(Icons.groups, color: kCyan),
            label: const Text('Teams', style: TextStyle(color: kCyan)),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => MatchSetupScreen(store: store))),
        icon: const Icon(Icons.sports_cricket),
        label: const Text('New match'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset('assets/logo.png', fit: BoxFit.cover),
          ),
          const SizedBox(height: 6),
          const Center(
              child: Text('60Score • Super Sixty League • fully offline',
                  style: TextStyle(color: Colors.white54, fontSize: 12))),
          const SizedBox(height: 14),
          const Text('Tournaments',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          if (store.tournaments.isEmpty)
            const Text('No tournaments yet.',
                style: TextStyle(color: Colors.white54)),
          for (final t in store.tournaments)
            Card(
              child: ListTile(
                leading: const Icon(Icons.emoji_events, color: kCopper),
                title: Text(t.name),
                subtitle: Text('${t.teamIds.length} teams'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            TournamentDetailScreen(store: store, tournament: t))),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _createTournament(context),
              icon: const Icon(Icons.add),
              label: const Text('Create tournament'),
            ),
          ),
          const Divider(height: 24),
          const Text('Live matches',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          if (live.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text('No live matches.',
                  style: TextStyle(color: Colors.white54)),
            ),
          for (final m in live) _matchTile(context, m, live: true),
          const SizedBox(height: 10),
          const Text('Completed',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          if (done.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text('No completed matches yet.',
                  style: TextStyle(color: Colors.white54)),
            ),
          for (final m in done) _matchTile(context, m, live: false),
          const SizedBox(height: 70),
        ],
      ),
    );
  }

  Widget _matchTile(BuildContext context, Match m, {required bool live}) {
    final summary = m.innings.isEmpty
        ? 'Not started'
        : m.innings
            .map((i) =>
                '${store.teamName(i.battingTeamId)} ${i.totalRuns}/${i.wickets} (${oversText(i.legalBalls, i.ballsPerOver)})')
            .join('  •  ');
    return Card(
      child: ListTile(
        leading: Icon(live ? Icons.play_circle : Icons.check_circle,
            color: live ? kCyan : Colors.white54),
        title: Text(
            '${store.teamName(m.teamAId)} vs ${store.teamName(m.teamBId)}'),
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
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: nameCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Tournament name')),
              const SizedBox(height: 8),
              const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Teams', style: TextStyle(fontWeight: FontWeight.bold))),
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
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Create')),
          ],
        ),
      ),
    );
    if (ok == true && nameCtrl.text.trim().isNotEmpty) {
      await store.upsertTournament(Tournament(
        id: Store.newId('tournament'),
        name: nameCtrl.text.trim(),
        teamIds: selected.toList(),
      ));
    }
  }
}

class TournamentDetailScreen extends StatefulWidget {
  final Store store;
  final Tournament tournament;
  const TournamentDetailScreen(
      {super.key, required this.store, required this.tournament});

  @override
  State<TournamentDetailScreen> createState() =>
      _TournamentDetailScreenState();
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
    final tStats = computeCareerStats(store.matches, tournamentId: tournament.id);
    final topRuns = tStats.values.toList()
      ..sort((a, b) => b.runs.compareTo(a.runs));
    final topWkts = tStats.values.toList()
      ..sort((a, b) => b.wickets.compareTo(a.wickets));
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
          bottom: const TabBar(tabs: [
            Tab(text: 'Points Table'),
            Tab(text: 'Fixtures'),
            Tab(text: 'Stats'),
          ]),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => MatchSetupScreen(
                      store: store, tournamentId: tournament.id)))
              .then((_) => setState(() {})),
          icon: const Icon(Icons.add),
          label: const Text('New fixture'),
        ),
        body: TabBarView(children: [
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
                      DataRow(cells: [
                        DataCell(Text(store.teamName(r.teamId))),
                        DataCell(Text('${r.played}')),
                        DataCell(Text('${r.won}')),
                        DataCell(Text('${r.lost}')),
                        DataCell(Text('${r.tied}')),
                        DataCell(Text('${r.noResult}')),
                        DataCell(Text('${r.points}',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, color: kCyan))),
                        DataCell(Text(r.nrr.toStringAsFixed(3))),
                        DataCell(IconButton(
                          icon: const Icon(Icons.edit, size: 18),
                          tooltip: 'Custom points adjustment',
                          onPressed: () =>
                              _editAdjustment(context, r.teamId),
                        )),
                      ]),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                    'NRR uses the ICC rule: aggregate runs per over scored minus conceded across the tournament; a team bowled out is deemed to have faced its full overs quota.',
                    style: TextStyle(fontSize: 11, color: Colors.white38)),
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
                        '${store.teamName(m.teamAId)} vs ${store.teamName(m.teamBId)}'),
                    subtitle: Text(m.resultText.isNotEmpty
                        ? m.resultText
                        : (m.status == 'live' ? 'Live' : m.status)),
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
          // Tournament stats
          ListView(
            padding: const EdgeInsets.all(12),
            children: [
              const Text('Most runs',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              for (final c in topRuns.take(10))
                if (c.runs > 0)
                  ListTile(
                      dense: true,
                      title: Text(store.playerName(c.playerId)),
                      trailing: Text('${c.runs} runs')),
              const Divider(),
              const Text('Most wickets',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              for (final c in topWkts.take(10))
                if (c.wickets > 0)
                  ListTile(
                      dense: true,
                      title: Text(store.playerName(c.playerId)),
                      trailing: Text('${c.wickets} wkts')),
            ],
          ),
        ]),
      ),
    );
  }

  Future<void> _editAdjustment(BuildContext context, String teamId) async {
    final ctrl = TextEditingController(
        text: '${tournament.pointsAdjustments[teamId] ?? 0}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Custom points — ${store.teamName(teamId)}'),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(signed: true),
          decoration: const InputDecoration(
              labelText: 'Adjustment (added to earned points)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
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
