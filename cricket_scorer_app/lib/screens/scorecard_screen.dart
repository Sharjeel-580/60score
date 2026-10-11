// Match Centre: Summary / Scorecard / Stats / Super Stars / Balls / Info.
import 'package:flutter/material.dart';

import '../models.dart';
import '../pdf_export.dart';
import '../scoring.dart';
import '../store.dart';
import '../summary_share.dart';
import '../theme.dart';
import '../widgets/charts.dart';

class ScorecardScreen extends StatelessWidget {
  final Store store;
  final Match match;
  const ScorecardScreen({super.key, required this.store, required this.match});

  String nameOf(String id) => store.playerName(id);

  String get _tournamentName {
    final tid = match.tournamentId;
    if (tid == null) return '';
    return store.tournamentById(tid)?.name ?? '';
  }

  Future<void> _sharePdf(BuildContext context) async {
    final bytes = await buildScorecardPdf(
      match,
      nameOf,
      store.teamName,
      tournamentName: _tournamentName,
    );
    await shareBytes(
      'scorecard_${match.id}.pdf',
      bytes,
      text: '60Score scorecard',
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 6,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Match Centre'),
          actions: [
            IconButton(
              icon: const Icon(Icons.copy),
              tooltip: 'Copy scorecard as text',
              onPressed: () async {
                await copyToClipboard(
                  scorecardText(match, nameOf, store.teamName),
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Scorecard copied to clipboard'),
                    ),
                  );
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.picture_as_pdf),
              tooltip: 'Share scorecard PDF',
              onPressed: () => _sharePdf(context),
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Summary'),
              Tab(text: 'Scorecard'),
              Tab(text: 'Stats'),
              Tab(text: 'Super Stars'),
              Tab(text: 'Balls'),
              Tab(text: 'Info'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _SummaryTab(store: store, match: match),
            _scorecardTab(context),
            _chartsTab(),
            _SuperStarsTab(store: store, match: match),
            _BallsTab(store: store, match: match),
            _InfoTab(store: store, match: match),
          ],
        ),
      ),
    );
  }

  // ---------------- Scorecard tab (unchanged content) ----------------

  Widget _scorecardTab(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(
          '${store.teamName(match.teamAId)} vs ${store.teamName(match.teamBId)}',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
        Text(
          '${match.oversLimit} overs${match.venue.isNotEmpty ? ' | ${match.venue}' : ''}${match.dateIso.isNotEmpty ? ' | ${match.dateIso}' : ''}',
        ),
        Text(
          'Toss: ${store.teamName(match.tossWinnerId)} chose to ${match.tossDecision} first',
        ),
        if (match.resultText.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              match.resultText,
              style: const TextStyle(
                color: kCyan,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ),
        if (match.manOfMatchId.isNotEmpty)
          Text(
            'Man of the Match: ${nameOf(match.manOfMatchId)}',
            style: const TextStyle(color: kCopper),
          ),
        for (final inn in match.innings) ...[
          const Divider(height: 24),
          Text(
            '${store.teamName(inn.battingTeamId)} innings - ${inn.totalRuns}/${inn.wickets} (${oversText(inn.legalBalls, inn.ballsPerOver)} ov)',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          _battingTable(inn),
          const SizedBox(height: 4),
          Text(
            'Extras: ${inn.extrasTotal} (wd ${inn.widesRuns}, nb ${inn.noBallRuns}, b ${inn.byeRuns}, lb ${inn.legByeRuns})',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 8),
          _bowlingTable(inn),
          if (inn.fallOfWickets.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              'Fall of Wickets',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              inn.fallOfWickets
                  .map(
                    (w) =>
                        '${w.runs}-${w.wicketNo} (${nameOf(w.playerId)}, ${w.overText})',
                  )
                  .join(', '),
            ),
          ],
          const SizedBox(height: 8),
          const Text(
            'Partnerships',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          ...partnerships(inn).map(
            (p) => Text(
              '${nameOf(p.batter1Id)} & ${nameOf(p.batter2Id)}: ${p.runs} (${p.balls})${p.unbroken ? ' *' : ''}',
            ),
          ),
        ],
      ],
    );
  }

  Widget _battingTable(InningsState inn) {
    final rows = <DataRow>[];
    for (final pid in inn.battingXI) {
      final f = inn.batting[pid];
      if (f == null || !f.batted) continue;
      final sr = f.balls == 0
          ? '-'
          : (f.runs * 100 / f.balls).toStringAsFixed(1);
      rows.add(
        DataRow(
          cells: [
            DataCell(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(nameOf(pid)),
                  Text(
                    f.out ? resolveHowOut(f.howOut, nameOf) : 'not out',
                    style: const TextStyle(fontSize: 11, color: Colors.white54),
                  ),
                ],
              ),
            ),
            DataCell(Text('${f.runs}')),
            DataCell(Text('${f.balls}')),
            DataCell(Text('${f.fours}')),
            DataCell(Text('${f.sixes}')),
            DataCell(Text(sr)),
          ],
        ),
      );
    }
    final dnb = inn.battingXI
        .where((id) => !(inn.batting[id]?.batted ?? false))
        .map(nameOf)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 14,
            columns: const [
              DataColumn(label: Text('Batter')),
              DataColumn(label: Text('R')),
              DataColumn(label: Text('B')),
              DataColumn(label: Text('4s')),
              DataColumn(label: Text('6s')),
              DataColumn(label: Text('SR')),
            ],
            rows: rows,
          ),
        ),
        if (dnb.isNotEmpty)
          Text(
            'Did not bat: ${dnb.join(', ')}',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
      ],
    );
  }

  Widget _bowlingTable(InningsState inn) {
    final rows = <DataRow>[];
    for (final pid in inn.bowling.keys) {
      final f = inn.bowling[pid]!;
      if (f.legalBalls == 0 && f.wides == 0 && f.noBalls == 0) continue;
      final econ = f.legalBalls == 0
          ? '-'
          : (f.runs * inn.ballsPerOver / f.legalBalls).toStringAsFixed(2);
      rows.add(
        DataRow(
          cells: [
            DataCell(Text(nameOf(pid))),
            DataCell(Text(oversText(f.legalBalls, inn.ballsPerOver))),
            DataCell(Text('${f.maidens}')),
            DataCell(Text('${f.runs}')),
            DataCell(Text('${f.wickets}')),
            DataCell(Text(econ)),
          ],
        ),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 14,
        columns: const [
          DataColumn(label: Text('Bowler')),
          DataColumn(label: Text('O')),
          DataColumn(label: Text('M')),
          DataColumn(label: Text('R')),
          DataColumn(label: Text('W')),
          DataColumn(label: Text('Econ')),
        ],
        rows: rows,
      ),
    );
  }

  // ---------------- Stats tab (charts) ----------------

  Widget _chartsTab() {
    if (match.innings.isEmpty) {
      return const Center(child: Text('No data yet.'));
    }
    final i1 = match.innings[0];
    final i2 = match.innings.length > 1 ? match.innings[1] : null;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Text(
          'Runs Comparison (worm)',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        WormChart(
          innings1: wormData(i1),
          innings2: i2 != null ? wormData(i2) : const [],
          label1: store.teamName(i1.battingTeamId),
          label2: i2 != null ? store.teamName(i2.battingTeamId) : '',
        ),
        const Divider(height: 28),
        const Text(
          'Over Comparison (Manhattan)',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        ManhattanChart(
          innings1: manhattanData(i1),
          innings2: i2 != null ? manhattanData(i2) : const [],
        ),
        const Row(
          children: [
            Icon(Icons.square, size: 12, color: Colors.amber),
            SizedBox(width: 4),
            Text('Innings 1'),
            SizedBox(width: 12),
            Icon(Icons.square, size: 12, color: Colors.lightBlue),
            SizedBox(width: 4),
            Text('Innings 2'),
          ],
        ),
        const Divider(height: 28),
        const Text(
          'Wagon Wheel',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        for (final inn in match.innings) ...[
          const SizedBox(height: 8),
          Text(
            store.teamName(inn.battingTeamId),
            style: const TextStyle(color: kCopper),
          ),
          _WagonForInnings(inn: inn, nameOf: nameOf),
        ],
      ],
    );
  }
}

// ---------------- Summary tab ----------------

class _SummaryTab extends StatelessWidget {
  final Store store;
  final Match match;
  const _SummaryTab({required this.store, required this.match});

  String nameOf(String id) => store.playerName(id);

  @override
  Widget build(BuildContext context) {
    final result = match.resultText.isNotEmpty
        ? match.resultText
        : computeResult(match, store.teamName);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (match.matchTitle.isNotEmpty)
          Text(
            match.matchTitle,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: kCopper,
            ),
          ),
        Text(
          '${store.teamName(match.teamAId)} vs ${store.teamName(match.teamBId)}',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
        if (match.tournamentId != null &&
            store.tournamentById(match.tournamentId!) != null)
          Text(
            store.tournamentById(match.tournamentId!)!.name,
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
        const SizedBox(height: 10),
        for (final inn in match.innings) _inningsCard(inn),
        if (result.isNotEmpty)
          Card(
            color: kTealDark,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Icon(Icons.emoji_events, color: kCopper),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      result,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (match.manOfMatchId.isNotEmpty)
          Card(
            child: ListTile(
              leading: const Icon(Icons.star, color: Colors.amber),
              title: const Text(
                'Player of the Match',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              subtitle: Text(
                nameOf(match.manOfMatchId),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () async {
                  final tid = match.tournamentId;
                  final tname = tid == null
                      ? ''
                      : (store.tournamentById(tid)?.name ?? '');
                  final bytes = await buildScorecardPdf(
                    match,
                    nameOf,
                    store.teamName,
                    tournamentName: tname,
                  );
                  await shareBytes(
                    'scorecard_${match.id}.pdf',
                    bytes,
                    text: '60Score match report',
                  );
                },
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('Share Match Report'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => shareMatchSummaryImage(context, store, match),
                icon: const Icon(Icons.image),
                label: const Text('Share Summary'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _inningsCard(InningsState inn) {
    final batters = inn.batting.entries.where((e) => e.value.batted).toList()
      ..sort((a, b) => b.value.runs.compareTo(a.value.runs));
    final bowlers =
        inn.bowling.entries.where((e) => e.value.legalBalls > 0).toList()
          ..sort((a, b) {
            if (b.value.wickets != a.value.wickets) {
              return b.value.wickets.compareTo(a.value.wickets);
            }
            return a.value.runs.compareTo(b.value.runs);
          });
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    store.teamName(inn.battingTeamId).toUpperCase(),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
                Text(
                  '${inn.totalRuns}/${inn.wickets} (${oversText(inn.legalBalls, inn.ballsPerOver)})',
                  style: const TextStyle(
                    color: kCyan,
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                  ),
                ),
              ],
            ),
            const Divider(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final e in batters.take(3))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  nameOf(e.key),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                              Text(
                                '${e.value.runs}${e.value.out ? '' : '*'} (${e.value.balls})',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final e in bowlers.take(3))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  nameOf(e.key),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                              Text(
                                '${e.value.wickets}-${e.value.runs}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------- Super Stars tab ----------------

class _SuperStarsTab extends StatelessWidget {
  final Store store;
  final Match match;
  const _SuperStarsTab({required this.store, required this.match});

  String nameOf(String id) => store.playerName(id);

  String _teamOf(String playerId) {
    for (final t in store.teams) {
      if (t.players.any((p) => p.id == playerId)) return t.name;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final runs = <String, int>{};
    final balls = <String, int>{};
    final wkts = <String, int>{};
    final bowlRuns = <String, int>{};
    for (final inn in match.innings) {
      inn.batting.forEach((pid, f) {
        if (!f.batted) return;
        runs[pid] = (runs[pid] ?? 0) + f.runs;
        balls[pid] = (balls[pid] ?? 0) + f.balls;
      });
      inn.bowling.forEach((pid, f) {
        if (f.legalBalls == 0) return;
        wkts[pid] = (wkts[pid] ?? 0) + f.wickets;
        bowlRuns[pid] = (bowlRuns[pid] ?? 0) + f.runs;
      });
    }
    final topBat = runs.keys.toList()
      ..sort((a, b) => runs[b]!.compareTo(runs[a]!));
    final topBowl = wkts.keys.toList()
      ..sort((a, b) {
        if (wkts[b] != wkts[a]) return wkts[b]!.compareTo(wkts[a]!);
        return bowlRuns[a]!.compareTo(bowlRuns[b]!);
      });

    Widget starCard(int rank, String pid, String figure, String sub) {
      final medal = [Colors.amber, Colors.grey, const Color(0xFFCD7F32)];
      return Card(
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: rank <= 3 ? medal[rank - 1] : kTealDark,
            child: Text(
              '$rank',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          title: Text(
            nameOf(pid),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text('${_teamOf(pid)}${sub.isNotEmpty ? '  |  $sub' : ''}'),
          trailing: Text(
            figure,
            style: const TextStyle(
              color: kCyan,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Text(
          'Top Batters',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: kCopper,
          ),
        ),
        const SizedBox(height: 6),
        if (topBat.isEmpty)
          const Text(
            'No batting yet.',
            style: TextStyle(color: Colors.white54),
          ),
        for (var i = 0; i < topBat.take(3).length; i++)
          starCard(
            i + 1,
            topBat[i],
            '${runs[topBat[i]]} (${balls[topBat[i]]})',
            balls[topBat[i]]! > 0
                ? 'SR ${(runs[topBat[i]]! * 100 / balls[topBat[i]]!).toStringAsFixed(1)}'
                : '',
          ),
        const SizedBox(height: 12),
        const Text(
          'Top Bowlers',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: kCopper,
          ),
        ),
        const SizedBox(height: 6),
        if (topBowl.isEmpty)
          const Text(
            'No bowling yet.',
            style: TextStyle(color: Colors.white54),
          ),
        for (var i = 0; i < topBowl.take(3).length; i++)
          starCard(
            i + 1,
            topBowl[i],
            '${wkts[topBowl[i]]} wkts',
            '${bowlRuns[topBowl[i]]} runs conceded',
          ),
        const SizedBox(height: 20),
      ],
    );
  }
}

// ---------------- Balls tab (commentary) ----------------

class _BallsTab extends StatefulWidget {
  final Store store;
  final Match match;
  const _BallsTab({required this.store, required this.match});

  @override
  State<_BallsTab> createState() => _BallsTabState();
}

class _BallsTabState extends State<_BallsTab> {
  int inningsIdx = 0;
  int? overIdx; // 1-based selected over; null = latest

  Store get store => widget.store;
  Match get match => widget.match;
  String nameOf(String id) => store.playerName(id);

  @override
  Widget build(BuildContext context) {
    if (match.innings.isEmpty) {
      return const Center(child: Text('No balls recorded yet.'));
    }
    if (inningsIdx >= match.innings.length) inningsIdx = 0;
    final inn = match.innings[inningsIdx];
    final bpo = inn.ballsPerOver;
    final totalOvers = inn.legalBalls == 0
        ? 0
        : ((inn.legalBalls - 1) ~/ bpo) + 1;
    final selOver = (overIdx == null || overIdx! > totalOvers || overIdx! < 1)
        ? totalOvers
        : overIdx!;

    // ball numbers + over grouping
    var legalBefore = 0;
    final numbered = <_NumberedBall>[];
    for (final e in inn.events) {
      final overNo = legalBefore ~/ bpo + 1;
      final ballNo = legalBefore % bpo + 1;
      numbered.add(_NumberedBall(e, overNo, ballNo));
      if (e.legalBall) legalBefore++;
    }
    final overEvents = numbered.where((n) => n.overNo == selOver).toList();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (match.innings.length > 1)
          SegmentedButton<int>(
            segments: [
              for (var i = 0; i < match.innings.length; i++)
                ButtonSegment(
                  value: i,
                  label: Text('${i + 1}${i == 0 ? 'st' : 'nd'} Innings'),
                ),
            ],
            selected: {inningsIdx},
            onSelectionChanged: (s) => setState(() {
              inningsIdx = s.first;
              overIdx = null;
            }),
          )
        else
          Text(
            'Innings 1 - ${store.teamName(inn.battingTeamId)}',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
        const SizedBox(height: 10),
        if (totalOvers > 0)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Over',
                        style: TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(width: 8),
                      DropdownButton<int>(
                        value: selOver,
                        items: [
                          for (var o = 1; o <= totalOvers; o++)
                            DropdownMenuItem(value: o, child: Text('Over $o')),
                        ],
                        onChanged: (v) => setState(() => overIdx = v),
                      ),
                      const Spacer(),
                      Text(
                        '${inn.totalRuns}/${inn.wickets} (${oversText(inn.legalBalls, bpo)})',
                        style: const TextStyle(
                          color: kCyan,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [for (final n in overEvents) _ballChip(n.event)],
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 10),
        const Text(
          'Commentary',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: kCopper,
          ),
        ),
        const SizedBox(height: 6),
        for (final n in numbered.reversed) _commentaryRow(n),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _ballChip(BallEvent e) {
    final bool outlined = e.extraType == 'wide' || e.extraType == 'noBall';
    final Color fill;
    if (e.isWicket) {
      fill = kOrangeRed;
    } else if (outlined) {
      fill = Colors.transparent;
    } else if (e.batRuns == 6) {
      fill = Colors.blue.shade700;
    } else if (e.batRuns == 4) {
      fill = Colors.green.shade700;
    } else {
      fill = kPanel2;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(12),
        border: outlined ? Border.all(color: kTeal) : null,
      ),
      child: Text(
        e.display,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: outlined ? kCyan : Colors.white,
        ),
      ),
    );
  }

  Widget _commentaryRow(_NumberedBall n) {
    final e = n.event;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 40,
            child: Text(
              '${n.overNo}.${n.ballNo}',
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ),
          _ballChip(e),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_first(nameOf(e.bowlerId))} to ${_first(nameOf(e.strikerId))}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _commentaryText(e),
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _first(String name) => name.split(' ').first;

  String _commentaryText(BallEvent e) {
    final batter = _first(nameOf(e.strikerId));
    if (e.isWicket) {
      String tail;
      switch (e.wicketType) {
        case 'bowled':
          tail = 'Bowled him! $batter departs.';
          break;
        case 'caught':
          tail = 'Caught! ${_first(nameOf(e.fielderId))} takes it.';
          break;
        case 'lbw':
          tail = 'LBW! Big appeal and the finger goes up.';
          break;
        case 'stumped':
          tail = 'Stumped! Beaten in the flight.';
          break;
        case 'runOut':
          tail = 'Run out! Sharp work in the field.';
          break;
        case 'hitWicket':
          tail = 'Hit wicket! Unlucky for $batter.';
          break;
        default:
          tail = 'Wicket falls.';
      }
      if (e.batRuns > 0) tail += ' ${e.batRuns} run(s) completed.';
      return tail;
    }
    switch (e.extraType) {
      case 'wide':
        return e.extraRuns > 0
            ? 'Wide, plus ${e.extraRuns} extra.'
            : 'Wide ball.';
      case 'noBall':
        return e.batRuns > 0
            ? 'No ball, ${e.batRuns} off the bat.'
            : 'No ball.';
      case 'bye':
        return '${e.batRuns} bye(s).';
      case 'legBye':
        return '${e.batRuns} leg bye(s).';
    }
    switch (e.batRuns) {
      case 6:
        return "Huge. It's a six!";
      case 4:
        return 'Cracked away for four.';
      case 0:
        return 'Dot ball.';
      case 1:
        return 'One run.';
      case 2:
        return 'Two runs.';
      case 3:
        return 'Three runs.';
      default:
        return '${e.batRuns} runs.';
    }
  }
}

class _NumberedBall {
  final BallEvent event;
  final int overNo;
  final int ballNo;
  _NumberedBall(this.event, this.overNo, this.ballNo);
}

// ---------------- Info tab ----------------

class _InfoTab extends StatefulWidget {
  final Store store;
  final Match match;
  const _InfoTab({required this.store, required this.match});

  @override
  State<_InfoTab> createState() => _InfoTabState();
}

class _InfoTabState extends State<_InfoTab> {
  int section = 0; // 0 info, 1 squad, 2 compare, 3 head-to-head

  Store get store => widget.store;
  Match get match => widget.match;
  String nameOf(String id) => store.playerName(id);

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('INFO')),
            ButtonSegment(value: 1, label: Text('SQUAD')),
            ButtonSegment(value: 2, label: Text('COMPARE')),
            ButtonSegment(value: 3, label: Text('HEAD TO HEAD')),
          ],
          selected: {section},
          onSelectionChanged: (s) => setState(() => section = s.first),
          style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
            textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12)),
          ),
        ),
        const SizedBox(height: 12),
        if (section == 0) _infoSection(),
        if (section == 1) _squadSection(),
        if (section == 2) _compareSection(),
        if (section == 3) _h2hSection(),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _row(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(k, style: const TextStyle(color: Colors.white54)),
        ),
        Expanded(
          child: Text(v, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );

  Widget _infoSection() {
    final tid = match.tournamentId;
    final tname = tid == null
        ? 'Friendly'
        : (store.tournamentById(tid)?.name ?? 'Friendly');
    final perSide = match.xiA.length >= match.xiB.length
        ? match.xiA.length
        : match.xiB.length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row('Tournament', tname),
            if (match.matchTitle.isNotEmpty)
              _row('Match Title', match.matchTitle),
            _row('Format', 'T${match.oversLimit}'),
            _row('Ball Type', match.ballType),
            if (match.season.isNotEmpty) _row('Season', match.season),
            _row('Playing', '$perSide Per Side'),
            _row('Overs', '${match.oversLimit}'),
            if (match.venue.isNotEmpty) _row('Venue', match.venue),
            if (match.dateIso.isNotEmpty) _row('Date', match.dateIso),
            _row('Toss Won By', store.teamName(match.tossWinnerId)),
            _row(
              'Chose to',
              match.tossDecision == 'bat' ? 'Bat first' : 'Bowl first',
            ),
          ],
        ),
      ),
    );
  }

  Widget _squadSection() {
    Widget teamXi(String label, List<String> xi) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: kCopper,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 4),
        Card(
          child: Column(
            children: [
              for (var i = 0; i < xi.length; i++)
                ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 14,
                    backgroundColor: kTealDark,
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(fontSize: 11, color: Colors.white),
                    ),
                  ),
                  title: Text(nameOf(xi[i])),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
    return Column(
      children: [
        teamXi(store.teamName(match.teamAId), match.xiA),
        teamXi(store.teamName(match.teamBId), match.xiB),
      ],
    );
  }

  Widget _compareSection() {
    final stats = computeTeamStats(store.matches);
    final a = stats[match.teamAId];
    final b = stats[match.teamBId];
    Widget row(String label, String va, String vb) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              va,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60),
            ),
          ),
          Expanded(
            child: Text(
              vb,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    store.teamName(match.teamAId),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: kCyan,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Text('vs', style: TextStyle(color: Colors.white54)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    store.teamName(match.teamBId),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: kCyan,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            row('Played', '${a?.played ?? 0}', '${b?.played ?? 0}'),
            row('Won', '${a?.won ?? 0}', '${b?.won ?? 0}'),
            row('Lost', '${a?.lost ?? 0}', '${b?.lost ?? 0}'),
            row(
              'Win %',
              '${(a?.winPct ?? 0).toStringAsFixed(0)}%',
              '${(b?.winPct ?? 0).toStringAsFixed(0)}%',
            ),
            row(
              'Bat-first wins',
              '${a?.wonBattingFirst ?? 0}/${a?.battedFirst ?? 0}',
              '${b?.wonBattingFirst ?? 0}/${b?.battedFirst ?? 0}',
            ),
            row(
              'Chase wins',
              '${a?.wonChasing ?? 0}/${a?.chased ?? 0}',
              '${b?.wonChasing ?? 0}/${b?.chased ?? 0}',
            ),
            row('Toss won', '${a?.tossWon ?? 0}', '${b?.tossWon ?? 0}'),
          ],
        ),
      ),
    );
  }

  Widget _h2hSection() {
    final h = headToHead(store.matches, match.teamAId, match.teamBId);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text('Played: ${h.played}', style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            Text('${store.teamName(match.teamAId)} wins: ${h.aWins}'),
            Text('${store.teamName(match.teamBId)} wins: ${h.bWins}'),
            Text('Tied: ${h.tied} | No result: ${h.noResult}'),
          ],
        ),
      ),
    );
  }
}

// ---------------- Wagon wheel (per-batter picker) ----------------

class _WagonForInnings extends StatefulWidget {
  final InningsState inn;
  final String Function(String) nameOf;
  const _WagonForInnings({required this.inn, required this.nameOf});

  @override
  State<_WagonForInnings> createState() => _WagonForInningsState();
}

class _WagonForInningsState extends State<_WagonForInnings> {
  String? batterId;

  @override
  Widget build(BuildContext context) {
    final batters = widget.inn.batting.entries
        .where((e) => e.value.batted)
        .map((e) => e.key)
        .toList();
    batterId ??= batters.isNotEmpty ? batters.first : null;
    if (batterId == null) return const Text('No batting data.');
    if (!batters.contains(batterId)) batterId = batters.first;
    return Column(
      children: [
        DropdownButton<String>(
          value: batterId,
          items: batters
              .map(
                (id) =>
                    DropdownMenuItem(value: id, child: Text(widget.nameOf(id))),
              )
              .toList(),
          onChanged: (v) => setState(() => batterId = v),
        ),
        Center(child: WagonWheel(shots: wagonWheelShots(widget.inn, batterId!))),
        const SizedBox(height: 6),
        const WagonLegend(),
      ],
    );
  }
}
