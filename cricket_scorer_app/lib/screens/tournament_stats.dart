// Tournament statistics leaderboards (Stumps-style cards).
import 'dart:convert';

import 'package:flutter/material.dart';

import '../models.dart';
import '../scoring.dart';
import '../store.dart';
import '../theme.dart';
import 'stats_screen.dart' show CompareScreen, allPersons;

String _teamOfPlayer(Store store, String playerId) {
  for (final t in store.teams) {
    if (t.players.any((p) => p.id == playerId)) return t.name;
  }
  return '';
}

/// One leaderboard card's headline data.
class _StatHeadline {
  final String label;
  final String value;
  final String playerId;
  final String detail; // secondary line, e.g. "45 balls"
  final List<_LeaderRow> leaders;
  _StatHeadline({
    required this.label,
    required this.value,
    required this.playerId,
    required this.detail,
    required this.leaders,
  });
}

class _LeaderRow {
  final String playerId;
  final String primary;
  final String secondary;
  _LeaderRow(this.playerId, this.primary, this.secondary);
}

class TournamentStatsTab extends StatelessWidget {
  final Store store;
  final Tournament tournament;
  const TournamentStatsTab({
    super.key,
    required this.store,
    required this.tournament,
  });

  List<_StatHeadline> _build() {
    final tid = tournament.id;
    final career = computeCareerStats(store.matches, tournamentId: tid);
    final persons = allPersons(store);
    String nameOf(String id) => persons[id] ?? store.playerName(id);
    final list = career.values.toList();

    List<_LeaderRow> rowsOf(
      List<CareerStats> sorted,
      String Function(CareerStats c) primary,
      String Function(CareerStats c) secondary,
      bool Function(CareerStats c) include,
    ) => sorted
        .where(include)
        .take(10)
        .map((c) => _LeaderRow(c.playerId, primary(c), secondary(c)))
        .toList();

    final byRuns = [...list]..sort((a, b) => b.runs.compareTo(a.runs));
    final byWkts = [...list]..sort((a, b) => b.wickets.compareTo(a.wickets));
    final byHS = [...list]..sort((a, b) => b.highScore.compareTo(a.highScore));
    final byBowl = [...list]
      ..sort((a, b) {
        if (b.bestWickets != a.bestWickets) {
          return b.bestWickets.compareTo(a.bestWickets);
        }
        return a.bestRuns.compareTo(b.bestRuns);
      });
    final bySixes = [...list]..sort((a, b) => b.sixes.compareTo(a.sixes));
    final byFours = [...list]..sort((a, b) => b.fours.compareTo(a.fours));
    final byCatches = [...list]..sort((a, b) => b.catches.compareTo(a.catches));
    final byStump = [...list]
      ..sort((a, b) => b.stumpings.compareTo(a.stumpings));
    final byBalls = [...list]
      ..sort((a, b) => b.ballsFaced.compareTo(a.ballsFaced));

    final fastest = fastestMilestones(store.matches, tournamentId: tid);
    final power = inningsPowerLeaders(store.matches, tournamentId: tid);
    final partnershipsBest = bestPartnerships(store.matches, tournamentId: tid);

    String pName(String id) => nameOf(id);

    final out = <_StatHeadline>[
      _StatHeadline(
        label: 'Most Runs',
        value: byRuns.isNotEmpty && byRuns.first.runs > 0
            ? '${byRuns.first.runs}'
            : '0',
        playerId: byRuns.isNotEmpty ? byRuns.first.playerId : '',
        detail: byRuns.isNotEmpty && byRuns.first.runs > 0
            ? 'Avg ${byRuns.first.battingAverage.toStringAsFixed(1)} • SR ${byRuns.first.battingSR.toStringAsFixed(0)}'
            : '',
        leaders: rowsOf(
          byRuns,
          (c) => '${c.runs} runs',
          (c) =>
              'Avg ${c.battingAverage.toStringAsFixed(1)} • SR ${c.battingSR.toStringAsFixed(0)}',
          (c) => c.runs > 0,
        ),
      ),
      _StatHeadline(
        label: 'Most Wickets',
        value: byWkts.isNotEmpty && byWkts.first.wickets > 0
            ? '${byWkts.first.wickets}'
            : '0',
        playerId: byWkts.isNotEmpty ? byWkts.first.playerId : '',
        detail: byWkts.isNotEmpty && byWkts.first.wickets > 0
            ? 'Econ ${byWkts.first.economy.toStringAsFixed(2)} • Best ${byWkts.first.bestFigures}'
            : '',
        leaders: rowsOf(
          byWkts,
          (c) => '${c.wickets} wkts',
          (c) => 'Econ ${c.economy.toStringAsFixed(2)} • Best ${c.bestFigures}',
          (c) => c.wickets > 0,
        ),
      ),
      _StatHeadline(
        label: 'Highest Score',
        value: byHS.isNotEmpty && byHS.first.highScore > 0
            ? '${byHS.first.highScore}'
            : '0',
        playerId: byHS.isNotEmpty ? byHS.first.playerId : '',
        detail: '',
        leaders: rowsOf(
          byHS,
          (c) => '${c.highScore}',
          (c) => '${c.runs} runs • SR ${c.battingSR.toStringAsFixed(0)}',
          (c) => c.highScore > 0,
        ),
      ),
      _StatHeadline(
        label: 'Best Bowling',
        value: byBowl.isNotEmpty && byBowl.first.bestWickets > 0
            ? byBowl.first.bestFigures
            : '0-0',
        playerId: byBowl.isNotEmpty ? byBowl.first.playerId : '',
        detail: '',
        leaders: rowsOf(
          byBowl,
          (c) => c.bestFigures,
          (c) => '${c.wickets} wkts • Econ ${c.economy.toStringAsFixed(2)}',
          (c) => c.bestWickets > 0,
        ),
      ),
      _StatHeadline(
        label: 'Most Sixes',
        value: bySixes.isNotEmpty && bySixes.first.sixes > 0
            ? '${bySixes.first.sixes}'
            : '0',
        playerId: bySixes.isNotEmpty ? bySixes.first.playerId : '',
        detail: '',
        leaders: rowsOf(
          bySixes,
          (c) => '${c.sixes} sixes',
          (c) => '${c.runs} runs',
          (c) => c.sixes > 0,
        ),
      ),
      _StatHeadline(
        label: 'Most Fours',
        value: byFours.isNotEmpty && byFours.first.fours > 0
            ? '${byFours.first.fours}'
            : '0',
        playerId: byFours.isNotEmpty ? byFours.first.playerId : '',
        detail: '',
        leaders: rowsOf(
          byFours,
          (c) => '${c.fours} fours',
          (c) => '${c.runs} runs',
          (c) => c.fours > 0,
        ),
      ),
      _StatHeadline(
        label: 'Most Catches',
        value: byCatches.isNotEmpty && byCatches.first.catches > 0
            ? '${byCatches.first.catches}'
            : '0',
        playerId: byCatches.isNotEmpty ? byCatches.first.playerId : '',
        detail: '',
        leaders: rowsOf(
          byCatches,
          (c) => '${c.catches} catches',
          (c) => 'MVP ${c.mvpPoints.toStringAsFixed(0)}',
          (c) => c.catches > 0,
        ),
      ),
      _StatHeadline(
        label: 'Most Stumpings',
        value: byStump.isNotEmpty && byStump.first.stumpings > 0
            ? '${byStump.first.stumpings}'
            : '0',
        playerId: byStump.isNotEmpty ? byStump.first.playerId : '',
        detail: '',
        leaders: rowsOf(
          byStump,
          (c) => '${c.stumpings} stumpings',
          (c) => 'MVP ${c.mvpPoints.toStringAsFixed(0)}',
          (c) => c.stumpings > 0,
        ),
      ),
      _StatHeadline(
        label: 'Fastest Fifty',
        value: fastest.fifties.isNotEmpty
            ? '${fastest.fifties.first.balls} balls'
            : '-',
        playerId: fastest.fifties.isNotEmpty
            ? fastest.fifties.first.playerId
            : '',
        detail: fastest.fifties.isNotEmpty
            ? '${fastest.fifties.first.runs} runs'
            : '',
        leaders: fastest.fifties
            .take(10)
            .map(
              (m) =>
                  _LeaderRow(m.playerId, '${m.balls} balls', '${m.runs} runs'),
            )
            .toList(),
      ),
      _StatHeadline(
        label: 'Fastest Hundred',
        value: fastest.hundreds.isNotEmpty
            ? '${fastest.hundreds.first.balls} balls'
            : '-',
        playerId: fastest.hundreds.isNotEmpty
            ? fastest.hundreds.first.playerId
            : '',
        detail: fastest.hundreds.isNotEmpty
            ? '${fastest.hundreds.first.runs} runs'
            : '',
        leaders: fastest.hundreds
            .take(10)
            .map(
              (m) =>
                  _LeaderRow(m.playerId, '${m.balls} balls', '${m.runs} runs'),
            )
            .toList(),
      ),
      _StatHeadline(
        label: 'Best Partnership',
        value: partnershipsBest.isNotEmpty
            ? '${partnershipsBest.first.runs}'
            : '0',
        playerId: '',
        detail: partnershipsBest.isNotEmpty
            ? '${pName(partnershipsBest.first.batter1Id)} & ${pName(partnershipsBest.first.batter2Id)} • ${partnershipsBest.first.balls} balls'
            : '',
        leaders: partnershipsBest
            .take(10)
            .map(
              (p) => _LeaderRow(
                p.batter1Id,
                '${p.runs} (${p.balls})',
                '${pName(p.batter1Id)} & ${pName(p.batter2Id)}',
              ),
            )
            .toList(),
      ),
      _StatHeadline(
        label: 'Most Balls Faced',
        value: byBalls.isNotEmpty && byBalls.first.ballsFaced > 0
            ? '${byBalls.first.ballsFaced}'
            : '0',
        playerId: byBalls.isNotEmpty ? byBalls.first.playerId : '',
        detail: '',
        leaders: rowsOf(
          byBalls,
          (c) => '${c.ballsFaced} balls',
          (c) => '${c.runs} runs',
          (c) => c.ballsFaced > 0,
        ),
      ),
      _StatHeadline(
        label: 'Most Sixes (Innings)',
        value: power.sixes.isNotEmpty ? '${power.sixes.first.count}' : '0',
        playerId: power.sixes.isNotEmpty ? power.sixes.first.playerId : '',
        detail: power.sixes.isNotEmpty
            ? '${power.sixes.first.runs} runs in the innings'
            : '',
        leaders: power.sixes
            .take(10)
            .map(
              (e) =>
                  _LeaderRow(e.playerId, '${e.count} sixes', '${e.runs} runs'),
            )
            .toList(),
      ),
      _StatHeadline(
        label: 'Most Fours (Innings)',
        value: power.fours.isNotEmpty ? '${power.fours.first.count}' : '0',
        playerId: power.fours.isNotEmpty ? power.fours.first.playerId : '',
        detail: power.fours.isNotEmpty
            ? '${power.fours.first.runs} runs in the innings'
            : '',
        leaders: power.fours
            .take(10)
            .map(
              (e) =>
                  _LeaderRow(e.playerId, '${e.count} fours', '${e.runs} runs'),
            )
            .toList(),
      ),
    ];
    return out;
  }

  Future<void> _exportCsv(BuildContext context) async {
    final buf = StringBuffer('Category,Player,Team,Figure,Detail\n');
    String esc(String s) => '"${s.replaceAll('"', '""')}"';
    for (final h in _build()) {
      for (final r in h.leaders) {
        final persons = allPersons(store);
        buf.writeln(
          '${esc(h.label)},${esc(persons[r.playerId] ?? store.playerName(r.playerId))},${esc(_teamOfPlayer(store, r.playerId))},${esc(r.primary)},${esc(r.secondary)}',
        );
      }
    }
    await shareBytes(
      'stats_${tournament.id}.csv',
      utf8.encode(buf.toString()),
      text: '${tournament.name} statistics',
    );
  }

  @override
  Widget build(BuildContext context) {
    final stats = _build();
    final persons = allPersons(store);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 4, 4),
          child: Row(
            children: [
              const Text(
                'Statistics',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                tooltip: 'More options',
                onSelected: (v) {
                  if (v == 'export') {
                    _exportCsv(context);
                  } else if (v == 'compare') {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CompareScreen(store: store),
                      ),
                    );
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'export',
                    child: Text('Export stats (CSV)'),
                  ),
                  PopupMenuItem(
                    value: 'compare',
                    child: Text('Compare players'),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.92,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: stats.length,
            itemBuilder: (c, i) {
              final s = stats[i];
              final hasData = s.leaders.isNotEmpty;
              final name = s.playerId.isEmpty
                  ? (s.detail.isNotEmpty ? '' : 'No data yet')
                  : (persons[s.playerId] ?? store.playerName(s.playerId));
              final team = s.playerId.isEmpty
                  ? ''
                  : _teamOfPlayer(store, s.playerId);
              return Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: hasData
                      ? () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => _LeaderboardScreen(
                              store: store,
                              title: '${tournament.name} - ${s.label}',
                              leaders: s.leaders,
                            ),
                          ),
                        )
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          s.value,
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.bold,
                            color: kCyan,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          s.label,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (name.isNotEmpty)
                          Text(
                            name,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        if (team.isNotEmpty)
                          Text(
                            team,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white54,
                            ),
                          ),
                        if (s.detail.isNotEmpty && s.playerId.isEmpty)
                          Text(
                            s.detail,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white54,
                            ),
                          ),
                        if (s.detail.isNotEmpty && s.playerId.isNotEmpty)
                          Text(
                            s.detail,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white38,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _LeaderboardScreen extends StatelessWidget {
  final Store store;
  final String title;
  final List<_LeaderRow> leaders;
  const _LeaderboardScreen({
    required this.store,
    required this.title,
    required this.leaders,
  });

  @override
  Widget build(BuildContext context) {
    final persons = allPersons(store);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: leaders.length,
        separatorBuilder: (_, _) => const Divider(height: 8),
        itemBuilder: (c, i) {
          final r = leaders[i];
          final name = persons[r.playerId] ?? store.playerName(r.playerId);
          final team = _teamOfPlayer(store, r.playerId);
          return ListTile(
            dense: true,
            leading: CircleAvatar(
              backgroundColor: kTealDark,
              child: Text(
                '${i + 1}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text(name),
            subtitle: Text(
              '${r.secondary}${team.isNotEmpty ? '  •  $team' : ''}',
            ),
            trailing: Text(
              r.primary,
              style: const TextStyle(
                color: kCyan,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          );
        },
      ),
    );
  }
}
