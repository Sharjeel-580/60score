import 'package:flutter/material.dart';
import '../draft.dart';
import '../models.dart';
import '../player_io.dart';
import '../store.dart';
import '../theme.dart';

class DraftListScreen extends StatelessWidget {
  final Store store;
  const DraftListScreen({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Draft')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createDraft(context),
        icon: const Icon(Icons.add),
        label: const Text('New draft'),
      ),
      body: store.drafts.isEmpty
          ? const Center(
              child: Text(
                  'No drafts yet.\nCreate a draft — registered players become the pool.',
                  textAlign: TextAlign.center))
          : ListView.builder(
              itemCount: store.drafts.length,
              itemBuilder: (context, i) {
                final d = store.drafts[i];
                return ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.groups)),
                  title: Text(d.name),
                  subtitle: Text(
                      '${d.picks.length}/${d.totalPicks} picks • squad ${d.squadSize} • ${d.status}'
                      '${d.appliedToTeams ? ' • squads applied' : ''}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => store.deleteDraft(d.id),
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => DraftRoomScreen(store: store, draft: d)),
                  ),
                );
              },
            ),
    );
  }

  Future<void> _createDraft(BuildContext context) async {
    final nameCtrl =
        TextEditingController(text: 'Super Sixty Draft');
    var squadSize = 14;
    var snake = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('New draft'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Draft name')),
            const SizedBox(height: 8),
            Text('Teams (pick order): ${store.teams.map((t) => t.name).join(', ')}',
                style: const TextStyle(fontSize: 12, color: Colors.white70)),
            DropdownButtonFormField<int>(
              initialValue: squadSize,
              decoration: const InputDecoration(labelText: 'Squad size'),
              items: [11, 12, 13, 14, 15, 16, 18, 20]
                  .map((n) => DropdownMenuItem(value: n, child: Text('$n players per team')))
                  .toList(),
              onChanged: (v) => setD(() => squadSize = v ?? 14),
            ),
            SwitchListTile(
              value: snake,
              title: const Text('Snake order (reverse every round)'),
              onChanged: (v) => setD(() => snake = v),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Create')),
          ],
        ),
      ),
    );
    if (ok == true && store.teams.isNotEmpty) {
      final d = Draft(
        id: Store.newId('draft'),
        name: nameCtrl.text.trim().isEmpty ? 'Draft' : nameCtrl.text.trim(),
        teamIds: store.teams.map((t) => t.id).toList(),
        squadSize: squadSize,
        snakeOrder: snake,
      );
      await store.upsertDraft(d);
    }
  }
}

class DraftRoomScreen extends StatefulWidget {
  final Store store;
  final Draft draft;
  const DraftRoomScreen({super.key, required this.store, required this.draft});

  @override
  State<DraftRoomScreen> createState() => _DraftRoomScreenState();
}

class _DraftRoomScreenState extends State<DraftRoomScreen> {
  String query = '';
  Store get store => widget.store;
  Draft get draft => widget.draft;

  List<RegPlayer> get pool {
    final taken = draftedPlayerIds(draft);
    return store.regPlayers.where((p) => !taken.contains(p.id)).where((p) {
      if (query.isEmpty) return true;
      return p.name.toLowerCase().contains(query.toLowerCase()) ||
          p.role.toLowerCase().contains(query.toLowerCase()) ||
          p.area.toLowerCase().contains(query.toLowerCase());
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final turn = nextTurn(draft);
    final squads = draftSquads(draft);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(draft.name),
          actions: [
            IconButton(
              icon: const Icon(Icons.undo),
              tooltip: 'Undo last pick',
              onPressed: draft.picks.isEmpty
                  ? null
                  : () async {
                      setState(() => undoPick(draft));
                      await store.persist();
                    },
            ),
            PlayerListIoButtons(
              exportName: '60score_draft_squads',
              exportRows: () {
                final rows = <PlayerRow>[];
                for (final tid in draft.teamIds) {
                  for (final pick in squads[tid]?.toList() ?? <DraftPick>[]) {
                    final reg = store.regById(pick.playerId);
                    rows.add(reg != null
                        ? rowFromRegPlayer(reg, teamName: store.teamName(tid))
                        : PlayerRow(
                            teamName: store.teamName(tid),
                            playerName: pick.playerName));
                  }
                }
                return rows;
              },
              onImport: (rows) async {
                for (final r in rows) {
                  store.regPlayers.add(r.toRegPlayer(Store.newId('reg')));
                }
                await store.persist();
                if (mounted) setState(() {});
              },
            ),
          ],
          bottom: const TabBar(tabs: [
            Tab(text: 'Pick'),
            Tab(text: 'Board'),
            Tab(text: 'Squads'),
          ]),
        ),
        body: TabBarView(children: [
          // ---- Pick tab ----
          Column(children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: kPanel,
              child: draft.isComplete || turn == null
                  ? Column(children: [
                      const Text('Draft complete!',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: kCyan)),
                      const SizedBox(height: 6),
                      Text(
                          '${draft.picks.length}/${draft.totalPicks} picks done'),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: draft.appliedToTeams
                            ? null
                            : () async {
                                await store.applyDraftToTeams(draft);
                                setState(() {});
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text(
                                              'Squads applied to Scorer teams')));
                                }
                              },
                        icon: const Icon(Icons.check),
                        label: Text(draft.appliedToTeams
                            ? 'Squads applied to teams'
                            : 'Apply squads to Scorer teams'),
                      ),
                    ])
                  : Column(children: [
                      Text(
                          'Round ${turn.round} • Pick ${turn.pickNo} of ${draft.totalPicks}',
                          style: const TextStyle(color: Colors.white70)),
                      const SizedBox(height: 4),
                      Text('${store.teamName(turn.teamId)} — pick a player',
                          style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.bold,
                              color: kCopper)),
                      LinearProgressIndicator(
                          value: draftProgress(draft),
                          color: kCyan,
                          backgroundColor: kPanel2),
                    ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: TextField(
                decoration: const InputDecoration(
                    hintText: 'Search pool (name / role / area)…',
                    prefixIcon: Icon(Icons.search),
                    isDense: true),
                onChanged: (v) => setState(() => query = v),
              ),
            ),
            Expanded(
              child: pool.isEmpty
                  ? const Center(child: Text('Pool is empty.'))
                  : ListView.builder(
                      itemCount: pool.length,
                      itemBuilder: (context, i) {
                        final p = pool[i];
                        return ListTile(
                          title: Text(p.name),
                          subtitle: Text(
                              '${p.role}${p.area.isNotEmpty ? ' • ${p.area}' : ''} • ${p.availability}'),
                          trailing: turn == null
                              ? null
                              : FilledButton(
                                  onPressed: () async {
                                    setState(() => applyPick(draft, p));
                                    await store.persist();
                                  },
                                  child: const Text('Pick'),
                                ),
                        );
                      },
                    ),
            ),
          ]),
          // ---- Board tab ----
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: [
                const DataColumn(label: Text('Round')),
                for (final tid in draft.teamIds)
                  DataColumn(label: Text(store.teamName(tid))),
              ],
              rows: [
                for (var r = 1; r <= draft.squadSize; r++)
                  DataRow(cells: [
                    DataCell(Text('$r')),
                    for (final tid in draft.teamIds)
                      DataCell(Text(draft.picks
                              .where((p) => p.round == r && p.teamId == tid)
                              .map((p) => p.playerName)
                              .firstOrNull ??
                          '—')),
                  ]),
              ],
            ),
          ),
          // ---- Squads tab ----
          ListView(
            children: [
              for (final tid in draft.teamIds)
                ExpansionTile(
                  title: Text(
                      '${store.teamName(tid)} (${squads[tid]?.length ?? 0}/${draft.squadSize})'),
                  children: [
                    for (final pick in squads[tid] ?? <DraftPick>[])
                      ListTile(
                        dense: true,
                        leading: Text('#${pick.pickNo}'),
                        title: Text(pick.playerName),
                        subtitle: Text('Round ${pick.round}'),
                      ),
                    if ((squads[tid] ?? []).isEmpty)
                      const ListTile(title: Text('No picks yet')),
                  ],
                ),
            ],
          ),
        ]),
      ),
    );
  }
}
