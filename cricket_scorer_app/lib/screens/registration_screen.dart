import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models.dart';
import '../player_io.dart';
import '../scoring.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/player_avatar.dart';

const kRoles = ['Batter', 'Bowler', 'All-Rounder', 'Wicket-Keeper'];
const kBatStyles = ['Right-hand', 'Left-hand'];
const kBowlStyles = [
  'None',
  'Right-arm fast',
  'Right-arm medium',
  'Right-arm spin',
  'Left-arm fast',
  'Left-arm medium',
  'Left-arm spin',
];

class RegistrationScreen extends StatefulWidget {
  final Store store;
  const RegistrationScreen({super.key, required this.store});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  String query = '';
  String? roleFilter;
  String? areaFilter;
  String? availFilter;

  Store get store => widget.store;

  String? get effectiveArea {
    if (areaFilter == null) return null;
    final exists = store.regPlayers.any((p) => p.area == areaFilter);
    return exists ? areaFilter : null;
  }

  List<RegPlayer> get filtered {
    final area = effectiveArea;
    return store.regPlayers.where((p) {
      if (query.isNotEmpty &&
          !p.name.toLowerCase().contains(query.toLowerCase())) {
        return false;
      }
      if (roleFilter != null && p.role != roleFilter) return false;
      if (area != null && p.area != area) return false;
      if (availFilter != null && p.availability != availFilter) return false;
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final areas =
        store.regPlayers
            .map((p) => p.area)
            .where((a) => a.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final list = filtered;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Registration'),
        actions: [
          PlayerListIoButtons(
            exportName: '60score_registered_players',
            exportRows: () =>
                store.regPlayers.map((p) => rowFromRegPlayer(p)).toList(),
            onImport: (rows) async {
              for (final r in rows) {
                store.regPlayers.add(r.toRegPlayer(Store.newId('reg')));
              }
              await store.persistRegPlayersOnly();
              if (mounted) setState(() {});
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editRegPlayer(null),
        icon: const Icon(Icons.person_add),
        label: const Text('Register player'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search players…',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
              onChanged: (v) => setState(() => query = v),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                _filterDropdown('Role', roleFilter, [
                  null,
                  ...kRoles,
                ], (v) => setState(() => roleFilter = v)),
                const SizedBox(width: 8),
                _filterDropdown('Area', effectiveArea, [
                  null,
                  ...areas,
                ], (v) => setState(() => areaFilter = v)),
                const SizedBox(width: 8),
                _filterDropdown('Availability', availFilter, [
                  null,
                  'Available',
                  'Not Available',
                ], (v) => setState(() => availFilter = v)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${store.regPlayers.length} registered • ${store.regPlayers.where((p) => p.availability == 'Available').length} available — this list is the draft pool',
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ),
          ),
          const Divider(height: 8),
          Expanded(
            child: list.isEmpty
                ? const Center(
                    child: Text(
                      'No registered players yet.\nRegister players as they arrive, or import an Excel/CSV list.',
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final p = list[i];
                      return ListTile(
                        leading: PlayerAvatar(
                          photoBase64: p.photoBase64.isEmpty ? null : p.photoBase64,
                          role: p.role,
                          name: p.name,
                          radius: 22,
                        ),
                        title: Text(p.name),
                        subtitle: Text(
                          '${p.role}${p.category.isNotEmpty ? ' • ${p.category}' : ''}'
                          '${p.area.isNotEmpty ? ' • ${p.area}' : ''}'
                          '${p.phone.isNotEmpty ? ' • ${p.phone}' : ''}\n'
                          '${p.regStatus} • ${p.availability}'
                          '${p.teamName.isNotEmpty ? ' • Team: ${p.teamName}' : ''}',
                        ),
                        isThreeLine: true,
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Delete player',
                          onPressed: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (c) => AlertDialog(
                                title: const Text('Delete player?'),
                                content: Text(
                                  'Remove "${p.name}" from registered players?',
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
                              await store.deleteRegPlayer(p.id);
                              if (mounted) setState(() {});
                            }
                          },
                        ),
                        onTap: () => _showPlayerDetails(p),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _filterDropdown(
    String label,
    String? value,
    List<String?> options,
    void Function(String?) onChanged,
  ) {
    final allLabel = switch (label) {
      'Role' => 'All roles',
      'Area' => 'All areas',
      _ => 'All',
    };
    return DropdownButton<String?>(
      value: value,
      hint: Text(label),
      items: options
          .map(
            (o) =>
                DropdownMenuItem<String?>(value: o, child: Text(o ?? allLabel)),
          )
          .toList(),
      onChanged: onChanged,
    );
  }

  /// Player Details dialog (screen 9): existing fields + career stats,
  /// with Edit and Delete actions.
  Future<void> _showPlayerDetails(RegPlayer p) async {
    final career = computeCareerStats(store.matches);
    final stats = career[p.id];
    final avg = stats == null || (stats.inningsBatted - stats.notOuts) <= 0
        ? '–'
        : (stats.runs / (stats.inningsBatted - stats.notOuts))
              .toStringAsFixed(1);
    final sr = stats == null || stats.ballsFaced == 0
        ? '–'
        : (stats.runs * 100 / stats.ballsFaced).toStringAsFixed(1);
    Widget row(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(k, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ),
          Expanded(child: Text(v, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Row(
          children: [
            PlayerAvatar(
              photoBase64: p.photoBase64.isEmpty ? null : p.photoBase64,
              role: p.role,
              name: p.name,
              radius: 22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.name, style: const TextStyle(fontSize: 17)),
                  Text(
                    p.role,
                    style: const TextStyle(color: kCyan, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('OVERVIEW',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: kGold)),
              const SizedBox(height: 4),
              row('Full Name', p.name),
              row('Playing Role', p.role),
              row('Batting Style', p.battingStyle),
              row('Bowling Style', p.bowlingStyle),
              if (p.age > 0) row('Age', '${p.age}'),
              if (p.area.isNotEmpty) row('Area', p.area),
              if (p.phone.isNotEmpty) row('Phone', p.phone),
              if (p.category.isNotEmpty) row('Category', p.category),
              if (p.jerseyNo > 0) row('Jersey No', '${p.jerseyNo}'),
              if (p.teamName.isNotEmpty) row('Team', p.teamName),
              row('Status', '${p.regStatus} • ${p.availability}'),
              if (p.isCaptain || p.isKeeper)
                row('Tags', [
                  if (p.isCaptain) 'Captain',
                  if (p.isKeeper) 'Wicket-keeper',
                ].join(' • ')),
              if (p.remarks.isNotEmpty) row('Remarks', p.remarks),
              const SizedBox(height: 10),
              const Text('CAREER STATS (ALL TOURNAMENTS)',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: kGold)),
              const SizedBox(height: 4),
              if (stats == null || stats.matches == 0)
                const Text('No recorded matches yet.',
                    style: TextStyle(color: Colors.white54, fontSize: 12))
              else ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _statChip('Matches', '${stats.matches}'),
                    _statChip('Runs', '${stats.runs}'),
                    _statChip('Avg', avg),
                    _statChip('SR', sr),
                    _statChip('HS', '${stats.highScore}'),
                    _statChip('50s/100s', '${stats.fifties}/${stats.hundreds}'),
                    _statChip('Wickets', '${stats.wickets}'),
                    _statChip('Best', stats.bestFigures),
                  ],
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(c);
              await _editRegPlayer(p);
            },
            child: const Text('Edit'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kRed),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (c2) => AlertDialog(
                  title: const Text('Delete player?'),
                  content: Text('Remove "${p.name}" from registered players?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(c2, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: kRed),
                      onPressed: () => Navigator.pop(c2, true),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );
              if (ok == true) {
                await store.deleteRegPlayer(p.id);
                if (context.mounted) Navigator.pop(c);
                if (mounted) setState(() {});
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Widget _statChip(String label, String value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: kPanel2,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: kTeal.withValues(alpha: 0.35)),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value,
            style: const TextStyle(
                color: kWhite, fontWeight: FontWeight.w800, fontSize: 13)),
        Text(label,
            style: const TextStyle(color: Colors.white54, fontSize: 9)),
      ],
    ),
  );

  Future<void> _editRegPlayer(RegPlayer? existing) async {
    final p = existing ?? RegPlayer(id: Store.newId('reg'), name: '');
    final name = TextEditingController(text: p.name);
    final area = TextEditingController(text: p.area);
    final phone = TextEditingController(text: p.phone);
    final remarks = TextEditingController(text: p.remarks);
    final category = TextEditingController(text: p.category);
    final age = TextEditingController(text: p.age > 0 ? '${p.age}' : '');
    final jersey = TextEditingController(
      text: p.jerseyNo > 0 ? '${p.jerseyNo}' : '',
    );
    final teamName = TextEditingController(text: p.teamName);
    var role = p.role;
    var avail = p.availability;
    var bat = p.battingStyle;
    var bowl = p.bowlingStyle;
    var status = p.regStatus;
    var cap = p.isCaptain;
    var wk = p.isKeeper;
    var photoBase64 = p.photoBase64;
    final saved = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: Text(existing == null ? 'Register player' : 'Edit player'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Photo picker
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
                    children: [
                      PlayerAvatar(
                        photoBase64: photoBase64.isEmpty ? null : photoBase64,
                        role: role,
                        name: name.text,
                        radius: 40,
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
                const Text(
                  'Tap to add photo',
                  style: TextStyle(fontSize: 11, color: Colors.white54),
                ),
                const SizedBox(height: 8),
                if (photoBase64.isNotEmpty)
                  TextButton(
                    onPressed: () => setD(() => photoBase64 = ''),
                    child: const Text('Remove photo'),
                  ),
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Name *'),
                ),
                TextField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone number'),
                ),
                TextField(
                  controller: area,
                  decoration: const InputDecoration(labelText: 'Area'),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: age,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Age'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: jersey,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Jersey no',
                        ),
                      ),
                    ),
                  ],
                ),
                TextField(
                  controller: category,
                  decoration: const InputDecoration(
                    labelText: 'Category (optional)',
                  ),
                ),
                TextField(
                  controller: teamName,
                  decoration: const InputDecoration(
                    labelText: 'Team name (optional)',
                  ),
                ),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: kRoles
                      .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                      .toList(),
                  onChanged: (v) => setD(() => role = v ?? role),
                ),
                DropdownButtonFormField<String>(
                  initialValue: bat,
                  decoration: const InputDecoration(labelText: 'Batting style'),
                  items: kBatStyles
                      .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                      .toList(),
                  onChanged: (v) => setD(() => bat = v ?? bat),
                ),
                DropdownButtonFormField<String>(
                  initialValue: bowl,
                  decoration: const InputDecoration(labelText: 'Bowling style'),
                  items: kBowlStyles
                      .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                      .toList(),
                  onChanged: (v) => setD(() => bowl = v ?? bowl),
                ),
                DropdownButtonFormField<String>(
                  initialValue: avail,
                  decoration: const InputDecoration(labelText: 'Availability'),
                  items: const [
                    DropdownMenuItem(
                      value: 'Available',
                      child: Text('Available'),
                    ),
                    DropdownMenuItem(
                      value: 'Not Available',
                      child: Text('Not Available'),
                    ),
                  ],
                  onChanged: (v) => setD(() => avail = v ?? avail),
                ),
                DropdownButtonFormField<String>(
                  initialValue: status,
                  decoration: const InputDecoration(
                    labelText: 'Registration status',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'Confirmed',
                      child: Text('Confirmed'),
                    ),
                    DropdownMenuItem(value: 'Pending', child: Text('Pending')),
                  ],
                  onChanged: (v) => setD(() => status = v ?? status),
                ),
                TextField(
                  controller: remarks,
                  decoration: const InputDecoration(labelText: 'Remarks'),
                ),
                CheckboxListTile(
                  value: cap,
                  title: const Text('Captain'),
                  onChanged: (v) => setD(() => cap = v ?? false),
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
    if (saved == true && name.text.trim().isNotEmpty) {
      p.name = name.text.trim();
      p.phone = phone.text.trim();
      p.area = area.text.trim();
      p.remarks = remarks.text.trim();
      p.category = category.text.trim();
      p.teamName = teamName.text.trim();
      p.age = int.tryParse(age.text) ?? 0;
      p.jerseyNo = int.tryParse(jersey.text) ?? 0;
      p.role = role;
      p.availability = avail;
      p.battingStyle = bat;
      p.bowlingStyle = bowl;
      p.regStatus = status;
      p.isCaptain = cap;
      p.isKeeper = wk;
      p.photoBase64 = photoBase64;
      await store.upsertRegPlayer(p);
      if (mounted) setState(() {});
    }
  }
}
