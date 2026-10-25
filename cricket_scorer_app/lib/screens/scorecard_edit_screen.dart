// Post-match scorecard editor (v1.3.4).
//
// A completed match stays correctable: batting figures (name, runs,
// balls, 4s, 6s, out + dismissal text), bowling figures and extras
// can all be edited AFTER the match was saved and even after it was
// shared. Edits are written into the stored match record — the
// innings totals are recomputed from the figures (unless the team
// total itself was typed directly, which overrides the computed
// total), the result text is recomputed, and because the points
// table, NRR and the career
// statistics are all derived from the stored figures at read time,
// one correction (say, an added six) shows up in the player's
// score, the team total and his stats everywhere on its own.
//
// The editor works on a deep copy of the match; nothing touches
// the stored record until Save. The Playing XI itself is editable
// too (v1.3.5): a player can be added to a team's XI for the match
// (he appears as did-not-bat) or removed from it (his batting and
// bowling figures in the match go with him). Edited figures are
// the source of truth: on save, the totals, the result, the points
// table and every statistic — including the delivery-derived ones
// (fastest milestones, partnerships, catches), which fall back to
// the figures when deliveries are missing — recompute from the
// corrected record. The recorded ball-by-ball sequence itself is
// the one thing an edit does not rewrite (worm / manhattan charts
// plot the deliveries as they were bowled).
import 'package:flutter/material.dart';

import '../models.dart';
import '../scoring.dart';
import '../store.dart';
import '../theme.dart';
import '../tournament_engine.dart';

class _BatEdit {
  final TextEditingController runs = TextEditingController();
  final TextEditingController balls = TextEditingController();
  final TextEditingController fours = TextEditingController();
  final TextEditingController sixes = TextEditingController();
  final TextEditingController howOut = TextEditingController();
  bool out = false;

  /// The dismissal text as stored (id tokens) and as displayed
  /// (names) when the editor loaded it: if the user leaves the
  /// field untouched, the stored token form is kept verbatim so
  /// name resolution keeps working exactly as before.
  String originalRaw = '';
  String originalDisplay = '';

  void dispose() {
    runs.dispose();
    balls.dispose();
    fours.dispose();
    sixes.dispose();
    howOut.dispose();
  }
}

class _BowlEdit {
  final TextEditingController overs = TextEditingController();
  final TextEditingController maidens = TextEditingController();
  final TextEditingController runs = TextEditingController();
  final TextEditingController wickets = TextEditingController();
  final TextEditingController wides = TextEditingController();
  final TextEditingController noBalls = TextEditingController();

  void dispose() {
    overs.dispose();
    maidens.dispose();
    runs.dispose();
    wickets.dispose();
    wides.dispose();
    noBalls.dispose();
  }
}

class _ExtrasEdit {
  final TextEditingController wides = TextEditingController();
  final TextEditingController noBalls = TextEditingController();
  final TextEditingController byes = TextEditingController();
  final TextEditingController legByes = TextEditingController();

  void dispose() {
    wides.dispose();
    noBalls.dispose();
    byes.dispose();
    legByes.dispose();
  }
}

class _InnEdit {
  final Map<String, _BatEdit> bat = {};
  final Map<String, _BowlEdit> bowl = {};
  final _ExtrasEdit extras = _ExtrasEdit();

  /// Directly edited team total (null until validated on save):
  /// when set, it overrides the total recomputed from the figures.
  final TextEditingController total = TextEditingController();
  int? totalOverride;

  void dispose() {
    for (final e in bat.values) {
      e.dispose();
    }
    for (final e in bowl.values) {
      e.dispose();
    }
    extras.dispose();
    total.dispose();
  }
}

class ScorecardEditScreen extends StatefulWidget {
  final Store store;
  final Match match;
  const ScorecardEditScreen({
    super.key,
    required this.store,
    required this.match,
  });

  @override
  State<ScorecardEditScreen> createState() => _ScorecardEditScreenState();
}

class _ScorecardEditScreenState extends State<ScorecardEditScreen> {
  Store get store => widget.store;

  /// Deep copy of the match — the stored record is only written on
  /// Save, so Cancel can never leave a half-edit behind.
  late final Match _edit;
  final List<_InnEdit> _inns = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _edit = Match.fromJson(widget.match.toJson());
    for (var i = 0; i < _edit.innings.length; i++) {
      final ie = _InnEdit();
      _inns.add(ie);
      _fillControllers(i, ie);
    }
  }

  @override
  void dispose() {
    for (final ie in _inns) {
      ie.dispose();
    }
    super.dispose();
  }

  String nameOf(String id) => store.playerName(id);

  void _fillControllers(int idx, _InnEdit ie) {
    final inn = _edit.innings[idx];
    ie.bat.clear();
    ie.bowl.clear();
    inn.batting.forEach((pid, f) {
      if (!f.batted) return;
      final display = f.out ? _displayHowOut(f.howOut) : '';
      final e = _BatEdit()
        ..runs.text = '${f.runs}'
        ..balls.text = '${f.balls}'
        ..fours.text = '${f.fours}'
        ..sixes.text = '${f.sixes}'
        ..howOut.text = display
        ..out = f.out
        ..originalRaw = f.howOut
        ..originalDisplay = display;
      ie.bat[pid] = e;
    });
    inn.bowling.forEach((pid, f) {
      final e = _BowlEdit()
        ..overs.text = oversText(f.legalBalls, inn.ballsPerOver)
        ..maidens.text = '${f.maidens}'
        ..runs.text = '${f.runs}'
        ..wickets.text = '${f.wickets}'
        ..wides.text = '${f.wides}'
        ..noBalls.text = '${f.noBalls}';
      ie.bowl[pid] = e;
    });
    ie.extras.wides.text = '${inn.widesRuns}';
    ie.extras.noBalls.text = '${inn.noBallRuns}';
    ie.extras.byes.text = '${inn.byeRuns}';
    ie.extras.legByes.text = '${inn.legByeRuns}';
    ie.total.text = '${inn.totalRuns}';
    ie.totalOverride = null;
  }

  /// Dismissal text shown for editing: resolve the stored id tokens
  /// to names so the user edits readable text. On save the text is
  /// stored verbatim (see _save).
  String _displayHowOut(String howOut) => resolveHowOut(howOut, nameOf);

  void _rebuildInnings(int idx) {
    _inns[idx].dispose();
    final ie = _InnEdit();
    _inns[idx] = ie;
    _fillControllers(idx, ie);
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<String?> _pickPlayer(
    String title,
    List<String> ids,
    String currentId,
  ) {
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
              trailing: ids[i] == currentId
                  ? const Icon(Icons.check, color: kGold)
                  : null,
              onTap: () => Navigator.pop(c, ids[i]),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _changeBatter(int idx, String fromId) async {
    final inn = _edit.innings[idx];
    final picked = await _pickPlayer(
      'Batting figure belongs to',
      inn.battingXI,
      fromId,
    );
    if (picked == null || picked == fromId) return;
    if (remapBattingFigure(inn, fromId, picked)) {
      _rebuildInnings(idx);
      if (mounted) setState(() {});
    }
  }

  Future<void> _changeBowler(int idx, String fromId) async {
    final inn = _edit.innings[idx];
    final picked = await _pickPlayer(
      'Bowling figure belongs to',
      inn.bowlingXI,
      fromId,
    );
    if (picked == null || picked == fromId) return;
    if (remapBowlingFigure(inn, fromId, picked)) {
      _rebuildInnings(idx);
      if (mounted) setState(() {});
    }
  }

  /// Playing XI editing (v1.3.5): add a squad player to the match
  /// XI of [teamId]. He joins as did-not-bat; his figures can then
  /// be corrected like anyone else's once he has a batted row — and
  /// every innings card is rebuilt so both show the new XI.
  Future<void> _addToXi(String teamId) async {
    final team = store.teamById(teamId);
    if (team == null) return;
    final current = _edit.xiFor(teamId);
    final candidates = team.players
        .map((p) => p.id)
        .where((id) => !current.contains(id))
        .toList();
    if (candidates.isEmpty) {
      _snack('Every squad player is already in the Playing XI.');
      return;
    }
    final picked = await _pickPlayer(
      'Add to Playing XI — ${team.name}',
      candidates,
      '',
    );
    if (picked == null) return;
    if (!addToMatchXI(_edit, teamId, picked)) {
      _snack('Playing XI is full (11 players). Remove a player first.');
      return;
    }
    for (var i = 0; i < _edit.innings.length; i++) {
      _rebuildInnings(i);
    }
    if (mounted) setState(() {});
  }

  /// Remove a player from the match XI of [teamId] — his batting
  /// and bowling figures in this match are removed with him, and
  /// totals/result/stats recompute on save.
  Future<void> _removeFromXi(String teamId, String playerId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Remove from Playing XI?'),
        content: Text(
          'Remove ${nameOf(playerId)} from the Playing XI? His '
          'batting and bowling figures in this match will be '
          'removed too.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    removeFromMatchXI(_edit, teamId, playerId);
    for (var i = 0; i < _edit.innings.length; i++) {
      _rebuildInnings(i);
    }
    if (mounted) setState(() {});
  }

  int? _intOf(TextEditingController c) {
    final v = int.tryParse(c.text.trim());
    return (v == null || v < 0) ? null : v;
  }

  /// Overs text ('3.2') -> legal balls, honouring ballsPerOver.
  int? _ballsOf(TextEditingController c, int ballsPerOver) {
    final t = c.text.trim();
    if (t.isEmpty) return null;
    final parts = t.split('.');
    if (parts.length > 2) return null;
    final overs = int.tryParse(parts[0]);
    if (overs == null || overs < 0) return null;
    var balls = 0;
    if (parts.length == 2) {
      final b = int.tryParse(parts[1]);
      if (b == null || b < 0 || b >= ballsPerOver) return null;
      balls = b;
    }
    return overs * ballsPerOver + balls;
  }

  /// Validate + write the controllers of innings [idx] into the
  /// copy's figures. Returns an error message, or null on success.
  String? _applyInnings(int idx) {
    final inn = _edit.innings[idx];
    final ie = _inns[idx];
    var outs = 0;
    for (final entry in ie.bat.entries) {
      final fig = inn.batting[entry.key];
      if (fig == null) continue;
      final e = entry.value;
      final runs = _intOf(e.runs);
      final balls = _intOf(e.balls);
      final fours = _intOf(e.fours);
      final sixes = _intOf(e.sixes);
      if (runs == null || balls == null || fours == null || sixes == null) {
        return '${nameOf(entry.key)}: runs, balls, 4s and 6s must be '
            'numbers (0 or more).';
      }
      if (fours * 4 + sixes * 6 > runs) {
        return '${nameOf(entry.key)}: runs from 4s and 6s exceed the '
            'total runs.';
      }
      fig.runs = runs;
      fig.balls = balls;
      fig.fours = fours;
      fig.sixes = sixes;
      // Full dismissal set cascade: plain dismissal texts typed
      // here ('retired out', 'timed out', 'obstructing the field',
      // 'hit the ball twice', 'mankad' / 'Mankad (Name)') are stored
      // verbatim — fielderCreditFromHowOut gives them no fielder
      // credit (except a mankad id token, credited as a run out),
      // and dismissal counting follows fig.out alone. 'retired
      // hurt' is NOT a dismissal: it never counts as out, and a
      // retired-hurt marker survives figure edits untouched.
      final typedHow = e.howOut.text.trim();
      var isOut = e.out;
      String how;
      if (isOut && typedHow.toLowerCase() == 'retired hurt') {
        isOut = false;
        how = 'retired hurt';
      } else if (!isOut) {
        how = e.originalRaw == 'retired hurt' ? 'retired hurt' : '';
      } else if (typedHow == e.originalDisplay) {
        how = e.originalRaw; // untouched: keep the token form
      } else {
        how = typedHow; // edited: stored verbatim
      }
      fig.out = isOut;
      fig.howOut = how;
      if (isOut) outs++;
    }
    if (outs > inn.effectiveMaxWickets) {
      return '${store.teamName(inn.battingTeamId)}: $outs batters out, '
          'but only ${inn.effectiveMaxWickets} wickets can fall.';
    }
    var bowlerWickets = 0;
    for (final entry in ie.bowl.entries) {
      final fig = inn.bowling[entry.key];
      if (fig == null) continue;
      final e = entry.value;
      final legal = _ballsOf(e.overs, inn.ballsPerOver);
      final maidens = _intOf(e.maidens);
      final runs = _intOf(e.runs);
      final wickets = _intOf(e.wickets);
      final wides = _intOf(e.wides);
      final noBalls = _intOf(e.noBalls);
      if (legal == null ||
          maidens == null ||
          runs == null ||
          wickets == null ||
          wides == null ||
          noBalls == null) {
        return '${nameOf(entry.key)}: bowling figures are invalid '
            '(overs like 3.2, other fields numbers 0 or more).';
      }
      fig.legalBalls = legal;
      fig.maidens = maidens;
      fig.runs = runs;
      fig.wickets = wickets;
      fig.wides = wides;
      fig.noBalls = noBalls;
      bowlerWickets += wickets;
    }
    if (bowlerWickets > outs) {
      return 'Bowler wickets ($bowlerWickets) exceed the dismissals '
          '($outs) — run outs make up the rest.';
    }
    final wides = _intOf(ie.extras.wides);
    final noBalls = _intOf(ie.extras.noBalls);
    final byes = _intOf(ie.extras.byes);
    final legByes = _intOf(ie.extras.legByes);
    if (wides == null || noBalls == null || byes == null || legByes == null) {
      return 'Extras must be numbers (0 or more).';
    }
    inn.widesRuns = wides;
    inn.noBallRuns = noBalls;
    inn.byeRuns = byes;
    inn.legByeRuns = legByes;
    // Directly edited team total: validated here, applied on save
    // AFTER the totals are recomputed from the figures, so the typed
    // total wins over the computed one.
    final total = _intOf(ie.total);
    if (total == null) {
      return '${store.teamName(inn.battingTeamId)}: team total must be '
          'a number (0 or more).';
    }
    ie.totalOverride = total;
    return null;
  }

  Future<void> _save() async {
    if (_saving) return;
    for (var i = 0; i < _edit.innings.length; i++) {
      final err = _applyInnings(i);
      if (err != null) {
        _snack(err);
        return;
      }
    }
    setState(() => _saving = true);
    // Recompute every derived number from the corrected figures,
    // then apply any directly edited team total over the computed
    // one (the typed total is the correction, not the figures).
    for (var i = 0; i < _edit.innings.length; i++) {
      final inn = _edit.innings[i];
      recomputeInningsTotals(inn);
      final override = _inns[i].totalOverride;
      if (override != null) inn.totalRuns = override;
      // The undo history describes the pre-edit balls; it must not
      // resurrect them over the corrected record.
      inn.undoStack = [];
    }
    if (_edit.innings.length > 1) {
      _edit.innings[1].target = _edit.innings[0].totalRuns + 1;
    }
    widget.match.innings = _edit.innings;
    widget.match.xiA = List.of(_edit.xiA);
    widget.match.xiB = List.of(_edit.xiB);
    final text = computeResult(widget.match, store.teamName);
    if (text.isNotEmpty) widget.match.resultText = text;
    await store.persist();
    // Corrected totals can move the points table / playoff seeds.
    final tid = widget.match.tournamentId;
    if (tid != null && mounted) {
      final update = await applyPlayoffUpdate(store, tid);
      if (update.needsConfirmation && mounted) {
        final apply = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Playoff reseeding needed'),
            content: Text(update.message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Keep current'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Apply'),
              ),
            ],
          ),
        );
        if (apply == true) {
          await applyPlayoffUpdate(store, tid, force: true);
        }
      }
    }
    if (!mounted) return;
    _snack('Scorecard updated — totals, result and stats refreshed');
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit scorecard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: 'Save corrections',
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Text(
            'Correct any figure — or type the team total directly '
            'to override it. The result, the points table and the '
            'player stats all update from the corrected record when '
            'you save.',
            style: TextStyle(color: Colors.white60, fontSize: 13),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < _edit.innings.length; i++) ...[
            _inningsCard(i),
            const SizedBox(height: 12),
          ],
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save),
            label: const Text('Save corrections'),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _inningsCard(int idx) {
    final inn = _edit.innings[idx];
    final ie = _inns[idx];
    final battedIds = inn.battingXI
        .where((pid) => ie.bat.containsKey(pid))
        .toList()
      ..addAll(ie.bat.keys.where((pid) => !inn.battingXI.contains(pid)));
    final dnb = inn.battingXI
        .where((pid) => !(inn.batting[pid]?.batted ?? false))
        .map(nameOf)
        .toList();
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
                    store.teamName(inn.battingTeamId),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '${inn.totalRuns}/${inn.wickets} '
                  '(${oversText(inn.legalBalls, inn.ballsPerOver)} ov)',
                  style: const TextStyle(
                    color: kGold,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Text(
                  'Team total',
                  style: TextStyle(fontSize: 13, color: Colors.white70),
                ),
                const SizedBox(width: 10),
                _numField('Total', ie.total),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Edit directly to override the total computed '
                    'from the figures above.',
                    style: TextStyle(fontSize: 11, color: Colors.white38),
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            const Text(
              'Batting',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: kCopper,
              ),
            ),
            for (final pid in battedIds) _batRow(idx, pid),
            if (dnb.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Did not bat: ${dnb.join(', ')}',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                ),
              ),
            const Divider(height: 20),
            const Text(
              'Bowling',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: kCopper,
              ),
            ),
            for (final pid in ie.bowl.keys) _bowlRow(idx, pid),
            const Divider(height: 20),
            const Text(
              'Extras (runs)',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: kCopper,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                _numField('Wides', ie.extras.wides),
                _numField('No balls', ie.extras.noBalls),
                _numField('Byes', ie.extras.byes),
                _numField('Leg byes', ie.extras.legByes),
              ],
            ),
            const Divider(height: 20),
            const Text(
              'Playing XI',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: kCopper,
              ),
            ),
            _xiSection(inn.battingTeamId),
            _xiSection(inn.bowlingTeamId),
          ],
        ),
      ),
    );
  }

  /// One team's XI inside an innings card: every player with a
  /// remove button, plus an add button fed from the team squad.
  Widget _xiSection(String teamId) {
    final xi = _edit.xiFor(teamId);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${store.teamName(teamId)} (${xi.length})',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          for (final pid in xi)
            Row(
              children: [
                Expanded(
                  child: Text(
                    nameOf(pid),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline, size: 20),
                  tooltip: 'Remove from Playing XI',
                  onPressed: () => _removeFromXi(teamId, pid),
                ),
              ],
            ),
          TextButton.icon(
            onPressed: () => _addToXi(teamId),
            icon: const Icon(Icons.person_add, size: 18),
            label: const Text('Add player'),
          ),
        ],
      ),
    );
  }

  Widget _nameRow(String pid, VoidCallback onChange) {
    return Row(
      children: [
        Expanded(
          child: Text(
            nameOf(pid),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ),
        TextButton.icon(
          onPressed: onChange,
          icon: const Icon(Icons.swap_horiz, size: 16),
          label: const Text('Change name'),
        ),
      ],
    );
  }

  Widget _batRow(int idx, String pid) {
    final e = _inns[idx].bat[pid]!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _nameRow(pid, () => _changeBatter(idx, pid)),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _numField('Runs', e.runs),
              _numField('Balls', e.balls),
              _numField('4s', e.fours),
              _numField('6s', e.sixes),
            ],
          ),
          Row(
            children: [
              const Text('Out', style: TextStyle(fontSize: 13)),
              Switch(
                value: e.out,
                onChanged: (v) => setState(() => e.out = v),
              ),
              if (e.out)
                Expanded(
                  child: TextField(
                    controller: e.howOut,
                    decoration: const InputDecoration(
                      labelText: 'How out (e.g. c Ahmed b Bilal)',
                      isDense: true,
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bowlRow(int idx, String pid) {
    final e = _inns[idx].bowl[pid]!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _nameRow(pid, () => _changeBowler(idx, pid)),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _numField('Overs', e.overs),
              _numField('Maidens', e.maidens),
              _numField('Runs', e.runs),
              _numField('Wkts', e.wickets),
              _numField('Wides', e.wides),
              _numField('No balls', e.noBalls),
            ],
          ),
        ],
      ),
    );
  }

  Widget _numField(String label, TextEditingController c) {
    return SizedBox(
      width: 64,
      child: TextField(
        controller: c,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        decoration: InputDecoration(labelText: label, isDense: true),
        style: const TextStyle(fontSize: 14),
      ),
    );
  }
}
