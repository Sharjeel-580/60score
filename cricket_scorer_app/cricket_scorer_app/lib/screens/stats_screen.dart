import 'package:flutter/material.dart';
import '../models.dart';
import '../scoring.dart';
import '../store.dart';
import '../theme.dart';
import 'scorecard_screen.dart';

Map<String, CareerStats> careerOf(Store store) {
  final map = computeCareerStats(store.matches);
  applyManualStats(map, store.manualStats);
  return map;
}

/// All known persons (team squads + registered players), id -> name.
Map<String, String> allPersons(Store store) {
  final map = <String, String>{};
  for (final t in store.teams) {
    for (final p in t.players) {
      map[p.id] = p.name;
    }
  }
  for (final r in store.regPlayers) {
    map[r.id] = r.name;
  }
  return map;
}

class StatsScreen extends StatefulWidget {
  final Store store;
  const StatsScreen({super.key, required this.store});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  Store get store => widget.store;

  @override
  Widget build(BuildContext context) {
    final career = careerOf(store);
    final persons = allPersons(store);
    final byRuns = career.values.toList()
      ..sort((a, b) => b.runs.compareTo(a.runs));
    final byWkts = career.values.toList()
      ..sort((a, b) => b.wickets.compareTo(a.wickets));
    final bySR = career.values.where((c) => c.ballsFaced >= 20).toList()
      ..sort((a, b) => b.battingSR.compareTo(a.battingSR));
    final byEcon = career.values.where((c) => c.ballsBowled >= 24).toList()
      ..sort((a, b) => a.economy.compareTo(b.economy));
    final teamStats = computeTeamStats(store.matches);
    final archive =
        store.matches.where((m) => m.status != 'live').toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Stats & History')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _section('Leaderboard — Most Runs'),
          for (final c in byRuns.take(10))
            if (c.runs > 0)
              _playerTile(context, c,
                  '${c.runs} runs • Avg ${c.battingAverage.toStringAsFixed(1)} • SR ${c.battingSR.toStringAsFixed(0)}'),
          _section('Leaderboard — Most Wickets'),
          for (final c in byWkts.take(10))
            if (c.wickets > 0)
              _playerTile(context, c,
                  '${c.wickets} wkts • Econ ${c.economy.toStringAsFixed(2)} • Best ${c.bestFigures}'),
          _section('Best Batting Strike Rate (min 20 balls)'),
          for (final c in bySR.take(5))
            _playerTile(context, c, 'SR ${c.battingSR.toStringAsFixed(1)}'),
          _section('Best Bowling Economy (min 4 overs)'),
          for (final c in byEcon.take(5))
            _playerTile(context, c, 'Econ ${c.economy.toStringAsFixed(2)}'),
          const Divider(height: 28),
          _section('Players'),
          Wrap(spacing: 8, children: [
            FilledButton.tonalIcon(
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => CompareScreen(store: store))),
              icon: const Icon(Icons.compare_arrows),
              label: const Text('Compare players 1-to-1'),
            ),
            FilledButton.tonalIcon(
              onPressed: () async {
                await _addPastScore(context);
                if (mounted) setState(() {});
              },
              icon: const Icon(Icons.add_chart),
              label: const Text('Add past scores'),
            ),
          ]),
          for (final entry in persons.entries)
            ListTile(
              dense: true,
              leading: const CircleAvatar(child: Icon(Icons.person, size: 18)),
              title: Text(entry.value),
              subtitle: Text(career.containsKey(entry.key)
                  ? '${career[entry.key]!.matches} matches • ${career[entry.key]!.runs} runs • ${career[entry.key]!.wickets} wkts • MVP ${career[entry.key]!.mvpPoints.toStringAsFixed(0)}'
                  : 'No matches yet'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => PlayerProfileScreen(
                          store: store, playerId: entry.key))),
            ),
          const Divider(height: 28),
          _section('Teams'),
          for (final t in store.teams)
            Builder(builder: (context) {
              final s = teamStats[t.id];
              return ListTile(
                dense: true,
                title: Text(t.name),
                subtitle: Text(s == null
                    ? 'No matches'
                    : 'P ${s.played} • W ${s.won} • L ${s.lost} • Win% ${s.winPct.toStringAsFixed(0)} • Bat first W ${s.wonBattingFirst}/${s.battedFirst} • Chase W ${s.wonChasing}/${s.chased} • Toss won ${s.tossWon}'),
              );
            }),
          const SizedBox(height: 6),
          FilledButton.tonalIcon(
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => HeadToHeadScreen(store: store))),
            icon: const Icon(Icons.sports),
            label: const Text('Head-to-head'),
          ),
          const Divider(height: 28),
          _section('Past score entries (manual)'),
          if (store.manualStats.isEmpty)
            const Text('No manual entries. Use "Add past scores" to bring in old performances.',
                style: TextStyle(color: Colors.white54)),
          for (final e in store.manualStats)
            ListTile(
              dense: true,
              title: Text('${e.playerName} — ${e.matchLabel}'),
              subtitle: Text(
                  '${e.runs} (${e.balls}) • ${e.wickets} wkts • ${e.runsConceded} conceded • manual entry'),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  await store.deleteManualStat(e.id);
                  if (mounted) setState(() {});
                },
              ),
            ),
          const Divider(height: 28),
          _section('Match Archive'),
          if (archive.isEmpty)
            const Text('No completed matches yet.',
                style: TextStyle(color: Colors.white54)),
          for (final m in archive)
            Card(
              child: ListTile(
                title: Text(
                    '${store.teamName(m.teamAId)} vs ${store.teamName(m.teamBId)}'),
                subtitle: Text(m.resultText.isNotEmpty
                    ? m.resultText
                    : '${m.dateIso} • ${m.status}'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    await store.deleteMatch(m.id);
                    if (mounted) setState(() {});
                  },
                ),
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            ScorecardScreen(store: store, match: m))),
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 4),
        child: Text(title,
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.bold, color: kCopper)),
      );

  Widget _playerTile(BuildContext context, CareerStats c, String sub) {
    return ListTile(
      dense: true,
      title: Text(store.playerName(c.playerId)),
      subtitle: Text(sub),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) =>
                  PlayerProfileScreen(store: store, playerId: c.playerId))),
    );
  }

  Future<void> _addPastScore(BuildContext context) async {
    final persons = allPersons(store);
    String? playerId = persons.isNotEmpty ? persons.keys.first : null;
    final nameCtrl = TextEditingController();
    final labelCtrl = TextEditingController();
    final runs = TextEditingController(text: '0');
    final balls = TextEditingController(text: '0');
    final fours = TextEditingController(text: '0');
    final sixes = TextEditingController(text: '0');
    final wkts = TextEditingController(text: '0');
    final conceded = TextEditingController(text: '0');
    final ballsBowled = TextEditingController(text: '0');
    var notOut = false;
    int n(TextEditingController c) => int.tryParse(c.text) ?? 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('Add past score (manual)'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (persons.isNotEmpty)
                DropdownButtonFormField<String>(
                  initialValue: playerId,
                  decoration: const InputDecoration(labelText: 'Player'),
                  items: persons.entries
                      .map((e) => DropdownMenuItem(
                          value: e.key, child: Text(e.value)))
                      .toList(),
                  onChanged: (v) => setD(() => playerId = v),
                ),
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Or type a new player name')),
              TextField(controller: labelCtrl, decoration: const InputDecoration(labelText: 'Match label (e.g. Season 1 Final)')),
              Row(children: [
                Expanded(child: TextField(controller: runs, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Runs'))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: balls, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Balls'))),
              ]),
              Row(children: [
                Expanded(child: TextField(controller: fours, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '4s'))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: sixes, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '6s'))),
              ]),
              CheckboxListTile(value: notOut, title: const Text('Not out'), onChanged: (v) => setD(() => notOut = v ?? false)),
              Row(children: [
                Expanded(child: TextField(controller: wkts, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Wickets'))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: conceded, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Runs conceded'))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: ballsBowled, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Balls bowled'))),
              ]),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Add')),
          ],
        ),
      ),
    );
    if (ok == true) {
      var id = playerId;
      var name = id != null ? (persons[id] ?? '') : '';
      if (nameCtrl.text.trim().isNotEmpty) {
        id = Store.newId('reg');
        name = nameCtrl.text.trim();
        await store.upsertRegPlayer(RegPlayer(id: id, name: name));
      }
      if (id == null) return;
      await store.addManualStat(ManualStatEntry(
        id: Store.newId('manual'),
        playerId: id,
        playerName: name,
        matchLabel: labelCtrl.text.trim().isEmpty ? 'Past match' : labelCtrl.text.trim(),
        dateIso: DateTime.now().toIso8601String().substring(0, 10),
        runs: n(runs),
        balls: n(balls),
        fours: n(fours),
        sixes: n(sixes),
        notOut: notOut,
        wickets: n(wkts),
        runsConceded: n(conceded),
        ballsBowled: n(ballsBowled),
      ));
    }
  }
}

class PlayerProfileScreen extends StatelessWidget {
  final Store store;
  final String playerId;
  const PlayerProfileScreen(
      {super.key, required this.store, required this.playerId});

  @override
  Widget build(BuildContext context) {
    final career = careerOf(store);
    final c = career[playerId] ?? CareerStats(playerId);
    final reg = store.regById(playerId);
    final manual = store.manualStats.where((e) => e.playerId == playerId);
    Widget row(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(child: Text(k, style: const TextStyle(color: Colors.white70))),
            Text(v, style: const TextStyle(fontWeight: FontWeight.bold)),
          ]),
        );
    return Scaffold(
      appBar: AppBar(title: Text(store.playerName(playerId))),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          if (reg != null)
            Text(
                '${reg.role} • ${reg.battingStyle} bat • ${reg.bowlingStyle}'
                '${reg.area.isNotEmpty ? ' • ${reg.area}' : ''}'
                '${reg.age > 0 ? ' • Age ${reg.age}' : ''}'
                '${reg.category.isNotEmpty ? ' • ${reg.category}' : ''}',
                style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 8),
          const Text('Batting', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kCyan)),
          row('Matches', '${c.matches}'),
          row('Innings', '${c.inningsBatted}'),
          row('Runs', '${c.runs}'),
          row('Balls faced', '${c.ballsFaced}'),
          row('High score', '${c.highScore}'),
          row('Average', c.battingAverage.toStringAsFixed(2)),
          row('Strike rate', c.battingSR.toStringAsFixed(1)),
          row('50s / 100s', '${c.fifties} / ${c.hundreds}'),
          row('4s / 6s', '${c.fours} / ${c.sixes}'),
          row('Not outs', '${c.notOuts}'),
          const Divider(height: 24),
          const Text('Bowling', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kCyan)),
          row('Balls bowled', '${c.ballsBowled}'),
          row('Overs', oversText(c.ballsBowled, 6)),
          row('Runs conceded', '${c.runsConceded}'),
          row('Wickets', '${c.wickets}'),
          row('Average', c.wickets == 0 ? '-' : c.bowlingAverage.toStringAsFixed(2)),
          row('Economy', c.economy.toStringAsFixed(2)),
          row('Strike rate', c.wickets == 0 ? '-' : c.bowlingSR.toStringAsFixed(1)),
          row('Best figures', c.bestFigures),
          const Divider(height: 24),
          const Text('Fielding & MVP', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kCyan)),
          row('Catches', '${c.catches}'),
          row('Stumpings', '${c.stumpings}'),
          row('Run outs', '${c.runOuts}'),
          row('MVP points', c.mvpPoints.toStringAsFixed(0)),
          if (manual.isNotEmpty) ...[
            const Divider(height: 24),
            const Text('Manual past-score entries',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kCopper)),
            for (final e in manual)
              ListTile(
                dense: true,
                title: Text(e.matchLabel),
                subtitle: Text(
                    '${e.runs} (${e.balls}) • ${e.wickets} wkts • ${e.runsConceded} conceded'),
              ),
          ],
        ],
      ),
    );
  }
}

class CompareScreen extends StatefulWidget {
  final Store store;
  const CompareScreen({super.key, required this.store});

  @override
  State<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends State<CompareScreen> {
  String? aId;
  String? bId;

  @override
  Widget build(BuildContext context) {
    final persons = allPersons(widget.store);
    final career = careerOf(widget.store);
    aId ??= persons.isNotEmpty ? persons.keys.elementAt(0) : null;
    if (persons.length > 1) bId ??= persons.keys.elementAt(1);
    final a = aId != null ? (career[aId] ?? CareerStats(aId!)) : null;
    final b = bId != null ? (career[bId] ?? CareerStats(bId!)) : null;
    Widget picker(String label, String? value, void Function(String?) fn) {
      return DropdownButtonFormField<String>(
        initialValue: value,
        decoration: InputDecoration(labelText: label),
        items: persons.entries
            .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
            .toList(),
        onChanged: fn,
      );
    }

    Widget row(String label, String va, String vb) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Expanded(child: Text(va, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold))),
            Expanded(child: Text(label, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60))),
            Expanded(child: Text(vb, style: const TextStyle(fontWeight: FontWeight.bold))),
          ]),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Compare players')),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Row(children: [
            Expanded(child: picker('Player A', aId, (v) => setState(() => aId = v))),
            const SizedBox(width: 10),
            Expanded(child: picker('Player B', bId, (v) => setState(() => bId = v))),
          ]),
          const SizedBox(height: 16),
          if (a != null && b != null) ...[
            row('Matches', '${a.matches}', '${b.matches}'),
            row('Runs', '${a.runs}', '${b.runs}'),
            row('High score', '${a.highScore}', '${b.highScore}'),
            row('Bat average', a.battingAverage.toStringAsFixed(1), b.battingAverage.toStringAsFixed(1)),
            row('Bat SR', a.battingSR.toStringAsFixed(1), b.battingSR.toStringAsFixed(1)),
            row('50s / 100s', '${a.fifties}/${a.hundreds}', '${b.fifties}/${b.hundreds}'),
            row('Wickets', '${a.wickets}', '${b.wickets}'),
            row('Economy', a.economy.toStringAsFixed(2), b.economy.toStringAsFixed(2)),
            row('Best figures', a.bestFigures, b.bestFigures),
            row('MVP points', a.mvpPoints.toStringAsFixed(0), b.mvpPoints.toStringAsFixed(0)),
          ],
        ],
      ),
    );
  }
}

class HeadToHeadScreen extends StatefulWidget {
  final Store store;
  const HeadToHeadScreen({super.key, required this.store});

  @override
  State<HeadToHeadScreen> createState() => _HeadToHeadScreenState();
}

class _HeadToHeadScreenState extends State<HeadToHeadScreen> {
  String? aId;
  String? bId;

  @override
  Widget build(BuildContext context) {
    final teams = widget.store.teams;
    aId ??= teams.isNotEmpty ? teams[0].id : null;
    if (teams.length > 1) bId ??= teams[1].id;
    final h = (aId != null && bId != null && aId != bId)
        ? headToHead(widget.store.matches, aId!, bId!)
        : null;
    return Scaffold(
      appBar: AppBar(title: const Text('Head-to-head')),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: aId,
                decoration: const InputDecoration(labelText: 'Team A'),
                items: teams.map((t) => DropdownMenuItem(value: t.id, child: Text(t.name))).toList(),
                onChanged: (v) => setState(() => aId = v),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: bId,
                decoration: const InputDecoration(labelText: 'Team B'),
                items: teams.map((t) => DropdownMenuItem(value: t.id, child: Text(t.name))).toList(),
                onChanged: (v) => setState(() => bId = v),
              ),
            ),
          ]),
          const SizedBox(height: 20),
          if (h != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  Text('Played: ${h.played}', style: const TextStyle(fontSize: 16)),
                  const SizedBox(height: 8),
                  Text('${widget.store.teamName(aId!)} wins: ${h.aWins}'),
                  Text('${widget.store.teamName(bId!)} wins: ${h.bWins}'),
                  Text('Tied: ${h.tied} • No result: ${h.noResult}'),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}
