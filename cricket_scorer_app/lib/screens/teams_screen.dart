import 'package:flutter/material.dart';

import '../models.dart';
import '../player_io.dart';
import '../store.dart';
import '../theme.dart';

class TeamsScreen extends StatefulWidget {
  final Store store;
  const TeamsScreen({super.key, required this.store});

  @override
  State<TeamsScreen> createState() => _TeamsScreenState();
}

class _TeamsScreenState extends State<TeamsScreen> {
  Store get store => widget.store;

  @override
  void initState() {
    super.initState();
    store.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    store.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Teams')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _editTeam(context, null),
        child: const Icon(Icons.add),
      ),
      body: ListView.builder(
        itemCount: store.teams.length,
        itemBuilder: (context, i) {
          final t = store.teams[i];
          final stats = store.teams.length;
          // ignore: unused_local_variable
          // (team W/L shown in Stats tab)
          final _ = stats;
          return ListTile(
            leading: CircleAvatar(
              child: Text(t.name.isEmpty ? '?' : t.name[0]),
            ),
            title: Text(t.name),
            subtitle: Text('${t.players.length} players'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => TeamDetailScreen(store: store, team: t),
              ),
            ).then((_) => store.persist()),
          );
        },
      ),
    );
  }

  Future<void> _editTeam(BuildContext context, Team? existing) async {
    final ctrl = TextEditingController(text: existing?.name ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(existing == null ? 'New team' : 'Edit team'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Team name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      if (existing == null) {
        await store.upsertTeam(Team(id: Store.newId('team'), name: name));
      } else {
        existing.name = name;
        await store.persist();
      }
    }
  }
}

class TeamDetailScreen extends StatefulWidget {
  final Store store;
  final Team team;
  const TeamDetailScreen({super.key, required this.store, required this.team});

  @override
  State<TeamDetailScreen> createState() => _TeamDetailScreenState();
}

class _TeamDetailScreenState extends State<TeamDetailScreen> {
  Team get team => widget.team;
  Store get store => widget.store;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(team.name),
        actions: [
          PlayerListIoButtons(
            exportName: '60score_squad_${team.id}',
            exportRows: () =>
                team.players.map((p) => rowFromPlayer(p, team.name)).toList(),
            onImport: (rows) async {
              for (final r in rows) {
                // Reuse a registered player with the same name when one
                // exists, so ids (and career stats) stay unified.
                final reg = store.regPlayers
                    .where(
                      (x) => x.name.toLowerCase() == r.playerName.toLowerCase(),
                    )
                    .firstOrNull;
                if (reg != null) {
                  if (team.playerById(reg.id) == null) {
                    team.players.add(reg.toTeamPlayer());
                  }
                } else if (!team.players.any(
                  (x) => x.name.toLowerCase() == r.playerName.toLowerCase(),
                )) {
                  team.players.add(r.toTeamPlayer(Store.newId('player')));
                }
              }
              await store.persist();
              setState(() {});
            },
          ),
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () async {
              final ctrl = TextEditingController(text: team.name);
              final name = await showDialog<String>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Rename team'),
                  content: TextField(controller: ctrl),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(c, ctrl.text.trim()),
                      child: const Text('Save'),
                    ),
                  ],
                ),
              );
              if (name != null && name.isNotEmpty) {
                setState(() => team.name = name);
                await store.persist();
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: Text('Delete ${team.name}?'),
                  content: const Text('This removes the team and its squad.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );
              if (ok == true && context.mounted) {
                await store.deleteTeam(team.id);
                if (context.mounted) Navigator.pop(context);
              }
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editPlayer(context, null),
        icon: const Icon(Icons.person_add),
        label: const Text('Add player'),
      ),
      body: team.players.isEmpty
          ? const Center(child: Text('No players yet. Add the squad.'))
          : ListView.builder(
              itemCount: team.players.length,
              itemBuilder: (context, i) {
                final p = team.players[i];
                final tags = [
                  if (p.isCaptain) 'C',
                  if (p.isViceCaptain) 'VC',
                  if (p.isKeeper) 'WK',
                ].join(' · ');
                return ListTile(
                  leading: CircleAvatar(
                    child: Text(p.jerseyNo > 0 ? '${p.jerseyNo}' : '?'),
                  ),
                  title: Text(p.name),
                  subtitle: Text(
                    '${p.role} · ${p.battingStyle} bat · ${p.bowlingStyle}${tags.isEmpty ? '' : ' · $tags'}',
                  ),
                  onTap: () => _editPlayer(context, p),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      setState(() => team.players.removeAt(i));
                      await store.persist();
                    },
                  ),
                );
              },
            ),
    );
  }

  Future<void> _editPlayer(BuildContext context, Player? existing) async {
    final p =
        existing ?? Player(id: Store.newId('player'), name: '', jerseyNo: 0);
    final nameCtrl = TextEditingController(text: p.name);
    final jerseyCtrl = TextEditingController(
      text: p.jerseyNo > 0 ? '${p.jerseyNo}' : '',
    );
    var role = p.role;
    var bat = p.battingStyle;
    var bowl = p.bowlingStyle;
    var cap = p.isCaptain;
    var vc = p.isViceCaptain;
    var wk = p.isKeeper;
    const roles = ['Batter', 'Bowler', 'All-Rounder', 'Wicket-Keeper'];
    const bats = ['Right-hand', 'Left-hand'];
    const bowls = [
      'None',
      'Right-arm fast',
      'Right-arm medium',
      'Right-arm spin',
      'Left-arm fast',
      'Left-arm medium',
      'Left-arm spin',
    ];
    final saved = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: Text(existing == null ? 'Add player' : 'Edit player'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                TextField(
                  controller: jerseyCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Jersey no.'),
                ),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: roles
                      .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                      .toList(),
                  onChanged: (v) => setD(() => role = v ?? role),
                ),
                DropdownButtonFormField<String>(
                  initialValue: bat,
                  decoration: const InputDecoration(labelText: 'Batting style'),
                  items: bats
                      .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                      .toList(),
                  onChanged: (v) => setD(() => bat = v ?? bat),
                ),
                DropdownButtonFormField<String>(
                  initialValue: bowl,
                  decoration: const InputDecoration(labelText: 'Bowling style'),
                  items: bowls
                      .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                      .toList(),
                  onChanged: (v) => setD(() => bowl = v ?? bowl),
                ),
                CheckboxListTile(
                  value: cap,
                  title: const Text('Captain'),
                  onChanged: (v) => setD(() => cap = v ?? false),
                ),
                CheckboxListTile(
                  value: vc,
                  title: const Text('Vice-captain'),
                  onChanged: (v) => setD(() => vc = v ?? false),
                ),
                CheckboxListTile(
                  value: wk,
                  title: const Text('Wicket-keeper'),
                  onChanged: (v) => setD(() => wk = v ?? false),
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
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved == true && nameCtrl.text.trim().isNotEmpty) {
      p.name = nameCtrl.text.trim();
      p.jerseyNo = int.tryParse(jerseyCtrl.text) ?? 0;
      p.role = role;
      p.battingStyle = bat;
      p.bowlingStyle = bowl;
      // only one captain / vice-captain / keeper flag set per team
      if (cap) {
        for (final x in team.players) {
          x.isCaptain = false;
        }
      }
      if (vc) {
        for (final x in team.players) {
          x.isViceCaptain = false;
        }
      }
      p.isCaptain = cap;
      p.isViceCaptain = vc;
      p.isKeeper = wk;
      if (existing == null) team.players.add(p);
      setState(() {});
      await store.persist();
    }
  }
}
