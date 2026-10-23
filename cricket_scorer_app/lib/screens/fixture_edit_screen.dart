// Fixture editor (v1.3.7).
//
// An existing UPCOMING fixture is fully editable after creation —
// date, time, venue, teams, overs, balls per over, ball type,
// title, stage (round) and season — from the Fixture Detail
// screen's "Edit fixture" button. Before this, the button was a
// stub and the only remedy was cancel-and-recreate, which lost
// the fixture's identity (and its place in a tournament).
//
// Guard rails: the editor is only offered while the match is
// 'upcoming', so there is no scoring data to corrupt — live
// matches keep the live Playing XI editor and completed matches
// keep the scorecard editor. Changing a team clears that side's
// saved Playing XI and any toss recorded against a replaced team
// (see applyFixtureEdit), so the fixture simply goes through the
// normal "Do Scoring" setup checks afterwards. Saving persists
// through the store like every other mutation (and syncs).
import 'package:flutter/material.dart';

import '../scoring.dart';
import '../store.dart';
import '../theme.dart';
import 'fixture_detail_screen.dart' show stageLabel;

class FixtureEditScreen extends StatefulWidget {
  final Store store;
  final String matchId;
  const FixtureEditScreen({
    super.key,
    required this.store,
    required this.matchId,
  });

  @override
  State<FixtureEditScreen> createState() => _FixtureEditScreenState();
}

class _FixtureEditScreenState extends State<FixtureEditScreen> {
  Store get store => widget.store;

  static const _presetOvers = {5, 8, 10, 20, 30, 40, 50};
  static const _stages = ['league', 'semifinal1', 'semifinal2', 'final'];

  late String _teamAId;
  late String _teamBId;
  late DateTime _date;
  late TimeOfDay _time;
  late int _overs;
  late bool _customOvers;
  late int _ballsPerOver;
  late String _stage;
  late String _ballType;

  final _venueCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _seasonCtrl = TextEditingController();
  final _customOversCtrl = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final m = store.matchById(widget.matchId);
    _teamAId = m?.teamAId ?? '';
    _teamBId = m?.teamBId ?? '';
    _overs = m?.oversLimit ?? 8;
    _customOvers = !_presetOvers.contains(_overs);
    if (_customOvers) _customOversCtrl.text = '$_overs';
    _ballsPerOver = m?.ballsPerOver ?? 6;
    if (![4, 5, 6, 8].contains(_ballsPerOver)) _ballsPerOver = 6;
    _stage = _stages.contains(m?.stage) ? m!.stage : 'league';
    _ballType = m?.ballType ?? 'Tennis Ball';
    if (!['Tennis Ball', 'Leather Ball', 'Other'].contains(_ballType)) {
      _ballType = 'Tennis Ball';
    }
    _venueCtrl.text = m?.venue ?? '';
    _titleCtrl.text = m?.matchTitle ?? '';
    _seasonCtrl.text = m?.season ?? '';
    // Stored format: "2026-11-06T15:00:00" or a plain "2026-11-06".
    final iso = m?.dateIso ?? '';
    var date = DateTime.now();
    var time = const TimeOfDay(hour: 14, minute: 0);
    final parsed = DateTime.tryParse(iso);
    if (parsed != null) date = parsed;
    if (iso.contains('T')) {
      final tp = iso.split('T')[1].split(':');
      final h = tp.isNotEmpty ? int.tryParse(tp[0]) : null;
      final min = tp.length > 1 ? int.tryParse(tp[1]) : null;
      if (h != null && min != null) time = TimeOfDay(hour: h, minute: min);
    }
    _date = date;
    _time = time;
  }

  @override
  void dispose() {
    _venueCtrl.dispose();
    _titleCtrl.dispose();
    _seasonCtrl.dispose();
    _customOversCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String get _dateLabel {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${_date.day.toString().padLeft(2, '0')} '
        '${months[_date.month - 1]} ${_date.year}';
  }

  Future<void> _save() async {
    if (_saving) return;
    final m = store.matchById(widget.matchId);
    if (m == null) {
      Navigator.pop(context);
      return;
    }
    if (_teamAId.isNotEmpty && _teamAId == _teamBId) {
      _snack('Both teams cannot be the same.');
      return;
    }
    final overs = _customOvers
        ? (int.tryParse(_customOversCtrl.text.trim()) ?? 0)
        : _overs;
    if (overs <= 0) {
      _snack('Enter a valid number of overs.');
      return;
    }
    setState(() => _saving = true);
    try {
      String p2(int v) => v.toString().padLeft(2, '0');
      applyFixtureEdit(
        m,
        teamAId: _teamAId,
        teamBId: _teamBId,
        // Local date + time as a plain string (never UTC) — the
        // same dateIso format the rest of the app stores.
        dateIso: '${_date.year}-${p2(_date.month)}-${p2(_date.day)}'
            'T${p2(_time.hour)}:${p2(_time.minute)}:00',
        venue: _venueCtrl.text.trim(),
        oversLimit: overs,
        ballsPerOver: _ballsPerOver,
        matchTitle: _titleCtrl.text.trim(),
        stage: _stage,
        ballType: _ballType,
        season: _seasonCtrl.text.trim(),
      );
      await store.upsertMatch(m);
      if (!mounted) return;
      _snack('Fixture updated.');
      Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _section(String title, List<Widget> children) {
    return ScoreCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: kWhite,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _teamDropdown({
    required String label,
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    // Items: a TBD slot ('') plus every team. A stored id whose
    // team was deleted stays selectable so the dropdown never
    // asserts; it shows through the store's name lookup.
    final ids = <String>{'', value};
    for (final t in store.teams) {
      ids.add(t.id);
    }
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: ids
          .map(
            (id) => DropdownMenuItem(
              value: id,
              child: Text(
                id.isEmpty ? 'TBD' : store.teamName(id),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = store.matchById(widget.matchId);
    if (m == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit Fixture')),
        body: const Center(
          child: EmptyState(
            icon: Icons.event_busy,
            title: 'Fixture not found',
            subtitle: 'This fixture may have been deleted.',
          ),
        ),
      );
    }
    final teamsChanged = _teamAId != m.teamAId || _teamBId != m.teamBId;
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Fixture')),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          _section('Teams', [
            _teamDropdown(
              label: 'Team 1',
              value: _teamAId,
              onChanged: (v) => setState(() => _teamAId = v),
            ),
            const SizedBox(height: 10),
            _teamDropdown(
              label: 'Team 2',
              value: _teamBId,
              onChanged: (v) => setState(() => _teamBId = v),
            ),
            if (teamsChanged) ...[
              const SizedBox(height: 10),
              const Text(
                'Changing a team clears that side\'s saved Playing XI '
                'and any toss recorded against it — both are set again '
                'when scoring starts.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ]),
          const SizedBox(height: 12),
          _section('Schedule', [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_month, color: kCyan),
              title: const Text('Match date'),
              subtitle: Text(_dateLabel),
              trailing: const Icon(Icons.chevron_right, color: Colors.white38),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                if (d != null && mounted) setState(() => _date = d);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.access_time, color: kTeal),
              title: const Text('Match time'),
              subtitle: Text(_time.format(context)),
              trailing: const Icon(Icons.chevron_right, color: Colors.white38),
              onTap: () async {
                final t = await showTimePicker(
                  context: context,
                  initialTime: _time,
                );
                if (t != null && mounted) setState(() => _time = t);
              },
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _venueCtrl,
              decoration: const InputDecoration(
                labelText: 'Venue',
                hintText: 'e.g. 75 LOKRI CLUB',
              ),
            ),
          ]),
          const SizedBox(height: 12),
          _section('Format', [
            DropdownButtonFormField<int>(
              initialValue: _customOvers ? -1 : _overs,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Overs'),
              items: [
                ..._presetOvers.map(
                  (o) => DropdownMenuItem(value: o, child: Text('$o overs')),
                ),
                const DropdownMenuItem(value: -1, child: Text('Custom')),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() {
                  _customOvers = v == -1;
                  if (!_customOvers) _overs = v;
                });
              },
            ),
            if (_customOvers) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _customOversCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Custom overs',
                ),
              ),
            ],
            const SizedBox(height: 10),
            DropdownButtonFormField<int>(
              initialValue: _ballsPerOver,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Balls per over'),
              items: [4, 5, 6, 8]
                  .map(
                    (o) => DropdownMenuItem(
                      value: o,
                      child: Text(o == 6 ? '6 (Standard)' : '$o'),
                    ),
                  )
                  .toList(),
              onChanged: (v) =>
                  setState(() => _ballsPerOver = v ?? _ballsPerOver),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _ballType,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Match ball'),
              items: const [
                DropdownMenuItem(
                  value: 'Tennis Ball',
                  child: Text('Tennis Ball'),
                ),
                DropdownMenuItem(
                  value: 'Leather Ball',
                  child: Text('Leather Ball'),
                ),
                DropdownMenuItem(value: 'Other', child: Text('Other')),
              ],
              onChanged: (v) =>
                  setState(() => _ballType = v ?? _ballType),
            ),
          ]),
          const SizedBox(height: 12),
          _section('Details', [
            DropdownButtonFormField<String>(
              initialValue: _stage,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Round / stage'),
              items: _stages
                  .map(
                    (s) => DropdownMenuItem(
                      value: s,
                      child: Text(stageLabel(s)),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _stage = v ?? _stage),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: 'Match title (optional)',
                hintText: 'e.g. Final',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _seasonCtrl,
              decoration: const InputDecoration(
                labelText: 'Season / year (optional)',
                hintText: 'e.g. 2025',
              ),
            ),
          ]),
          const SizedBox(height: 20),
          ScoreButton(
            label: 'Save changes',
            icon: Icons.save_outlined,
            onPressed: _saving ? null : _save,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
