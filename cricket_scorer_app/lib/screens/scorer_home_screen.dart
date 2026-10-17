import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../tournament_engine.dart';
import 'fixture_detail_screen.dart';
import 'match_setup_screen.dart';
import 'scorecard_screen.dart';
import 'scoring_screen.dart';
import 'stats_screen.dart';
import 'teams_screen.dart';
import 'tournament_stats.dart';

// 60Score v4 home: blue/red fire theme matching the AI mockup.
// Header logo + hero banner are cropped from the approved artwork.
class ScorerHomeScreen extends StatelessWidget {
  final Store store;
  const ScorerHomeScreen({super.key, required this.store});

  static const _bg = Color(0xFF05080D);
  static const _blue = Color(0xFF29B6F6);
  static const _cyan = Color(0xFF00E5FF);
  static const _red = Color(0xFFFF3D2E);

  @override
  Widget build(BuildContext context) {
    final live = store.matches.where((m) => m.status == 'live').toList();
    final done = store.matches.where((m) => m.status != 'live').toList();
    final tournamentsKey = GlobalKey();
    final liveKey = GlobalKey();

    void scrollTo(GlobalKey key) {
      final ctx = key.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx,
            duration: const Duration(milliseconds: 400));
      }
    }

    return Scaffold(
      backgroundColor: _bg,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => MatchSetupScreen(store: store)),
        ),
        backgroundColor: _red,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.sports_cricket),
        label: const Text('New match'),
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          _header(context),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: _heroBanner(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: _actionGrid(context,
                onTournaments: () => scrollTo(tournamentsKey),
                onLive: () => scrollTo(liveKey)),
          ),
          const SizedBox(height: 18),
          _sectionHeader(
            key: tournamentsKey,
            context,
            icon: Icons.emoji_events,
            iconColor: const Color(0xFFFFB300),
            title: 'Upcoming Tournaments',
            onViewAll: () => scrollTo(tournamentsKey),
          ),
          if (store.tournaments.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Text('No tournaments yet.',
                  style: TextStyle(color: Colors.white54)),
            ),
          for (final t in store.tournaments)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              child: _tournamentCard(context, t),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 4),
              child: TextButton.icon(
                onPressed: () => _createTournament(context),
                icon: const Icon(Icons.add, color: _cyan),
                label:
                    const Text('Create tournament', style: TextStyle(color: _cyan)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _sectionHeader(
            key: liveKey,
            context,
            icon: Icons.play_circle,
            iconColor: _cyan,
            title: 'Live Matches',
            badge: live.isNotEmpty ? '${live.length}' : null,
            onViewAll: () => scrollTo(liveKey),
          ),
          if (live.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Text(
                  'No live matches right now.', style: TextStyle(color: Colors.white54)),
            ),
          for (final m in live)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              child: _liveMatchCard(context, m),
            ),
          const SizedBox(height: 8),
          _sectionHeader(
            context,
            icon: Icons.check_circle,
            iconColor: Colors.white54,
            title: 'Recent Results',
          ),
          if (done.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Text('No completed matches yet.',
                  style: TextStyle(color: Colors.white54)),
            ),
          for (final m in done)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: _matchTile(context, m),
            ),
          const SizedBox(height: 90),
        ],
      ),
    );
  }

  /// Top bar: 60Score logo artwork + circular Teams button (like the mockup).
  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 52, 12, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Image.asset(
              'assets/home_header_logo.png',
              fit: BoxFit.contain,
              alignment: Alignment.centerLeft,
            ),
          ),
          const SizedBox(width: 8),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: _blue.withValues(alpha: 0.7), width: 1.5),
                  color: _blue.withValues(alpha: 0.12),
                ),
                child: IconButton(
                  icon: const Icon(Icons.groups, color: _cyan),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => TeamsScreen(store: store)),
                  ),
                ),
              ),
              const SizedBox(height: 2),
              const Text('Teams',
                  style: TextStyle(color: Colors.white70, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }

  /// Hero banner artwork + carousel dots (decorative, like the mockup).
  Widget _heroBanner() {
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Image.asset('assets/hero_banner.png', fit: BoxFit.cover),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                    shape: BoxShape.circle, color: _cyan)),
            const SizedBox(width: 6),
            Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.25))),
            const SizedBox(width: 6),
            Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.25))),
          ],
        ),
      ],
    );
  }

  /// 2x2 action cards: Tournaments / Live Matches / Teams / Stats.
  Widget _actionGrid(BuildContext context,
      {required VoidCallback onTournaments, required VoidCallback onLive}) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.55,
      children: [
        _actionCard(
          title: 'Tournaments',
          subtitle: 'Create & Manage',
          icon: Icons.emoji_events,
          gradient: const [Color(0xFFB26A00), Color(0xFF5C2E00)],
          border: const Color(0xFFFFB300),
          onTap: onTournaments,
        ),
        _actionCard(
          title: 'Live Matches',
          subtitle: 'Ball by Ball Scores',
          icon: Icons.play_circle,
          gradient: const [Color(0xFFC62828), Color(0xFF4A0E0E)],
          border: _red,
          badge: 'LIVE',
          onTap: onLive,
        ),
        _actionCard(
          title: 'Teams',
          subtitle: 'Manage Teams',
          icon: Icons.groups,
          gradient: const [Color(0xFF0277BD), Color(0xFF0A2A4A)],
          border: _blue,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => TeamsScreen(store: store)),
          ),
        ),
        _actionCard(
          title: 'Stats',
          subtitle: 'Players & Records',
          icon: Icons.bar_chart,
          gradient: const [Color(0xFF6A1B9A), Color(0xFF2A0A4A)],
          border: const Color(0xFFBA68C8),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => StatsScreen(store: store)),
          ),
        ),
      ],
    );
  }

  Widget _actionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Color> gradient,
    required Color border,
    required VoidCallback onTap,
    String? badge,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradient,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border.withValues(alpha: 0.55), width: 1),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, color: Colors.white.withValues(alpha: 0.9), size: 30),
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _red,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(badge,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold)),
                    Text(subtitle,
                        style: TextStyle(
                            color:
                                Colors.white.withValues(alpha: 0.75),
                            fontSize: 11)),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: border.withValues(alpha: 0.8), width: 1.5),
                  ),
                  child: Icon(Icons.chevron_right,
                      color: border, size: 18),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(
    BuildContext context, {
    Key? key,
    required IconData icon,
    required Color iconColor,
    required String title,
    String? badge,
    VoidCallback? onViewAll,
  }) {
    return Padding(
      key: key,
      padding: const EdgeInsets.fromLTRB(14, 4, 12, 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: iconColor),
          const SizedBox(width: 8),
          Text(title,
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.bold)),
          if (badge != null) ...[
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
              decoration: BoxDecoration(
                color: _red,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(badge,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
            ),
          ],
          const Spacer(),
          if (onViewAll != null)
            GestureDetector(
              onTap: onViewAll,
              child: const Row(
                children: [
                  Text('View All',
                      style: TextStyle(color: _cyan, fontSize: 13)),
                  Icon(Icons.chevron_right, color: _cyan, size: 18),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _tournamentCard(BuildContext context, Tournament t) {
    return Card(
      margin: EdgeInsets.zero,
      color: const Color(0xFF0B1220),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: _blue.withValues(alpha: 0.25), width: 1),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.asset('assets/app_icon_v4.png',
              width: 64, height: 64, fit: BoxFit.cover),
        ),
        title: Text(t.name,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.groups, size: 14, color: Colors.white54),
                const SizedBox(width: 4),
                Text('${t.teamIds.length} Teams',
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 12)),
              ],
            ),
            if (t.venue.isNotEmpty) ...[
              const SizedBox(height: 2),
              Row(
                children: [
                  const Icon(Icons.location_on,
                      size: 14, color: Colors.white54),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(t.venue,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12)),
                  ),
                ],
              ),
            ],
          ],
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.white54),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                TournamentDetailScreen(store: store, tournament: t),
          ),
        ),
      ),
    );
  }

  /// Live match card styled like the mockup: LIVE badge, tournament,
  /// innings label, team crests + score, VS divider.
  Widget _liveMatchCard(BuildContext context, Match m) {
    final inn = m.innings.isNotEmpty ? m.innings.last : null;
    final innNo = inn != null ? m.innings.indexOf(inn) + 1 : 0;
    final t = store.tournamentById(m.tournamentId);
    Widget crest(String teamId, Color c) {
      final name = store.teamName(teamId);
      final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [c, c.withValues(alpha: 0.45)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.25), width: 1),
            ),
            alignment: Alignment.center,
            child: Text(initial,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 84,
            child: Text(name,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      );
    }

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ScoringScreen(store: store, match: m)),
      ),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF3A0E0E), Color(0xFF12060A)],
          ),
          borderRadius: BorderRadius.circular(16),
          border:
              Border.all(color: _red.withValues(alpha: 0.4), width: 1),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _red,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('LIVE',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                ),
                Expanded(
                  child: Text(
                    t?.name ?? '',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 12),
                  ),
                ),
                Text(
                  inn != null ? '${_ordinal(innNo)} Innings' : '',
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                crest(m.teamAId, _red),
                Column(
                  children: [
                    Text(
                      inn != null
                          ? '${inn.totalRuns}/${inn.wickets}'
                          : 'vs',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.bold),
                    ),
                    if (inn != null)
                      Text(
                        '(${oversText(inn.legalBalls, inn.ballsPerOver)})',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12),
                      ),
                    const Text('VS',
                        style: TextStyle(
                            color: _red,
                            fontSize: 13,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
                crest(m.teamBId, _blue),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _ordinal(int n) {
    if (n == 1) return '1st';
    if (n == 2) return '2nd';
    if (n == 3) return '3rd';
    return '${n}th';
  }

  Widget _matchTile(BuildContext context, Match m) {
    final summary = m.innings.isEmpty
        ? 'Not started'
        : m.innings
            .map(
              (i) =>
                  '${store.teamName(i.battingTeamId)} ${i.totalRuns}/${i.wickets} (${oversText(i.legalBalls, i.ballsPerOver)})',
            )
            .join('  •  ');
    return Card(
      margin: EdgeInsets.zero,
      color: const Color(0xFF0B1220),
      child: ListTile(
        leading:
            const Icon(Icons.check_circle, color: Colors.white54),
        title: Text(
          '${store.teamName(m.teamAId)} vs ${store.teamName(m.teamBId)}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(m.resultText.isNotEmpty ? m.resultText : summary),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ScorecardScreen(store: store, match: m),
          ),
        ),
      ),
    );
  }

  Future<void> _createTournament(BuildContext context) async {
    final nameCtrl = TextEditingController();
    final selected = <String>{};
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('Create tournament'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Tournament name',
                  ),
                ),
                const SizedBox(height: 8),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Teams',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                for (final t in store.teams)
                  CheckboxListTile(
                    dense: true,
                    value: selected.contains(t.id),
                    title: Text(t.name),
                    onChanged: (v) => setD(() {
                      if (v == true) {
                        selected.add(t.id);
                      } else {
                        selected.remove(t.id);
                      }
                    }),
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
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    if (ok == true && nameCtrl.text.trim().isNotEmpty) {
      await store.upsertTournament(
        Tournament(
          id: Store.newId('tournament'),
          name: nameCtrl.text.trim(),
          teamIds: selected.toList(),
        ),
      );
    }
  }
}

class TournamentDetailScreen extends StatefulWidget {
  final Store store;
  final Tournament tournament;
  const TournamentDetailScreen({
    super.key,
    required this.store,
    required this.tournament,
  });

  @override
  State<TournamentDetailScreen> createState() => _TournamentDetailScreenState();
}

class _TournamentDetailScreenState extends State<TournamentDetailScreen> {
  Store get store => widget.store;
  Tournament get tournament => widget.tournament;

  /// Latest playoff recalculation outcome (idempotent engine pass).
  /// Fetched once on open and re-run whenever a fixture screen pops back.
  PlayoffUpdate? _playoffUpdate;

  @override
  void initState() {
    super.initState();
    _runPlayoffUpdate();
  }

  Future<void> _runPlayoffUpdate() async {
    final update = await applyPlayoffUpdate(store, tournament.id);
    if (mounted) setState(() => _playoffUpdate = update);
  }

  /// Team IDs currently shown with a Q badge. Final qualifiers when the
  /// league stage is locked, otherwise mathematically guaranteed
  /// provisional qualifiers.
  Set<String> get _qualifierIds {
    final finalQ = _playoffUpdate?.finalQualifiers ?? tournament.qualifiedTeamIds;
    if (tournament.qualificationFinalized && finalQ.isNotEmpty) {
      return finalQ.toSet();
    }
    return (_playoffUpdate?.provisionalQualifiers ?? const <String>[]).toSet();
  }

  bool get _qualificationFinal =>
      tournament.qualificationFinalized &&
      ((_playoffUpdate?.finalQualifiers ?? tournament.qualifiedTeamIds)
          .isNotEmpty);

  Future<void> _openFixture(Match m) async {
    late final Widget screen;
    switch (m.status) {
      case 'live':
        screen = ScoringScreen(store: store, match: m);
        break;
      case 'completed':
        screen = ScorecardScreen(store: store, match: m);
        break;
      default:
        // upcoming / noResult / cancelled -> detail screen (never the
        // scorecard; that was the red-screen routing bug).
        screen = FixtureDetailScreen(store: store, matchId: m.id);
    }
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
    if (!mounted) return;
    setState(() {});
    await _runPlayoffUpdate();
  }

  /// Branded fixture card used by both the league and playoff sections.
  Widget _fixtureCard(Match m, {String? stageOverride}) {
    final title = m.matchTitle.isNotEmpty
        ? m.matchTitle
        : (stageOverride ?? 'League Fixture');
    final subtitle = m.resultText.isNotEmpty
        ? m.resultText
        : '${formatFixtureDate(m.dateIso)}'
              '${m.venue.isNotEmpty ? ' · ${m.venue}' : ''}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ScoreCard(
        onTap: () => _openFixture(m),
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
            Row(
              children: [
                TeamAvatar(store.teamName(m.teamAId)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    store.teamName(m.teamAId),
                    style: const TextStyle(
                      color: kWhite,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
                const Text(
                  'vs',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
                Expanded(
                  child: Text(
                    store.teamName(m.teamBId),
                    textAlign: TextAlign.end,
                    style: const TextStyle(
                      color: kWhite,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                TeamAvatar(store.teamName(m.teamBId)),
              ],
            ),
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

  @override
  Widget build(BuildContext context) {
    final rows = leaguePointsTable(tournament, store.matches);
    final qualifierIds = _qualifierIds;
    final leagueFixtures = store.matches
        .where((m) => m.tournamentId == tournament.id && m.stage == 'league')
        .toList()
      ..sort((a, b) => a.dateIso.compareTo(b.dateIso));
    final playoffFixtures = playoffMatchesOf(tournament.id, store.matches);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(tournament.name),
          actions: [
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                await store.deleteTournament(tournament.id);
                if (context.mounted) Navigator.pop(context);
              },
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Points Table'),
              Tab(text: 'Fixtures'),
              Tab(text: 'Stats'),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  MatchSetupScreen(store: store, tournamentId: tournament.id),
            ),
          ).then((_) => setState(() {})),
          icon: const Icon(Icons.add),
          label: const Text('New fixture'),
        ),
        body: TabBarView(
          children: [
            // Points table (ICC NRR) with playoff qualification badges
            ListView(
              padding: const EdgeInsets.all(10),
              children: [
                if (qualifierIds.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8, left: 4),
                    child: Row(
                      children: [
                        _qualificationFinal
                            ? const QBadge()
                            : const QBadge(provisional: true),
                        const SizedBox(width: 8),
                        Text(
                          _qualificationFinal
                              ? 'Qualified for the playoffs'
                              : 'Q* = provisional qualification (mathematically guaranteed)',
                          style: const TextStyle(
                            color: kGold,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
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
                      DataColumn(label: Text('Adj')),
                    ],
                    rows: [
                      for (var i = 0; i < rows.length; i++)
                        DataRow(
                          color: qualifierIds.contains(rows[i].teamId)
                              ? WidgetStateProperty.all(
                                  kGold.withValues(alpha: 0.10),
                                )
                              : null,
                          cells: [
                            DataCell(Text('${i + 1}')),
                            DataCell(
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(store.teamName(rows[i].teamId)),
                                  if (qualifierIds
                                      .contains(rows[i].teamId)) ...[
                                    const SizedBox(width: 6),
                                    _qualificationFinal
                                        ? const QBadge()
                                        : const QBadge(provisional: true),
                                  ],
                                ],
                              ),
                            ),
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
                            DataCell(
                              Text(rows[i].nrr.toStringAsFixed(3)),
                            ),
                            DataCell(
                              IconButton(
                                icon: const Icon(Icons.edit, size: 18),
                                tooltip: 'Custom points adjustment',
                                onPressed: () =>
                                    _editAdjustment(context, rows[i].teamId),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'NRR uses the ICC rule: aggregate runs per over scored minus conceded across the tournament; a team bowled out is deemed to have faced its full overs quota.',
                    style: TextStyle(fontSize: 11, color: Colors.white38),
                  ),
                ),
              ],
            ),
            // Fixtures — league and playoffs, with status-based routing
            ListView(
              padding: const EdgeInsets.all(10),
              children: [
                const SectionHeader('League Fixtures'),
                if (leagueFixtures.isEmpty)
                  const EmptyState(
                    icon: Icons.event_note,
                    title: 'No league fixtures',
                    subtitle: 'Use the + button to add fixtures.',
                  ),
                for (final m in leagueFixtures) _fixtureCard(m),
                const SectionHeader('Playoffs'),
                if (playoffFixtures.isEmpty)
                  const EmptyState(
                    icon: Icons.emoji_events_outlined,
                    title: 'No playoff fixtures',
                    subtitle:
                        'Semifinals and the final appear here once added.',
                  ),
                for (final m in playoffFixtures)
                  _fixtureCard(m, stageOverride: stageLabel(m.stage)),
                const SizedBox(height: 70),
              ],
            ),
            // Tournament stats (Stumps-style leaderboards)
            TournamentStatsTab(store: store, tournament: tournament),
          ],
        ),
      ),
    );
  }

  Future<void> _editAdjustment(BuildContext context, String teamId) async {
    final ctrl = TextEditingController(
      text: '${tournament.pointsAdjustments[teamId] ?? 0}',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Custom points — ${store.teamName(teamId)}'),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(signed: true),
          decoration: const InputDecoration(
            labelText: 'Adjustment (added to earned points)',
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
    );
    if (ok == true) {
      final v = int.tryParse(ctrl.text) ?? 0;
      if (v == 0) {
        tournament.pointsAdjustments.remove(teamId);
      } else {
        tournament.pointsAdjustments[teamId] = v;
      }
      await store.persist();
      if (mounted) setState(() {});
    }
  }
}
