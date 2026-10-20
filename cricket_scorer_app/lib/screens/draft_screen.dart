import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../draft.dart';
import '../models.dart';
import '../player_io.dart';
import '../store.dart';
import '../theme.dart';
import 'registration_screen.dart';

// ---------------------------------------------------------------------------
// Shared helpers for the drafting flow (v1.1.2 redesign).
// ---------------------------------------------------------------------------

/// Standard delete-confirmation dialog. Returns true when confirmed.
Future<bool> confirmDelete(
  BuildContext context,
  String title,
  String message,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: kRed),
          onPressed: () => Navigator.pop(c, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return ok == true;
}

String _fmtDate(int ms) {
  if (ms <= 0) return '—';
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

String _roleShort(String role) {
  switch (role) {
    case 'Bowler':
      return 'BOWL';
    case 'All-Rounder':
      return 'AR';
    case 'Wicket-Keeper':
      return 'WK';
    default:
      return 'BAT';
  }
}

Color _roleColor(String role) {
  switch (role) {
    case 'Bowler':
      return const Color(0xFF9B6BF3);
    case 'All-Rounder':
      return kGreen;
    case 'Wicket-Keeper':
      return kGold;
    default:
      return kTeal;
  }
}

/// Small role badge chip (BAT / BOWL / AR / WK).
class RoleBadge extends StatelessWidget {
  final String role;
  const RoleBadge(this.role, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _roleColor(role).withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _roleColor(role).withValues(alpha: 0.6)),
      ),
      child: Text(
        _roleShort(role),
        style: TextStyle(
          color: _roleColor(role),
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

Widget _panel(Widget child) => Container(
  width: double.infinity,
  padding: const EdgeInsets.all(14),
  decoration: BoxDecoration(
    color: kPanel,
    borderRadius: BorderRadius.circular(14),
    border: Border.all(color: kTeal.withValues(alpha: 0.35)),
  ),
  child: child,
);

Widget _navRow(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String subtitle,
  required VoidCallback onTap,
  Color? iconColor,
}) {
  return Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: ListTile(
      leading: Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: (iconColor ?? kCyan).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor ?? kCyan, size: 22),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: const Icon(Icons.chevron_right, color: kSilver),
      onTap: onTap,
    ),
  );
}

/// Export a draft as CSV / PDF / Excel using the existing share helpers.
Future<void> showDraftExportSheet(
  BuildContext context,
  Store store,
  Draft draft,
) async {
  await showModalBottomSheet<void>(
    context: context,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Export Draft',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              '${draft.name} • ${draft.picks.length} picks',
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
            const SizedBox(height: 12),
            _navRow(
              context,
              icon: Icons.table_chart,
              title: 'CSV report',
              subtitle: 'Round-wise pick list (.csv)',
              onTap: () {
                Navigator.pop(c);
                _exportDraftCsv(draft, store);
              },
            ),
            _navRow(
              context,
              icon: Icons.picture_as_pdf,
              title: 'PDF report',
              subtitle: 'Printable draft summary (.pdf)',
              onTap: () {
                Navigator.pop(c);
                _exportDraftPdf(draft, store);
              },
            ),
            _navRow(
              context,
              icon: Icons.grid_on,
              title: 'Excel squads',
              subtitle: 'Team squads sheet (.xlsx)',
              onTap: () {
                Navigator.pop(c);
                _exportDraftXlsx(draft, store);
              },
            ),
          ],
        ),
      ),
    ),
  );
}

String _draftCsv(Draft d, Store store) {
  final buf = StringBuffer('Round,Pick,Team,Player,Role\n');
  String cell(String v) => '"${v.replaceAll('"', '""')}"';
  final picks = List<DraftPick>.of(d.picks)
    ..sort((a, b) => a.pickNo.compareTo(b.pickNo));
  for (final p in picks) {
    final role = store.regById(p.playerId)?.role ?? '';
    buf.writeln(
      '${p.round},${p.pickNo},${cell(store.teamName(p.teamId))},'
      '${cell(p.playerName)},${cell(role)}',
    );
  }
  return buf.toString();
}

Future<void> _exportDraftCsv(Draft d, Store store) =>
    shareCsvFile('60score_draft_${d.id}.csv', _draftCsv(d, store));

Future<void> _exportDraftPdf(Draft d, Store store) async {
  final doc = pw.Document();
  final picks = List<DraftPick>.of(d.picks)
    ..sort((a, b) => a.pickNo.compareTo(b.pickNo));
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (_) => [
        pw.Header(
          level: 0,
          child: pw.Text(
            '60Score Draft Report — ${d.name}',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.Paragraph(
          text:
              'Status: ${d.status} • Rounds: ${d.rounds} • '
              'Picks: ${d.picks.length}/${d.totalPicks} • '
              'Date: ${_fmtDate(d.createdAt)}',
        ),
        pw.TableHelper.fromTextArray(
          headers: const ['Pick', 'Round', 'Team', 'Player'],
          data: [
            for (final p in picks)
              [
                '${p.pickNo}',
                '${p.round}',
                store.teamName(p.teamId),
                p.playerName,
              ],
          ],
        ),
      ],
    ),
  );
  final bytes = await doc.save();
  await shareBytes('60score_draft_${d.id}.pdf', bytes, text: '60Score draft report');
}

Future<void> _exportDraftXlsx(Draft d, Store store) {
  final rows = <PlayerRow>[];
  final squads = draftSquads(d);
  for (final tid in d.teamIds) {
    for (final pick in squads[tid] ?? <DraftPick>[]) {
      final reg = store.regById(pick.playerId);
      rows.add(
        reg != null
            ? rowFromRegPlayer(reg, teamName: store.teamName(tid))
            : PlayerRow(
                teamName: store.teamName(tid),
                playerName: pick.playerName,
              ),
      );
    }
  }
  return shareXlsxFile('60score_draft_${d.id}.xlsx', rows);
}

// ---------------------------------------------------------------------------
// 1. Drafting Overview — tournament card, counts, actions, draft list.
// ---------------------------------------------------------------------------

class DraftListScreen extends StatefulWidget {
  final Store store;
  const DraftListScreen({super.key, required this.store});

  @override
  State<DraftListScreen> createState() => _DraftListScreenState();
}

class _DraftListScreenState extends State<DraftListScreen> {
  Store get store => widget.store;

  @override
  void initState() {
    super.initState();
    store.addListener(_onStore);
  }

  @override
  void dispose() {
    store.removeListener(_onStore);
    super.dispose();
  }

  void _onStore() {
    if (mounted) setState(() {});
  }

  Tournament? get _tournament {
    return store.tournaments.isEmpty ? null : store.tournaments.first;
  }

  Draft? get _latest => store.drafts.isEmpty ? null : store.drafts.first;

  String _draftStatusLabel(Draft? d) {
    if (d == null) return 'Not Started';
    if (d.status == 'completed' || d.isComplete) return 'Completed';
    return d.picks.isEmpty ? 'Not Started' : 'Live';
  }

  @override
  Widget build(BuildContext context) {
    final t = _tournament;
    final latest = _latest;
    final rounds = latest?.rounds ?? 14;
    return Scaffold(
      appBar: AppBar(title: const Text('Drafting')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          const SectionTitle(icon: Icons.emoji_events, title: 'Drafting'),
          // ---- tournament card ----
          _panel(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.emoji_events, color: kGold, size: 30),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t?.name ?? 'No tournament',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                          if (t != null && t.venue.isNotEmpty)
                            Text(
                              t.venue,
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                    StatusPill(
                      switch (_draftStatusLabel(latest)) {
                        'Live' => 'live',
                        'Completed' => 'completed',
                        _ => 'not started',
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: StatChip(
                        'Teams',
                        '${latest?.teamIds.length ?? store.teams.length}',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: StatChip(
                        'Players',
                        '${store.regPlayers.length}',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: StatChip('Rounds', '$rounds')),
                    const SizedBox(width: 8),
                    Expanded(
                      child: StatChip(
                        'Picks',
                        latest == null
                            ? '0'
                            : '${latest.picks.length}/${latest.totalPicks}',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          GoldButton(
            label: latest == null ? 'Start Draft' : 'Open Live Draft',
            icon: Icons.play_arrow,
            onPressed: () {
              if (latest == null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DraftSettingsScreen(store: store),
                  ),
                );
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        DraftRoomScreen(store: store, draft: latest),
                  ),
                );
              }
            },
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    DraftSettingsScreen(store: store, draft: latest),
              ),
            ),
            icon: const Icon(Icons.settings),
            label: const Text('Draft Settings'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: BorderSide(color: kCyan.withValues(alpha: 0.6)),
            ),
          ),
          const SectionTitle(icon: Icons.dashboard, title: 'Manage'),
          _navRow(
            context,
            icon: Icons.person_add_alt,
            title: 'Draft Players',
            subtitle: 'Manage registered players (the draft pool)',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => RegistrationScreen(store: store),
              ),
            ),
          ),
          _navRow(
            context,
            icon: Icons.groups,
            title: 'Team Squads',
            subtitle: 'View squads after draft',
            onTap: () => _needDraft(
              context,
              (d) => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DraftSquadsScreen(store: store, draft: d),
                ),
              ),
            ),
          ),
          _navRow(
            context,
            icon: Icons.history,
            title: 'Draft History',
            subtitle: 'View picks and changes',
            onTap: () => _needDraft(
              context,
              (d) => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DraftHistoryScreen(store: store, draft: d),
                ),
              ),
            ),
          ),
          _navRow(
            context,
            icon: Icons.ios_share,
            iconColor: kGold,
            title: 'Export Draft',
            subtitle: 'PDF, CSV reports',
            onTap: () => _needDraft(
              context,
              (d) => showDraftExportSheet(context, store, d),
            ),
          ),
          const SectionTitle(icon: Icons.list_alt, title: 'Drafts'),
          if (store.drafts.isEmpty)
            const EmptyState(
              icon: Icons.groups_outlined,
              title: 'No drafts yet',
              subtitle:
                  'Configure draft settings, then run the draft — registered players become the pool.',
            )
          else
            for (final d in store.drafts)
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: kPanel2,
                    child: Icon(Icons.groups, color: kCyan),
                  ),
                  title: Text(
                    d.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    '${d.picks.length}/${d.totalPicks} picks • '
                    '${d.teamIds.length} teams • ${d.rounds} rounds • ${d.status}'
                    '${d.appliedToTeams ? ' • squads applied' : ''}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: kRed),
                    tooltip: 'Delete draft',
                    onPressed: () async {
                      final ok = await confirmDelete(
                        context,
                        'Delete draft?',
                        'Delete "${d.name}" and all its picks? Team squads already applied to Scorer teams are kept.',
                      );
                      if (ok) await store.deleteDraft(d.id);
                    },
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          DraftSummaryScreen(store: store, draft: d),
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }

  /// Runs [go] with the latest draft, or opens settings when none exists.
  void _needDraft(BuildContext context, void Function(Draft d) go) {
    final d = _latest;
    if (d == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Create draft settings first.'),
        ),
      );
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => DraftSettingsScreen(store: store)),
      );
      return;
    }
    go(d);
  }
}

// ---------------------------------------------------------------------------
// 2. Draft Settings — tournament, ordered teams, rounds, timer, toggles,
//    per-round manual pick orders. Save first, then the draft runs.
// ---------------------------------------------------------------------------

class DraftSettingsScreen extends StatefulWidget {
  final Store store;
  final Draft? draft; // null = create new
  const DraftSettingsScreen({super.key, required this.store, this.draft});

  @override
  State<DraftSettingsScreen> createState() => _DraftSettingsScreenState();
}

class _DraftSettingsScreenState extends State<DraftSettingsScreen> {
  Store get store => widget.store;

  final _nameCtrl = TextEditingController();
  String tournamentId = '';
  List<String> selectedTeamIds = [];
  int rounds = 14;
  int pickTimeSeconds = 30;
  bool allowManualSkip = true;
  bool allowUndo = true;
  bool autoNextPick = false;
  bool showPlayerRoles = true;
  bool snakeOrder = false;
  bool manualRoundsEnabled = false;
  Map<String, List<String>> manualRounds = {};

  @override
  void initState() {
    super.initState();
    final d = widget.draft;
    if (d != null) {
      _nameCtrl.text = d.name;
      tournamentId = d.tournamentId;
      selectedTeamIds = List.of(
        d.manualPickOrder.isNotEmpty ? d.manualPickOrder : d.teamIds,
      );
      rounds = d.squadSize;
      pickTimeSeconds = d.pickTimeSeconds;
      allowManualSkip = d.allowManualSkip;
      allowUndo = d.allowUndo;
      autoNextPick = d.autoNextPick;
      showPlayerRoles = d.showPlayerRoles;
      snakeOrder = d.snakeOrder;
      manualRoundsEnabled = d.manualRoundPicks.isNotEmpty;
      manualRounds = {
        for (final e in d.manualRoundPicks.entries) e.key: List.of(e.value),
      };
    } else {
      // New draft defaults to the first tournament, if one exists.
      tournamentId =
          store.tournaments.isEmpty ? '' : store.tournaments.first.id;
      final t = store.tournamentById(tournamentId);
      // Draft name follows the selected tournament — not hardcoded.
      _nameCtrl.text = t != null ? '${t.name} Draft' : 'New Draft';
      if (t != null) selectedTeamIds = List.of(t.teamIds);
    }
    if (tournamentId.isEmpty && store.tournaments.isNotEmpty) {
      tournamentId = store.tournaments.first.id;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Tournament? get _tournament => store.tournamentById(tournamentId);

  List<Team> get _tournamentTeams {
    final t = _tournament;
    if (t == null) return [];
    return [
      for (final id in t.teamIds)
        if (store.teamById(id) != null) store.teamById(id)!,
    ];
  }

  List<String> _roundOrder(int round) {
    final key = '$round';
    final saved = manualRounds[key];
    if (saved != null && saved.isNotEmpty) {
      return saved.where((id) => selectedTeamIds.contains(id)).toList();
    }
    return List.of(selectedTeamIds);
  }

  void _moveIn(List<String> list, int i, int dir) {
    final j = i + dir;
    if (j < 0 || j >= list.length) return;
    setState(() {
      final tmp = list[i];
      list[i] = list[j];
      list[j] = tmp;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.draft == null ? 'Draft Settings' : 'Edit Draft Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          const SectionTitle(icon: Icons.settings, title: 'Draft Settings'),
          // ---- tournament ----
          _panel(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tournament',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: tournamentId.isEmpty ? null : tournamentId,
                  decoration: const InputDecoration(isDense: true),
                  items: [
                    for (final t in store.tournaments)
                      DropdownMenuItem(value: t.id, child: Text(t.name)),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() {
                      tournamentId = v;
                      final t = store.tournamentById(v);
                      selectedTeamIds = t == null ? [] : List.of(t.teamIds);
                      manualRounds.clear();
                      // Suggest draft name from the newly selected tournament
                      // (user can still edit it freely).
                      if (t != null) _nameCtrl.text = '${t.name} Draft';
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Draft name',
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          // ---- teams with order ----
          const SectionTitle(icon: Icons.groups, title: 'Teams & Pick Order'),
          _panel(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pick order (${selectedTeamIds.length}) — use arrows to reorder',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                if (selectedTeamIds.isEmpty)
                  const Text(
                    'No teams selected.',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                for (var i = 0; i < selectedTeamIds.length; i++)
                  _teamOrderRow(selectedTeamIds[i], i, selectedTeamIds),
                const SizedBox(height: 8),
                const Text(
                  'Available teams',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final t in _tournamentTeams)
                      if (!selectedTeamIds.contains(t.id))
                        ActionChip(
                          avatar: const Icon(Icons.add, size: 16),
                          label: Text(t.name),
                          onPressed: () => setState(
                            () => selectedTeamIds.add(t.id),
                          ),
                        ),
                  ],
                ),
              ],
            ),
          ),
          // ---- rounds / pick time ----
          const SectionTitle(icon: Icons.format_list_numbered, title: 'Rounds & Timer'),
          _panel(
            Column(
              children: [
                _stepper(
                  'Number of Rounds',
                  'one pick per team per round',
                  rounds,
                  1,
                  20,
                  (v) => setState(() {
                    rounds = v;
                    manualRounds.removeWhere(
                      (k, _) => (int.tryParse(k) ?? 1) > rounds,
                    );
                  }),
                ),
                const Divider(height: 20),
                _stepper(
                  'Pick Time (seconds)',
                  'countdown per pick',
                  pickTimeSeconds,
                  5,
                  300,
                  step: 5,
                  (v) => setState(() => pickTimeSeconds = v),
                ),
              ],
            ),
          ),
          // ---- toggles ----
          const SectionTitle(icon: Icons.tune, title: 'Draft Rules'),
          _panel(
            Column(
              children: [
                SwitchListTile(
                  value: allowManualSkip,
                  title: const Text('Allow Manual Skip'),
                  subtitle: const Text('Skip a team\'s turn (forfeits the pick)'),
                  onChanged: (v) => setState(() => allowManualSkip = v),
                ),
                SwitchListTile(
                  value: allowUndo,
                  title: const Text('Allow Undo'),
                  subtitle: const Text('Remove the last pick'),
                  onChanged: (v) => setState(() => allowUndo = v),
                ),
                SwitchListTile(
                  value: autoNextPick,
                  title: const Text('Auto Next Pick'),
                  subtitle: const Text(
                    'Restart the timer automatically after each pick. '
                    'OFF = fully manual (default). Never auto-picks a player.',
                  ),
                  onChanged: (v) => setState(() => autoNextPick = v),
                ),
                SwitchListTile(
                  value: showPlayerRoles,
                  title: const Text('Show Player Roles'),
                  subtitle: const Text('Role badges in the player pool'),
                  onChanged: (v) => setState(() => showPlayerRoles = v),
                ),
                SwitchListTile(
                  value: snakeOrder,
                  title: const Text('Snake order'),
                  subtitle: const Text('Reverse pick order every even round'),
                  onChanged: (v) => setState(() => snakeOrder = v),
                ),
                SwitchListTile(
                  value: manualRoundsEnabled,
                  title: const Text('Manual Round Picks'),
                  subtitle: const Text('Set a custom pick order per round'),
                  onChanged: (v) => setState(() {
                    manualRoundsEnabled = v;
                    if (!v) manualRounds.clear();
                  }),
                ),
              ],
            ),
          ),
          if (manualRoundsEnabled) ...[
            const SectionTitle(
              icon: Icons.reorder,
              title: 'Per-Round Pick Order',
            ),
            for (var r = 1; r <= rounds; r++)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ExpansionTile(
                  title: Text('Round $r'),
                  subtitle: Text(
                    _roundOrder(r).map(store.teamName).join(' → '),
                    style: const TextStyle(fontSize: 11),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  children: [
                    Builder(
                      builder: (context) {
                        final order = _roundOrder(r);
                        manualRounds['$r'] = order;
                        return Column(
                          children: [
                            for (var i = 0; i < order.length; i++)
                              _teamOrderRow(order[i], i, order),
                            const SizedBox(height: 6),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 16),
          GoldButton(
            label: widget.draft == null ? 'Save Settings' : 'Update Settings',
            icon: Icons.save,
            onPressed: _save,
          ),
        ],
      ),
    );
  }

  Widget _teamOrderRow(String teamId, int i, List<String> list) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: kGold.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: kGold.withValues(alpha: 0.5)),
            ),
            child: Text(
              '${i + 1}',
              style: const TextStyle(
                color: kGold,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TeamAvatar(store.teamName(teamId), radius: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              store.teamName(teamId),
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.arrow_upward, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: i == 0 ? null : () => _moveIn(list, i, -1),
          ),
          IconButton(
            icon: const Icon(Icons.arrow_downward, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: i == list.length - 1
                ? null
                : () => _moveIn(list, i, 1),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18, color: kRed),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: 'Remove team',
            onPressed: list == selectedTeamIds
                ? () => setState(() {
                    selectedTeamIds.remove(teamId);
                    for (final e in manualRounds.entries) {
                      e.value.remove(teamId);
                    }
                  })
                : null,
          ),
        ],
      ),
    );
  }

  Widget _stepper(
    String label,
    String hint,
    int value,
    int min,
    int max,
    void Function(int) onChanged, {
    int step = 1,
  }) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(
                hint,
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: value > min ? () => onChanged(value - step) : null,
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 52),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: kPanel2,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$value',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          onPressed: value < max ? () => onChanged(value + step) : null,
        ),
      ],
    );
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Give the draft a name.')),
      );
      return;
    }
    if (selectedTeamIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one team.')),
      );
      return;
    }
    final existing = widget.draft;
    final hasPicks = existing != null && existing.picks.isNotEmpty;
    if (hasPicks) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Update draft settings?'),
          content: const Text(
            'This draft already has picks. Changing teams or order will '
            're-index the existing picks to keep rounds fair.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Update'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }

    final d = existing ??
        Draft(
          id: Store.newId('draft'),
          name: name,
          teamIds: List.of(selectedTeamIds),
          createdAt: DateTime.now().millisecondsSinceEpoch,
        );
    d.name = name;
    d.tournamentId = tournamentId;
    d.teamIds = List.of(selectedTeamIds);
    d.manualPickOrder = List.of(selectedTeamIds);
    d.squadSize = rounds;
    d.pickTimeSeconds = pickTimeSeconds;
    d.allowManualSkip = allowManualSkip;
    d.allowUndo = allowUndo;
    d.autoNextPick = autoNextPick;
    d.showPlayerRoles = showPlayerRoles;
    d.snakeOrder = snakeOrder;
    d.manualRoundPicks = manualRoundsEnabled
        ? {
            for (var r = 1; r <= rounds; r++)
              '$r': _roundOrder(r),
          }
        : {};
    if (hasPicks) reindexPicks(d);
    await store.upsertDraft(d);
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Draft settings saved.')),
      );
    }
  }
}

// ---------------------------------------------------------------------------
// 4. Live Draft room — current pick, upcoming picks, timer, player pool.
//    Fully manual: nothing is ever auto-picked. Progress is persisted after
//    every change, so reopening the room never resets the draft.
// ---------------------------------------------------------------------------

const _poolRoles = ['Batter', 'Bowler', 'All-Rounder', 'Wicket-Keeper'];

class DraftRoomScreen extends StatefulWidget {
  final Store store;
  final Draft draft;
  const DraftRoomScreen({super.key, required this.store, required this.draft});

  @override
  State<DraftRoomScreen> createState() => _DraftRoomScreenState();
}

class _DraftRoomScreenState extends State<DraftRoomScreen> {
  Store get store => widget.store;
  Draft get draft => widget.draft;

  String query = '';
  String roleFilter = 'All';
  int secondsLeft = 30;
  bool timerRunning = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    secondsLeft = draft.pickTimeSeconds;
    store.addListener(_onStore);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    // Start the clock for the first pick automatically.
    if (!draft.isComplete) timerRunning = true;
  }

  @override
  void dispose() {
    _timer?.cancel();
    store.removeListener(_onStore);
    super.dispose();
  }

  void _onStore() {
    if (mounted) setState(() {});
  }

  void _tick() {
    if (!mounted || !timerRunning) return;
    if (draft.isComplete) {
      setState(() => timerRunning = false);
      return;
    }
    setState(() {
      if (secondsLeft > 0) secondsLeft--;
      if (secondsLeft == 0) timerRunning = false; // time's up: pick manually
    });
  }

  void _resetTimer() =>
      setState(() => secondsLeft = draft.pickTimeSeconds);

  List<RegPlayer> get pool {
    final taken = draftedPlayerIds(draft);
    return store.regPlayers.where((p) {
      if (taken.contains(p.id)) return false;
      if (roleFilter != 'All' && p.role != roleFilter) return false;
      if (query.isEmpty) return true;
      final q = query.toLowerCase();
      return p.name.toLowerCase().contains(q) ||
          p.role.toLowerCase().contains(q) ||
          p.area.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _pick(RegPlayer p) async {
    if (!applyPick(draft, p)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pick failed — player taken or squad full.')),
        );
      }
      return;
    }
    setState(() {
      if (draft.autoNextPick && !draft.isComplete) {
        secondsLeft = draft.pickTimeSeconds;
        timerRunning = true;
      } else {
        timerRunning = false;
      }
    });
    await store.persist();
  }

  Future<void> _skip() async {
    final turn = nextTurn(draft);
    if (turn == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Skip this turn?'),
        content: Text(
          '${store.teamName(turn.teamId)} forfeits pick #${turn.pickNo}. '
          'This cannot be undone except via Undo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Skip turn'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      skipTurn(draft);
      timerRunning = false;
    });
    await store.persist();
  }

  Future<void> _undo() async {
    setState(() {
      undoPick(draft);
      timerRunning = false;
    });
    await store.persist();
  }

  String get _clock {
    final m = secondsLeft ~/ 60;
    final s = secondsLeft % 60;
    return '${m.toString().padLeft(2, '0')} : ${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final turn = nextTurn(draft);
    final upcoming = upcomingTurns(draft, 6);
    final complete = draft.isComplete || turn == null;
    return Scaffold(
      appBar: AppBar(
        title: Text(draft.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Draft history',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DraftHistoryScreen(store: store, draft: draft),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.groups),
            tooltip: 'Team squads',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DraftSquadsScreen(store: store, draft: draft),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: 'Export draft',
            onPressed: () => showDraftExportSheet(context, store, draft),
          ),
        ],
      ),
      body: complete ? _buildComplete(context) : _buildLive(context, turn, upcoming),
    );
  }

  Widget _buildLive(BuildContext context, DraftTurn turn, List<DraftTurn> upcoming) {
    final list = pool;
    return Column(
      children: [
        // ---- header: round/pick + timer ----
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            color: kPanel,
            border: Border(bottom: BorderSide(color: kTeal.withValues(alpha: 0.3))),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Round ${turn.round} of ${draft.rounds}  •  Pick ${turn.pickNo} of ${draft.totalPicks}',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(width: 8),
                  const StatusPill('live'),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Time Remaining',
                    style: TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _clock,
                    style: TextStyle(
                      color: secondsLeft == 0 ? kRed : kCyan,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton.filled(
                    onPressed: () =>
                        setState(() => timerRunning = !timerRunning),
                    icon: Icon(timerRunning ? Icons.pause : Icons.play_arrow),
                    style: IconButton.styleFrom(backgroundColor: kGold),
                    color: const Color(0xFF2B1C05),
                    tooltip: timerRunning ? 'Pause timer' : 'Resume timer',
                  ),
                  IconButton(
                    onPressed: _resetTimer,
                    icon: const Icon(Icons.refresh, color: kSilver),
                    tooltip: 'Reset timer',
                  ),
                ],
              ),
              if (secondsLeft == 0)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    "Time's up — pick manually, the draft never auto-picks.",
                    style: TextStyle(color: kRed, fontSize: 11),
                  ),
                ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: draftProgress(draft),
                  minHeight: 8,
                  color: kCyan,
                  backgroundColor: kPanel2,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              // ---- current pick ----
              _panel(
                Row(
                  children: [
                    TeamAvatar(store.teamName(turn.teamId), radius: 26),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Current Pick',
                        style: TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      store.teamName(turn.teamId),
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: kGold,
                      ),
                    ),
                  ],
                ),
              ),
              // ---- upcoming ----
              const SectionTitle(icon: Icons.upcoming, title: 'Upcoming Picks'),
              SizedBox(
                height: 76,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: upcoming.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (context, i) {
                    final u = upcoming[i];
                    final name = store.teamName(u.teamId);
                    return Column(
                      children: [
                        TeamAvatar(name, radius: 20),
                        const SizedBox(height: 4),
                        SizedBox(
                          width: 64,
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 10),
                          ),
                        ),
                        Text(
                          '#${u.pickNo}',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white54,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              // ---- skip / undo ----
              if (draft.allowManualSkip || draft.allowUndo) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (draft.allowManualSkip)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _skip,
                          icon: const Icon(Icons.skip_next, size: 18),
                          label: const Text('Manual Skip'),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                              color: kGold.withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                      ),
                    if (draft.allowManualSkip && draft.allowUndo)
                      const SizedBox(width: 10),
                    if (draft.allowUndo)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: draft.picks.isEmpty ? null : _undo,
                          icon: const Icon(Icons.undo, size: 18),
                          label: const Text('Undo Last Pick'),
                        ),
                      ),
                  ],
                ),
              ],
              // ---- player pool ----
              const SectionTitle(icon: Icons.person_search, title: 'Select a Player'),
              TextField(
                decoration: const InputDecoration(
                  hintText: 'Search players…',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => query = v),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final r in ['All', ..._poolRoles])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(r),
                          selected: roleFilter == r,
                          onSelected: (_) =>
                              setState(() => roleFilter = r),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${list.length} available in pool',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 6),
              if (list.isEmpty)
                const EmptyState(
                  icon: Icons.person_off_outlined,
                  title: 'Pool is empty',
                  subtitle: 'All registered players are drafted.',
                )
              else
                for (final p in list)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        backgroundColor: kPanel2,
                        child: Text(
                          p.name.isEmpty ? '?' : p.name[0].toUpperCase(),
                          style: const TextStyle(color: kCyan),
                        ),
                      ),
                      title: Text(
                        p.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '${p.role}${p.area.isNotEmpty ? ' • ${p.area}' : ''}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (draft.showPlayerRoles) RoleBadge(p.role),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: () => _pick(p),
                            style: FilledButton.styleFrom(
                              backgroundColor: kCyan,
                              foregroundColor: const Color(0xFF062A33),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                            ),
                            child: const Text(
                              'Select',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildComplete(BuildContext context) {
    final squads = draftSquads(draft);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      children: [
        const Icon(Icons.emoji_events, color: kGold, size: 64),
        const SizedBox(height: 12),
        const Center(
          child: Text(
            'Draft complete!',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: kCyan,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(
            '${draft.picks.length}/${draft.totalPicks} picks done • ${draft.rounds} rounds',
            style: const TextStyle(color: Colors.white70),
          ),
        ),
        const SizedBox(height: 16),
        GoldButton(
          label: draft.appliedToTeams
              ? 'Squads Applied to Teams'
              : 'Apply Squads to Teams',
          icon: Icons.check,
          onPressed: draft.appliedToTeams
              ? null
              : () async {
                  await store.applyDraftToTeams(draft);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Squads applied to Scorer teams'),
                      ),
                    );
                  }
                },
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => DraftHistoryScreen(store: store, draft: draft),
            ),
          ),
          icon: const Icon(Icons.history),
          label: const Text('View Draft History'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => DraftSquadsScreen(store: store, draft: draft),
            ),
          ),
          icon: const Icon(Icons.groups),
          label: const Text('View Team Squads'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => showDraftExportSheet(context, store, draft),
          icon: const Icon(Icons.ios_share),
          label: const Text('Export Draft'),
        ),
        if (draft.allowUndo) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: draft.picks.isEmpty
                ? null
                : () async {
                    await _undo();
                  },
            icon: const Icon(Icons.undo),
            label: const Text('Undo Last Pick (reopen draft)'),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: kGold.withValues(alpha: 0.7)),
            ),
          ),
        ],
        const SectionTitle(icon: Icons.groups, title: 'Final Squads'),
        for (final tid in draft.teamIds)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ExpansionTile(
              leading: TeamAvatar(store.teamName(tid), radius: 16),
              title: Text(
                '${store.teamName(tid)} (${squads[tid]?.length ?? 0}/${draft.squadSize})',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              children: [
                for (final pick in squads[tid] ?? <DraftPick>[])
                  ListTile(
                    dense: true,
                    leading: Text('#${pick.pickNo}'),
                    title: Text(pick.playerName),
                    subtitle: Text('Round ${pick.round}'),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 5. Draft History — round-wise pick list with per-pick delete.
// ---------------------------------------------------------------------------

class DraftHistoryScreen extends StatefulWidget {
  final Store store;
  final Draft draft;
  const DraftHistoryScreen({super.key, required this.store, required this.draft});

  @override
  State<DraftHistoryScreen> createState() => _DraftHistoryScreenState();
}

class _DraftHistoryScreenState extends State<DraftHistoryScreen> {
  Store get store => widget.store;
  Draft get draft => widget.draft;
  int? roundFilter; // null = all rounds

  @override
  void initState() {
    super.initState();
    store.addListener(_onStore);
  }

  @override
  void dispose() {
    store.removeListener(_onStore);
    super.dispose();
  }

  void _onStore() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final picks = List<DraftPick>.of(draft.picks)
      ..sort((a, b) => a.pickNo.compareTo(b.pickNo));
    final rounds = <int>{for (final p in picks) p.round}.toList()..sort();
    final shown = roundFilter == null
        ? rounds
        : rounds.where((r) => r == roundFilter).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Draft History')),
      body: picks.isEmpty
          ? const EmptyState(
              icon: Icons.history,
              title: 'No picks yet',
              subtitle: 'Picks will appear here round by round.',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                _panel(
                  Row(
                    children: [
                      const Icon(Icons.filter_list, color: kCyan, size: 20),
                      const SizedBox(width: 8),
                      const Text(
                        'Round',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<int?>(
                          initialValue: roundFilter,
                          decoration: const InputDecoration(isDense: true),
                          items: [
                            const DropdownMenuItem<int?>(
                              value: null,
                              child: Text('All Rounds'),
                            ),
                            for (final r in rounds)
                              DropdownMenuItem<int?>(
                                value: r,
                                child: Text('Round $r'),
                              ),
                          ],
                          onChanged: (v) =>
                              setState(() => roundFilter = v),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                for (final r in shown) ...[
                  SectionTitle(icon: Icons.star, title: 'Round $r'),
                  for (final p in picks.where((x) => x.round == r))
                    _historyRow(context, p),
                ],
              ],
            ),
    );
  }

  Widget _historyRow(BuildContext context, DraftPick p) {
    final skipped = p.playerId.isEmpty;
    final role = skipped ? '' : (store.regById(p.playerId)?.role ?? '');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        dense: true,
        leading: Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: kGold.withValues(alpha: 0.18),
            shape: BoxShape.circle,
            border: Border.all(color: kGold.withValues(alpha: 0.5)),
          ),
          child: Text(
            '${p.pickNo}',
            style: const TextStyle(
              color: kGold,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ),
        title: Row(
          children: [
            TeamAvatar(store.teamName(p.teamId), radius: 13),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                store.teamName(p.teamId),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        subtitle: Row(
          children: [
            Expanded(
              child: Text(
                p.playerName,
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: skipped ? FontStyle.italic : FontStyle.normal,
                  color: skipped ? Colors.white54 : Colors.white,
                ),
              ),
            ),
            if (role.isNotEmpty && draft.showPlayerRoles) RoleBadge(role),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: kRed, size: 20),
          tooltip: 'Delete pick',
          onPressed: () async {
            final ok = await confirmDelete(
              context,
              'Delete pick #${p.pickNo}?',
              'Remove "${p.playerName}" from ${store.teamName(p.teamId)}? '
              'Remaining picks are re-indexed to keep rounds fair.',
            );
            if (ok) await store.deleteDraftPick(draft, p);
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 6. Team Squads — per-team drafted squads, remove-from-squad, apply.
// ---------------------------------------------------------------------------

class DraftSquadsScreen extends StatefulWidget {
  final Store store;
  final Draft draft;
  const DraftSquadsScreen({super.key, required this.store, required this.draft});

  @override
  State<DraftSquadsScreen> createState() => _DraftSquadsScreenState();
}

class _DraftSquadsScreenState extends State<DraftSquadsScreen> {
  Store get store => widget.store;
  Draft get draft => widget.draft;
  String? teamId;

  @override
  void initState() {
    super.initState();
    teamId = draft.teamIds.isEmpty ? null : draft.teamIds.first;
    store.addListener(_onStore);
  }

  @override
  void dispose() {
    store.removeListener(_onStore);
    super.dispose();
  }

  void _onStore() {
    if (mounted) {
      if (teamId != null && !draft.teamIds.contains(teamId)) {
        teamId = draft.teamIds.isEmpty ? null : draft.teamIds.first;
      }
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final squads = draftSquads(draft);
    final picks = (teamId == null ? <DraftPick>[] : squads[teamId] ?? [])
      ..sort((a, b) => a.pickNo.compareTo(b.pickNo));
    return Scaffold(
      appBar: AppBar(title: const Text('Team Squads')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _panel(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  draft.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: teamId,
                  decoration: const InputDecoration(
                    labelText: 'Team',
                    isDense: true,
                  ),
                  items: [
                    for (final tid in draft.teamIds)
                      DropdownMenuItem(
                        value: tid,
                        child: Text(
                          '${store.teamName(tid)} '
                          '(${(squads[tid] ?? []).length}/${draft.squadSize})',
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => teamId = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (teamId != null)
            _panel(
              Row(
                children: [
                  TeamAvatar(store.teamName(teamId!), radius: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          store.teamName(teamId!),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          'Squad (${picks.length}/${draft.squadSize})',
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit, color: kCyan),
                    tooltip: 'Manage team',
                    onPressed: () {
                      final t = store.teamById(teamId!);
                      if (t != null && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Manage "${t.name}" from Teams & Players.',
                            ),
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          if (picks.isEmpty)
            const EmptyState(
              icon: Icons.groups_outlined,
              title: 'No picks yet',
              subtitle: 'This team has no drafted players.',
            )
          else
            for (var i = 0; i < picks.length; i++)
              _squadRow(context, i + 1, picks[i]),
          const SizedBox(height: 16),
          GoldButton(
            label: draft.appliedToTeams
                ? 'Squads Applied to Teams'
                : 'Apply Squads to Teams',
            icon: Icons.check,
            onPressed: draft.appliedToTeams || draft.picks.isEmpty
                ? null
                : () async {
                    await store.applyDraftToTeams(draft);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content:
                              Text('Squads applied to Scorer teams'),
                        ),
                      );
                    }
                  },
          ),
        ],
      ),
    );
  }

  Widget _squadRow(BuildContext context, int n, DraftPick p) {
    final skipped = p.playerId.isEmpty;
    final reg = skipped ? null : store.regById(p.playerId);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        dense: true,
        leading: Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: kPanel2,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$n',
            style: const TextStyle(
              color: kCyan,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ),
        title: Text(
          p.playerName,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontStyle: skipped ? FontStyle.italic : FontStyle.normal,
            color: skipped ? Colors.white54 : Colors.white,
          ),
        ),
        subtitle: Text(
          'Round ${p.round} • Pick #${p.pickNo}'
          '${reg != null && reg.area.isNotEmpty ? ' • ${reg.area}' : ''}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (reg != null && draft.showPlayerRoles) RoleBadge(reg.role),
            IconButton(
              icon: const Icon(
                Icons.remove_circle_outline,
                color: kRed,
                size: 20,
              ),
              tooltip: 'Remove from squad',
              onPressed: () async {
                final ok = await confirmDelete(
                  context,
                  'Remove from squad?',
                  'Remove "${p.playerName}" from '
                  '${store.teamName(p.teamId)}\'s squad? '
                  'The pick returns to the pool order.',
                );
                if (ok) await store.deleteDraftPick(draft, p);
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 12. Tournament Draft Summary — status, totals, history/export/quick links.
// ---------------------------------------------------------------------------

class DraftSummaryScreen extends StatefulWidget {
  final Store store;
  final Draft draft;
  const DraftSummaryScreen({super.key, required this.store, required this.draft});

  @override
  State<DraftSummaryScreen> createState() => _DraftSummaryScreenState();
}

class _DraftSummaryScreenState extends State<DraftSummaryScreen> {
  Store get store => widget.store;
  Draft get draft => widget.draft;

  @override
  void initState() {
    super.initState();
    store.addListener(_onStore);
  }

  @override
  void dispose() {
    store.removeListener(_onStore);
    super.dispose();
  }

  void _onStore() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final complete = draft.isComplete;
    return Scaffold(
      appBar: AppBar(title: const Text('Draft Summary')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          const Icon(Icons.emoji_events, color: kGold, size: 72),
          const SizedBox(height: 8),
          Center(
            child: Text(
              draft.name,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: StatusPill(complete ? 'completed' : 'live'),
          ),
          const SizedBox(height: 14),
          _panel(
            Column(
              children: [
                _infoRow('Status', complete ? 'Completed' : 'In Progress'),
                _infoRow('Date', _fmtDate(draft.createdAt)),
                _infoRow('Total Players', '${store.regPlayers.length}'),
                _infoRow('Teams', '${draft.teamIds.length}'),
                _infoRow('Rounds', '${draft.rounds}'),
                _infoRow(
                  'Picks',
                  '${draft.picks.length}/${draft.totalPicks}',
                ),
                _infoRow(
                  'Squads Applied',
                  draft.appliedToTeams ? 'Yes' : 'No',
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (!complete)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GoldButton(
                label: 'Open Live Draft',
                icon: Icons.play_arrow,
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        DraftRoomScreen(store: store, draft: draft),
                  ),
                ),
              ),
            ),
          _navRow(
            context,
            icon: Icons.history,
            title: 'View Full Draft History',
            subtitle: 'Round-wise pick details',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DraftHistoryScreen(store: store, draft: draft),
              ),
            ),
          ),
          _navRow(
            context,
            icon: Icons.ios_share,
            iconColor: kGold,
            title: 'Export Draft (PDF/CSV)',
            subtitle: 'Share the draft report',
            onTap: () => showDraftExportSheet(context, store, draft),
          ),
          const SectionTitle(icon: Icons.link, title: 'Quick Links'),
          _navRow(
            context,
            icon: Icons.groups,
            title: 'Team Squads',
            subtitle: 'View squads after draft',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DraftSquadsScreen(store: store, draft: draft),
              ),
            ),
          ),
          _navRow(
            context,
            icon: Icons.person_add_alt,
            title: 'Registered Players',
            subtitle: 'The draft pool',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => RegistrationScreen(store: store),
              ),
            ),
          ),
          _navRow(
            context,
            icon: Icons.delete_outline,
            iconColor: kRed,
            title: 'Delete Draft',
            subtitle: 'Remove this draft and its picks',
            onTap: () async {
              final ok = await confirmDelete(
                context,
                'Delete draft?',
                'Delete "${draft.name}" and all its picks?',
              );
              if (ok && context.mounted) {
                await store.deleteDraft(draft.id);
                if (context.mounted) Navigator.pop(context);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.white60, fontSize: 13),
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
