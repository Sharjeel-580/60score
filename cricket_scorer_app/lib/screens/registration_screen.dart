import 'package:flutter/material.dart';

import '../models.dart';
import '../player_io.dart';
import '../store.dart';
import '../theme.dart';

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
              await store.persist();
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
                        leading: CircleAvatar(
                          backgroundColor: p.availability == 'Available'
                              ? kTeal
                              : kPanel2,
                          child: Text(p.name.isEmpty ? '?' : p.name[0]),
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
                          onPressed: () async {
                            await store.deleteRegPlayer(p.id);
                            if (mounted) setState(() {});
                          },
                        ),
                        onTap: () => _editRegPlayer(p),
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
    final saved = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: Text(existing == null ? 'Register player' : 'Edit player'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
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
      await store.upsertRegPlayer(p);
      if (mounted) setState(() {});
    }
  }
}
