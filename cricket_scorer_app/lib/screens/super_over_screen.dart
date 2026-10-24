// Super Over screen (Feature 5): compact ball-by-ball scoring for
// ONE super-over innings at a time. Super-over innings live in
// Match.superOverInnings (outside Match.innings), scored with the
// same applyBall / undoLastBall engine as the main match, so the
// main scorecard, NRR and career stats are never touched by them.
//
// Known simplification (documented in scoring.dart): a batsman
// dismissed in super-over round 1 is not barred from round 2 —
// every round starts from the full match XI with fresh figures.
import 'package:flutter/material.dart';

import '../models.dart';
import '../scoring.dart';
import '../store.dart';
import '../theme.dart';

class SuperOverScreen extends StatefulWidget {
  final Store store;
  final Match match;
  const SuperOverScreen({super.key, required this.store, required this.match});

  @override
  State<SuperOverScreen> createState() => _SuperOverScreenState();
}

class _SuperOverScreenState extends State<SuperOverScreen> {
  Store get store => widget.store;
  Match get match => widget.match;

  /// Index (into match.superOverInnings) of the innings on screen —
  /// always the latest one; starting a chase / a new round appends
  /// the next innings and moves to it.
  int _current = 0;

  @override
  void initState() {
    super.initState();
    if (match.superOverInnings.isEmpty) {
      startSuperOverInnings(match, 1);
    }
    _current = match.superOverInnings.length - 1;
  }

  InningsState get inn => match.superOverInnings[_current];
  int get roundNo => _current ~/ 2 + 1;
  bool get isFirstOfRound => _current % 2 == 0;

  String nameOf(String id) => store.playerName(id);

  /// Mirror of ScoringScreen._afterChange: recompute the match
  /// result (so a decided super over rewrites resultText) and persist.
  Future<void> _afterChange() async {
    computeResult(match, store.teamName);
    await store.persist();
    if (mounted) setState(() {});
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<String?> _pickPlayer(String title, List<String> ids) {
    return showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: ids.length,
            itemBuilder: (c, i) => ListTile(
              title: Text(nameOf(ids[i])),
              onTap: () => Navigator.pop(c, ids[i]),
            ),
          ),
        ),
      ),
    );
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
          title: const Text('Openers & bowler'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _playerDropdown(
                  'Striker', battingXI, striker, (v) => setD(() => striker = v)),
              _playerDropdown('Non-striker', battingXI, nonStriker,
                  (v) => setD(() => nonStriker = v)),
              _playerDropdown(
                  'Bowler', bowlingXI, bowler, (v) => setD(() => bowler = v)),
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

  Future<void> _chooseNextBatter() async {
    final atCrease = {inn.strikerId, inn.nonStrikerId}..remove('');
    final out =
        inn.batting.entries.where((e) => e.value.out).map((e) => e.key).toSet();
    final available = inn.battingXI
        .where((id) => !atCrease.contains(id) && !out.contains(id))
        .toList();
    final picked = await _pickPlayer('Next batter', available);
    if (picked != null) {
      setNextBatter(inn, picked);
      await _afterChange();
    }
  }

  Future<void> _chooseBowler() async {
    final available =
        inn.bowlingXI.where((id) => id != inn.lastBowlerId).toList();
    final picked = await _pickPlayer('Bowler', available);
    if (picked != null) {
      if (!setBowler(inn, picked)) {
        _snack('That bowler bowled the previous over');
        return;
      }
      await _afterChange();
    }
  }

  Future<void> _record(BallInput input) async {
    if (!applyBall(inn, input)) {
      _snack('Ball could not be recorded');
      return;
    }
    await _afterChange();
  }

  /// Wicket dialog-lite: pick the dismissal type, then a fielder
  /// where the type needs one (caught / stumped / run out) and the
  /// out end for a run out.
  Future<void> _wicket() async {
    const types = <String, String>{
      'Bowled': 'bowled',
      'Caught': 'caught',
      'LBW': 'lbw',
      'Run Out': 'runOut',
      'Stumped': 'stumped',
      'Hit Wicket': 'hitWicket',
    };
    final label = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Wicket — how?'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: types.length,
            itemBuilder: (c, i) => ListTile(
              title: Text(types.keys.elementAt(i)),
              onTap: () => Navigator.pop(c, types.keys.elementAt(i)),
            ),
          ),
        ),
      ),
    );
    if (label == null) return;
    final type = types[label]!;
    var fielderId = '';
    if (type == 'caught' || type == 'stumped' || type == 'runOut') {
      final f = await _pickPlayer('Fielder', inn.bowlingXI);
      if (f == null) return;
      fielderId = f;
    }
    var outPlayerId = '';
    var batRuns = 0;
    if (type == 'runOut') {
      final ends = [inn.strikerId, inn.nonStrikerId]
          .where((id) => id.isNotEmpty)
          .toList();
      final out = await _pickPlayer('Who is out?', ends);
      if (out == null) return;
      outPlayerId = out;
      // Runs completed on the run out (0-3, simple stepper dialog).
      final runs = await _runsDialog('Runs completed', 0);
      if (runs == null) return;
      batRuns = runs;
    }
    await _record(BallInput(
      batRuns: batRuns,
      isWicket: true,
      wicketType: type,
      fielderId: fielderId,
      outPlayerId: outPlayerId,
    ));
  }

  Future<int?> _runsDialog(String title, int initial) {
    var runs = initial;
    return showDialog<int>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: Text(title),
          content: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: () => setD(() => runs = runs > 0 ? runs - 1 : 0),
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text('$runs',
                  style: const TextStyle(
                      fontSize: 26, fontWeight: FontWeight.bold)),
              IconButton(
                onPressed: () => setD(() => runs++),
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, runs),
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _wide() async {
    final extra = await _runsDialog('Wide — extra runs beyond penalty', 0);
    if (extra == null) return;
    await _record(BallInput(extraType: 'wide', extraRuns: extra));
  }

  Future<void> _noBall() async {
    final runs = await _runsDialog('No ball — runs off the bat', 0);
    if (runs == null) return;
    await _record(BallInput(extraType: 'noBall', batRuns: runs));
  }

  Future<void> _startNextInnings() async {
    final next = startSuperOverInnings(match, match.superOverInnings.length + 1);
    _current = match.superOverInnings.indexOf(next);
    await _afterChange();
  }

  @override
  Widget build(BuildContext context) {
    final inn = this.inn;
    final battingName = store.teamName(inn.battingTeamId);
    final needsOpeners =
        inn.events.isEmpty && inn.strikerId == '' && !inn.isComplete;
    final target = inn.target;
    final needRuns = target > 0 ? target - inn.totalRuns : 0;
    final ballsLeft = inn.oversLimit * inn.ballsPerOver - inn.legalBalls;

    return Scaffold(
      appBar: AppBar(
        title: Text('Super Over — Round $roundNo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: 'Undo last ball',
            onPressed: inn.events.isEmpty && inn.undoStack.isEmpty
                ? null
                : () async {
                    if (undoLastBall(inn)) await _afterChange();
                  },
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
                    'Super Over • Round $roundNo • '
                    'Innings ${isFirstOfRound ? 1 : 2} of the round',
                    style: const TextStyle(
                        fontSize: 13, color: Colors.white60),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$battingName batting',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${inn.totalRuns}/${inn.wickets}  '
                    '(${oversText(inn.legalBalls, inn.ballsPerOver)} ov)',
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
                    Text(
                      '${nameOf(inn.strikerId)} *  '
                      '${inn.batting[inn.strikerId]?.runs ?? 0} '
                      '(${inn.batting[inn.strikerId]?.balls ?? 0})',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  if (inn.nonStrikerId.isNotEmpty)
                    Text(
                      '${nameOf(inn.nonStrikerId)}  '
                      '${inn.batting[inn.nonStrikerId]?.runs ?? 0} '
                      '(${inn.batting[inn.nonStrikerId]?.balls ?? 0})',
                    ),
                  if (inn.currentBowlerId.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Bowling: ${nameOf(inn.currentBowlerId)}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                  const SizedBox(height: 6),
                  _thisOverRow(inn),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (needsOpeners)
            FilledButton.icon(
              onPressed: _chooseOpeners,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Select openers & bowler'),
            )
          else if (inn.awaitingBatter && !inn.isComplete)
            FilledButton.icon(
              onPressed: _chooseNextBatter,
              icon: const Icon(Icons.person_add),
              label: const Text('Select next batter'),
            )
          else if (inn.awaitingBowler && !inn.isComplete)
            FilledButton.icon(
              onPressed: _chooseBowler,
              icon: const Icon(Icons.sports_baseball),
              label: const Text('Select bowler'),
            )
          else if (inn.isComplete)
            _completionCard()
          else
            _scoringPad(),
          if (match.superOverInnings.length > 1) ...[
            const SizedBox(height: 12),
            _roundsSummary(),
          ],
        ],
      ),
    );
  }

  Widget _thisOverRow(InningsState inn) {
    if (inn.events.isEmpty) return const SizedBox.shrink();
    // Wrap, not Row (owner UI rule 2026-10-24): a wide-heavy over
    // has more chips than a 360dp screen fits on one line — the
    // chips must flow to the next line instead of overflowing.
    return Wrap(
      spacing: 0,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text('This over: ', style: TextStyle(color: Colors.white60)),
        ...inn.events.map(
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

  Widget _completionCard() {
    final winner = superOverWinnerId(match);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Text(
              isFirstOfRound ? 'Innings complete' : 'Round $roundNo complete',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (isFirstOfRound)
              FilledButton.icon(
                onPressed: _startNextInnings,
                icon: const Icon(Icons.play_arrow),
                label: Text(
                    'Start chase — target ${inn.totalRuns + 1}'),
              )
            else if (winner != null) ...[
              Text(
                '${store.teamName(winner)} won the Super Over',
                style: const TextStyle(
                    color: kCyan, fontSize: 15, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ] else ...[
              const Text(
                'Super Over tied',
                style: TextStyle(
                    color: kGold, fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (superOverNeedsAnotherRound(match))
                FilledButton.icon(
                  onPressed: _startNextInnings,
                  icon: const Icon(Icons.replay),
                  label: const Text('Play another Super Over'),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _roundsSummary() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Super overs so far',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            for (var i = 0; i < match.superOverInnings.length; i++)
              Text(
                'Round ${i ~/ 2 + 1} • ${store.teamName(match.superOverInnings[i].battingTeamId)}: '
                '${match.superOverInnings[i].totalRuns}/${match.superOverInnings[i].wickets} '
                '(${oversText(match.superOverInnings[i].legalBalls, match.superOverInnings[i].ballsPerOver)} ov)',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
          ],
        ),
      ),
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
        Row(children: [runBtn('0', 0), runBtn('1', 1), runBtn('2', 2), runBtn('3', 3)]),
        Row(
          children: [
            runBtn('4', 4),
            runBtn('6', 6),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: kOrangeRed,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _wicket,
                  child: const Text('Wicket', style: TextStyle(fontSize: 16)),
                ),
              ),
            ),
          ],
        ),
        Row(children: [extraBtn('Wide', _wide), extraBtn('No Ball', _noBall)]),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          onPressed: inn.events.isEmpty && inn.undoStack.isEmpty
              ? null
              : () async {
                  if (undoLastBall(inn)) await _afterChange();
                },
          icon: const Icon(Icons.undo),
          label: const Text('Undo last ball'),
        ),
      ],
    );
  }
}
