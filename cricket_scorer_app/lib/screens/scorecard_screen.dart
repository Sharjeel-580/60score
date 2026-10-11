import 'package:flutter/material.dart';
import '../models.dart';
import '../pdf_export.dart';
import '../scoring.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/charts.dart';

class ScorecardScreen extends StatelessWidget {
  final Store store;
  final Match match;
  const ScorecardScreen({super.key, required this.store, required this.match});

  String nameOf(String id) => store.playerName(id);

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Scorecard'),
          actions: [
            IconButton(
              icon: const Icon(Icons.copy),
              tooltip: 'Copy scorecard as text',
              onPressed: () async {
                await copyToClipboard(
                    scorecardText(match, nameOf, store.teamName));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Scorecard copied to clipboard')));
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.picture_as_pdf),
              tooltip: 'Share scorecard PDF',
              onPressed: () async {
                final bytes =
                    await buildScorecardPdf(match, nameOf, store.teamName);
                await shareBytes('scorecard_${match.id}.pdf', bytes,
                    text: '60Score scorecard');
              },
            ),
          ],
          bottom: const TabBar(tabs: [
            Tab(text: 'Scorecard'),
            Tab(text: 'Ball by Ball'),
            Tab(text: 'Charts'),
          ]),
        ),
        body: TabBarView(children: [
          _scorecardTab(context),
          _ballsTab(),
          _chartsTab(),
        ]),
      ),
    );
  }

  Widget _scorecardTab(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(
            '${store.teamName(match.teamAId)} vs ${store.teamName(match.teamBId)}',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        Text(
            '${match.oversLimit} overs${match.venue.isNotEmpty ? ' • ${match.venue}' : ''}${match.dateIso.isNotEmpty ? ' • ${match.dateIso}' : ''}'),
        Text(
            'Toss: ${store.teamName(match.tossWinnerId)} chose to ${match.tossDecision} first'),
        if (match.resultText.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(match.resultText,
                style: const TextStyle(
                    color: kCyan, fontWeight: FontWeight.bold, fontSize: 15)),
          ),
        if (match.manOfMatchId.isNotEmpty)
          Text('Man of the Match: ${nameOf(match.manOfMatchId)}',
              style: const TextStyle(color: kCopper)),
        for (final inn in match.innings) ...[
          const Divider(height: 24),
          Text(
              '${store.teamName(inn.battingTeamId)} innings — ${inn.totalRuns}/${inn.wickets} (${oversText(inn.legalBalls, inn.ballsPerOver)} ov)',
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          _battingTable(inn),
          const SizedBox(height: 4),
          Text(
              'Extras: ${inn.extrasTotal} (wd ${inn.widesRuns}, nb ${inn.noBallRuns}, b ${inn.byeRuns}, lb ${inn.legByeRuns})',
              style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 8),
          _bowlingTable(inn),
          if (inn.fallOfWickets.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('Fall of Wickets',
                style: TextStyle(fontWeight: FontWeight.bold)),
            Text(inn.fallOfWickets
                .map((w) =>
                    '${w.runs}-${w.wicketNo} (${nameOf(w.playerId)}, ${w.overText})')
                .join(', ')),
          ],
          const SizedBox(height: 8),
          const Text('Partnerships',
              style: TextStyle(fontWeight: FontWeight.bold)),
          ...partnerships(inn).map((p) => Text(
              '${nameOf(p.batter1Id)} & ${nameOf(p.batter2Id)}: ${p.runs} (${p.balls})${p.unbroken ? ' *' : ''}')),
        ],
      ],
    );
  }

  Widget _battingTable(InningsState inn) {
    final rows = <DataRow>[];
    for (final pid in inn.battingXI) {
      final f = inn.batting[pid];
      if (f == null || !f.batted) continue;
      final sr = f.balls == 0 ? '-' : (f.runs * 100 / f.balls).toStringAsFixed(1);
      rows.add(DataRow(cells: [
        DataCell(Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(nameOf(pid)),
            Text(f.out ? resolveHowOut(f.howOut, nameOf) : 'not out',
                style: const TextStyle(fontSize: 11, color: Colors.white54)),
          ],
        )),
        DataCell(Text('${f.runs}')),
        DataCell(Text('${f.balls}')),
        DataCell(Text('${f.fours}')),
        DataCell(Text('${f.sixes}')),
        DataCell(Text(sr)),
      ]));
    }
    final dnb = inn.battingXI
        .where((id) => !(inn.batting[id]?.batted ?? false))
        .map(nameOf)
        .toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
        Text('Did not bat: ${dnb.join(', ')}',
            style: const TextStyle(color: Colors.white54, fontSize: 12)),
    ]);
  }

  Widget _bowlingTable(InningsState inn) {
    final rows = <DataRow>[];
    for (final pid in inn.bowling.keys) {
      final f = inn.bowling[pid]!;
      if (f.legalBalls == 0 && f.wides == 0 && f.noBalls == 0) continue;
      final econ = f.legalBalls == 0
          ? '-'
          : (f.runs * inn.ballsPerOver / f.legalBalls).toStringAsFixed(2);
      rows.add(DataRow(cells: [
        DataCell(Text(nameOf(pid))),
        DataCell(Text(oversText(f.legalBalls, inn.ballsPerOver))),
        DataCell(Text('${f.maidens}')),
        DataCell(Text('${f.runs}')),
        DataCell(Text('${f.wickets}')),
        DataCell(Text(econ)),
      ]));
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

  Widget _ballsTab() {
    if (match.innings.isEmpty) {
      return const Center(child: Text('No balls recorded yet.'));
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (var ii = 0; ii < match.innings.length; ii++) ...[
          Text(
              'Innings ${ii + 1} — ${store.teamName(match.innings[ii].battingTeamId)}',
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ..._overGroups(match.innings[ii]),
          const Divider(height: 24),
        ],
      ],
    );
  }

  List<Widget> _overGroups(InningsState inn) {
    final widgets = <Widget>[];
    var runsCum = 0;
    var wkts = 0;
    var legalInOver = 0;
    var overNo = 1;
    final lines = <String>[];
    void flush() {
      if (lines.isEmpty) return;
      widgets.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text('Over $overNo: ${lines.join('  ')}   →  $runsCum/$wkts',
            style: const TextStyle(fontSize: 13)),
      ));
      lines.clear();
    }

    for (final e in inn.events) {
      runsCum += e.totalRuns;
      if (e.isWicket) wkts++;
      lines.add(
          '${nameOf(e.strikerId).split(' ').first} to ${nameOf(e.bowlerId).split(' ').first}: ${e.display}');
      if (e.legalBall) {
        legalInOver++;
        if (legalInOver == inn.ballsPerOver) {
          flush();
          overNo++;
          legalInOver = 0;
        }
      }
    }
    flush();
    return widgets;
  }

  Widget _chartsTab() {
    if (match.innings.isEmpty) {
      return const Center(child: Text('No data yet.'));
    }
    final i1 = match.innings[0];
    final i2 = match.innings.length > 1 ? match.innings[1] : null;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Text('Runs Comparison (worm)',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        WormChart(
          innings1: wormData(i1),
          innings2: i2 != null ? wormData(i2) : const [],
          label1: store.teamName(i1.battingTeamId),
          label2: i2 != null ? store.teamName(i2.battingTeamId) : '',
        ),
        const Divider(height: 28),
        const Text('Over Comparison (Manhattan)',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        ManhattanChart(
          innings1: manhattanData(i1),
          innings2: i2 != null ? manhattanData(i2) : const [],
        ),
        const Row(children: [
          Icon(Icons.square, size: 12, color: Colors.amber),
          SizedBox(width: 4),
          Text('Innings 1'),
          SizedBox(width: 12),
          Icon(Icons.square, size: 12, color: Colors.lightBlue),
          SizedBox(width: 4),
          Text('Innings 2'),
        ]),
        const Divider(height: 28),
        const Text('Wagon Wheel',
            style: TextStyle(fontWeight: FontWeight.bold)),
        for (final inn in match.innings) ...[
          const SizedBox(height: 8),
          Text(store.teamName(inn.battingTeamId),
              style: const TextStyle(color: kCopper)),
          _WagonForInnings(inn: inn, nameOf: nameOf),
        ],
      ],
    );
  }
}

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
    return Column(children: [
      DropdownButton<String>(
        value: batterId,
        items: batters
            .map((id) => DropdownMenuItem(
                value: id, child: Text(widget.nameOf(id))))
            .toList(),
        onChanged: (v) => setState(() => batterId = v),
      ),
      Center(
          child: WagonWheel(
              zones: wagonWheelData(widget.inn, batterId!))),
      const Text(
          'Zones: 1 Third man • 2 Point • 3 Cover • 4 Long off • 5 Long on • 6 Mid-wicket • 7 Square leg • 8 Fine leg',
          style: TextStyle(fontSize: 11, color: Colors.white38)),
    ]);
  }
}
