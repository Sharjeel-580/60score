// READ-ONLY view of a published tournament (v1.3.0).
// Opened from Search Tournaments by anyone — guests included. Shows the
// owner's published snapshot: fixtures & results, the points table
// (same engine as the owner's) and the team list. There are NO edit,
// delete or add controls anywhere in this file on purpose: viewers can
// look, never touch. The snapshot streams live, so scores update while
// the screen is open.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models.dart';
import '../publish_service.dart';
import '../scoring.dart';
import '../theme.dart';
import '../tournament_engine.dart';
import '../widgets/player_avatar.dart';
import '../widgets/stat_category_card.dart';
import 'fixture_detail_screen.dart';

/// Tournament logo from base64 (or the default trophy icon), shared by
/// the search list and this view. Remote data is decoded defensively.
class PublishedLogo extends StatelessWidget {
  final String logoBase64;
  final double size;
  const PublishedLogo({super.key, required this.logoBase64, this.size = 48});

  Uint8List? get _bytes {
    if (logoBase64.isEmpty) return null;
    try {
      return base64Decode(logoBase64);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: kPanel2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kCyan.withValues(alpha: 0.25)),
      ),
      child: bytes == null
          ? Icon(
              Icons.emoji_events_outlined,
              color: Colors.white54,
              size: size * 0.52,
            )
          : Image.memory(
              bytes,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Icon(
                Icons.emoji_events_outlined,
                color: Colors.white54,
                size: size * 0.52,
              ),
            ),
    );
  }
}

class PublishedTournamentScreen extends StatefulWidget {
  final String tournamentId;

  /// Snapshot already in hand (from the search list) for instant paint;
  /// the live stream replaces it as updates arrive.
  final PublishedTournament? initial;

  const PublishedTournamentScreen({
    super.key,
    required this.tournamentId,
    this.initial,
  });

  @override
  State<PublishedTournamentScreen> createState() =>
      _PublishedTournamentScreenState();
}

class _PublishedTournamentScreenState
    extends State<PublishedTournamentScreen> {
  List<String> _followIds = [];
  bool _following = false;

  @override
  void initState() {
    super.initState();
    _loadFollows();
  }

  Future<void> _loadFollows() async {
    final ids = await FollowStore.load();
    if (!mounted) return;
    setState(() {
      _followIds = ids;
      _following = ids.contains(widget.tournamentId);
    });
  }

  Future<void> _toggleFollow() async {
    final ids = [..._followIds];
    if (_following) {
      ids.remove(widget.tournamentId);
    } else if (!ids.contains(widget.tournamentId)) {
      ids.add(widget.tournamentId);
    }
    await FollowStore.save(ids);
    if (!mounted) return;
    setState(() {
      _followIds = ids;
      _following = ids.contains(widget.tournamentId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PublishedTournament?>(
      stream: PublishService().watchOne(widget.tournamentId),
      initialData: widget.initial,
      builder: (context, snap) {
        final pub = snap.data;
        return Scaffold(
          appBar: AppBar(
            title: Text(pub?.name ?? 'Tournament'),
            actions: [
              IconButton(
                icon: Icon(
                  _following ? Icons.bookmark : Icons.bookmark_border,
                  color: _following ? kGold : null,
                ),
                tooltip: _following
                    ? 'Following — tap to unfollow'
                    : 'Follow for live updates',
                onPressed: _toggleFollow,
              ),
            ],
          ),
          body: pub == null
              ? const EmptyState(
                  icon: Icons.cloud_off,
                  title: 'Not available',
                  subtitle:
                      'This tournament is no longer published, or you '
                      'are offline right now.',
                )
              : _body(pub),
        );
      },
    );
  }

  Widget _body(PublishedTournament pub) {
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          _header(pub),
          const TabBar(
            tabs: [
              Tab(text: 'Fixtures & Results'),
              Tab(text: 'Points Table'),
              Tab(text: 'Statistics'),
              Tab(text: 'Teams'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _fixturesTab(pub),
                _pointsTab(pub),
                _statsTab(pub),
                _teamsTab(pub),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(PublishedTournament pub) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PublishedLogo(logoBase64: pub.logoBase64, size: 64),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pub.name,
                  style: const TextStyle(
                    color: kWhite,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.place, color: kSilver, size: 13),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        pub.venue.isEmpty ? 'Venue TBD' : pub.venue,
                        style: const TextStyle(
                            color: kSilver, fontSize: 12.5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: kGreen.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: kGreen.withValues(alpha: 0.5)),
                      ),
                      child: const Text(
                        'PUBLISHED TOURNAMENT',
                        style: TextStyle(
                          color: kGreen,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'View only',
                      style:
                          TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------- Fixtures & results (read-only) ----------

  Widget _fixturesTab(PublishedTournament pub) {
    final league = pub.matches.where((m) => m.stage == 'league').toList()
      ..sort((a, b) => a.dateIso.compareTo(b.dateIso));
    final playoffs = playoffMatchesOf(pub.tournament.id, pub.matches);
    if (league.isEmpty && playoffs.isEmpty) {
      return const EmptyState(
        icon: Icons.event_note,
        title: 'No fixtures yet',
        subtitle: 'Fixtures appear here once the organizer adds them.',
      );
    }
    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        if (league.isNotEmpty) ...[
          const SectionHeader('League Fixtures'),
          for (final m in league) _matchCard(pub, m),
        ],
        if (playoffs.isNotEmpty) ...[
          const SectionHeader('Playoffs'),
          for (final m in playoffs) _matchCard(pub, m),
        ],
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _matchCard(PublishedTournament pub, Match m) {
    final title =
        m.matchTitle.isNotEmpty ? m.matchTitle : stageLabel(m.stage);
    final subtitle = m.resultText.isNotEmpty
        ? m.resultText
        : '${formatFixtureDate(m.dateIso)}'
            '${m.venue.isNotEmpty ? ' · ${m.venue}' : ''}';
    final canScorecard = m.status == 'completed' && m.innings.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ScoreCard(
        onTap: canScorecard
            ? () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        _PublishedScorecardScreen(pub: pub, match: m),
                  ),
                )
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: kCyan,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                StatusPill(m.status),
              ],
            ),
            const SizedBox(height: 10),
            _scoreLine(pub, m, m.teamAId),
            const SizedBox(height: 4),
            _scoreLine(pub, m, m.teamBId),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            if (canScorecard) ...[
              const SizedBox(height: 6),
              const Row(
                children: [
                  Icon(Icons.receipt_long,
                      size: 13, color: Colors.white38),
                  SizedBox(width: 5),
                  Text(
                    'Tap to view the full scorecard',
                    style:
                        TextStyle(color: Colors.white38, fontSize: 11.5),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _scoreLine(PublishedTournament pub, Match m, String teamId) {
    InningsState? inn;
    for (final i in m.innings) {
      if (i.battingTeamId == teamId) inn = i;
    }
    final score = inn == null
        ? ''
        : '${inn.totalRuns}/${inn.wickets} '
            '(${oversText(inn.legalBalls, inn.ballsPerOver)} ov)';
    return Row(
      children: [
        Expanded(
          child: Text(
            pub.teamName(teamId),
            style: const TextStyle(
              color: kWhite,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
        ),
        Text(
          score,
          style: const TextStyle(
            color: kSilver,
            fontWeight: FontWeight.w600,
            fontSize: 13.5,
          ),
        ),
      ],
    );
  }

  // ---------- Points table (read-only, same engine as the owner) --

  Widget _pointsTab(PublishedTournament pub) {
    final rows = leaguePointsTable(pub.tournament, pub.matches);
    if (rows.isEmpty) {
      return const EmptyState(
        icon: Icons.table_chart_outlined,
        title: 'No standings yet',
        subtitle: 'The points table appears once teams are set.',
      );
    }
    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 12,
            columns: const [
              DataColumn(label: Text('#')),
              DataColumn(label: Text('Team')),
              DataColumn(label: Text('P')),
              DataColumn(label: Text('W')),
              DataColumn(label: Text('L')),
              DataColumn(label: Text('T')),
              DataColumn(label: Text('NR')),
              DataColumn(label: Text('Pts')),
              DataColumn(label: Text('NRR')),
            ],
            rows: [
              for (var i = 0; i < rows.length; i++)
                DataRow(
                  cells: [
                    DataCell(Text('${i + 1}')),
                    DataCell(Text(pub.teamName(rows[i].teamId))),
                    DataCell(Text('${rows[i].played}')),
                    DataCell(Text('${rows[i].won}')),
                    DataCell(Text('${rows[i].lost}')),
                    DataCell(Text('${rows[i].tied}')),
                    DataCell(Text('${rows[i].noResult}')),
                    DataCell(
                      Text(
                        '${rows[i].points}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: kCyan,
                        ),
                      ),
                    ),
                    DataCell(Text(rows[i].nrr.toStringAsFixed(3))),
                  ],
                ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            'NRR uses the ICC rule: aggregate runs per over scored minus '
            'conceded across the tournament; a team bowled out is deemed '
            'to have faced its full overs quota.',
            style: TextStyle(fontSize: 11, color: Colors.white38),
          ),
        ),
      ],
    );
  }

  // ---------- Statistics (read-only, from the snapshot slice) ----

  Widget _statsTab(PublishedTournament pub) {
    final cats = _pubCategories(pub);
    if (cats.every((c) => c.rows.isEmpty)) {
      return const EmptyState(
        icon: Icons.bar_chart_outlined,
        title: 'No statistics yet',
        subtitle:
            'Top performers appear here once matches are completed.',
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.45,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: cats.length,
      itemBuilder: (c, i) {
        final cat = cats[i];
        final leaderId = cat.rows.isEmpty ? '' : cat.rows.first.playerId;
        return StatCategoryCard(
          icon: cat.icon,
          accent: cat.accent,
          label: cat.label,
          hasData: cat.rows.isNotEmpty,
          value: cat.value,
          playerName:
              leaderId.isEmpty ? '' : _slicePlayerName(pub, leaderId),
          teamName: leaderId.isEmpty ? '' : _sliceTeamOf(pub, leaderId),
          detail: cat.detail,
          photoBase64:
              leaderId.isEmpty ? '' : _slicePlayerPhoto(pub, leaderId),
          role: leaderId.isEmpty
              ? 'Batter'
              : _slicePlayerRole(pub, leaderId),
          onTap: cat.rows.isEmpty
              ? null
              : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => _PublishedLeaderboardScreen(
                        pub: pub,
                        category: cat,
                      ),
                    ),
                  ),
        );
      },
    );
  }

  /// Top-performer categories computed from the SNAPSHOT's own matches
  /// with the same career engine the owner app uses — no Store, no
  /// local data involved.
  List<_PubCategory> _pubCategories(PublishedTournament pub) {
    final career =
        computeCareerStats(pub.matches, tournamentId: pub.tournament.id);
    final list = career.values.toList();

    List<_PubRow> rowsOf(
      List<CareerStats> sorted,
      String Function(CareerStats c) primary,
      String Function(CareerStats c) secondary,
      bool Function(CareerStats c) include,
    ) => sorted
        .where(include)
        .take(5)
        .map((c) => _PubRow(c.playerId, primary(c), secondary(c)))
        .toList();

    final byRuns = [...list]..sort((a, b) => b.runs.compareTo(a.runs));
    final byWkts = [...list]
      ..sort((a, b) => b.wickets.compareTo(a.wickets));
    final byHS = [...list]
      ..sort((a, b) => b.highScore.compareTo(a.highScore));
    final bySixes = [...list]
      ..sort((a, b) => b.sixes.compareTo(a.sixes));
    final byFours = [...list]
      ..sort((a, b) => b.fours.compareTo(a.fours));

    return [
      _PubCategory(
        label: 'Most Runs',
        icon: Icons.sports_cricket,
        accent: kGold,
        value: byRuns.isNotEmpty && byRuns.first.runs > 0
            ? '${byRuns.first.runs}'
            : '0',
        detail: byRuns.isNotEmpty && byRuns.first.runs > 0
            ? 'Avg ${byRuns.first.battingAverage.toStringAsFixed(1)} • SR ${byRuns.first.battingSR.toStringAsFixed(0)}'
            : '',
        rows: rowsOf(
          byRuns,
          (c) => '${c.runs} runs',
          (c) =>
              'Avg ${c.battingAverage.toStringAsFixed(1)} • SR ${c.battingSR.toStringAsFixed(0)}',
          (c) => c.runs > 0,
        ),
      ),
      _PubCategory(
        label: 'Most Wickets',
        icon: Icons.sports_baseball,
        accent: kCyan,
        value: byWkts.isNotEmpty && byWkts.first.wickets > 0
            ? '${byWkts.first.wickets}'
            : '0',
        detail: byWkts.isNotEmpty && byWkts.first.wickets > 0
            ? 'Econ ${byWkts.first.economy.toStringAsFixed(2)} • Best ${byWkts.first.bestFigures}'
            : '',
        rows: rowsOf(
          byWkts,
          (c) => '${c.wickets} wkts',
          (c) =>
              'Econ ${c.economy.toStringAsFixed(2)} • Best ${c.bestFigures}',
          (c) => c.wickets > 0,
        ),
      ),
      _PubCategory(
        label: 'Highest Score',
        icon: Icons.emoji_events,
        accent: kGold,
        value: byHS.isNotEmpty && byHS.first.highScore > 0
            ? '${byHS.first.highScore}'
            : '0',
        detail: '',
        rows: rowsOf(
          byHS,
          (c) => '${c.highScore}',
          (c) => '${c.runs} runs • SR ${c.battingSR.toStringAsFixed(0)}',
          (c) => c.highScore > 0,
        ),
      ),
      _PubCategory(
        label: 'Most Sixes',
        icon: Icons.looks_6,
        accent: kGold,
        value: bySixes.isNotEmpty && bySixes.first.sixes > 0
            ? '${bySixes.first.sixes}'
            : '0',
        detail: '',
        rows: rowsOf(
          bySixes,
          (c) => '${c.sixes} sixes',
          (c) => '${c.runs} runs',
          (c) => c.sixes > 0,
        ),
      ),
      _PubCategory(
        label: 'Most Fours',
        icon: Icons.looks_4,
        accent: kGold,
        value: byFours.isNotEmpty && byFours.first.fours > 0
            ? '${byFours.first.fours}'
            : '0',
        detail: '',
        rows: rowsOf(
          byFours,
          (c) => '${c.fours} fours',
          (c) => '${c.runs} runs',
          (c) => c.fours > 0,
        ),
      ),
    ];
  }

  // ---------- Teams (read-only) ----------

  Widget _teamsTab(PublishedTournament pub) {
    if (pub.teams.isEmpty) {
      return const EmptyState(
        icon: Icons.groups_outlined,
        title: 'No teams yet',
        subtitle: 'Teams appear here once the organizer adds them.',
      );
    }
    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        for (final team in pub.teams)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ScoreCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.groups, color: kCyan, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          team.name,
                          style: const TextStyle(
                            color: kWhite,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      Text(
                        '${team.players.length} players',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                  if (team.players.isNotEmpty) ...[
                    const Divider(height: 20),
                    for (final p in team.players)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 34,
                              child: Text(
                                p.jerseyNo > 0 ? '#${p.jerseyNo}' : '—',
                                style: const TextStyle(
                                    color: Colors.white38, fontSize: 12),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                p.isCaptain ? '${p.name} (C)' : p.name,
                                style:
                                    const TextStyle(color: kSilver),
                              ),
                            ),
                            Text(
                              p.role,
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
      ],
    );
  }
}

// ---------- Snapshot slice lookups (viewer-side, no Store) ----------

String _slicePlayerName(PublishedTournament pub, String id) {
  for (final t in pub.teams) {
    final p = t.playerById(id);
    if (p != null) return p.name;
  }
  for (final r in pub.slice.regPlayers) {
    if (r.id == id) return r.name;
  }
  return 'Player';
}

String _slicePlayerPhoto(PublishedTournament pub, String id) {
  for (final r in pub.slice.regPlayers) {
    if (r.id == id && r.photoBase64.isNotEmpty) return r.photoBase64;
  }
  for (final t in pub.teams) {
    final p = t.playerById(id);
    if (p != null && p.photoBase64.isNotEmpty) return p.photoBase64;
  }
  return '';
}

String _slicePlayerRole(PublishedTournament pub, String id) {
  for (final t in pub.teams) {
    final p = t.playerById(id);
    if (p != null) return p.role;
  }
  for (final r in pub.slice.regPlayers) {
    if (r.id == id) return r.role;
  }
  return 'Batter';
}

String _sliceTeamOf(PublishedTournament pub, String id) {
  for (final t in pub.teams) {
    if (t.players.any((p) => p.id == id)) return t.name;
  }
  return '';
}

class _PubRow {
  final String playerId;
  final String primary;
  final String secondary;
  const _PubRow(this.playerId, this.primary, this.secondary);
}

class _PubCategory {
  final String label;
  final IconData icon;
  final Color accent;
  final String value;
  final String detail;
  final List<_PubRow> rows;
  const _PubCategory({
    required this.label,
    required this.icon,
    required this.accent,
    required this.value,
    required this.detail,
    required this.rows,
  });
}

/// Read-only top-5 leaderboard for one published category.
class _PublishedLeaderboardScreen extends StatelessWidget {
  final PublishedTournament pub;
  final _PubCategory category;
  const _PublishedLeaderboardScreen({
    required this.pub,
    required this.category,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${pub.name} - ${category.label}')),
      body: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: category.rows.length,
        separatorBuilder: (_, _) => const Divider(height: 8),
        itemBuilder: (c, i) {
          final r = category.rows[i];
          final team = _sliceTeamOf(pub, r.playerId);
          final photo = _slicePlayerPhoto(pub, r.playerId);
          return ListTile(
            dense: true,
            leading: PlayerAvatar(
              photoBase64: photo.isEmpty ? null : photo,
              role: _slicePlayerRole(pub, r.playerId),
              name: _slicePlayerName(pub, r.playerId),
              radius: 18,
            ),
            title: Text('${i + 1}. ${_slicePlayerName(pub, r.playerId)}'),
            subtitle: Text(
              '${r.secondary}${team.isNotEmpty ? '  •  $team' : ''}',
            ),
            trailing: Text(
              r.primary,
              style: const TextStyle(
                color: kCyan,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// READ-ONLY scorecard for one completed fixture, rendered purely from
/// the snapshot match's stored innings state. No scoring, editing,
/// adding or deleting exists here — display only.
class _PublishedScorecardScreen extends StatelessWidget {
  final PublishedTournament pub;
  final Match match;
  const _PublishedScorecardScreen({required this.pub, required this.match});

  String _name(String id) => _slicePlayerName(pub, id);

  @override
  Widget build(BuildContext context) {
    final title =
        match.matchTitle.isNotEmpty ? match.matchTitle : 'Scorecard';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: match.innings.isEmpty
          ? const EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No scorecard yet',
              subtitle: 'This match has no recorded innings.',
            )
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                ScoreCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${pub.teamName(match.teamAId)} vs '
                        '${pub.teamName(match.teamBId)}',
                        style: const TextStyle(
                          color: kWhite,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (match.resultText.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          match.resultText,
                          style: const TextStyle(
                            color: kGold,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                      if (match.manOfMatchId.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Player of the Match: '
                          '${_name(match.manOfMatchId)}',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12.5),
                        ),
                      ],
                    ],
                  ),
                ),
                for (var i = 0; i < match.innings.length; i++) ...[
                  const SizedBox(height: 14),
                  _inningsCard(match.innings[i], i + 1),
                ],
                const SizedBox(height: 12),
              ],
            ),
    );
  }

  Widget _inningsCard(InningsState inn, int number) {
    final batted = inn.battingXI
        .where((pid) => inn.batting[pid]?.batted ?? false)
        .toList();
    final dnb = inn.battingXI
        .where((pid) => !(inn.batting[pid]?.batted ?? false))
        .map(_name)
        .toList();
    final bowlers = inn.bowling.keys.where((pid) {
      final f = inn.bowling[pid]!;
      return f.legalBalls > 0 || f.wides > 0 || f.noBalls > 0;
    }).toList();
    return ScoreCard(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${pub.teamName(inn.battingTeamId)} — Innings $number',
                    style: const TextStyle(
                      color: kWhite,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '${inn.totalRuns}/${inn.wickets} '
                  '(${oversText(inn.legalBalls, inn.ballsPerOver)} ov)',
                  style: const TextStyle(
                    color: kCyan,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 18),
          _tableHeader(
              const ['Batter', 'R', 'B', '4s', '6s', 'SR'],
              const [5, 2, 2, 2, 2, 3]),
          for (final pid in batted) _battingRow(inn, pid),
          if (dnb.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 2),
              child: Text(
                'Did not bat: ${dnb.join(', ')}',
                style: const TextStyle(
                    color: Colors.white54, fontSize: 12),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 2),
            child: Text(
              'Extras: ${inn.extrasTotal} (wd ${inn.widesRuns}, '
              'nb ${inn.noBallRuns}, b ${inn.byeRuns}, '
              'lb ${inn.legByeRuns})',
              style: const TextStyle(
                  color: Colors.white70, fontSize: 12),
            ),
          ),
          if (inn.fallOfWickets.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 2),
              child: Text(
                'Fall of wickets: ${inn.fallOfWickets.map((f) => '${f.wicketNo}-${f.runs} (${_name(f.playerId)}, ${f.overText} ov)').join(', ')}',
                style: const TextStyle(
                    color: Colors.white54, fontSize: 12),
              ),
            ),
          const Divider(height: 18),
          _tableHeader(
              const ['Bowler', 'O', 'M', 'R', 'W', 'Econ'],
              const [5, 2, 2, 2, 2, 3]),
          for (final pid in bowlers) _bowlingRow(inn, pid),
        ],
      ),
    );
  }

  Widget _tableHeader(List<String> labels, List<int> flexes) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              flex: flexes[i],
              child: Text(
                labels[i],
                textAlign: i == 0 ? TextAlign.left : TextAlign.right,
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _battingRow(InningsState inn, String pid) {
    final f = inn.batting[pid]!;
    final sr =
        f.balls == 0 ? '-' : (f.runs * 100 / f.balls).toStringAsFixed(1);
    final figures = ['${f.runs}', '${f.balls}', '${f.fours}', '${f.sixes}', sr];
    const flexes = [2, 2, 2, 2, 3];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _name(pid),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                Text(
                  f.out ? resolveHowOut(f.howOut, _name) : 'not out',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: f.out ? Colors.white38 : kCyan,
                  ),
                ),
              ],
            ),
          ),
          for (var i = 0; i < figures.length; i++)
            Expanded(
              flex: flexes[i],
              child: Text(
                figures[i],
                textAlign: TextAlign.right,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }

  Widget _bowlingRow(InningsState inn, String pid) {
    final f = inn.bowling[pid]!;
    final econ = f.legalBalls == 0
        ? '-'
        : (f.runs * inn.ballsPerOver / f.legalBalls).toStringAsFixed(2);
    final figures = [
      oversText(f.legalBalls, inn.ballsPerOver),
      '${f.maidens}',
      '${f.runs}',
      '${f.wickets}',
      econ,
    ];
    const flexes = [2, 2, 2, 2, 3];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Text(
              _name(pid),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          for (var i = 0; i < figures.length; i++)
            Expanded(
              flex: flexes[i],
              child: Text(
                figures[i],
                textAlign: TextAlign.right,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }
}
