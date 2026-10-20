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
import '../theme.dart';
import '../tournament_engine.dart';
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
      length: 3,
      child: Column(
        children: [
          _header(pub),
          const TabBar(
            tabs: [
              Tab(text: 'Fixtures & Results'),
              Tab(text: 'Points Table'),
              Tab(text: 'Teams'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _fixturesTab(pub),
                _pointsTab(pub),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ScoreCard(
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
