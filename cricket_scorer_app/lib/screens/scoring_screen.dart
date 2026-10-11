import 'package:flutter/material.dart';

import '../models.dart';
import '../scoring.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/charts.dart';
import 'scorecard_screen.dart';

class ScoringScreen extends StatefulWidget {
  final Store store;
  final Match match;
  const ScoringScreen({super.key, required this.store, required this.match});

  @override
  State<ScoringScreen> createState() => _ScoringScreenState();
}

class _ScoringScreenState extends State<ScoringScreen> {
  Store get store => widget.store;
  Match get match => widget.match;
  int? selectedZone;

  InningsState get inn {
    if (match.innings.isEmpty) startInnings(match, 1);
    return match.innings.last;
  }

  String nameOf(String id) => store.playerName(id);
  Team? teamOf(String id) => store.teamById(id);

  Future<void> _afterChange() async {
    computeResult(match, store.teamName);
    await store.persist();
    if (mounted) setState(() {});
  }

  // ---------- dialogs ----------

  Future<int?> _pickPlayer(
    String title,
    List<String> ids, {
    String? excludeId,
  }) async {
    final list = ids.where((id) => id != excludeId).toList();
    return showDialog<int>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: list.length,
            itemBuilder: (c, i) => ListTile(
              title: Text(nameOf(list[i])),
              onTap: () => Navigator.pop(c, i),
            ),
          ),
        ),
      ),
    ).then((idx) => idx == null ? null : list.indexOf(list[idx]));
  }

  Future<void> _chooseOpeners() async {
    final battingXI = inn.battingXI;
    final bowlingXI = inn.bowlingXI;
    String? striker = battingXI.isNotEmpty ? battingXI[0] : null;
    String? nonStriker = battingXI.length > 1 ? battingXI[1] : null;
    String? bowler = bowlingXI.isNotEmpty ? bowlingXI[0] : null;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('Openers & first bowler'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _playerDropdown(
                'Striker',
                battingXI,
                striker,
                (v) => setD(() => striker = v),
              ),
              _playerDropdown(
                'Non-striker',
                battingXI,
                nonStriker,
                (v) => setD(() => nonStriker = v),
              ),
              _playerDropdown(
                'Bowler',
                bowlingXI,
                bowler,
                (v) => setD(() => bowler = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Start'),
            ),
          ],
        ),
      ),
    );
    if (ok == true && striker != null && nonStriker != null && bowler != null) {
      if (striker == nonStriker) {
        _snack('Striker and non-striker must be different');
        return;
      }
      setOpeners(inn, striker!, nonStriker!, bowler!);
      await _afterChange();
    }
  }

  Widget _playerDropdown(
    String label,
    List<String> ids,
    String? value,
    void Function(String?) onChanged,
  ) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: ids
          .map((id) => DropdownMenuItem(value: id, child: Text(nameOf(id))))
          .toList(),
      onChanged: onChanged,
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _chooseNextBatter() async {
    final inn = this.inn;
    final atCrease = {inn.strikerId, inn.nonStrikerId}..remove('');
    final out = inn.batting.entries
        .where((e) => e.value.out)
        .map((e) => e.key)
        .toSet();
    var available = inn.battingXI
        .where((id) => !atCrease.contains(id) && !out.contains(id))
        .toList();
    if (available.isEmpty && match.lastManStands) {
      // Last man stands: a dismissed batter may return as the partner.
      available = inn.battingXI.where((id) => !atCrease.contains(id)).toList();
    }
    final idx = await _pickPlayer('Next batter', available);
    if (idx != null) {
      setNextBatter(inn, available[idx]);
      await _afterChange();
    }
  }

  Future<void> _chooseBowler() async {
    final inn = this.inn;
    final available = inn.bowlingXI
        .where((id) => id != inn.lastBowlerId)
        .toList();
    final idx = await _pickPlayer('Bowler for next over', available);
    if (idx != null) {
      if (!setBowler(inn, available[idx])) {
        _snack('That bowler bowled the previous over');
        return;
      }
      await _afterChange();
    }
  }

  Future<BallInput?> _ballDialog({
    required String title,
    int initialRuns = 0,
    bool runsEditable = true,
    List<String> wicketTypes = const [],
    String runsLabel = 'Runs',
  }) async {
    var runs = initialRuns;
    String? wicketType = wicketTypes.isEmpty ? null : null;
    String? fielder;
    var outIsStriker = true;
    final bowlingXI = inn.bowlingXI;
    return showDialog<BallInput>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (runsEditable)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        onPressed: () =>
                            setD(() => runs = runs > 0 ? runs - 1 : 0),
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      Text(
                        '$runs',
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        onPressed: () => setD(() => runs++),
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                      Text(runsLabel),
                    ],
                  ),
                if (wicketTypes.isNotEmpty) ...[
                  const Divider(),
                  DropdownButtonFormField<String?>(
                    initialValue: wicketType,
                    decoration: const InputDecoration(
                      labelText: 'Wicket (optional)',
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('No wicket'),
                      ),
                      ...wicketTypes.map(
                        (w) => DropdownMenuItem(value: w, child: Text(w)),
                      ),
                    ],
                    onChanged: (v) => setD(() => wicketType = v),
                  ),
                  if (wicketType != null &&
                      wicketType != 'Bowled' &&
                      wicketType != 'LBW' &&
                      wicketType != 'Hit Wicket')
                    _playerDropdown(
                      'Fielder',
                      bowlingXI,
                      fielder,
                      (v) => setD(() => fielder = v),
                    ),
                  if (wicketType == 'Run Out')
                    DropdownButtonFormField<bool>(
                      initialValue: outIsStriker,
                      decoration: const InputDecoration(
                        labelText: 'Who is out?',
                      ),
                      items: const [
                        DropdownMenuItem(value: true, child: Text('Striker')),
                        DropdownMenuItem(
                          value: false,
                          child: Text('Non-striker'),
                        ),
                      ],
                      onChanged: (v) => setD(() => outIsStriker = v ?? true),
                    ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final typeMap = {
                  'Bowled': 'bowled',
                  'Caught': 'caught',
                  'LBW': 'lbw',
                  'Run Out': 'runOut',
                  'Stumped': 'stumped',
                  'Hit Wicket': 'hitWicket',
                };
                Navigator.pop(
                  c,
                  BallInput(
                    batRuns: runs,
                    isWicket: wicketType != null,
                    wicketType: wicketType == null
                        ? ''
                        : (typeMap[wicketType] ?? ''),
                    fielderId: fielder ?? '',
                    outPlayerId: wicketType == 'Run Out'
                        ? (outIsStriker ? inn.strikerId : inn.nonStrikerId)
                        : '',
                  ),
                );
              },
              child: const Text('Record ball'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _record(BallInput input) async {
    input.zone = selectedZone;
    final ok = applyBall(inn, input);
    if (!ok) {
      _snack('Ball could not be recorded');
      return;
    }
    selectedZone = null;
    await _afterChange();
  }

  // ---------- build ----------

  @override
  Widget build(BuildContext context) {
    final inn = this.inn;
    final battingTeam = teamOf(inn.battingTeamId);
    final needsOpeners =
        inn.events.isEmpty && inn.strikerId == '' && match.status == 'live';
    final crr = inn.legalBalls == 0
        ? 0.0
        : inn.totalRuns * inn.ballsPerOver / inn.legalBalls;
    final target = inn.target;
    final needRuns = target > 0 ? target - inn.totalRuns : 0;
    final ballsLeft = inn.oversLimit * inn.ballsPerOver - inn.legalBalls;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${store.teamName(match.teamAId)} vs ${store.teamName(match.teamBId)}',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: 'Undo last ball',
            onPressed: inn.events.isEmpty
                ? null
                : () async {
                    if (undoLastBall(inn)) {
                      if (match.status == 'completed') {
                        match.status = 'live';
                        match.resultText = '';
                      }
                      await _afterChange();
                    }
                  },
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              final nav = Navigator.of(context);
              if (v == 'scorecard') {
                nav.push(
                  MaterialPageRoute(
                    builder: (_) => ScorecardScreen(store: store, match: match),
                  ),
                );
              } else if (v == 'noresult') {
                match.status = 'noResult';
                match.resultText = 'No result';
                await store.persist();
                nav.pop();
              } else if (v == 'delete') {
                await store.deleteMatch(match.id);
                nav.pop();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'scorecard', child: Text('View scorecard')),
              PopupMenuItem(value: 'noresult', child: Text('Mark no result')),
              PopupMenuItem(value: 'delete', child: Text('Delete match')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${battingTeam?.name ?? ''} — Innings ${match.innings.length}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${inn.totalRuns}/${inn.wickets}  (${oversText(inn.legalBalls, inn.ballsPerOver)} ov)   CRR ${crr.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: kCyan,
                    ),
                  ),
                  if (target > 0)
                    Text(
                      'Target $target • Need $needRuns off $ballsLeft balls',
                      style: const TextStyle(color: kCopper),
                    ),
                  const Divider(),
                  if (inn.strikerId.isNotEmpty)
                    _creaseRow(inn.strikerId, true, inn),
                  if (inn.nonStrikerId.isNotEmpty)
                    _creaseRow(inn.nonStrikerId, false, inn),
                  if (inn.currentBowlerId.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Bowling: ${nameOf(inn.currentBowlerId)} ${_bowlerLine(inn)}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                  const SizedBox(height: 6),
                  _thisOverRow(inn),
                ],
              ),
            ),
          ),
          if (inn.events.isNotEmpty && match.status == 'live')
            _liveWagonCard(inn),
          if (needsOpeners)
            FilledButton.icon(
              onPressed: _chooseOpeners,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Select openers & bowler'),
            )
          else if (match.status == 'live' &&
              inn.awaitingBatter &&
              !inn.isComplete)
            FilledButton.icon(
              onPressed: _chooseNextBatter,
              icon: const Icon(Icons.person_add),
              label: const Text('Select next batter'),
            )
          else if (match.status == 'live' &&
              inn.awaitingBowler &&
              !inn.isComplete)
            FilledButton.icon(
              onPressed: _chooseBowler,
              icon: const Icon(Icons.sports_baseball),
              label: const Text('Select bowler for next over'),
            )
          else if (inn.isComplete)
            _inningsBreakCard()
          else if (match.status == 'live')
            _scoringPad(),
        ],
      ),
    );
  }

  Widget _creaseRow(String pid, bool striker, InningsState inn) {
    final f = inn.batting[pid];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Text(
        '${nameOf(pid)}${striker ? ' *' : ''}   ${f?.runs ?? 0} (${f?.balls ?? 0})',
        style: TextStyle(
          fontWeight: striker ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  String _bowlerLine(InningsState inn) {
    final f = inn.bowling[inn.currentBowlerId];
    if (f == null) return '';
    return '${oversText(f.legalBalls, inn.ballsPerOver)}-${f.maidens}-${f.runs}-${f.wickets}';
  }

  Widget _thisOverRow(InningsState inn) {
    final events = inn.events;
    var legal = 0;
    var start = 0;
    for (var i = 0; i < events.length; i++) {
      if (events[i].legalBall) {
        legal++;
        if (legal % inn.ballsPerOver == 1 && i > 0) start = i;
        if (legal % inn.ballsPerOver == 0) start = i + 1;
      }
    }
    final overEvents = events.sublist(start.clamp(0, events.length));
    return Row(
      children: [
        const Text('This over: ', style: TextStyle(color: Colors.white60)),
        ...overEvents.map(
          (e) => Container(
            margin: const EdgeInsets.only(right: 4),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: e.isWicket
                  ? kOrangeRed
                  : (e.batRuns >= 4 && e.extraType == 'none' ? kTeal : kPanel2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(e.display, style: const TextStyle(fontSize: 12)),
          ),
        ),
      ],
    );
  }

  /// Live wagon wheel for the current striker, rebuilt after every ball.
  Widget _liveWagonCard(InningsState inn) {
    final striker = inn.strikerId;
    if (striker.isEmpty) return const SizedBox.shrink();
    final zones = wagonWheelData(inn, striker);
    final shotCounts = <int, int>{}; // runs value -> balls (striker)
    var strikerWkts = 0;
    final wktZones = <int, int>{}; // zone -> wickets (whole innings)
    for (final e in inn.events) {
      if (e.zone != null && e.isWicket) {
        wktZones[e.zone!] = (wktZones[e.zone!] ?? 0) + 1;
      }
      if (e.strikerId != striker || e.extraType == 'wide') continue;
      if (e.isWicket && e.outPlayerId == striker) strikerWkts++;
      shotCounts[e.batRuns] = (shotCounts[e.batRuns] ?? 0) + 1;
    }
    Widget chip(String label) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: kPanel2,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
    return Card(
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Text(
          'Wagon wheel - live (${nameOf(striker)})',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        children: [
          Center(child: WagonWheel(zones: zones)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: [
              for (final r in [1, 2, 3, 4, 6])
                chip('${r}s: ${shotCounts[r] ?? 0}'),
              chip('W: $strikerWkts'),
            ],
          ),
          if (wktZones.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 8),
              child: Text(
                'Wickets by zone: ${wktZones.entries.map((e) => 'Z${e.key}: ${e.value}').join('  ')}',
                style: const TextStyle(fontSize: 12, color: Colors.white54),
              ),
            )
          else
            const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Zones: 1 Third man | 2 Point | 3 Cover | 4 Long off | 5 Long on | 6 Mid-wicket | 7 Square leg | 8 Fine leg',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Colors.white38),
            ),
          ),
        ],
      ),
    );
  }

  Widget _inningsBreakCard() {
    final isFirst = match.innings.length == 1;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Text(
              isFirst ? 'Innings break' : 'Match finished',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (isFirst)
              FilledButton.icon(
                onPressed: () async {
                  startInnings(match, 2);
                  await _afterChange();
                },
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start 2nd innings'),
              )
            else ...[
              Text(
                computeResult(match, store.teamName),
                style: const TextStyle(color: kCyan, fontSize: 15),
              ),
              const SizedBox(height: 8),
              _momPicker(),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: () async {
                  final nav = Navigator.of(context);
                  computeResult(match, store.teamName);
                  match.status = 'completed';
                  await store.persist();
                  nav.pushReplacement(
                    MaterialPageRoute(
                      builder: (_) =>
                          ScorecardScreen(store: store, match: match),
                    ),
                  );
                },
                icon: const Icon(Icons.emoji_events),
                label: const Text('Finish & view scorecard'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _momPicker() {
    final xi = {...match.xiA, ...match.xiB}.toList();
    return DropdownButtonFormField<String>(
      initialValue: match.manOfMatchId.isEmpty ? null : match.manOfMatchId,
      decoration: const InputDecoration(
        labelText: 'Man of the Match (optional)',
      ),
      items: [
        const DropdownMenuItem(value: '', child: Text('None')),
        ...xi.map((id) => DropdownMenuItem(value: id, child: Text(nameOf(id)))),
      ],
      onChanged: (v) async {
        match.manOfMatchId = v ?? '';
        await store.persist();
        setState(() {});
      },
    );
  }

  Widget _scoringPad() {
    Widget runBtn(String label, int runs) => Expanded(
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: runs >= 4 ? kTeal : kPanel2,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onPressed: () => _record(BallInput(batRuns: runs)),
          child: Text(label, style: const TextStyle(fontSize: 17)),
        ),
      ),
    );
    Widget extraBtn(String label, VoidCallback fn) => Expanded(
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
          onPressed: fn,
          child: Text(label),
        ),
      ),
    );
    return Column(
      children: [
        const SizedBox(height: 8),
        // wagon-wheel zone selector
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              const Text('Zone: ', style: TextStyle(color: Colors.white60)),
              ChoiceChip(
                label: const Text('None'),
                selected: selectedZone == null,
                onSelected: (_) => setState(() => selectedZone = null),
              ),
              for (var z = 1; z <= 8; z++)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: ChoiceChip(
                    label: Text('$z'),
                    selected: selectedZone == z,
                    onSelected: (_) => setState(() => selectedZone = z),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            runBtn('0', 0),
            runBtn('1', 1),
            runBtn('2', 2),
            runBtn('3', 3),
          ],
        ),
        Row(
          children: [
            runBtn('4', 4),
            runBtn('6', 6),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: kPanel2,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () async {
                    final input = await _ballDialog(
                      title: 'Other runs',
                      runsLabel: 'runs',
                    );
                    if (input != null) {
                      _record(BallInput(batRuns: input.batRuns));
                    }
                  },
                  child: const Text('Other', style: TextStyle(fontSize: 16)),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: kOrangeRed,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () async {
                    final input = await _ballDialog(
                      title: 'Wicket',
                      runsEditable: true,
                      runsLabel: 'runs completed (run out)',
                      wicketTypes: const [
                        'Bowled',
                        'Caught',
                        'LBW',
                        'Run Out',
                        'Stumped',
                        'Hit Wicket',
                      ],
                    );
                    if (input != null && input.isWicket) {
                      if (input.wicketType != 'runOut') input.batRuns = 0;
                      _record(input);
                    }
                  },
                  child: const Text('Wicket', style: TextStyle(fontSize: 16)),
                ),
              ),
            ),
          ],
        ),
        Row(
          children: [
            extraBtn('Wide', () async {
              final input = await _ballDialog(
                title: 'Wide ball',
                runsLabel: 'extra runs beyond penalty',
                wicketTypes: const ['Stumped', 'Run Out'],
              );
              if (input != null) {
                _record(
                  BallInput(
                    extraType: 'wide',
                    extraRuns: input.batRuns,
                    isWicket: input.isWicket,
                    wicketType: input.wicketType,
                    fielderId: input.fielderId,
                    outPlayerId: input.outPlayerId,
                  ),
                );
              }
            }),
            extraBtn('No Ball', () async {
              final input = await _ballDialog(
                title: 'No ball',
                runsLabel: 'runs off the bat',
                wicketTypes: const ['Run Out'],
              );
              if (input != null) {
                _record(
                  BallInput(
                    extraType: 'noBall',
                    batRuns: input.batRuns,
                    isWicket: input.isWicket,
                    wicketType: input.wicketType,
                    fielderId: input.fielderId,
                    outPlayerId: input.outPlayerId,
                  ),
                );
              }
            }),
            extraBtn('Bye', () async {
              final input = await _ballDialog(
                title: 'Byes',
                initialRuns: 1,
                runsLabel: 'byes',
                wicketTypes: const ['Run Out'],
              );
              if (input != null) {
                _record(
                  BallInput(
                    extraType: 'bye',
                    batRuns: input.batRuns,
                    isWicket: input.isWicket,
                    wicketType: input.wicketType,
                    fielderId: input.fielderId,
                    outPlayerId: input.outPlayerId,
                  ),
                );
              }
            }),
            extraBtn('Leg Bye', () async {
              final input = await _ballDialog(
                title: 'Leg byes',
                initialRuns: 1,
                runsLabel: 'leg byes',
                wicketTypes: const ['Run Out'],
              );
              if (input != null) {
                _record(
                  BallInput(
                    extraType: 'legBye',
                    batRuns: input.batRuns,
                    isWicket: input.isWicket,
                    wicketType: input.wicketType,
                    fielderId: input.fielderId,
                    outPlayerId: input.outPlayerId,
                  ),
                );
              }
            }),
          ],
        ),
        const Text(
          'Zones: 1 Third man • 2 Point • 3 Cover • 4 Long off • 5 Long on • 6 Mid-wicket • 7 Square leg • 8 Fine leg',
          style: TextStyle(fontSize: 11, color: Colors.white38),
        ),
      ],
    );
  }
}
