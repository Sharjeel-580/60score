// 60Score home dashboard — v1.1.2 redesign.
// Built only from real persisted store data — nothing hardcoded.
import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/player_avatar.dart';
import 'backup_screen.dart';
import 'draft_screen.dart';
import 'registration_screen.dart';
import 'scorer_home_screen.dart';
import 'scorecard_screen.dart';
import 'settings_screen.dart';
import 'teams_screen.dart';
import 'tournaments_screen.dart';

/// Short fixture date range, e.g. '2026-10-22T14:00:00' -> '22 Oct 2026'.
String _shortDate(String iso) {
  try {
    final d = iso.split('T').first.split('-');
    if (d.length != 3) return '';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final month = int.parse(d[1]);
    if (month < 1 || month > 12) return '';
    return '${d[2].trim().padLeft(2, '0')} ${months[month - 1]} ${d[0]}';
  } catch (_) {
    return '';
  }
}

class HomeScreen extends StatefulWidget {
  final Store store;
  final VoidCallback onOpenDrawer;
  final ValueChanged<int> onSelectTab;
  const HomeScreen({super.key, required this.store, required this.onOpenDrawer, required this.onSelectTab});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  Store get store => widget.store;

  void _openTournament(BuildContext context, Tournament t) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TournamentDetailScreen(store: store, tournament: t),
      ),
    );
  }

  void _push(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final defaultT = store.tournamentById(Store.defaultTournamentId);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Branded header
            BrandedHeader(
              onMenu: widget.onOpenDrawer,
              onSettings: () =>
                  _push(context, SettingsScreen(store: store)),
            ),
            const SizedBox(height: 12),
            // 2. Five action cards
            _actionRow(context, defaultT),
            const SizedBox(height: 12),
            // 3. Default tournament card
            _tournamentCard(context, defaultT),
            // 4. Quick actions grid
            SectionTitle(
              icon: Icons.flash_on,
              title: 'Quick Actions',
            ),
            _quickActionsGrid(context, defaultT),
            // 5. Recent matches
            SectionTitle(
              icon: Icons.history,
              title: 'Recent Matches',
              trailing: ViewAllLink(onTap: () => widget.onSelectTab(1)),
            ),
            _recentMatches(context),
          ],
        ),
      ),
    );
  }

  // ---------- 2. Five action cards (horizontal scroll row) ----------
  Widget _actionRow(BuildContext context, Tournament? defaultT) {
    void push(Widget page) => _push(context, page);
    const cardWidth = 132.0;
    final cards = <Widget>[
      _sizedActionCard(
        cardWidth,
        ActionCard(
          icon: Icons.sports_cricket,
          title: 'New Match',
          subtitle: 'Quick / Custom',
          gradient: const [Color(0xFFB26A00), kGold],
          onTap: () => widget.onSelectTab(2),
        ),
      ),
      _sizedActionCard(
        cardWidth,
        ActionCard(
          icon: Icons.emoji_events,
          title: 'Tournaments',
          subtitle: 'View & Manage',
          gradient: const [Color(0xFF0B5FA5), Color(0xFF19D7F2)],
          // Same Tournament Management screen as the sidebar's Tournaments
          // menu (v1.1.5): never a separate implementation.
          onTap: () => push(TournamentsScreen(store: store)),
        ),
      ),
      _sizedActionCard(
        cardWidth,
        ActionCard(
          icon: Icons.groups,
          title: 'Teams',
          subtitle: 'Add / Manage',
          gradient: const [Color(0xFF0B5FA5), Color(0xFF19D7F2)],
          onTap: () => push(TeamsScreen(store: store)),
        ),
      ),
      _sizedActionCard(
        cardWidth,
        ActionCard(
          icon: Icons.person,
          title: 'Registered Players',
          subtitle: 'View All Players',
          gradient: const [Color(0xFF0E7A3D), Color(0xFF3ECF6F)],
          onTap: () => push(RegistrationScreen(store: store)),
        ),
      ),
      _sizedActionCard(
        cardWidth,
        ActionCard(
          icon: Icons.edit_note,
          title: 'Drafting',
          subtitle: 'Create Playing XI',
          gradient: const [Color(0xFF6A1FB0), Color(0xFFB14BF2)],
          onTap: () => push(DraftListScreen(store: store)),
        ),
      ),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            cards[i],
          ],
        ],
      ),
    );
  }

  Widget _sizedActionCard(double width, Widget card) =>
      SizedBox(width: width, child: card);

  // ---------- 3. Default tournament card ----------
  Widget _tournamentCard(BuildContext context, Tournament? t) {
    if (t == null) {
      return const EmptyState(
        icon: Icons.emoji_events_outlined,
        title: 'No tournament yet',
        subtitle: 'The default tournament will appear here after setup.',
      );
    }
    final fixtures =
        store.matches.where((m) => m.tournamentId == t.id).toList();
    final dateRange = _fixtureDateRange(fixtures);
    final teamNames = t.teamIds.map(store.teamName).toList();
    return ScoreCard(
      highlight: true,
      onTap: () => _openTournament(context, t),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Gold 'DEFAULT TOURNAMENT' pill
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: kGold.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'DEFAULT TOURNAMENT',
              style: TextStyle(
                color: Color(0xFF2B1C05),
                fontWeight: FontWeight.w900,
                fontSize: 11,
                letterSpacing: 0.6,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            t.name,
            style: const TextStyle(
              color: kWhite,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 10),
          // venue + date range + team count
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (t.venue.isNotEmpty)
                _metaChip(Icons.location_on_outlined, t.venue),
              if (dateRange.isNotEmpty)
                _metaChip(Icons.calendar_month_outlined, dateRange),
              _metaChip(
                Icons.groups_outlined,
                '${t.teamIds.length} Teams',
              ),
            ],
          ),
          if (teamNames.isNotEmpty) ...[
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              child: Row(
                children: [
                  for (var i = 0; i < teamNames.length; i++) ...[
                    if (i > 0) const SizedBox(width: 10),
                    _teamChip(context, t, i),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _metaChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: kNavyDeep.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kTeal.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: kSilver, size: 14),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: kWhite, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  /// Date range label from real fixture dates, e.g. '22 Oct - 08 Nov 2026'.
  String _fixtureDateRange(List<Match> fixtures) {
    final dates =
        fixtures.map((m) => m.dateIso).where((d) => d.isNotEmpty).toList()
          ..sort();
    if (dates.isEmpty) return '';
    final first = dates.first;
    final last = dates.last;
    if (first.split('T').first == last.split('T').first) {
      return _shortDate(first);
    }
    return '${_shortDate(first)} - ${_shortDate(last)}';
  }

  Widget _teamChip(BuildContext context, Tournament t, int index) {
    final teamId = t.teamIds[index];
    final name = store.teamName(teamId);
    final team = store.teamById(teamId);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: team == null
            ? null
            : () => _push(
                  context,
                  TeamDetailScreen(store: store, team: team),
                ),
        child: Container(
          width: 76,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: kNavyDeep.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kCyan.withValues(alpha: 0.18)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CaptainAvatar(store: store, teamId: teamId, radius: 24),
              const SizedBox(height: 6),
              Text(
                name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: kWhite,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------- 4. Quick actions grid (2 rows x 4) ----------
  Widget _quickActionsGrid(BuildContext context, Tournament? defaultT) {
    void push(Widget page) => _push(context, page);
    final items = <_QuickNav>[
      _QuickNav(
        icon: Icons.group_add,
        title: 'New Team',
        subtitle: 'Create Team',
        gradient: const [Color(0xFF9B2C2C), Color(0xFFD05A5A)],
        onTap: () => push(TeamsScreen(store: store)),
      ),
      _QuickNav(
        icon: Icons.person_add,
        title: 'New Player',
        subtitle: 'Add Player',
        gradient: const [Color(0xFF0B5FA5), Color(0xFF19D7F2)],
        onTap: () => push(RegistrationScreen(store: store)),
      ),
      _QuickNav(
        icon: Icons.edit_note,
        title: 'Drafting',
        subtitle: 'Create Playing XI',
        gradient: const [Color(0xFF6A1FB0), Color(0xFFB14BF2)],
        onTap: () => push(DraftListScreen(store: store)),
      ),
      _QuickNav(
        icon: Icons.bar_chart,
        title: 'Points Table',
        subtitle: 'Live Standings',
        gradient: const [Color(0xFFB26A00), kGold],
        onTap: () {
          if (defaultT != null) {
            _openTournament(context, defaultT);
          } else {
            widget.onSelectTab(1);
          }
        },
      ),
      _QuickNav(
        icon: Icons.calendar_month,
        title: 'Fixtures',
        subtitle: 'Full Schedule',
        gradient: const [Color(0xFF0B5FA5), Color(0xFF3ECF6F)],
        onTap: () => widget.onSelectTab(1),
      ),
      _QuickNav(
        icon: Icons.description,
        title: 'Scorecards',
        subtitle: 'All Matches',
        gradient: const [Color(0xFFB26A00), Color(0xFFE8A13D)],
        onTap: () => widget.onSelectTab(1),
      ),
      _QuickNav(
        icon: Icons.pie_chart,
        title: 'Statistics',
        subtitle: 'Players & Teams',
        gradient: const [Color(0xFF0E7A3D), Color(0xFF19D7F2)],
        onTap: () => widget.onSelectTab(3),
      ),
      _QuickNav(
        icon: Icons.upload,
        title: 'Import / Export',
        subtitle: 'CSV & PDF',
        gradient: const [Color(0xFF0B5FA5), Color(0xFF19D7F2)],
        onTap: () => push(BackupScreen(store: store)),
      ),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.78,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final a = items[i];
        return ActionCard(
          icon: a.icon,
          title: a.title,
          subtitle: a.subtitle,
          gradient: a.gradient,
          onTap: a.onTap,
          iconSize: 26,
        );
      },
    );
  }

  // ---------- 5. Recent matches ----------
  Widget _recentMatches(BuildContext context) {
    final done = store.matches
        .where((m) => m.status == 'completed')
        .toList()
      ..sort((a, b) => b.dateIso.compareTo(a.dateIso));
    final show = done.take(3).toList();
    if (show.isEmpty) {
      return ScoreCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const EmptyState(
              icon: Icons.scoreboard_outlined,
              title: 'No matches yet',
              subtitle:
                  'Start a new match or open a tournament to view match history.',
            ),
            ScoreButton(
              label: 'New Match',
              icon: Icons.add_circle_outline,
              kind: ScoreButtonKind.ghost,
              onPressed: () => widget.onSelectTab(2),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < show.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _recentMatchCard(context, show[i]),
        ],
      ],
    );
  }

  Widget _recentMatchCard(BuildContext context, Match m) {
    final a = store.teamName(m.teamAId);
    final b = store.teamName(m.teamBId);
    return ScoreCard(
      padding: const EdgeInsets.all(12),
      onTap: () =>
          _push(context, ScorecardScreen(store: store, match: m)),
      child: Row(
        children: [
          CaptainAvatar(store: store, teamId: m.teamAId, radius: 18),
          const SizedBox(width: 4),
          CaptainAvatar(store: store, teamId: m.teamBId, radius: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$a vs $b',
                  style: const TextStyle(
                    color: kWhite,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                ..._scoreLines(m).map(
                  (line) => Padding(
                    padding: const EdgeInsets.only(bottom: 1),
                    child: Text(
                      line,
                      style: const TextStyle(
                          color: kSilver, fontSize: 12),
                    ),
                  ),
                ),
                if (m.resultText.isNotEmpty)
                  Text(
                    m.resultText,
                    style: const TextStyle(
                      color: kCyan,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
          const StatusPill('completed'),
        ],
      ),
    );
  }

  List<String> _scoreLines(Match m) {
    final lines = <String>[];
    for (final inn in m.innings) {
      final bat = store.teamName(inn.battingTeamId);
      final overs = inn.ballsPerOver > 0
          ? '${inn.legalBalls ~/ inn.ballsPerOver}.${inn.legalBalls % inn.ballsPerOver}'
          : '${inn.legalBalls}';
      lines.add('$bat ${inn.totalRuns}/${inn.wickets} ($overs ov)');
    }
    return lines.take(2).toList();
  }
}

class _QuickNav {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Color> gradient;
  final VoidCallback onTap;
  _QuickNav({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.gradient,
    required this.onTap,
  });
}
