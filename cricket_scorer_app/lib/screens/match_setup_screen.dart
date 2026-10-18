import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import 'scoring_screen.dart';
import 'settings_screen.dart';

class MatchSetupScreen extends StatefulWidget {
  final Store store;
  final String? tournamentId;

  /// When set, the setup edits this existing fixture in place (e.g. an
  /// upcoming fixture opened from the fixture detail screen) instead of
  /// creating a brand-new match. Starting the match flips it to live.
  final Match? existingMatch;

  const MatchSetupScreen({
    super.key,
    required this.store,
    this.tournamentId,
    this.existingMatch,
  });

  @override
  State<MatchSetupScreen> createState() => _MatchSetupScreenState();
}

/// Preset formats shown in the Match Format grid. Super Sixty is 8 overs and
/// is the default selection for a fresh setup screen.
const List<(String, int)> _formatPresets = [
  ('Super Sixty', 8),
  ('T5', 5),
  ('T10', 10),
  ('T20', 20),
  ('T30', 30),
  ('T40', 40),
  ('T50', 50),
];

const Set<int> _presetOvers = {5, 8, 10, 20, 30, 40, 50};

class _MatchSetupScreenState extends State<MatchSetupScreen> {
  String? teamAId;
  String? teamBId;
  String? tournamentId;
  final Set<String> xiA = {};
  final Set<String> xiB = {};
  int overs = 8;
  int totalWickets = 0; // 0 = auto (XI - 1)
  bool lastManStands = false;
  bool widePenalty = true;
  bool noBallPenalty = true;
  int ballsPerOver = 6;
  final venueCtrl = TextEditingController();
  final titleCtrl = TextEditingController();
  final seasonCtrl = TextEditingController();
  String ballType = 'Tennis Ball';
  DateTime date = DateTime.now();
  String? tossWinnerId;
  String tossDecision = 'bat';

  /// UI-only flags (presentational; not part of the match-creation logic).
  bool _customOvers = false; // Custom Overs toggle in the format section.
  bool _showTossDetail = false; // 'Set Now' reveals winner/decision pickers.
  bool _starting = false; // double-tap guard on the Create button.
  bool _tossSpinning = false; // coin-spin animation in progress.
  double _tossSpinTurns = 0; // animated rotation for the coin.

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
    // Redesign default: toss is 'Auto (Toss later)' until the user picks a
    // result. _canStart (unchanged) keeps Create disabled while it is null.
    tossWinnerId = null;
    // Pre-fill from an existing fixture (Start Setup flow). Only adopt team
    // IDs that actually exist, so TBD playoff slots ('') never break the
    // dropdowns with a value-not-in-items assertion.
    final em = widget.existingMatch;
    if (em != null) {
      tournamentId = em.tournamentId ?? tournamentId;
      if (em.teamAId.isNotEmpty && store.teamById(em.teamAId) != null) {
        teamAId = em.teamAId;
      }
      if (em.teamBId.isNotEmpty && store.teamById(em.teamBId) != null) {
        teamBId = em.teamBId;
      }
      overs = em.oversLimit;
      ballsPerOver = em.ballsPerOver;
      venueCtrl.text = em.venue;
      titleCtrl.text = em.matchTitle;
      seasonCtrl.text = em.season;
      final parsedDate = DateTime.tryParse(em.dateIso);
      if (parsedDate != null) date = parsedDate;
      _preselect();
      if (em.xiA.isNotEmpty) {
        xiA.clear();
        xiA.addAll(em.xiA);
      }
      if (em.xiB.isNotEmpty) {
        xiB.clear();
        xiB.addAll(em.xiB);
      }
      tossWinnerId = null;
    }
    // A non-preset overs count (e.g. from an existing fixture) means the
    // Custom Overs toggle starts enabled.
    _customOvers = !_presetOvers.contains(overs);
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
          decoration: const InputDecoration(labelText: 'Player name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, ctrl.text.trim()),
            child: const Text('Add'),
          ),
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
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            TextButton(
              onPressed: () => _quickAdd(teamId, xi),
              child: const Text('Quick-add'),
            ),
          ],
        ),
        if (team.players.isEmpty)
          const Text(
            'No squad players yet — use Quick-add.',
            style: TextStyle(color: Colors.orange),
          ),
        ...team.players.map(
          (p) => CheckboxListTile(
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
          ),
        ),
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

  String get _hint {
    if (teamAId == null || teamBId == null || teamAId == teamBId) {
      return 'Pick two different teams to continue.';
    }
    if (xiA.length < 2 || xiB.length < 2) {
      return 'Pick two different teams and at least 2 players per XI to start.';
    }
    if (tossWinnerId == null) {
      return 'Choose a toss result above (or Set Now) to create the match.';
    }
    return '';
  }

  static String _fmtDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day.toString().padLeft(2, '0')} ${months[d.month - 1]} ${d.year}';
  }

  static String _fmtTime(DateTime d) {
    final h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final ampm = d.hour < 12 ? 'AM' : 'PM';
    return '${h12.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} $ampm';
  }

  @override
  Widget build(BuildContext context) {
    final isFixture = widget.existingMatch != null;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            _header(),
            const SizedBox(height: 10),
            _titleRow(isFixture),
            const SizedBox(height: 10),
            _matchTypeRow(),
            if (tournamentId != null) ...[
              const SizedBox(height: 10),
              _tournamentPicker(),
            ],
            const SizedBox(height: 12),
            _formatSection(),
            _teamsSection(),
            _venueSection(),
            _dateTimeSection(),
            _tossSection(),
            _settingsSection(),
            const SizedBox(height: 4),
            Opacity(
              opacity: _canStart && !_starting ? 1 : 0.45,
              child: GoldButton(
                label: _starting
                    ? 'Creating…'
                    : (isFixture ? 'Start Match' : 'Create Match'),
                icon: Icons.play_arrow,
                onPressed: _canStart && !_starting ? _create : null,
              ),
            ),
            // v1.1.6: "Add Fixture" — save the schedule now, score later.
            // Relaxed validation: only two different teams are required
            // (no squad, no Playing XI, no toss). Hidden when editing an
            // existing fixture (that screen already has Start Match).
            if (!isFixture) ...[
              const SizedBox(height: 10),
              Opacity(
                opacity: _canSaveFixture && !_savingFixture ? 1 : 0.45,
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.event_note, size: 20),
                    label: Text(
                        _savingFixture ? 'Saving…' : 'Add Fixture — score later'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kCyan,
                      side: BorderSide(
                          color: kCyan.withValues(alpha: 0.6), width: 1.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    onPressed: _canSaveFixture && !_savingFixture
                        ? _saveFixture
                        : null,
                  ),
                ),
              ),
              if (!_canSaveFixture)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Pick two different teams to save a fixture.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ),
            ],
            if (!_canStart)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _hint,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.orange),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ---------- Header ----------

  Widget _header() {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        const Expanded(
          child: Column(
            children: [
              Text(
                '60Score',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: kWhite,
                ),
              ),
              Text(
                'Cricket Scoring, Simplified.',
                style: TextStyle(fontSize: 12, color: Colors.white54),
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.settings),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SettingsScreen(store: store),
            ),
          ),
        ),
      ],
    );
  }

  Widget _titleRow(bool isFixture) {
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            gradient: kGoldGradient,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(
            Icons.sports_cricket,
            color: Color(0xFF2B1C05),
            size: 26,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isFixture ? 'Fixture Setup' : 'New Match',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: kWhite,
                ),
              ),
              Text(
                isFixture
                    ? 'Update the fixture details, then start'
                    : 'Create a quick or custom match',
                style: const TextStyle(fontSize: 12, color: Colors.white54),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Quick Match <=> tournamentId == null (the old 'Friendly / none' choice);
  /// Tournament Match <=> a tournament is attached.
  Widget _matchTypeRow() {
    final quick = tournamentId == null;
    return Row(
      children: [
        Expanded(
          child: OptionCard(
            title: 'Quick Match',
            subtitle: 'Create a standalone match',
            icon: Icons.bolt,
            selected: quick,
            onTap: () {
              if (!quick) setState(() => tournamentId = null);
            },
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OptionCard(
            title: 'Tournament Match',
            subtitle: 'From existing tournament',
            icon: Icons.emoji_events,
            selected: !quick,
            onTap: () {
              if (!quick) return;
              if (store.tournaments.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('No tournaments yet — create one first.'),
                  ),
                );
                return;
              }
              setState(() => tournamentId = store.tournaments.first.id);
            },
          ),
        ),
      ],
    );
  }

  /// Which tournament a Tournament Match belongs to (the old optional
  /// tournament dropdown, shown only in Tournament Match mode).
  Widget _tournamentPicker() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: kPanel2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kCyan.withValues(alpha: 0.25)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: tournamentId,
          hint: const Text('Select tournament'),
          items: store.tournaments
              .map((t) => DropdownMenuItem(value: t.id, child: Text(t.name)))
              .toList(),
          onChanged: (v) => setState(() {
            tournamentId = v;
            // Same preselect the old initState applied when a tournament was
            // attached: default the two sides to the tournament's teams.
            final t = store.tournamentById(v);
            if (t != null && t.teamIds.length >= 2) {
              teamAId = t.teamIds[0];
              teamBId = t.teamIds[1];
              _preselect();
              tossWinnerId = teamAId;
            }
            _showTossDetail = false;
          }),
        ),
      ),
    );
  }

  // ---------- Section 1: Match Format ----------

  Widget _formatSection() {
    return NumberedSection(
      number: 1,
      title: 'Match Format',
      subtitle: 'Select a format or set custom overs',
      child: Column(
        children: [
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 0.72,
            children: [
              for (final (name, o) in _formatPresets)
                OptionCard(
                  title: name,
                  subtitle: '($o Overs)',
                  selected: !_customOvers && overs == o,
                  onTap: () => setState(() {
                    overs = o;
                    _customOvers = false;
                  }),
                ),
              OptionCard(
                title: 'Custom',
                subtitle: '(Set Overs)',
                selected: _customOvers,
                onTap: () => setState(() => _customOvers = true),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _customOversPanel(),
        ],
      ),
    );
  }

  Widget _customOversPanel() {
    final enabled = _customOvers;
    return Opacity(
      opacity: enabled ? 1 : 0.75,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: kPanel2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kCyan.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.settings, color: kSilver, size: 22),
                const SizedBox(width: 8),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Custom Overs (Optional)',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: kWhite,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        'Set your own number of overs',
                        style: TextStyle(fontSize: 11, color: Colors.white54),
                      ),
                    ],
                  ),
                ),
                const Text(
                  'Enable Custom Overs',
                  style: TextStyle(fontSize: 11, color: kSilver),
                ),
                const SizedBox(width: 6),
                Switch(
                  value: enabled,
                  onChanged: (v) => setState(() {
                    _customOvers = v;
                    if (!v) overs = 8; // back to the Super Sixty default
                  }),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Text('Overs:', style: TextStyle(color: kSilver)),
                const SizedBox(width: 8),
                _stepperButton(
                  Icons.remove,
                  enabled && overs > 1
                      ? () => setState(() => overs--)
                      : null,
                ),
                Container(
                  width: 52,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: kPanel,
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: kCyan.withValues(alpha: 0.25)),
                  ),
                  child: Text(
                    '$overs',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: kWhite,
                      fontSize: 15,
                    ),
                  ),
                ),
                _stepperButton(
                  Icons.add,
                  enabled ? () => setState(() => overs++) : null,
                ),
                Container(
                  width: 1,
                  height: 34,
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  color: kCyan.withValues(alpha: 0.25),
                ),
                const Text('Balls per Over:', style: TextStyle(color: kSilver)),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: kPanel,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: kCyan.withValues(alpha: 0.25)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        isExpanded: true,
                        value: ballsPerOver,
                        items: [4, 5, 6, 8]
                            .map(
                              (o) => DropdownMenuItem(
                                value: o,
                                child: Text(
                                  o == 6 ? '6 (Standard)' : '$o',
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) =>
                            setState(() => ballsPerOver = v ?? 6),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepperButton(IconData icon, VoidCallback? onTap) {
    return Opacity(
      opacity: onTap == null ? 0.35 : 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: kPanel,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: kCyan.withValues(alpha: 0.35)),
          ),
          child: Icon(icon, color: kCyan, size: 18),
        ),
      ),
    );
  }

  // ---------- Section 2: Select Teams ----------

  Widget _teamsSection() {
    return NumberedSection(
      number: 2,
      title: 'Select Teams',
      headerAction: OutlinedButton.icon(
        icon: const Icon(Icons.add, size: 18),
        label: const Text('New Team'),
        style: OutlinedButton.styleFrom(
          foregroundColor: kCyan,
          side: BorderSide(color: kCyan.withValues(alpha: 0.5)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        onPressed: _newTeam,
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: _teamCard(true)),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  'VS',
                  style: TextStyle(
                    color: kRed,
                    fontWeight: FontWeight.w900,
                    fontStyle: FontStyle.italic,
                    fontSize: 22,
                  ),
                ),
              ),
              Expanded(child: _teamCard(false)),
            ],
          ),
          if (teamAId != null) ...[
            const SizedBox(height: 10),
            _xiPicker(teamAId!, xiA),
          ],
          if (teamBId != null) ...[
            const Divider(height: 20),
            _xiPicker(teamBId!, xiB),
          ],
        ],
      ),
    );
  }

  Widget _teamCard(bool isTeamA) {
    final teamId = isTeamA ? teamAId : teamBId;
    final team = teamId == null ? null : store.teamById(teamId);
    return InkWell(
      onTap: () => _pickTeam(isTeamA),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: kPanel2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kCyan.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: kCyan.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isTeamA ? 'Team 1' : 'Team 2',
                  style: const TextStyle(
                    color: kCyan,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TeamAvatar(team?.name ?? '?', radius: 30),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    team?.name ?? 'Select team',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: kWhite,
                      fontSize: 14,
                    ),
                  ),
                ),
                const Icon(
                  Icons.keyboard_arrow_down,
                  color: kSilver,
                  size: 20,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Team picker dialog. The selection handlers mirror the old Team A / Team B
  /// dropdown onChanged bodies exactly (same-team guard + toss handling).
  Future<void> _pickTeam(bool isTeamA) async {
    final teams = store.teams;
    final currentId = isTeamA ? teamAId : teamBId;
    final picked = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: Text(isTeamA ? 'Select Team 1' : 'Select Team 2'),
        children: [
          if (teams.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No teams yet — tap + New Team to add one.'),
            ),
          for (final t in teams)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, t.id),
              child: Row(
                children: [
                  TeamAvatar(t.name, radius: 16),
                  const SizedBox(width: 10),
                  Expanded(child: Text(t.name)),
                  if (t.id == currentId)
                    const Icon(Icons.check, color: kCyan, size: 18),
                ],
              ),
            ),
        ],
      ),
    );
    if (picked == null) return;
    setState(() {
      if (isTeamA) {
        teamAId = picked;
        if (teamBId == picked) teamBId = null;
        tossWinnerId = picked;
        _preselect();
      } else {
        teamBId = picked;
        // Keep the toss-winner value inside the dropdown items (null = Auto
        // is a legitimate state now, so only repair a stale non-null value).
        if (tossWinnerId != null &&
            tossWinnerId != teamAId &&
            tossWinnerId != teamBId) {
          tossWinnerId = teamAId;
        }
        _preselect();
      }
      _showTossDetail = false;
    });
  }

  /// '+ New Team' — the same new-team dialog as the Teams screen.
  Future<void> _newTeam() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('New team'),
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
    if (name == null || name.isEmpty) return;
    final team = Team(id: Store.newId('team'), name: name);
    await store.upsertTeam(team);
    setState(() {
      // Fill the first empty slot with the new team.
      if (teamAId == null) {
        teamAId = team.id;
        tossWinnerId = team.id;
        _preselect();
      } else if (teamBId == null) {
        teamBId = team.id;
        _preselect();
      }
    });
  }

  // ---------- Section 3: Venue ----------

  Widget _venueSection() {
    return NumberedSection(
      number: 3,
      title: 'Venue (Optional)',
      child: TextField(
        controller: venueCtrl,
        decoration: InputDecoration(
          hintText: 'e.g. 75 LOKRI CLUB',
          prefixIcon: const Icon(Icons.location_on, color: kSilver),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: venueCtrl,
            builder: (_, v, _) => v.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    icon: const Icon(Icons.clear, color: kSilver),
                    onPressed: venueCtrl.clear,
                  ),
          ),
          filled: true,
          fillColor: kPanel2,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: kCyan.withValues(alpha: 0.25)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: kCyan.withValues(alpha: 0.25)),
          ),
        ),
      ),
    );
  }

  // ---------- Section 4: Date & Time ----------

  Widget _dateTimeSection() {
    return NumberedSection(
      number: 4,
      title: 'Date & Time',
      child: Row(
        children: [
          Expanded(
            child: _pickerTile(
              icon: Icons.calendar_month,
              label: _fmtDate(date),
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
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _pickerTile(
              icon: Icons.access_time,
              label: _fmtTime(date),
              onTap: () async {
                final t = await showTimePicker(
                  context: context,
                  initialTime:
                      TimeOfDay(hour: date.hour, minute: date.minute),
                );
                if (t != null) {
                  setState(() {
                    date = DateTime(
                      date.year, date.month, date.day, t.hour, t.minute);
                  });
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _pickerTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: kPanel2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kCyan.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Icon(icon, color: kSilver, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: kWhite, fontSize: 14),
              ),
            ),
            const Icon(Icons.keyboard_arrow_down, color: kSilver, size: 20),
          ],
        ),
      ),
    );
  }

  // ---------- Section 5: Toss ----------

  /// Spins the toss coin: ~2.5s animation, then a random team wins.
  Future<void> _spinTossCoin() async {
    if (teamAId == null || teamBId == null || _tossSpinning) return;
    setState(() {
      _tossSpinning = true;
      _tossSpinTurns += 6; // several full rotations
    });
    await Future.delayed(const Duration(milliseconds: 2500));
    if (!mounted) return;
    final winner =
        (DateTime.now().microsecondsSinceEpoch % 2 == 0) ? teamAId : teamBId;
    setState(() {
      _tossSpinning = false;
      tossWinnerId = winner;
      _showTossDetail = true; // reveal "Chose to" Bat/Bowl picker
    });
  }

  Widget _tossSection() {
    final t1 = tossWinnerId == teamAId && tossWinnerId != null;
    final t2 = tossWinnerId == teamBId && tossWinnerId != null;
    return NumberedSection(
      number: 5,
      title: 'Toss',
      child: Column(
        children: [
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.7,
            children: [
              OptionCard(
                title: 'Auto (Toss later)',
                icon: Icons.check_circle,
                selected: tossWinnerId == null && !_showTossDetail,
                onTap: () => setState(() {
                  tossWinnerId = null;
                  _showTossDetail = false;
                }),
              ),
              OptionCard(
                title: 'Team 1',
                icon: Icons.shield,
                selected: t1 && !_showTossDetail,
                onTap: () {
                  if (teamAId == null) return;
                  setState(() {
                    tossWinnerId = teamAId;
                    _showTossDetail = false;
                  });
                },
              ),
              OptionCard(
                title: 'Team 2',
                icon: Icons.shield,
                selected: t2 && !_showTossDetail,
                onTap: () {
                  if (teamBId == null) return;
                  setState(() {
                    tossWinnerId = teamBId;
                    _showTossDetail = false;
                  });
                },
              ),
              OptionCard(
                title: 'Set Now',
                icon: Icons.tune,
                selected: _showTossDetail,
                onTap: () => setState(() {
                  _showTossDetail = true;
                  tossWinnerId ??= teamAId;
                }),
              ),
            ],
          ),
          // Coin toss simulator — tap to spin, random winner, then choose.
          const SizedBox(height: 10),
          Center(
            child: Column(
              children: [
                AnimatedRotation(
                  turns: _tossSpinTurns,
                  duration: const Duration(milliseconds: 2500),
                  curve: Curves.easeOut,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [kGold, Color(0xFFB8860B)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(color: Colors.white54, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: kGold.withValues(alpha: 0.4),
                          blurRadius: 12,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: _tossSpinning
                        ? const SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'TOSS',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                if (_tossSpinning)
                  const Text(
                    'Spinning...',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  )
                else if (tossWinnerId != null && !_showTossDetail)
                  Text(
                    '${store.teamName(tossWinnerId!)} won the toss!',
                    style: const TextStyle(
                      color: kGold,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                const SizedBox(height: 6),
                FilledButton.icon(
                  onPressed: (teamAId == null || teamBId == null || _tossSpinning)
                      ? null
                      : _spinTossCoin,
                  icon: const Icon(Icons.monetization_on_outlined),
                  label: Text(_tossSpinning ? 'Spinning...' : 'Toss Coin'),
                  style: FilledButton.styleFrom(
                    backgroundColor: kGold,
                    foregroundColor: Colors.black,
                  ),
                ),
                if (tossWinnerId != null && !_showTossDetail) ...[
                  const SizedBox(height: 10),
                  const Text(
                    'Choose:',
                    style: TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: OptionCard(
                          title: 'Bat',
                          icon: Icons.sports_cricket,
                          selected: tossDecision == 'bat',
                          onTap: () => setState(() {
                            tossDecision = 'bat';
                            _showTossDetail = true;
                          }),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OptionCard(
                          title: 'Bowl',
                          icon: Icons.sports_baseball,
                          selected: tossDecision == 'bowl',
                          onTap: () => setState(() {
                            tossDecision = 'bowl';
                            _showTossDetail = true;
                          }),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (_showTossDetail) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: tossWinnerId,
                    decoration: const InputDecoration(
                      labelText: 'Toss won by',
                    ),
                    items: [
                      if (teamAId != null)
                        DropdownMenuItem(
                          value: teamAId,
                          child: Text(store.teamName(teamAId!)),
                        ),
                      if (teamBId != null)
                        DropdownMenuItem(
                          value: teamBId,
                          child: Text(store.teamName(teamBId!)),
                        ),
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
                      DropdownMenuItem(
                          value: 'bowl', child: Text('Bowl first')),
                    ],
                    onChanged: (v) => setState(() => tossDecision = v ?? 'bat'),
                  ),
                ),
              ],
            ),
          ],
          if (tossWinnerId == null && !_showTossDetail)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                'Toss will be recorded later — pick Team 1 or Team 2 '
                '(or Set Now) before creating the match.',
                style: TextStyle(fontSize: 12, color: Colors.white54),
              ),
            ),
        ],
      ),
    );
  }

  // ---------- Section 6: Additional Settings ----------

  Widget _settingsSection() {
    return NumberedSection(
      number: 6,
      title: 'Additional Settings (Optional)',
      child: Column(
        children: [
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.7,
            children: [
              _settingCard(
                'Match Ball',
                DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: ballType,
                    items: const [
                      DropdownMenuItem(
                        value: 'Tennis Ball',
                        child: Text('Tennis Ball',
                            style: TextStyle(fontSize: 14)),
                      ),
                      DropdownMenuItem(
                        value: 'Leather Ball',
                        child: Text('Leather Ball',
                            style: TextStyle(fontSize: 14)),
                      ),
                      DropdownMenuItem(
                        value: 'Other',
                        child:
                            Text('Other', style: TextStyle(fontSize: 14)),
                      ),
                    ],
                    onChanged: (v) =>
                        setState(() => ballType = v ?? 'Tennis Ball'),
                  ),
                ),
              ),
              _settingCard(
                'Total Wickets',
                DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    isExpanded: true,
                    value: totalWickets,
                    items: const [
                      DropdownMenuItem(
                        value: 0,
                        child: Text('Auto (XI - 1)',
                            style: TextStyle(fontSize: 14)),
                      ),
                      DropdownMenuItem(
                        value: 10,
                        child: Text('10 wickets',
                            style: TextStyle(fontSize: 14)),
                      ),
                      DropdownMenuItem(
                        value: 9,
                        child:
                            Text('9 wickets', style: TextStyle(fontSize: 14)),
                      ),
                      DropdownMenuItem(
                        value: 8,
                        child:
                            Text('8 wickets', style: TextStyle(fontSize: 14)),
                      ),
                      DropdownMenuItem(
                        value: 11,
                        child: Text('11 wickets',
                            style: TextStyle(fontSize: 14)),
                      ),
                    ],
                    onChanged: (v) => setState(() => totalWickets = v ?? 0),
                  ),
                ),
              ),
              _settingCard(
                'Season / Year',
                TextField(
                  controller: seasonCtrl,
                  decoration: const InputDecoration(
                    hintText: 'e.g. 2025',
                    isDense: true,
                    border: InputBorder.none,
                  ),
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              _settingCard(
                'Match Title',
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(
                    hintText: 'e.g. Final',
                    isDense: true,
                    border: InputBorder.none,
                  ),
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _switchTile(
            'Last man stands',
            lastManStands,
            (v) => setState(() => lastManStands = v),
          ),
          _switchTile(
            'Wide ball penalty run',
            widePenalty,
            (v) => setState(() => widePenalty = v),
          ),
          _switchTile(
            'No ball penalty run',
            noBallPenalty,
            (v) => setState(() => noBallPenalty = v),
          ),
        ],
      ),
    );
  }

  Widget _settingCard(String label, Widget control) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: kPanel2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kCyan.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.white54),
          ),
          control,
        ],
      ),
    );
  }

  Widget _switchTile(String title, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      value: value,
      title: Text(title, style: const TextStyle(fontSize: 14)),
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      onChanged: onChanged,
    );
  }

  // ---------- Create / Add Fixture ----------

  /// Double-tap guard around the unchanged [_start] flow.
  Future<void> _create() async {
    if (_starting || !_canStart) return;
    setState(() => _starting = true);
    try {
      await _start();
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  bool _savingFixture = false; // double-tap guard on the Add Fixture button.

  /// v1.1.6: Add Fixture needs only two different teams — no squad,
  /// no Playing XI, no toss. Everything else is optional.
  bool get _canSaveFixture =>
      teamAId != null && teamBId != null && teamAId != teamBId;

  /// Save a scheduled fixture (status 'upcoming') WITHOUT starting a live
  /// match. Squad/Playing XI/toss are deferred until the user taps
  /// "Do Scoring" on the fixture later. Never duplicates: one new match
  /// record is inserted via the existing upsertMatch.
  Future<void> _saveFixture() async {
    if (_savingFixture || !_canSaveFixture) return;
    setState(() => _savingFixture = true);
    try {
      String p2(int v) => v.toString().padLeft(2, '0');
      final m = Match(
        id: Store.newId('match'),
        tournamentId: tournamentId,
        teamAId: teamAId!,
        teamBId: teamBId!,
        xiA: const [],
        xiB: const [],
        oversLimit: overs,
        ballsPerOver: ballsPerOver,
        venue: venueCtrl.text.trim(),
        // Local date + time as a plain string (never UTC), same format as
        // the seeded fixtures, so the schedule survives timezone shifts.
        dateIso:
            '${date.year}-${p2(date.month)}-${p2(date.day)}T${p2(date.hour)}:${p2(date.minute)}:00',
        matchTitle: titleCtrl.text.trim(),
        ballType: ballType,
        season: seasonCtrl.text.trim(),
        tossWinnerId: '',
        tossDecision: tossDecision,
        status: 'upcoming',
        totalWickets: totalWickets,
        lastManStands: lastManStands,
        widePenalty: widePenalty,
        noBallPenalty: noBallPenalty,
      );
      await store.upsertMatch(m);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fixture added successfully.')),
      );
      Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _savingFixture = false);
    }
  }

  Future<void> _start() async {
    final em = widget.existingMatch;
    if (em != null) {
      // Start setup for the existing fixture: update it in place so no
      // duplicate match is created.
      em.tournamentId = tournamentId;
      em.teamAId = teamAId!;
      em.teamBId = teamBId!;
      em.xiA = xiA.toList();
      em.xiB = xiB.toList();
      em.oversLimit = overs;
      em.ballsPerOver = ballsPerOver;
      em.venue = venueCtrl.text.trim();
      // Keep the fixture's local time; the setup screen picks a date only.
      // Stored as a plain local string (never UTC) so dates can't shift.
      final existingTime = em.dateIso.contains('T')
          ? em.dateIso.split('T')[1]
          : '14:00:00';
      String p2(int v) => v.toString().padLeft(2, '0');
      em.dateIso =
          '${date.year}-${p2(date.month)}-${p2(date.day)}T$existingTime';
      em.matchTitle = titleCtrl.text.trim();
      em.ballType = ballType;
      em.season = seasonCtrl.text.trim();
      em.tossWinnerId = tossWinnerId!;
      em.tossDecision = tossDecision;
      em.status = 'live';
      em.totalWickets = totalWickets;
      em.lastManStands = lastManStands;
      em.widePenalty = widePenalty;
      em.noBallPenalty = noBallPenalty;
      await store.upsertMatch(em);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ScoringScreen(store: store, match: em),
        ),
      );
      return;
    }
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
      matchTitle: titleCtrl.text.trim(),
      ballType: ballType,
      season: seasonCtrl.text.trim(),
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
      MaterialPageRoute(
        builder: (_) => ScoringScreen(store: store, match: m),
      ),
    );
  }
}
