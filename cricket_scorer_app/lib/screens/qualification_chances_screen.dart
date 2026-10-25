// Qualification chances screen (v1.4.5) — team-wise, for ALL teams.
//
// Read-only like the NRR calculator: it renders the pure computation in
// qualification_analysis.dart over the current league table + remaining
// league fixtures. Nothing here writes to the store — fixtures, matches
// and the table are never modified.
import 'package:flutter/material.dart';

import '../models.dart';
import '../qualification_analysis.dart';
import '../scoring.dart';
import '../store.dart';
import '../theme.dart';
import '../tournament_engine.dart';

/// Remaining league fixtures for the analysis: league stage only, not
/// terminal (completed / noResult / cancelled — the same terminal set
/// the playoff engine uses), both teams known and on the table.
List<QualFixtureInput> _remainingLeagueFixtures(
  Tournament t,
  List<Match> matches,
  Set<String> tableTeamIds,
) {
  const terminal = {'completed', 'noResult', 'cancelled'};
  final out = <QualFixtureInput>[];
  for (final m in matches) {
    if (m.tournamentId != t.id || m.stage != 'league') continue;
    if (terminal.contains(m.status)) continue;
    if (m.teamAId.isEmpty || m.teamBId.isEmpty) continue;
    if (!tableTeamIds.contains(m.teamAId)) continue;
    if (!tableTeamIds.contains(m.teamBId)) continue;
    out.add(QualFixtureInput(teamAId: m.teamAId, teamBId: m.teamBId));
  }
  return out;
}

String _ordinal(int rank) {
  if (rank == 1) return '1st';
  if (rank == 2) return '2nd';
  if (rank == 3) return '3rd';
  return '${rank}th';
}

String _pct(double p) => '${(p * 100).toStringAsFixed(1)}%';

class QualificationChancesScreen extends StatefulWidget {
  final Store store;
  const QualificationChancesScreen({super.key, required this.store});

  @override
  State<QualificationChancesScreen> createState() =>
      _QualificationChancesScreenState();
}

class _QualificationChancesScreenState
    extends State<QualificationChancesScreen> {
  Store get store => widget.store;

  String? _tournamentId;
  String? _selectedTeamId;
  final Map<int, QualOutcome> _fixed = {};

  QualificationAnalysis? _analysis;
  String? _analysisKey;
  QualificationAnalysis? _conditioned;
  String? _conditionedKey;

  @override
  void initState() {
    super.initState();
    if (store.tournaments.isNotEmpty) {
      _tournamentId = store.tournaments.first.id;
    }
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

  Tournament? get _tournament {
    for (final t in store.tournaments) {
      if (t.id == _tournamentId) return t;
    }
    return store.tournaments.isEmpty ? null : store.tournaments.first;
  }

  List<PointsRow> get _rows {
    final t = _tournament;
    if (t == null) return const [];
    return leaguePointsTable(t, store.matches);
  }

  List<QualFixtureInput> _remaining(List<PointsRow> rows) {
    final t = _tournament;
    if (t == null) return const [];
    return _remainingLeagueFixtures(
      t,
      store.matches,
      rows.map((r) => r.teamId).toSet(),
    );
  }

  /// Memoized recompute: the analysis only re-runs when its inputs
  /// change (tournament switch, team pick, what-if edit) — never on
  /// every build.
  void _ensureComputed(List<PointsRow> rows, List<QualFixtureInput> rem) {
    final inputs = [
      for (final r in rows) QualTeamInput(teamId: r.teamId, points: r.points, nrr: r.nrr),
    ];
    final key = _tournamentId ?? '';
    if (_analysisKey != key) {
      _analysis = analyzeQualification(teams: inputs, fixtures: rem);
      _analysisKey = key;
    }
    if (_selectedTeamId != null) {
      final cKey = '$key|$_selectedTeamId|${_fixed.entries.map((e) => '${e.key}:${e.value.index}').join(',')}';
      if (_conditionedKey != cKey) {
        _conditioned = analyzeQualification(
          teams: inputs,
          fixtures: rem,
          fixed: Map.of(_fixed),
        );
        _conditionedKey = cKey;
      }
    } else {
      _conditioned = null;
      _conditionedKey = null;
    }
  }

  void _pickTournament(String? id) {
    setState(() {
      _tournamentId = id;
      _selectedTeamId = null;
      _fixed.clear();
    });
  }

  String _minimumLine(TeamQualification q) {
    if (!q.canQualify) {
      return 'Kisi surat qualify nahi — sab jeet kar bhi nahi.';
    }
    if (q.minWins == 0 && q.minNoResults == 0 && !q.minNeedsOtherResults) {
      return 'Pehle se qualified — baqi natijon se farq nahi.';
    }
    final parts = <String>[];
    if (q.minWins! > 0) parts.add('${q.minWins} jeet');
    if (q.minNoResults! > 0) parts.add('${q.minNoResults} no-result');
    final need = q.minNeedsOtherResults
        ? ' + doosri teams ke natije bhi chahiye'
        : ' (doosre natijon se farq nahi)';
    return 'Kam se kam: ${parts.join(' + ')}$need';
  }

  @override
  Widget build(BuildContext context) {
    final t = _tournament;
    final rows = _rows;
    final rem = _remaining(rows);
    _ensureComputed(rows, rem);
    final analysis = _analysis;
    final sorted = analysis == null
        ? const <TeamQualification>[]
        : (List.of(analysis.teams)
          ..sort((a, b) {
            final pc = b.qualifyProbability.compareTo(a.qualifyProbability);
            if (pc != 0) return pc;
            return b.currentPoints.compareTo(a.currentPoints);
          }));

    return Scaffold(
      appBar: AppBar(title: const Text('Qualification Chances')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
        children: [
          const Text(
            'Har baqi league match ke 3 natije: jeet (2-0 points), haar '
            '(0-2), no-result (1-1 points, NRR par koi asar nahi). Tie bhi '
            '1-1 points hota hai, is liye no-result wahi points case '
            'cover karta hai — tie alag se nahi ginay gaye.',
            style: TextStyle(color: kSilver, fontSize: 12.5),
          ),
          const SizedBox(height: 6),
          const Text(
            'Tie par maujooda NRR se faisla — aane wale matches ke '
            'margins NRR badal sakte hain.',
            style: TextStyle(color: kGold, fontSize: 12.5),
          ),
          const SizedBox(height: 6),
          const Text(
            'Ye sirf hisaab hai — table ya matches tabdeel nahi hote.',
            style: TextStyle(color: kSilver, fontSize: 12.5),
          ),
          if (analysis != null && analysis.isApproximate) ...[
            const SizedBox(height: 6),
            const Text(
              'Approx (Monte Carlo, 10,000 samples) — baqi matches zyada '
              'hain, is liye exact ginna mumkin nahi.',
              style: TextStyle(color: kGold, fontSize: 12.5),
            ),
          ],
          const SectionHeader('Tournament'),
          DropdownButtonFormField<String>(
            initialValue: t?.id,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Tournament'),
            dropdownColor: kPanel2,
            items: [
              for (final tr in store.tournaments)
                DropdownMenuItem(
                  value: tr.id,
                  child: Text(
                    tr.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: _pickTournament,
          ),
          if (t == null)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Text(
                'Koi tournament nahi — pehle tournament banayen.',
                style: TextStyle(color: kSilver, fontSize: 13),
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                '${rem.length} baqi league matches • '
                '${analysis?.combinations ?? 0} combinations'
                '${analysis != null && analysis.isApproximate ? ' (approx)' : ''}',
                style: const TextStyle(color: kSilver, fontSize: 12.5),
              ),
            ),
            if (_selectedTeamId != null)
              _whatIfCard(rem, analysis),
            if (_selectedTeamId == null)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text(
                  'What-if ke liye kisi team par tap karen — us ke baqi '
                  'matches ke natije khud set kar ke dekhen.',
                  style: TextStyle(color: kSilver, fontSize: 12.5),
                ),
              ),
            const SectionHeader('All Teams'),
            for (final q in sorted) _teamCard(q),
          ],
        ],
      ),
    );
  }

  Widget _teamCard(TeamQualification q) {
    final selected = q.teamId == _selectedTeamId;
    return ScoreCard(
      highlight: selected,
      onTap: () => setState(() {
        _selectedTeamId = q.teamId;
        _fixed.clear();
      }),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  store.teamName(q.teamId),
                  style: const TextStyle(
                    color: kWhite,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              Text(
                _pct(q.qualifyProbability),
                style: TextStyle(
                  color: q.qualifyProbability >= 0.5 ? kGreen : kGold,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${q.currentPoints} pts • NRR ${q.currentNrr >= 0 ? '+' : ''}${q.currentNrr.toStringAsFixed(3)} • '
            '${q.remainingMatches} matches baqi',
            style: const TextStyle(color: kSilver, fontSize: 12.5),
          ),
          const SizedBox(height: 4),
          Text(
            'NRR sensitivity: ${_pct(q.nrrSensitivity)} scenarios mein '
            'cutoff par points tie thi',
            style: const TextStyle(color: kSilver, fontSize: 12.5),
          ),
          Text(
            'Best: ${_ordinal(q.bestRank)} • Worst: ${_ordinal(q.worstRank)}',
            style: const TextStyle(color: kSilver, fontSize: 12.5),
          ),
          Text(
            _minimumLine(q),
            style: const TextStyle(color: kSilver, fontSize: 12.5),
          ),
        ],
      ),
    );
  }

  Widget _whatIfCard(
    List<QualFixtureInput> rem,
    QualificationAnalysis? analysis,
  ) {
    final teamId = _selectedTeamId!;
    final row = _conditioned?.teams.firstWhere(
      (e) => e.teamId == teamId,
      orElse: () => analysis!.teams.firstWhere((e) => e.teamId == teamId),
    );
    final myFixtures = <int>[];
    for (var j = 0; j < rem.length; j++) {
      if (rem[j].teamAId == teamId || rem[j].teamBId == teamId) {
        myFixtures.add(j);
      }
    }
    return ScoreCard(
      highlight: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'What-if: ${store.teamName(teamId)}',
                  style: const TextStyle(
                    color: kWhite,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _selectedTeamId = null;
                  _fixed.clear();
                }),
                child: const Text('Close'),
              ),
            ],
          ),
          if (row != null) ...[
            Text(
              'Is surat mein qualify: ${_pct(row.qualifyProbability)} • '
              'Best: ${_ordinal(row.bestRank)} • '
              'Worst: ${_ordinal(row.worstRank)}',
              style: const TextStyle(color: kSilver, fontSize: 12.5),
            ),
            const SizedBox(height: 8),
          ],
          if (myFixtures.isEmpty)
            const Text(
              'Is team ka koi baqi match nahi — natija sirf doosri '
              'teams ke matches par munhasir hai.',
              style: TextStyle(color: kSilver, fontSize: 12.5),
            ),
          for (final j in myFixtures) _whatIfRow(j, rem, teamId),
          TextButton(
            onPressed: () => setState(_fixed.clear),
            child: const Text('Clear what-if'),
          ),
        ],
      ),
    );
  }

  /// Dropdown values are from the SELECTED TEAM's view ('Jeet' = the
  /// team wins); the analysis stores them from team A's view. These two
  /// helpers convert between the views (no-op when the team is A).
  static QualOutcome _toTeamAView(QualOutcome v, bool teamIsA) {
    if (teamIsA) return v;
    return switch (v) {
      QualOutcome.teamAWin => QualOutcome.teamBWin,
      QualOutcome.teamBWin => QualOutcome.teamAWin,
      QualOutcome.noResult => QualOutcome.noResult,
    };
  }

  static QualOutcome? _toTeamView(QualOutcome? stored, bool teamIsA) {
    if (stored == null) return null;
    return _toTeamAView(stored, teamIsA);
  }

  Widget _whatIfRow(int j, List<QualFixtureInput> rem, String teamId) {
    final teamIsA = rem[j].teamAId == teamId;
    final opponent = teamIsA ? rem[j].teamBId : rem[j].teamAId;
    return Row(
      children: [
        Expanded(
          child: Text(
            'vs ${store.teamName(opponent)}',
            style: const TextStyle(color: kWhite, fontSize: 13),
          ),
        ),
        DropdownButton<QualOutcome?>(
          value: _toTeamView(_fixed[j], teamIsA),
          dropdownColor: kPanel2,
          items: const [
            DropdownMenuItem<QualOutcome?>(
              value: null,
              child: Text('Any'),
            ),
            DropdownMenuItem(
              value: QualOutcome.teamAWin,
              child: Text('Jeet'),
            ),
            DropdownMenuItem(
              value: QualOutcome.teamBWin,
              child: Text('Haar'),
            ),
            DropdownMenuItem(
              value: QualOutcome.noResult,
              child: Text('No result'),
            ),
          ],
          onChanged: (v) => setState(() {
            if (v == null) {
              _fixed.remove(j);
            } else {
              _fixed[j] = _toTeamAView(v, teamIsA);
            }
          }),
        ),
      ],
    );
  }
}
