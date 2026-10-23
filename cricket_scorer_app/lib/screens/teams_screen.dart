import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models.dart';
import '../player_io.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/player_avatar.dart';

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
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit, size: 20),
                  tooltip: 'Edit team',
                  onPressed: () => _editTeam(context, t),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  tooltip: 'Delete team',
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: Text('Delete ${t.name}?'),
                        content: const Text(
                          'This removes the team and its squad.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(c, false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: kRed,
                            ),
                            onPressed: () => Navigator.pop(c, true),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) {
                      await store.deleteTeam(t.id);
                      if (mounted) setState(() {});
                    }
                  },
                ),
                const Icon(Icons.chevron_right, size: 20),
              ],
            ),
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
        // v1.1.7: choose between creating a new player and picking an
        // existing registered player.
        onPressed: () => _chooseAddPlayer(context),
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
                // v1.1.6: photo via the shared player record — a registered
                // player's saved photo shows here. Plain person icon when
                // no photo exists (never a question mark).
                final cardPhoto = store.photoForPlayer(p.id);
                return ListTile(
                  leading: PlayerAvatar(
                    photoBase64: cardPhoto.isEmpty ? null : cardPhoto,
                    role: p.role,
                    name: p.name,
                    radius: 22,
                    fallbackIcon: Icons.person,
                  ),
                  title: Text(p.name),
                  subtitle: Text(
                    '${p.role} · ${p.battingStyle} bat · ${p.bowlingStyle}${tags.isEmpty ? '' : ' · $tags'}',
                  ),
                  onTap: () => _editPlayer(context, p),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      // v1.3.7: standard confirm before removing a
                      // squad player (this was an instant delete —
                      // every other delete in the app confirms first).
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (d) => AlertDialog(
                          title: const Text('Remove player?'),
                          content: Text(
                            'Remove ${p.name} from ${team.name}? '
                            'Their past match figures are not changed.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(d, false),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(d, true),
                              child: const Text('Remove'),
                            ),
                          ],
                        ),
                      );
                      if (confirm != true) return;
                      setState(() => team.players.removeAt(i));
                      await store.persist();
                    },
                  ),
                );
              },
            ),
    );
  }

  /// v1.1.7: Add-player chooser — create a new player or pick an existing
  /// registered player into this team.
  void _chooseAddPlayer(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add player'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person_add_outlined),
              title: const Text('Add New Player'),
              subtitle: const Text('Create a new player profile'),
              onTap: () {
                Navigator.pop(ctx);
                _editPlayer(context, null);
              },
            ),
            ListTile(
              leading: const Icon(Icons.group_add_outlined),
              title: const Text('Choose Registered Player'),
              subtitle: const Text('Pick from registered players'),
              onTap: () {
                Navigator.pop(ctx);
                _pickRegisteredPlayer(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// v1.1.7: searchable registered-player picker. Adds the selected player
  /// to the current team using the same shared record/ID (no duplicates).
  void _pickRegisteredPlayer(BuildContext context) {
    final store = widget.store;
    final team = widget.team;
    var query = '';
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final q = query.trim().toLowerCase();
          final list = store.regPlayers.where((r) {
            if (q.isEmpty) return true;
            return r.name.toLowerCase().contains(q) ||
                (r.jerseyNo > 0 && '${r.jerseyNo}'.contains(q));
          }).toList();
          return AlertDialog(
            title: const Text('Choose Registered Player'),
            content: SizedBox(
              width: double.maxFinite,
              height: 420,
              child: Column(
                children: [
                  TextField(
                    decoration: const InputDecoration(
                      hintText: 'Search name or shirt number',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => setDialogState(() => query = v),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: list.isEmpty
                        ? const Center(
                            child:
                                Text('No registered players found.'),
                          )
                        : ListView.builder(
                            itemCount: list.length,
                            itemBuilder: (_, i) {
                              final r = list[i];
                              final already = team.players
                                  .any((p) => p.id == r.id);
                              return ListTile(
                                leading: PlayerAvatar(
                                  photoBase64: r.photoBase64.isEmpty
                                      ? null
                                      : r.photoBase64,
                                  role: r.role,
                                  name: r.name,
                                  radius: 20,
                                  fallbackIcon: Icons.person,
                                ),
                                title: Text(r.name),
                                subtitle: Text(
                                  '${r.role}${r.jerseyNo > 0 ? ' · #${r.jerseyNo}' : ''}',
                                ),
                                trailing: already
                                    ? const Icon(Icons.check,
                                        color: Colors.green)
                                    : null,
                                onTap: () async {
                                  if (already) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                            'Player is already in this team.'),
                                      ),
                                    );
                                    return;
                                  }
                                  team.players.add(r.toTeamPlayer());
                                  await store.persist();
                                  if (ctx.mounted) Navigator.pop(ctx);
                                  if (context.mounted) {
                                    setState(() {});
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                            'Player added successfully.'),
                                      ),
                                    );
                                  }
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
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
    // v1.1.6: photo management through Team Management — Add / Change /
    // Remove Image, saved on the shared player record (see save below).
    var photoBase64 = p.photoBase64;
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
                // v1.1.6: photo picker (same gallery flow as player
                // registration). Tap avatar to Add/Change; Remove Image
                // clears the photo on the shared record.
                GestureDetector(
                  onTap: () async {
                    final picker = ImagePicker();
                    final img = await picker.pickImage(
                      source: ImageSource.gallery,
                      maxWidth: 512,
                      maxHeight: 512,
                      imageQuality: 75,
                    );
                    if (img != null) {
                      final bytes = await img.readAsBytes();
                      setD(() {
                        photoBase64 = base64Encode(bytes);
                      });
                    }
                  },
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      PlayerAvatar(
                        photoBase64:
                            photoBase64.isEmpty ? null : photoBase64,
                        role: role,
                        name: nameCtrl.text,
                        radius: 40,
                        fallbackIcon: Icons.person,
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: kCyan,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.camera_alt,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                TextButton.icon(
                  onPressed: photoBase64.isEmpty
                      ? null
                      : () => setD(() => photoBase64 = ''),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Remove Image'),
                ),
                const SizedBox(height: 4),
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
      // v1.1.6: photo lives on the shared player record — when this team
      // player links to a registered player (same ID), update the
      // canonical record too so every screen shows the same photo.
      p.photoBase64 = photoBase64;
      final reg = store.regById(p.id);
      if (reg != null) {
        reg.photoBase64 = photoBase64;
        await store.upsertRegPlayer(reg);
      }
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
