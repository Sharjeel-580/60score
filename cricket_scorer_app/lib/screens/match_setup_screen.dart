import 'package:flutter/material.dart';
import '../models.dart';
import '../store.dart';
import 'scoring_screen.dart';

class MatchSetupScreen extends StatefulWidget {
  final Store store;
  final String? tournamentId;
  const MatchSetupScreen({super.key, required this.store, this.tournamentId});

  @override
  State<MatchSetupScreen> createState() => _MatchSetupScreenState();
}

class _MatchSetupScreenState extends State<MatchSetupScreen> {
  String? teamAId;
  String? teamBId;
  String? tournamentId;
  final Set<String> xiA = {};
  final Set<String> xiB = {};
  int overs = 10;
  int totalWickets = 0; // 0 = auto (XI - 1)
  bool lastManStands = false;
  bool widePenalty = true;
  bool noBallPenalty = true;
  int ballsPerOver = 6;
  final venueCtrl = TextEditingController();
  DateTime date = DateTime.now();
  String? tossWinnerId;
  String tossDecision = 'bat';

  Store get store => widget.store;

  @override
  void initState() {
    super.initState();
    tournamentId = widget.tournamentId;
    if (store.teams.length >= 2) {
      teamAId = store.teams[0].id;
      teamBId = store.teams[1].id;
      _preselect();
    }
    if (tournamentId != null) {
      final t = store.tournamentById(tournamentId);
      if (t != null && t.teamIds.length >= 2) {
        teamAId = t.teamIds[0];
        teamBId = t.teamIds[1];
        _preselect();
      }
    }
    tossWinnerId = teamAId;
  }

  void _preselect() {
    xiA.clear();
    xiB.clear();
    final a = store.teamById(teamAId ?? '');
    final b = store.teamById(teamBId ?? '');
    if (a != null) xiA.addAll(a.players.take(11).map((p) => p.id));
    if (b != null) xiB.addAll(b.players.take(11).map((p) => p.id));
  }

  Future<void> _quickAdd(String teamId, Set<String> xi) async {
    final team = store.teamById(teamId);
    if (team == null) return;
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Quick-add player to ${team.name}'),
        content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(labelText: 'Player name')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(c, ctrl.text.trim()),
              child: const Text('Add')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      final p = Player(id: Store.newId('player'), name: name);
      team.players.add(p);
      xi.add(p.id);
      await store.persist();
      setState(() {});
    }
  }

  Widget _xiPicker(String teamId, Set<String> xi) {
    final team = store.teamById(teamId);
    if (team == null) return const SizedBox();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
                child: Text(
                    '${team.name} — Playing XI (${xi.length}/11)${xi.length >= 11 ? ' — full' : ''}',
                    style: const TextStyle(fontWeight: FontWeight.bold))),
            TextButton(
              onPressed: () => _quickAdd(teamId, xi),
              child: const Text('Quick-add'),
            ),
          ],
        ),
        if (team.players.isEmpty)
          const Text('No squad players yet — use Quick-add.',
              style: TextStyle(color: Colors.orange)),
        ...team.players.map((p) => CheckboxListTile(
              dense: true,
              value: xi.contains(p.id),
              title: Text(p.name),
              subtitle: Text(p.role),
              onChanged: (v) {
                setState(() {
                  if (v == true) {
                    if (xi.length < 11) xi.add(p.id);
                  } else {
                    xi.remove(p.id);
                  }
                });
              },
            )),
      ],
    );
  }

  bool get _canStart =>
      teamAId != null &&
      teamBId != null &&
      teamAId != teamBId &&
      xiA.length >= 2 &&
      xiB.length >= 2 &&
      tossWinnerId != null;

  @override
  Widget build(BuildContext context) {
    final teams = store.teams;
    return Scaffold(
      appBar: AppBar(title: const Text('New match')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          DropdownButtonFormField<String>(
            initialValue: tournamentId,
            decoration: const InputDecoration(labelText: 'Tournament (optional)'),
            items: [
              const DropdownMenuItem<String>(value: null, child: Text('Friendly / none')),
              ...store.tournaments.map((t) =>
                  DropdownMenuItem(value: t.id, child: Text(t.name))),
            ],
            onChanged: (v) => setState(() => tournamentId = v),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: teamAId,
                  decoration: const InputDecoration(labelText: 'Team A'),
                  items: teams
                      .map((t) => DropdownMenuItem(value: t.id, child: Text(t.name)))
                      .toList(),
                  onChanged: (v) => setState(() {
                    teamAId = v;
                    if (teamBId == v) teamBId = null;
                    tossWinnerId = v;
                    _preselect();
                  }),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('vs'),
              ),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: teamBId,
                  decoration: const InputDecoration(labelText: 'Team B'),
                  items: teams
                      .map((t) => DropdownMenuItem(value: t.id, child: Text(t.name)))
                      .toList(),
                  onChanged: (v) => setState(() {
                    teamBId = v;
                    _preselect();
                  }),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: overs,
                  decoration: const InputDecoration(labelText: 'Overs'),
                  items: [5, 10, 15, 20, 25, 30, 40, 50]
                      .map((o) => DropdownMenuItem(value: o, child: Text('$o overs')))
                      .toList(),
                  onChanged: (v) => setState(() => overs = v ?? 10),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  initialValue: '$overs',
                  decoration: const InputDecoration(labelText: 'Custom overs'),
                  keyboardType: TextInputType.number,
                  onChanged: (v) {
                    final n = int.tryParse(v);
                    if (n != null && n > 0) setState(() => overs = n);
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: ballsPerOver,
                  decoration: const InputDecoration(labelText: 'Balls / over'),
                  items: [4, 5, 6, 8]
                      .map((o) => DropdownMenuItem(value: o, child: Text('$o balls')))
                      .toList(),
                  onChanged: (v) => setState(() => ballsPerOver = v ?? 6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
              controller: venueCtrl,
              decoration: const InputDecoration(labelText: 'Venue')),
          const SizedBox(height: 10),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Date'),
            subtitle: Text(date.toIso8601String().substring(0, 10)),
            trailing: const Icon(Icons.calendar_month),
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: date,
                firstDate: DateTime(2020),
                lastDate: DateTime(2035),
              );
              if (d != null) setState(() => date = d);
            },
          ),
          const Divider(),
          const Text('Match settings',
              style: TextStyle(fontWeight: FontWeight.bold)),
          DropdownButtonFormField<int>(
            initialValue: totalWickets,
            decoration:
                const InputDecoration(labelText: 'Total wickets'),
            items: const [
              DropdownMenuItem(value: 0, child: Text('Auto (players - 1)')),
              DropdownMenuItem(value: 10, child: Text('10 wickets')),
              DropdownMenuItem(value: 9, child: Text('9 wickets')),
              DropdownMenuItem(value: 8, child: Text('8 wickets')),
              DropdownMenuItem(value: 11, child: Text('11 wickets')),
            ],
            onChanged: (v) => setState(() => totalWickets = v ?? 0),
          ),
          SwitchListTile(
            value: lastManStands,
            title: const Text('Last man stands'),
            onChanged: (v) => setState(() => lastManStands = v),
          ),
          SwitchListTile(
            value: widePenalty,
            title: const Text('Wide ball penalty run'),
            onChanged: (v) => setState(() => widePenalty = v),
          ),
          SwitchListTile(
            value: noBallPenalty,
            title: const Text('No ball penalty run'),
            onChanged: (v) => setState(() => noBallPenalty = v),
          ),
          const Divider(),
          const Text('Toss', style: TextStyle(fontWeight: FontWeight.bold)),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: tossWinnerId,
                  decoration: const InputDecoration(labelText: 'Toss won by'),
                  items: [
                    if (teamAId != null)
                      DropdownMenuItem(
                          value: teamAId, child: Text(store.teamName(teamAId!))),
                    if (teamBId != null)
                      DropdownMenuItem(
                          value: teamBId, child: Text(store.teamName(teamBId!))),
                  ],
                  onChanged: (v) => setState(() => tossWinnerId = v),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: tossDecision,
                  decoration: const InputDecoration(labelText: 'Chose to'),
                  items: const [
                    DropdownMenuItem(value: 'bat', child: Text('Bat first')),
                    DropdownMenuItem(value: 'bowl', child: Text('Bowl first')),
                  ],
                  onChanged: (v) => setState(() => tossDecision = v ?? 'bat'),
                ),
              ),
            ],
          ),
          const Divider(),
          if (teamAId != null) _xiPicker(teamAId!, xiA),
          const Divider(),
          if (teamBId != null) _xiPicker(teamBId!, xiB),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _canStart ? _start : null,
            icon: const Icon(Icons.sports_cricket),
            label: const Text('Start match'),
          ),
          if (!_canStart)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                  'Pick two different teams and at least 2 players per XI to start.',
                  style: TextStyle(color: Colors.orange)),
            ),
        ],
      ),
    );
  }

  Future<void> _start() async {
    final m = Match(
      id: Store.newId('match'),
      tournamentId: tournamentId,
      teamAId: teamAId!,
      teamBId: teamBId!,
      xiA: xiA.toList(),
      xiB: xiB.toList(),
      oversLimit: overs,
      ballsPerOver: ballsPerOver,
      venue: venueCtrl.text.trim(),
      dateIso: date.toIso8601String().substring(0, 10),
      tossWinnerId: tossWinnerId!,
      tossDecision: tossDecision,
      status: 'live',
      totalWickets: totalWickets,
      lastManStands: lastManStands,
      widePenalty: widePenalty,
      noBallPenalty: noBallPenalty,
    );
    await store.upsertMatch(m);
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => ScoringScreen(store: store, match: m)),
    );
  }
}
